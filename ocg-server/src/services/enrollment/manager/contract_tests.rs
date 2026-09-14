//! Real-database contracts for the enrollment manager: transactional
//! compositions that mocks cannot prove, run by `just db-contract-tests`.

use std::sync::Arc;

use anyhow::Result;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::{
        DynDB, PgDB,
        contract_tests::helpers::{
            community_id, contract_tests_db, contract_tests_pool, group_id, lifecycle_cancelee_id,
            lifecycle_rollback_cancelee_id, mutation_event_id, organizer_id,
        },
    },
    services::{
        enrollment::{
            EnrollmentError, EnrollmentManager, OrganizerCancellationInput, PgEnrollmentManager,
        },
        notifications::MockNotificationsManager,
        payments::MockPaymentsManager,
    },
};

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_enrollment_manager_organizer_cancellation_commits_with_notification()
-> Result<()> {
    // Setup the manager over the real database
    let db = contract_tests_db()?;
    let manager = sample_enrollment_manager(db);
    let pool = contract_tests_pool()?;
    let client = pool.get().await?;
    let user_id = lifecycle_cancelee_id();

    // Cancel the confirmed free attendance as the organizer
    manager
        .cancel_attendance_as_organizer(&OrganizerCancellationInput {
            actor_user_id: organizer_id(),
            community_id: community_id(),
            event_id: mutation_event_id(),
            group_id: group_id(),
            user_id,
        })
        .await?;

    // Check the attendance cancellation and its required notification committed together
    let attendance_status: String = client
        .query_one(
            "select status::text from event_attendee where event_id = $1::uuid and user_id = $2::uuid",
            &[&mutation_event_id(), &user_id],
        )
        .await?
        .get(0);
    assert_eq!(attendance_status, "attendance-canceled");
    let notifications: i64 = client
        .query_one(
            "select count(*) from notification where user_id = $1::uuid and kind = 'event-attendance-canceled'",
            &[&user_id],
        )
        .await?
        .get(0);
    assert_eq!(notifications, 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_enrollment_manager_failing_required_enqueue_rolls_back_cancellation()
-> Result<()> {
    // Setup the manager over the real database
    let db = contract_tests_db()?;
    let manager = sample_enrollment_manager(db);
    let pool = contract_tests_pool()?;
    let client = pool.get().await?;
    let user_id = lifecycle_rollback_cancelee_id();

    // Cancel with a community the event does not belong to so the required
    // notification context load fails after the attendance mutation
    let err = manager
        .cancel_attendance_as_organizer(&OrganizerCancellationInput {
            actor_user_id: organizer_id(),
            community_id: Uuid::new_v4(),
            event_id: mutation_event_id(),
            group_id: group_id(),
            user_id,
        })
        .await
        .expect_err("required enqueue failure should fail the cancellation");
    assert!(matches!(err, EnrollmentError::Other(_)));

    // Check the attendance change rolled back and nothing was enqueued
    let attendance_status: String = client
        .query_one(
            "select status::text from event_attendee where event_id = $1::uuid and user_id = $2::uuid",
            &[&mutation_event_id(), &user_id],
        )
        .await?
        .get(0);
    assert_eq!(attendance_status, "confirmed");
    let notifications: i64 = client
        .query_one(
            "select count(*) from notification where user_id = $1::uuid and kind = 'event-attendance-canceled'",
            &[&user_id],
        )
        .await?
        .get(0);
    assert_eq!(notifications, 0);

    Ok(())
}

// Helpers.

/// Creates an enrollment manager over the real database with inert provider doubles.
fn sample_enrollment_manager(db: PgDB) -> PgEnrollmentManager {
    // Setup payments manager mock
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_configured_provider().return_const(None);
    let db: DynDB = Arc::new(db);

    PgEnrollmentManager::new(
        db,
        Arc::new(MockNotificationsManager::new()),
        Arc::new(payments_manager),
        HttpServerConfig::default(),
    )
}
