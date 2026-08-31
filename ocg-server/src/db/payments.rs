//! Database operations for payments, ticketing, and refunds.

use std::ops::{Deref, DerefMut};

use anyhow::{Result, anyhow};
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::PgExecutor,
    services::payments::CheckoutSession,
    types::{
        event::EventEnrollmentReconciliationOutcome,
        payments::{EventPurchaseSummary, PaymentProvider, PreparedEventCheckout, TicketVenue},
        questionnaire::QuestionnaireAnswers,
    },
};

/// Database operations for payments.
#[async_trait]
pub(crate) trait DBPayments {
    /// Approves an external-purchase refund request and refunds it locally.
    async fn approve_external_event_refund_request(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        event_purchase_id: Uuid,
        review_note: Option<String>,
        notification_template_data: Option<serde_json::Value>,
    ) -> Result<CompletedEventPurchase>;

    /// Attaches an asynchronously created application fee to its direct-charge purchase.
    async fn attach_application_fee_to_event_purchase(
        &self,
        payment_provider: PaymentProvider,
        connected_seller_id: &str,
        provider_charge_id: &str,
        provider_application_fee_id: &str,
        amount_minor: i64,
    ) -> Result<()>;

    /// Adds the provider checkout session details to a pending purchase.
    async fn attach_checkout_session_to_event_purchase(
        &self,
        event_purchase_id: Uuid,
        payment_provider: PaymentProvider,
        checkout_session: &CheckoutSession,
    ) -> Result<()>;

    /// Adds a paid invoice and current provider URLs to its purchase.
    async fn attach_invoice_to_event_purchase(
        &self,
        event_purchase_id: Uuid,
        connected_seller_id: &str,
        provider_invoice_id: &str,
        provider_invoice_hosted_url: &str,
        provider_invoice_pdf_url: Option<String>,
    ) -> Result<()>;

    /// Cancels an attendee's active pending checkout.
    async fn cancel_event_checkout(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
        payment_provider: Option<PaymentProvider>,
    ) -> Result<()>;

    /// Claims the next due application-fee adjustment.
    async fn claim_event_purchase_application_fee_adjustment(
        &self,
        payment_provider: PaymentProvider,
    ) -> Result<Option<ClaimedEventPurchaseApplicationFeeAdjustment>>;

    /// Claims the next due credit note.
    async fn claim_event_purchase_credit_note(
        &self,
        payment_provider: PaymentProvider,
    ) -> Result<Option<ClaimedEventPurchaseCreditNote>>;

    /// Claims the next refund ready for the configured provider.
    async fn claim_event_purchase_refund(
        &self,
        payment_provider: PaymentProvider,
    ) -> Result<Option<ClaimedEventPurchaseRefund>>;

    /// Completes an application-fee adjustment resolved outside OCG.
    async fn complete_event_purchase_application_fee_adjustment_recovery(
        &self,
        input: &CompleteEventPurchaseFinancialRecoveryInput,
    ) -> Result<()>;

    /// Completes a credit note issued outside OCG.
    async fn complete_event_purchase_credit_note_recovery(
        &self,
        input: &CompleteEventPurchaseFinancialRecoveryInput,
    ) -> Result<()>;

    /// Completes an externally resolved terminal provider refund.
    async fn complete_event_purchase_refund_recovery(
        &self,
        input: &CompleteEventPurchaseRefundRecoveryInput,
    ) -> Result<()>;

    /// Completes a pending external purchase after an organizer marks it paid.
    async fn complete_external_event_purchase(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        event_purchase_id: Uuid,
        details: Option<String>,
        notification_attachments: Option<serde_json::Value>,
        notification_template_data: Option<serde_json::Value>,
    ) -> Result<CompletedEventPurchase>;

    /// Completes a free purchase locally without a provider checkout.
    async fn complete_free_event_purchase(
        &self,
        event_purchase_id: Uuid,
    ) -> Result<CompletedEventPurchase>;

    /// Expires a pending purchase when its provider checkout session expires.
    async fn expire_event_purchase_for_checkout_session(
        &self,
        payment_provider: PaymentProvider,
        provider_object_account_id: String,
        provider_session_id: &str,
    ) -> Result<()>;

    /// Finalizes a provider-complete refund for the current worker claim.
    async fn finalize_event_purchase_refund(
        &self,
        event_purchase_refund_id: Uuid,
        claim_id: Uuid,
        notification_template_data: serde_json::Value,
        payment_provider: Option<PaymentProvider>,
    ) -> Result<()>;

    /// Loads the charge model recorded on a purchase.
    async fn get_event_purchase_charge_model(
        &self,
        event_purchase_id: Uuid,
    ) -> Result<crate::types::payments::EventPurchaseChargeModel>;

    /// Loads identifiers used to compose purchase completion notifications.
    async fn get_event_purchase_notification_context(
        &self,
        group_id: Uuid,
        event_purchase_id: Uuid,
    ) -> Result<Option<EventPurchaseNotificationContext>>;

    /// Loads the durable refund record for a purchase.
    async fn get_event_purchase_refund(
        &self,
        event_purchase_id: Uuid,
    ) -> Result<EventPurchaseRefund>;

    /// Loads authoritative context for completing a refund recovery.
    async fn get_event_purchase_refund_recovery_context(
        &self,
        group_id: Uuid,
        event_purchase_id: Uuid,
    ) -> Result<EventPurchaseRefundRecoveryContext>;

    /// Loads the current attendee-facing summary for a purchase.
    async fn get_event_purchase_summary(
        &self,
        event_purchase_id: Uuid,
    ) -> Result<EventPurchaseSummary>;

    /// Loads an account-scoped performance location for an exact venue fingerprint.
    async fn get_payment_provider_tax_location(
        &self,
        payment_provider: PaymentProvider,
        connected_seller_id: &str,
        fingerprint: &str,
    ) -> Result<Option<String>>;

    /// Resolves an attendee-owned invoice or credit note through provider scope.
    async fn get_user_purchase_document_context(
        &self,
        user_id: Uuid,
        event_purchase_id: Uuid,
        event_purchase_credit_note_id: Option<Uuid>,
    ) -> Result<Option<UserPurchaseDocumentContext>>;

    /// Prepares a checkout purchase for an attendee ticket purchase.
    async fn prepare_event_checkout_purchase(
        &self,
        community_id: Uuid,
        input: &PrepareEventCheckoutPurchaseInput,
    ) -> Result<PrepareEventCheckoutPurchaseResult>;

    /// Queues an approved attendee refund request for worker processing.
    async fn queue_event_refund_request_approval(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        event_purchase_id: Uuid,
        review_note: Option<String>,
    ) -> Result<()>;

    /// Reconciles a provider-backed purchase by checkout session id.
    async fn reconcile_event_purchase_for_checkout_session(
        &self,
        input: &ReconcileEventPurchaseForCheckoutSessionInput,
    ) -> Result<ReconcileEventPurchaseResult>;

