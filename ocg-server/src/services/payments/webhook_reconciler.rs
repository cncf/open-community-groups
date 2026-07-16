//! Payments webhook reconciliation helpers.

use anyhow::Result;
use tracing::warn;
use uuid::Uuid;

use crate::{
    db::{
        DynDB,
        payments::{EventPurchaseRefund, EventPurchaseRefundStatus, ReconcileEventPurchaseResult},
    },
    services::payments::{
        DynPaymentsProvider, FindRefundInput, PaymentsWebhookEvent, RefundPaymentResult,
        RefundPaymentStatus,
        notification_composer::PaymentsNotificationComposer,
        refund_recorder::{RecordedProviderRefund, persist_provider_refund_result},
    },
    types::payments::{EventPurchaseStatus, EventPurchaseSummary, PaymentProvider},
};

#[cfg(test)]
mod tests;

/// Reconciles verified payments webhook events with local purchase state.
#[derive(Clone)]
pub(super) struct PaymentsWebhookReconciler {
    /// Database handle for payment reconciliation.
    db: DynDB,
    /// Shared notification helper for completed purchases.
    notification_composer: PaymentsNotificationComposer,
    /// Provider adapter used to reconcile payment events.
    payments_provider: DynPaymentsProvider,
}

impl PaymentsWebhookReconciler {
    /// Creates a new payments webhook reconciler.
    pub(super) fn new(
        db: DynDB,
        notification_composer: PaymentsNotificationComposer,
        payments_provider: DynPaymentsProvider,
    ) -> Self {
        Self {
            db,
            notification_composer,
            payments_provider,
        }
    }

    /// Handles a verified payments webhook event.
    pub(super) async fn handle_webhook_event(
        &self,
        webhook_event: PaymentsWebhookEvent,
    ) -> Result<()> {
        match webhook_event {
            PaymentsWebhookEvent::CheckoutCompleted {
                provider_session_id,
                provider_payment_reference,
            } => {
                self.handle_completed_checkout(provider_payment_reference, &provider_session_id)
                    .await
            }
            PaymentsWebhookEvent::CheckoutExpired {
                provider_session_id,
            } => self.expire_checkout_session(&provider_session_id).await,
            PaymentsWebhookEvent::Noop => Ok(()),
            PaymentsWebhookEvent::RefundUpdated {
                amount_minor,
                currency_code,
                provider_payment_reference,
                provider_refund_id,
                purchase_id,
                status,
            } => {
                self.handle_refund_updated(
                    amount_minor,
                    &currency_code,
                    &provider_payment_reference,
                    &provider_refund_id,
                    purchase_id,
                    status,
                )
                .await
            }
        }
    }

    /// Expires the local purchase hold for a checkout session reported as expired.
    async fn expire_checkout_session(&self, provider_session_id: &str) -> Result<()> {
        self.db
            .expire_event_purchase_for_checkout_session(
                self.payments_provider.provider(),
                provider_session_id,
            )
            .await
            .map_err(|err| {
                warn!(error = %err, "failed to expire checkout session");
                err
            })
    }

    /// Reconciles a completed checkout session with local purchase state.
    async fn handle_completed_checkout(
        &self,
        provider_payment_reference: Option<String>,
        provider_session_id: &str,
    ) -> Result<()> {
        // Reconcile the provider checkout session with the current local purchase state
        match self
            .db
            .reconcile_event_purchase_for_checkout_session(
                self.payments_provider.provider(),
                provider_session_id,
                provider_payment_reference,
            )
            .await
        {
            Ok(ReconcileEventPurchaseResult::Completed(completed_purchase)) => {
                // Notify the attendee after the purchase is finalized locally
                self.notification_composer
                    .enqueue_checkout_completed_notification(completed_purchase)
                    .await;
                Ok(())
            }
            Ok(ReconcileEventPurchaseResult::Noop | ReconcileEventPurchaseResult::RefundQueued) => {
                Ok(())
            }
            Err(err) => {
                warn!(error = %err, "failed to reconcile purchase");
                Err(err)
            }
        }
    }

    /// Reconciles a provider refund lifecycle event with its durable local record.
    async fn handle_refund_updated(
        &self,
        amount_minor: i64,
        currency_code: &str,
        provider_payment_reference: &str,
        provider_refund_id: &str,
        purchase_id: Uuid,
        status: RefundPaymentStatus,
    ) -> Result<()> {
        // Load the purchase and validated durable refund owning this provider event
        let purchase = self.db.get_event_purchase_summary(purchase_id).await?;
        let refund = self
            .load_validated_refund_for_event(
                &purchase,
                amount_minor,
                currency_code,
                provider_payment_reference,
            )
            .await?;
        // Validate the signed refund belongs to the expected provider operation
        let is_current_attempt = Self::validate_refund_event(
            &purchase,
            &refund,
            self.payments_provider.provider(),
            amount_minor,
            currency_code,
            provider_payment_reference,
            provider_refund_id,
        )?;
        if !is_current_attempt {
            return Ok(());
        }

        // Ignore non-terminal updates after the provider attempt is pinned as failed
        if status != RefundPaymentStatus::Failed
            && refund.status == EventPurchaseRefundStatus::ProviderFailed
            && refund.terminal_failure
        {
            return Ok(());
        }

        // Preserve completed outcomes unless Stripe explicitly reports a later failure
        if status != RefundPaymentStatus::Failed
            && matches!(
                refund.status,
                EventPurchaseRefundStatus::Finalized | EventPurchaseRefundStatus::ProviderSucceeded
            )
        {
            return Ok(());
        }

        // Refresh unpinned success before trusting a potentially out-of-order webhook
        let status = self
            .refresh_unpinned_success_status(
                &refund,
                provider_payment_reference,
                provider_refund_id,
                status,
            )
            .await?;

        // Persist and reconcile the validated provider lifecycle transition
        self.reconcile_refund_status(refund, provider_refund_id, status).await
    }

