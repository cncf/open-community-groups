//! Background reconciliation for due event enrollment reservations.

use tokio_util::{sync::CancellationToken, task::TaskTracker};
use tracing::error;

use crate::{
    db::DynDB,
    services::workers::claim_loop::{self, ClaimLoopConfig},
    types::payments::PaymentProvider,
};

#[cfg(test)]
mod tests;

/// Number of concurrent enrollment reconciliation workers.
const NUM_ENROLLMENT_WORKERS: usize = 1;

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
        claim_loop::run(
            &self.cancellation_token,
            ClaimLoopConfig::default(),
            || async {
                // Map the optional reconciliation outcome to the shared claim contract
                self.db
                    .reconcile_next_event_enrollment(self.payment_provider)
                    .await
                    .map(|outcome| outcome.is_some())
            },
            |err| {
                error!(error = %err, "error reconciling event enrollment");
                None
            },
        )
        .await;
    }
}
