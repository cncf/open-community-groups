//! Database operations for payments, ticketing, and refunds.

use std::ops::{Deref, DerefMut};

use anyhow::Result;
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::Deserialize;
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::PgExecutor,
    services::payments::CheckoutSession,
    types::{
        payments::{EventPurchaseSummary, PaymentProvider, PreparedEventCheckout},
        questionnaire::QuestionnaireAnswers,
    },
};

/// Database operations for payments.
#[async_trait]
pub(crate) trait DBPayments {
    /// Adds the provider checkout session details to a pending purchase.
    async fn attach_checkout_session_to_event_purchase(
        &self,
        event_purchase_id: Uuid,
        provider: PaymentProvider,
        checkout_session: &CheckoutSession,
    ) -> Result<()>;

    /// Cancels an attendee's active pending checkout.
    async fn cancel_event_checkout(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
    ) -> Result<()>;

    /// Claims the next refund ready for the configured provider.
    async fn claim_event_purchase_refund(
        &self,
        provider: PaymentProvider,
    ) -> Result<Option<ClaimedEventPurchaseRefund>>;

    /// Completes an externally resolved terminal provider refund.
    async fn complete_event_purchase_refund_recovery(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        event_purchase_refund_id: Uuid,
        recovery_reference: String,
        recovery_note: String,
        notification_template_data: Option<serde_json::Value>,
    ) -> Result<()>;

    /// Completes a free purchase locally without a provider checkout.
    async fn complete_free_event_purchase(
        &self,
        event_purchase_id: Uuid,
    ) -> Result<CompletedEventPurchase>;

    /// Expires a pending purchase when its provider checkout session expires.
    async fn expire_event_purchase_for_checkout_session(
        &self,
        provider: PaymentProvider,
        provider_session_id: &str,
    ) -> Result<()>;

    /// Finalizes a provider-complete refund for the current worker claim.
    async fn finalize_event_purchase_refund(
        &self,
        event_purchase_refund_id: Uuid,
        claim_id: Uuid,
        notification_template_data: serde_json::Value,
    ) -> Result<()>;

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

    /// Prepares a checkout purchase for an attendee ticket purchase.
    async fn prepare_event_checkout_purchase(
        &self,
        community_id: Uuid,
        input: &PrepareEventCheckoutPurchaseInput,
    ) -> Result<PreparedEventCheckout>;

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
        provider: PaymentProvider,
        provider_session_id: &str,
        provider_payment_reference: Option<String>,
    ) -> Result<ReconcileEventPurchaseResult>;

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
        review_note: Option<String>,
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

    /// Requeues a retryable refund after an administrator requests another attempt.
    async fn requeue_event_purchase_refund(
        &self,
        group_id: Uuid,
        event_purchase_id: Uuid,
    ) -> Result<()>;

    /// Releases stale claims left by interrupted refund workers.
    async fn requeue_stale_event_purchase_refund_claims(&self) -> Result<i32>;
}

