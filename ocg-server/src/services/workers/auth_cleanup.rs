//! Periodic cleanup of expired authentication records.

use std::{future::Future, time::Duration};

use anyhow::Result;
use tokio_util::sync::CancellationToken;
use tracing::{error, info, warn};

use crate::{
    db::{DynDB, auth::AUTH_CLEANUP_BATCH_SIZE},
    services::workers::{BackgroundTasks, WorkerIteration, run_worker},
};

#[cfg(test)]
mod tests;

/// Interval between auth cleanup sweeps.
const CLEANUP_INTERVAL: Duration = Duration::from_hours(1);

/// Maximum bounded batches executed per cleanup target in one sweep.
const MAX_BATCHES_PER_SWEEP: usize = 100;

/// Short breather before resuming when a sweep reaches the per-target batch cap.
const PAUSE_ON_BACKLOG: Duration = Duration::from_secs(10);

/// Retry backoff when a cleanup target fails with a database error.
const PAUSE_ON_ERROR: Duration = Duration::from_mins(1);

/// Starts the periodic auth cleanup worker.
pub(crate) fn start(db: &DynDB, background_tasks: &BackgroundTasks) {
    let worker = Worker {
        cancellation_token: background_tasks.cancellation_token(),
        db: db.clone(),
    };
    background_tasks.spawn("auth-cleanup", async move {
        worker.run().await;
    });
}

/// Removes expired authentication sessions, verification codes, and password
/// reset tokens on an hourly cadence.
struct Worker {
    /// Coordinates graceful worker shutdown.
    cancellation_token: CancellationToken,
    /// Executes batched database cleanup functions.
    db: DynDB,
}

impl Worker {
    /// Runs auth cleanup sweeps until graceful shutdown.
    async fn run(&self) {
        run_worker(&self.cancellation_token, || async {
            // Sweep every auth cleanup target and select the next pause cadence
            let pause = match self.cleanup().await {
                SweepOutcome::Backlog => PAUSE_ON_BACKLOG,
                SweepOutcome::CaughtUp => CLEANUP_INTERVAL,
                SweepOutcome::Error => PAUSE_ON_ERROR,
            };
            WorkerIteration::Pause(pause)
        })
        .await;
    }

    /// Sweeps expired authentication records across independent cleanup targets.
    ///
    /// Cleanup targets are independent: an error in one never prevents the
    /// others from running in the same pass.
    async fn cleanup(&self) -> SweepOutcome {
        // Delete expired authentication sessions in bounded batches
        let sessions_outcome = self
            .drain_batches("auth_session", || {
                self.db.delete_expired_auth_sessions(AUTH_CLEANUP_BATCH_SIZE)
            })
            .await;

        // Delete expired email verification codes in bounded batches
        let codes_outcome = self
            .drain_batches("email_verification_code", || {
                self.db
                    .delete_expired_email_verification_codes(AUTH_CLEANUP_BATCH_SIZE)
            })
            .await;

        // Delete expired password reset tokens in bounded batches
        let reset_tokens_outcome = self
            .drain_batches("password_reset_token", || {
                self.db.delete_expired_password_reset_tokens(AUTH_CLEANUP_BATCH_SIZE)
            })
            .await;

        sessions_outcome.combine(codes_outcome).combine(reset_tokens_outcome)
    }

    /// Drains one cleanup target in bounded batches until caught up, capped,
    /// failed, or cancelled.
    async fn drain_batches<DeleteBatch, DeleteBatchFuture>(
        &self,
        table: &'static str,
        mut delete_batch: DeleteBatch,
    ) -> SweepOutcome
    where
        DeleteBatch: FnMut() -> DeleteBatchFuture,
        DeleteBatchFuture: Future<Output = Result<usize>>,
    {
        let mut total_deleted = 0;

        for _ in 0..MAX_BATCHES_PER_SWEEP {
            // Stop before starting another database batch after cancellation
            if self.cancellation_token.is_cancelled() {
                if total_deleted > 0 {
                    info!(
                        table,
                        deleted = total_deleted,
                        "deleted expired auth records"
                    );
                }
                return SweepOutcome::CaughtUp;
            }

            // Execute one bounded deletion batch and return on error or short batch
            match delete_batch().await {
                Ok(deleted) => {
                    total_deleted += deleted;
                    if deleted < AUTH_CLEANUP_BATCH_SIZE {
                        if total_deleted > 0 {
                            info!(
                                table,
                                deleted = total_deleted,
                                "deleted expired auth records"
                            );
                        }
                        return SweepOutcome::CaughtUp;
                    }
                }
                Err(err) => {
                    error!(
                        error = %format_args!("{err:#}"),
                        table,
                        deleted = total_deleted,
                        "error cleaning up expired auth records"
                    );
                    return SweepOutcome::Error;
                }
            }
        }

        // Handle cancellation observed on the final batch before reporting a cap
        if self.cancellation_token.is_cancelled() {
            if total_deleted > 0 {
                info!(
                    table,
                    deleted = total_deleted,
                    "deleted expired auth records"
                );
            }
            return SweepOutcome::CaughtUp;
        }

        // Report that backlog remains after reaching the per-sweep batch cap
        warn!(
            table,
            deleted = total_deleted,
            "auth cleanup reached batch limit for this sweep; continuing after backlog pause"
        );
        SweepOutcome::Backlog
    }
}

/// Cadence outcome of one auth cleanup sweep.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum SweepOutcome {
    /// At least one target reached the per-sweep batch cap with backlog remaining.
    Backlog,
    /// Every target caught up without error.
    CaughtUp,
    /// At least one target failed with a database error.
    Error,
}

impl SweepOutcome {
    /// Combines two target outcomes, prioritizing error backoff over backlog drain.
    fn combine(self, other: Self) -> Self {
        match (self, other) {
            (Self::Error, _) | (_, Self::Error) => Self::Error,
            (Self::Backlog, _) | (_, Self::Backlog) => Self::Backlog,
            (Self::CaughtUp, Self::CaughtUp) => Self::CaughtUp,
        }
    }
}