    /// Reconciles one event with a due enrollment reservation.
    async fn reconcile_next_event_enrollment(
        &self,
        payment_provider: Option<PaymentProvider>,
    ) -> Result<Option<EventEnrollmentReconciliationOutcome>>;

    /// Releases a failed application-fee adjustment claim for retry.
    async fn record_event_purchase_application_fee_adjustment_failure(
        &self,
        adjustment_id: Uuid,
        claim_id: Uuid,
        failure_message: String,
    ) -> Result<()>;

    /// Records a completed provider application-fee refund.
    async fn record_event_purchase_application_fee_adjustment_succeeded(
        &self,
        adjustment_id: Uuid,
        claim_id: Uuid,
        provider_application_fee_refund_id: String,
    ) -> Result<()>;

    /// Releases a failed credit-note claim for retry.
    async fn record_event_purchase_credit_note_failure(
        &self,
        credit_note_id: Uuid,
        claim_id: Uuid,
        failure_message: String,
    ) -> Result<()>;

    /// Records an issued provider credit note and current document URLs.
    async fn record_event_purchase_credit_note_succeeded(
        &self,
        credit_note_id: Uuid,
        claim_id: Uuid,
        provider_credit_note_id: String,
        provider_hosted_url: Option<String>,
        provider_pdf_url: Option<String>,
    ) -> Result<()>;

    /// Records an in-progress provider refund for the expected attempt.
    async fn record_event_purchase_refund_pending(
        &self,
        event_purchase_refund_id: Uuid,
        expected_idempotency_key: String,
        provider_refund_id: String,
        expected_claim_id: Option<Uuid>,
    ) -> Result<EventPurchaseRefund>;

    /// Releases a worker claim after a retryable provider error.
    async fn record_event_purchase_refund_retryable_failure(
        &self,
        event_purchase_refund_id: Uuid,
        claim_id: Uuid,
        failure_message: String,
    ) -> Result<()>;

    /// Records a successful provider refund for the expected attempt.
    async fn record_event_purchase_refund_succeeded(
        &self,
        event_purchase_refund_id: Uuid,
        expected_idempotency_key: String,
        provider_refund_id: String,
        expected_claim_id: Option<Uuid>,
    ) -> Result<EventPurchaseRefund>;

    /// Records a terminal failure and pins the expected provider attempt.
    async fn record_event_purchase_refund_terminal_failed(
        &self,
        event_purchase_refund_id: Uuid,
        expected_idempotency_key: String,
        provider_refund_id: String,
        failure_message: String,
        expected_claim_id: Option<Uuid>,
    ) -> Result<()>;

    /// Rejects a pending attendee refund request.
    async fn reject_event_refund_request(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        event_purchase_id: Uuid,
        review_note: String,
    ) -> Result<CompletedEventPurchase>;

    /// Creates a refund request for an attendee purchase.
    async fn request_event_refund(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
        requested_reason: Option<String>,
        notification_template_data: serde_json::Value,
    ) -> Result<()>;

    /// Requeues an exhausted application-fee adjustment.
    async fn requeue_event_purchase_application_fee_adjustment(
        &self,
        group_id: Uuid,
        adjustment_id: Uuid,
    ) -> Result<()>;

    /// Requeues an exhausted credit note.
    async fn requeue_event_purchase_credit_note(
        &self,
        group_id: Uuid,
        credit_note_id: Uuid,
    ) -> Result<()>;

    /// Requeues a retryable refund after an administrator requests another attempt.
    async fn requeue_event_purchase_refund(
        &self,
        group_id: Uuid,
        event_purchase_id: Uuid,
    ) -> Result<()>;

    /// Releases stale claims left by interrupted application-fee adjustment workers.
    async fn requeue_stale_event_purchase_application_fee_adjustment_claims(&self) -> Result<i32>;

    /// Releases stale claims left by interrupted credit-note workers.
    async fn requeue_stale_event_purchase_credit_note_claims(&self) -> Result<i32>;

    /// Releases stale claims left by interrupted refund workers.
    async fn requeue_stale_event_purchase_refund_claims(&self) -> Result<i32>;

    /// Upserts or deletes the singleton external-payments configuration row.
    async fn sync_external_payments_config(
        &self,
        config: Option<crate::config::ExternalPaymentsConfig>,
    ) -> Result<()>;

    /// Persists an account-scoped performance location for future reuse.
    async fn upsert_payment_provider_tax_location(
        &self,
        payment_provider: PaymentProvider,
        connected_seller_id: &str,
        fingerprint: &str,
        provider_tax_location_id: &str,
        venue: &TicketVenue,
    ) -> Result<()>;
}

