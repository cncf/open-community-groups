//! Payments service management across providers and local services.

use std::sync::Arc;

use anyhow::{Result, bail};
use async_trait::async_trait;
use axum::http::HeaderMap;
#[cfg(test)]
use mockall::automock;
use tracing::warn;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::{
        DynDB,
        payments::{EventPurchaseRefund, EventPurchaseRefundKind, EventPurchaseRefundStatus},
    },
    services::notifications::DynNotificationsManager,
    types::payments::{EventPurchaseSummary, PreparedEventCheckout},
};

use super::{
    CreateCheckoutSessionInput, DynPaymentsProvider, FindRefundInput, RefundPaymentInput,
    RefundPaymentResult, RefundPaymentStatus, notification_composer::PaymentsNotificationComposer,
    webhook_reconciler::PaymentsWebhookReconciler,
};

#[cfg(test)]
mod tests;

/// Trait implemented by the payments manager used by handlers.
#[async_trait]
#[cfg_attr(test, automock)]
pub(crate) trait PaymentsManager {
    /// Approves a pending refund request and submits the provider refund.
    async fn approve_refund_request(&self, input: &ApproveRefundRequestInput) -> Result<()>;

    /// Completes a free checkout and enqueues the attendee welcome notification.
    async fn complete_free_checkout(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        event_purchase_id: Uuid,
        user_id: Uuid,
    ) -> Result<()>;

    /// Creates or reuses the provider checkout URL for a pending event purchase.
    async fn get_or_create_checkout_redirect_url(
        &self,
        prepared_checkout: &PreparedEventCheckout,
        user_id: Uuid,
    ) -> Result<String>;

    /// Verifies and processes a webhook payload.
    async fn handle_webhook(
        &self,
        headers: &HeaderMap,
        body: &str,
    ) -> std::result::Result<(), HandleWebhookError>;

    /// Rejects a pending refund request and notifies the attendee.
    async fn reject_refund_request(&self, input: &RejectRefundRequestInput) -> Result<()>;

    /// Records an attendee refund request with notification payload data.
    async fn request_refund(&self, input: &RequestRefundInput) -> Result<()>;
}

/// Shared payments manager trait object.
pub(crate) type DynPaymentsManager = Arc<dyn PaymentsManager + Send + Sync>;

/// PostgreSQL-backed payments manager implementation.
#[derive(Clone)]
pub(crate) struct PgPaymentsManager {
    /// Database handle for payment-related persistence.
    db: DynDB,
    /// Shared notification helper used by payments flows.
    notification_composer: PaymentsNotificationComposer,
    /// Provider adapter used for payment operations.
    payments_provider: Option<DynPaymentsProvider>,
    /// Server configuration used to build links and attachments.
    server_cfg: HttpServerConfig,
}

impl PgPaymentsManager {
    /// Creates a new `PgPaymentsManager`.
    pub(crate) fn new(
        db: DynDB,
        notifications_manager: DynNotificationsManager,
        payments_provider: Option<DynPaymentsProvider>,
        server_cfg: HttpServerConfig,
    ) -> Self {
        // Build the shared notification helper once for reuse across payments flows
        let notification_composer = PaymentsNotificationComposer::new(
            db.clone(),
            notifications_manager,
            server_cfg.clone(),
        );

        Self {
            db,
            notification_composer,
            payments_provider,
            server_cfg,
        }
    }

