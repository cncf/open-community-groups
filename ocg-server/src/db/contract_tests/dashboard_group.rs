//! Contract tests for the `DBDashboardGroup` functions.

use std::collections::HashMap;

use anyhow::{Context, Result};
use chrono::{DateTime, NaiveDate, Utc};
use tokio_postgres::{
    error::{DbError, SqlState},
    types::{Json, ToSql},
};

use crate::{
    db::{
        DB,
        common::DBCommon,
        dashboard::{
            group::{
                DBDashboardGroup, EventAdmissionAllocationOutcome, EventAdmissionAllocationResult,
                EventAttendeeCancellationStatus, EventAttendeeInvitationInput,
            },
            user::DBDashboardUser,
        },
        payments::{DBPayments, EventPurchaseRefundKind, EventPurchaseRefundStatus},
    },
    handlers::error::USER_FACING_DB_ERROR_CODE,
    templates::dashboard::{
        audit::AuditLogFilters,
        group::{
            attendees::{
                AttendeeEnrollmentStatus, AttendeeEnrollmentStatusFilter, AttendeesFilters,
            },
            check_in::CheckInOutcome,
            events::{Event as EventUpdate, EventsListFilters},
            invitation_requests::{InvitationRequestsFilters, InvitationRequestsStatusFilter},
            members::GroupMembersFilters,
            refunds::{FinancialRecoveryKind, GroupRefundStatus, RefundsFilters, RefundsView},
            sponsors::GroupSponsorsFilters,
            submissions::CfsSubmissionsFilters as GroupCfsSubmissionsFilters,
            team::GroupTeamFilters,
            waitlist::WaitlistFilters,
        },
    },
    types::{
        badges::{
            AwardedBadgesFilters, Badge, BadgeArtwork, BadgeAwardDefinition, BadgeAwardInput,
            BadgeAwardSource, BadgeAwardSourceFilter, BadgeFilters, BadgeStatusList,
            PublicBadgeSnapshot, PublicBadgeSnapshotIssuer, PublicUserBadge, UserBadge,
        },
        event::{
            EventAdmissionOfferSource, EventAdmissionOfferStatus, EventDeleteEligibility,
            EventInvitationRequestStatus, EventKind,
        },
        group::GroupRole,
        payments::{EventPurchaseChargeModel, PaymentProvider},
        questionnaire::QuestionnaireAnswerValue,
    },
};

