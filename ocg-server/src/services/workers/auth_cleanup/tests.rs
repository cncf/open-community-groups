use std::{
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};

use anyhow::anyhow;
use mockall::{Sequence, predicate::eq};
use tokio::{
    sync::Notify,
    time::{Instant, advance},
};
use tokio_util::sync::CancellationToken;

use crate::db::{auth::AUTH_CLEANUP_BATCH_SIZE, mock::MockDB};

use super::{
    CLEANUP_INTERVAL, MAX_BATCHES_PER_SWEEP, PAUSE_ON_BACKLOG, PAUSE_ON_ERROR, SweepOutcome, Worker,
};

#[tokio::test]
async fn test_cleanup_caps_draining_at_max_batches_per_sweep() {
    // Setup a persistent full-batch backlog for sessions and an empty code table
    let mut db = MockDB::new();
    db.expect_delete_expired_auth_sessions()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(MAX_BATCHES_PER_SWEEP)
        .returning(|_| Ok(AUTH_CLEANUP_BATCH_SIZE));
    db.expect_delete_expired_email_verification_codes()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(1)
        .return_once(|_| Ok(0));
    let worker = worker(db);

    // Run one sweep and check the outcome reports remaining backlog
    let outcome = worker.cleanup().await;
    assert_eq!(outcome, SweepOutcome::Backlog);
}

#[tokio::test]
async fn test_cleanup_continues_after_session_cleanup_error() {
    // Setup a failing session cleanup followed by a succeeding code cleanup
    let mut db = MockDB::new();
    db.expect_delete_expired_auth_sessions()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(1)
        .return_once(|_| Err(anyhow!("database failure")));
    db.expect_delete_expired_email_verification_codes()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(1)
        .return_once(|_| Ok(3));
    let worker = worker(db);

    // Run one sweep and verify the second target still executes and error is reported
    let outcome = worker.cleanup().await;
    assert_eq!(outcome, SweepOutcome::Error);
}

#[tokio::test]
async fn test_cleanup_drains_multiple_batches_until_short_batch() {
    // Setup two full session batches plus a trailing short batch, and one full code batch plus a zero tail
    let mut db = MockDB::new();
    let mut session_seq = Sequence::new();
    db.expect_delete_expired_auth_sessions()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(1)
        .in_sequence(&mut session_seq)
        .return_once(|_| Ok(AUTH_CLEANUP_BATCH_SIZE));
    db.expect_delete_expired_auth_sessions()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(1)
        .in_sequence(&mut session_seq)
        .return_once(|_| Ok(AUTH_CLEANUP_BATCH_SIZE));
    db.expect_delete_expired_auth_sessions()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(1)
        .in_sequence(&mut session_seq)
        .return_once(|_| Ok(12));

    let mut code_seq = Sequence::new();
    db.expect_delete_expired_email_verification_codes()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(1)
        .in_sequence(&mut code_seq)
        .return_once(|_| Ok(AUTH_CLEANUP_BATCH_SIZE));
    db.expect_delete_expired_email_verification_codes()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(1)
        .in_sequence(&mut code_seq)
        .return_once(|_| Ok(0));
    let worker = worker(db);

    // Run one sweep and verify all batches drain completely
    let outcome = worker.cleanup().await;
    assert_eq!(outcome, SweepOutcome::CaughtUp);
}

#[tokio::test]
async fn test_cleanup_runs_single_batch_per_target_when_caught_up() {
    // Setup both cleanup targets returning short batches
    let mut db = MockDB::new();
    db.expect_delete_expired_auth_sessions()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(1)
        .return_once(|_| Ok(5));
    db.expect_delete_expired_email_verification_codes()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(1)
        .return_once(|_| Ok(2));
    let worker = worker(db);

    // Run one sweep and verify the worker reports caught up
    let outcome = worker.cleanup().await;
    assert_eq!(outcome, SweepOutcome::CaughtUp);
}