    /// Loads or creates the durable refund record for a webhook purchase.
    async fn load_refund_for_purchase(
        &self,
        purchase: &EventPurchaseSummary,
    ) -> Result<EventPurchaseRefund> {
        match purchase.status {
            EventPurchaseStatus::RefundPending
            | EventPurchaseStatus::RefundRequested
            | EventPurchaseStatus::Refunded
            | EventPurchaseStatus::RefundRecoveryPending => {
                self.db.get_event_purchase_refund(purchase.event_purchase_id).await
            }
            _ => Err(anyhow::anyhow!("event purchase is not awaiting a refund")),
        }
    }

    /// Validates a provider event before loading its durable refund.
    async fn load_validated_refund_for_event(
        &self,
        purchase: &EventPurchaseSummary,
        amount_minor: i64,
        currency_code: &str,
        provider_payment_reference: &str,
    ) -> Result<EventPurchaseRefund> {
        // Validate financial ownership before loading durable refund state
        Self::validate_refund_purchase_event(
            purchase,
            amount_minor,
            currency_code,
            provider_payment_reference,
        )?;

        // Load the durable refund owning the validated event
        self.load_refund_for_purchase(purchase).await
    }

    /// Persists a validated provider refund status and applies webhook policy.
    async fn reconcile_refund_status(
        &self,
        refund: EventPurchaseRefund,
        provider_refund_id: &str,
        status: RefundPaymentStatus,
    ) -> Result<()> {
        // Persist the provider lifecycle transition
        let recorded_refund = persist_provider_refund_result(
            &self.db,
            &refund,
            RefundPaymentResult {
                provider_refund_id: provider_refund_id.to_string(),
                status,
            },
        )
        .await?;

        // Workers own local finalization after the provider lifecycle is durable
        match recorded_refund {
            RecordedProviderRefund::Failed
            | RecordedProviderRefund::Pending
            | RecordedProviderRefund::Succeeded => Ok(()),
        }
    }

    /// Refreshes current provider state before accepting an unpinned success event.
    async fn refresh_unpinned_success_status(
        &self,
        refund: &EventPurchaseRefund,
        provider_payment_reference: &str,
        provider_refund_id: &str,
        status: RefundPaymentStatus,
    ) -> Result<RefundPaymentStatus> {
        if status != RefundPaymentStatus::Succeeded || refund.provider_refund_id.is_some() {
            return Ok(status);
        }

        // Poll the exact named refund so stale success cannot override current provider state
        let provider_refund = self
            .payments_provider
            .find_refund(&FindRefundInput {
                amount_minor: refund.amount_minor,
                provider_payment_reference: provider_payment_reference.to_string(),
                purchase_id: refund.event_purchase_id,

                provider_refund_id: Some(provider_refund_id.to_string()),
            })
            .await?
            .ok_or_else(|| anyhow::anyhow!("provider refund not found"))?;

        if provider_refund.provider_refund_id != provider_refund_id {
            return Err(anyhow::anyhow!("provider refund id does not match webhook"));
        }

        Ok(provider_refund.status)
    }

    /// Validates a refund webhook against its purchase and durable provider attempt.
    fn validate_refund_event(
        purchase: &EventPurchaseSummary,
        refund: &EventPurchaseRefund,
        provider: PaymentProvider,
        amount_minor: i64,
        currency_code: &str,
        provider_payment_reference: &str,
        provider_refund_id: &str,
    ) -> Result<bool> {
        // Validate the signed financial contract before checking the durable attempt
        Self::validate_refund_purchase_event(
            purchase,
            amount_minor,
            currency_code,
            provider_payment_reference,
        )?;

        // Validate the durable provider and amount contract
        if refund.payment_provider != provider {
            return Err(anyhow::anyhow!(
                "refund webhook provider does not match purchase"
            ));
        }
        if refund.amount_minor != amount_minor {
            return Err(anyhow::anyhow!(
                "refund webhook amount does not match purchase"
            ));
        }

        // A different pinned refund belongs to a stale or unrelated provider attempt
        Ok(refund
            .provider_refund_id
            .as_deref()
            .is_none_or(|current_id| current_id == provider_refund_id))
    }

    /// Validates a signed refund's financial ownership before local state changes.
    fn validate_refund_purchase_event(
        purchase: &EventPurchaseSummary,
        amount_minor: i64,
        currency_code: &str,
        provider_payment_reference: &str,
    ) -> Result<()> {
        // Validate the signed financial fields against the persisted purchase
        if purchase.amount_minor != amount_minor {
            return Err(anyhow::anyhow!(
                "refund webhook amount does not match purchase"
            ));
        }
        if !purchase.currency_code.eq_ignore_ascii_case(currency_code) {
            return Err(anyhow::anyhow!(
                "refund webhook currency does not match purchase"
            ));
        }
        if purchase.provider_payment_reference.as_deref() != Some(provider_payment_reference) {
            return Err(anyhow::anyhow!(
                "refund webhook payment reference does not match purchase"
            ));
        }

        Ok(())
    }
}
