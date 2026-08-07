//! Background reconciliation for due event enrollment reservations.

use std::time::Duration;

use tokio::time::sleep;
use tokio_util::{sync::CancellationToken, task::TaskTracker};
use tracing::error;

use crate::{db::DynDB, services::workers::run_until_cancelled, types::payments::PaymentProvider};

#[cfg(test)]
mod tests;

/// Number of concurrent enrollment reconciliation workers.
const NUM_ENROLLMENT_WORKERS: usize = 1;

/// Pause after a worker iteration fails.
const PAUSE_ON_ERROR: Duration = Duration::from_secs(10);

/// Pause when no due enrollment work is available.
const PAUSE_ON_NONE: Duration = Duration::from_secs(15);

/// Starts workers that expire due enrollment reservations and fill capacity.
pub(crate) fn start_enrollment_workers(
    db: &DynDB,
    task_tracker: &TaskTracker,
    cancellation_token: &CancellationToken,
    payment_provider: Option<PaymentProvider>,
) {
    // Start independent workers with shared graceful-shutdown coordination
    for _ in 0..NUM_ENROLLMENT_WORKERS {
        let worker = EnrollmentWorker {
            cancellation_token: cancellation_token.clone(),
            db: db.clone(),
            payment_provider,
        };
        task_tracker.spawn(async move {
            worker.run().await;
        });
    }
}

/// Reconciles due enrollment work until graceful shutdown.
struct EnrollmentWorker {
    /// Coordinates graceful worker shutdown.
    cancellation_token: CancellationToken,
    /// Persists enrollment reconciliation transitions.
    db: DynDB,
    /// Payment provider configured for checkout cleanup.
    payment_provider: Option<PaymentProvider>,
}

impl EnrollmentWorker {
    /// Processes due enrollment reservations until graceful shutdown.
    async fn run(&self) {
        loop {
            // Stop before claiming more work after graceful shutdown begins
            if self.cancellation_token.is_cancelled() {
                break;
            }

            // Reconcile one due event while allowing prompt shutdown
            let Some(result) = run_until_cancelled(
                &self.cancellation_token,
                self.db.reconcile_next_event_enrollment(self.payment_provider),
            )
            .await
            else {
                break;
            };

            // Continue immediately after work or select the idle/error backoff
            let pause = match result {
                Ok(Some(_)) => None,
                Ok(None) => Some(PAUSE_ON_NONE),
                Err(err) => {
                    error!(error = %err, "error reconciling event enrollment");
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
        }
    }
}
