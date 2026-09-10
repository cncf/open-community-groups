//! Contract tests for the `DBEvent` functions.

use anyhow::Result;
use chrono::{DateTime, Utc};
use tokio_postgres::error::{DbError, SqlState};

use crate::{
    db::{DB, event::DBEvent},
    handlers::error::USER_FACING_DB_ERROR_CODE,
    types::{
        event::{EventEnrollmentStatus, EventKind},
        payments::{
            EventPurchaseChargeModel, EventRefundRequestStatus, ExternalPaymentInfo,
            PaymentProvider,
        },
    },
};

use super::helpers::{
    attendee_id, cancellation_lock_attendee_id, cancellation_lock_event_id,
    cfs_add_lock_proposal_id, community_id, contract_tests_db, contract_tests_pool, event_id,
    external_event_id, external_pending_purchase_id, external_pending_user_id, invitation_offer_id,
    invitation_ticket_type_id, leaver_id, mutation_event_id, organizer_id, pre_registered_id,
    refund_event_id, refund_offer_user_id, refund_rejected_buyer_id, rejected_request_user_id,
    session_proposal_id, status_event_id, status_expired_user_id, status_pending_payment_user_id,
    subgroup_id,
};

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_add_cfs_submission_blocks_no_key_updates() -> Result<()> {
    // Setup independent submission and proposal-lock connections
    let pool = contract_tests_pool()?;
    let proposal_client = pool.get().await?;
    let submission_client = pool.get().await?;

    // Add a submission while retaining its proposal share lock
    submission_client.batch_execute("begin").await?;
    submission_client
        .query_one(
            "select add_cfs_submission($1::uuid, $2::uuid, $3::uuid, $4::uuid, null::uuid[])",
            &[
                &community_id(),
                &event_id(),
                &organizer_id(),
                &cfs_add_lock_proposal_id(),
            ],
        )
        .await?;

    // Probe with a lock mode that does not conflict with the foreign-key lock
    proposal_client
        .batch_execute("begin; set local lock_timeout = '250ms'")
        .await?;
    let lock_result = proposal_client
        .query_one(
            "select session_proposal_id from session_proposal where session_proposal_id = $1::uuid for no key update",
            &[&cfs_add_lock_proposal_id()],
        )
        .await;

    // Release both transactions before checking the lock outcome
    proposal_client.batch_execute("rollback").await?;
    submission_client.batch_execute("rollback").await?;

    // Check the explicit share lock blocks a competing non-key update
    let lock_err = lock_result.expect_err("proposal update should wait for the submission lock");
    assert_eq!(lock_err.code(), Some(&SqlState::LOCK_NOT_AVAILABLE));

    Ok(())
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_enrollment_deserializes() -> Result<()> {
    // Setup the contract database and enrollment identifiers
    let db = contract_tests_db()?;

    // Load attendee enrollment through the Rust contract
    let enrollment = db
        .get_event_enrollment(community_id(), event_id(), attendee_id())
        .await?;
    let offer_enrollment = db
        .get_event_enrollment(community_id(), event_id(), pre_registered_id())
        .await?;
    let refund_offer_enrollment = db
        .get_event_enrollment(community_id(), refund_event_id(), refund_offer_user_id())
        .await?;
    let rejected_refund_enrollment = db
        .get_event_enrollment(
            community_id(),
            refund_event_id(),
            refund_rejected_buyer_id(),
        )
        .await?;
    let rejected_request_enrollment = db
        .get_event_enrollment(
            community_id(),
            refund_event_id(),
            rejected_request_user_id(),
        )
        .await?;
    let expired_offer_enrollment = db
        .get_event_enrollment(community_id(), status_event_id(), status_expired_user_id())
        .await?;
    let pending_payment_enrollment = db
        .get_event_enrollment(
            community_id(),
            status_event_id(),
            status_pending_payment_user_id(),
        )
        .await?;
    let enrollment_json = serde_json::to_value(&enrollment)?;

    // Check attendee enrollment omits purchase-document routing
    assert_eq!(enrollment.status, EventEnrollmentStatus::Attendee);
    assert!(enrollment.is_checked_in);
    assert!(enrollment.manually_invited);
    assert!(enrollment_json.get("provider_invoice_url").is_none());

    // Check owned ticket offers expose their exact offer and tier identifiers
    assert_eq!(
        offer_enrollment.status,
        EventEnrollmentStatus::InvitationApproved
    );
    assert_eq!(
        offer_enrollment.admission_offer_id,
        Some(invitation_offer_id())
    );
    assert_eq!(
        offer_enrollment.event_ticket_type_id,
        Some(invitation_ticket_type_id())
    );

    // Refund processing and disabled approval suppress stale offer/request actions
    assert_eq!(refund_offer_enrollment.status, EventEnrollmentStatus::None);
    assert_eq!(
        rejected_refund_enrollment.status,
        EventEnrollmentStatus::Attendee
    );
    assert_eq!(
        rejected_refund_enrollment.refund_rejection_reason.as_deref(),
        Some("Outside the refund policy window")
    );
    assert_eq!(
        rejected_refund_enrollment.refund_request_status,
        Some(EventRefundRequestStatus::Rejected)
    );
    assert_eq!(
        rejected_request_enrollment.status,
        EventEnrollmentStatus::None
    );

    // Check attendee-facing pending purchase and expired offer encodings
    assert_eq!(
        expired_offer_enrollment.status,
        EventEnrollmentStatus::OfferExpired
    );
    assert_eq!(
        pending_payment_enrollment.status,
        EventEnrollmentStatus::PendingPayment
    );
    assert_eq!(
        pending_payment_enrollment.purchase_charge_model,
        Some(EventPurchaseChargeModel::DirectCharge)
    );
    assert_eq!(
        pending_payment_enrollment.resume_checkout_url.as_deref(),
        Some("https://example.test/checkout/status-pending")
    );
    assert!(pending_payment_enrollment.external_payment.is_none());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_enrollment_external_payment_deserializes() -> Result<()> {
    // Setup the contract database and pending external purchase fixture
    let db = contract_tests_db()?;

    // Load pending external enrollment through the Rust contract
    let enrollment = db
        .get_event_enrollment(
            community_id(),
            external_event_id(),
            external_pending_user_id(),
        )
        .await?;

    // Check pending external purchases expose payment instructions without a checkout URL
    assert_eq!(enrollment.status, EventEnrollmentStatus::PendingPayment);
    assert_eq!(enrollment.purchase_amount_minor, Some(5000));
    assert_eq!(
        enrollment.purchase_charge_model,
        Some(EventPurchaseChargeModel::External)
    );
    assert!(enrollment.resume_checkout_url.is_none());
    assert_eq!(
        enrollment.external_payment,
        Some(ExternalPaymentInfo {
            amount_minor: 5000,
            currency_code: "USD".to_string(),
            deadline: DateTime::parse_from_rfc3339("2099-08-30T10:00:00Z")?.with_timezone(&Utc),
            reference: external_pending_purchase_id(),
            url: "https://pay.example.test/contract-external".to_string(),
            instructions: Some("Wire transfer using the purchase reference.".to_string()),
        })
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_full_by_slug_deserializes() -> Result<()> {
    // Setup the contract database and event slugs
    let db = contract_tests_db()?;

    // Load the full event by slug through the Rust contract
    let event = db
        .get_event_full_by_slug(community_id(), "contract-group", "future-contract-event")
        .await?
        .expect("contract event should exist");

    // Check the event and nested collection fields
    assert_eq!(event.attendee_count, 2);
    assert_eq!(event.event_id, event_id());
    assert_eq!(event.name, "Future Contract Event");
    assert_eq!(event.sessions.len(), 1);
    assert_eq!(event.sponsors.len(), 1);

    // Check public capacity follows the visible ticket inventory
    assert_eq!(event.capacity, Some(100));
    assert_eq!(event.remaining_capacity, Some(98));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_registration_questions_deserializes() -> Result<()> {
    // Setup the contract database and event fixture
    let db = contract_tests_db()?;

    // Load registration questions through the Rust contract
    let questions = db
        .get_event_registration_questions(community_id(), event_id())
        .await?;

    // Check the question and option fields
    assert_eq!(questions.len(), 1);
    assert_eq!(questions[0].prompt, "Meal preference");
    assert_eq!(questions[0].options.len(), 1);
    assert_eq!(questions[0].options[0].label, "Vegetarian");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_summary_by_id_deserializes() -> Result<()> {
    // Setup the contract database and event identifier
    let db = contract_tests_db()?;

    // Load the event summary by identifier
    let event = db.get_event_summary_by_id(community_id(), event_id()).await?;

    // Check identity, kind, and name fields
    assert_eq!(event.event_id, event_id());
    assert!(
        event
            .ticket_types
            .as_ref()
            .is_some_and(|ticket_types| !ticket_types.is_empty())
    );
    assert_eq!(event.kind, EventKind::Hybrid);
    assert_eq!(event.name, "Future Contract Event");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_leave_event_deserializes() -> Result<()> {
    // Setup the contract database and attendee fixture
    let db = contract_tests_db()?;

    // Leave the event through the Rust contract
    let outcome = db
        .leave_event(
            community_id(),
            mutation_event_id(),
            leaver_id(),
            Some(PaymentProvider::Stripe),
        )
        .await?;

    // Check the prior status and waitlist outcome
    assert_eq!(outcome.left_status, EventEnrollmentStatus::Attendee);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_session_proposals_for_cfs_event_deserializes() -> Result<()> {
    // Setup the contract database and call-for-sessions event
    let db = contract_tests_db()?;

    // Load eligible user proposals through the Rust contract
    let proposals = db
        .list_user_session_proposals_for_cfs_event(attendee_id(), event_id())
        .await?;

    // Check submission state and proposal fields
    assert_eq!(proposals.len(), 1);
    assert!(proposals[0].is_submitted);
    assert_eq!(proposals[0].session_proposal_id, session_proposal_id());
    assert_eq!(
        proposals[0].submission_status_id.as_deref(),
        Some("approved")
    );
    assert_eq!(proposals[0].title, "Contract Rust Proposal");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_lock_events_for_cancellation_serializes_rsvp() -> Result<()> {
    // Setup independent cancellation and RSVP connections
    let db = contract_tests_db()?;
    let racing_pool = contract_tests_pool()?;
    let racing_client = racing_pool.get().await?;
    racing_client.batch_execute("set lock_timeout = '250ms'").await?;

    // Lock the event in the cancellation transaction
    let uow = db.begin().await?;
    uow.lock_events_for_cancellation(subgroup_id(), &[cancellation_lock_event_id()])
        .await?;

    // Check a competing RSVP cannot pass the cancellation lock
    let lock_err = racing_client
        .query_one(
            "select attend_event($1::uuid, $2::uuid, $3::uuid, null::jsonb)",
            &[
                &community_id(),
                &cancellation_lock_event_id(),
                &cancellation_lock_attendee_id(),
            ],
        )
        .await
        .expect_err("competing RSVP should wait for the cancellation lock");
    assert_eq!(lock_err.code(), Some(&SqlState::LOCK_NOT_AVAILABLE));

    // Cancel and commit while retaining ownership of the event lock
    uow.cancel_event(organizer_id(), subgroup_id(), cancellation_lock_event_id())
        .await?;
    uow.commit().await?;

    // Check the serialized RSVP observes the terminal canceled state
    let canceled_err = racing_client
        .query_one(
            "select attend_event($1::uuid, $2::uuid, $3::uuid, null::jsonb)",
            &[
                &community_id(),
                &cancellation_lock_event_id(),
                &cancellation_lock_attendee_id(),
            ],
        )
        .await
        .expect_err("RSVP should fail after cancellation commits");
    assert_eq!(
        canceled_err.as_db_error().map(DbError::message),
        Some("event not found or inactive")
    );
    assert_eq!(
        canceled_err.code(),
        Some(&SqlState::from_code(USER_FACING_DB_ERROR_CODE))
    );

    Ok(())
}