    /// Approves a pending refund request and submits the provider refund.
    pub(crate) async fn approve_refund_request(
        &self,
        input: &ApproveRefundRequestInput,
    ) -> Result<()> {
        // Load the configured provider before changing refund request state
        let payments_provider = self.payments_provider()?;

        // Mark the refund request as being processed and load the purchase
        let purchase = self
            .db
            .begin_event_refund_approval(input.group_id, input.event_id, input.user_id)
            .await?;

        // Extract the provider payment reference or roll back the approval state
        let provider_payment_reference = self
            .revert_refund_approval_on_error(
                input.group_id,
                input.event_id,
                input.user_id,
                purchase
                    .provider_payment_reference
                    .clone()
                    .ok_or_else(|| anyhow::anyhow!("provider payment reference is missing")),
            )
            .await?;

        // Start the durable refund handoff before the provider call
        let refund = self
            .revert_refund_approval_on_error(
                input.group_id,
                input.event_id,
                input.user_id,
                self.db
                    .ensure_event_purchase_refund_started(
                        purchase.event_purchase_id,
                        payments_provider.provider(),
                        EventPurchaseRefundKind::RefundRequestApproval,
                    )
                    .await,
            )
            .await?;

        // Reconcile or create the provider refund from the durable handoff
        let refund = self
            .resolve_refund_request_provider_refund(
                payments_provider,
                &purchase,
                provider_payment_reference,
                refund,
            )
            .await
            .map_err(|err| {
                warn!(error = %err, "failed to resolve refund request provider refund");
                err
            })?;

        // Require the provider identifier before local finalization
        let provider_refund_id = refund
            .provider_refund_id
            .ok_or_else(|| anyhow::anyhow!("provider refund id is missing after refund"))?;

        // Persist the refund approval in the database
        let completed_refund = self
            .db
            .approve_event_refund_request(
                input.actor_user_id,
                input.group_id,
                input.event_id,
                input.user_id,
                provider_refund_id,
                input.review_note.clone(),
            )
            .await?;

        // Notify the attendee about the approved refund
        if completed_refund.finalized_now {
            debug_assert_eq!(completed_refund.community_id, input.community_id);
            self.notification_composer
                .enqueue_refund_approval_notification(
                    completed_refund.community_id,
                    completed_refund.event_id,
                    completed_refund.user_id,
                )
                .await;
        }

        Ok(())
    }

    /// Completes a free checkout and enqueues the attendee welcome notification.
    pub(crate) async fn complete_free_checkout(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        event_purchase_id: Uuid,
        user_id: Uuid,
    ) -> Result<()> {
        // Finalize the free purchase before notifying the attendee
        self.db.complete_free_event_purchase(event_purchase_id).await?;
        self.notification_composer
            .enqueue_event_welcome_notification(community_id, event_id, user_id)
            .await;

        Ok(())
    }

    /// Creates or reuses the provider checkout URL for a pending event purchase.
    pub(crate) async fn get_or_create_checkout_redirect_url(
        &self,
        prepared_checkout: &PreparedEventCheckout,
        user_id: Uuid,
    ) -> Result<String> {
        if let Some(provider_checkout_url) =
            prepared_checkout.purchase.provider_checkout_url.clone()
        {
            return Ok(provider_checkout_url);
        }

        // Load the payment provider required to open a fresh checkout session
        let payments_provider = self.payments_provider()?;

        if prepared_checkout.recipient.provider != payments_provider.provider() {
            bail!("group payments recipient is not configured for this provider");
        }

        // Create the provider checkout session
        let checkout_session = payments_provider
            .create_checkout_session(&CreateCheckoutSessionInput {
                amount_minor: prepared_checkout.purchase.amount_minor,
                base_url: self.server_cfg.base_url.clone(),
                community_name: prepared_checkout.community_name.clone(),
                currency_code: prepared_checkout.purchase.currency_code.clone(),
                event_id: prepared_checkout.event_id,
                event_slug: prepared_checkout.event_slug.clone(),
                group_slug: prepared_checkout.group_slug.clone(),
                purchase_id: prepared_checkout.purchase.event_purchase_id,
                recipient: prepared_checkout.recipient.clone(),
                ticket_title: prepared_checkout.purchase.ticket_title.clone(),
                user_id,

                discount_code: prepared_checkout.purchase.discount_code.clone(),
                group_slug_pretty: prepared_checkout.group_slug_pretty.clone(),
            })
            .await?;

        // Persist the canonical checkout session used for webhook reconciliation
        self.db
            .attach_checkout_session_to_event_purchase(
                prepared_checkout.purchase.event_purchase_id,
                payments_provider.provider(),
                &checkout_session,
            )
            .await?;

        // Reload the purchase so concurrent requests return the canonical
        // checkout URL stored on the purchase
        let purchase = self
            .db
            .get_event_purchase_summary(prepared_checkout.purchase.event_purchase_id)
            .await?;

        purchase.provider_checkout_url.ok_or_else(|| {
            anyhow::anyhow!("provider checkout URL is missing after checkout creation")
        })
    }

