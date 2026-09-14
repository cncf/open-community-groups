use std::sync::Arc;

use tokio_util::sync::CancellationToken;

use crate::{
    db::mock::MockDB,
    types::workers::{QueueHealth, WorkerQueueHealth},
};

use super::{Reporter, WorkerRegistry};

#[tokio::test]
async fn test_report_handles_database_error() {
    // Fail the single queue health read
    let mut db = MockDB::new();
    db.expect_get_worker_queue_health()
        .times(1)
        .return_once(|| Err(anyhow::anyhow!("health unavailable")));

    // Report without propagating the read error
    reporter(db).report().await;
}

#[tokio::test]
async fn test_report_reads_queue_health_once() {
    // Return backlog signals for every queue
    let mut db = MockDB::new();
    db.expect_get_worker_queue_health().times(1).return_once(|| {
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

    // Report the signals
    reporter(db).report().await;
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
