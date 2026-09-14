//! Periodic reporter of worker health signals.
//!
//! The reporter reads the pending and processing counts and the oldest
//! pending job age of the badge award, notification, and payment job queues
//! and the running instances and unexpected exits of every worker, and emits
//! them through tracing so a stalled, starved, or dead worker is visible
//! without a dashboard.

use std::time::Duration;

use tokio_util::sync::CancellationToken;
use tracing::{error, info};

use crate::{
    db::DynDB,
    services::workers::{BackgroundTasks, WorkerIteration, WorkerRegistry, run_worker},
    types::workers::{QueueHealth, WorkerQueueHealth},
};

#[cfg(test)]
mod tests;

/// Interval between queue health reports.
const REPORT_INTERVAL: Duration = Duration::from_mins(5);

/// Starts the queue health reporter.
pub(crate) fn start(
    db: &DynDB,
    worker_registry: WorkerRegistry,
    background_tasks: &BackgroundTasks,
) {
    let reporter = Reporter {
        cancellation_token: background_tasks.cancellation_token(),
        db: db.clone(),
        worker_registry,
    };
    background_tasks.spawn("queue-health", async move {
        reporter.run().await;
    });
}

/// Reports queue backlog signals on a fixed cadence.
struct Reporter {
    /// Coordinates graceful reporter shutdown.
    cancellation_token: CancellationToken,
    /// Reads the queue backlog signals.
    db: DynDB,
    /// Observed state of the background workers.
    worker_registry: WorkerRegistry,
}

impl Reporter {
    /// Reports queue health until graceful shutdown.
    async fn run(&self) {
        run_worker(&self.cancellation_token, || async {
            // Emit one report per queue before the fixed cadence
            self.report().await;
            WorkerIteration::Pause(REPORT_INTERVAL)
        })
        .await;
    }

    /// Logs one line per queue and one per worker.
    async fn report(&self) {
        // Log the durable queues
        match self.db.get_worker_queue_health().await {
            Ok(health) => Self::log_health(&health),
            Err(err) => error!(error = %err, "error reading worker queue health"),
        }

        // Log the running instances and unexpected exits of every worker
        for (worker, status) in self.worker_registry.snapshot() {
            info!(
                worker,
                running = status.running,
                unexpected_exits = status.unexpected_exits.len(),
                "worker health"
            );
        }
    }

    /// Logs the backlog signals of every queue.
    fn log_health(health: &WorkerQueueHealth) {
        Self::log_queue("badge_award_jobs", &health.badge_award_jobs);
        Self::log_queue("notifications", &health.notifications);
        Self::log_queue("payment_jobs", &health.payment_jobs);
    }

    /// Logs the backlog signals of one queue.
    fn log_queue(queue: &str, health: &QueueHealth) {
        info!(
            queue,
            pending = health.pending,
            processing = health.processing,
            oldest_pending_age_secs = health.oldest_pending_age_secs,
            "worker queue health"
        );
    }
}
