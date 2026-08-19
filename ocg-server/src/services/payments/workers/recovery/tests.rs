use std::{sync::Arc, time::Duration};

use mockall::Sequence;
use tokio::{sync::Notify, time::timeout};
use tokio_util::sync::CancellationToken;

use crate::db::mock::MockDB;

use super::Worker;

#[tokio::test]
async fn test_run_does_not_sweep_after_cancellation() {
    // Forbid every recovery query after cancellation
    let mut db = MockDB::new();
    db.expect_requeue_stale_event_purchase_application_fee_adjustment_claims()
        .never();
    db.expect_requeue_stale_event_purchase_credit_note_claims().never();
    db.expect_requeue_stale_event_purchase_refund_claims().never();
    let cancellation_token = CancellationToken::new();
    cancellation_token.cancel();
    let worker = Worker {
        cancellation_token,
        db: Arc::new(db),
    };

    // Run the already canceled recovery worker
    worker.run().await;
}

#[tokio::test(start_paused = true)]
async fn test_run_stops_during_recovery_cadence_wait() {
    // Complete one pass and hold the worker in its cadence wait
    let recovery_completed = Arc::new(Notify::new());
    let recovery_completed_for_query = recovery_completed.clone();
    let mut db = MockDB::new();
    db.expect_requeue_stale_event_purchase_application_fee_adjustment_claims()
        .times(1)
        .return_once(|| Ok(0));
    db.expect_requeue_stale_event_purchase_credit_note_claims()
        .times(1)
        .return_once(|| Ok(0));
    db.expect_requeue_stale_event_purchase_refund_claims()
        .times(1)
        .return_once(move || {
            recovery_completed_for_query.notify_one();
            Ok(0)
        });
    let cancellation_token = CancellationToken::new();
    let worker = Worker {
        cancellation_token: cancellation_token.clone(),
        db: Arc::new(db),
    };

    // Start the worker and let its first pass complete
    let worker_task = tokio::spawn(async move { worker.run().await });
    recovery_completed.notified().await;

    // Cancel without advancing the one-minute cadence
    cancellation_token.cancel();
    timeout(Duration::from_secs(1), worker_task)
        .await
        .expect("payment recovery cadence wait to stop promptly")
        .expect("payment recovery worker to complete");
}

#[tokio::test]
async fn test_run_stops_during_recovery_pass() {
    // Signal when the first recovery query completes before the pass yields
    let recovery_started = Arc::new(Notify::new());
    let recovery_started_for_query = recovery_started.clone();
    let mut db = MockDB::new();
    db.expect_requeue_stale_event_purchase_application_fee_adjustment_claims()
        .times(1)
        .return_once(move || {
            recovery_started_for_query.notify_one();
            Ok(0)
        });
    db.expect_requeue_stale_event_purchase_credit_note_claims().never();
    db.expect_requeue_stale_event_purchase_refund_claims().never();
    let cancellation_token = CancellationToken::new();
    let worker = Worker {
        cancellation_token: cancellation_token.clone(),
        db: Arc::new(db),
    };

    // Start the worker and wait for the pending pass boundary
    let worker_task = tokio::spawn(async move { worker.run().await });
    timeout(Duration::from_secs(1), recovery_started.notified())
        .await
        .expect("payment recovery pass to start");

    // Cancel and require the pending pass to be dropped promptly
    cancellation_token.cancel();
    timeout(Duration::from_secs(1), worker_task)
        .await
        .expect("payment recovery pass to stop promptly")
        .expect("payment recovery worker to complete");
}

#[tokio::test]
async fn test_sweep_stale_claims_continues_after_application_fee_adjustment_error() {
    // Fail the first queue and require both later queues to run
    let mut sequence = Sequence::new();
    let mut db = MockDB::new();
    db.expect_requeue_stale_event_purchase_application_fee_adjustment_claims()
        .times(1)
        .in_sequence(&mut sequence)
        .return_once(|| Err(anyhow::anyhow!("application fee recovery unavailable")));
    db.expect_requeue_stale_event_purchase_credit_note_claims()
        .times(1)
        .in_sequence(&mut sequence)
        .return_once(|| Ok(2));
    db.expect_requeue_stale_event_purchase_refund_claims()
        .times(1)
        .in_sequence(&mut sequence)
        .return_once(|| Ok(3));

    // Sweep all queues despite the first failure
    worker(db).sweep_stale_claims().await;
}

#[tokio::test]
async fn test_sweep_stale_claims_continues_after_credit_note_error() {
    // Fail the middle queue and require the final queue to run
    let mut sequence = Sequence::new();
    let mut db = MockDB::new();
    db.expect_requeue_stale_event_purchase_application_fee_adjustment_claims()
        .times(1)
        .in_sequence(&mut sequence)
        .return_once(|| Ok(1));
    db.expect_requeue_stale_event_purchase_credit_note_claims()
        .times(1)
        .in_sequence(&mut sequence)
        .return_once(|| Err(anyhow::anyhow!("credit note recovery unavailable")));
    db.expect_requeue_stale_event_purchase_refund_claims()
        .times(1)
        .in_sequence(&mut sequence)
        .return_once(|| Ok(3));

    // Sweep all queues despite the middle failure
    worker(db).sweep_stale_claims().await;
}

#[tokio::test]
async fn test_sweep_stale_claims_handles_refund_error_after_other_queues() {
    // Require the first two queues before failing the final queue
    let mut sequence = Sequence::new();
    let mut db = MockDB::new();
    db.expect_requeue_stale_event_purchase_application_fee_adjustment_claims()
        .times(1)
        .in_sequence(&mut sequence)
        .return_once(|| Ok(1));
    db.expect_requeue_stale_event_purchase_credit_note_claims()
        .times(1)
        .in_sequence(&mut sequence)
        .return_once(|| Ok(2));
    db.expect_requeue_stale_event_purchase_refund_claims()
        .times(1)
        .in_sequence(&mut sequence)
        .return_once(|| Err(anyhow::anyhow!("refund recovery unavailable")));

    // Sweep every queue through the final failure
    worker(db).sweep_stale_claims().await;
}

#[tokio::test]
async fn test_sweep_stale_claims_sweeps_every_queue() {
    // Return successful recovery counts from every queue in order
    let mut sequence = Sequence::new();
    let mut db = MockDB::new();
    db.expect_requeue_stale_event_purchase_application_fee_adjustment_claims()
        .times(1)
        .in_sequence(&mut sequence)
        .return_once(|| Ok(1));
    db.expect_requeue_stale_event_purchase_credit_note_claims()
        .times(1)
        .in_sequence(&mut sequence)
        .return_once(|| Ok(2));
    db.expect_requeue_stale_event_purchase_refund_claims()
        .times(1)
        .in_sequence(&mut sequence)
        .return_once(|| Ok(3));

    // Sweep all payment queues
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
