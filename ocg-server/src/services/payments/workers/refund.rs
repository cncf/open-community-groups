//! Background processing for all provider-mediated event refunds.

use anyhow::{Context, Result, anyhow};
use tokio_util::sync::CancellationToken;
use tracing::{error, instrument, warn};

use crate::{
    config::HttpServerConfig,
    db::{DynDB, payments::ClaimedEventPurchaseRefund},
    services::{
        notifications::DynNotificationsManager,
        workers::{
            BackgroundTasks,
            claim_loop::{self, ClaimLoopConfig},
        },
    },
};

use super::super::{
    DynPaymentsProvider, FindRefundInput, RefundPaymentInput,
    notification_composer::PaymentsNotificationComposer,
    refund_recorder::{RecordedProviderRefund, persist_provider_refund_result},
};

#[cfg(test)]
mod tests;

/// Number of workers that reconcile provider refunds.
const NUM_WORKERS: usize = 2;

/// Starts provider refund workers.
pub(in crate::services::payments) fn start(
    db: &DynDB,
    notifications_manager: DynNotificationsManager,
    payments_provider: Option<&DynPaymentsProvider>,
    server_cfg: HttpServerConfig,
    background_tasks: &BackgroundTasks,
) {
    let notification_composer =
        PaymentsNotificationComposer::new(db.clone(), notifications_manager, server_cfg);

    // Start provider workers even when this deployment has no configured provider
    for _ in 0..NUM_WORKERS {
        let worker = Worker {
            cancellation_token: background_tasks.cancellation_token(),
            db: db.clone(),
            notification_composer: notification_composer.clone(),
            payments_provider: payments_provider.cloned(),
        };
        background_tasks.spawn(async move {
            worker.run().await;
        });
    }
}

/// Processes durable refund jobs for the configured provider.
struct Worker {
    /// Coordinates graceful worker shutdown.
    cancellation_token: CancellationToken,
    /// Persists durable refund lifecycle transitions.
    db: DynDB,
    /// Enqueues attendee notifications after local finalization.
    notification_composer: PaymentsNotificationComposer,
    /// Provider used to find or create refunds when configured.
    payments_provider: Option<DynPaymentsProvider>,
}

impl Worker {
    /// Processes refunds until graceful shutdown.
    async fn run(&self) {
        // Delegate payment-specific claim cadence while preserving this error boundary
        claim_loop::run(
            &self.cancellation_token,
            ClaimLoopConfig::default(),
            || self.process_next_refund(),
            |err| {
                error!(error = %err, "error processing event purchase refund");
                None
            },
        )
        .await;
    }

    /// Finalizes local state and atomically queues its completion notification.
    async fn finalize_refund(&self, refund: &ClaimedEventPurchaseRefund) -> Result<()> {
        // Validate claim ownership before committing terminal local state
        let claim_id = refund
            .claim_id
            .ok_or_else(|| anyhow!("event purchase refund claim id is missing"))?;

        // Build the durable notification payload before finalizing local state
        let notification_template_data = self
            .notification_composer
            .build_refund_approval_template_data(refund.community_id, refund.event_id, false)
            .await
            .context("failed to build refund approval notification")?;

        // Finalize state and enqueue its completion notification atomically
        self.db
            .finalize_event_purchase_refund(
                refund.event_purchase_refund_id,
                claim_id,
                notification_template_data,
                Some(refund.payment_provider),
            )
            .await?;

        Ok(())
    }

    /// Claims and processes one durable refund job.
    #[instrument(skip(self), err)]
    async fn process_next_refund(&self) -> Result<bool> {
        // Leave durable jobs unclaimed when this worker has no configured provider
        let Some(payments_provider) = self.payments_provider.as_ref() else {
            return Ok(false);
        };

        // Claim one provider-specific job before reconciling external state
        let Some(refund) = self
            .db
            .claim_event_purchase_refund(payments_provider.provider())
            .await?
        else {
            return Ok(false);
        };

        // Finalize persisted success directly or reconcile the provider first
        let result = if refund.provider_refunded_at.is_some() {
            self.finalize_refund(&refund).await
        } else {
            self.reconcile_provider_refund(payments_provider, &refund).await
        };

        // Release the claim when either provider reconciliation or finalization fails
        if let Err(err) = result {
            self.release_retryable_failure(&refund, &err).await;
            return Err(err);
        }

        Ok(true)
    }

    /// Finds an existing provider refund or creates it with the stable idempotency key.
    async fn reconcile_provider_refund(
        &self,
        payments_provider: &DynPaymentsProvider,
        refund: &ClaimedEventPurchaseRefund,
    ) -> Result<()> {
        // Require the original payment reference before querying the provider
        let provider_payment_reference = refund
            .provider_payment_reference
            .clone()
            .ok_or_else(|| anyhow!("provider payment reference is missing"))?;

        // Reuse provider state when a prior attempt may have created the refund
        let provider_refund = payments_provider
            .find_refund(&FindRefundInput {
                amount_minor: refund.amount_minor,
                connected_seller_id: refund.connected_seller_id.clone(),
                provider_payment_reference: provider_payment_reference.clone(),
                purchase_id: refund.event_purchase_id,

                provider_refund_id: refund.provider_refund_id.clone(),
            })
            .await?;

        // Create only when no provider refund exists and no pinned refund disappeared
        let provider_refund = match provider_refund {
            Some(provider_refund) => provider_refund,
            None if refund.provider_refund_id.is_some() => {
                return Err(anyhow!("provider refund not found"));
            }
            None => {
                payments_provider
                    .refund_payment(&RefundPaymentInput {
                        amount_minor: refund.amount_minor,
                        connected_seller_id: refund.connected_seller_id.clone(),
                        idempotency_key: refund.idempotency_key.clone(),
                        provider_payment_reference,
                        purchase_id: refund.event_purchase_id,
                    })
                    .await?
            }
        };

        // Persist the provider result before finalizing local attendance and purchase state
        match persist_provider_refund_result(&self.db, &refund.refund, provider_refund).await? {
            RecordedProviderRefund::Failed | RecordedProviderRefund::Pending => Ok(()),
            RecordedProviderRefund::Succeeded => self.finalize_refund(refund).await,
        }
    }

    /// Releases the current claim without hiding the provider error.
    async fn release_retryable_failure(
        &self,
        refund: &ClaimedEventPurchaseRefund,
        err: &anyhow::Error,
    ) {
        let Some(claim_id) = refund.claim_id else {
            return;
        };
        if let Err(record_err) = self
            .db
            .record_event_purchase_refund_retryable_failure(
                refund.event_purchase_refund_id,
                claim_id,
                err.to_string(),
            )
            .await
        {
            warn!(error = %record_err, "failed to release event purchase refund claim");
        }
    }
}