#[async_trait]
impl<T> DBPayments for T
where
    T: PgExecutor + Send + Sync,
{
    /// [`DBPayments::approve_external_event_refund_request`].
    #[instrument(skip(self), err)]
    async fn approve_external_event_refund_request(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        event_purchase_id: Uuid,
        review_note: Option<String>,
        notification_template_data: Option<serde_json::Value>,
    ) -> Result<CompletedEventPurchase> {
        self.fetch_json_one(
            "select approve_external_event_refund_request($1::uuid, $2::uuid, $3::uuid, $4::text, $5::jsonb)",
            &[
                &actor_user_id,
                &group_id,
                &event_purchase_id,
                &review_note,
                &notification_template_data.as_ref().map(Json),
            ],
        )
        .await
    }

    /// [`DBPayments::attach_application_fee_to_event_purchase`].
    #[instrument(skip(self), err)]
    async fn attach_application_fee_to_event_purchase(
        &self,
        payment_provider: PaymentProvider,
        connected_seller_id: &str,
        provider_charge_id: &str,
        provider_application_fee_id: &str,
        amount_minor: i64,
    ) -> Result<()> {
        self.execute(
            "select attach_application_fee_to_event_purchase($1::text, $2::text, $3::text, $4::text, $5::bigint)",
            &[
                &payment_provider.to_string(),
                &connected_seller_id,
                &provider_charge_id,
                &provider_application_fee_id,
                &amount_minor,
            ],
        )
        .await
    }

    /// [`DBPayments::attach_checkout_session_to_event_purchase`].
    #[instrument(skip(self, checkout_session), err)]
    async fn attach_checkout_session_to_event_purchase(
        &self,
        event_purchase_id: Uuid,
        payment_provider: PaymentProvider,
        checkout_session: &CheckoutSession,
    ) -> Result<()> {
        self.execute(
            "
            select attach_checkout_session_to_event_purchase(
                $1::uuid,
                $2::text,
                $3::text,
                $4::text,
                $5::text,
                $6::text,
                $7::text,
                $8::text,
                $9::text
            )
            ",
            &[
                &event_purchase_id,
                &payment_provider.to_string(),
                &checkout_session.provider_object_account_id,
                &checkout_session.provider_session_id,
                &checkout_session.redirect_url,
                &checkout_session.provider_tax_location_id,
                &checkout_session.performance_location_fingerprint,
                &checkout_session.provider_tax_product_id,
                &checkout_session.product_fingerprint,
            ],
        )
        .await
    }

    /// [`DBPayments::attach_invoice_to_event_purchase`].
    #[instrument(skip(self), err)]
    async fn attach_invoice_to_event_purchase(
        &self,
        event_purchase_id: Uuid,
        connected_seller_id: &str,
        provider_invoice_id: &str,
        provider_invoice_hosted_url: &str,
        provider_invoice_pdf_url: Option<String>,
    ) -> Result<()> {
        self.execute(
            "
            select attach_invoice_to_event_purchase(
                $1::uuid,
                $2::text,
                $3::text,
                $4::text,
                $5::text
            )
            ",
            &[
                &event_purchase_id,
                &connected_seller_id,
                &provider_invoice_id,
                &provider_invoice_hosted_url,
                &provider_invoice_pdf_url,
            ],
        )
        .await
    }

    /// [`DBPayments::cancel_event_checkout`].
    #[instrument(skip(self), err)]
    async fn cancel_event_checkout(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
        payment_provider: Option<PaymentProvider>,
    ) -> Result<()> {
        self.execute(
            "select cancel_event_checkout($1::uuid, $2::uuid, $3::uuid, $4::text)",
            &[
                &community_id,
                &event_id,
                &user_id,
                &payment_provider.map(|provider| provider.to_string()),
            ],
        )
        .await
    }

    /// [`DBPayments::claim_event_purchase_application_fee_adjustment`].
    #[instrument(skip(self), err)]
    async fn claim_event_purchase_application_fee_adjustment(
        &self,
        payment_provider: PaymentProvider,
    ) -> Result<Option<ClaimedEventPurchaseApplicationFeeAdjustment>> {
        self.fetch_json_opt(
            "select claim_event_purchase_application_fee_adjustment($1::text)",
            &[&payment_provider.to_string()],
        )
        .await
    }

    /// [`DBPayments::claim_event_purchase_credit_note`].
    #[instrument(skip(self), err)]
    async fn claim_event_purchase_credit_note(
        &self,
        payment_provider: PaymentProvider,
    ) -> Result<Option<ClaimedEventPurchaseCreditNote>> {
        self.fetch_json_opt(
            "select claim_event_purchase_credit_note($1::text)",
            &[&payment_provider.to_string()],
        )
        .await
    }

    /// [`DBPayments::claim_event_purchase_refund`].
    #[instrument(skip(self), err)]
    async fn claim_event_purchase_refund(
        &self,
        payment_provider: PaymentProvider,
    ) -> Result<Option<ClaimedEventPurchaseRefund>> {
        self.fetch_json_opt(
            "select claim_event_purchase_refund($1::text)",
            &[&payment_provider.to_string()],
        )
        .await
    }

    /// [`DBPayments::complete_event_purchase_application_fee_adjustment_recovery`].
    #[instrument(skip(self, input), err)]
    async fn complete_event_purchase_application_fee_adjustment_recovery(
        &self,
        input: &CompleteEventPurchaseFinancialRecoveryInput,
    ) -> Result<()> {
        self.execute(
            "
            select complete_event_purchase_application_fee_adjustment_recovery(
                $1::uuid,
                $2::uuid,
                $3::uuid,
                $4::text,
                $5::text,
                $6::text
            )
            ",
            &[
                &input.actor_user_id,
                &input.group_id,
                &input.work_id,
                &input.provider_object_id,
                &input.recovery_reference,
                &input.recovery_note,
            ],
        )
        .await
    }

    /// [`DBPayments::complete_event_purchase_credit_note_recovery`].
    #[instrument(skip(self, input), err)]
    async fn complete_event_purchase_credit_note_recovery(
        &self,
        input: &CompleteEventPurchaseFinancialRecoveryInput,
    ) -> Result<()> {
        self.execute(
            "
            select complete_event_purchase_credit_note_recovery(
                $1::uuid,
                $2::uuid,
                $3::uuid,
                $4::text,
                $5::text,
                $6::text
            )
            ",
            &[
                &input.actor_user_id,
                &input.group_id,
                &input.work_id,
                &input.provider_object_id,
                &input.recovery_reference,
                &input.recovery_note,
            ],
        )
        .await
    }

    /// [`DBPayments::complete_event_purchase_refund_recovery`].
    #[instrument(skip(self, input), err)]
    async fn complete_event_purchase_refund_recovery(
        &self,
        input: &CompleteEventPurchaseRefundRecoveryInput,
    ) -> Result<()> {
        self.execute(
            "
            select complete_event_purchase_refund_recovery(
                $1::uuid,
                $2::uuid,
                $3::uuid,
                $4::text,
                $5::text,
                $6::jsonb,
                $7::text
            )
            ",
            &[
                &input.actor_user_id,
                &input.group_id,
                &input.event_purchase_refund_id,
                &input.recovery_reference,
                &input.recovery_note,
                &input.notification_template_data.as_ref().map(Json),
                &input.payment_provider.map(|provider| provider.to_string()),
            ],
        )
        .await
    }

    /// [`DBPayments::complete_external_event_purchase`].
    #[instrument(skip(self), err)]
    async fn complete_external_event_purchase(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        event_purchase_id: Uuid,
        details: Option<String>,
        notification_attachments: Option<serde_json::Value>,
        notification_template_data: Option<serde_json::Value>,
    ) -> Result<CompletedEventPurchase> {
        self.fetch_json_one(
            "select complete_external_event_purchase($1::uuid, $2::uuid, $3::uuid, $4::text, $5::jsonb, $6::jsonb)",
            &[
                &actor_user_id,
                &group_id,
                &event_purchase_id,
                &details,
                &notification_attachments.as_ref().map(Json),
                &notification_template_data.as_ref().map(Json),
            ],
        )
        .await
    }

    /// [`DBPayments::complete_free_event_purchase`].
    #[instrument(skip(self), err)]
    async fn complete_free_event_purchase(
        &self,
        event_purchase_id: Uuid,
    ) -> Result<CompletedEventPurchase> {
        self.fetch_json_one(
            "select complete_free_event_purchase($1::uuid)",
            &[&event_purchase_id],
        )
        .await
    }

    /// [`DBPayments::expire_event_purchase_for_checkout_session`].
    #[instrument(skip(self), err)]
    async fn expire_event_purchase_for_checkout_session(
        &self,
        payment_provider: PaymentProvider,
        provider_object_account_id: String,
        provider_session_id: &str,
    ) -> Result<()> {
        self.execute(
            "select expire_event_purchase_for_checkout_session($1::text, $2::text, $3::text)",
            &[
                &payment_provider.to_string(),
                &provider_object_account_id,
                &provider_session_id,
            ],
        )
        .await
    }

    /// [`DBPayments::finalize_event_purchase_refund`].
    #[instrument(skip(self, notification_template_data), err)]
    async fn finalize_event_purchase_refund(
        &self,
        event_purchase_refund_id: Uuid,
        claim_id: Uuid,
        notification_template_data: serde_json::Value,
        payment_provider: Option<PaymentProvider>,
    ) -> Result<()> {
        self.execute(
            "
            select finalize_event_purchase_refund(
                $1::uuid,
                $2::uuid,
                $3::jsonb,
                $4::text
            )
            ",
            &[
                &event_purchase_refund_id,
                &claim_id,
                &Json(&notification_template_data),
                &payment_provider.map(|provider| provider.to_string()),
            ],
        )
        .await
    }

    /// [`DBPayments::get_event_purchase_charge_model`].
    #[instrument(skip(self), err)]
    async fn get_event_purchase_charge_model(
        &self,
        event_purchase_id: Uuid,
    ) -> Result<crate::types::payments::EventPurchaseChargeModel> {
        let charge_model: String = self
            .fetch_scalar_one(
                "
                select charge_model
                from event_purchase
                where event_purchase_id = $1::uuid
                ",
                &[&event_purchase_id],
            )
            .await?;

        charge_model
            .parse()
            .map_err(|err| anyhow!("unsupported event purchase charge model: {err}"))
    }

    /// [`DBPayments::get_event_purchase_notification_context`].
    #[instrument(skip(self), err)]
    async fn get_event_purchase_notification_context(
        &self,
        group_id: Uuid,
        event_purchase_id: Uuid,
    ) -> Result<Option<EventPurchaseNotificationContext>> {
        self.fetch_json_opt(
            "select get_event_purchase_notification_context($1::uuid, $2::uuid)",
            &[&group_id, &event_purchase_id],
        )
        .await
    }

    /// [`DBPayments::get_event_purchase_refund`].
    #[instrument(skip(self), err)]
    async fn get_event_purchase_refund(
        &self,
        event_purchase_id: Uuid,
    ) -> Result<EventPurchaseRefund> {
        self.fetch_json_one(
            "select get_event_purchase_refund($1::uuid)",
            &[&event_purchase_id],
        )
        .await
    }

    /// [`DBPayments::get_event_purchase_refund_recovery_context`].
    #[instrument(skip(self), err)]
    async fn get_event_purchase_refund_recovery_context(
        &self,
        group_id: Uuid,
        event_purchase_id: Uuid,
    ) -> Result<EventPurchaseRefundRecoveryContext> {
        self.fetch_json_one(
            "select get_event_purchase_refund_recovery_context($1::uuid, $2::uuid)",
            &[&group_id, &event_purchase_id],
        )
        .await
    }

    /// [`DBPayments::get_event_purchase_summary`].
    #[instrument(skip(self), err)]
    async fn get_event_purchase_summary(
        &self,
        event_purchase_id: Uuid,
    ) -> Result<EventPurchaseSummary> {
        self.fetch_json_one(
            "select prepare_event_checkout_get_purchase_summary($1::uuid)",
            &[&event_purchase_id],
        )
        .await
    }

    /// [`DBPayments::get_payment_provider_tax_location`].
    #[instrument(skip(self), err)]
    async fn get_payment_provider_tax_location(
        &self,
        payment_provider: PaymentProvider,
        connected_seller_id: &str,
        fingerprint: &str,
    ) -> Result<Option<String>> {
        self.fetch_scalar_opt(
            "
            select provider_tax_location_id
            from payment_provider_tax_location
            where payment_provider_id = $1::text
            and connected_seller_id = $2::text
            and fingerprint = $3::text
            ",
            &[
                &payment_provider.to_string(),
                &connected_seller_id,
                &fingerprint,
            ],
        )
        .await
    }

    /// [`DBPayments::get_user_purchase_document_context`].
    #[instrument(skip(self), err)]
    async fn get_user_purchase_document_context(
        &self,
        user_id: Uuid,
        event_purchase_id: Uuid,
        event_purchase_credit_note_id: Option<Uuid>,
    ) -> Result<Option<UserPurchaseDocumentContext>> {
        self.fetch_json_opt(
            "select get_user_purchase_document_context($1::uuid, $2::uuid, $3::uuid)",
            &[&user_id, &event_purchase_id, &event_purchase_credit_note_id],
        )
        .await
    }

    /// [`DBPayments::prepare_event_checkout_purchase`].
    #[instrument(skip(self, input), err)]
    async fn prepare_event_checkout_purchase(
        &self,
        community_id: Uuid,
        input: &PrepareEventCheckoutPurchaseInput,
    ) -> Result<PrepareEventCheckoutPurchaseResult> {
        let output: PrepareEventCheckoutPurchaseOutput = self
            .fetch_json_one(
                "
                select prepare_event_checkout_purchase(
                    $1::uuid,
                    $2::uuid,
                    $3::uuid,
                    $4::uuid,
                    $5::text,
                    $6::text,
                    $7::jsonb,
                    $8::uuid,
                    $9::int
                )
                ",
                &[
                    &community_id,
                    &input.event_id,
                    &input.event_ticket_type_id,
                    &input.user_id,
                    &input.discount_code,
                    &input.payment_provider.map(|provider| provider.to_string()),
                    &input.registration_answers.as_ref().map(Json),
                    &input.admission_offer_id,
                    &input.platform_fee_bps,
                ],
            )
            .await?;

        Ok(output.into())
    }

    /// [`DBPayments::queue_event_refund_request_approval`].
    #[instrument(skip(self, review_note), err)]
    async fn queue_event_refund_request_approval(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        event_purchase_id: Uuid,
        review_note: Option<String>,
    ) -> Result<()> {
        self.execute(
            "select queue_event_refund_request_approval($1::uuid, $2::uuid, $3::uuid, $4::text)",
            &[&actor_user_id, &group_id, &event_purchase_id, &review_note],
        )
        .await
    }

    /// [`DBPayments::reconcile_event_purchase_for_checkout_session`].
    #[instrument(skip(self), err)]
    async fn reconcile_event_purchase_for_checkout_session(
        &self,
        input: &ReconcileEventPurchaseForCheckoutSessionInput,
    ) -> Result<ReconcileEventPurchaseResult> {
        let result: ReconcileEventPurchaseForCheckoutSessionOutput = self
            .fetch_json_one(
                "
                select reconcile_event_purchase_for_checkout_session(
                    $1::text,
                    $2::text,
                    $3::text,
                    $4::text,
                    $5::text,
                    $6::bigint,
                    $7::bigint,
                    $8::text
                )
                ",
                &[
                    &input.payment_provider.to_string(),
                    &input.provider_object_account_id,
                    &input.provider_session_id,
                    &input.provider_payment_reference,
                    &input.provider_charge_id,
                    &input.provider_total_minor,
                    &input.tax_amount_minor,
                    &input.provider_application_fee_id,
                ],
            )
            .await?;

        Ok(result.into())
    }

    /// [`DBPayments::reconcile_next_event_enrollment`].
    #[instrument(skip(self), err)]
    async fn reconcile_next_event_enrollment(
        &self,
        payment_provider: Option<PaymentProvider>,
    ) -> Result<Option<EventEnrollmentReconciliationOutcome>> {
        self.fetch_json_opt(
            "select reconcile_next_event_enrollment($1::text)",
            &[&payment_provider.map(|provider| provider.to_string())],
        )
        .await
    }

    /// [`DBPayments::record_event_purchase_application_fee_adjustment_failure`].
    #[instrument(skip(self, failure_message), err)]
    async fn record_event_purchase_application_fee_adjustment_failure(
        &self,
        adjustment_id: Uuid,
        claim_id: Uuid,
        failure_message: String,
    ) -> Result<()> {
        self.execute(
            "select record_event_purchase_application_fee_adjustment_failure($1::uuid, $2::uuid, $3::text)",
            &[&adjustment_id, &claim_id, &failure_message],
        )
        .await
    }

    /// [`DBPayments::record_event_purchase_application_fee_adjustment_succeeded`].
    #[instrument(skip(self), err)]
    async fn record_event_purchase_application_fee_adjustment_succeeded(
        &self,
        adjustment_id: Uuid,
        claim_id: Uuid,
        provider_application_fee_refund_id: String,
    ) -> Result<()> {
        self.execute(
            "select record_event_purchase_application_fee_adjustment_succeeded($1::uuid, $2::uuid, $3::text)",
            &[
                &adjustment_id,
                &claim_id,
                &provider_application_fee_refund_id,
            ],
        )
        .await
    }

    /// [`DBPayments::record_event_purchase_credit_note_failure`].
    #[instrument(skip(self, failure_message), err)]
    async fn record_event_purchase_credit_note_failure(
        &self,
        credit_note_id: Uuid,
        claim_id: Uuid,
        failure_message: String,
    ) -> Result<()> {
        self.execute(
            "select record_event_purchase_credit_note_failure($1::uuid, $2::uuid, $3::text)",
            &[&credit_note_id, &claim_id, &failure_message],
        )
        .await
    }

    /// [`DBPayments::record_event_purchase_credit_note_succeeded`].
    #[instrument(skip(self), err)]
    async fn record_event_purchase_credit_note_succeeded(
        &self,
        credit_note_id: Uuid,
        claim_id: Uuid,
        provider_credit_note_id: String,
        provider_hosted_url: Option<String>,
        provider_pdf_url: Option<String>,
    ) -> Result<()> {
        self.execute(
            "select record_event_purchase_credit_note_succeeded($1::uuid, $2::uuid, $3::text, $4::text, $5::text)",
            &[
                &credit_note_id,
                &claim_id,
                &provider_credit_note_id,
                &provider_hosted_url,
                &provider_pdf_url,
            ],
        )
        .await
    }

    /// [`DBPayments::record_event_purchase_refund_pending`].
    #[instrument(skip(self), err)]
    async fn record_event_purchase_refund_pending(
        &self,
        event_purchase_refund_id: Uuid,
        expected_idempotency_key: String,
        provider_refund_id: String,
        expected_claim_id: Option<Uuid>,
    ) -> Result<EventPurchaseRefund> {
        self.fetch_json_one(
            "select record_event_purchase_refund_pending($1::uuid, $2::text, $3::text, $4::uuid)",
            &[
                &event_purchase_refund_id,
                &expected_idempotency_key,
                &provider_refund_id,
                &expected_claim_id,
            ],
        )
        .await
    }

    /// [`DBPayments::record_event_purchase_refund_retryable_failure`].
    #[instrument(skip(self, failure_message), err)]
    async fn record_event_purchase_refund_retryable_failure(
        &self,
        event_purchase_refund_id: Uuid,
        claim_id: Uuid,
        failure_message: String,
    ) -> Result<()> {
        self.execute(
            "select record_event_purchase_refund_retryable_failure($1::uuid, $2::uuid, $3::text)",
            &[&event_purchase_refund_id, &claim_id, &failure_message],
        )
        .await
    }

    /// [`DBPayments::record_event_purchase_refund_succeeded`].
    #[instrument(skip(self), err)]
    async fn record_event_purchase_refund_succeeded(
        &self,
        event_purchase_refund_id: Uuid,
        expected_idempotency_key: String,
        provider_refund_id: String,
        expected_claim_id: Option<Uuid>,
    ) -> Result<EventPurchaseRefund> {
        self.fetch_json_one(
            "select record_event_purchase_refund_succeeded($1::uuid, $2::text, $3::text, $4::uuid)",
            &[
                &event_purchase_refund_id,
                &expected_idempotency_key,
                &provider_refund_id,
                &expected_claim_id,
            ],
        )
        .await
    }

    /// [`DBPayments::record_event_purchase_refund_terminal_failed`].
    #[instrument(skip(self, failure_message), err)]
    async fn record_event_purchase_refund_terminal_failed(
        &self,
        event_purchase_refund_id: Uuid,
        expected_idempotency_key: String,
        provider_refund_id: String,
        failure_message: String,
        expected_claim_id: Option<Uuid>,
    ) -> Result<()> {
        self.execute(
            "select record_event_purchase_refund_terminal_failed($1::uuid, $2::text, $3::text, $4::text, $5::uuid)",
            &[
                &event_purchase_refund_id,
                &expected_idempotency_key,
                &provider_refund_id,
                &failure_message,
                &expected_claim_id,
            ],
        )
        .await
    }

    /// [`DBPayments::reject_event_refund_request`].
    #[instrument(skip(self, review_note), err)]
    async fn reject_event_refund_request(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        event_purchase_id: Uuid,
        review_note: String,
    ) -> Result<CompletedEventPurchase> {
        self.fetch_json_one(
            "
            select reject_event_refund_request(
                $1::uuid,
                $2::uuid,
                $3::uuid,
                $4::text
            )
            ",
            &[&actor_user_id, &group_id, &event_purchase_id, &review_note],
        )
        .await
    }

    /// [`DBPayments::request_event_refund`].
    #[instrument(skip(self, requested_reason, notification_template_data), err)]
    async fn request_event_refund(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
        requested_reason: Option<String>,
        notification_template_data: serde_json::Value,
    ) -> Result<()> {
        self.execute(
            "
            select request_event_refund(
                $1::uuid,
                $2::uuid,
                $3::uuid,
                $4::text,
                $5::jsonb
            )
            ",
            &[
                &community_id,
                &event_id,
                &user_id,
                &requested_reason,
                &notification_template_data,
            ],
        )
        .await
    }

    /// [`DBPayments::requeue_event_purchase_application_fee_adjustment`].
    #[instrument(skip(self), err)]
    async fn requeue_event_purchase_application_fee_adjustment(
        &self,
        group_id: Uuid,
        adjustment_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select requeue_event_purchase_application_fee_adjustment($1::uuid, $2::uuid)",
            &[&group_id, &adjustment_id],
        )
        .await
    }

    /// [`DBPayments::requeue_event_purchase_credit_note`].
    #[instrument(skip(self), err)]
    async fn requeue_event_purchase_credit_note(
        &self,
        group_id: Uuid,
        credit_note_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select requeue_event_purchase_credit_note($1::uuid, $2::uuid)",
            &[&group_id, &credit_note_id],
        )
        .await
    }

    /// [`DBPayments::requeue_event_purchase_refund`].
    #[instrument(skip(self), err)]
    async fn requeue_event_purchase_refund(
        &self,
        group_id: Uuid,
        event_purchase_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select requeue_event_purchase_refund($1::uuid, $2::uuid)",
            &[&group_id, &event_purchase_id],
        )
        .await
    }

    /// [`DBPayments::requeue_stale_event_purchase_application_fee_adjustment_claims`].
    #[instrument(skip(self), err)]
    async fn requeue_stale_event_purchase_application_fee_adjustment_claims(&self) -> Result<i32> {
        self.fetch_scalar_one(
            "select requeue_stale_event_purchase_application_fee_adjustment_claims()",
            &[],
        )
        .await
    }

    /// [`DBPayments::requeue_stale_event_purchase_credit_note_claims`].
    #[instrument(skip(self), err)]
    async fn requeue_stale_event_purchase_credit_note_claims(&self) -> Result<i32> {
        self.fetch_scalar_one(
            "select requeue_stale_event_purchase_credit_note_claims()",
            &[],
        )
        .await
    }

    /// [`DBPayments::requeue_stale_event_purchase_refund_claims`].
    #[instrument(skip(self), err)]
    async fn requeue_stale_event_purchase_refund_claims(&self) -> Result<i32> {
        self.fetch_scalar_one("select requeue_stale_event_purchase_refund_claims()", &[])
            .await
    }

    /// [`DBPayments::sync_external_payments_config`].
    #[instrument(skip(self, config), err)]
    async fn sync_external_payments_config(
        &self,
        config: Option<crate::config::ExternalPaymentsConfig>,
    ) -> Result<()> {
        let allowed_countries = config
            .as_ref()
            .map(crate::config::ExternalPaymentsConfig::allowed_countries_normalized);
        let default_payment_window_hours =
            config.as_ref().map(|cfg| cfg.default_payment_window_hours);
        let max_payment_window_hours = config.as_ref().map(|cfg| cfg.max_payment_window_hours);

        self.execute(
            "
            select sync_external_payments_config(
                $1::text[],
                $2::int,
                $3::int
            )
            ",
            &[
                &allowed_countries,
                &default_payment_window_hours,
                &max_payment_window_hours,
            ],
        )
        .await
    }

    /// [`DBPayments::upsert_payment_provider_tax_location`].
    #[instrument(skip(self, venue), err)]
    async fn upsert_payment_provider_tax_location(
        &self,
        payment_provider: PaymentProvider,
        connected_seller_id: &str,
        fingerprint: &str,
        provider_tax_location_id: &str,
        venue: &TicketVenue,
    ) -> Result<()> {
        self.execute(
            "
            select upsert_payment_provider_tax_location(
                $1::text,
                $2::text,
                $3::text,
                $4::text,
                $5::jsonb
            )
            ",
            &[
                &payment_provider.to_string(),
                &connected_seller_id,
                &fingerprint,
                &provider_tax_location_id,
                &Json(venue),
            ],
        )
        .await
    }
}

