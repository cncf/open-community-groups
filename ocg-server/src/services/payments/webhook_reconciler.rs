//! Payments webhook reconciliation helpers.

use anyhow::Result;
use tracing::warn;
use uuid::Uuid;

use crate::{
    db::{
        DynDB,
        payments::{
            EventPurchaseRefund, EventPurchaseRefundStatus,
            ReconcileEventPurchaseForCheckoutSessionInput, ReconcileEventPurchaseResult,
        },
    },
    services::payments::{
        DynPaymentsProvider, FindRefundInput, GetCheckoutFinancialContextInput,
        PaymentsWebhookEvent, RefundPaymentResult, RefundPaymentStatus,
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
            PaymentsWebhookEvent::ApplicationFeeCreated {
                amount_minor,
                connected_account_id,
                is_live: _,
                provider_application_fee_id,
                provider_charge_id,
            } => {
                self.attach_application_fee(
                    amount_minor,
                    &connected_account_id,
                    &provider_application_fee_id,
                    &provider_charge_id,
                )
                .await
            }
            PaymentsWebhookEvent::CheckoutCompleted {
                connected_account_id,
                is_live: _,
                provider_session_id,
            } => {
                self.handle_completed_checkout(connected_account_id, &provider_session_id)
                    .await
            }
            PaymentsWebhookEvent::CheckoutExpired {
                connected_account_id,
                is_live: _,
                provider_session_id,
            } => {
                self.expire_checkout_session(connected_account_id, &provider_session_id)
                    .await
            }
            PaymentsWebhookEvent::InvoicePaid {
                connected_account_id,
                hosted_url,
                is_live: _,
                pdf_url,
                provider_invoice_id,
                purchase_id,
            } => {
                self.attach_invoice(
                    &connected_account_id,
                    &hosted_url,
                    pdf_url,
                    &provider_invoice_id,
                    purchase_id,
                )
                .await
            }
            PaymentsWebhookEvent::Noop => Ok(()),
            PaymentsWebhookEvent::RefundUpdated {
                amount_minor,
                connected_account_id,
                currency_code,
                is_live: _,
                provider_payment_reference,
                provider_refund_id,
                purchase_id,
                status,
            } => {
                self.handle_refund_updated(&RefundUpdatedInput {
                    amount_minor,
                    connected_account_id,
                    currency_code,
                    provider_payment_reference,
                    provider_refund_id,
                    purchase_id,
                    status,
                })
                .await
            }
        }
    }

    /// Attaches a platform application fee through its immutable direct-charge scope.
    async fn attach_application_fee(
        &self,
        amount_minor: i64,
        connected_account_id: &str,
        provider_application_fee_id: &str,
        provider_charge_id: &str,
    ) -> Result<()> {
        self.db
            .attach_application_fee_to_event_purchase(
                self.payments_provider.provider(),
                connected_account_id,
                provider_charge_id,
                provider_application_fee_id,
                amount_minor,
            )
            .await
    }

    /// Attaches a connected-account invoice to its purchase.
    async fn attach_invoice(
        &self,
        connected_account_id: &str,
        hosted_url: &str,
        pdf_url: Option<String>,
        provider_invoice_id: &str,
        purchase_id: Uuid,
    ) -> Result<()> {
        self.db
            .attach_invoice_to_event_purchase(
                purchase_id,
                connected_account_id,
                provider_invoice_id,
                hosted_url,
                pdf_url,
            )
            .await
    }

    /// Expires the local purchase hold for a checkout session reported as expired.
    async fn expire_checkout_session(
        &self,
        provider_object_account_id: String,
        provider_session_id: &str,
    ) -> Result<()> {
        self.db
            .expire_event_purchase_for_checkout_session(
                self.payments_provider.provider(),
                provider_object_account_id,
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
        provider_object_account_id: String,
        provider_session_id: &str,
    ) -> Result<()> {
        // Retrieve authoritative amounts and provider references in the seller account
        let financial_context = self
            .payments_provider
            .get_checkout_financial_context(&GetCheckoutFinancialContextInput {
                connected_seller_id: provider_object_account_id.clone(),
                provider_session_id: provider_session_id.to_string(),
            })
            .await?;

        // Reconcile the provider checkout session with the current local purchase state
        match self
            .db
            .reconcile_event_purchase_for_checkout_session(
                &ReconcileEventPurchaseForCheckoutSessionInput {
                    payment_provider: self.payments_provider.provider(),
                    provider_charge_id: financial_context.provider_charge_id,
                    provider_object_account_id,
                    provider_payment_reference: financial_context.provider_payment_reference,
                    provider_session_id: provider_session_id.to_string(),
                    provider_total_minor: financial_context.provider_total_minor,
                    tax_amount_minor: financial_context.tax_amount_minor,

                    provider_application_fee_id: financial_context.provider_application_fee_id,
                },
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
    async fn handle_refund_updated(&self, input: &RefundUpdatedInput) -> Result<()> {
        // Load the purchase and validated durable refund owning this provider event
        let purchase = self.db.get_event_purchase_summary(input.purchase_id).await?;
        Self::validate_provider_account(&purchase, &input.connected_account_id)?;
        let refund = self
            .load_validated_refund_for_event(
                &purchase,
                input.amount_minor,
                &input.currency_code,
                &input.provider_payment_reference,
            )
            .await?;
        // Validate the signed refund belongs to the expected provider operation
        let is_current_attempt = Self::validate_refund_event(
            &purchase,
            &refund,
            self.payments_provider.provider(),
            input.amount_minor,
            &input.currency_code,
            &input.provider_payment_reference,
            &input.provider_refund_id,
        )?;
        if !is_current_attempt {
            return Ok(());
        }

        // Ignore non-terminal updates after the provider attempt is pinned as failed
        if input.status != RefundPaymentStatus::Failed
            && refund.status == EventPurchaseRefundStatus::ProviderFailed
            && refund.terminal_failure
        {
            return Ok(());
        }

        // Preserve completed outcomes unless Stripe explicitly reports a later failure
        if input.status != RefundPaymentStatus::Failed
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
                &purchase,
                &refund,
                &input.provider_payment_reference,
                &input.provider_refund_id,
                input.status,
            )
            .await?;

        // Persist and reconcile the validated provider lifecycle transition
        self.reconcile_refund_status(refund, &input.provider_refund_id, status)
            .await
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
        purchase: &EventPurchaseSummary,
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
                connected_seller_id: purchase.provider_object_account_id.clone().ok_or_else(
                    || anyhow::anyhow!("purchase is missing connected seller account"),
                )?,
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

    /// Validates that a connected event belongs to the purchase's provider account.
    fn validate_provider_account(
        purchase: &EventPurchaseSummary,
        connected_account_id: &str,
    ) -> Result<()> {
        let expected_account_id = purchase.provider_object_account_id.as_deref();
        if expected_account_id != Some(connected_account_id) {
            return Err(anyhow::anyhow!(
                "webhook connected account does not match purchase"
            ));
        }

        Ok(())
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
        if purchase.provider_total_minor.unwrap_or(purchase.amount_minor) != amount_minor {
            return Err(anyhow::anyhow!(
                "refund webhook amount does not match purchase"
            ));
        }
        if purchase
            .currency_code
            .as_deref()
            .is_none_or(|purchase_currency| !purchase_currency.eq_ignore_ascii_case(currency_code))
        {
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

/// Normalized provider refund event fields used across validation phases.
struct RefundUpdatedInput {
    /// Refund amount reported by the provider.
    amount_minor: i64,
    /// Connected account that owns the refund.
    connected_account_id: String,
    /// Refund currency reported by the provider.
    currency_code: String,
    /// `PaymentIntent` associated with the refund.
    provider_payment_reference: String,
    /// Provider refund identifier.
    provider_refund_id: String,
    /// Purchase identifier carried in provider metadata.
    purchase_id: Uuid,
    /// Current provider refund lifecycle status.
    status: RefundPaymentStatus,
}
