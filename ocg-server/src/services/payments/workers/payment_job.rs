//! Background processing for provider-mediated payment jobs.

use std::sync::atomic::{AtomicUsize, Ordering};

use anyhow::Result;
use tokio_util::sync::CancellationToken;
use tracing::{debug, error, instrument, warn};

use crate::{
    config::HttpServerConfig,
    db::{
        DynDB,
        payments::{ClaimedPaymentJob, ClaimedPaymentJobWork},
    },
    services::{
        notifications::DynNotificationsManager,
        workers::{
            BackgroundTasks,
            claim_loop::{self, ClaimLoopConfig},
        },
    },
    types::payments::PaymentJobKind,
};

use super::super::{DynPaymentsProvider, notification_composer::PaymentsNotificationComposer};

mod application_fee_adjustment;
mod credit_note;
mod refund;

#[cfg(test)]
mod tests;

/// Number of workers that process payment jobs.
const NUM_WORKERS: usize = 2;

/// Starts provider-mediated payment job workers.
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
            next_kind_index: AtomicUsize::new(0),
            notification_composer: notification_composer.clone(),
            payments_provider: payments_provider.cloned(),
        };
        background_tasks.spawn("payments-jobs", async move {
            worker.run().await;
        });
    }
}

/// Processes durable payment jobs for the configured provider.
struct Worker {
    /// Coordinates graceful worker shutdown.
    cancellation_token: CancellationToken,
    /// Persists durable payment job lifecycle transitions.
    db: DynDB,
    /// Position in [`PaymentJobKind::ALL`] that the next iteration claims first.
    ///
    /// Rotating the starting kind gives every queue a first claim in turn, so a
    /// continuously busy kind cannot starve the others.
    next_kind_index: AtomicUsize,
    /// Enqueues attendee notifications after local refund finalization.
    notification_composer: PaymentsNotificationComposer,

    /// Provider used to process payment jobs when configured.
    payments_provider: Option<DynPaymentsProvider>,
}

impl Worker {
    /// Processes payment jobs until graceful shutdown.
    async fn run(&self) {
        // Delegate payment-specific claim cadence while preserving this error boundary
        claim_loop::run(
            &self.cancellation_token,
            ClaimLoopConfig::default(),
            || self.process_next_payment_job(),
            |err| {
                error!(error = %err, "error processing payment job");
                None
            },
        )
        .await;
    }

    /// Claims and processes one durable payment job.
    #[instrument(skip(self), err)]
    async fn process_next_payment_job(&self) -> Result<bool> {
        // Leave durable jobs unclaimed when this worker has no configured provider
        let Some(provider_adapter) = self.payments_provider.as_ref() else {
            return Ok(false);
        };
        let configured_provider = provider_adapter.provider();

        // Claim at most one provider-specific job, starting from a rotating kind
        let start =
            self.next_kind_index.fetch_add(1, Ordering::Relaxed) % PaymentJobKind::ALL.len();
        for offset in 0..PaymentJobKind::ALL.len() {
            let kind = PaymentJobKind::ALL[(start + offset) % PaymentJobKind::ALL.len()];
            let Some(job) = self.db.claim_payment_job(kind, configured_provider).await? else {
                continue;
            };

            // Expose the claimed lifecycle state at the worker boundary
            debug!(
                attempt_count = job.attempt_count,
                payment_job_id = %job.payment_job_id,
                payment_provider = %job.payment_provider,
                "processing payment job"
            );

            // Release the claimed job when any processing phase fails
            if let Err(err) = self.process_payment_job(provider_adapter, &job).await {
                self.release_claim(&job, &err).await;
                return Err(err);
            }

            return Ok(true);
        }

        Ok(false)
    }

    /// Dispatches the claimed job to its kind-specific provider workflow.
    async fn process_payment_job(
        &self,
        payments_provider: &DynPaymentsProvider,
        job: &ClaimedPaymentJob,
    ) -> Result<()> {
        match &job.work {
            ClaimedPaymentJobWork::EventPurchaseApplicationFeeAdjustment {
                application_fee_adjustment,
            } => {
                application_fee_adjustment::process(
                    &self.db,
                    payments_provider,
                    job,
                    application_fee_adjustment,
                )
                .await
            }
            ClaimedPaymentJobWork::EventPurchaseCreditNote { credit_note } => {
                credit_note::process(&self.db, payments_provider, job, credit_note).await
            }
            ClaimedPaymentJobWork::EventPurchaseRefund { refund } => {
                refund::process(
                    &self.db,
                    &self.notification_composer,
                    payments_provider,
                    job,
                    refund,
                )
                .await
            }
        }
    }

    /// Releases the current claim without hiding the processing error.
    ///
    /// The failure is logged with the `payment_job_id` so it can be correlated
    /// with the request that enqueued the job.
    async fn release_claim(&self, job: &ClaimedPaymentJob, err: &anyhow::Error) {
        warn!(
            payment_job_id = %job.payment_job_id,
            attempt_count = job.attempt_count,
            error = %err,
            "payment job failed; claim released for retry"
        );
        if let Err(record_err) = self
            .db
            .record_payment_job_failure(job.payment_job_id, job.claim_id, err.to_string())
            .await
        {
            warn!(
                payment_job_id = %job.payment_job_id,
                error = %record_err,
                "failed to release payment job claim"
            );
        }
    }
}