// Types.

/// Claimed application-fee adjustment with immutable provider context.
#[derive(Debug, Clone, Deserialize)]
pub(crate) struct ClaimedEventPurchaseApplicationFeeAdjustment {
    /// Amount returned to the connected seller, in minor units.
    pub amount_minor: i64,
    /// Current worker claim identifier.
    pub claim_id: Uuid,
    /// Connected seller that owns the direct charge.
    pub connected_seller_id: String,
    /// Currency of the purchase and adjustment amount.
    pub currency_code: String,
    /// Durable adjustment identifier.
    pub event_purchase_application_fee_adjustment_id: Uuid,
    /// Purchase whose application fee is adjusted.
    pub event_purchase_id: Uuid,
    /// Stable provider idempotency key.
    pub idempotency_key: String,
    /// Adjustment reason.
    pub kind: String,
    /// Provider application fee being refunded.
    pub provider_application_fee_id: String,
}

/// Claimed credit-note creation with immutable invoice and refund context.
#[derive(Debug, Clone, Deserialize)]
pub(crate) struct ClaimedEventPurchaseCreditNote {
    /// Gross credit-note amount, in minor units.
    pub amount_minor: i64,
    /// Current worker claim identifier.
    pub claim_id: Uuid,
    /// Connected seller that owns the invoice and refund.
    pub connected_seller_id: String,
    /// Durable credit-note identifier.
    pub event_purchase_credit_note_id: Uuid,
    /// Purchase receiving the credit note.
    pub event_purchase_id: Uuid,
    /// Customer refund linked to the credit note.
    pub event_purchase_refund_id: Uuid,
    /// Stable provider idempotency key.
    pub idempotency_key: String,
    /// Provider invoice receiving the credit note.
    pub provider_invoice_id: String,
    /// Existing provider refund linked without creating another refund.
    pub provider_refund_id: String,
    /// Expected tax amount in the full credit.
    pub tax_amount_minor: i64,
}

