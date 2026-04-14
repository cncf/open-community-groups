//! Payments service management across providers and local services.

use std::sync::Arc;

use anyhow::{Result, bail};
use async_trait::async_trait;
#[cfg(test)]
use mockall::automock;
use tracing::warn;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::{
        DynDB,
        payments::{CompletedEventPurchase, ReconcileEventPurchaseResult, RefundRequiredEventPurchase},
    },
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::notifications::{
        EventRefundApproved, EventRefundRejected, EventRefundRequested, EventWelcome,
    },
    types::{
        event::EventSummary,
        payments::{EventPurchaseStatus, EventPurchaseSummary},
    },
    util::{build_event_calendar_attachment, build_event_page_link},
};

use super::{CreateCheckoutSessionInput, DynPaymentsProvider, PaymentsWebhookEvent, RefundPaymentInput};

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
        signature_header: &str,
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
    /// Notifications manager used for attendee notifications.
    notifications_manager: DynNotificationsManager,
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
        Self {
            db,
            notifications_manager,
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
        self.enqueue_refund_approval_notification(input.community_id, input.event_id, input.user_id)
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
        self.db.complete_free_event_purchase(event_purchase_id).await?;
        self.enqueue_event_welcome_notification(community_id, event_id, user_id)
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

        // Create the provider checkout session and store it on the pending purchase
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
        let redirect_url = checkout_session.redirect_url.clone();

        self.db
            .attach_checkout_session_to_event_purchase(
                purchase.event_purchase_id,
                payments_provider.provider(),
                &checkout_session,
            )
            .await?;

        Ok(redirect_url)
    }

    /// Verifies and processes a webhook payload.
    pub(crate) async fn handle_webhook(
        &self,
        signature_header: &str,
        body: &str,
    ) -> std::result::Result<(), HandleWebhookError> {
        let payments_provider = self
            .payments_provider
            .as_ref()
            .ok_or(HandleWebhookError::PaymentsNotConfigured)?;

        // Verify the webhook payload before dispatching the normalized event
        let webhook_event = payments_provider
            .verify_and_parse_webhook(signature_header, body)
            .map_err(|err| {
                warn!(error = %err, "failed to verify payments webhook");
                HandleWebhookError::InvalidPayload
            })?;

        self.handle_webhook_event(webhook_event)
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
        self.enqueue_refund_rejection_notification(input.community_id, input.event_id, input.user_id)
            .await;

        Ok(())
    }

    /// Records an attendee refund request with notification payload data.
    pub(crate) async fn request_refund(&self, input: &RequestRefundInput) -> Result<()> {
        // Load the data required to build the refund request notification
        let (event, site_settings) = tokio::try_join!(
            self.db.get_event_summary_by_id(input.community_id, input.event_id),
            self.db.get_site_settings(),
        )?;

        // Build the organizer link and notification payload for the refund request
        let base_url = self
            .server_cfg
            .base_url
            .strip_suffix('/')
            .unwrap_or(&self.server_cfg.base_url);
        let link = format!("{base_url}/dashboard/group/events/{}/attendees", input.event_id);
        let template_data = serde_json::to_value(&EventRefundRequested {
            event,
            link,
            theme: site_settings.theme,
        })?;

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

    /// Enqueues the attendee welcome notification for a completed paid checkout.
    async fn enqueue_checkout_completed_notification(&self, completed_purchase: CompletedEventPurchase) {
        self.enqueue_event_welcome_notification(
            completed_purchase.community_id,
            completed_purchase.event_id,
            completed_purchase.user_id,
        )
        .await;
    }

    /// Enqueues the attendee welcome notification after a successful ticket purchase.
    async fn enqueue_event_welcome_notification(&self, community_id: Uuid, event_id: Uuid, user_id: Uuid) {
        // Load the data required to build the welcome notification
        let (site_settings, event) = match tokio::try_join!(
            self.db.get_site_settings(),
            self.db.get_event_summary_by_id(community_id, event_id),
        ) {
            Ok(context) => context,
            Err(err) => {
                warn!(error = %err, "failed to load event welcome notification context");
                return;
            }
        };

        // Build the notification payload for the completed checkout
        let base_url = self
            .server_cfg
            .base_url
            .strip_suffix('/')
            .unwrap_or(&self.server_cfg.base_url);
        let link = build_event_page_link(base_url, &event);
        let template_data = EventWelcome {
            event: event.clone(),
            link: link.clone(),
            theme: site_settings.theme,
        };
        let notification = NewNotification {
            attachments: vec![build_event_calendar_attachment(base_url, &event)],
            kind: NotificationKind::EventWelcome,
            recipients: vec![user_id],
            template_data: serde_json::to_value(&template_data).ok(),
        };

        // Enqueue the welcome notification on a best-effort basis
        if let Err(err) = self.notifications_manager.enqueue(&notification).await {
            warn!(error = %err, "failed to enqueue event welcome notification");
        }
    }

    /// Enqueues the attendee notification for an approved refund request.
    async fn enqueue_refund_approval_notification(&self, community_id: Uuid, event_id: Uuid, user_id: Uuid) {
        // Load the data required to build the refund notification
        let (site_settings, event) = match tokio::try_join!(
            self.db.get_site_settings(),
            self.db.get_event_summary_by_id(community_id, event_id),
        ) {
            Ok(context) => context,
            Err(err) => {
                warn!(error = %err, "failed to load refund approval notification context");
                return;
            }
        };

        // Build the notification payload for the approved refund
        let base_url = self
            .server_cfg
            .base_url
            .strip_suffix('/')
            .unwrap_or(&self.server_cfg.base_url);
        let link = build_event_page_link(base_url, &event);
        let template_data = EventRefundApproved {
            event,
            link,
            theme: site_settings.theme,
        };
        let notification = NewNotification {
            attachments: vec![],
            kind: NotificationKind::EventRefundApproved,
            recipients: vec![user_id],
            template_data: serde_json::to_value(&template_data).ok(),
        };

        // Enqueue the refund notification on a best-effort basis
        if let Err(err) = self.notifications_manager.enqueue(&notification).await {
            warn!(error = %err, "failed to enqueue refund approval notification");
        }
    }

    /// Enqueues the attendee notification for a rejected refund request.
    async fn enqueue_refund_rejection_notification(&self, community_id: Uuid, event_id: Uuid, user_id: Uuid) {
        // Load the data required to build the refund notification
        let (site_settings, event) = match tokio::try_join!(
            self.db.get_site_settings(),
            self.db.get_event_summary_by_id(community_id, event_id),
        ) {
            Ok(context) => context,
            Err(err) => {
                warn!(error = %err, "failed to load refund rejection notification context");
                return;
            }
        };

        // Build the notification payload for the rejected refund
        let base_url = self
            .server_cfg
            .base_url
            .strip_suffix('/')
            .unwrap_or(&self.server_cfg.base_url);
        let link = build_event_page_link(base_url, &event);
        let template_data = EventRefundRejected {
            event,
            link,
            theme: site_settings.theme,
        };
        let notification = NewNotification {
            attachments: vec![],
            kind: NotificationKind::EventRefundRejected,
            recipients: vec![user_id],
            template_data: serde_json::to_value(&template_data).ok(),
        };

        // Enqueue the refund notification on a best-effort basis
        if let Err(err) = self.notifications_manager.enqueue(&notification).await {
            warn!(error = %err, "failed to enqueue refund rejection notification");
        }
    }

    /// Expires a checkout session after the provider reports it as expired.
    async fn expire_checkout_session(&self, provider_session_id: &str) -> Result<()> {
        let payments_provider = self.payments_provider()?;

        self.db
            .expire_event_purchase_for_checkout_session(payments_provider.provider(), provider_session_id)
            .await
            .map_err(|err| {
                warn!(error = %err, "failed to expire checkout session");
                err
            })
    }

    /// Completes or refunds a checkout session after webhook verification.
    async fn handle_completed_checkout(
        &self,
        provider_payment_reference: Option<String>,
        provider_session_id: &str,
    ) -> Result<()> {
        let payments_provider = self.payments_provider()?;

        // Reconcile the checkout session with the local purchase state
        match self
            .db
            .reconcile_event_purchase_for_checkout_session(
                payments_provider.provider(),
                provider_session_id,
                provider_payment_reference,
            )
            .await
        {
            Ok(ReconcileEventPurchaseResult::Completed(completed_purchase)) => {
                self.enqueue_checkout_completed_notification(completed_purchase).await;
                Ok(())
            }
            Ok(ReconcileEventPurchaseResult::Noop) => Ok(()),
            Ok(ReconcileEventPurchaseResult::RefundRequired(refund_purchase)) => {
                self.refund_unfulfillable_checkout(refund_purchase).await
            }
            Err(err) => {
                warn!(error = %err, "failed to reconcile purchase");
                Err(err)
            }
        }
    }

    /// Handles a verified payments webhook event.
    async fn handle_webhook_event(&self, webhook_event: PaymentsWebhookEvent) -> Result<()> {
        match webhook_event {
            PaymentsWebhookEvent::CheckoutCompleted {
                provider_payment_reference,
                provider_session_id,
            } => {
                self.handle_completed_checkout(provider_payment_reference, &provider_session_id)
                    .await
            }
            PaymentsWebhookEvent::CheckoutExpired { provider_session_id } => {
                self.expire_checkout_session(&provider_session_id).await
            }
        }
    }

    /// Returns the configured payments provider when paid operations are available.
    fn payments_provider(&self) -> Result<&DynPaymentsProvider> {
        self.payments_provider
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("payments are not configured"))
    }

    /// Refunds a checkout that can no longer be fulfilled locally.
    async fn refund_unfulfillable_checkout(
        &self,
        refund_purchase: RefundRequiredEventPurchase,
    ) -> Result<()> {
        let payments_provider = self.payments_provider()?;

        // Request a refund from the payment provider
        let refund = payments_provider
            .refund_payment(&RefundPaymentInput {
                amount_minor: refund_purchase.amount_minor,
                provider_payment_reference: refund_purchase.provider_payment_reference,
                purchase_id: refund_purchase.event_purchase_id,
            })
            .await
            .map_err(|err| {
                warn!(error = %err, "failed to refund unfulfillable purchase");
                err
            })?;

        // Persist the automatic refund after the provider call succeeds
        self.db
            .record_automatic_refund_for_event_purchase(
                refund_purchase.event_purchase_id,
                refund.provider_refund_id,
            )
            .await
            .map_err(|err| {
                warn!(error = %err, "failed to persist automatic refund");
                err
            })
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
        signature_header: &str,
        body: &str,
    ) -> std::result::Result<(), HandleWebhookError> {
        PgPaymentsManager::handle_webhook(self, signature_header, body).await
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