#[async_trait]
impl<T> DBPayments for T
where
    T: PgExecutor + Send + Sync,
{
    /// [`DBPayments::attach_checkout_session_to_event_purchase`].
    #[instrument(skip(self, checkout_session), err)]
    async fn attach_checkout_session_to_event_purchase(
        &self,
        event_purchase_id: Uuid,
        provider: PaymentProvider,
        checkout_session: &CheckoutSession,
    ) -> Result<()> {
        self.execute(
            "
            select attach_checkout_session_to_event_purchase(
                $1::uuid,
                $2::text,
                $3::text,
                $4::text
            )
            ",
            &[
                &event_purchase_id,
                &provider.to_string(),
                &checkout_session.provider_session_id,
                &checkout_session.redirect_url,
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
    ) -> Result<()> {
        self.execute(
            "select cancel_event_checkout($1::uuid, $2::uuid, $3::uuid)",
            &[&community_id, &event_id, &user_id],
        )
        .await
    }

    /// [`DBPayments::claim_event_purchase_refund`].
    #[instrument(skip(self), err)]
    async fn claim_event_purchase_refund(
        &self,
        provider: PaymentProvider,
    ) -> Result<Option<ClaimedEventPurchaseRefund>> {
        self.fetch_json_opt(
            "select claim_event_purchase_refund($1::text)",
            &[&provider.to_string()],
        )
        .await
    }

    /// [`DBPayments::complete_event_purchase_refund_recovery`].
    #[instrument(skip(self, recovery_note, notification_template_data), err)]
    async fn complete_event_purchase_refund_recovery(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        event_purchase_refund_id: Uuid,
        recovery_reference: String,
        recovery_note: String,
        notification_template_data: Option<serde_json::Value>,
    ) -> Result<()> {
        self.execute(
            "
            select complete_event_purchase_refund_recovery(
                $1::uuid,
                $2::uuid,
                $3::uuid,
                $4::text,
                $5::text,
                $6::jsonb
            )
            ",
            &[
                &actor_user_id,
                &group_id,
                &event_purchase_refund_id,
                &recovery_reference,
                &recovery_note,
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
        provider: PaymentProvider,
        provider_session_id: &str,
    ) -> Result<()> {
        self.execute(
            "select expire_event_purchase_for_checkout_session($1::text, $2::text)",
            &[&provider.to_string(), &provider_session_id],
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
    ) -> Result<()> {
        self.execute(
            "select finalize_event_purchase_refund($1::uuid, $2::uuid, $3::jsonb)",
            &[
                &event_purchase_refund_id,
                &claim_id,
                &Json(&notification_template_data),
            ],
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

    /// [`DBPayments::prepare_event_checkout_purchase`].
    #[instrument(skip(self, input), err)]
    async fn prepare_event_checkout_purchase(
        &self,
        community_id: Uuid,
        input: &PrepareEventCheckoutPurchaseInput,
    ) -> Result<PreparedEventCheckout> {
        self.fetch_json_one(
            "
            select prepare_event_checkout_purchase(
                $1::uuid,
                $2::uuid,
                $3::uuid,
                $4::uuid,
                $5::text,
                $6::text,
                $7::jsonb
            )
            ",
            &[
                &community_id,
                &input.event_id,
                &input.event_ticket_type_id,
                &input.user_id,
                &input.discount_code,
                &input.configured_provider.map(|provider| provider.to_string()),
                &input.registration_answers.as_ref().map(Json),
            ],
        )
        .await
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
        provider: PaymentProvider,
        provider_session_id: &str,
        provider_payment_reference: Option<String>,
    ) -> Result<ReconcileEventPurchaseResult> {
        let result: ReconcileEventPurchaseForCheckoutSessionOutput = self
            .fetch_json_one(
                "
                select reconcile_event_purchase_for_checkout_session(
                    $1::text,
                    $2::text,
                    $3::text
                )
                ",
                &[
                    &provider.to_string(),
                    &provider_session_id,
                    &provider_payment_reference,
                ],
            )
            .await?;

        Ok(result.into())
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
        review_note: Option<String>,
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

    /// [`DBPayments::requeue_stale_event_purchase_refund_claims`].
    #[instrument(skip(self), err)]
    async fn requeue_stale_event_purchase_refund_claims(&self) -> Result<i32> {
        self.fetch_scalar_one("select requeue_stale_event_purchase_refund_claims()", &[])
            .await
    }
}

// Types.

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
            }),
            ReconcileEventPurchaseForCheckoutSessionOutput::Noop => Self::Noop,
            ReconcileEventPurchaseForCheckoutSessionOutput::RefundQueued => Self::RefundQueued,
        }
    }
}

/// Claimed refund work with the context required for atomic notification handoff.
#[derive(Debug, Clone, Deserialize)]
pub(crate) struct ClaimedEventPurchaseRefund {
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

/// Input used to prepare an attendee checkout purchase.
#[derive(Debug, Clone)]
pub(crate) struct PrepareEventCheckoutPurchaseInput {
    /// Event identifier.
    pub event_id: Uuid,
    /// Ticket type identifier.
    pub event_ticket_type_id: Uuid,
    /// User identifier.
    pub user_id: Uuid,

    /// Configured payments provider for this deployment.
    pub configured_provider: Option<PaymentProvider>,
    /// Discount code provided by the attendee.
    pub discount_code: Option<String>,
    /// Registration answers provided before checkout starts.
    pub registration_answers: Option<QuestionnaireAnswers>,
}

#[cfg(test)]
mod tests {
    use serde_json::json;
    use uuid::Uuid;

    use super::{ReconcileEventPurchaseForCheckoutSessionOutput, ReconcileEventPurchaseResult};

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