/// Claimed refund work with the context required for atomic notification handoff.
#[derive(Debug, Clone, Deserialize)]
pub(crate) struct ClaimedEventPurchaseRefund {
    /// Connected account that owns a direct charge.
    pub connected_seller_id: String,
    /// Community identifier.
    pub community_id: Uuid,
    /// Event identifier.
    pub event_id: Uuid,
    /// Durable provider refund state.
    #[serde(flatten)]
    pub refund: EventPurchaseRefund,
}

impl Deref for ClaimedEventPurchaseRefund {
    type Target = EventPurchaseRefund;

    fn deref(&self) -> &Self::Target {
        &self.refund
    }
}

impl DerefMut for ClaimedEventPurchaseRefund {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.refund
    }
}

/// Data returned when a purchase is completed.
#[derive(Debug, Clone, Deserialize)]
pub(crate) struct CompletedEventPurchase {
    /// Community identifier.
    pub community_id: Uuid,
    /// Event identifier.
    pub event_id: Uuid,
    /// User identifier.
    pub user_id: Uuid,

    /// Whether this call performed the state transition.
    #[allow(dead_code)]
    #[serde(default)]
    pub transitioned: Option<bool>,
}

/// Input used to complete exhausted financial work outside OCG.
#[derive(Debug, Clone)]
pub(crate) struct CompleteEventPurchaseFinancialRecoveryInput {
    /// Operator completing the recovery.
    pub actor_user_id: Uuid,
    /// Group that owns the purchase.
    pub group_id: Uuid,
    /// Provider object created outside OCG.
    pub provider_object_id: String,
    /// Operator note describing the recovery evidence.
    pub recovery_note: String,
    /// External reference proving the recovery.
    pub recovery_reference: String,
    /// Durable financial-work identifier.
    pub work_id: Uuid,
}

