//! Payments webhook reconciliation helpers.

use anyhow::Result;
use tracing::warn;
use uuid::Uuid;

use crate::{
    db::{
        DynDB,
        payments::{
            EventPurchaseRefund, EventPurchaseRefundKind, EventPurchaseRefundStatus,
            ReconcileEventPurchaseResult, RefundRequiredEventPurchase,
        },
    },
    services::payments::{
        DynPaymentsProvider, FindRefundInput, PaymentsWebhookEvent, RefundPaymentInput,
        RefundPaymentResult, RefundPaymentStatus,
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

    /// Finalizes an automatic refund when the provider has completed it.
    async fn finalize_automatic_refund(&self, refund: EventPurchaseRefund) -> Result<()> {
        // Ignore provider attempts that have not completed successfully
        if !matches!(
            refund.status,
            EventPurchaseRefundStatus::Finalized | EventPurchaseRefundStatus::ProviderSucceeded
        ) {
            return Ok(());
        }

        // Require the provider identifier before local finalization
        let provider_refund_id = refund
            .provider_refund_id
            .ok_or_else(|| anyhow::anyhow!("provider refund id is missing after refund"))?;

        // Persist the completed automatic refund locally
        self.db
            .record_automatic_refund_for_event_purchase(
                refund.event_purchase_id,
                provider_refund_id,
            )
            .await
            .map_err(|err| {
                warn!(error = %err, "failed to persist automatic refund");
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
            Ok(ReconcileEventPurchaseResult::Noop) => Ok(()),
            Ok(ReconcileEventPurchaseResult::RefundRequired(refund_purchase)) => {
                // Refund checkouts that can no longer be finalized safely
                self.refund_unfulfillable_purchase(refund_purchase).await
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
        let kind = refund.kind;

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

        // Confirm an unpinned success against current provider state before accepting it
        let status = if status == RefundPaymentStatus::Succeeded
            && refund.status == EventPurchaseRefundStatus::ProviderFailed
            && refund.provider_refund_id.is_none()
        {
            self.reconcile_unpinned_refund_status(&purchase, provider_refund_id)
                .await?
        } else {
            status
        };

        // Ignore non-terminal updates after the provider attempt is pinned as failed
        if status != RefundPaymentStatus::Failed
            && refund.status == EventPurchaseRefundStatus::ProviderFailed
            && refund.provider_refund_id.is_some()
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
            return if kind == EventPurchaseRefundKind::AutomaticUnfulfillableCheckout {
                self.finalize_automatic_refund(refund).await
            } else {
                Ok(())
            };
        }

        // Persist and reconcile the validated provider lifecycle transition
        self.reconcile_refund_status(refund, provider_refund_id, status).await
    }

    /// Loads or creates the durable refund record for a webhook purchase.
    async fn load_refund_for_purchase(
        &self,
        purchase: &EventPurchaseSummary,
    ) -> Result<EventPurchaseRefund> {
        match purchase.status {
            EventPurchaseStatus::RefundPending => {
                self.db
                    .ensure_event_purchase_refund_started(
                        purchase.event_purchase_id,
                        self.payments_provider.provider(),
                        EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
                    )
                    .await
            }
            EventPurchaseStatus::RefundRequested => {
                self.db
                    .ensure_event_purchase_refund_started(
                        purchase.event_purchase_id,
                        self.payments_provider.provider(),
                        EventPurchaseRefundKind::RefundRequestApproval,
                    )
                    .await
            }
            EventPurchaseStatus::Refunded | EventPurchaseStatus::RefundRecoveryPending => {
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
        let kind = refund.kind;

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

        // Apply webhook acknowledgement and automatic finalization policy
        match recorded_refund {
            RecordedProviderRefund::Pending(refund) | RecordedProviderRefund::Succeeded(refund)
                if kind == EventPurchaseRefundKind::AutomaticUnfulfillableCheckout =>
            {
                self.finalize_automatic_refund(refund).await
            }
            RecordedProviderRefund::Failed
            | RecordedProviderRefund::Pending(_)
            | RecordedProviderRefund::Succeeded(_) => Ok(()),
        }
    }

    /// Reconciles an unpinned success event with the provider's current refund state.
    async fn reconcile_unpinned_refund_status(
        &self,
        purchase: &EventPurchaseSummary,
        provider_refund_id: &str,
    ) -> Result<RefundPaymentStatus> {
        // Require the payment reference used to scope the provider lookup
        let provider_payment_reference = purchase
            .provider_payment_reference
            .clone()
            .ok_or_else(|| anyhow::anyhow!("provider payment reference is missing"))?;

        // Load the named refund so an out-of-order success cannot revive a failed attempt
        let provider_refund = self
            .payments_provider
            .find_refund(&FindRefundInput {
                amount_minor: purchase.amount_minor,
                provider_payment_reference,
                purchase_id: purchase.event_purchase_id,

                provider_refund_id: Some(provider_refund_id.to_string()),
            })
            .await?
            .ok_or_else(|| anyhow::anyhow!("provider refund not found"))?;

        if provider_refund.provider_refund_id != provider_refund_id {
            return Err(anyhow::anyhow!(
                "provider refund lookup returned a different refund"
            ));
        }

        Ok(provider_refund.status)
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

    /// Records a provider refund result.
    async fn record_provider_refund_result(
        &self,
        refund: &EventPurchaseRefund,
        provider_refund: RefundPaymentResult,
    ) -> Result<EventPurchaseRefund> {
        // Persist the normalized result before applying automatic-refund policy
        match persist_provider_refund_result(&self.db, refund, provider_refund).await? {
            RecordedProviderRefund::Failed => Err(anyhow::anyhow!("provider refund failed")),
            RecordedProviderRefund::Pending(refund) | RecordedProviderRefund::Succeeded(refund) => {
                Ok(refund)
            }
        }
    }

    /// Refunds an unfulfillable purchase and records the provider result locally.
    async fn refund_unfulfillable_purchase(
        &self,
        refund_purchase: RefundRequiredEventPurchase,
    ) -> Result<()> {
        // Persist the refund handoff before calling the provider
        let refund = self
            .db
            .ensure_event_purchase_refund_started(
                refund_purchase.event_purchase_id,
                self.payments_provider.provider(),
                EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
            )
            .await
            .map_err(|err| {
                warn!(error = %err, "failed to start automatic refund record");
                err
            })?;

        // Reconcile or create the provider refund from the durable handoff
        let refund = self.resolve_provider_refund(&refund_purchase, refund).await?;

        // Finalize local state only after provider success
        self.finalize_automatic_refund(refund).await
    }

    /// Records or reuses the provider refund for a durable purchase refund.
    async fn resolve_provider_refund(
        &self,
        refund_purchase: &RefundRequiredEventPurchase,
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
        match self
            .payments_provider
            .find_refund(&FindRefundInput {
                amount_minor: refund_purchase.amount_minor,
                provider_payment_reference: refund_purchase.provider_payment_reference.clone(),
                purchase_id: refund_purchase.event_purchase_id,

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
        let provider_refund = self
            .payments_provider
            .refund_payment(&RefundPaymentInput {
                amount_minor: refund_purchase.amount_minor,
                idempotency_key: refund.idempotency_key.clone(),
                provider_payment_reference: refund_purchase.provider_payment_reference.clone(),
                purchase_id: refund_purchase.event_purchase_id,
            })
            .await
            .map_err(|err| {
                warn!(error = %err, "failed to refund purchase");
                err
            });

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
