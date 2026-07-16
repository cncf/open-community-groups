//! Background processing for all provider-mediated event refunds.

use std::{future::Future, time::Duration};

use anyhow::{Context, Result, anyhow};
use tokio::time::sleep;
use tokio_util::{sync::CancellationToken, task::TaskTracker};
use tracing::{error, instrument, warn};

use crate::{
    config::HttpServerConfig,
    db::{DynDB, payments::ClaimedEventPurchaseRefund},
    services::notifications::DynNotificationsManager,
};

use super::{
    DynPaymentsProvider, FindRefundInput, RefundPaymentInput,
    notification_composer::PaymentsNotificationComposer,
    refund_recorder::{RecordedProviderRefund, persist_provider_refund_result},
};

#[cfg(test)]
mod tests;

/// Number of workers that recover stale refund claims.
const NUM_REFUND_RECOVERY_WORKERS: usize = 1;
/// Number of workers that reconcile provider refunds.
const NUM_REFUND_WORKERS: usize = 2;
/// Pause after a worker iteration fails.
const PAUSE_ON_ERROR: Duration = Duration::from_secs(10);
/// Pause when no refund work is available.
const PAUSE_ON_NONE: Duration = Duration::from_secs(15);
/// Interval between stale-claim recovery attempts.
const PAUSE_ON_RECOVERY: Duration = Duration::from_mins(1);

/// Starts provider refund and abandoned-claim recovery workers.
pub(crate) fn start_refund_workers(
    db: &DynDB,
    notifications_manager: DynNotificationsManager,
    payments_provider: Option<&DynPaymentsProvider>,
    server_cfg: HttpServerConfig,
    task_tracker: &TaskTracker,
    cancellation_token: &CancellationToken,
) {
    let notification_composer =
        PaymentsNotificationComposer::new(db.clone(), notifications_manager, server_cfg);

    // Start provider workers even when this deployment has no configured provider
    for _ in 0..NUM_REFUND_WORKERS {
        let worker = RefundWorker {
            cancellation_token: cancellation_token.clone(),
            db: db.clone(),
            notification_composer: notification_composer.clone(),
            payments_provider: payments_provider.cloned(),
        };
        task_tracker.spawn(async move {
            worker.run().await;
        });
    }

    // Start stale-claim recovery independently from provider configuration
    for _ in 0..NUM_REFUND_RECOVERY_WORKERS {
        let worker = RefundRecoveryWorker {
            cancellation_token: cancellation_token.clone(),
            db: db.clone(),
        };
        task_tracker.spawn(async move {
            worker.run().await;
        });
    }
}

/// Waits for work to finish while giving graceful cancellation priority.
async fn run_until_cancelled<T>(
    cancellation_token: &CancellationToken,
    future: impl Future<Output = T>,
) -> Option<T> {
    tokio::select! {
        biased;
        () = cancellation_token.cancelled() => None,
        result = future => Some(result),
    }
}

/// Processes durable refund jobs for the configured provider.
struct RefundWorker {
    /// Coordinates graceful worker shutdown.
    cancellation_token: CancellationToken,
    /// Persists durable refund lifecycle transitions.
    db: DynDB,
    /// Enqueues attendee notifications after local finalization.
    notification_composer: PaymentsNotificationComposer,
    /// Provider used to find or create refunds when configured.
    payments_provider: Option<DynPaymentsProvider>,
}

impl RefundWorker {
    /// Processes refunds until graceful shutdown.
    async fn run(&self) {
        loop {
            // Stop before claiming more work after graceful shutdown begins
            if self.cancellation_token.is_cancelled() {
                break;
            }

            // Process one refund while allowing shutdown to leave its claim for recovery
            let Some(result) =
                run_until_cancelled(&self.cancellation_token, self.process_next_refund()).await
            else {
                break;
            };

            // Continue after completed work or select the appropriate idle/error backoff
            let pause = match result {
                Ok(true) => None,
                Ok(false) => Some(PAUSE_ON_NONE),
                Err(err) => {
                    // Report processing failures once at the worker boundary
                    error!(error = %err, "error processing event purchase refund");
                    Some(PAUSE_ON_ERROR)
                }
            };

            // Apply the selected backoff without delaying graceful shutdown
            if let Some(pause) = pause {
                tokio::select! {
                    () = sleep(pause) => {},
                    () = self.cancellation_token.cancelled() => break,
                }
            }

            // Avoid another claim when cancellation raced with this iteration
            if self.cancellation_token.is_cancelled() {
                break;
            }
        }
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
            .build_refund_approval_template_data(refund.community_id, refund.event_id)
            .await
            .context("failed to build refund approval notification")?;

        // Finalize state and enqueue its completion notification atomically
        self.db
            .finalize_event_purchase_refund(
                refund.event_purchase_refund_id,
                claim_id,
                notification_template_data,
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

/// Recovers claims abandoned by interrupted workers.
struct RefundRecoveryWorker {
    /// Coordinates graceful recovery-worker shutdown.
    cancellation_token: CancellationToken,
    /// Requeues durable refund claims abandoned by interrupted workers.
    db: DynDB,
}

impl RefundRecoveryWorker {
    /// Requeues stale claims until graceful shutdown.
    async fn run(&self) {
        loop {
            // Stop before requeueing more claims after graceful shutdown begins
            if self.cancellation_token.is_cancelled() {
                break;
            }

            // Run one stale-claim sweep while allowing shutdown to interrupt the wait
            let Some(result) = run_until_cancelled(
                &self.cancellation_token,
                self.db.requeue_stale_event_purchase_refund_claims(),
            )
            .await
            else {
                break;
            };

            // Report meaningful recovery activity and failures at the worker boundary
            match result {
                Ok(recovered) if recovered > 0 => {
                    warn!(recovered, "requeued stale event purchase refund claims");
                }
                Ok(_) => {}
                Err(err) => error!(error = %err, "error recovering event purchase refund claims"),
            }

            // Preserve the recovery cadence without delaying graceful shutdown
            tokio::select! {
                () = sleep(PAUSE_ON_RECOVERY) => {},
                () = self.cancellation_token.cancelled() => break,
            }
        }
    }
}