    /// Verifies and processes a webhook payload.
    pub(crate) async fn handle_webhook(
        &self,
        headers: &HeaderMap,
        body: &str,
    ) -> std::result::Result<(), HandleWebhookError> {
        let payments_provider = self
            .payments_provider
            .as_ref()
            .ok_or(HandleWebhookError::PaymentsNotConfigured)?;

        // Verify the webhook payload before dispatching the normalized event
        let webhook_event =
            payments_provider
                .verify_and_parse_webhook(headers, body)
                .map_err(|err| {
                    warn!(error = %err, "failed to verify payments webhook");
                    HandleWebhookError::InvalidPayload
                })?;

        // Reconcile the verified webhook through the focused webhook helper
        self.webhook_reconciler(payments_provider.clone())
            .handle_webhook_event(webhook_event)
            .await
            .map_err(HandleWebhookError::Unexpected)
    }

    /// Rejects a pending refund request and notifies the attendee.
    pub(crate) async fn reject_refund_request(
        &self,
        input: &RejectRefundRequestInput,
    ) -> Result<()> {
        // Persist the refund rejection in the database
        self.db
            .reject_event_refund_request(
                input.actor_user_id,
                input.group_id,
                input.event_id,
                input.user_id,
                input.review_note.clone(),
            )
            .await?;

        // Notify the attendee about the rejected refund
        self.notification_composer
            .enqueue_refund_rejection_notification(
                input.community_id,
                input.event_id,
                input.user_id,
            )
            .await;

        Ok(())
    }

    /// Records an attendee refund request with notification payload data.
    pub(crate) async fn request_refund(&self, input: &RequestRefundInput) -> Result<()> {
        // Build the organizer notification payload before recording the refund request
        let template_data = self
            .notification_composer
            .build_refund_request_template_data(input.community_id, input.event_id)
            .await?;

        // Record the attendee's refund request with the notification payload
        self.db
            .request_event_refund(
                input.community_id,
                input.event_id,
                input.user_id,
                input.requested_reason.clone(),
                template_data,
            )
            .await
    }