#[tokio::test]
async fn test_cleanup_stops_draining_and_skips_remaining_targets_when_cancelled() {
    // Cancel the worker during the first full session batch
    let cancellation_token = CancellationToken::new();
    let cancel_on_batch = cancellation_token.clone();
    let mut db = MockDB::new();
    db.expect_delete_expired_auth_sessions()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(1)
        .return_once(move |_| {
            cancel_on_batch.cancel();
            Ok(AUTH_CLEANUP_BATCH_SIZE)
        });
    db.expect_delete_expired_email_verification_codes().never();
    let worker = Worker {
        cancellation_token,
        db: Arc::new(db),
    };

    // Run one sweep and verify cancellation halts further batches and targets
    let outcome = worker.cleanup().await;
    assert_eq!(outcome, SweepOutcome::CaughtUp);
}

#[tokio::test(start_paused = true)]
async fn test_run_pauses_briefly_on_backlog_before_resuming_hourly_cadence() {
    // Setup a capped first sweep followed by a caught-up second sweep that cancels
    let cancellation_token = CancellationToken::new();
    let cancel_on_second_sweep = cancellation_token.clone();
    let first_sweep_done = Arc::new(Notify::new());
    let notify_first_done = first_sweep_done.clone();
    let sweeps = Arc::new(AtomicUsize::new(0));
    let sweeps_first = sweeps.clone();
    let sweeps_second = sweeps.clone();
    let mut db = MockDB::new();
    let mut seq = Sequence::new();
    db.expect_delete_expired_auth_sessions()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(MAX_BATCHES_PER_SWEEP)
        .in_sequence(&mut seq)
        .returning(|_| Ok(AUTH_CLEANUP_BATCH_SIZE));
    db.expect_delete_expired_email_verification_codes()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(1)
        .in_sequence(&mut seq)
        .return_once(move |_| {
            sweeps_first.fetch_add(1, Ordering::SeqCst);
            notify_first_done.notify_one();
            Ok(0)
        });
    db.expect_delete_expired_auth_sessions()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(1)
        .in_sequence(&mut seq)
        .return_once(|_| Ok(0));
    db.expect_delete_expired_email_verification_codes()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(1)
        .in_sequence(&mut seq)
        .return_once(move |_| {
            sweeps_second.fetch_add(1, Ordering::SeqCst);
            cancel_on_second_sweep.cancel();
            Ok(0)
        });
    let worker = Worker {
        cancellation_token,
        db: Arc::new(db),
    };

    // Run the worker and verify the second sweep waits for the full backlog pause
    let started_at = Instant::now();
    let handle = tokio::spawn(async move {
        worker.run().await;
    });
    first_sweep_done.notified().await;
    advance(
        PAUSE_ON_BACKLOG
            .checked_sub(Duration::from_secs(1))
            .expect("backlog pause to exceed one second"),
    )
    .await;
    tokio::task::yield_now().await;
    assert_eq!(sweeps.load(Ordering::SeqCst), 1);

    // Advance past the backlog pause and verify exact elapsed time
    advance(Duration::from_secs(1)).await;
    handle.await.expect("cleanup worker task to finish cleanly");
    assert_eq!(sweeps.load(Ordering::SeqCst), 2);
    assert_eq!(started_at.elapsed(), PAUSE_ON_BACKLOG);
}

#[tokio::test(start_paused = true)]
async fn test_run_repeats_on_hourly_cadence_and_stops_on_cancellation() {
    // Setup two caught-up sweeps separated by the hourly pause, cancelling on the second
    let cancellation_token = CancellationToken::new();
    let cancel_on_second_sweep = cancellation_token.clone();
    let first_sweep_done = Arc::new(Notify::new());
    let notify_first_done = first_sweep_done.clone();
    let sweeps = Arc::new(AtomicUsize::new(0));
    let sweeps_first = sweeps.clone();
    let sweeps_second = sweeps.clone();
    let mut db = MockDB::new();
    let mut seq = Sequence::new();
    db.expect_delete_expired_auth_sessions()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(1)
        .in_sequence(&mut seq)
        .return_once(|_| Ok(0));
    db.expect_delete_expired_email_verification_codes()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(1)
        .in_sequence(&mut seq)
        .return_once(move |_| {
            sweeps_first.fetch_add(1, Ordering::SeqCst);
            notify_first_done.notify_one();
            Ok(0)
        });
    db.expect_delete_expired_auth_sessions()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(1)
        .in_sequence(&mut seq)
        .return_once(|_| Ok(0));
    db.expect_delete_expired_email_verification_codes()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(1)
        .in_sequence(&mut seq)
        .return_once(move |_| {
            sweeps_second.fetch_add(1, Ordering::SeqCst);
            cancel_on_second_sweep.cancel();
            Ok(0)
        });
    let worker = Worker {
        cancellation_token,
        db: Arc::new(db),
    };

    // Run the worker and check the second sweep does not fire before one hour elapses
    let started_at = Instant::now();
    let handle = tokio::spawn(async move {
        worker.run().await;
    });
    first_sweep_done.notified().await;
    advance(
        CLEANUP_INTERVAL
            .checked_sub(Duration::from_secs(1))
            .expect("cleanup interval to exceed one second"),
    )
    .await;
    tokio::task::yield_now().await;
    assert_eq!(sweeps.load(Ordering::SeqCst), 1);

    // Advance the remaining second and check exact hourly cadence
    advance(Duration::from_secs(1)).await;
    handle.await.expect("cleanup worker task to finish cleanly");
    assert_eq!(sweeps.load(Ordering::SeqCst), 2);
    assert_eq!(started_at.elapsed(), Duration::from_hours(1));
}

