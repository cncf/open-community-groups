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
    db::DynDB,
    services::notifications::DynNotificationsManager,
    types::{
        event::EventSummary,
        payments::{EventPurchaseStatus, EventPurchaseSummary},
    },
};

use super::{
    CreateCheckoutSessionInput, DynPaymentsProvider, RefundPaymentInput,
    notification_composer::PaymentsNotificationComposer, webhook_reconciler::PaymentsWebhookReconciler,
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
        community_id: Uuid,
        event: &EventSummary,
        purchase: &EventPurchaseSummary,
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
        let notification_composer =
            PaymentsNotificationComposer::new(db.clone(), notifications_manager, server_cfg.clone());

        Self {
            db,
            notification_composer,
            payments_provider,
            server_cfg,
        }
    }

    /// Approves a pending refund request and submits the provider refund.
    pub(crate) async fn approve_refund_request(&self, input: &ApproveRefundRequestInput) -> Result<()> {
        let payments_provider = self.payments_provider()?;

        // Mark the refund request as being processed and load the purchase
        let purchase = self
            .db
            .begin_event_refund_approval(input.group_id, input.event_id, input.user_id)
            .await?;

        // Validate the refund request is still pending
        if purchase.status != EventPurchaseStatus::RefundRequested {
            return Err(anyhow::anyhow!("refund request is not pending"));
        }

        // Extract the provider payment reference or roll back the approval state
        let provider_payment_reference = purchase
            .provider_payment_reference
            .clone()
            .ok_or_else(|| anyhow::anyhow!("provider payment reference is missing"));
        let provider_payment_reference = match provider_payment_reference {
            Ok(provider_payment_reference) => provider_payment_reference,
            Err(err) => {
                self.revert_refund_approval_state(input.group_id, input.event_id, input.user_id)
                    .await;
                return Err(err);
            }
        };

        // Submit the refund to the payments provider or roll back the approval state
        let refund = match payments_provider
            .refund_payment(&RefundPaymentInput {
                amount_minor: purchase.amount_minor,
                provider_payment_reference,
                purchase_id: purchase.event_purchase_id,
            })
            .await
        {
            Ok(refund) => refund,
            Err(err) => {
                self.revert_refund_approval_state(input.group_id, input.event_id, input.user_id)
                    .await;
                return Err(err);
            }
        };

        // Persist the refund approval in the database
        self.db
            .approve_event_refund_request(
                input.actor_user_id,
                input.group_id,
                input.event_id,
                input.user_id,
                refund.provider_refund_id,
                input.review_note.clone(),
            )
            .await?;

        // Notify the attendee about the approved refund
        self.notification_composer
            .enqueue_refund_approval_notification(input.community_id, input.event_id, input.user_id)
            .await;

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
        community_id: Uuid,
        event: &EventSummary,
        purchase: &EventPurchaseSummary,
        user_id: Uuid,
    ) -> Result<String> {
        if let Some(provider_checkout_url) = purchase.provider_checkout_url.clone() {
            return Ok(provider_checkout_url);
        }

        // Load the payment provider and recipient details required to open a fresh checkout session
        let payments_provider = self.payments_provider()?;
        let event_full = self
            .db
            .get_event_full_by_slug(community_id, &event.group_slug, &event.slug)
            .await?;
        let group = self
            .db
            .get_group_full(community_id, event_full.group.group_id)
            .await?;
        let recipient = group
            .payment_recipient
            .clone()
            .ok_or_else(|| anyhow::anyhow!("group payments recipient is not configured"))?;

        if recipient.provider != payments_provider.provider() {
            bail!("group payments recipient is not configured for this provider");
        }

        // Create the provider checkout session
        let checkout_session = payments_provider
            .create_checkout_session(&CreateCheckoutSessionInput {
                amount_minor: purchase.amount_minor,
                base_url: self.server_cfg.base_url.clone(),
                community_name: event.community_name.clone(),
                currency_code: purchase.currency_code.clone(),
                event_id: event.event_id,
                event_slug: event.slug.clone(),
                group_slug: event.group_slug.clone(),
                purchase_id: purchase.event_purchase_id,
                recipient,
                ticket_title: purchase.ticket_title.clone(),
                user_id,

                discount_code: purchase.discount_code.clone(),
            })
            .await?;

        // Persist the canonical checkout session used for webhook reconciliation
        self.db
            .attach_checkout_session_to_event_purchase(
                purchase.event_purchase_id,
                payments_provider.provider(),
                &checkout_session,
            )
            .await?;

        // Reload the purchase so concurrent requests return the canonical
        // checkout URL stored on the purchase
        let purchase = self.db.get_event_purchase_summary(purchase.event_purchase_id).await?;

        purchase
            .provider_checkout_url
            .ok_or_else(|| anyhow::anyhow!("provider checkout URL is missing after checkout creation"))
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
        let webhook_event = payments_provider
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
    pub(crate) async fn reject_refund_request(&self, input: &RejectRefundRequestInput) -> Result<()> {
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
            .enqueue_refund_rejection_notification(input.community_id, input.event_id, input.user_id)
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

    /// Reverts the temporary refund approval state after a failed provider call.
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
    fn webhook_reconciler(&self, payments_provider: DynPaymentsProvider) -> PaymentsWebhookReconciler {
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
        PgPaymentsManager::complete_free_checkout(self, community_id, event_id, event_purchase_id, user_id)
            .await
    }

    /// [`PaymentsManager::get_or_create_checkout_redirect_url`].
    async fn get_or_create_checkout_redirect_url(
        &self,
        community_id: Uuid,
        event: &EventSummary,
        purchase: &EventPurchaseSummary,
        user_id: Uuid,
    ) -> Result<String> {
        PgPaymentsManager::get_or_create_checkout_redirect_url(self, community_id, event, purchase, user_id)
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