/// Input used to complete an externally resolved refund recovery.
#[derive(Debug, Clone)]
pub(crate) struct CompleteEventPurchaseRefundRecoveryInput {
    /// Operator completing the recovery.
    pub actor_user_id: Uuid,
    /// Durable refund identifier.
    pub event_purchase_refund_id: Uuid,
    /// Group that owns the recovered purchase.
    pub group_id: Uuid,
    /// Operator note describing the recovery evidence.
    pub recovery_note: String,
    /// External reference proving the recovery.
    pub recovery_reference: String,

    /// Notification data composed before atomic completion.
    pub notification_template_data: Option<serde_json::Value>,
    /// Payment provider configured for queue reconciliation.
    pub payment_provider: Option<PaymentProvider>,
}

/// Identifiers used to compose purchase completion notifications.
#[derive(Debug, Clone, Deserialize)]
pub(crate) struct EventPurchaseNotificationContext {
    /// Community containing the event.
    pub community_id: Uuid,
    /// Event whose purchase needs a notification.
    pub event_id: Uuid,
}

/// Durable provider refund record used to reconcile local and provider state.
#[derive(Debug, Clone, Deserialize, Eq, PartialEq)]
pub(crate) struct EventPurchaseRefund {
    /// Provider refund amount in minor units.
    pub amount_minor: i64,
    /// Refund currency code.
    pub currency_code: String,
    /// Purchase identifier being refunded.
    pub event_purchase_id: Uuid,
    /// Durable refund identifier.
    pub event_purchase_refund_id: Uuid,
    /// Provider idempotency key used for refund creation.
    pub idempotency_key: String,
    /// Refund workflow that owns this record.
    pub kind: EventPurchaseRefundKind,
    /// Payments provider processing the refund.
    pub payment_provider: PaymentProvider,
    /// Current provider refund lifecycle status.
    pub status: EventPurchaseRefundStatus,
    /// Whether the provider reported a terminal failure requiring recovery.
    pub terminal_failure: bool,