    /// Returns the configured payments provider when paid operations are available.
    fn payments_provider(&self) -> Result<&DynPaymentsProvider> {
        self.payments_provider
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("payments are not configured"))
    }

    /// Records a provider refund failure without hiding the original error.
    async fn record_provider_refund_failure(
        &self,
        refund: &EventPurchaseRefund,
        err: &anyhow::Error,
    ) {
        if let Err(record_err) = self
            .db
            .record_event_purchase_refund_failed(refund.event_purchase_refund_id, err.to_string())
            .await
        {
            warn!(error = %record_err, "failed to record provider refund failure");
        }
    }

    /// Records a provider refund result and only returns success when final.
    async fn record_provider_refund_result(
        &self,
        refund: &EventPurchaseRefund,
        provider_refund: RefundPaymentResult,
    ) -> Result<EventPurchaseRefund> {
        // Persist the provider lifecycle outcome
        match provider_refund.status {
            RefundPaymentStatus::Succeeded => {
                self.db
                    .record_event_purchase_refund_succeeded(
                        refund.event_purchase_refund_id,
                        provider_refund.provider_refund_id,
                    )
                    .await
            }
            RefundPaymentStatus::Pending => {
                let refund = self
                    .db
                    .record_event_purchase_refund_pending(
                        refund.event_purchase_refund_id,
                        refund.idempotency_key.clone(),
                        provider_refund.provider_refund_id,
                    )
                    .await?;
                if matches!(
                    refund.status,
                    EventPurchaseRefundStatus::Finalized
                        | EventPurchaseRefundStatus::ProviderSucceeded
                ) {
                    return Ok(refund);
                }

                Err(anyhow::anyhow!("provider refund is not complete yet"))
            }
            RefundPaymentStatus::Failed => {
                self.db
                    .record_event_purchase_refund_terminal_failed(
                        refund.event_purchase_refund_id,
                        refund.idempotency_key.clone(),
                        provider_refund.provider_refund_id,
                        "provider refund failed".to_string(),
                    )
                    .await?;
                Err(anyhow::anyhow!("provider refund failed"))
            }
        }
    }

    /// Records or reuses the provider refund for an approved refund request.
    async fn resolve_refund_request_provider_refund(
        &self,
        payments_provider: &DynPaymentsProvider,
        purchase: &EventPurchaseSummary,
        provider_payment_reference: String,
        refund: EventPurchaseRefund,
    ) -> Result<EventPurchaseRefund> {
        // Return provider-complete refunds without another external request
        if matches!(
            refund.status,
            EventPurchaseRefundStatus::Finalized | EventPurchaseRefundStatus::ProviderSucceeded
        ) {
            return Ok(refund);
        }

        // Reconcile provider state before risking another refund request
        let provider_refund_id = refund.provider_refund_id.clone();
        match payments_provider
            .find_refund(&FindRefundInput {
                amount_minor: purchase.amount_minor,
                provider_payment_reference: provider_payment_reference.clone(),
                purchase_id: purchase.event_purchase_id,

                provider_refund_id: provider_refund_id.clone(),
            })
            .await
        {
            Ok(Some(provider_refund)) => {
                return self.record_provider_refund_result(&refund, provider_refund).await;
            }
            Ok(None) if provider_refund_id.is_some() => {
                return Err(anyhow::anyhow!("provider refund not found"));
            }
            Ok(None) => {}
            Err(err) => {
                warn!(error = %err, "failed to find existing provider refund");
                return Err(err);
            }
        }

        // Submit a fresh provider refund with the durable idempotency key
        let provider_refund = payments_provider
            .refund_payment(&RefundPaymentInput {
                amount_minor: purchase.amount_minor,
                idempotency_key: refund.idempotency_key.clone(),
                provider_payment_reference,
                purchase_id: purchase.event_purchase_id,
            })
            .await;

        // Persist the provider outcome while preserving the original failure
        match provider_refund {
            Ok(provider_refund) => {
                self.record_provider_refund_result(&refund, provider_refund).await
            }
            Err(err) => {
                self.record_provider_refund_failure(&refund, &err).await;
                Err(err)
            }
        }
    }

    /// Runs a pre-handoff refund approval step and restores the pending state if it fails.
    async fn revert_refund_approval_on_error<T>(
        &self,
        group_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
        result: Result<T>,
    ) -> Result<T> {
        match result {
            Ok(value) => Ok(value),
            Err(err) => {
                self.revert_refund_approval_state(group_id, event_id, user_id).await;
                Err(err)
            }
        }
    }

    /// Reverts the temporary refund approval state before a durable refund starts.
    async fn revert_refund_approval_state(&self, group_id: Uuid, event_id: Uuid, user_id: Uuid) {
        if let Err(revert_err) = self
            .db
            .revert_event_refund_approval(group_id, event_id, user_id)
            .await
        {
            warn!(error = %revert_err, "failed to revert refund approval state");
        }
    }

    /// Builds the webhook reconciler for the configured payments provider.
    fn webhook_reconciler(
        &self,
        payments_provider: DynPaymentsProvider,
    ) -> PaymentsWebhookReconciler {
        PaymentsWebhookReconciler::new(
            self.db.clone(),
            self.notification_composer.clone(),
            payments_provider,
        )
    }
}

