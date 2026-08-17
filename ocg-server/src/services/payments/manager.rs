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
    db::{DynDB, payments::CompleteEventPurchaseRefundRecoveryInput},
    services::notifications::DynNotificationsManager,
    types::payments::{
        GroupPaymentRecipient, PaymentProvider, PreparedEventCheckout, TicketTaxBehavior,
        TicketTaxCalculationMode, TicketTaxRate,
    },
};

use super::{
    CreateCheckoutSessionInput, DynPaymentsProvider, FinancialDocumentKind,
    FiscalSponsorReadinessError, FiscalSponsorReadinessInput, GetFinancialDocumentInput,
    ListTaxRatesInput, ValidateTaxRatesInput, notification_composer::PaymentsNotificationComposer,
    provider::PaymentsWebhookEndpoint, webhook_reconciler::PaymentsWebhookReconciler,
};

#[cfg(test)]
mod tests;

/// Trait implemented by the payments manager used by handlers.
#[async_trait]
#[cfg_attr(test, automock)]
pub(crate) trait PaymentsManager {
    /// Approves a pending refund request and queues the provider refund.
    async fn approve_refund_request(&self, input: &ApproveRefundRequestInput) -> Result<()>;

    /// Completes a free checkout and enqueues the attendee welcome notification.
    async fn complete_free_checkout(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        event_purchase_id: Uuid,
        user_id: Uuid,
    ) -> Result<()>;

    /// Completes an externally resolved terminal provider refund.
    async fn complete_refund_recovery(&self, input: &CompleteRefundRecoveryInput) -> Result<()>;

    /// Returns the configured payments provider, when paid operations are enabled.
    fn configured_provider(&self) -> Option<PaymentProvider>;

    /// Creates or reuses the provider checkout URL for a pending event purchase.
    async fn get_or_create_checkout_redirect_url(
        &self,
        prepared_checkout: &PreparedEventCheckout,
        user_id: Uuid,
    ) -> Result<String>;

    /// Retrieves the current provider URL for an attendee-owned financial document.
    async fn get_purchase_document_url(
        &self,
        user_id: Uuid,
        event_purchase_id: Uuid,
        event_purchase_credit_note_id: Option<Uuid>,
    ) -> Result<Option<String>>;

    /// Lists active Tax Rates in the group's fiscal sponsor account.
    async fn list_tax_rates(
        &self,
        recipient: &GroupPaymentRecipient,
        tax_behavior: TicketTaxBehavior,
    ) -> Result<Vec<TicketTaxRate>>;

    /// Verifies and processes a connected-account webhook payload.
    async fn handle_connected_webhook(
        &self,
        headers: &HeaderMap,
        body: &str,
    ) -> std::result::Result<(), HandleWebhookError>;

    /// Verifies and processes a platform-account webhook payload.
    async fn handle_webhook(
        &self,
        headers: &HeaderMap,
        body: &str,
    ) -> std::result::Result<(), HandleWebhookError>;

    /// Rejects a pending refund request and notifies the attendee.
    async fn reject_refund_request(&self, input: &RejectRefundRequestInput) -> Result<()>;

    /// Records an attendee refund request with notification payload data.
    async fn request_refund(&self, input: &RequestRefundInput) -> Result<()>;

    /// Validates a fiscal sponsor before persisting paid ticket configuration.
    async fn validate_fiscal_sponsor(
        &self,
        recipient: &GroupPaymentRecipient,
        require_automatic_tax: bool,
    ) -> std::result::Result<(), FiscalSponsorReadinessError>;

    /// Validates manual Tax Rates in the group's fiscal sponsor account.
    async fn validate_tax_rates(
        &self,
        recipient: &GroupPaymentRecipient,
        manual_tax_rate_ids: &[String],
        tax_behavior: TicketTaxBehavior,
    ) -> std::result::Result<(), FiscalSponsorReadinessError>;
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

