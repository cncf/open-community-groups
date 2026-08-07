use std::{future::pending, sync::Arc, time::Duration};

use anyhow::anyhow;
use mockall::Sequence;
use tokio::{sync::Notify, time::timeout};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::{
    db::{DynDB, mock::MockDB},
    services::workers::run_until_cancelled,
    types::event::EventEnrollmentReconciliationOutcome,
    types::payments::PaymentProvider,
};

use super::{EnrollmentWorker, PAUSE_ON_ERROR, PAUSE_ON_NONE};

#[tokio::test(start_paused = true)]
async fn test_run_applies_error_pause() {
    // Setup a failed iteration followed by cancellation on the next claim
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_mock = cancellation_token.clone();
    let reconciliation_started = Arc::new(Notify::new());
    let reconciliation_started_for_mock = reconciliation_started.clone();
    let mut sequence = Sequence::new();
    let mut db = MockDB::new();
    db.expect_reconcile_next_event_enrollment()
        .times(1)
        .in_sequence(&mut sequence)
        .withf(|provider| *provider == Some(PaymentProvider::Stripe))
        .returning(move |_| {
            reconciliation_started_for_mock.notify_one();
            Err(anyhow!("reconciliation failed"))
        });
    db.expect_reconcile_next_event_enrollment()
        .times(1)
        .in_sequence(&mut sequence)
        .withf(|provider| *provider == Some(PaymentProvider::Stripe))
        .returning(move |_| {
            cancellation_token_for_mock.cancel();
            Ok(None)
        });
    let worker = EnrollmentWorker {
        cancellation_token,
        db: Arc::new(db),
        payment_provider: Some(PaymentProvider::Stripe),
    };

    // Run through the error backoff boundary
    let worker_task = tokio::spawn(async move { worker.run().await });
    reconciliation_started.notified().await;
    tokio::time::advance(PAUSE_ON_ERROR.checked_sub(Duration::from_secs(1)).unwrap()).await;
    tokio::task::yield_now().await;
    assert!(!worker_task.is_finished());
    tokio::time::advance(Duration::from_secs(1)).await;

    // Check the worker resumes only after the configured error pause
    worker_task.await.expect("enrollment worker to stop cleanly");
}

#[tokio::test(start_paused = true)]
async fn test_run_applies_idle_pause() {
    // Setup an idle iteration followed by cancellation on the next claim
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_mock = cancellation_token.clone();
    let reconciliation_started = Arc::new(Notify::new());
    let reconciliation_started_for_mock = reconciliation_started.clone();
    let mut sequence = Sequence::new();
    let mut db = MockDB::new();
    db.expect_reconcile_next_event_enrollment()
        .times(1)
        .in_sequence(&mut sequence)
        .withf(Option::is_none)
        .returning(move |_| {
            reconciliation_started_for_mock.notify_one();
            Ok(None)
        });
    db.expect_reconcile_next_event_enrollment()
        .times(1)
        .in_sequence(&mut sequence)
        .withf(Option::is_none)
        .returning(move |_| {
            cancellation_token_for_mock.cancel();
            Ok(None)
        });
    let worker = EnrollmentWorker {
        cancellation_token,
        db: Arc::new(db),
        payment_provider: None,
    };

    // Run through the idle backoff boundary
    let worker_task = tokio::spawn(async move { worker.run().await });
    reconciliation_started.notified().await;
    tokio::time::advance(PAUSE_ON_NONE.checked_sub(Duration::from_secs(1)).unwrap()).await;
    tokio::task::yield_now().await;
    assert!(!worker_task.is_finished());
    tokio::time::advance(Duration::from_secs(1)).await;

    // Check the worker resumes only after the configured idle pause
    worker_task.await.expect("enrollment worker to stop cleanly");
}

#[tokio::test]
async fn test_run_continues_immediately_after_work_and_forwards_provider() {
    // Setup completed work followed by cancellation on the immediate next claim
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_mock = cancellation_token.clone();
    let mut sequence = Sequence::new();
    let mut db = MockDB::new();
    db.expect_reconcile_next_event_enrollment()
        .times(1)
        .in_sequence(&mut sequence)
        .withf(|provider| *provider == Some(PaymentProvider::Stripe))
        .returning(|_| {
            Ok(Some(EventEnrollmentReconciliationOutcome {
                community_id: Uuid::from_u128(1),
                event_id: Uuid::from_u128(2),
                group_id: Uuid::from_u128(3),
            }))
        });
    db.expect_reconcile_next_event_enrollment()
        .times(1)
        .in_sequence(&mut sequence)
        .withf(|provider| *provider == Some(PaymentProvider::Stripe))
        .returning(move |_| {
            cancellation_token_for_mock.cancel();
            Ok(None)
        });
    let worker = EnrollmentWorker {
        cancellation_token,
        db: Arc::new(db),
        payment_provider: Some(PaymentProvider::Stripe),
    };

    // Run the worker until the second claim cancels it
    timeout(Duration::from_secs(1), worker.run())
        .await
        .expect("worker to continue without a success pause");
}

#[tokio::test]
async fn test_run_stops_before_database_work_when_canceled() {
    // Setup a canceled worker that must not reconcile enrollment
    let mut db = MockDB::new();
    db.expect_reconcile_next_event_enrollment().never();
    let db: DynDB = Arc::new(db);
    let worker = EnrollmentWorker {
        cancellation_token: CancellationToken::new(),
        db,
        payment_provider: Some(PaymentProvider::Stripe),
    };
    worker.cancellation_token.cancel();

    // Run the worker through graceful shutdown
    worker.run().await;
}

#[tokio::test]
async fn test_run_stops_pending_reconciliation_after_cancellation() {
    // Setup reconciliation work that remains pending after it starts
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_task = cancellation_token.clone();
    let reconciliation_started = Arc::new(Notify::new());
    let reconciliation_started_for_task = reconciliation_started.clone();
    let reconciliation_task = tokio::spawn(async move {
        run_until_cancelled(&cancellation_token_for_task, async move {
            reconciliation_started_for_task.notify_one();
            pending::<()>().await;
        })
        .await
    });
    timeout(Duration::from_secs(1), reconciliation_started.notified())
        .await
        .expect("enrollment reconciliation to start");

    // Cancel and require the pending reconciliation to be dropped promptly
    cancellation_token.cancel();
    let result = timeout(Duration::from_secs(1), reconciliation_task)
        .await
        .expect("enrollment reconciliation to stop promptly")
        .expect("enrollment reconciliation task to complete");
    assert!(result.is_none());
}