#[tokio::test(start_paused = true)]
async fn test_run_retries_after_error_pause_when_cleanup_fails() {
    // Setup a failing first sweep followed by a succeeding second sweep that cancels
    let cancellation_token = CancellationToken::new();
    let cancel_on_second_sweep = cancellation_token.clone();
    let first_sweep_done = Arc::new(Notify::new());
    let notify_first_done = first_sweep_done.clone();
    let sweeps = Arc::new(AtomicUsize::new(0));
    let sweeps_first = sweeps.clone();
    let sweeps_second = sweeps.clone();
    let mut db = MockDB::new();
    let mut seq = Sequence::new();
    db.expect_delete_expired_auth_sessions()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(1)
        .in_sequence(&mut seq)
        .return_once(|_| Err(anyhow!("transient database error")));
    db.expect_delete_expired_email_verification_codes()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(1)
        .in_sequence(&mut seq)
        .return_once(move |_| {
            sweeps_first.fetch_add(1, Ordering::SeqCst);
            notify_first_done.notify_one();
            Ok(0)
        });
    db.expect_delete_expired_auth_sessions()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(1)
        .in_sequence(&mut seq)
        .return_once(|_| Ok(0));
    db.expect_delete_expired_email_verification_codes()
        .with(eq(AUTH_CLEANUP_BATCH_SIZE))
        .times(1)
        .in_sequence(&mut seq)
        .return_once(move |_| {
            sweeps_second.fetch_add(1, Ordering::SeqCst);
            cancel_on_second_sweep.cancel();
            Ok(0)
        });
    let worker = Worker {
        cancellation_token,
        db: Arc::new(db),
    };

    // Run the worker and check the retry waits for the full error backoff
    let started_at = Instant::now();
    let handle = tokio::spawn(async move {
        worker.run().await;
    });
    first_sweep_done.notified().await;
    advance(
        PAUSE_ON_ERROR
            .checked_sub(Duration::from_secs(1))
            .expect("error pause to exceed one second"),
    )
    .await;
    tokio::task::yield_now().await;
    assert_eq!(sweeps.load(Ordering::SeqCst), 1);

    // Advance the remaining second and check exact retry cadence
    advance(Duration::from_secs(1)).await;
    handle.await.expect("cleanup worker task to finish cleanly");
    assert_eq!(sweeps.load(Ordering::SeqCst), 2);
    assert_eq!(started_at.elapsed(), PAUSE_ON_ERROR);
}

#[tokio::test]
async fn test_run_stops_immediately_when_cancelled_before_start() {
    // Reject every cleanup call when cancelled before the loop starts
    let mut db = MockDB::new();
    db.expect_delete_expired_auth_sessions().never();
    db.expect_delete_expired_email_verification_codes().never();
    let worker = worker(db);

    // Cancel before running the worker
    worker.cancellation_token.cancel();
    worker.run().await;
}

// Helpers.

/// Creates an auth cleanup worker with a fresh cancellation token.
fn worker(db: MockDB) -> Worker {
    Worker {
        cancellation_token: CancellationToken::new(),
        db: Arc::new(db),
    }
}