    /// Verifies and processes a webhook payload in the expected account scope.
    async fn handle_scoped_webhook(
        &self,
        endpoint: PaymentsWebhookEndpoint,
        headers: &HeaderMap,
        body: &str,
    ) -> std::result::Result<(), HandleWebhookError> {
        let payments_provider = self
            .payments_provider
            .as_ref()
            .ok_or(HandleWebhookError::PaymentsNotConfigured)?;

        // Verify the webhook payload before dispatching the normalized event
        let webhook_event = payments_provider
            .verify_and_parse_webhook(endpoint, headers, body)
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

    /// Returns the configured payments provider when paid operations are available.
    fn payments_provider(&self) -> Result<&DynPaymentsProvider> {
        self.payments_provider
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("payments are not configured"))
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
        // Persist the review decision and durable worker job atomically
        self.db
            .queue_event_refund_request_approval(
                input.actor_user_id,
                input.group_id,
                input.event_purchase_id,
                input.review_note.clone(),
            )
            .await
    }

    /// [`PaymentsManager::complete_free_checkout`].
    async fn complete_free_checkout(
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

    /// [`PaymentsManager::complete_refund_recovery`].
    async fn complete_refund_recovery(&self, input: &CompleteRefundRecoveryInput) -> Result<()> {
        // Load group-scoped event context before composing attendee-facing data
        let context = self
            .db
            .get_event_purchase_refund_recovery_context(input.group_id, input.event_purchase_id)
            .await?;

        // Compose the notification only when local finalization remains pending
        let notification_template_data = if context.notification_required {
            Some(
                self.notification_composer
                    .build_refund_approval_template_data(context.community_id, context.event_id)
                    .await?,
            )
        } else {
            None
        };

        // Complete local state and enqueue any notification atomically
        self.db
            .complete_event_purchase_refund_recovery(&CompleteEventPurchaseRefundRecoveryInput {
                actor_user_id: input.actor_user_id,
                event_purchase_refund_id: context.event_purchase_refund_id,
                group_id: input.group_id,
                recovery_note: input.recovery_note.clone(),
                recovery_reference: input.recovery_reference.clone(),
                notification_template_data,
                payment_provider: self
                    .payments_provider
                    .as_ref()
                    .map(|provider| provider.provider()),
            })
            .await
    }

    /// [`PaymentsManager::configured_provider`].
    fn configured_provider(&self) -> Option<PaymentProvider> {
        self.payments_provider
            .as_ref()
            .map(|payments_provider| payments_provider.provider())
    }

    /// [`PaymentsManager::get_or_create_checkout_redirect_url`].
    async fn get_or_create_checkout_redirect_url(
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
        let currency_code = prepared_checkout
            .purchase
            .currency_code
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("paid checkout is missing currency_code"))?;
        let seller = prepared_checkout
            .seller
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("paid checkout is missing a fiscal sponsor seller"))?;
        let tax_behavior = prepared_checkout
            .tax_behavior
            .ok_or_else(|| anyhow::anyhow!("paid checkout is missing tax behavior"))?;
        let tax_calculation_mode = prepared_checkout
            .tax_calculation_mode
            .ok_or_else(|| anyhow::anyhow!("paid checkout is missing tax calculation mode"))?;
        let tax_code = match tax_calculation_mode {
            TicketTaxCalculationMode::Automatic => Some(
                prepared_checkout
                    .tax_code
                    .as_ref()
                    .ok_or_else(|| anyhow::anyhow!("paid checkout is missing ticket tax code"))?
                    .clone(),
            ),
            TicketTaxCalculationMode::Manual | TicketTaxCalculationMode::None => None,
        };
        let venue = prepared_checkout
            .venue
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("paid checkout is missing venue snapshot"))?;

        if seller.provider != payments_provider.provider() {
            bail!("fiscal sponsor seller is not configured for this provider");
        }

        // Create the provider checkout session
        let checkout_session = payments_provider
            .create_checkout_session(&CreateCheckoutSessionInput {
                amount_minor: prepared_checkout.purchase.amount_minor,
                base_url: self.server_cfg.base_url.clone(),
                community_display_name: prepared_checkout.community_display_name.clone(),
                community_name: prepared_checkout.community_name.clone(),
                currency_code: currency_code.clone(),
                event_id: prepared_checkout.event_id,
                event_name: prepared_checkout.event_name.clone(),
                event_slug: prepared_checkout.event_slug.clone(),
                event_timezone: prepared_checkout.event_timezone.clone(),
                group_name: prepared_checkout.group_name.clone(),
                group_slug: prepared_checkout.group_slug.clone(),
                provisional_platform_fee_amount_minor: prepared_checkout
                    .purchase
                    .provisional_platform_fee_amount_minor,
                purchase_id: prepared_checkout.purchase.event_purchase_id,
                seller: seller.clone(),
                tax_behavior,
                tax_calculation_mode,
                ticket_title: prepared_checkout.purchase.ticket_title.clone(),
                user_id,
                venue: venue.clone(),

                cached_performance_location_fingerprint: prepared_checkout
                    .cached_performance_location_fingerprint
                    .clone(),
                cached_product_fingerprint: prepared_checkout.cached_product_fingerprint.clone(),
                cached_provider_tax_location_id: prepared_checkout
                    .cached_provider_tax_location_id
                    .clone(),
                cached_provider_tax_product_id: prepared_checkout
                    .cached_provider_tax_product_id
                    .clone(),
                discount_code: prepared_checkout.purchase.discount_code.clone(),
                group_slug_pretty: prepared_checkout.group_slug_pretty.clone(),
                manual_tax_rate_ids: prepared_checkout.manual_tax_rate_ids.clone(),
                tax_code,
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

    /// [`PaymentsManager::get_purchase_document_url`].
    async fn get_purchase_document_url(
        &self,
        user_id: Uuid,
        event_purchase_id: Uuid,
        event_purchase_credit_note_id: Option<Uuid>,
    ) -> Result<Option<String>> {
        // Load the attendee-owned invoice or credit-note context
        let Some(context) = self
            .db
            .get_user_purchase_document_context(
                user_id,
                event_purchase_id,
                event_purchase_credit_note_id,
            )
            .await?
        else {
            return Ok(None);
        };

        // Require the document to belong to the configured provider
        let payments_provider = self.payments_provider()?;
        if context.payment_provider != payments_provider.provider() {
            bail!("purchase document is not owned by the configured provider");
        }

        // Retrieve the document's current provider URLs
        let document = payments_provider
            .get_financial_document(&GetFinancialDocumentInput {
                connected_seller_id: context.connected_seller_id,
                kind: if event_purchase_credit_note_id.is_some() {
                    FinancialDocumentKind::CreditNote
                } else {
                    FinancialDocumentKind::Invoice
                },
                provider_document_id: context.provider_document_id,
            })
            .await?;

        // Return the provider's available hosted or PDF URL
        Ok(Some(document.url().ok_or_else(|| {
            anyhow::anyhow!("provider financial document has no current URL")
        })?))
    }

    /// [`PaymentsManager::handle_connected_webhook`].
    async fn handle_connected_webhook(
        &self,
        headers: &HeaderMap,
        body: &str,
    ) -> std::result::Result<(), HandleWebhookError> {
        self.handle_scoped_webhook(PaymentsWebhookEndpoint::ConnectedAccount, headers, body)
            .await
    }

    /// [`PaymentsManager::handle_webhook`].
    async fn handle_webhook(
        &self,
        headers: &HeaderMap,
        body: &str,
    ) -> std::result::Result<(), HandleWebhookError> {
        self.handle_scoped_webhook(PaymentsWebhookEndpoint::PlatformAccount, headers, body)
            .await
    }

    /// [`PaymentsManager::list_tax_rates`].
    async fn list_tax_rates(
        &self,
        recipient: &GroupPaymentRecipient,
        tax_behavior: TicketTaxBehavior,
    ) -> Result<Vec<TicketTaxRate>> {
        let payments_provider = self.payments_provider()?;
        if recipient.provider != payments_provider.provider() {
            bail!("fiscal sponsor seller is not configured for this provider");
        }

        payments_provider
            .list_tax_rates(&ListTaxRatesInput {
                connected_seller_id: recipient.recipient_id.clone(),
                tax_behavior,
            })
            .await
    }

    /// [`PaymentsManager::reject_refund_request`].
    async fn reject_refund_request(&self, input: &RejectRefundRequestInput) -> Result<()> {
        // Normalize the attendee-visible reason once for persistence and delivery
        let rejection_reason = input.review_note.trim().to_string();

        // Persist the refund rejection in the database
        let purchase = self
            .db
            .reject_event_refund_request(
                input.actor_user_id,
                input.group_id,
                input.event_purchase_id,
                rejection_reason.clone(),
            )
            .await?;

        // Notify the attendee about the rejected refund
        self.notification_composer
            .enqueue_refund_rejection_notification(
                purchase.community_id,
                purchase.event_id,
                purchase.user_id,
                &rejection_reason,
            )
            .await;

        Ok(())
    }

    /// [`PaymentsManager::request_refund`].
    async fn request_refund(&self, input: &RequestRefundInput) -> Result<()> {
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

    /// [`PaymentsManager::validate_fiscal_sponsor`].
    async fn validate_fiscal_sponsor(
        &self,
        recipient: &GroupPaymentRecipient,
        require_automatic_tax: bool,
    ) -> std::result::Result<(), FiscalSponsorReadinessError> {
        let payments_provider = self
            .payments_provider()
            .map_err(FiscalSponsorReadinessError::Unexpected)?;
        payments_provider
            .validate_fiscal_sponsor(&FiscalSponsorReadinessInput {
                connected_seller_id: recipient.recipient_id.clone(),
                provider: recipient.provider,
                require_automatic_tax,
            })
            .await
    }

    /// [`PaymentsManager::validate_tax_rates`].
    async fn validate_tax_rates(
        &self,
        recipient: &GroupPaymentRecipient,
        manual_tax_rate_ids: &[String],
        tax_behavior: TicketTaxBehavior,
    ) -> std::result::Result<(), FiscalSponsorReadinessError> {
        let payments_provider = self
            .payments_provider()
            .map_err(FiscalSponsorReadinessError::Unexpected)?;
        if recipient.provider != payments_provider.provider() {
            return Err(FiscalSponsorReadinessError::NotReady(
                "fiscal sponsor seller is not configured for this provider".to_string(),
            ));
        }

        payments_provider
            .validate_tax_rates(&ValidateTaxRatesInput {
                connected_seller_id: recipient.recipient_id.clone(),
                manual_tax_rate_ids: manual_tax_rate_ids.to_vec(),
                tax_behavior,
            })
            .await
    }
}

/// Parameters used to approve a pending refund request.
#[derive(Clone, Debug)]
pub(crate) struct ApproveRefundRequestInput {
    /// User approving the refund request.
    pub actor_user_id: Uuid,
    /// Purchase whose refund request is being approved.
    pub event_purchase_id: Uuid,
    /// Group containing the event.
    pub group_id: Uuid,

    /// Optional review note stored with the approval.
    pub review_note: Option<String>,
}

/// Parameters used to complete an externally resolved refund.
#[derive(Clone, Debug)]
pub(crate) struct CompleteRefundRecoveryInput {
    /// User completing the recovery.
    pub actor_user_id: Uuid,
    /// Purchase whose refund is being recovered.
    pub event_purchase_id: Uuid,
    /// Group containing the event.
    pub group_id: Uuid,
    /// Evidence reviewed before completing recovery.
    pub recovery_note: String,
    /// Reference for the external refund.
    pub recovery_reference: String,
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
    /// Purchase whose refund request is being rejected.
    pub event_purchase_id: Uuid,
    /// Group containing the event.
    pub group_id: Uuid,

    /// Attendee-visible reason stored with the rejection.
    pub review_note: String,
}