    /// Number of provider reconciliation claims made so far.
    #[serde(default)]
    pub attempt_count: i32,
    /// Identity of the worker claim currently processing this refund.
    pub claim_id: Option<Uuid>,
    /// Most recent provider failure message.
    pub failure_message: Option<String>,
    /// Time when the local purchase state was finalized.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub finalized_at: Option<DateTime<Utc>>,
    /// Provider payment reference used to find or create the refund.
    pub provider_payment_reference: Option<String>,
    /// Provider-specific refund identifier once known.
    pub provider_refund_id: Option<String>,
    /// Time when the provider reported that the refund succeeded.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub provider_refunded_at: Option<DateTime<Utc>>,
}

/// Authoritative event context required to complete a refund recovery.
#[derive(Debug, Clone, Deserialize)]
pub(crate) struct EventPurchaseRefundRecoveryContext {
    /// Community containing the event.
    pub community_id: Uuid,
    /// Event whose purchase is being recovered.
    pub event_id: Uuid,
    /// Durable refund identifier.
    pub event_purchase_refund_id: Uuid,
    /// Whether recovery must enqueue the attendee completion notification.
    pub notification_required: bool,
}

/// Durable refund workflow kind.
#[derive(Debug, Clone, Copy, Deserialize, Eq, PartialEq, strum::Display)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum EventPurchaseRefundKind {
    /// Full refund caused by an organizer canceling one attendee's attendance.
    AttendanceCancellation,
    /// Automatic refund for a checkout that can no longer be fulfilled.
    AutomaticUnfulfillableCheckout,
    /// Automatic refund caused by an organizer canceling the event.
    EventCancellation,
    /// Organizer approval of an attendee refund request.
    RefundRequestApproval,
}

/// Durable provider refund lifecycle status.
#[derive(Debug, Clone, Copy, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum EventPurchaseRefundStatus {
    /// Local purchase and request state have been finalized.
    Finalized,
    /// A refund worker currently owns the durable job.
    Processing,
    /// Provider reconciliation failed transiently or terminally.
    ProviderFailed,
    /// Provider refund has not succeeded yet.
    ProviderPending,
    /// Provider refund succeeded and local finalization is pending or retrying.
    ProviderSucceeded,
}

/// Conflict returned while preparing an attendee checkout.
#[derive(Debug, Clone, Copy, Eq, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum PrepareEventCheckoutPurchaseConflict {
    /// The selected admission offer cannot apply a new discount code.
    AdmissionOfferPriceLocked,
    /// An active admission offer must be claimed through its dedicated checkout path.
    AdmissionOfferRequired,
    /// The selected admission offer is no longer claimable.
    AdmissionOfferUnavailable,
    /// The selected ticket requires payment setup that is currently unavailable.
    PaymentSetupUnavailable,
    /// The selected ticket cannot open a confirmation window before it expires.
    PaymentWindowUnavailable,
    /// The selected ticket tier is no longer active.
    TicketTypeInactive,
    /// The selected ticket tier has no current price.
    TicketTypePriceUnavailable,
    /// The selected ticket tier has no unallocated capacity.
    TicketTypeSoldOut,
    /// The selected ticket tier is not available to this checkout path.
    TicketTypeUnavailable,
}

/// Input used to prepare an attendee checkout purchase.
#[derive(Debug, Clone)]
pub(crate) struct PrepareEventCheckoutPurchaseInput {
    /// Event identifier.
    pub event_id: Uuid,
    /// Ticket type identifier.
    pub event_ticket_type_id: Uuid,
    /// Platform fee in basis points snapshotted on new purchases.
    pub platform_fee_bps: i32,
    /// User identifier.
    pub user_id: Uuid,

    /// Admission offer being claimed by the attendee.
    pub admission_offer_id: Option<Uuid>,
    /// Discount code provided by the attendee.
    pub discount_code: Option<String>,
    /// Payment provider configured for this deployment.
    pub payment_provider: Option<PaymentProvider>,
    /// Registration answers provided before checkout starts.
    pub registration_answers: Option<QuestionnaireAnswers>,
}

/// Result of preparing an attendee checkout purchase.
#[derive(Debug, Clone, PartialEq)]
pub(crate) enum PrepareEventCheckoutPurchaseResult {
    /// Checkout could not reserve the selected ticket.
    Conflict(PrepareEventCheckoutPurchaseConflict),
    /// Checkout purchase was created or reused.
    Prepared(Box<PreparedEventCheckout>),
}

/// Database output returned after preparing an attendee checkout purchase.
#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum PrepareEventCheckoutPurchaseOutput {
    /// Checkout could not reserve the selected ticket.
    Conflict {
        /// Conflict kind.
        conflict: PrepareEventCheckoutPurchaseConflict,
    },
    /// Checkout purchase was created or reused.
    Prepared(Box<PreparedEventCheckout>),
}

