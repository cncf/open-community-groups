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
    },
    types::payments::EventPurchaseStatus,
};

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
                purchase_id,
                provider_refund_id,
                status,
            } => {
                self.handle_refund_updated(purchase_id, provider_refund_id, status)
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
        purchase_id: Uuid,
        provider_refund_id: String,
        status: RefundPaymentStatus,
    ) -> Result<()> {
        // Load the purchase to identify the refund workflow owning this event
        let purchase = self.db.get_event_purchase_summary(purchase_id).await?;
        let kind = match purchase.status {
            EventPurchaseStatus::RefundPending => {
                EventPurchaseRefundKind::AutomaticUnfulfillableCheckout
            }
            EventPurchaseStatus::RefundRequested => EventPurchaseRefundKind::RefundRequestApproval,
            EventPurchaseStatus::Refunded => return Ok(()),
            _ => return Err(anyhow::anyhow!("event purchase is not awaiting a refund")),
        };

        // Ensure legacy in-flight refunds gain a durable record during rollout
        let refund = self
            .db
            .ensure_event_purchase_refund_started(
                purchase_id,
                self.payments_provider.provider(),
                kind,
            )
            .await?;

        // Handle provider-complete refunds without downgrading local state
        if matches!(
            refund.status,
            EventPurchaseRefundStatus::Finalized | EventPurchaseRefundStatus::ProviderSucceeded
        ) {
            return if kind == EventPurchaseRefundKind::AutomaticUnfulfillableCheckout {
                self.finalize_automatic_refund(refund).await
            } else {
                Ok(())
            };
        }

        // Do not let delayed pending events revive a terminal provider attempt
        if status == RefundPaymentStatus::Pending
            && refund.status == EventPurchaseRefundStatus::ProviderFailed
            && refund.provider_refund_id.is_none()
        {
            return Ok(());
        }

        // Ignore stale non-success events after a newer provider attempt starts
        if status != RefundPaymentStatus::Succeeded
            && refund
                .provider_refund_id
                .as_deref()
                .is_some_and(|current_id| current_id != provider_refund_id.as_str())
        {
            return Ok(());
        }

        // Persist and reconcile the provider lifecycle transition
        match status {
            RefundPaymentStatus::Pending => {
                let refund = self
                    .db
                    .record_event_purchase_refund_pending(
                        refund.event_purchase_refund_id,
                        refund.idempotency_key.clone(),
                        provider_refund_id,
                    )
                    .await?;

                if kind == EventPurchaseRefundKind::AutomaticUnfulfillableCheckout {
                    self.finalize_automatic_refund(refund).await
                } else {
                    Ok(())
                }
            }
            RefundPaymentStatus::Succeeded => {
                let refund = self
                    .db
                    .record_event_purchase_refund_succeeded(
                        refund.event_purchase_refund_id,
                        provider_refund_id,
                    )
                    .await?;

                if kind == EventPurchaseRefundKind::AutomaticUnfulfillableCheckout {
                    self.finalize_automatic_refund(refund).await
                } else {
                    Ok(())
                }
            }
            RefundPaymentStatus::Failed => {
                // Rotate only the current non-terminal provider attempt
                if refund.provider_refund_id.is_some()
                    || refund.status != EventPurchaseRefundStatus::ProviderFailed
                {
                    self.db
                        .record_event_purchase_refund_terminal_failed(
                            refund.event_purchase_refund_id,
                            refund.idempotency_key.clone(),
                            provider_refund_id,
                            "provider refund failed".to_string(),
                        )
                        .await?;
                }

                // Leave terminal failures durable for an explicit retry outside the webhook
                Ok(())
            }
        }
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
            warn!(error = %record_err, "failed to record automatic provider refund failure");
        }
    }

    /// Records a provider refund result.
    async fn record_provider_refund_result(
        &self,
        refund: &EventPurchaseRefund,
        provider_refund: RefundPaymentResult,
    ) -> Result<EventPurchaseRefund> {
        // Persist the provider lifecycle outcome
        match provider_refund.status {
            RefundPaymentStatus::Succeeded => self
                .db
                .record_event_purchase_refund_succeeded(
                    refund.event_purchase_refund_id,
                    provider_refund.provider_refund_id,
                )
                .await
                .map_err(|err| {
                    warn!(error = %err, "failed to record automatic provider refund");
                    err
                }),
            RefundPaymentStatus::Pending => self
                .db
                .record_event_purchase_refund_pending(
                    refund.event_purchase_refund_id,
                    refund.idempotency_key.clone(),
                    provider_refund.provider_refund_id,
                )
                .await
                .map_err(|err| {
                    warn!(error = %err, "failed to record pending automatic provider refund");
                    err
                }),
            RefundPaymentStatus::Failed => {
                self.db
                    .record_event_purchase_refund_terminal_failed(
                        refund.event_purchase_refund_id,
                        refund.idempotency_key.clone(),
                        provider_refund.provider_refund_id,
                        "provider refund failed".to_string(),
                    )
                    .await
                    .map_err(|err| {
                        warn!(error = %err, "failed to record terminal automatic provider refund failure");
                        err
                    })?;
                Err(anyhow::anyhow!("provider refund failed"))
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

    /// Records or reuses the provider refund for an unfulfillable checkout.
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
                warn!(error = %err, "failed to find existing automatic provider refund");
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
                warn!(error = %err, "failed to refund unfulfillable purchase");
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
}
