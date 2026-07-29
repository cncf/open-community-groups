use std::sync::Arc;

use anyhow::anyhow;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::{DynDB, mock::MockDB},
    handlers::tests::{sample_event_summary, sample_site_settings},
    services::notifications::NotificationKind,
    types::{event::EventEnrollmentReconciliationOutcome, payments::PaymentProvider},
};

use super::EnrollmentWorker;

#[tokio::test]
async fn test_process_next_event_enqueues_non_ticketed_promotion_notification() {
    // Setup one reconciliation outcome with a non-ticketed promotion
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let promoted_user_id = Uuid::new_v4();
    let mut tx = MockDB::new();
    tx.expect_reconcile_next_event_enrollment()
        .times(1)
        .withf(|provider| *provider == Some(PaymentProvider::Stripe))
        .returning(move |_| {
            Ok(Some(EventEnrollmentReconciliationOutcome {
                community_id,
                event_id,
                group_id,
                non_ticketed_promoted_user_ids: vec![promoted_user_id],
            }))
        });
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(sample_event_summary(event_id, group_id)));
    tx.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventWaitlistPromoted)
                && notification.recipients == vec![promoted_user_id]
        })
        .returning(|_| Ok(()));
    tx.expect_commit().times(1).returning(|| Ok(()));
    tx.expect_rollback().never();
    let mut db = MockDB::new();
    db.expect_begin().times(1).return_once(|| Ok(Box::new(tx)));
    let worker = enrollment_worker(db);

    // Process the due reconciliation outcome
    let processed = worker.process_next_event().await.unwrap();

    // Check the worker commits after enqueueing the required notification
    assert!(processed);
}

#[tokio::test]
async fn test_process_next_event_propagates_database_failure() {
    // Setup a worker whose reconciliation operation fails
    let mut tx = MockDB::new();
    tx.expect_reconcile_next_event_enrollment()
        .times(1)
        .withf(|provider| *provider == Some(PaymentProvider::Stripe))
        .returning(|_| Err(anyhow!("reconciliation failed")));
    tx.expect_commit().never();
    tx.expect_rollback().times(1).returning(|| Ok(()));
    let mut db = MockDB::new();
    db.expect_begin().times(1).return_once(|| Ok(Box::new(tx)));
    let worker = enrollment_worker(db);

    // Process the next due event
    let result = worker.process_next_event().await;

    // Check the database failure remains visible at the worker boundary
    assert_eq!(result.unwrap_err().to_string(), "reconciliation failed");
}

#[tokio::test]
async fn test_process_next_event_propagates_notification_failure_and_rolls_back() {
    // Setup one reconciliation outcome whose required notification fails
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let promoted_user_id = Uuid::new_v4();
    let mut tx = MockDB::new();
    tx.expect_reconcile_next_event_enrollment()
        .times(1)
        .withf(|provider| *provider == Some(PaymentProvider::Stripe))
        .returning(move |_| {
            Ok(Some(EventEnrollmentReconciliationOutcome {
                community_id,
                event_id,
                group_id,
                non_ticketed_promoted_user_ids: vec![promoted_user_id],
            }))
        });
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(sample_event_summary(event_id, group_id)));
    tx.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventWaitlistPromoted)
                && notification.recipients == vec![promoted_user_id]
        })
        .returning(|_| Err(anyhow!("notification enqueue failed")));
    tx.expect_commit().never();
    tx.expect_rollback().times(1).returning(|| Ok(()));
    let mut db = MockDB::new();
    db.expect_begin().times(1).return_once(|| Ok(Box::new(tx)));
    let worker = enrollment_worker(db);

    // Process the due reconciliation outcome
    let result = worker.process_next_event().await;

    // Check the required notification failure rolls back reconciliation
    assert_eq!(
        result.unwrap_err().to_string(),
        "notification enqueue failed"
    );
}

#[tokio::test]
async fn test_process_next_event_returns_false_when_no_event_is_due() {
    // Setup a worker with no due enrollment work
    let mut tx = MockDB::new();
    tx.expect_reconcile_next_event_enrollment()
        .times(1)
        .withf(|provider| *provider == Some(PaymentProvider::Stripe))
        .returning(|_| Ok(None));
    tx.expect_commit().times(1).returning(|| Ok(()));
    tx.expect_rollback().never();
    let mut db = MockDB::new();
    db.expect_begin().times(1).return_once(|| Ok(Box::new(tx)));
    let worker = enrollment_worker(db);

    // Process the next due event
    let processed = worker.process_next_event().await.unwrap();

    // Check the worker selects its idle path
    assert!(!processed);
}

#[tokio::test]
async fn test_process_next_event_returns_true_when_event_is_reconciled() {
    // Setup a worker with one due event
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let mut tx = MockDB::new();
    tx.expect_reconcile_next_event_enrollment()
        .times(1)
        .withf(|provider| *provider == Some(PaymentProvider::Stripe))
        .returning(move |_| {
            Ok(Some(EventEnrollmentReconciliationOutcome {
                community_id,
                event_id,
                group_id,
                non_ticketed_promoted_user_ids: vec![],
            }))
        });
    tx.expect_commit().times(1).returning(|| Ok(()));
    tx.expect_rollback().never();
    let mut db = MockDB::new();
    db.expect_begin().times(1).return_once(|| Ok(Box::new(tx)));
    let worker = enrollment_worker(db);

    // Process the next due event
    let processed = worker.process_next_event().await.unwrap();

    // Check completed work continues without the idle pause
    assert!(processed);
}

#[tokio::test]
async fn test_run_stops_before_database_work_when_canceled() {
    // Setup a canceled worker and prohibit new reconciliation work
    let mut db = MockDB::new();
    db.expect_begin().never();
    let worker = enrollment_worker(db);
    worker.cancellation_token.cancel();

    // Run the worker after cancellation
    worker.run().await;
}

// Helpers.

/// Creates an enrollment worker using the configured Stripe provider.
fn enrollment_worker(db: MockDB) -> EnrollmentWorker {
    let db: DynDB = Arc::new(db);

    EnrollmentWorker {
        cancellation_token: CancellationToken::new(),
        db,
        server_cfg: HttpServerConfig::default(),

        payment_provider: Some(PaymentProvider::Stripe),
    }
}