impl From<PrepareEventCheckoutPurchaseOutput> for PrepareEventCheckoutPurchaseResult {
    /// Converts database checkout preparation output into the caller-facing result.
    fn from(output: PrepareEventCheckoutPurchaseOutput) -> Self {
        match output {
            PrepareEventCheckoutPurchaseOutput::Conflict { conflict } => Self::Conflict(conflict),
            PrepareEventCheckoutPurchaseOutput::Prepared(checkout) => Self::Prepared(checkout),
        }
    }
}

/// Provider completion context used to reconcile a checkout purchase.
#[derive(Debug, Clone)]
pub(crate) struct ReconcileEventPurchaseForCheckoutSessionInput {
    /// Payments provider that owns the completed Checkout Session.
    pub payment_provider: PaymentProvider,
    /// Charge created by the Checkout `PaymentIntent`.
    pub provider_charge_id: String,
    /// Connected account that owns the direct-charge objects.
    pub provider_object_account_id: String,
    /// `PaymentIntent` created by Checkout.
    pub provider_payment_reference: String,
    /// Completed Checkout Session identifier.
    pub provider_session_id: String,
    /// Total amount collected from the attendee.
    pub provider_total_minor: i64,
    /// Tax included in or added to the ticket line.
    pub tax_amount_minor: i64,

    /// Asynchronously created application fee, when already available.
    pub provider_application_fee_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case", tag = "outcome")]
enum ReconcileEventPurchaseForCheckoutSessionOutput {
    /// Purchase completed successfully.
    Completed {
        /// Community that owns the event.
        community_id: Uuid,
        /// Purchased event identifier.
        event_id: Uuid,
        /// Purchasing user identifier.
        user_id: Uuid,
    },
    /// Purchase was already reconciled.
    Noop,
    /// Purchase cannot be fulfilled and its refund was durably queued.
    RefundQueued,
}

/// Result of reconciling a provider-backed purchase completion webhook.
#[derive(Debug, Clone)]
pub(crate) enum ReconcileEventPurchaseResult {
    /// The purchase was completed successfully.
    Completed(CompletedEventPurchase),
    /// No local work remains for this webhook.
    Noop,
    /// The purchase can no longer be fulfilled and its refund is queued.
    RefundQueued,
}

impl From<ReconcileEventPurchaseForCheckoutSessionOutput> for ReconcileEventPurchaseResult {
    fn from(value: ReconcileEventPurchaseForCheckoutSessionOutput) -> Self {
        match value {
            ReconcileEventPurchaseForCheckoutSessionOutput::Completed {
                community_id,
                event_id,
                user_id,
            } => Self::Completed(CompletedEventPurchase {
                community_id,
                event_id,
                user_id,

                transitioned: None,
            }),
            ReconcileEventPurchaseForCheckoutSessionOutput::Noop => Self::Noop,
            ReconcileEventPurchaseForCheckoutSessionOutput::RefundQueued => Self::RefundQueued,
        }
    }
}

/// Provider scope for an attendee-owned financial document.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub(crate) struct UserPurchaseDocumentContext {
    /// Connected seller that owns the invoice or credit note.
    pub connected_seller_id: String,
    /// Configured provider that owns the document.
    pub payment_provider: PaymentProvider,
    /// Durable provider invoice or credit-note identifier.
    pub provider_document_id: String,
}

#[cfg(test)]
mod tests {
    use serde_json::json;
    use uuid::Uuid;

    use super::{
        PrepareEventCheckoutPurchaseConflict, PrepareEventCheckoutPurchaseOutput,
        ReconcileEventPurchaseForCheckoutSessionOutput, ReconcileEventPurchaseResult,
    };

    #[test]
    fn prepare_event_checkout_purchase_output_maps_conflicts() {
        for (value, expected) in [
            (
                "admission-offer-price-locked",
                PrepareEventCheckoutPurchaseConflict::AdmissionOfferPriceLocked,
            ),
            (
                "admission-offer-required",
                PrepareEventCheckoutPurchaseConflict::AdmissionOfferRequired,
            ),
            (
                "admission-offer-unavailable",
                PrepareEventCheckoutPurchaseConflict::AdmissionOfferUnavailable,
            ),
            (
                "payment-setup-unavailable",
                PrepareEventCheckoutPurchaseConflict::PaymentSetupUnavailable,
            ),
            (
                "payment-window-unavailable",
                PrepareEventCheckoutPurchaseConflict::PaymentWindowUnavailable,
            ),
            (
                "ticket-type-inactive",
                PrepareEventCheckoutPurchaseConflict::TicketTypeInactive,
            ),
            (
                "ticket-type-price-unavailable",
                PrepareEventCheckoutPurchaseConflict::TicketTypePriceUnavailable,
            ),
            (
                "ticket-type-sold-out",
                PrepareEventCheckoutPurchaseConflict::TicketTypeSoldOut,
            ),
            (
                "ticket-type-unavailable",
                PrepareEventCheckoutPurchaseConflict::TicketTypeUnavailable,
            ),
        ] {
            let output: PrepareEventCheckoutPurchaseOutput =
                serde_json::from_value(json!({ "conflict": value })).unwrap();

            assert!(matches!(
                output,
                PrepareEventCheckoutPurchaseOutput::Conflict { conflict }
                    if conflict == expected
            ));
        }
    }

    #[test]
    fn reconcile_event_purchase_for_checkout_session_output_maps_completed() {
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let user_id = Uuid::new_v4();

        let output: ReconcileEventPurchaseForCheckoutSessionOutput =
            serde_json::from_value(json!({
                "outcome": "completed",
                "community_id": community_id,
                "event_id": event_id,
                "user_id": user_id
            }))
            .unwrap();

        match ReconcileEventPurchaseResult::from(output) {
            ReconcileEventPurchaseResult::Completed(completed) => {
                assert_eq!(completed.community_id, community_id);
                assert_eq!(completed.event_id, event_id);
                assert_eq!(completed.user_id, user_id);
            }
            _ => panic!("expected completed result"),
        }
    }

    #[test]
    fn reconcile_event_purchase_for_checkout_session_output_maps_noop() {
        let output: ReconcileEventPurchaseForCheckoutSessionOutput =
            serde_json::from_value(json!({
                "outcome": "noop"
            }))
            .unwrap();

        assert!(matches!(
            ReconcileEventPurchaseResult::from(output),
            ReconcileEventPurchaseResult::Noop
        ));
    }

    #[test]
    fn reconcile_event_purchase_for_checkout_session_output_maps_refund_queued() {
        let output: ReconcileEventPurchaseForCheckoutSessionOutput =
            serde_json::from_value(json!({
                "outcome": "refund_queued"
            }))
            .unwrap();

        assert!(matches!(
            ReconcileEventPurchaseResult::from(output),
            ReconcileEventPurchaseResult::RefundQueued
        ));
    }
}
