use std::sync::Arc;

use mockall::Sequence;
use tokio_util::sync::CancellationToken;

use crate::{
    db::mock::MockDB,
    types::workers::{QueueHealth, WorkerQueueHealth},
};

use super::{Reporter, WorkerRegistry};

#[tokio::test]
async fn test_report_reads_queue_health_once_per_report() {
    // Return backlog signals for every queue, then fail the next read
    let mut db = MockDB::new();
    let mut seq = Sequence::new();
    db.expect_get_worker_queue_health()
        .times(1)
        .in_sequence(&mut seq)
        .return_once(|| {
            Ok(WorkerQueueHealth {
                badge_award_jobs: QueueHealth {
                    pending: 1,
                    processing: 0,
                    oldest_pending_age_secs: Some(30),
                },
                notifications: QueueHealth {
                    pending: 3,
                    processing: 1,
                    oldest_pending_age_secs: Some(120),
                },
                payment_jobs: QueueHealth {
                    pending: 0,
                    processing: 0,
                    oldest_pending_age_secs: None,
                },
            })
        });
    db.expect_get_worker_queue_health()
        .times(1)
        .in_sequence(&mut seq)
        .return_once(|| Err(anyhow::anyhow!("health unavailable")));

    // Report twice; the read error is logged, not propagated
    let reporter = reporter(db);
    reporter.report().await;
    reporter.report().await;
}

#[tokio::test]
async fn test_run_stops_during_initial_delay_when_cancelled() {
    // Reject every queue health read
    let mut db = MockDB::new();
    db.expect_get_worker_queue_health().times(0);

    // Cancel before the initial delay elapses
    let reporter = reporter(db);
    reporter.cancellation_token.cancel();
    reporter.run().await;
}

// Helpers.

/// Creates a queue health reporter with a fresh cancellation token.
fn reporter(db: MockDB) -> Reporter {
    Reporter {
        cancellation_token: CancellationToken::new(),
        db: Arc::new(db),
        worker_registry: WorkerRegistry::new(),
    }
}
