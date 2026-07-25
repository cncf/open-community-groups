//! Background processing for durable badge award jobs.

use std::{future::Future, time::Duration};

use anyhow::Result;
use tokio::time::sleep;
use tokio_util::{sync::CancellationToken, task::TaskTracker};
use tracing::{error, info, instrument, warn};

use crate::db::{DynDB, badges::ClaimedBadgeAwardJob};

#[cfg(test)]
mod tests;

/// Maximum number of queued recipients consumed by one transaction.
const AWARD_BATCH_SIZE: usize = 25;
/// Maximum credentials admitted across all replicas during one rolling minute.
const AWARD_RATE_LIMIT_PER_MINUTE: usize = 500;
/// Completed job summary retention period.
const COMPLETED_JOB_RETENTION: Duration = Duration::from_hours(30 * 24);
/// Number of consecutive failures allowed before operator intervention is required.
const MAX_FAILURES: usize = 10;
/// Number of workers that recover stale claims and clean completed summaries.
const NUM_AWARD_RECOVERY_WORKERS: usize = 1;
/// Number of deliberately low-concurrency award workers.
const NUM_AWARD_WORKERS: usize = 1;
/// Pause after a worker iteration fails.
const PAUSE_ON_ERROR: Duration = Duration::from_secs(10);
/// Pause when no badge award work is available.
const PAUSE_ON_NONE: Duration = Duration::from_secs(15);
/// Interval between recovery and cleanup attempts.
const PAUSE_ON_RECOVERY: Duration = Duration::from_mins(1);
/// Time after which an interrupted processing claim may be recovered.
const PROCESSING_TIMEOUT: Duration = Duration::from_mins(15);

/// Starts durable badge award and abandoned-claim recovery workers.
pub(crate) fn start_badge_award_workers(
    db: &DynDB,
    task_tracker: &TaskTracker,
    cancellation_token: &CancellationToken,
) {
    for _ in 0..NUM_AWARD_WORKERS {
        let worker = BadgeAwardWorker {
            cancellation_token: cancellation_token.clone(),
            db: db.clone(),
        };
        task_tracker.spawn(async move {
            worker.run().await;
        });
    }

    for _ in 0..NUM_AWARD_RECOVERY_WORKERS {
        let worker = BadgeAwardRecoveryWorker {
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

/// Processes queued badge awards at a fixed low concurrency and global rate.
struct BadgeAwardWorker {
    /// Coordinates graceful worker shutdown.
    cancellation_token: CancellationToken,
    /// Persists durable award lifecycle transitions.
    db: DynDB,
}

impl BadgeAwardWorker {
    /// Processes badge awards until graceful shutdown.
    async fn run(&self) {
        loop {
            if self.cancellation_token.is_cancelled() {
                break;
            }

            let Some(result) =
                run_until_cancelled(&self.cancellation_token, self.process_next_award_job()).await
            else {
                break;
            };

            let pause = match result {
                Ok(true) => None,
                Ok(false) => Some(PAUSE_ON_NONE),
                Err(err) => {
                    error!(error = %err, "error processing badge award job");
                    Some(PAUSE_ON_ERROR)
                }
            };

            if let Some(pause) = pause {
                tokio::select! {
                    () = sleep(pause) => {},
                    () = self.cancellation_token.cancelled() => break,
                }
            }

            if self.cancellation_token.is_cancelled() {
                break;
            }
        }
    }

    /// Claims and processes one bounded durable award batch.
    #[instrument(skip(self), err)]
    async fn process_next_award_job(&self) -> Result<bool> {
        let Some(job) = self.db.claim_badge_award_job().await? else {
            return Ok(false);
        };

        let result = self
            .db
            .process_badge_award_job_batch(
                job.badge_award_job_id,
                job.claim_id,
                AWARD_BATCH_SIZE,
                AWARD_RATE_LIMIT_PER_MINUTE,
            )
            .await;

        match result {
            Ok(outcome) => {
                if outcome.rate_limited {
                    info!(
                        badge_award_job_id = %job.badge_award_job_id,
                        "paused badge award job at global issuance limit"
                    );
                    return Ok(false);
                }
                if outcome.completed {
                    info!(
                        badge_award_job_id = %job.badge_award_job_id,
                        processed = outcome.processed_count,
                        "completed badge award job"
                    );
                }
                Ok(true)
            }
            Err(err) => {
                self.release_failure(&job, &err).await;
                Err(err)
            }
        }
    }

    /// Releases the current claim or records terminal failure without hiding the error.
    async fn release_failure(&self, job: &ClaimedBadgeAwardJob, err: &anyhow::Error) {
        match self
            .db
            .record_badge_award_job_failure(
                job.badge_award_job_id,
                job.claim_id,
                err.to_string(),
                MAX_FAILURES,
            )
            .await
        {
            Ok(true) => error!(
                badge_award_job_id = %job.badge_award_job_id,
                "badge award job requires operator intervention"
            ),
            Ok(false) => {}
            Err(record_err) => warn!(
                error = %record_err,
                badge_award_job_id = %job.badge_award_job_id,
                "failed to release badge award job claim"
            ),
        }
    }
}

/// Recovers claims abandoned by interrupted workers and removes old summaries.
struct BadgeAwardRecoveryWorker {
    /// Coordinates graceful recovery-worker shutdown.
    cancellation_token: CancellationToken,
    /// Persists recovery and cleanup transitions.
    db: DynDB,
}

impl BadgeAwardRecoveryWorker {
    /// Runs maintenance until graceful shutdown.
    async fn run(&self) {
        loop {
            if self.cancellation_token.is_cancelled() {
                break;
            }

            let Some(()) = run_until_cancelled(&self.cancellation_token, self.maintain()).await
            else {
                break;
            };

            tokio::select! {
                () = sleep(PAUSE_ON_RECOVERY) => {},
                () = self.cancellation_token.cancelled() => break,
            }
        }
    }

    /// Performs one stale-claim recovery and completed-summary cleanup pass.
    async fn maintain(&self) {
        match self
            .db
            .recover_stale_badge_award_jobs(MAX_FAILURES, PROCESSING_TIMEOUT)
            .await
        {
            Ok(recovered) if recovered > 0 => {
                warn!(recovered, "recovered stale badge award job claims");
            }
            Ok(_) => {}
            Err(err) => error!(error = %err, "error recovering badge award job claims"),
        }

        match self.db.cleanup_badge_award_jobs(COMPLETED_JOB_RETENTION).await {
            Ok(deleted) if deleted > 0 => {
                info!(deleted, "deleted expired badge award job summaries");
            }
            Ok(_) => {}
            Err(err) => error!(error = %err, "error cleaning badge award job summaries"),
        }
    }
}
