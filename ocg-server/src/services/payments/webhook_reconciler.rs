//! Payments webhook reconciliation helpers.

use anyhow::Result;
use tracing::warn;

use crate::{
    db::{
        DynDB,
        payments::{ReconcileEventPurchaseResult, RefundRequiredEventPurchase},
    },
    services::payments::{
        DynPaymentsProvider, PaymentsWebhookEvent, RefundPaymentInput,
        notification_composer::PaymentsNotificationComposer,
    },
};

/// Reconciles verified payments webhook events with local purchase state.
#[derive(Clone)]
pub(super) struct PaymentsWebhookReconciler {
    db: DynDB,
    notification_composer: PaymentsNotificationComposer,
    payments_provider: DynPaymentsProvider,
}

impl PaymentsWebhookReconciler {
    /// Create a new payments webhook reconciler.
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

    /// Handle a verified payments webhook event.
    pub(super) async fn handle_webhook_event(&self, webhook_event: PaymentsWebhookEvent) -> Result<()> {
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
            Ok(ReconcileEventPurchaseResult::Noop) => Ok(()),
            Ok(ReconcileEventPurchaseResult::RefundRequired(refund_purchase)) => {
                // Refund checkouts that can no longer be finalized safely
                self.refund_unfulfillable_checkout(refund_purchase).await
            }
            Err(err) => {
                warn!(error = %err, "failed to reconcile purchase");
                Err(err)
            }
        }
    }

    /// Refunds a checkout that could not be finalized and records the refund locally.
    async fn refund_unfulfillable_checkout(
        &self,
        refund_purchase: RefundRequiredEventPurchase,
    ) -> Result<()> {
        // Refund the payment with the configured provider before updating local state
        let refund = self
            .payments_provider
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

        // Persist the automatic refund so the purchase lifecycle remains consistent
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
}