use super::helpers::{
    active_user_badge_id, attendee_id, badge_artwork_id, badge_id, badge_status_list_id,
    cancelee_id, cancellation_lock_attendee_id, cancellation_lock_event_id, cfs_lock_session_id,
    cfs_submission_id, check_in_code, claim_group_id, community_id, contract_active_user_badge,
    contract_badge_snapshot, contract_tests_db, contract_tests_pool, event_category_id, event_id,
    external_completed_purchase_id, external_completed_user_id, external_event_id,
    external_pending_purchase_id, external_pending_user_id, financial_recovery_adjustment_job_id,
    financial_recovery_credit_note_job_id, group_id, group_lock_event_update,
    group_lock_first_event_id, group_lock_second_event_id, group_sponsor_id, invitation_offer_id,
    invitation_ticket_type_id, invite_event_id, invitee_id, mutation_event_id, mutation_offer_id,
    organizer_id, paid_cancellation_purchase_id, paid_cancellation_user_id, paid_event_id,
    parse_uuid, pre_registered_id, queue_invite_event_id, queue_invitee_id, refund_reject_buyer_id,
    refund_reject_purchase_id, request_event_id, requester_id, revoked_user_badge_id,
    session_proposal_id, status_canceled_user_id, status_declined_user_id, status_event_id,
    status_expired_user_id, subgroup_id, waitlist_id,
};

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_accept_event_invitation_request_deserializes() -> Result<()> {
    // Setup the contract database and pending RSVP request fixture
    let db = contract_tests_db()?;

    // Accept the pending request through the Rust JSON contract
    let result = db
        .accept_event_invitation_request(
            organizer_id(),
            subgroup_id(),
            request_event_id(),
            requester_id(),
            None,
            None,
        )
        .await?;

    // Require the successful allocation variant
    let EventAdmissionAllocationResult::Success(allocation) = result else {
        panic!("request acceptance should succeed");
    };

    // Check the RSVP allocation fields deserialize completely
    assert_eq!(
        allocation.outcome,
        EventAdmissionAllocationOutcome::OfferCreated
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_award_badge_deserializes() -> Result<()> {
    // Setup the contract database and badge recipient
    let db = contract_tests_db()?;

    // Queue the badge award through the Rust contract
    let outcome = db
        .award_badge(
            organizer_id(),
            community_id(),
            group_id(),
            &BadgeAwardInput {
                badge_id: badge_id(),
                user_ids: vec![organizer_id()],
                event_id: None,
            },
        )
        .await?;

    // Check the award queue outcome
    assert_eq!(outcome.queued_count, 1);
    assert_eq!(outcome.skipped_count, 0);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
#[allow(clippy::too_many_lines)]
async fn db_contracts_badge_json_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Read every badge JSON shape through its production database wrapper
    let artwork = db.list_badge_artwork(group_id()).await?;
    let badges = db
        .list_badges(
            group_id(),
            &BadgeFilters {
                limit: 10,
                offset: 0,
                query: Some("Contract Participant".to_string()),
            },
        )
        .await?;
    let awards = db
        .list_awarded_badges(
            group_id(),
            &AwardedBadgesFilters {
                limit: 10,
                offset: 0,
                ..Default::default()
            },
        )
        .await?;
    let group_awards = db
        .list_awarded_badges(
            group_id(),
            &AwardedBadgesFilters {
                limit: 10,
                offset: 0,
                source: Some(BadgeAwardSourceFilter::Group),
                ..Default::default()
            },
        )
        .await?;
    let active = db
        .get_user_badge(attendee_id(), active_user_badge_id())
        .await?
        .context("active contract badge should exist")?;
    let public = db
        .get_public_user_badge(active_user_badge_id())
        .await?
        .context("public contract badge should exist")?;
    let profile = db.list_user_public_badges(50, 0, "contract-attendee").await?;
    let status = db
        .get_badge_status_list(badge_status_list_id())
        .await?
        .context("contract status list should exist")?;
    let user_badges = db.list_user_badges(attendee_id()).await?;

    // Check every required, optional, and revocation field
    let snapshot = contract_badge_snapshot();
    assert_eq!(
        artwork,
        vec![BadgeArtwork {
            badge_artwork_id: badge_artwork_id(),
            file_name: "contract-badge.png".to_string(),
        }]
    );
    assert_eq!(badges.total, 1);
    assert_eq!(
        badges.badges,
        vec![Badge {
            badge_id: badge_id(),
            criteria: "Attend the contract event".to_string(),
            description: "Recognizes contract event participation".to_string(),
            image_file_name: "contract-badge.png".to_string(),
            name: "Contract Participant".to_string(),
        }]
    );
    assert_eq!(awards.total, 2);
    assert_eq!(
        awards.badges,
        vec![BadgeAwardDefinition {
            badge_id: badge_id(),
            name: "Contract Participant".to_string(),
        }]
    );
    assert_eq!(
        awards.sources,
        vec![
            BadgeAwardSource {
                name: "Group".to_string(),
                event_id: None,
            },
            BadgeAwardSource {
                name: "Future Contract Event".to_string(),
                event_id: Some(event_id()),
            },
        ]
    );
    assert_eq!(
        awards.awards,
        vec![
            contract_active_user_badge(
                snapshot.clone(),
                Some("Future Contract Event".to_string()),
                Some("Contract Attendee".to_string()),
                Some("contract-attendee".to_string()),
            ),
            UserBadge {
                awarded_at: DateTime::from_timestamp(1_704_880_800, 0).unwrap(),
                badge_status_list_id: badge_status_list_id(),
                display_order: 1,
                group_id: group_id(),
                is_listed: false,
                snapshot: snapshot.clone(),
                status_list_index: 11,
                user_badge_id: revoked_user_badge_id(),

                badge_id: Some(badge_id()),
                event_id: None,
                event_name: None,
                identity_bound_at: None,
                identity_hash: None,
                identity_salt: None,
                recipient_name: Some("Contract Attendee".to_string()),
                recipient_username: Some("contract-attendee".to_string()),
                revocation_reason: Some("contract revocation".to_string()),
                revoked_at: Some(DateTime::from_timestamp(1_705_140_000, 0).unwrap()),
                revoked_by_user_id: Some(organizer_id()),
                user_id: Some(attendee_id()),
            },
        ]
    );
    assert_eq!(group_awards.total, 1);
    assert_eq!(
        group_awards.awards.first().map(|award| award.user_badge_id),
        Some(revoked_user_badge_id())
    );
    assert_eq!(
        active,
        contract_active_user_badge(snapshot.clone(), None, None, None)
    );
    assert_eq!(
        public,
        contract_active_user_badge(
            snapshot.clone(),
            None,
            Some("Contract Attendee".to_string()),
            Some("contract-attendee".to_string()),
        )
    );
    assert_eq!(
        profile,
        vec![PublicUserBadge {
            snapshot: PublicBadgeSnapshot {
                image_file_name: "contract-badge.png".to_string(),
                issuer: PublicBadgeSnapshotIssuer {
                    community_name: "Contract Community".to_string(),
                    group_name: "Contract Group".to_string(),
                },
                name: "Contract Participant".to_string(),
            },
            user_badge_id: active_user_badge_id(),
        }]
    );
    assert_eq!(
        status,
        BadgeStatusList {
            badge_status_list_id: badge_status_list_id(),
            group_id: group_id(),
            revoked_indexes: vec![11],
        }
    );
    assert_eq!(
        user_badges,
        vec![contract_active_user_badge(snapshot, None, None, None)]
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_cancel_event_admission_offer_deserializes() -> Result<()> {
    // Setup the contract database and dedicated RSVP offer fixture
    let db = contract_tests_db()?;

    // Cancel the offer through the Rust JSON contract
    let outcome = db
        .cancel_event_admission_offer(organizer_id(), group_id(), mutation_offer_id(), None)
        .await?;

    // Check the reconciliation context deserializes completely
    assert_eq!(outcome.community_id, community_id());
    assert_eq!(outcome.event_id, mutation_event_id());
    assert_eq!(outcome.group_id, group_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_cancel_event_attendee_attendance_deserializes() -> Result<()> {
    // Setup the contract database and attendance fixture
    let db = contract_tests_db()?;

    // Cancel the attendee through the Rust contract
    let outcome = db
        .cancel_event_attendee_attendance(
            organizer_id(),
            group_id(),
            mutation_event_id(),
            cancelee_id(),
            None,
        )
        .await?;

    // Check the cancellation lifecycle result
    assert_eq!(
        outcome.cancellation_status,
        EventAttendeeCancellationStatus::AttendanceCanceled
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_cancel_event_attendee_attendance_queues_paid_refund_deserializes()
-> Result<()> {
    // Setup the contract database and paid attendance fixture
    let db = contract_tests_db()?;

    // Queue cancellation through the real paid-attendance database contract
    let outcome = db
        .cancel_event_attendee_attendance(
            organizer_id(),
            group_id(),
            paid_event_id(),
            paid_cancellation_user_id(),
            Some(PaymentProvider::Stripe),
        )
        .await?;

    // Check both cancellation and durable refund enums deserialize completely
    assert_eq!(
        outcome.cancellation_status,
        EventAttendeeCancellationStatus::RefundQueued
    );
    let refund = db.get_event_purchase_refund(paid_cancellation_purchase_id()).await?;
    assert_eq!(refund.event_purchase_id, paid_cancellation_purchase_id());
    assert_eq!(refund.kind, EventPurchaseRefundKind::AttendanceCancellation);
    assert_eq!(refund.status, EventPurchaseRefundStatus::ProviderPending);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_cfs_session_link_serializes_submission_rejection() -> Result<()> {
    // Setup independent session-link and submission-review connections
    let pool = contract_tests_pool()?;
    let review_client = pool.get().await?;
    let session_client = pool.get().await?;
    review_client.batch_execute("set lock_timeout = '250ms'").await?;
    session_client.batch_execute("begin").await?;

    // Link the approved submission while retaining its share lock
    session_client
        .execute(
            "insert into session (cfs_submission_id, ends_at, event_id, name, session_id, session_kind_id, starts_at) values ($1::uuid, '2099-05-20 18:30:00+00', $2::uuid, 'CFS Lock Session', $3::uuid, 'hybrid', '2099-05-20 18:00:00+00')",
            &[&cfs_submission_id(), &event_id(), &cfs_lock_session_id()],
        )
        .await?;

    // Check a concurrent rejection cannot pass the session-link share lock
    let lock_err = review_client
        .query_one(
            "select update_cfs_submission($1::uuid, $2::uuid, $3::uuid, '{\"label_ids\": [], \"status_id\": \"rejected\"}'::jsonb)",
            &[&organizer_id(), &event_id(), &cfs_submission_id()],
        )
        .await
        .expect_err("submission rejection should wait for the session link lock");
    assert_eq!(lock_err.code(), Some(&SqlState::LOCK_NOT_AVAILABLE));

    // Commit the session link before retrying the review
    session_client.batch_execute("commit").await?;

    // Check the serialized rejection observes the committed session link
    let linked_err = review_client
        .query_one(
            "select update_cfs_submission($1::uuid, $2::uuid, $3::uuid, '{\"label_ids\": [], \"status_id\": \"rejected\"}'::jsonb)",
            &[&organizer_id(), &event_id(), &cfs_submission_id()],
        )
        .await
        .expect_err("linked submissions should remain approved");
    assert_eq!(
        linked_err.as_db_error().map(DbError::message),
        Some("linked submissions must remain approved")
    );
    assert_eq!(
        linked_err.code(),
        Some(&SqlState::from_code(USER_FACING_DB_ERROR_CODE))
    );

    // Restore the shared submission fixture for later contract tests
    review_client
        .execute(
            "delete from session where session_id = $1::uuid",
            &[&cfs_lock_session_id()],
        )
        .await?;

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_check_in_attendee_by_code_deserializes() -> Result<()> {
    // Setup the contract database and already checked-in attendee credential
    let db = contract_tests_db()?;

    // Scan the credential through the Rust JSON contract
    let result = db
        .check_in_attendee_by_code(
            organizer_id(),
            check_in_code(),
            community_id(),
            event_id(),
            group_id(),
        )
        .await?;

    // Check duplicate outcome and attendee context deserialize completely
    assert_eq!(result.attendee.username, "contract-attendee");
    assert_eq!(result.attendee.name.as_deref(), Some("Contract Attendee"));
    assert_eq!(
        result.attendee.photo_url.as_deref(),
        Some("https://example.com/attendee.png")
    );
    assert_eq!(
        result.checked_in_at,
        DateTime::parse_from_rfc3339("2099-05-20T17:30:00Z")?
    );
    assert_eq!(result.outcome, CheckInOutcome::AlreadyCheckedIn);
    assert_eq!(result.ticket_title.as_deref(), Some("General Admission"));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_check_in_attendee_by_code_rejects_concurrently_revoked_code() -> Result<()> {
    // Setup independent event-lock, scanner, and credential-rotation connections
    let pool = contract_tests_pool()?;
    let event_lock_client = pool.get().await?;
    let scan_client = pool.get().await?;
    let rotation_client = pool.get().await?;
    event_lock_client.batch_execute("begin").await?;
    event_lock_client
        .query_one(
            "select event_id from event where event_id = $1::uuid for update",
            &[&event_id()],
        )
        .await?;

    // Start an old-credential scan while event validation is blocked
    let scan = tokio::spawn(async move {
        scan_client
            .query_one(
                "select check_in_attendee_by_code($1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::uuid)",
                &[
                    &organizer_id(),
                    &check_in_code(),
                    &community_id(),
                    &event_id(),
                    &group_id(),
                ],
            )
            .await
    });

    // Cancel and reconfirm attendance to rotate the credential before validation continues
    rotation_client
        .execute(
            "update event_attendee set attendance_canceled_at = current_timestamp, status = 'attendance-canceled' where event_id = $1::uuid and user_id = $2::uuid",
            &[&event_id(), &attendee_id()],
        )
        .await?;
    rotation_client
        .execute(
            "update event_attendee set attendance_canceled_at = null, attendance_canceled_by_user_id = null, status = 'confirmed' where event_id = $1::uuid and user_id = $2::uuid",
            &[&event_id(), &attendee_id()],
        )
        .await?;
    event_lock_client.batch_execute("commit").await?;
    let scan_result = scan.await?;

    // Restore the deterministic fixture credential before checking the scan failure
    rotation_client
        .execute(
            "update event_attendee set check_in_code = $1::uuid where event_id = $2::uuid and user_id = $3::uuid",
            &[&check_in_code(), &event_id(), &attendee_id()],
        )
        .await?;
    let scan_err =
        scan_result.expect_err("the revoked credential should not pass the attendee lock");
    assert_eq!(
        scan_err.as_db_error().map(DbError::message),
        Some("check-in credential not found")
    );
    assert_eq!(
        scan_err.code(),
        Some(&SqlState::from_code(USER_FACING_DB_ERROR_CODE))
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_check_in_event_serializes_concurrent_transitions() -> Result<()> {
    // Seed one unchecked attendee and open two independent check-in connections
    let pool = contract_tests_pool()?;
    let setup_client = pool.get().await?;
    let first_client = pool.get().await?;
    let second_client = pool.get().await?;
    let actor_user_id = organizer_id();
    let attendee_user_id = cancellation_lock_attendee_id();
    let check_in_community_id = community_id();
    let check_in_event_id = cancellation_lock_event_id();
    setup_client
        .execute(
            "insert into event_attendee (event_id, user_id, status) values ($1::uuid, $2::uuid, 'confirmed')",
            &[&check_in_event_id, &attendee_user_id],
        )
        .await?;

    // Race both organizer transitions against the same attendee row
    let check_in_params: [&(dyn ToSql + Sync); 4] = [
        &actor_user_id,
        &check_in_community_id,
        &check_in_event_id,
        &attendee_user_id,
    ];
    let (first_result, second_result) = tokio::join!(
        first_client.query_one(
            "select check_in_event($1::uuid, $2::uuid, $3::uuid, $4::uuid)",
            &check_in_params,
        ),
        second_client.query_one(
            "select check_in_event($1::uuid, $2::uuid, $3::uuid, $4::uuid)",
            &check_in_params,
        ),
    );

    // Load the persisted attendee and audit outcomes
    let state = setup_client
        .query_one(
            "select checked_in, checked_in_at from event_attendee where event_id = $1::uuid and user_id = $2::uuid",
            &[&check_in_event_id, &attendee_user_id],
        )
        .await?;
    let audit_count = setup_client
        .query_one(
            "select count(*) from audit_log where action = 'event_attendee_checked_in' and event_id = $1::uuid and resource_id = $2::uuid",
            &[&check_in_event_id, &attendee_user_id],
        )
        .await?
        .get::<_, i64>(0);

    // Check exactly one call transitioned, timestamped, and audited the attendee
    let first_transition = first_result?.get::<_, bool>(0);
    let second_transition = second_result?.get::<_, bool>(0);
    assert_ne!(first_transition, second_transition);
    assert!(state.get::<_, bool>(0));
    assert!(state.get::<_, Option<DateTime<Utc>>>(1).is_some());
    assert_eq!(audit_count, 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_event_ticketing_configuration_changed_deserializes() -> Result<()> {
    // Setup the contract database and the seeded paid event
    let db = contract_tests_db()?;

    // A venue change on the paid event governs its tax readiness
    let changed = db
        .event_ticketing_configuration_changed(
            community_id(),
            group_id(),
            paid_event_id(),
            &serde_json::json!({
                "kind_id": "in-person",
                "venue_city": "Oakland"
            }),
        )
        .await?;
    assert!(changed);

    // Dropping every ticket type makes the event free, so nothing to validate
    let unchanged = db
        .event_ticketing_configuration_changed(
            community_id(),
            group_id(),
            paid_event_id(),
            &serde_json::json!({
                "kind_id": "in-person",
                "ticket_types": [],
                "venue_city": "Oakland"
            }),
        )
        .await?;
    assert!(!unchanged);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_event_ticketing_configuration_changed_rejects_foreign_event() -> Result<()> {
    // Setup a direct connection to observe the SQLSTATE of the scope check
    let pool = contract_tests_pool()?;
    let client = pool.get().await?;

    // An event outside the group scope is rejected with the user-facing SQLSTATE
    let scope_err = client
        .query_one(
            "select event_ticketing_configuration_changed($1::uuid, $2::uuid, $3::uuid, $4::jsonb)",
            &[
                &community_id(),
                &subgroup_id(),
                &paid_event_id(),
                &Json(serde_json::json!({ "kind_id": "in-person" })),
            ],
        )
        .await
        .expect_err("events outside the group scope should be rejected");
    assert_eq!(
        scope_err.as_db_error().map(DbError::message),
        Some("event not found or inactive")
    );
    assert_eq!(
        scope_err.code(),
        Some(&SqlState::from_code(USER_FACING_DB_ERROR_CODE))
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_cfs_submission_notification_data_deserializes() -> Result<()> {
    // Setup the contract database and submission fixture
    let db = contract_tests_db()?;

    // Load notification data through the Rust contract
    let data = db
        .get_cfs_submission_notification_data(event_id(), cfs_submission_id())
        .await?;

    // Check the submission status and recipient fields
    assert_eq!(data.action_required_message, None);
    assert_eq!(data.status_id, "approved");
    assert_eq!(data.status_name, "Approved");
    assert_eq!(data.user_id, attendee_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_summary_dashboard_deserializes() -> Result<()> {
    // Setup the contract database and event fixture
    let db = contract_tests_db()?;

    // Load the dashboard event summary through the Rust contract
    let event = db
        .get_event_summary_dashboard(community_id(), group_id(), event_id())
        .await?;

    // Check shared summary fields
    assert_eq!(event.event_id, event_id());
    assert!(event.has_registration_questions);
    assert!(
        event
            .ticket_types
            .as_ref()
            .is_some_and(|ticket_types| !ticket_types.is_empty())
    );
    assert_eq!(event.kind, EventKind::Hybrid);

    // Check dashboard-only fields
    assert_eq!(event.attendee_count, Some(2));
    assert_eq!(
        event.created_by_display_name.as_deref(),
        Some("Contract Organizer")
    );
    assert_eq!(
        event.created_by_username.as_deref(),
        Some("contract-organizer")
    );
    assert_eq!(
        event.delete_eligibility,
        Some(EventDeleteEligibility::CancelFirst)
    );

    // Check the full ticket type inventory is included
    let ticket_types = event.ticket_types.as_deref().unwrap_or_default();
    assert_eq!(ticket_types.len(), 1);
    assert_eq!(ticket_types[0].title, "General Admission");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_external_payments_context_deserializes() -> Result<()> {
    // Setup the contract database and group fixture
    let db = contract_tests_db()?;

    // Load the external-payments settings context through the Rust contract
    let context = db
        .get_group_external_payments_context(community_id(), group_id())
        .await?;

    // Check eligibility, toggle, and window limits
    assert!(context.configured);
    assert!(context.eligible);
    assert!(context.enabled);
    assert_eq!(context.country_code.as_deref(), Some("US"));
    assert_eq!(context.default_payment_window_hours, Some(72));
    assert_eq!(context.max_payment_window_hours, Some(336));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_payment_recipient_deserializes() -> Result<()> {
    // Setup the contract database and group fixture
    let db = contract_tests_db()?;

    // Load the payment recipient through the Rust contract
    let payment_recipient = db
        .get_group_payment_recipient(community_id(), group_id())
        .await?
        .expect("contract group should have a payment recipient");

    // Check provider and recipient identifiers
    assert_eq!(payment_recipient.provider, PaymentProvider::Stripe);
    assert_eq!(payment_recipient.recipient_id, "acct_contract");
    assert_eq!(
        payment_recipient.seller_display_name,
        "Contract Fiscal Sponsor"
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_sponsor_deserializes() -> Result<()> {
    // Setup the contract database and sponsor fixture
    let db = contract_tests_db()?;

    // Load the group sponsor through the Rust contract
    let sponsor = db.get_group_sponsor(group_id(), group_sponsor_id()).await?;

    // Check sponsor identity and visibility fields
    assert_eq!(sponsor.group_sponsor_id, group_sponsor_id());
    assert_eq!(sponsor.name, "Contract Sponsor");
    assert!(sponsor.featured);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_stats_deserializes() -> Result<()> {
    // Setup the contract database and group fixture
    let db = contract_tests_db()?;

    // Load dashboard group statistics through the Rust contract
    let stats = db.get_group_stats(community_id(), group_id(), false).await?;

    // Check entity and page-view totals
    assert_eq!(stats.attendees.total, 1);
    assert_eq!(stats.events.total, 2);
    assert_eq!(stats.members.total, 1);
    assert_eq!(stats.page_views.events.total_views, 2);
    assert_eq!(stats.page_views.group.total_views, 3);
    assert_eq!(stats.page_views.total_views, 5);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_invite_event_attendee_deserializes() -> Result<()> {
    // Setup the contract database and dedicated invitee fixture
    let db = contract_tests_db()?;

    // Invite the registered user through the Rust JSON contract
    let result = db
        .invite_event_attendee(
            organizer_id(),
            subgroup_id(),
            invite_event_id(),
            &EventAttendeeInvitationInput {
                email: None,
                event_ticket_type_id: None,
                user_id: Some(invitee_id()),
            },
            None,
        )
        .await?;

    // Require the successful allocation variant
    let EventAdmissionAllocationResult::Success(allocation) = result else {
        panic!("invitation should succeed");
    };

    // Check the invitation allocation fields deserialize completely
    assert_eq!(
        allocation.outcome,
        EventAdmissionAllocationOutcome::OfferCreated
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_invite_event_attendee_queue_offer_deserializes() -> Result<()> {
    // Setup the contract database and queued invitee fixture
    let db = contract_tests_db()?;

    // Invite the queue head so reconciliation allocates the released seat
    let result = db
        .invite_event_attendee(
            organizer_id(),
            subgroup_id(),
            queue_invite_event_id(),
            &EventAttendeeInvitationInput {
                email: None,
                event_ticket_type_id: None,
                user_id: Some(queue_invitee_id()),
            },
            None,
        )
        .await?;

    // Require the queue-specific allocation variant
    let EventAdmissionAllocationResult::Success(allocation) = result else {
        panic!("queued invitation should succeed");
    };
    assert_eq!(
        allocation.outcome,
        EventAdmissionAllocationOutcome::QueueOffer
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_cfs_submission_statuses_for_review_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load review statuses through the Rust contract
    let statuses = db.list_cfs_submission_statuses_for_review().await?;

    // Check status ordering and display fields
    assert_eq!(statuses.len(), 4);
    assert_eq!(statuses[0].cfs_submission_status_id, "approved");
    assert_eq!(statuses[0].display_name, "Approved");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_event_approved_cfs_submissions_deserializes() -> Result<()> {
    // Setup the contract database and event fixture
    let db = contract_tests_db()?;

    // Load approved submissions through the Rust contract
    let submissions = db.list_event_approved_cfs_submissions(event_id()).await?;

    // Check proposal and speaker fields
    assert_eq!(submissions.len(), 1);
    assert_eq!(submissions[0].cfs_submission_id, cfs_submission_id());
    assert_eq!(submissions[0].session_proposal_id, session_proposal_id());
    assert_eq!(submissions[0].speaker_name, "Contract Attendee");
    assert_eq!(submissions[0].title, "Contract Rust Proposal");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_event_categories_deserializes() -> Result<()> {
    // Setup the contract database and community fixture
    let db = contract_tests_db()?;

    // Load event categories through the Rust contract
    let categories = db.list_event_categories(community_id()).await?;

    // Check the seeded category
    assert_eq!(categories.len(), 1);
    assert_eq!(categories[0].name, "Conference");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_event_cfs_submissions_deserializes() -> Result<()> {
    // Setup the contract database and submission filters
    let db = contract_tests_db()?;
    let filters = GroupCfsSubmissionsFilters {
        limit: Some(10),
        offset: Some(0),

        ..Default::default()
    };

    // Load event submissions through the Rust contract
    let output = db.list_event_cfs_submissions(event_id(), &filters).await?;

    // Check submission pagination totals
    assert_eq!(output.total, 1);
    assert_eq!(output.submissions.len(), 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_event_kinds_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load event kinds through the Rust contract
    let kinds = db.list_event_kinds().await?;

    // Check kind ordering and display fields
    assert_eq!(kinds.len(), 3);
    assert_eq!(kinds[0].event_kind_id, "hybrid");
    assert_eq!(kinds[0].display_name, "Hybrid");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_group_audit_logs_deserializes() -> Result<()> {
    // Setup the contract database and scoped audit filters
    let db = contract_tests_db()?;
    let filters = AuditLogFilters {
        // Scope to the fixture action so refund mutation tests do not interfere
        action: Some("group_payment_recipient_updated".to_string()),
        limit: Some(10),
        offset: Some(0),

        ..Default::default()
    };

    // Load group audit logs through the Rust contract
    let output = db.list_group_audit_logs(group_id(), &filters).await?;

    // Check pagination, actor, and resource fields
    assert_eq!(output.total, 1);
    assert_eq!(output.logs.len(), 1);
    assert_eq!(output.logs[0].action, "group_payment_recipient_updated");
    assert_eq!(
        output.logs[0].actor_username.as_deref(),
        Some("contract-organizer")
    );
    assert_eq!(output.logs[0].resource_id, group_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_group_check_in_events_deserializes() -> Result<()> {
    // Setup the contract database and group fixture
    let db = contract_tests_db()?;

    // Load scanner cards through the Rust JSON contract
    let events = db.list_group_check_in_events(group_id()).await?;

    // Check the narrow event card fields deserialize completely
    let event = events
        .iter()
        .find(|event| event.event_id == event_id())
        .expect("future contract event to be available for check-in");
    assert_eq!(event.event_id, event_id());
    assert!(!event.in_progress);
    assert_eq!(event.kind, EventKind::Hybrid);
    assert_eq!(event.name, "Future Contract Event");
    assert_eq!(
        event.starts_at,
        DateTime::parse_from_rfc3339("2099-05-20T17:00:00Z")?
    );
    assert_eq!(event.timezone.to_string(), "America/Los_Angeles");
    assert_eq!(
        event.logo_url.as_deref(),
        Some("https://example.com/future-event-logo.png")
    );
    assert_eq!(
        event.location.as_deref(),
        Some("Contract Hall, San Francisco, California, United States")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_group_events_deserializes() -> Result<()> {
    // Setup database and pagination filters
    let db = contract_tests_db()?;
    let filters = EventsListFilters {
        limit: Some(10),
        past_offset: Some(0),
        upcoming_offset: Some(0),

        ..Default::default()
    };

    // Load both dashboard event collections
    let events = db.list_group_events(group_id(), &filters).await?;

    // Check collection totals
    assert_eq!(events.past.total, 1);
    assert_eq!(events.upcoming.total, 4);

    // Check event capacity and occupied reservations deserialize together
    let event = events
        .upcoming
        .events
        .iter()
        .find(|event| event.event_id == event_id())
        .expect("future contract event to be listed");
    assert_eq!(event.attendee_count, Some(2));
    assert_eq!(event.capacity, Some(100));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_group_members_deserializes() -> Result<()> {
    // Setup the contract database and member filters
    let db = contract_tests_db()?;
    let filters = GroupMembersFilters {
        limit: Some(10),
        offset: Some(0),
    };

    // Load group members through the Rust contract
    let output = db.list_group_members(group_id(), &filters).await?;

    // Check pagination and member identity fields
    assert_eq!(output.total, 1);
    assert_eq!(output.members.len(), 1);
    assert_eq!(output.members[0].username, "contract-attendee");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_group_refunds_deserializes() -> Result<()> {
    // Setup the contract database and refund filters
    let db = contract_tests_db()?;
    let filters = RefundsFilters {
        view: RefundsView::All,
        event_id: Some(paid_event_id()),
        limit: Some(10),
        offset: Some(0),
        ts_query: Some("buyer-refund-reject.contract@example.com".to_string()),
    };

    // Load the filtered group refunds through the Rust contract
    let output = db.list_group_refunds(group_id(), &filters).await?;

    // Check event options and refund pagination
    assert_eq!(output.events.len(), 3);
    assert!(
        output.events.iter().any(|event| {
            event.event_id == paid_event_id() && event.name == "Contract Paid Event"
        })
    );
    assert_eq!(output.refunds.len(), 1);
    assert_eq!(output.total, 2);

    // Check the application-fee recovery JSON contract
    assert_eq!(output.financial_recoveries.len(), 1);
    let recovery = &output.financial_recoveries[0];
    assert_eq!(recovery.amount_minor, 25);
    assert_eq!(recovery.attempt_count, 10);
    assert_eq!(recovery.currency_code, "USD");
    assert_eq!(recovery.email, "buyer-refund-reject.contract@example.com");
    assert_eq!(recovery.event_name, "Contract Paid Event");
    assert_eq!(recovery.failure_message, "Contract application-fee failure");
    assert_eq!(
        recovery.kind,
        FinancialRecoveryKind::EventPurchaseApplicationFeeAdjustment
    );
    assert_eq!(recovery.operation, "Application-fee refund");
    assert_eq!(
        recovery.payment_job_id,
        financial_recovery_adjustment_job_id()
    );
    assert_eq!(recovery.username, "contract-buyer-refund-reject");
    assert_eq!(
        recovery.name.as_deref(),
        Some("Contract Buyer Refund Reject")
    );

    // Check required refund row fields
    let refund = &output.refunds[0];
    assert_eq!(refund.amount_minor, 2500);
    assert!(refund.created_at <= refund.updated_at);
    assert_eq!(refund.currency_code, "USD");
    assert_eq!(refund.email, "buyer-refund-reject.contract@example.com");
    assert_eq!(refund.event_id, paid_event_id());
    assert_eq!(refund.event_name, "Contract Paid Event");
    assert_eq!(refund.event_purchase_id, refund_reject_purchase_id());
    assert_eq!(refund.status, GroupRefundStatus::NeedsReview);
    assert_eq!(refund.ticket_title, "Contract Paid Ticket");
    assert_eq!(refund.user_id, refund_reject_buyer_id());
    assert_eq!(refund.username, "contract-buyer-refund-reject");

    // Check optional workflow and profile fields
    assert_eq!(refund.attempt_count, None);
    assert_eq!(refund.failure_message, None);
    assert_eq!(refund.kind.as_deref(), Some("refund-request-approval"));
    assert_eq!(refund.name.as_deref(), Some("Contract Buyer Refund Reject"));
    assert_eq!(refund.payment_job_id, None);
    assert_eq!(refund.photo_url, None);
    assert_eq!(refund.provider_refund_id, None);
    assert_eq!(
        refund.requested_reason.as_deref(),
        Some("Cannot attend anymore")
    );
    assert_eq!(refund.review_note, None);

    // Load and check the credit-note recovery JSON contract independently
    let credit_note_filters = RefundsFilters {
        view: RefundsView::Attention,
        event_id: Some(paid_event_id()),
        limit: Some(10),
        offset: Some(0),
        ts_query: Some("buyer-refund-approve.contract@example.com".to_string()),
    };
    let credit_note_output = db.list_group_refunds(group_id(), &credit_note_filters).await?;
    assert_eq!(credit_note_output.financial_recoveries.len(), 1);
    let recovery = &credit_note_output.financial_recoveries[0];
    assert_eq!(recovery.amount_minor, 2500);
    assert_eq!(recovery.attempt_count, 10);
    assert_eq!(recovery.currency_code, "USD");
    assert_eq!(recovery.email, "buyer-refund-approve.contract@example.com");
    assert_eq!(recovery.event_name, "Contract Paid Event");
    assert_eq!(recovery.failure_message, "Contract credit-note failure");
    assert_eq!(
        recovery.kind,
        FinancialRecoveryKind::EventPurchaseCreditNote
    );
    assert_eq!(recovery.operation, "Credit note");
    assert_eq!(
        recovery.payment_job_id,
        financial_recovery_credit_note_job_id()
    );
    assert_eq!(recovery.username, "contract-buyer-refund-approve");
    assert_eq!(
        recovery.name.as_deref(),
        Some("Contract Buyer Refund Approve")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_group_roles_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load group roles through the Rust contract
    let roles = db.list_group_roles().await?;

    // Check role ordering and display fields
    assert_eq!(roles.len(), 4);
    assert_eq!(roles[0].group_role_id, "admin");
    assert_eq!(roles[0].display_name, "Admin");
    assert_eq!(roles[1].group_role_id, "check-in-manager");
    assert_eq!(roles[1].display_name, "Check-In Manager");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_group_sponsors_deserializes() -> Result<()> {
    // Setup the contract database and sponsor filters
    let db = contract_tests_db()?;
    let filters = GroupSponsorsFilters {
        limit: Some(10),
        offset: Some(0),
    };

    // Load group sponsors through the Rust contract
    let output = db.list_group_sponsors(group_id(), &filters, false).await?;

    // Check pagination and sponsor fields
    assert_eq!(output.total, 1);
    assert_eq!(output.sponsors.len(), 1);
    assert_eq!(output.sponsors[0].group_sponsor_id, group_sponsor_id());
    assert_eq!(
        output.sponsors[0].website_url.as_deref(),
        Some("https://example.com/sponsor")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_group_team_members_deserializes() -> Result<()> {
    // Setup the contract database and team filters
    let db = contract_tests_db()?;
    let filters = GroupTeamFilters {
        limit: Some(10),
        offset: Some(0),
    };

    // Load group team members through the Rust contract
    let output = db.list_group_team_members(group_id(), &filters).await?;

    // Check accepted totals and member role fields
    assert_eq!(output.total, 1);
    assert_eq!(output.total_accepted, 1);
    assert_eq!(output.total_admins_accepted, 1);
    assert_eq!(output.members[0].role, Some(GroupRole::Admin));
    assert_eq!(output.members[0].user_id, organizer_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_session_kinds_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load session kinds through the Rust contract
    let kinds = db.list_session_kinds().await?;

    // Check kind ordering and display fields
    assert_eq!(kinds.len(), 3);
    assert_eq!(kinds[0].session_kind_id, "hybrid");
    assert_eq!(kinds[0].display_name, "Hybrid");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_groups_deserializes() -> Result<()> {
    // Setup the contract database and user fixture
    let db = contract_tests_db()?;

    // Load the user's organized groups through the Rust contract
    let output = db.list_user_groups(&organizer_id()).await?;

    // Check the community and all seeded groups
    assert_eq!(output.len(), 1);
    assert_eq!(output[0].community.community_id, community_id());
    assert_eq!(output[0].groups.len(), 3);
    assert!(output[0].groups.iter().any(|group| group.group_id == group_id()));
    assert!(output[0].groups.iter().any(|group| group.group_id == subgroup_id()));
    assert!(
        output[0]
            .groups
            .iter()
            .any(|group| group.group_id == claim_group_id())
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_lock_group_events_serializes_update() -> Result<()> {
    // Setup independent event-lock and update connections
    let db = contract_tests_db()?;
    let racing_pool = contract_tests_pool()?;
    let racing_client = racing_pool.get().await?;
    let event_id = group_lock_first_event_id();
    let event_payload =
        Json(group_lock_event_update("Contract Group Lock Event One Updated", 3).to_db_payload()?);
    racing_client.batch_execute("set lock_timeout = '250ms'").await?;

    // Lock the group and event through the Rust database contract
    let uow = db.begin().await?;
    uow.lock_group_events(claim_group_id(), &[event_id]).await?;

    // Check a competing event update cannot pass the helper's locks
    let lock_err = racing_client
        .query_one(
            "select update_event($1::uuid, $2::uuid, $3::uuid, $4::jsonb)",
            &[
                &organizer_id(),
                &claim_group_id(),
                &event_id,
                &event_payload,
            ],
        )
        .await
        .expect_err("event update should wait for the group event locks");
    assert_eq!(lock_err.code(), Some(&SqlState::LOCK_NOT_AVAILABLE));

    // Release the helper locks before retrying the update
    uow.commit().await?;

    // Check the serialized update succeeds after the locks are released
    let updated = racing_client
        .query_one(
            "select update_event($1::uuid, $2::uuid, $3::uuid, $4::jsonb)",
            &[
                &organizer_id(),
                &claim_group_id(),
                &event_id,
                &event_payload,
            ],
        )
        .await?;
    assert!(!updated.get::<_, bool>(0));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_event_attendees_deserializes() -> Result<()> {
    // Setup the contract database and attendee filters
    let db = contract_tests_db()?;
    let filters = AttendeesFilters {
        checked_in: None,
        event_ticket_type_ids: None,
        limit: Some(10),
        offset: Some(0),
        sort: None,
        status: None,
        title: None,
        ts_query: None,
    };

    // Search event attendees through the Rust contract
    let output = db.search_event_attendees(group_id(), event_id(), &filters).await?;

    // Check attendee totals and registered user fields
    assert_eq!(output.all_attendees_email_recipient_total, 1);
    assert_eq!(output.total, 2);
    assert_eq!(output.attendees.len(), 2);
    assert_eq!(output.attendees[0].user.user_id, attendee_id());
    assert_eq!(output.attendees[0].user.username, "contract-attendee");
    assert_eq!(
        output.attendees[0].user.bio.as_deref(),
        Some("Attends contract test events")
    );
    assert_eq!(
        output.attendees[0].user.github_url.as_deref(),
        Some("https://github.com/contract-attendee")
    );
    assert_eq!(
        output.attendees[0]
            .user
            .provider
            .as_ref()
            .and_then(|provider| provider.github.as_ref())
            .map(|github| github.username.as_str()),
        Some("contract-attendee")
    );
    assert!(output.attendees[0].can_receive_attendee_email);
    assert!(output.attendees[0].checked_in);
    assert!(output.attendees[0].registration_answers.is_some());

    // Check the pending pre-registered attendee offer fields
    assert_eq!(
        output.attendees[1].admission_offer_id,
        Some(invitation_offer_id())
    );
    assert_eq!(
        output.attendees[1].admission_offer_source,
        Some(EventAdmissionOfferSource::OrganizerInvitation)
    );
    assert_eq!(
        output.attendees[1].admission_offer_status,
        Some(EventAdmissionOfferStatus::Pending)
    );
    assert_eq!(output.attendees[1].amount_minor, None);
    assert_eq!(output.attendees[1].currency_code, None);
    assert_eq!(
        output.attendees[1].email,
        "pre-registered.contract@example.com"
    );
    assert_eq!(
        output.attendees[1].event_ticket_type_id,
        Some(invitation_ticket_type_id())
    );
    assert!(output.attendees[1].manually_invited);
    assert_eq!(
        output.attendees[1].offer_expires_at,
        Some(DateTime::parse_from_rfc3339("2099-05-20T18:30:00Z")?.with_timezone(&Utc),)
    );
    assert_eq!(
        output.attendees[1].enrollment_status,
        AttendeeEnrollmentStatus::InvitationPending
    );
    assert_eq!(
        output.attendees[1].ticket_title.as_deref(),
        Some("General Admission")
    );
    assert_eq!(output.attendees[1].user.user_id, pre_registered_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_event_attendees_external_payment_deserializes() -> Result<()> {
    // Setup the contract database and unfiltered external-event search
    let db = contract_tests_db()?;
    let filters = AttendeesFilters {
        checked_in: None,
        event_ticket_type_ids: None,
        limit: Some(10),
        offset: Some(0),
        sort: None,
        status: Some(AttendeeEnrollmentStatusFilter::All),
        title: None,
        ts_query: None,
    };

    // Search external-payment attendees through the Rust contract
    let output = db
        .search_event_attendees(group_id(), external_event_id(), &filters)
        .await?;

    // Check pending and completed external purchase encodings
    assert!(output.total >= 2);
    let pending = output
        .attendees
        .iter()
        .find(|attendee| attendee.user.user_id == external_pending_user_id())
        .expect("pending external attendee to be returned");
    assert_eq!(pending.amount_minor, Some(5000));
    assert_eq!(
        pending.charge_model,
        Some(EventPurchaseChargeModel::External)
    );
    assert_eq!(pending.currency_code.as_deref(), Some("USD"));
    assert_eq!(
        pending.enrollment_status,
        AttendeeEnrollmentStatus::PaymentPending
    );
    assert_eq!(
        pending.event_purchase_id,
        Some(external_pending_purchase_id())
    );
    assert_eq!(
        pending.external_payment_deadline,
        Some(DateTime::parse_from_rfc3339("2099-08-30T10:00:00Z")?.with_timezone(&Utc))
    );
    assert!(pending.external_payment_details.is_none());
    assert!(pending.external_payment_marked_by.is_none());
    assert_eq!(
        pending.external_payment_reference,
        Some(external_pending_purchase_id())
    );
    assert!(!pending.externally_paid);
    assert_eq!(pending.ticket_title.as_deref(), Some("External Admission"));

    let completed = output
        .attendees
        .iter()
        .find(|attendee| attendee.user.user_id == external_completed_user_id())
        .expect("completed external attendee to be returned");
    assert_eq!(
        completed.charge_model,
        Some(EventPurchaseChargeModel::External)
    );
    assert_eq!(
        completed.completed_at,
        Some(DateTime::parse_from_rfc3339("2024-03-02T10:00:00Z")?.with_timezone(&Utc))
    );
    assert_eq!(
        completed.enrollment_status,
        AttendeeEnrollmentStatus::Confirmed
    );
    assert_eq!(
        completed.event_purchase_id,
        Some(external_completed_purchase_id())
    );
    assert_eq!(
        completed.external_payment_details.as_deref(),
        Some("Bank transfer received")
    );
    assert_eq!(
        completed.external_payment_marked_by.as_deref(),
        Some("contract-organizer")
    );
    assert_eq!(
        completed.external_payment_reference,
        Some(external_completed_purchase_id())
    );
    assert!(completed.externally_paid);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_event_attendees_terminal_offer_statuses_deserialize() -> Result<()> {
    // Setup the contract database and unfiltered status event search
    let db = contract_tests_db()?;
    let filters = AttendeesFilters {
        checked_in: None,
        event_ticket_type_ids: None,
        limit: Some(10),
        offset: Some(0),
        sort: None,
        status: Some(AttendeeEnrollmentStatusFilter::All),
        title: None,
        ts_query: None,
    };

    // Search terminal organizer offers through the Rust contract
    let output = db
        .search_event_attendees(subgroup_id(), status_event_id(), &filters)
        .await?;

    // Check canceled, declined, and expired offer encodings
    assert_eq!(output.total, 3);
    for (user_id, enrollment_status, offer_status) in [
        (
            status_canceled_user_id(),
            AttendeeEnrollmentStatus::InvitationCanceled,
            EventAdmissionOfferStatus::Canceled,
        ),
        (
            status_declined_user_id(),
            AttendeeEnrollmentStatus::InvitationDeclined,
            EventAdmissionOfferStatus::Declined,
        ),
        (
            status_expired_user_id(),
            AttendeeEnrollmentStatus::InvitationExpired,
            EventAdmissionOfferStatus::Expired,
        ),
    ] {
        let attendee = output
            .attendees
            .iter()
            .find(|attendee| attendee.user.user_id == user_id)
            .expect("terminal offer attendee to be returned");
        assert_eq!(attendee.enrollment_status, enrollment_status);
        assert_eq!(attendee.admission_offer_status, Some(offer_status));
    }

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_event_invitation_requests_deserializes() -> Result<()> {
    // Setup the contract database and invitation request filters
    let db = contract_tests_db()?;
    let filters = InvitationRequestsFilters {
        limit: Some(10),
        offset: Some(0),
        sort: None,
        status: InvitationRequestsStatusFilter::All,
        title: None,
        ts_query: None,
    };

    // Search invitation requests through the Rust contract
    let output = db
        .search_event_invitation_requests(group_id(), event_id(), &filters)
        .await?;

    // Check request status and user profile fields
    assert_eq!(output.total, 1);
    assert_eq!(output.invitation_requests.len(), 1);
    assert_eq!(
        output.invitation_requests[0].invitation_request_status,
        EventInvitationRequestStatus::Pending
    );
    assert_eq!(output.invitation_requests[0].user.user_id, waitlist_id());
    assert_eq!(
        output.invitation_requests[0].user.username,
        "contract-waitlist"
    );
    assert_eq!(
        output.invitation_requests[0].user.bio.as_deref(),
        Some("Waits for contract test events")
    );
    assert_eq!(output.invitation_requests[0].admission_offer_id, None);
    assert_eq!(output.invitation_requests[0].admission_offer_status, None);
    assert_eq!(output.invitation_requests[0].offer_expires_at, None);
    assert_eq!(
        output.invitation_requests[0].offered_event_ticket_type_id,
        None
    );
    assert_eq!(output.invitation_requests[0].offered_ticket_title, None);
    assert!(output.invitation_requests[0].registration_answers.is_some());
    assert_eq!(
        output.invitation_requests[0].requested_event_ticket_type_id,
        Some(invitation_ticket_type_id())
    );
    assert_eq!(
        output.invitation_requests[0].requested_ticket_title.as_deref(),
        Some("General Admission")
    );
    assert_eq!(output.invitation_requests[0].reviewed_at, None);

    // Check the single-select registration answers payload
    let answers = output.invitation_requests[0]
        .registration_answers
        .as_ref()
        .expect("contract invitation request should include registration answers");
    assert_eq!(answers.answers.len(), 1);
    assert_eq!(
        answers.answers[0].question_id,
        parse_uuid("00000000-0000-0000-0000-00000000c071")
    );
    match &answers.answers[0].value {
        QuestionnaireAnswerValue::One(value) => {
            assert_eq!(value, "00000000-0000-0000-0000-00000000c072");
        }
        QuestionnaireAnswerValue::Many(_) => panic!("expected single-select answer"),
    }

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_event_waitlist_deserializes() -> Result<()> {
    // Setup the contract database and waitlist filters
    let db = contract_tests_db()?;
    let filters = WaitlistFilters {
        limit: Some(10),
        offset: Some(0),
        sort: None,
        title: None,
        ts_query: None,
    };

    // Search the event waitlist through the Rust contract
    let output = db.search_event_waitlist(group_id(), event_id(), &filters).await?;

    // Check waitlist totals, profile, and position fields
    assert_eq!(output.total, 1);
    assert_eq!(output.waitlist.len(), 1);
    assert_eq!(output.waitlist[0].user.user_id, waitlist_id());
    assert_eq!(output.waitlist[0].user.username, "contract-waitlist");
    assert_eq!(
        output.waitlist[0].user.website_url.as_deref(),
        Some("https://example.com/waitlist")
    );
    assert_eq!(output.waitlist[0].admission_offer_id, None);
    assert_eq!(output.waitlist[0].admission_offer_status, None);
    assert_eq!(
        output.waitlist[0].event_ticket_type_id,
        invitation_ticket_type_id()
    );
    assert_eq!(output.waitlist[0].offer_expires_at, None);
    assert_eq!(output.waitlist[0].ticket_title, "General Admission");
    assert_eq!(output.waitlist[0].waitlist_position, Some(1));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_update_event_deserializes() -> Result<()> {
    // Setup the contract database and event schedule
    let db = contract_tests_db()?;
    let starts_at = NaiveDate::from_ymd_opt(2099, 8, 1)
        .expect("date should be valid")
        .and_hms_opt(10, 0, 0)
        .expect("time should be valid");
    let ends_at = NaiveDate::from_ymd_opt(2099, 8, 1)
        .expect("date should be valid")
        .and_hms_opt(11, 0, 0)
        .expect("time should be valid");
    let event = EventUpdate {
        category_id: event_category_id(),
        description: "A mutation event updated by Rust database contract tests".to_string(),
        kind_id: "virtual".to_string(),
        name: "Contract Mutation Event".to_string(),
        timezone: "UTC".to_string(),

        capacity: Some(100),
        ends_at: Some(ends_at),
        starts_at: Some(starts_at),
        test_event: Some(true),

        ..Default::default()
    };

    // Serialize the event update for the database contract
    let payload = event.to_db_payload()?;

    // Update the event through the Rust contract
    let requires_paid_notification = db
        .update_event(
            organizer_id(),
            group_id(),
            mutation_event_id(),
            &payload,
            &HashMap::new(),
            Some(PaymentProvider::Stripe),
        )
        .await?;

    // Check the free test event remained outside the notifiable paid state
    assert!(!requires_paid_notification);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_update_event_serializes_same_group_mutations() -> Result<()> {
    // Setup two event updates targeting different events in the same group
    let db = contract_tests_db()?;
    let racing_pool = contract_tests_pool()?;
    let racing_client = racing_pool.get().await?;
    let first_event_id = group_lock_first_event_id();
    let first_payload =
        group_lock_event_update("Contract Group Lock Event One Updated", 3).to_db_payload()?;
    let second_event_id = group_lock_second_event_id();
    let second_payload =
        Json(group_lock_event_update("Contract Group Lock Event Two Updated", 4).to_db_payload()?);
    racing_client.batch_execute("set lock_timeout = '250ms'").await?;

    // Update the first event while retaining the owning group lock
    let uow = db.begin().await?;
    let requires_paid_notification = uow
        .update_event(
            organizer_id(),
            claim_group_id(),
            first_event_id,
            &first_payload,
            &HashMap::new(),
            None,
        )
        .await?;
    assert!(!requires_paid_notification);

    // Check the second event update cannot pass the shared group lock
    let lock_err = racing_client
        .query_one(
            "select update_event($1::uuid, $2::uuid, $3::uuid, $4::jsonb)",
            &[
                &organizer_id(),
                &claim_group_id(),
                &second_event_id,
                &second_payload,
            ],
        )
        .await
        .expect_err("same-group event update should wait for the group lock");
    assert_eq!(lock_err.code(), Some(&SqlState::LOCK_NOT_AVAILABLE));

    // Commit the first update before retrying the second mutation
    uow.commit().await?;

    // Check the second update succeeds after observing the committed group state
    let updated = racing_client
        .query_one(
            "select update_event($1::uuid, $2::uuid, $3::uuid, $4::jsonb)",
            &[
                &organizer_id(),
                &claim_group_id(),
                &second_event_id,
                &second_payload,
            ],
        )
        .await?;
    assert!(!updated.get::<_, bool>(0));

    Ok(())
}
