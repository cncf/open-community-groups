use std::sync::Arc;

use tokio_util::sync::CancellationToken;

use crate::db::mock::MockDB;

use super::Worker;

#[tokio::test]
async fn test_sweep_stale_claims_handles_database_error() {
    // Fail the single payment job recovery sweep
    let mut db = MockDB::new();
    db.expect_requeue_stale_payment_job_claims()
        .times(1)
        .return_once(|| Err(anyhow::anyhow!("recovery unavailable")));

    // Sweep claims without propagating recovery-worker errors
    worker(db).sweep_stale_claims().await;
}

#[tokio::test]
async fn test_sweep_stale_claims_sweeps_payment_jobs() {
    // Return a successful payment job recovery count
    let mut db = MockDB::new();
    db.expect_requeue_stale_payment_job_claims()
        .times(1)
        .return_once(|| Ok(1));

    // Sweep the payment job queue
    worker(db).sweep_stale_claims().await;
}

// Helpers.

/// Creates a payment recovery worker with a fresh cancellation token.
fn worker(db: MockDB) -> Worker {
    Worker {
        cancellation_token: CancellationToken::new(),
        db: Arc::new(db),
    }
}