#[async_trait]
impl PaymentsManager for PgPaymentsManager {
    /// [`PaymentsManager::approve_refund_request`].
    async fn approve_refund_request(&self, input: &ApproveRefundRequestInput) -> Result<()> {
        PgPaymentsManager::approve_refund_request(self, input).await
    }

    /// [`PaymentsManager::complete_free_checkout`].
    async fn complete_free_checkout(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        event_purchase_id: Uuid,
        user_id: Uuid,
    ) -> Result<()> {
        PgPaymentsManager::complete_free_checkout(
            self,
            community_id,
            event_id,
            event_purchase_id,
            user_id,
        )
        .await
    }

    /// [`PaymentsManager::get_or_create_checkout_redirect_url`].
    async fn get_or_create_checkout_redirect_url(
        &self,
        prepared_checkout: &PreparedEventCheckout,
        user_id: Uuid,
    ) -> Result<String> {
        PgPaymentsManager::get_or_create_checkout_redirect_url(self, prepared_checkout, user_id)
            .await
    }

    /// [`PaymentsManager::handle_webhook`].
    async fn handle_webhook(
        &self,
        headers: &HeaderMap,
        body: &str,
    ) -> std::result::Result<(), HandleWebhookError> {
        PgPaymentsManager::handle_webhook(self, headers, body).await
    }

    /// [`PaymentsManager::reject_refund_request`].
    async fn reject_refund_request(&self, input: &RejectRefundRequestInput) -> Result<()> {
        PgPaymentsManager::reject_refund_request(self, input).await
    }

    /// [`PaymentsManager::request_refund`].
    async fn request_refund(&self, input: &RequestRefundInput) -> Result<()> {
        PgPaymentsManager::request_refund(self, input).await
    }
}

/// Parameters used to approve a pending refund request.
#[derive(Clone, Debug)]
pub(crate) struct ApproveRefundRequestInput {
    /// User approving the refund request.
    pub actor_user_id: Uuid,
    /// Community containing the event.
    pub community_id: Uuid,
    /// Event containing the purchase.
    pub event_id: Uuid,
    /// Group containing the event.
    pub group_id: Uuid,
    /// Attendee receiving the refund.
    pub user_id: Uuid,

    /// Optional review note stored with the approval.
    pub review_note: Option<String>,
}

/// Errors returned while verifying or processing a webhook.
#[derive(Debug)]
pub(crate) enum HandleWebhookError {
    /// The webhook payload or signature is invalid.
    InvalidPayload,
    /// Payments are not configured for the current deployment.
    PaymentsNotConfigured,
    /// An unexpected error occurred while handling the webhook.
    Unexpected(anyhow::Error),
}

/// Parameters used to request an attendee refund.
#[derive(Clone, Debug)]
pub(crate) struct RequestRefundInput {
    /// Community containing the event.
    pub community_id: Uuid,
    /// Event for the refund request.
    pub event_id: Uuid,
    /// Attendee requesting the refund.
    pub user_id: Uuid,

    /// Optional reason provided by the attendee.
    pub requested_reason: Option<String>,
}

/// Parameters used to reject a pending refund request.
#[derive(Clone, Debug)]
pub(crate) struct RejectRefundRequestInput {
    /// User rejecting the refund request.
    pub actor_user_id: Uuid,
    /// Community containing the event.
    pub community_id: Uuid,
    /// Event containing the purchase.
    pub event_id: Uuid,
    /// Group containing the event.
    pub group_id: Uuid,
    /// Attendee whose refund was rejected.
    pub user_id: Uuid,

    /// Optional review note stored with the rejection.
    pub review_note: Option<String>,
}
