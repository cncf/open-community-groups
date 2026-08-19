use std::sync::Arc;

use mockall::Sequence;
use tokio_util::sync::CancellationToken;

use crate::db::mock::MockDB;

use super::Worker;

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
