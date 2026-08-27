use std::{collections::HashMap, env, time::Duration};

use anyhow::{Context, Result, anyhow};
use chrono::{DateTime, NaiveDate, Utc};
use deadpool_postgres::{Config as DeadpoolDbConfig, Pool, Runtime};
use tokio_postgres::{
    NoTls,
    error::{DbError, SqlState},
    types::{Json, ToSql},
};
use uuid::Uuid;

use crate::{
    auth::UserSummary,
    db::{
        DB, PgDB,
        auth::DBAuth,
        badges::DBBadges,
        common::DBCommon,
        community::DBCommunity,
        dashboard::{
            common::DBDashboardCommon,
            community::DBDashboardCommunity,
            group::{
                DBDashboardGroup, EventAdmissionAllocationOutcome, EventAdmissionAllocationResult,
                EventAttendeeCancellationStatus, EventAttendeeInvitationInput,
            },
            user::DBDashboardUser,
        },
        event::DBEvent,
        group::DBGroup,
        meetings::DBMeetings,
        notifications::DBNotifications,
        payments::{
            DBPayments, EventPurchaseRefundKind, EventPurchaseRefundStatus,
            PrepareEventCheckoutPurchaseInput, PrepareEventCheckoutPurchaseResult,
            ReconcileEventPurchaseForCheckoutSessionInput, ReconcileEventPurchaseResult,
        },
        site::DBSite,
    },
    services::meetings::MeetingProvider,
    templates::{
        dashboard::{
            audit::AuditLogFilters,
            community::team::CommunityTeamFilters,
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
            user::{
                events::{UserEventRole, UserEventsFilters},
                groups::UserGroupsFilters,
                purchases::PurchaseDocumentsFilters,
                session_proposals::SessionProposalsFilters,
                submissions::CfsSubmissionsFilters as UserCfsSubmissionsFilters,
            },
        },
        site::explore::Entity,
    },
    types::{
        badges::{
            AwardedBadgesFilters, Badge, BadgeArtwork, BadgeAwardDefinition, BadgeAwardInput,
            BadgeAwardSource, BadgeAwardSourceFilter, BadgeFilters, BadgeSnapshot,
            BadgeSnapshotIssuer, BadgeStatusList, PublicBadgeSnapshot, PublicBadgeSnapshotIssuer,
            PublicUserBadge, UserBadge,
        },
        community::CommunityRole,
        event::{
            EventAdmissionOfferSource, EventAdmissionOfferStatus, EventDeleteEligibility,
            EventEnrollmentStatus, EventInvitationRequestStatus, EventKind,
        },
        group::GroupRole,
        payments::{
            EventPurchaseStatus, EventRefundRequestStatus, EventTicketType,
            EventTicketTypeAvailability, PaymentProvider,
        },
        questionnaire::QuestionnaireAnswerValue,
        search::{SearchEventsFilters, SearchGroupsFilters},
        user::UserProvider,
    },
    util::compute_hash,
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
async fn db_contracts_activate_pre_registered_user_external_provider_deserializes() -> Result<()> {
    // Setup the activation identity and external profile
    let db = contract_tests_db()?;
    let user_summary = UserSummary {
        email: "activation.contract@example.com".to_string(),
        name: "Contract Activation".to_string(),
        username: "contract-activation".to_string(),

        has_password: None,
        password: None,
        provider: Some(UserProvider::from_github_username(
            "contract-activation".to_string(),
        )),
    };

    // Activate the pre-registered user through the Rust contract
    let user = db
        .activate_pre_registered_user_external_provider(&activation_id(), &user_summary)
        .await?;

    // Check the registered external user fields
    assert!(user.email_verified);
    assert_eq!(user.name, "Contract Activation");
    assert_eq!(user.registration_status, "registered");
    assert_eq!(user.user_id, activation_id());
    assert_eq!(user.username, "contract-activation");

    Ok(())
}

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
async fn db_contracts_badge_award_worker_deserializes() -> Result<()> {
    // Setup the contract database wrapper
    let db = contract_tests_db()?;

    // Claim and process the seeded pending award job
    let claim = db
        .claim_badge_award_job()
        .await?
        .context("contract badge award job should be claimable")?;
    let outcome = db
        .process_badge_award_job_batch(claim.badge_award_job_id, claim.claim_id, 25, 500)
        .await?;

    // Check worker claim and batch outcome JSON deserialize into Rust DTOs
    assert_eq!(claim.badge_award_job_id, badge_award_job_id());
    assert!(outcome.completed);
    assert_eq!(outcome.processed_count, 1);
    assert!(!outcome.rate_limited);

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
async fn db_contracts_claim_and_finalize_event_refund_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Claim the provider-complete durable refund from contract fixtures
    let refund = db
        .claim_event_purchase_refund(PaymentProvider::Stripe)
        .await?
        .context("provider-complete contract refund should be claimable")?;

    // Check the claimed JSON contract and persisted provider outcome
    assert_eq!(refund.community_id, community_id());
    assert_eq!(refund.event_id, paid_event_id());
    assert_eq!(refund.event_purchase_id, refund_approve_purchase_id());
    assert_eq!(refund.status, EventPurchaseRefundStatus::Processing);
    assert!(refund.provider_refunded_at.is_some());

    // Finalize local state with the current worker claim
    db.finalize_event_purchase_refund(
        refund.event_purchase_refund_id,
        refund.claim_id.context("refund claim id should be present")?,
        serde_json::json!({"scenario": "contract"}),
        Some(PaymentProvider::Stripe),
    )
    .await?;

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_claim_event_purchase_application_fee_adjustment_deserializes() -> Result<()> {
    // Setup the contract database and claim the pending adjustment fixture
    let db = contract_tests_db()?;
    let adjustment = db
        .claim_event_purchase_application_fee_adjustment(PaymentProvider::Stripe)
        .await?
        .context("contract application-fee adjustment should be claimable")?;

    // Check the complete provider request context deserializes
    assert_eq!(adjustment.amount_minor, 25);
    assert_eq!(adjustment.connected_seller_id, "acct_contract_documents");
    assert_eq!(adjustment.currency_code, "USD");
    assert_eq!(
        adjustment.event_purchase_application_fee_adjustment_id,
        document_adjustment_id()
    );
    assert_eq!(adjustment.event_purchase_id, document_purchase_id());
    assert_eq!(
        adjustment.idempotency_key,
        "event-purchase-application-fee-adjustment-contract-documents"
    );
    assert_eq!(adjustment.kind, "purchase-refund");
    assert_eq!(
        adjustment.provider_application_fee_id,
        "fee_contract_documents"
    );

    // Complete the claim so it cannot interfere with later worker contracts
    db.record_event_purchase_application_fee_adjustment_succeeded(
        adjustment.event_purchase_application_fee_adjustment_id,
        adjustment.claim_id,
        "fr_contract_documents".to_string(),
    )
    .await?;

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_claim_event_purchase_credit_note_deserializes() -> Result<()> {
    // Setup the contract database and claim the pending credit-note fixture
    let db = contract_tests_db()?;
    let credit_note = db
        .claim_event_purchase_credit_note(PaymentProvider::Stripe)
        .await?
        .context("contract credit note should be claimable")?;

    // Check the complete provider request context deserializes
    assert_eq!(credit_note.amount_minor, 2500);
    assert_eq!(credit_note.connected_seller_id, "acct_contract_documents");
    assert_eq!(
        credit_note.event_purchase_credit_note_id,
        document_credit_note_id()
    );
    assert_eq!(credit_note.event_purchase_id, document_purchase_id());
    assert_eq!(credit_note.event_purchase_refund_id, document_refund_id());
    assert_eq!(
        credit_note.idempotency_key,
        "event-purchase-credit-note-contract-documents"
    );
    assert_eq!(credit_note.provider_invoice_id, "in_contract_documents");
    assert_eq!(credit_note.provider_refund_id, "re_contract_documents");
    assert_eq!(credit_note.tax_amount_minor, 0);

    // Issue the document so later attendee contracts cover the provider fields
    db.record_event_purchase_credit_note_succeeded(
        credit_note.event_purchase_credit_note_id,
        credit_note.claim_id,
        "cn_contract_documents".to_string(),
        Some("https://invoice.stripe.test/cn/contract-documents".to_string()),
        Some("https://invoice.stripe.test/cn/contract-documents.pdf".to_string()),
    )
    .await?;

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_claim_meeting_for_auto_end_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Claim the meeting eligible for automatic ending
    let candidate = db
        .claim_meeting_for_auto_end()
        .await?
        .expect("contract auto-end candidate should exist");

    // Check the provider meeting contract
    assert_eq!(candidate.meeting_id, auto_end_meeting_id());
    assert_eq!(candidate.provider, MeetingProvider::Zoom);
    assert_eq!(candidate.provider_meeting_id, "contract-auto-end");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_claim_meeting_out_of_sync_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Claim the meeting requiring provider synchronization
    let meeting = db
        .claim_meeting_out_of_sync()
        .await?
        .expect("contract meeting sync candidate should exist");

    // Check synchronization inputs and claim metadata
    assert_eq!(meeting.duration, Some(Duration::from_hours(1)));
    assert_eq!(meeting.event_id, Some(sync_event_id()));
    assert_eq!(meeting.provider, MeetingProvider::Zoom);
    assert!(meeting.sync_claimed_at.is_some());
    assert!(meeting.sync_state_hash.is_some());
    assert_eq!(
        meeting.topic.as_deref(),
        Some("Contract Meeting Sync Event")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_claim_pending_notification_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Claim the seeded notification through the production wrapper
    let claim_started_at = Utc::now();
    let notification = db
        .claim_pending_notification()
        .await?
        .context("pending contract notification should be claimable")?;
    let claim_finished_at = Utc::now();

    // Check the complete delivery contract and claim identity were decoded
    assert!(notification.attachments.is_empty());
    let clock_tolerance = chrono::Duration::seconds(1);
    assert!(notification.delivery_claimed_at >= claim_started_at - clock_tolerance);
    assert!(notification.delivery_claimed_at <= claim_finished_at + clock_tolerance);
    assert_eq!(notification.email, "organizer.contract@example.com");
    assert_eq!(notification.kind.to_string(), "event-welcome");
    assert_eq!(notification.notification_id, notification_id());
    assert!(notification.template_data.is_none());

    // Finalize through the production wrapper to verify the claim identity round trip
    db.update_notification(&notification, None).await?;

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_complete_free_event_purchase_deserializes() -> Result<()> {
    // Setup the contract database and free purchase fixture
    let db = contract_tests_db()?;

    // Load the provider-free purchase snapshot before completing it
    let summary = db.get_event_purchase_summary(free_purchase_id()).await?;
    assert_eq!(summary.currency_code, None);

    // Complete the free purchase through the Rust contract
    let purchase = db.complete_free_event_purchase(free_purchase_id()).await?;

    // Check the completed purchase ownership fields
    assert_eq!(purchase.community_id, community_id());
    assert_eq!(purchase.event_id, paid_event_id());
    assert_eq!(purchase.user_id, free_buyer_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_delete_session_proposal_locks_before_submission_check() -> Result<()> {
    // Setup a table-lock barrier and independent proposal-lock probe
    let pool = contract_tests_pool()?;
    let barrier_client = pool.get().await?;
    let delete_client = pool.get().await?;
    let probe_client = pool.get().await?;
    let barrier_backend_pid = barrier_client
        .query_one("select pg_backend_pid()", &[])
        .await?
        .get::<_, i32>(0);
    let delete_backend_pid = delete_client
        .query_one("select pg_backend_pid()", &[])
        .await?
        .get::<_, i32>(0);

    // Block the dependent submission read after the proposal lock is acquired
    barrier_client
        .batch_execute("begin; lock table cfs_submission in access exclusive mode")
        .await?;
    let actor_user_id = organizer_id();
    let session_proposal_id = cfs_delete_lock_proposal_id();
    let delete_task = tokio::spawn(async move {
        delete_client.batch_execute("begin").await?;
        delete_client
            .query_one(
                "select delete_session_proposal($1::uuid, $2::uuid)",
                &[&actor_user_id, &session_proposal_id],
            )
            .await?;
        delete_client.batch_execute("rollback").await?;

        Ok::<(), anyhow::Error>(())
    });

    // Wait until deletion reaches the dependent submission read
    wait_for_backend_blocker(&probe_client, barrier_backend_pid, delete_backend_pid).await?;

    // Probe whether deletion already holds the proposal update lock
    probe_client
        .batch_execute("begin; set local lock_timeout = '250ms'")
        .await?;
    let lock_result = probe_client
        .query_one(
            "select session_proposal_id from session_proposal where session_proposal_id = $1::uuid for key share",
            &[&cfs_delete_lock_proposal_id()],
        )
        .await;

    // Release the probes and let the deletion roll back its mutation
    probe_client.batch_execute("rollback").await?;
    barrier_client.batch_execute("rollback").await?;
    delete_task.await??;

    // Check deletion locks the proposal before inspecting submissions
    let lock_err = lock_result.expect_err("proposal read should wait for the deletion lock");
    assert_eq!(lock_err.code(), Some(&SqlState::LOCK_NOT_AVAILABLE));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_decline_event_admission_offer_deserializes() -> Result<()> {
    // Setup the contract database and dedicated RSVP offer fixture
    let db = contract_tests_db()?;

    // Decline the owned offer through the Rust JSON contract
    let outcome = db
        .decline_event_admission_offer(offer_decliner_id(), offer_decline_offer_id(), None)
        .await?;

    // Check the reconciliation context deserializes completely
    assert_eq!(outcome.community_id, community_id());
    assert_eq!(outcome.event_id, offer_decline_event_id());
    assert_eq!(outcome.group_id, subgroup_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_event_purchase_refund_lifecycle_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Queue a durable manual refund from deterministic contract data
    db.queue_event_refund_request_approval(
        organizer_id(),
        group_id(),
        refund_lifecycle_purchase_id(),
        Some("Approved for lifecycle contract".to_string()),
    )
    .await?;
    let refund = db.get_event_purchase_refund(refund_lifecycle_purchase_id()).await?;

    // Check required fields and initial workflow metadata
    assert_eq!(refund.amount_minor, 2500);
    assert_eq!(refund.currency_code, "USD");
    assert_eq!(refund.event_purchase_id, refund_lifecycle_purchase_id());
    assert_ne!(refund.event_purchase_refund_id, Uuid::nil());
    assert_eq!(
        refund.idempotency_key,
        format!("event-purchase-refund-{}", refund_lifecycle_purchase_id())
    );
    assert_eq!(refund.kind, EventPurchaseRefundKind::RefundRequestApproval);
    assert_eq!(refund.payment_provider, PaymentProvider::Stripe);
    assert_eq!(refund.status, EventPurchaseRefundStatus::ProviderPending);

    // Check optional provider outcome fields are absent initially
    assert!(refund.failure_message.is_none());
    assert!(refund.finalized_at.is_none());
    assert!(refund.provider_refund_id.is_none());
    assert!(refund.provider_refunded_at.is_none());

    // Record the in-progress provider refund
    let refund = db
        .record_event_purchase_refund_pending(
            refund.event_purchase_refund_id,
            refund.idempotency_key.clone(),
            "re_contract_refund_lifecycle".to_string(),
            refund.claim_id,
        )
        .await?;

    // Check the pending provider identifier and workflow state
    assert_eq!(refund.event_purchase_id, refund_lifecycle_purchase_id());
    assert_eq!(refund.status, EventPurchaseRefundStatus::ProviderPending);

    assert!(refund.failure_message.is_none());
    assert!(refund.finalized_at.is_none());
    assert_eq!(
        refund.provider_refund_id.as_deref(),
        Some("re_contract_refund_lifecycle")
    );
    assert!(refund.provider_refunded_at.is_none());

    // Record provider success for the same durable refund
    let refund = db
        .record_event_purchase_refund_succeeded(
            refund.event_purchase_refund_id,
            refund.idempotency_key.clone(),
            "re_contract_refund_lifecycle".to_string(),
            refund.claim_id,
        )
        .await?;

    // Check the successful provider outcome deserializes completely
    assert_eq!(refund.event_purchase_id, refund_lifecycle_purchase_id());
    assert_eq!(refund.status, EventPurchaseRefundStatus::ProviderSucceeded);

    assert!(refund.failure_message.is_none());
    assert!(refund.finalized_at.is_none());
    assert_eq!(
        refund.provider_refund_id.as_deref(),
        Some("re_contract_refund_lifecycle")
    );
    assert!(refund.provider_refunded_at.is_some());

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
async fn db_contracts_get_community_full_deserializes() -> Result<()> {
    // Setup the contract database and community fixture
    let db = contract_tests_db()?;

    // Load the full community through the Rust contract
    let community = db.get_community_full(community_id()).await?;

    // Check required and optional community fields
    assert!(community.active);
    assert_eq!(community.community_id, community_id());
    assert_eq!(
        community.created_at,
        DateTime::from_timestamp(1_704_067_200, 0).unwrap()
    );
    assert_eq!(community.display_name, "Contract Community");
    assert_eq!(community.name, "contract-community");
    assert_eq!(
        community.ad_banner_link_url.as_deref(),
        Some("https://example.com/community-ad")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_community_recently_added_groups_deserializes() -> Result<()> {
    // Setup the contract database and community fixture
    let db = contract_tests_db()?;

    // Load recently added groups through the Rust contract
    let groups = db.get_community_recently_added_groups(community_id()).await?;

    // Check both seeded groups are returned
    assert_eq!(groups.len(), 2);
    assert!(groups.iter().any(|group| group.group_id == group_id()));
    assert!(groups.iter().any(|group| group.group_id == subgroup_id()));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_community_site_stats_deserializes() -> Result<()> {
    // Setup the contract database and community fixture
    let db = contract_tests_db()?;

    // Load public community statistics through the Rust contract
    let stats = db.get_community_site_stats(community_id()).await?;

    // Check event and group totals deserialize as expected
    assert_eq!(stats.events, 2);
    assert_eq!(stats.events_attendees, 1);
    assert_eq!(stats.groups, 2);
    assert_eq!(stats.groups_members, 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_community_stats_deserializes() -> Result<()> {
    // Setup the contract database and community fixture
    let db = contract_tests_db()?;

    // Load dashboard community statistics through the Rust contract
    let stats = db.get_community_stats(community_id()).await?;

    // Check entity and page-view totals
    assert_eq!(stats.attendees.total, 1);
    assert_eq!(stats.events.total, 2);
    assert_eq!(stats.groups.total, 2);
    assert_eq!(stats.members.total, 1);
    assert_eq!(stats.page_views.community.total_views, 0);
    assert_eq!(stats.page_views.events.total_views, 2);
    assert_eq!(stats.page_views.groups.total_views, 3);
    assert_eq!(stats.page_views.total_views, 5);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_community_summary_deserializes() -> Result<()> {
    // Setup the contract database and community fixture
    let db = contract_tests_db()?;

    // Load the community summary through the Rust contract
    let community = db.get_community_summary(community_id()).await?;

    // Check identity and advertising fields
    assert_eq!(
        community.ad_banner_url.as_deref(),
        Some("https://example.com/community-ad-banner.png")
    );
    assert_eq!(community.community_id, community_id());
    assert_eq!(community.name, "contract-community");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_community_upcoming_events_deserializes() -> Result<()> {
    // Setup the contract database and event kind filter
    let db = contract_tests_db()?;

    // Load upcoming community events through the Rust contract
    let events = db
        .get_community_upcoming_events(community_id(), vec![EventKind::Hybrid])
        .await?;

    // Check the matching event collection
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].event_id, event_id());

    Ok(())
}

#[tokio::test]
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
        pending_payment_enrollment.resume_checkout_url.as_deref(),
        Some("https://example.test/checkout/status-pending")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_full_deserializes() -> Result<()> {
    // Setup the contract database and event fixture
    let db = contract_tests_db()?;

    // Load the full event through the Rust contract
    let event = db.get_event_full(community_id(), group_id(), event_id()).await?;

    // Check community and event details
    assert_eq!(event.attendee_count, 2);
    assert_eq!(
        event.community.ad_banner_link_url.as_deref(),
        Some("https://example.com/community-ad")
    );
    assert_eq!(
        event.community.ad_banner_url.as_deref(),
        Some("https://example.com/community-ad-banner.png")
    );
    assert_eq!(event.event_id, event_id());
    assert!(event.has_registration_questions);
    assert_eq!(
        event.luma_url.as_deref(),
        Some("https://luma.com/contract-event")
    );
    assert_eq!(event.registration_questions.len(), 1);
    assert_eq!(event.registration_questions[0].prompt, "Meal preference");
    assert!(event.registration_questions_locked);
    assert_eq!(event.sessions.len(), 1);
    assert_eq!(event.sponsors.len(), 1);
    assert_contract_ticket_type(
        &event.ticket_types.as_ref().expect("event should have tickets")[0],
    );

    // Check host and organizer provider profiles
    assert_eq!(
        event.hosts[0].github_url.as_deref(),
        Some("https://github.com/contract-organizer")
    );
    assert_eq!(event.organizers.len(), 1);
    assert_eq!(
        event.organizers[0].github_url.as_deref(),
        Some("https://github.com/contract-organizer")
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
async fn db_contracts_get_event_purchase_recovery_summary_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load the deterministic purchase awaiting provider refund recovery
    let summary = db.get_event_purchase_summary(refund_recovery_purchase_id()).await?;

    // Check the recovery status crosses the SQL-to-Rust contract
    assert_eq!(summary.event_purchase_id, refund_recovery_purchase_id());
    assert_eq!(summary.status, EventPurchaseStatus::RefundRecoveryPending);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_purchase_refund_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load the deterministic post-finalization recovery record
    let refund = db.get_event_purchase_refund(refund_recovery_purchase_id()).await?;

    // Check the required durable refund contract
    assert_eq!(refund.amount_minor, 2500);
    assert_eq!(refund.currency_code, "USD");
    assert_eq!(refund.event_purchase_id, refund_recovery_purchase_id());
    assert_eq!(refund.event_purchase_refund_id, refund_recovery_refund_id());
    assert_eq!(
        refund.idempotency_key,
        "event-purchase-refund-00000000-0000-0000-0000-00000000c0fd-recovery"
    );
    assert_eq!(
        refund.kind,
        EventPurchaseRefundKind::AutomaticUnfulfillableCheckout
    );
    assert_eq!(refund.payment_provider, PaymentProvider::Stripe);
    assert_eq!(refund.status, EventPurchaseRefundStatus::ProviderFailed);

    // Check the optional recovery outcome fields
    assert_eq!(
        refund.failure_message.as_deref(),
        Some("provider refund failed: re_contract_refund_failed")
    );
    assert!(refund.finalized_at.is_some());
    assert!(refund.provider_refund_id.is_none());
    assert!(refund.provider_refunded_at.is_none());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_purchase_refund_recovery_context_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load group-scoped recovery context for the deterministic refund
    let context = db
        .get_event_purchase_refund_recovery_context(group_id(), refund_recovery_purchase_id())
        .await?;

    // Check the app receives authoritative notification composition context
    assert_eq!(context.community_id, community_id());
    assert_eq!(context.event_id, refund_event_id());
    assert_eq!(
        context.event_purchase_refund_id,
        refund_recovery_refund_id()
    );
    assert!(!context.notification_required);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_purchase_summary_deserializes() -> Result<()> {
    // Setup the contract database and purchase fixture
    let db = contract_tests_db()?;

    // Load the purchase summary through the Rust contract
    let summary = db.get_event_purchase_summary(summary_purchase_id()).await?;

    // Check pricing, hold, status, and ticket fields
    assert_eq!(summary.amount_minor, 2500);
    assert_eq!(summary.currency_code.as_deref(), Some("USD"));
    assert_eq!(summary.discount_amount_minor, 0);
    assert_eq!(summary.event_purchase_id, summary_purchase_id());
    assert_eq!(summary.event_ticket_type_id, paid_ticket_type_id());
    assert!(summary.hold_expires_at.is_some());
    assert_eq!(summary.provisional_platform_fee_amount_minor, 250);
    assert_eq!(summary.status, EventPurchaseStatus::Pending);
    assert_eq!(summary.ticket_title, "Contract Paid Ticket");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_user_purchase_document_context_deserializes() -> Result<()> {
    // Setup the contract database and resolve the attendee-owned invoice
    let db = contract_tests_db()?;
    let context = db
        .get_user_purchase_document_context(free_buyer_id(), document_purchase_id(), None)
        .await?
        .context("contract invoice context should exist")?;

    // Check immutable provider scope and document ownership deserialize
    assert_eq!(context.connected_seller_id, "acct_contract_documents");
    assert_eq!(context.payment_provider, PaymentProvider::Stripe);
    assert_eq!(context.provider_document_id, "in_contract_documents");

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
async fn db_contracts_get_event_summary_deserializes() -> Result<()> {
    // Setup the contract database and event fixture
    let db = contract_tests_db()?;

    // Load the event summary through the Rust contract
    let event = db.get_event_summary(community_id(), group_id(), event_id()).await?;

    // Check required and computed event fields
    assert_eq!(event.event_id, event_id());
    assert!(event.has_registration_questions);
    assert!(
        event
            .ticket_types
            .as_ref()
            .is_some_and(|ticket_types| !ticket_types.is_empty())
    );
    assert_contract_ticket_type(
        &event.ticket_types.as_ref().expect("event should have tickets")[0],
    );
    assert_eq!(event.kind, EventKind::Hybrid);
    assert_eq!(event.waitlist_count, 1);

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
async fn db_contracts_get_filters_options_deserializes() -> Result<()> {
    // Setup the contract database and exploration scope
    let db = contract_tests_db()?;

    // Load event filter options through the Rust contract
    let options = db
        .get_filters_options(Some("contract-community".to_string()), Some(Entity::Events))
        .await?;

    // Check community and distance options
    assert_eq!(options.communities.len(), 1);
    assert_eq!(options.communities[0].value, "contract-community");
    assert!(!options.distance.is_empty());

    // Check event category options
    let event_category = options.event_category.expect("event categories should be present");
    assert_eq!(event_category.len(), 1);
    assert_eq!(event_category[0].name, "Conference");

    // Check group options
    let groups = options.groups.expect("groups should be present");
    assert_eq!(groups.len(), 2);
    assert!(groups.iter().any(|group| group.name == "Contract Group"));
    assert!(groups.iter().any(|group| group.name == "Contract Subgroup"));

    // Check region options
    let region = options.region.expect("regions should be present");
    assert_eq!(region.len(), 1);
    assert_eq!(region[0].name, "North America");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_full_deserializes() -> Result<()> {
    // Setup the contract database and group fixtures
    let db = contract_tests_db()?;

    // Load the parent group through the Rust contract
    let group = db.get_group_full(community_id(), group_id()).await?;

    // Check the parent group and nested collections
    assert_eq!(
        group.community.ad_banner_link_url.as_deref(),
        Some("https://example.com/community-ad")
    );
    assert_eq!(
        group.community.ad_banner_url.as_deref(),
        Some("https://example.com/community-ad-banner.png")
    );
    assert_eq!(group.group_id, group_id());
    assert_eq!(group.organizers.len(), 1);
    assert_eq!(group.sponsors.len(), 1);
    assert_eq!(group.subgroups.len(), 1);
    assert_eq!(group.subgroups[0].group_id, subgroup_id());
    assert!(group.parent.is_none());
    assert_eq!(
        group.organizers[0].github_url.as_deref(),
        Some("https://github.com/contract-organizer")
    );

    // Load the subgroup through the same contract
    let subgroup = db.get_group_full(community_id(), subgroup_id()).await?;

    // Check the subgroup parent relationship
    assert_eq!(
        subgroup
            .parent
            .as_ref()
            .expect("subgroup should have a parent")
            .group_id,
        group_id()
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_full_by_slug_deserializes() -> Result<()> {
    // Setup the contract database and group slug
    let db = contract_tests_db()?;

    // Load the full group by slug through the Rust contract
    let group = db
        .get_group_full_by_slug(community_id(), "contract-group")
        .await?
        .expect("contract group should exist");

    // Check the group and nested collection fields
    assert_eq!(group.group_id, group_id());
    assert_eq!(group.name, "Contract Group");
    assert_eq!(group.organizers.len(), 1);
    assert_eq!(group.sponsors.len(), 1);
    assert_eq!(group.subgroups.len(), 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_past_events_deserializes() -> Result<()> {
    // Setup the contract database and event kind filter
    let db = contract_tests_db()?;

    // Load past group events through the Rust contract
    let events = db
        .get_group_past_events(
            community_id(),
            "contract-group",
            vec![EventKind::Virtual],
            10,
        )
        .await?;

    // Check the matching past event
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].event_id, past_event_id());
    assert_eq!(events[0].kind, EventKind::Virtual);

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
async fn db_contracts_get_group_summary_deserializes() -> Result<()> {
    // Setup the contract database and group fixture
    let db = contract_tests_db()?;

    // Load the group summary through the Rust contract
    let group = db.get_group_summary(community_id(), group_id()).await?;

    // Check group identity and community fields
    assert_eq!(group.group_id, group_id());
    assert_eq!(group.community_name, "contract-community");
    assert!(group.region.is_some());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_upcoming_events_deserializes() -> Result<()> {
    // Setup the contract database and event kind filter
    let db = contract_tests_db()?;

    // Load upcoming group events through the Rust contract
    let events = db
        .get_group_upcoming_events(
            community_id(),
            "contract-group",
            vec![EventKind::Hybrid],
            10,
        )
        .await?;

    // Check the matching upcoming event
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].event_id, event_id());
    assert_eq!(events[0].kind, EventKind::Hybrid);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_site_home_stats_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load homepage statistics through the Rust contract
    let stats = db.get_site_home_stats().await?;

    // Check site event and group totals
    assert_eq!(stats.events, 2);
    assert_eq!(stats.events_attendees, 1);
    assert_eq!(stats.groups, 2);
    assert_eq!(stats.groups_members, 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_site_recently_added_groups_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load recently added site groups through the Rust contract
    let groups = db.get_site_recently_added_groups().await?;

    // Check both seeded groups are returned
    assert_eq!(groups.len(), 2);
    assert!(groups.iter().any(|group| group.group_id == group_id()));
    assert!(groups.iter().any(|group| group.group_id == subgroup_id()));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_site_settings_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load site settings through the Rust contract
    let settings = db.get_site_settings().await?;

    // Check branding, theme, and identity fields
    assert_eq!(
        settings.copyright_notice.as_deref(),
        Some("Copyright Contract Site")
    );
    assert_eq!(settings.site_id, site_id());
    assert_eq!(
        settings.theme.palette.get(&50).map(String::as_str),
        Some("#eff6ff")
    );
    assert_eq!(settings.theme.primary_color, "#0066cc");
    assert_eq!(settings.title, "Contract Site");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_site_stats_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load site statistics through the Rust contract
    let stats = db.get_site_stats().await?;

    // Check site entity totals
    assert_eq!(stats.attendees.total, 1);
    assert_eq!(stats.events.total, 2);
    assert_eq!(stats.groups.total, 2);
    assert_eq!(stats.members.total, 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_site_upcoming_events_deserializes() -> Result<()> {
    // Setup the contract database and event kind filter
    let db = contract_tests_db()?;

    // Load upcoming site events through the Rust contract
    let events = db.get_site_upcoming_events(vec![EventKind::Hybrid]).await?;

    // Check the matching event collection
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].event_id, event_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_user_by_email_for_external_auth_pre_registered_deserializes() -> Result<()>
{
    // Setup the contract database and normalized email lookup
    let db = contract_tests_db()?;

    // Load the pre-registered user through the auth contract
    let user = db
        .get_user_by_email_for_external_auth("PRE-REGISTERED.CONTRACT@example.com")
        .await?
        .expect("contract pre-registered user should exist");

    // Check pre-registration identity fields
    assert_eq!(user.user_id, pre_registered_id());
    assert_eq!(user.name, "");
    assert_eq!(user.registration_status, "pre-registered");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_user_by_id_deserializes() -> Result<()> {
    // Setup the contract database and user identifier
    let db = contract_tests_db()?;

    // Load the user by identifier through the Rust contract
    let user = db
        .get_user_by_id(&attendee_id())
        .await?
        .expect("contract attendee should exist");

    // Check account and provider profile fields
    assert!(user.email_verified);
    assert_eq!(user.email, "attendee.contract@example.com");
    assert_eq!(
        user.github_url.as_deref(),
        Some("https://github.com/contract-attendee")
    );
    assert_eq!(user.user_id, attendee_id());
    assert_eq!(user.username, "contract-attendee");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_user_by_linuxfoundation_identity_for_external_auth_deserializes()
-> Result<()> {
    // Setup the contract database and provider identity
    let db = contract_tests_db()?;

    // Load the user through the Linux Foundation auth contract
    let user = db
        .get_user_by_linuxfoundation_identity_for_external_auth(
            "https://issuer.example.com",
            "auth0|contract-external-lookup",
        )
        .await?
        .expect("contract LF provider user should exist");

    // Check external account identity fields
    assert_eq!(user.email, "external-lookup.contract@example.com");
    assert_eq!(user.name, "");
    assert_eq!(user.user_id, external_lookup_id());
    assert_eq!(user.username, "contract-external-lookup");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_user_by_username_deserializes() -> Result<()> {
    // Setup the contract database and username lookup
    let db = contract_tests_db()?;

    // Load the user by username through the Rust contract
    let user = db
        .get_user_by_username("contract-organizer")
        .await?
        .expect("contract organizer should exist");

    // Check public user identity fields
    assert_eq!(user.name, "Contract Organizer");
    assert_eq!(user.user_id, organizer_id());

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
async fn db_contracts_list_communities_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load communities through the Rust contract
    let communities = db.list_communities().await?;

    // Check the seeded community summary
    assert_eq!(communities.len(), 1);
    assert_eq!(communities[0].community_id, community_id());
    assert_eq!(communities[0].name, "contract-community");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_community_audit_logs_deserializes() -> Result<()> {
    // Setup the contract database and audit filters
    let db = contract_tests_db()?;
    let filters = AuditLogFilters {
        limit: Some(10),
        offset: Some(0),

        ..Default::default()
    };

    // Load community audit logs through the Rust contract
    let output = db.list_community_audit_logs(community_id(), &filters).await?;

    // Check pagination and audit actor fields
    assert_eq!(output.total, 1);
    assert_eq!(output.logs.len(), 1);
    assert_eq!(output.logs[0].action, "group_payment_recipient_updated");
    assert_eq!(
        output.logs[0].actor_username.as_deref(),
        Some("contract-organizer")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_community_roles_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load community roles through the Rust contract
    let roles = db.list_community_roles().await?;

    // Check role ordering and display fields
    assert_eq!(roles.len(), 3);
    assert_eq!(roles[0].community_role_id, "admin");
    assert_eq!(roles[0].display_name, "Admin");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_community_team_members_deserializes() -> Result<()> {
    // Setup the contract database and team filters
    let db = contract_tests_db()?;
    let filters = CommunityTeamFilters {
        limit: Some(10),
        offset: Some(0),
    };

    // Load community team members through the Rust contract
    let output = db.list_community_team_members(community_id(), &filters).await?;

    // Check accepted and pending team member rows
    assert_eq!(output.total, 2);
    assert_eq!(output.members.len(), 2);
    assert!(output.members[0].accepted);
    assert_eq!(output.members[0].role, Some(CommunityRole::Admin));
    assert_eq!(output.members[0].user_id, organizer_id());
    assert!(!output.members[1].accepted);
    assert_eq!(output.members[1].user_id, waitlist_id());

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
async fn db_contracts_list_event_cfs_labels_deserializes() -> Result<()> {
    // Setup the contract database and event fixture
    let db = contract_tests_db()?;

    // Load event submission labels through the Rust contract
    let labels = db.list_event_cfs_labels(event_id()).await?;

    // Check label color and name fields
    assert_eq!(labels.len(), 1);
    assert_eq!(labels[0].color, "#DBEAFE");
    assert_eq!(labels[0].name, "track / backend");

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
async fn db_contracts_list_event_ticket_types_deserializes() -> Result<()> {
    // Query the normalized ticket inventory through its SQL boundary
    let pool = contract_tests_pool()?;
    let client = pool.get().await?;
    let row = client
        .query_one("select list_event_ticket_types($1)", &[&paid_event_id()])
        .await?;

    // Deserialize the exact JSON result into the production DTO
    let payload: serde_json::Value = row.try_get(0)?;
    let ticket_types: Vec<EventTicketType> = serde_json::from_value(payload)?;
    assert_eq!(ticket_types.len(), 2);
    let paid_ticket_type = ticket_types
        .iter()
        .find(|ticket_type| ticket_type.event_ticket_type_id == paid_ticket_type_id())
        .expect("paid ticket type to be returned");
    assert_contract_paid_ticket_type(paid_ticket_type);

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
async fn db_contracts_list_group_categories_deserializes() -> Result<()> {
    // Setup the contract database and community fixture
    let db = contract_tests_db()?;

    // Load group categories through the Rust contract
    let categories = db.list_group_categories(community_id()).await?;

    // Check the seeded category
    assert_eq!(categories.len(), 1);
    assert_eq!(categories[0].name, "Technology");

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
    assert_eq!(events.upcoming.total, 3);

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
    assert_eq!(output.events.len(), 2);
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
        FinancialRecoveryKind::ApplicationFeeAdjustment
    );
    assert_eq!(recovery.operation, "Application-fee refund");
    assert_eq!(recovery.username, "contract-buyer-refund-reject");
    assert_eq!(recovery.work_id, financial_recovery_adjustment_id());
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
    assert_eq!(recovery.kind, FinancialRecoveryKind::CreditNote);
    assert_eq!(recovery.operation, "Credit note");
    assert_eq!(recovery.username, "contract-buyer-refund-approve");
    assert_eq!(recovery.work_id, financial_recovery_credit_note_id());
    assert_eq!(
        recovery.name.as_deref(),
        Some("Contract Buyer Refund Approve")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_group_parent_options_deserializes() -> Result<()> {
    // Setup the contract database and subgroup context
    let db = contract_tests_db()?;

    // Load selectable parent options through the Rust contract
    let options = db
        .list_group_parent_options(community_id(), organizer_id(), Some(subgroup_id()))
        .await?;

    // Select the seeded parent option
    let parent = options
        .iter()
        .find(|option| option.group_id == group_id())
        .expect("contract group should be a parent option");

    // Check parent activity and selection fields
    assert!(parent.active);
    assert_eq!(parent.name, "Contract Group");
    assert!(!parent.is_current);
    assert!(parent.is_selectable);

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
async fn db_contracts_list_public_event_ticket_types_deserializes() -> Result<()> {
    // Query the attendee-facing ticket inventory through its SQL boundary
    let pool = contract_tests_pool()?;
    let client = pool.get().await?;
    let row = client
        .query_one(
            "select list_public_event_ticket_types($1)",
            &[&paid_event_id()],
        )
        .await?;

    // Deserialize the exact JSON result into the production DTO
    let payload: serde_json::Value = row.try_get(0)?;
    let ticket_types: Vec<EventTicketType> = serde_json::from_value(payload)?;
    assert_eq!(ticket_types.len(), 2);
    let paid_ticket_type = ticket_types
        .iter()
        .find(|ticket_type| ticket_type.event_ticket_type_id == paid_ticket_type_id())
        .expect("public paid ticket type to be returned");
    assert_contract_paid_ticket_type(paid_ticket_type);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_regions_deserializes() -> Result<()> {
    // Setup the contract database and community fixture
    let db = contract_tests_db()?;

    // Load regions through the Rust contract
    let regions = db.list_regions(community_id()).await?;

    // Check the seeded region
    assert_eq!(regions.len(), 1);
    assert_eq!(regions[0].name, "North America");

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
async fn db_contracts_list_session_proposal_levels_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load session proposal levels through the Rust contract
    let levels = db.list_session_proposal_levels().await?;

    // Check level ordering and display fields
    assert_eq!(levels.len(), 3);
    assert_eq!(levels[0].session_proposal_level_id, "advanced");
    assert_eq!(levels[0].display_name, "Advanced");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_audit_logs_deserializes() -> Result<()> {
    // Setup the contract database and audit filters
    let db = contract_tests_db()?;
    let filters = AuditLogFilters {
        limit: Some(10),
        offset: Some(0),

        ..Default::default()
    };

    // Load user audit logs through the Rust contract
    let output = db.list_user_audit_logs(attendee_id(), &filters).await?;

    // Check pagination, actor, and resource fields
    assert_eq!(output.total, 1);
    assert_eq!(output.logs.len(), 1);
    assert_eq!(output.logs[0].action, "event_attendee_invitation_rejected");
    assert_eq!(
        output.logs[0].actor_username.as_deref(),
        Some("contract-attendee")
    );
    assert_eq!(output.logs[0].resource_id, event_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_cfs_submissions_deserializes() -> Result<()> {
    // Setup the contract database and submission filters
    let db = contract_tests_db()?;
    let filters = UserCfsSubmissionsFilters {
        limit: Some(10),
        offset: Some(0),
    };

    // Load user submissions through the Rust contract
    let output = db.list_user_cfs_submissions(attendee_id(), &filters).await?;

    // Check submission pagination totals
    assert_eq!(output.total, 1);
    assert_eq!(output.submissions.len(), 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_check_in_events_deserializes() -> Result<()> {
    // Setup the contract database and attendee fixture
    let db = contract_tests_db()?;

    // Load attendee credential cards through the Rust JSON contract
    let events = db.list_user_check_in_events(attendee_id()).await?;

    // Check attendee state and ticket snapshot deserialize completely
    assert_eq!(events.len(), 1);
    let event = &events[0];
    assert!(event.checked_in);
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
    assert_eq!(event.ticket_title.as_deref(), Some("General Admission"));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_communities_deserializes() -> Result<()> {
    // Setup the contract database and user fixture
    let db = contract_tests_db()?;

    // Load the user's communities through the Rust contract
    let communities = db.list_user_communities(&organizer_id()).await?;

    // Check the seeded community membership
    assert_eq!(communities.len(), 1);
    assert_eq!(communities[0].community_id, community_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_community_team_invitations_deserializes() -> Result<()> {
    // Setup the contract database and invited user fixture
    let db = contract_tests_db()?;

    // Load community team invitations through the Rust contract
    let invitations = db.list_user_community_team_invitations(waitlist_id()).await?;

    // Check community and role fields
    assert_eq!(invitations.len(), 1);
    assert_eq!(invitations[0].community_id, community_id());
    assert_eq!(invitations[0].community_name, "contract-community");
    assert_eq!(invitations[0].role, CommunityRole::Viewer);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_event_invitations_deserializes() -> Result<()> {
    // Setup the contract database and invited user fixture
    let db = contract_tests_db()?;

    // Load event invitations through the Rust contract
    let invitations = db.list_user_event_invitations(pre_registered_id()).await?;

    // Check event invitation identity fields
    assert_eq!(invitations.len(), 1);
    assert_eq!(invitations[0].admission_offer_id, invitation_offer_id());
    assert_eq!(
        invitations[0].admission_offer_source,
        EventAdmissionOfferSource::OrganizerInvitation
    );
    assert_eq!(
        invitations[0].admission_offer_status,
        EventAdmissionOfferStatus::Pending
    );
    assert_eq!(invitations[0].amount_minor, Some(2500));
    assert_eq!(invitations[0].currency_code.as_deref(), Some("USD"));
    assert_eq!(invitations[0].event_id, event_id());
    assert_eq!(invitations[0].event_name, "Future Contract Event");
    assert_eq!(
        invitations[0].event_ticket_type_id,
        invitation_ticket_type_id()
    );
    assert_eq!(
        invitations[0].expires_at,
        DateTime::parse_from_rfc3339("2099-05-20T18:30:00Z")?.with_timezone(&Utc)
    );
    assert!(invitations[0].registration_answers.is_none());
    assert_eq!(invitations[0].registration_questions.len(), 1);
    assert_eq!(
        invitations[0].registration_questions[0].prompt,
        "Meal preference"
    );
    assert!(invitations[0].resume_checkout_url.is_none());
    assert_eq!(
        invitations[0].starts_at,
        Some(DateTime::parse_from_rfc3339("2099-05-20T17:00:00Z")?.with_timezone(&Utc),)
    );
    assert_eq!(invitations[0].ticket_title, "General Admission");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_events_deserializes() -> Result<()> {
    // Setup the contract database and event filters
    let db = contract_tests_db()?;
    let filters = UserEventsFilters {
        limit: Some(10),
        offset: Some(0),
    };

    // Load the user's events through the Rust contract
    let output = db.list_user_events(attendee_id(), &filters).await?;
    let offered_output = db.list_user_events(pre_registered_id(), &filters).await?;
    let pending_checkout_output = db
        .list_user_events(status_pending_payment_user_id(), &filters)
        .await?;
    let rejected_refund_output = db.list_user_events(refund_rejected_buyer_id(), &filters).await?;

    // Check attendance and registration question state
    assert_eq!(output.total, 1);
    assert_eq!(output.events.len(), 1);
    assert_eq!(
        output.events[0].enrollment_status,
        Some(EventEnrollmentStatus::Attendee)
    );
    assert_eq!(output.events[0].admission_offer_id, None);
    assert_eq!(output.events[0].admission_offer_source, None);
    assert_eq!(output.events[0].admission_offer_status, None);
    assert_eq!(output.events[0].amount_minor, None);
    assert!(output.events[0].can_complete_registration_questions());
    assert_eq!(output.events[0].currency_code, None);
    assert!(output.events[0].event.has_registration_questions);
    assert_eq!(output.events[0].event_ticket_type_id, None);
    assert_eq!(output.events[0].offer_expires_at, None);
    assert_eq!(output.events[0].registration_questions.len(), 1);
    assert!(!output.events[0].registration_questions_pending());
    assert_eq!(output.events[0].resume_checkout_url, None);
    assert_eq!(output.events[0].ticket_title, None);

    // Check active direct checkout remains actionable without an attendee role
    assert_eq!(pending_checkout_output.total, 1);
    assert_eq!(pending_checkout_output.events.len(), 1);
    let pending_checkout = &pending_checkout_output.events[0];
    assert_eq!(pending_checkout.event.event_id, status_event_id());
    assert!(!pending_checkout.has_paid_purchase);
    assert!(!pending_checkout.manually_invited);
    assert!(pending_checkout.registration_questions.is_empty());
    assert!(pending_checkout.roles.is_empty());
    assert_eq!(pending_checkout.admission_offer_id, None);
    assert_eq!(pending_checkout.admission_offer_source, None);
    assert_eq!(pending_checkout.admission_offer_status, None);
    assert_eq!(pending_checkout.amount_minor, Some(2500));
    assert_eq!(pending_checkout.currency_code.as_deref(), Some("USD"));
    assert_eq!(
        pending_checkout.enrollment_status,
        Some(EventEnrollmentStatus::PendingPayment)
    );
    assert_eq!(
        pending_checkout.event_ticket_type_id,
        Some(status_ticket_type_id())
    );
    assert_eq!(pending_checkout.offer_expires_at, None);
    assert!(pending_checkout.registration_answers.is_none());
    assert_eq!(
        pending_checkout.resume_checkout_url.as_deref(),
        Some("https://example.test/checkout/status-pending")
    );
    assert_eq!(
        pending_checkout.ticket_title.as_deref(),
        Some("Status Admission")
    );

    // Check active offers use their own role instead of attendee presentation
    assert_eq!(offered_output.total, 1);
    assert_eq!(offered_output.events.len(), 1);
    assert_eq!(
        offered_output.events[0].admission_offer_id,
        Some(invitation_offer_id())
    );
    assert_eq!(offered_output.events[0].roles, vec![UserEventRole::Offer]);

    // Check rejected refund feedback remains visible in My Events
    assert_eq!(rejected_refund_output.total, 1);
    assert_eq!(rejected_refund_output.events.len(), 1);
    assert_eq!(
        rejected_refund_output.events[0].refund_rejection_reason.as_deref(),
        Some("Outside the refund policy window")
    );
    assert_eq!(
        rejected_refund_output.events[0].refund_request_status,
        Some(EventRefundRequestStatus::Rejected)
    );

    // Load the persisted registration answers
    let answers = output.events[0]
        .registration_answers
        .as_ref()
        .expect("contract event should include registration answers");

    // Check the single-select answer encoding
    assert_eq!(answers.answers.len(), 1);
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
async fn db_contracts_list_user_purchase_documents_deserializes() -> Result<()> {
    // Setup the contract database and attendee document filters
    let db = contract_tests_db()?;
    let filters = PurchaseDocumentsFilters {
        limit: Some(10),
        offset: Some(0),
    };

    // Load invoice and credit-note history through the production wrapper
    let output = db.list_user_purchase_documents(free_buyer_id(), &filters).await?;

    // Check the purchase and nested credit-note JSON contracts
    assert_eq!(output.total, 1);
    assert_eq!(output.purchases.len(), 1);
    let purchase = &output.purchases[0];
    assert_eq!(purchase.amount_minor, 2500);
    assert_eq!(purchase.event_purchase_id, document_purchase_id());
    assert_eq!(
        purchase.provider_invoice_id.as_deref(),
        Some("in_contract_documents")
    );
    assert_eq!(
        purchase.seller_display_name.as_deref(),
        Some("Contract Document Sponsor")
    );
    assert_eq!(purchase.credit_notes.len(), 1);
    assert_eq!(
        purchase.credit_notes[0].event_purchase_credit_note_id,
        document_credit_note_id()
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_dashboard_groups_deserializes() -> Result<()> {
    // Setup the contract database and group filters
    let db = contract_tests_db()?;
    let filters = UserGroupsFilters {
        limit: Some(10),
        offset: Some(0),
    };

    // Load the attendee's member and accepted team groups
    let output = db.list_user_dashboard_groups(attendee_id(), &filters).await?;

    // Check the member row contract
    assert_eq!(output.groups.len(), 2);
    assert_eq!(output.total, 2);
    assert_eq!(output.groups[0].group.group_id, group_id());
    assert_eq!(
        output.groups[0].group.community_display_name,
        "Contract Community"
    );
    assert_eq!(output.groups[0].group.name, "Contract Group");
    assert!(output.groups[0].is_member);
    assert!(!output.groups[0].is_team_member);
    assert_eq!(output.groups[0].joined_at.timestamp(), 1_704_276_000);

    // Check the accepted team-only row contract
    assert_eq!(output.groups[1].group.group_id, subgroup_id());
    assert_eq!(output.groups[1].group.name, "Contract Subgroup");
    assert!(!output.groups[1].is_member);
    assert!(output.groups[1].is_team_member);
    assert_eq!(output.groups[1].joined_at.timestamp(), 1_704_362_400);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_group_team_invitations_deserializes() -> Result<()> {
    // Setup the contract database and invited user fixture
    let db = contract_tests_db()?;

    // Load group team invitations through the Rust contract
    let invitations = db.list_user_group_team_invitations(attendee_id()).await?;

    // Check community, group, and role fields
    assert_eq!(invitations.len(), 1);
    assert_eq!(invitations[0].community_name, "contract-community");
    assert_eq!(invitations[0].group_id, claim_group_id());
    assert_eq!(invitations[0].group_name, "Contract Meeting Claim Group");
    assert_eq!(invitations[0].role, GroupRole::Viewer);

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
async fn db_contracts_list_user_pending_session_proposal_co_speaker_invitations_deserializes()
-> Result<()> {
    // Setup the contract database and invited speaker fixture
    let db = contract_tests_db()?;

    // Load pending co-speaker invitations through the Rust contract
    let invitations = db
        .list_user_pending_session_proposal_co_speaker_invitations(waitlist_id())
        .await?;

    // Check proposal and speaker fields
    assert_eq!(invitations.len(), 1);
    assert_eq!(
        invitations[0].session_proposal.session_proposal_id,
        co_speaker_proposal_id()
    );
    assert_eq!(
        invitations[0].session_proposal.title,
        "Contract Go Proposal"
    );
    assert_eq!(invitations[0].speaker_name, "Contract Attendee");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_session_proposals_deserializes() -> Result<()> {
    // Setup the contract database and proposal filters
    let db = contract_tests_db()?;
    let filters = SessionProposalsFilters {
        limit: Some(10),
        offset: Some(0),
    };

    // Load the user's session proposals through the Rust contract
    let output = db.list_user_session_proposals(attendee_id(), &filters).await?;

    // Check proposal totals and co-speaker state
    assert_eq!(output.total, 2);
    assert_eq!(output.session_proposals.len(), 2);
    assert_eq!(output.session_proposals[0].title, "Contract Go Proposal");
    assert!(
        output.session_proposals[0]
            .co_speaker
            .as_ref()
            .is_some_and(|co_speaker| co_speaker.user_id == waitlist_id())
    );
    assert_eq!(output.session_proposals[1].title, "Contract Rust Proposal");
    assert!(output.session_proposals[1].has_submissions);

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
async fn db_contracts_prepare_event_checkout_purchase_deserializes() -> Result<()> {
    // Setup the contract database and checkout input
    let db = contract_tests_db()?;
    let input = PrepareEventCheckoutPurchaseInput {
        event_id: paid_event_id(),
        event_ticket_type_id: paid_ticket_type_id(),
        platform_fee_bps: 250,
        user_id: checkout_buyer_id(),

        admission_offer_id: None,
        discount_code: None,
        payment_provider: Some(PaymentProvider::Stripe),
        registration_answers: None,
    };

    // Prepare the checkout purchase through the Rust contract
    let checkout = match db.prepare_event_checkout_purchase(community_id(), &input).await? {
        PrepareEventCheckoutPurchaseResult::Conflict(conflict) => {
            return Err(anyhow!("unexpected checkout conflict: {conflict:?}"));
        }
        PrepareEventCheckoutPurchaseResult::Prepared(checkout) => *checkout,
    };

    // Check event, purchase, and recipient fields
    assert_eq!(checkout.community_name, "contract-community");
    assert_eq!(checkout.event_id, paid_event_id());
    assert_eq!(checkout.event_slug, "contract-paid-event");
    assert_eq!(checkout.group_slug, "contract-group");
    assert_eq!(
        checkout.venue.as_ref().and_then(|venue| venue.state_code.as_deref()),
        Some("CA")
    );
    assert_eq!(
        checkout.venue.as_ref().and_then(|venue| venue.state_name.as_deref()),
        Some("California")
    );
    assert_eq!(checkout.purchase.amount_minor, 2500);
    assert_eq!(
        checkout.purchase.event_ticket_type_id,
        paid_ticket_type_id()
    );
    assert!(checkout.purchase.hold_expires_at.is_some());
    assert_eq!(checkout.purchase.provisional_platform_fee_amount_minor, 62);
    assert_eq!(checkout.purchase.status, EventPurchaseStatus::Pending);
    assert_eq!(checkout.purchase.ticket_title, "Contract Paid Ticket");
    assert_eq!(
        checkout.seller.as_ref().map(|seller| seller.provider),
        Some(PaymentProvider::Stripe)
    );
    assert_eq!(
        checkout
            .seller
            .as_ref()
            .map(|seller| seller.connected_account_id.as_str()),
        Some("acct_contract")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_queue_event_refund_request_approval_blocks_event_writers() -> Result<()> {
    // Setup independent refund approval and event-lock connections
    let pool = contract_tests_pool()?;
    let approval_client = pool.get().await?;
    let event_client = pool.get().await?;

    // Queue approval while retaining the refund workflow locks
    approval_client.batch_execute("begin").await?;
    approval_client
        .query_one(
            "select queue_event_refund_request_approval($1::uuid, $2::uuid, $3::uuid, null::text)",
            &[&organizer_id(), &group_id(), &refund_begin_purchase_id()],
        )
        .await?;

    // Probe whether a competing writer can lock the owning event
    event_client
        .batch_execute("begin; set local lock_timeout = '250ms'")
        .await?;
    let lock_result = event_client
        .query_one(
            "select event_id from event where event_id = $1::uuid for update",
            &[&refund_event_id()],
        )
        .await;

    // Roll back the approval and lock probe before checking the outcome
    event_client.batch_execute("rollback").await?;
    approval_client.batch_execute("rollback").await?;

    // Check approval holds the event lock before refund workflow rows
    let lock_err = lock_result.expect_err("event writer should wait for refund approval");
    assert_eq!(lock_err.code(), Some(&SqlState::LOCK_NOT_AVAILABLE));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_queue_event_refund_request_approval_deserializes() -> Result<()> {
    // Setup the contract database and refund request fixture
    let db = contract_tests_db()?;

    // Queue organizer approval using deterministic request fixtures
    db.queue_event_refund_request_approval(
        organizer_id(),
        group_id(),
        refund_begin_purchase_id(),
        Some("Approved by contract test".to_string()),
    )
    .await?;

    // Load the queued durable refund through the Rust database contract
    let refund = db.get_event_purchase_refund(refund_begin_purchase_id()).await?;

    // Check required durable refund fields deserialize as expected
    assert_eq!(refund.amount_minor, 2500);
    assert_eq!(refund.currency_code, "USD");
    assert_eq!(refund.event_purchase_id, refund_begin_purchase_id());
    assert_eq!(refund.kind, EventPurchaseRefundKind::RefundRequestApproval);
    assert_eq!(refund.payment_provider, PaymentProvider::Stripe);
    assert_eq!(refund.status, EventPurchaseRefundStatus::ProviderPending);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_reconcile_event_purchase_for_checkout_session_deserializes() -> Result<()> {
    // Setup the contract database and provider checkout references
    let db = contract_tests_db()?;

    // Reconcile the provider checkout through the Rust contract
    let result = db
        .reconcile_event_purchase_for_checkout_session(
            &ReconcileEventPurchaseForCheckoutSessionInput {
                payment_provider: PaymentProvider::Stripe,
                provider_charge_id: "ch_contract_reconcile".to_string(),
                provider_object_account_id: "acct_contract".to_string(),
                provider_payment_reference: "pi_contract_reconcile".to_string(),
                provider_session_id: "cs_contract_reconcile".to_string(),
                provider_total_minor: 2_500,
                tax_amount_minor: 0,

                provider_application_fee_id: None,
            },
        )
        .await?;

    // Require the completed reconciliation outcome
    let ReconcileEventPurchaseResult::Completed(purchase) = result else {
        panic!("reconciliation should complete the purchase");
    };

    // Check completed purchase ownership fields
    assert_eq!(purchase.community_id, community_id());
    assert_eq!(purchase.event_id, paid_event_id());
    assert_eq!(purchase.user_id, reconcile_buyer_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_reconcile_next_event_enrollment_deserializes() -> Result<()> {
    // Setup the contract database and dedicated due event fixture
    let db = contract_tests_db()?;

    // Claim and reconcile the due event through the Rust JSON contract
    let outcome = db
        .reconcile_next_event_enrollment(None)
        .await?
        .context("due contract event should be claimable")?;

    // Check the reconciliation context deserializes completely
    assert_eq!(outcome.community_id, community_id());
    assert_eq!(outcome.event_id, reconcile_due_event_id());
    assert_eq!(outcome.group_id, subgroup_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_refresh_user_badge_identity_deserializes() -> Result<()> {
    // Setup the contract database and stale badge identity
    let db = contract_tests_db()?;

    // Rebind the stale seeded identity, repeat the current binding, and read
    // the persisted award through its production wrapper
    let rebound = db
        .refresh_user_badge_identity(organizer_id(), rebind_user_badge_id())
        .await?;
    let repeated = db
        .refresh_user_badge_identity(organizer_id(), rebind_user_badge_id())
        .await?;
    let award = db
        .get_user_badge(organizer_id(), rebind_user_badge_id())
        .await?
        .context("rebind contract badge should exist")?;

    // Check the database digest matches the Rust hash of the owner email and salt
    let expected_hash =
        compute_hash(format!("organizer.contract@example.com{}", rebound.identity_salt).as_bytes());
    assert_eq!(rebound.identity_hash, expected_hash);
    assert_ne!(rebound.identity_salt, "0123456789abcdef0123456789abcdef");
    assert_eq!(rebound.identity_salt.len(), 32);
    assert!(rebound.identity_bound_at > DateTime::from_timestamp(1_705_057_200, 0).unwrap());

    // Check the binding stays stable until the owner email changes again
    assert_eq!(repeated, rebound);

    // Check the award JSON exposes the persisted identity binding fields
    assert_eq!(award.identity_bound_at, Some(rebound.identity_bound_at));
    assert_eq!(award.identity_hash, Some(rebound.identity_hash));
    assert_eq!(award.identity_salt, Some(rebound.identity_salt));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_reject_event_refund_request_blocks_event_writers() -> Result<()> {
    // Setup independent refund rejection and event-lock connections
    let pool = contract_tests_pool()?;
    let event_client = pool.get().await?;
    let rejection_client = pool.get().await?;

    // Reject the request while retaining the refund workflow locks
    rejection_client.batch_execute("begin").await?;
    rejection_client
        .query_one(
            "select reject_event_refund_request($1::uuid, $2::uuid, $3::uuid, $4::text)",
            &[
                &organizer_id(),
                &group_id(),
                &refund_reject_purchase_id(),
                &"Rejected by lock contract",
            ],
        )
        .await?;

    // Probe whether a competing writer can lock the owning event
    event_client
        .batch_execute("begin; set local lock_timeout = '250ms'")
        .await?;
    let lock_result = event_client
        .query_one(
            "select event_id from event where event_id = $1::uuid for update",
            &[&refund_event_id()],
        )
        .await;

    // Roll back the rejection and lock probe before checking the outcome
    event_client.batch_execute("rollback").await?;
    rejection_client.batch_execute("rollback").await?;

    // Check rejection holds the event lock before refund workflow rows
    let lock_err = lock_result.expect_err("event writer should wait for refund rejection");
    assert_eq!(lock_err.code(), Some(&SqlState::LOCK_NOT_AVAILABLE));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_reject_event_refund_request_deserializes() -> Result<()> {
    // Setup the contract database and pending refund request
    let db = contract_tests_db()?;

    // Reject the refund request through the Rust contract
    let purchase = db
        .reject_event_refund_request(
            organizer_id(),
            group_id(),
            refund_reject_purchase_id(),
            "Rejected by contract test".to_string(),
        )
        .await?;

    // Check the returned purchase ownership fields
    assert_eq!(purchase.community_id, community_id());
    assert_eq!(purchase.event_id, paid_event_id());
    assert_eq!(purchase.user_id, refund_reject_buyer_id());

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
async fn db_contracts_search_events_deserializes() -> Result<()> {
    // Setup the contract database and event search filters
    let db = contract_tests_db()?;
    let filters = SearchEventsFilters {
        community: vec!["contract-community".to_string()],

        date_from: Some("2099-01-01".to_string()),
        date_to: Some("2099-12-31".to_string()),
        include_bbox: Some(true),
        limit: Some(10),
        offset: Some(0),

        ..Default::default()
    };

    // Search events through the Rust contract
    let output = db.search_events(&filters).await?;

    // Check result totals and map bounds
    assert_eq!(output.total, 1);
    assert_eq!(output.events.len(), 1);
    assert!(output.bbox.is_some());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_groups_deserializes() -> Result<()> {
    // Setup the contract database and group search filters
    let db = contract_tests_db()?;
    let filters = SearchGroupsFilters {
        community: vec!["contract-community".to_string()],

        include_bbox: Some(true),
        limit: Some(10),
        offset: Some(0),

        ..Default::default()
    };

    // Search groups through the Rust contract
    let output = db.search_groups(&filters).await?;

    // Check result totals and map bounds
    assert_eq!(output.total, 2);
    assert_eq!(output.groups.len(), 2);
    assert!(output.bbox.is_some());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_user_deserializes() -> Result<()> {
    // Setup the contract database and user query
    let db = contract_tests_db()?;

    // Search users through the Rust contract
    let users = db.search_user("contract-att").await?;

    // Check the matching public user fields
    assert_eq!(users.len(), 1);
    assert_eq!(users[0].user_id, attendee_id());
    assert_eq!(users[0].username, "contract-attendee");
    assert_eq!(users[0].name.as_deref(), Some("Contract Attendee"));

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

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_update_session_proposal_blocks_key_share() -> Result<()> {
    // Setup independent proposal update and lock-probe connections
    let pool = contract_tests_pool()?;
    let probe_client = pool.get().await?;
    let update_client = pool.get().await?;
    let proposal = Json(serde_json::json!({
        "co_speaker_user_id": null,
        "description": "An updated proposal used to verify update locks",
        "duration_minutes": 45,
        "session_proposal_level_id": "beginner",
        "title": "Contract Update Lock Proposal Updated"
    }));

    // Update the proposal while retaining its explicit update lock
    update_client.batch_execute("begin").await?;
    update_client
        .query_one(
            "select update_session_proposal($1::uuid, $2::uuid, $3::jsonb)",
            &[&organizer_id(), &cfs_update_lock_proposal_id(), &proposal],
        )
        .await?;

    // Probe with a lock mode compatible with an ordinary non-key update
    probe_client
        .batch_execute("begin; set local lock_timeout = '250ms'")
        .await?;
    let lock_result = probe_client
        .query_one(
            "select session_proposal_id from session_proposal where session_proposal_id = $1::uuid for key share",
            &[&cfs_update_lock_proposal_id()],
        )
        .await;

    // Roll back the update and lock probe before checking the outcome
    probe_client.batch_execute("rollback").await?;
    update_client.batch_execute("rollback").await?;

    // Check the explicit update lock blocks a competing key-share reader
    let lock_err = lock_result.expect_err("proposal read should wait for the update lock");
    assert_eq!(lock_err.code(), Some(&SqlState::LOCK_NOT_AVAILABLE));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_update_user_external_auth_deserializes() -> Result<()> {
    // Setup the contract database and external profile update
    let db = contract_tests_db()?;
    let user_summary = UserSummary {
        email: "external-update-new.contract@example.com".to_string(),
        name: "Contract External Update".to_string(),
        username: "contract-external-update".to_string(),

        has_password: None,
        password: None,
        provider: Some(UserProvider::from_linuxfoundation_identity(
            "https://issuer.example.com".to_string(),
            "auth0|contract-external-update".to_string(),
            "contract-external-update".to_string(),
        )),
    };

    // Update external authentication through the Rust contract
    let user = db
        .update_user_external_auth(&external_update_id(), &user_summary)
        .await?;

    // Check account identity and verification fields
    assert_eq!(user.email, "external-update-new.contract@example.com");
    assert!(user.email_verified);
    assert_eq!(user.name, "Contract External Update");
    assert_eq!(user.user_id, external_update_id());

    // Check provider identities deserialize as expected
    assert_eq!(
        user.provider,
        Some(UserProvider {
            github: Some(crate::types::user::GitHubUserProvider {
                username: "contract-external-update".to_string(),
            }),
            linuxfoundation: Some(crate::types::user::LinuxFoundationUserProvider {
                username: "contract-external-update".to_string(),

                issuer: Some("https://issuer.example.com".to_string()),
                subject: Some("auth0|contract-external-update".to_string()),
            }),
        })
    );

    Ok(())
}

// Helpers.

const ACTIVATION_ID: &str = "00000000-0000-0000-0000-00000000c045";
const ACTIVE_USER_BADGE_ID: &str = "00000000-0000-0000-0000-00000000c0bd";
const ATTENDEE_ID: &str = "00000000-0000-0000-0000-00000000c042";
const AUTO_END_MEETING_ID: &str = "00000000-0000-0000-0000-00000000c0a3";
const BADGE_ARTWORK_ID: &str = "00000000-0000-0000-0000-00000000c0ba";
const BADGE_AWARD_JOB_ID: &str = "00000000-0000-0000-0000-00000000c0bf";
const BADGE_ID: &str = "00000000-0000-0000-0000-00000000c0bb";
const BADGE_STATUS_LIST_ID: &str = "00000000-0000-0000-0000-00000000c0bc";
const CANCELEE_ID: &str = "00000000-0000-0000-0000-00000000c0e9";
/// User fixture that races an RSVP against event cancellation.
const CANCELLATION_LOCK_ATTENDEE_ID: &str = "00000000-0000-0000-0000-00000000c0ec";
/// Event fixture used to verify cancellation lock ownership.
const CANCELLATION_LOCK_EVENT_ID: &str = "00000000-0000-0000-0000-00000000c0d6";
/// Proposal fixture used to verify submission share locking.
const CFS_ADD_LOCK_PROPOSAL_ID: &str = "00000000-0000-0000-0000-00000000c124";
/// Proposal fixture used to verify deletion lock ordering.
const CFS_DELETE_LOCK_PROPOSAL_ID: &str = "00000000-0000-0000-0000-00000000c125";
/// Session fixture used to verify CFS submission locking.
const CFS_LOCK_SESSION_ID: &str = "00000000-0000-0000-0000-00000000c123";
const CFS_SUBMISSION_ID: &str = "00000000-0000-0000-0000-00000000c0c5";
/// Proposal fixture used to verify update lock strength.
const CFS_UPDATE_LOCK_PROPOSAL_ID: &str = "00000000-0000-0000-0000-00000000c126";
const CHECK_IN_CODE: &str = "00000000-0000-0000-0000-00000000c084";
const CHECKOUT_BUYER_ID: &str = "00000000-0000-0000-0000-00000000c0e1";
const CLAIM_GROUP_ID: &str = "00000000-0000-0000-0000-00000000c0a0";
const CO_SPEAKER_PROPOSAL_ID: &str = "00000000-0000-0000-0000-00000000c0c2";
const COMMUNITY_ID: &str = "00000000-0000-0000-0000-00000000c001";
const DOCUMENT_ADJUSTMENT_ID: &str = "00000000-0000-0000-0000-00000000c11d";
const DOCUMENT_CREDIT_NOTE_ID: &str = "00000000-0000-0000-0000-00000000c11e";
const DOCUMENT_PURCHASE_ID: &str = "00000000-0000-0000-0000-00000000c11b";
const DOCUMENT_REFUND_ID: &str = "00000000-0000-0000-0000-00000000c11c";
const EVENT_CATEGORY_ID: &str = "00000000-0000-0000-0000-00000000c013";
const EVENT_ID: &str = "00000000-0000-0000-0000-00000000c031";
const EXTERNAL_LOOKUP_ID: &str = "00000000-0000-0000-0000-00000000c046";
const EXTERNAL_UPDATE_ID: &str = "00000000-0000-0000-0000-00000000c047";
const FINANCIAL_RECOVERY_ADJUSTMENT_ID: &str = "00000000-0000-0000-0000-00000000c119";
const FINANCIAL_RECOVERY_CREDIT_NOTE_ID: &str = "00000000-0000-0000-0000-00000000c11a";
const FREE_BUYER_ID: &str = "00000000-0000-0000-0000-00000000c0e4";
const FREE_PURCHASE_ID: &str = "00000000-0000-0000-0000-00000000c0f3";
const GROUP_ID: &str = "00000000-0000-0000-0000-00000000c021";
/// First event fixture used to verify group-level mutation locks.
const GROUP_LOCK_FIRST_EVENT_ID: &str = "00000000-0000-0000-0000-00000000c121";
/// Second event fixture used to verify group-level mutation locks.
const GROUP_LOCK_SECOND_EVENT_ID: &str = "00000000-0000-0000-0000-00000000c122";
const GROUP_SPONSOR_ID: &str = "00000000-0000-0000-0000-00000000c061";
const INVITATION_OFFER_ID: &str = "00000000-0000-0000-0000-00000000c083";
const INVITATION_TICKET_TYPE_ID: &str = "00000000-0000-0000-0000-00000000c081";
const INVITE_EVENT_ID: &str = "00000000-0000-0000-0000-00000000c0d8";
const INVITEE_ID: &str = "00000000-0000-0000-0000-00000000c0ed";
const LEAVER_ID: &str = "00000000-0000-0000-0000-00000000c0e8";
const MUTATION_EVENT_ID: &str = "00000000-0000-0000-0000-00000000c0d5";
const MUTATION_OFFER_ID: &str = "00000000-0000-0000-0000-00000000c0d7";
const OFFER_DECLINE_EVENT_ID: &str = "00000000-0000-0000-0000-00000000c0dc";
const OFFER_DECLINE_OFFER_ID: &str = "00000000-0000-0000-0000-00000000c0dd";
const OFFER_DECLINER_ID: &str = "00000000-0000-0000-0000-00000000c0f0";
const ORGANIZER_ID: &str = "00000000-0000-0000-0000-00000000c041";
const PAID_CANCELLATION_PURCHASE_ID: &str = "00000000-0000-0000-0000-00000000c118";
const PAID_CANCELLATION_USER_ID: &str = "00000000-0000-0000-0000-00000000c117";
const PAID_TICKET_PRICE_WINDOW_ID: &str = "00000000-0000-0000-0000-00000000c0d2";
const PAID_TICKET_TYPE_ID: &str = "00000000-0000-0000-0000-00000000c0d1";
const PAST_EVENT_ID: &str = "00000000-0000-0000-0000-00000000c032";
const PRE_REGISTERED_ID: &str = "00000000-0000-0000-0000-00000000c044";
/// Event fixture whose full capacity sends organizer invitations to the queue.
const QUEUE_INVITE_EVENT_ID: &str = "00000000-0000-0000-0000-00000000c105";
/// User fixture queued by the organizer invitation contract.
const QUEUE_INVITEE_ID: &str = "00000000-0000-0000-0000-00000000c103";
const REBIND_USER_BADGE_ID: &str = "00000000-0000-0000-0000-00000000c0b9";
const RECONCILE_BUYER_ID: &str = "00000000-0000-0000-0000-00000000c0e3";
const RECONCILE_DUE_EVENT_ID: &str = "00000000-0000-0000-0000-00000000c0de";
const REFUND_OFFER_USER_ID: &str = "00000000-0000-0000-0000-00000000c101";
/// Purchase fixture whose provider refund is ready for local finalization.
const REFUND_APPROVE_PURCHASE_ID: &str = "00000000-0000-0000-0000-00000000c0f6";
const REFUND_BEGIN_PURCHASE_ID: &str = "00000000-0000-0000-0000-00000000c0f4";
const REFUND_LIFECYCLE_PURCHASE_ID: &str = "00000000-0000-0000-0000-00000000c0fb";
/// Paid event containing the refund contract fixtures.
const REFUND_EVENT_ID: &str = "00000000-0000-0000-0000-00000000c0d0";
/// Purchase fixture whose locally finalized refund requires recovery.
const REFUND_RECOVERY_PURCHASE_ID: &str = "00000000-0000-0000-0000-00000000c0fd";
/// Durable refund fixture preserving post-finalization recovery state.
const REFUND_RECOVERY_REFUND_ID: &str = "00000000-0000-0000-0000-00000000c0fe";
const REFUND_REJECT_BUYER_ID: &str = "00000000-0000-0000-0000-00000000c0e7";
/// Purchase fixture whose refund request is ready for rejection.
const REFUND_REJECT_PURCHASE_ID: &str = "00000000-0000-0000-0000-00000000c0f8";
/// Buyer fixture with a rejected refund reason for attendee-facing contracts.
const REFUND_REJECTED_BUYER_ID: &str = "00000000-0000-0000-0000-00000000c114";
const REJECTED_REQUEST_USER_ID: &str = "00000000-0000-0000-0000-00000000c102";
const REQUEST_EVENT_ID: &str = "00000000-0000-0000-0000-00000000c0d9";
const REQUESTER_ID: &str = "00000000-0000-0000-0000-00000000c0ee";
const REVOKED_USER_BADGE_ID: &str = "00000000-0000-0000-0000-00000000c0be";
const SESSION_PROPOSAL_ID: &str = "00000000-0000-0000-0000-00000000c0c1";
const SITE_ID: &str = "00000000-0000-0000-0000-00000000c0b1";
/// User fixture with a canceled organizer invitation.
const STATUS_CANCELED_USER_ID: &str = "00000000-0000-0000-0000-00000000c10e";
/// User fixture with a declined organizer invitation.
const STATUS_DECLINED_USER_ID: &str = "00000000-0000-0000-0000-00000000c10f";
/// Event fixture dedicated to enrollment status contracts.
const STATUS_EVENT_ID: &str = "00000000-0000-0000-0000-00000000c109";
/// User fixture with an expired organizer invitation.
const STATUS_EXPIRED_USER_ID: &str = "00000000-0000-0000-0000-00000000c10d";
/// User fixture with a resumable pending payment.
const STATUS_PENDING_PAYMENT_USER_ID: &str = "00000000-0000-0000-0000-00000000c10c";
/// Ticket fixture used by the pending payment.
const STATUS_TICKET_TYPE_ID: &str = "00000000-0000-0000-0000-00000000c10a";
const SUBGROUP_ID: &str = "00000000-0000-0000-0000-00000000c022";
const SUMMARY_PURCHASE_ID: &str = "00000000-0000-0000-0000-00000000c0f1";
const SYNC_EVENT_ID: &str = "00000000-0000-0000-0000-00000000c0a1";
const TICKETED_EVENT_ID: &str = "00000000-0000-0000-0000-00000000c0d0";
const WAITLIST_ID: &str = "00000000-0000-0000-0000-00000000c043";

/// Returns the activation identifier used by the contract fixture.
fn activation_id() -> Uuid {
    parse_uuid(ACTIVATION_ID)
}

/// Returns the active user badge identifier used by the contract fixture.
fn active_user_badge_id() -> Uuid {
    parse_uuid(ACTIVE_USER_BADGE_ID)
}

/// Checks the complete paid ticket type JSON contract.
fn assert_contract_paid_ticket_type(ticket_type: &EventTicketType) {
    assert!(ticket_type.active);
    assert_eq!(
        ticket_type.availability,
        EventTicketTypeAvailability::Public
    );
    assert_eq!(ticket_type.event_ticket_type_id, paid_ticket_type_id());
    assert_eq!(ticket_type.order, 1);
    assert_eq!(ticket_type.title, "Contract Paid Ticket");

    let current_price = ticket_type
        .current_price
        .as_ref()
        .expect("paid contract ticket to have a current price");
    assert_eq!(current_price.amount_minor, 2_500);
    assert_eq!(current_price.ends_at, None);
    assert_eq!(current_price.starts_at, None);
    assert_eq!(ticket_type.description, None);
    assert_eq!(ticket_type.price_windows.len(), 1);
    assert_eq!(ticket_type.price_windows[0].amount_minor, 2_500);
    assert_eq!(
        ticket_type.price_windows[0].event_ticket_price_window_id,
        paid_ticket_price_window_id()
    );
    assert_eq!(ticket_type.price_windows[0].ends_at, None);
    assert_eq!(ticket_type.price_windows[0].starts_at, None);
    assert!(ticket_type.remaining_seats.is_some());
    assert_eq!(ticket_type.seats_total, Some(50));
    assert!(!ticket_type.sold_out);
}

/// Checks the complete ticket type JSON contract shared by event projections.
fn assert_contract_ticket_type(ticket_type: &EventTicketType) {
    assert!(ticket_type.active);
    assert_eq!(
        ticket_type.availability,
        EventTicketTypeAvailability::Public
    );
    assert_eq!(
        ticket_type.event_ticket_type_id,
        invitation_ticket_type_id()
    );
    assert_eq!(ticket_type.order, 1);
    assert_eq!(ticket_type.title, "General Admission");

    let current_price = ticket_type
        .current_price
        .as_ref()
        .expect("contract ticket to have a current price");
    assert_eq!(current_price.amount_minor, 2_500);
    assert_eq!(current_price.ends_at, None);
    assert_eq!(current_price.starts_at, None);
    assert_eq!(ticket_type.description, None);
    assert_eq!(ticket_type.price_windows.len(), 1);
    assert_eq!(ticket_type.price_windows[0].amount_minor, 2_500);
    assert_eq!(
        ticket_type.price_windows[0].event_ticket_price_window_id,
        parse_uuid("00000000-0000-0000-0000-00000000c082")
    );
    assert_eq!(ticket_type.price_windows[0].ends_at, None);
    assert_eq!(ticket_type.price_windows[0].starts_at, None);
    assert_eq!(ticket_type.remaining_seats, Some(98));
    assert_eq!(ticket_type.seats_total, Some(100));
    assert!(!ticket_type.sold_out);
}

/// Returns the attendee identifier used by the contract fixture.
fn attendee_id() -> Uuid {
    parse_uuid(ATTENDEE_ID)
}

/// Returns the automatically ended meeting identifier used by the contract fixture.
fn auto_end_meeting_id() -> Uuid {
    parse_uuid(AUTO_END_MEETING_ID)
}

/// Returns the badge artwork identifier used by the contract fixture.
fn badge_artwork_id() -> Uuid {
    parse_uuid(BADGE_ARTWORK_ID)
}

/// Returns the badge award job identifier used by the contract fixture.
fn badge_award_job_id() -> Uuid {
    parse_uuid(BADGE_AWARD_JOB_ID)
}

/// Returns the badge identifier used by the contract fixture.
fn badge_id() -> Uuid {
    parse_uuid(BADGE_ID)
}

/// Returns the badge status list identifier used by the contract fixture.
fn badge_status_list_id() -> Uuid {
    parse_uuid(BADGE_STATUS_LIST_ID)
}

/// Builds an active user badge from the supplied contract snapshot and identity fields.
fn contract_active_user_badge(
    snapshot: BadgeSnapshot,
    event_name: Option<String>,
    recipient_name: Option<String>,
    recipient_username: Option<String>,
) -> UserBadge {
    UserBadge {
        awarded_at: DateTime::from_timestamp(1_705_053_600, 0).unwrap(),
        badge_status_list_id: badge_status_list_id(),
        display_order: 0,
        group_id: group_id(),
        is_listed: true,
        snapshot,
        status_list_index: 7,
        user_badge_id: active_user_badge_id(),

        badge_id: Some(badge_id()),
        event_id: Some(event_id()),
        event_name,
        identity_bound_at: None,
        identity_hash: None,
        identity_salt: None,
        recipient_name,
        recipient_username,
        revocation_reason: None,
        revoked_at: None,
        revoked_by_user_id: None,
        user_id: Some(attendee_id()),
    }
}

/// Builds the badge snapshot used by contract fixtures.
fn contract_badge_snapshot() -> BadgeSnapshot {
    BadgeSnapshot {
        criteria: "Attend the contract event".to_string(),
        description: "Recognizes contract event participation".to_string(),
        image_file_name: "contract-badge.png".to_string(),
        issuer: BadgeSnapshotIssuer {
            community_id: community_id(),
            community_name: "Contract Community".to_string(),
            group_id: group_id(),
            group_name: "Contract Group".to_string(),
        },
        name: "Contract Participant".to_string(),
    }
}

/// Returns the pending application-fee adjustment used by worker contracts.
fn document_adjustment_id() -> Uuid {
    parse_uuid(DOCUMENT_ADJUSTMENT_ID)
}

/// Returns the credit note used by worker and attendee document contracts.
fn document_credit_note_id() -> Uuid {
    parse_uuid(DOCUMENT_CREDIT_NOTE_ID)
}

/// Returns the provider-backed purchase used by attendee document contracts.
fn document_purchase_id() -> Uuid {
    parse_uuid(DOCUMENT_PURCHASE_ID)
}

/// Returns the provider refund used by credit-note worker contracts.
fn document_refund_id() -> Uuid {
    parse_uuid(DOCUMENT_REFUND_ID)
}

/// Returns the event cancellation target identifier used by the contract fixture.
fn cancelee_id() -> Uuid {
    parse_uuid(CANCELEE_ID)
}

/// Returns the attendee fixture that races event cancellation.
fn cancellation_lock_attendee_id() -> Uuid {
    parse_uuid(CANCELLATION_LOCK_ATTENDEE_ID)
}

/// Returns the event fixture used to verify cancellation locking.
fn cancellation_lock_event_id() -> Uuid {
    parse_uuid(CANCELLATION_LOCK_EVENT_ID)
}

/// Returns the proposal used to verify submission share locking.
fn cfs_add_lock_proposal_id() -> Uuid {
    parse_uuid(CFS_ADD_LOCK_PROPOSAL_ID)
}

/// Returns the proposal used to verify deletion lock ordering.
fn cfs_delete_lock_proposal_id() -> Uuid {
    parse_uuid(CFS_DELETE_LOCK_PROPOSAL_ID)
}

/// Returns the session identifier used to verify CFS submission locking.
fn cfs_lock_session_id() -> Uuid {
    parse_uuid(CFS_LOCK_SESSION_ID)
}

/// Returns the call-for-speakers submission identifier used by the contract fixture.
fn cfs_submission_id() -> Uuid {
    parse_uuid(CFS_SUBMISSION_ID)
}

/// Returns the proposal used to verify update lock strength.
fn cfs_update_lock_proposal_id() -> Uuid {
    parse_uuid(CFS_UPDATE_LOCK_PROPOSAL_ID)
}

/// Returns the attendee check-in code used by the contract fixture.
fn check_in_code() -> Uuid {
    parse_uuid(CHECK_IN_CODE)
}

/// Returns the checkout buyer identifier used by the contract fixture.
fn checkout_buyer_id() -> Uuid {
    parse_uuid(CHECKOUT_BUYER_ID)
}

/// Returns the claim group identifier used by the contract fixture.
fn claim_group_id() -> Uuid {
    parse_uuid(CLAIM_GROUP_ID)
}

/// Returns the co-speaker proposal identifier used by the contract fixture.
fn co_speaker_proposal_id() -> Uuid {
    parse_uuid(CO_SPEAKER_PROPOSAL_ID)
}

/// Returns the community identifier used by the contract fixture.
fn community_id() -> Uuid {
    parse_uuid(COMMUNITY_ID)
}

/// Builds the shared `PostgreSQL` configuration for contract tests.
fn contract_tests_config() -> Result<DeadpoolDbConfig> {
    let port = env_or_default("OCG_DB_PORT", "5432")
        .parse()
        .context("OCG_DB_PORT must be a valid port number")?;

    let mut cfg = DeadpoolDbConfig::new();
    cfg.dbname = Some(env_or_default(
        "OCG_DB_NAME_TESTS_CONTRACT",
        "ocg_tests_contract",
    ));
    cfg.host = Some(env_or_default("OCG_DB_HOST", "localhost"));
    cfg.port = Some(port);
    cfg.user = Some(env_or_default("OCG_DB_USER", "postgres"));

    if let Ok(password) = env::var("OCG_DB_PASSWORD")
        && !password.is_empty()
    {
        cfg.password = Some(password);
    }

    Ok(cfg)
}

/// Creates the typed database wrapper used by contract tests.
fn contract_tests_db() -> Result<PgDB> {
    Ok(PgDB::new(contract_tests_pool()?))
}

/// Creates an independent `PostgreSQL` connection pool for concurrency tests.
fn contract_tests_pool() -> Result<Pool> {
    Ok(contract_tests_config()?.create_pool(Some(Runtime::Tokio1), NoTls)?)
}

/// Returns an environment value or its contract-test default.
fn env_or_default(name: &str, default: &str) -> String {
    env::var(name).unwrap_or_else(|_| default.to_string())
}

/// Returns the event category identifier used by the contract fixture.
fn event_category_id() -> Uuid {
    parse_uuid(EVENT_CATEGORY_ID)
}

/// Returns the event identifier used by the contract fixture.
fn event_id() -> Uuid {
    parse_uuid(EVENT_ID)
}

/// Returns the external identity lookup identifier used by the contract fixture.
fn external_lookup_id() -> Uuid {
    parse_uuid(EXTERNAL_LOOKUP_ID)
}

/// Returns the external identity update identifier used by the contract fixture.
fn external_update_id() -> Uuid {
    parse_uuid(EXTERNAL_UPDATE_ID)
}

/// Returns the exhausted application-fee recovery work identifier.
fn financial_recovery_adjustment_id() -> Uuid {
    parse_uuid(FINANCIAL_RECOVERY_ADJUSTMENT_ID)
}

/// Returns the exhausted credit-note recovery work identifier.
fn financial_recovery_credit_note_id() -> Uuid {
    parse_uuid(FINANCIAL_RECOVERY_CREDIT_NOTE_ID)
}

/// Returns the free checkout buyer identifier used by the contract fixture.
fn free_buyer_id() -> Uuid {
    parse_uuid(FREE_BUYER_ID)
}

/// Returns the free purchase identifier used by the contract fixture.
fn free_purchase_id() -> Uuid {
    parse_uuid(FREE_PURCHASE_ID)
}

/// Returns the group identifier used by the contract fixture.
fn group_id() -> Uuid {
    parse_uuid(GROUP_ID)
}

/// Returns an event update used by group-level lock contract tests.
fn group_lock_event_update(name: &str, day: u32) -> EventUpdate {
    let starts_at = NaiveDate::from_ymd_opt(2099, 8, day)
        .expect("date should be valid")
        .and_hms_opt(10, 0, 0)
        .expect("time should be valid");
    let ends_at = NaiveDate::from_ymd_opt(2099, 8, day)
        .expect("date should be valid")
        .and_hms_opt(11, 0, 0)
        .expect("time should be valid");

    EventUpdate {
        category_id: event_category_id(),
        description: "An event used by group lock contract tests".to_string(),
        kind_id: "virtual".to_string(),
        name: name.to_string(),
        timezone: "UTC".to_string(),

        capacity: Some(100),
        ends_at: Some(ends_at),
        starts_at: Some(starts_at),
        test_event: Some(true),

        ..Default::default()
    }
}

/// Returns the first event used to verify group-level mutation locks.
fn group_lock_first_event_id() -> Uuid {
    parse_uuid(GROUP_LOCK_FIRST_EVENT_ID)
}

/// Returns the second event used to verify group-level mutation locks.
fn group_lock_second_event_id() -> Uuid {
    parse_uuid(GROUP_LOCK_SECOND_EVENT_ID)
}

/// Returns the group sponsor identifier used by the contract fixture.
fn group_sponsor_id() -> Uuid {
    parse_uuid(GROUP_SPONSOR_ID)
}

/// Returns the invitation offer identifier used by the contract fixture.
fn invitation_offer_id() -> Uuid {
    parse_uuid(INVITATION_OFFER_ID)
}

/// Returns the invitation ticket type identifier used by the contract fixture.
fn invitation_ticket_type_id() -> Uuid {
    parse_uuid(INVITATION_TICKET_TYPE_ID)
}

/// Returns the invited event identifier used by the contract fixture.
fn invite_event_id() -> Uuid {
    parse_uuid(INVITE_EVENT_ID)
}

/// Returns the invitee identifier used by the contract fixture.
fn invitee_id() -> Uuid {
    parse_uuid(INVITEE_ID)
}

/// Returns the departing attendee identifier used by the contract fixture.
fn leaver_id() -> Uuid {
    parse_uuid(LEAVER_ID)
}

/// Returns the mutation event identifier used by the contract fixture.
fn mutation_event_id() -> Uuid {
    parse_uuid(MUTATION_EVENT_ID)
}

/// Returns the mutation offer identifier used by the contract fixture.
fn mutation_offer_id() -> Uuid {
    parse_uuid(MUTATION_OFFER_ID)
}

/// Returns the notification identifier used by the contract fixture.
fn notification_id() -> Uuid {
    parse_uuid("00000000-0000-0000-0000-00000000c0f1")
}

/// Returns the declined offer event identifier used by the contract fixture.
fn offer_decline_event_id() -> Uuid {
    parse_uuid(OFFER_DECLINE_EVENT_ID)
}

/// Returns the declined offer identifier used by the contract fixture.
fn offer_decline_offer_id() -> Uuid {
    parse_uuid(OFFER_DECLINE_OFFER_ID)
}

/// Returns the offer decliner identifier used by the contract fixture.
fn offer_decliner_id() -> Uuid {
    parse_uuid(OFFER_DECLINER_ID)
}

/// Returns the organizer identifier used by the contract fixture.
fn organizer_id() -> Uuid {
    parse_uuid(ORGANIZER_ID)
}

/// Returns the purchase used by paid attendance cancellation contracts.
fn paid_cancellation_purchase_id() -> Uuid {
    parse_uuid(PAID_CANCELLATION_PURCHASE_ID)
}

/// Returns the attendee used by paid attendance cancellation contracts.
fn paid_cancellation_user_id() -> Uuid {
    parse_uuid(PAID_CANCELLATION_USER_ID)
}

/// Returns the paid ticket price window identifier used by the contract fixture.
fn paid_ticket_price_window_id() -> Uuid {
    parse_uuid(PAID_TICKET_PRICE_WINDOW_ID)
}

/// Returns the paid ticket type identifier used by the contract fixture.
fn paid_ticket_type_id() -> Uuid {
    parse_uuid(PAID_TICKET_TYPE_ID)
}

/// Parses a UUID stored by the contract fixture.
fn parse_uuid(value: &str) -> Uuid {
    Uuid::parse_str(value).expect("contract fixture UUID should be valid")
}

/// Returns the past event identifier used by the contract fixture.
fn past_event_id() -> Uuid {
    parse_uuid(PAST_EVENT_ID)
}

/// Returns the pre-registered attendee identifier used by the contract fixture.
fn pre_registered_id() -> Uuid {
    parse_uuid(PRE_REGISTERED_ID)
}

/// Returns the award fixture dedicated to the identity rebind contract.
fn rebind_user_badge_id() -> Uuid {
    parse_uuid(REBIND_USER_BADGE_ID)
}

/// Returns the reconciliation buyer identifier used by the contract fixture.
fn reconcile_buyer_id() -> Uuid {
    parse_uuid(RECONCILE_BUYER_ID)
}

/// Returns the due reconciliation event identifier used by the contract fixture.
fn reconcile_due_event_id() -> Uuid {
    parse_uuid(RECONCILE_DUE_EVENT_ID)
}

/// Returns the user whose linked offer is hidden during refund processing.
fn refund_offer_user_id() -> Uuid {
    parse_uuid(REFUND_OFFER_USER_ID)
}

/// Returns the purchase fixture ready for local refund finalization.
fn refund_approve_purchase_id() -> Uuid {
    parse_uuid(REFUND_APPROVE_PURCHASE_ID)
}

/// Returns the purchase fixture ready to begin refund processing.
fn refund_begin_purchase_id() -> Uuid {
    parse_uuid(REFUND_BEGIN_PURCHASE_ID)
}

/// Returns the paid event identifier containing the refund fixtures.
fn refund_event_id() -> Uuid {
    parse_uuid(REFUND_EVENT_ID)
}

/// Returns the purchase identifier used by the refund lifecycle fixture.
fn refund_lifecycle_purchase_id() -> Uuid {
    parse_uuid(REFUND_LIFECYCLE_PURCHASE_ID)
}

/// Returns the purchase identifier for the refund recovery fixture.
fn refund_recovery_purchase_id() -> Uuid {
    parse_uuid(REFUND_RECOVERY_PURCHASE_ID)
}

/// Returns the durable refund identifier for the recovery fixture.
fn refund_recovery_refund_id() -> Uuid {
    parse_uuid(REFUND_RECOVERY_REFUND_ID)
}

/// Returns the refund rejection buyer identifier used by the contract fixture.
fn refund_reject_buyer_id() -> Uuid {
    parse_uuid(REFUND_REJECT_BUYER_ID)
}

/// Returns the purchase fixture ready for refund rejection.
fn refund_reject_purchase_id() -> Uuid {
    parse_uuid(REFUND_REJECT_PURCHASE_ID)
}

/// Returns the buyer whose rejected refund is visible on attendee surfaces.
fn refund_rejected_buyer_id() -> Uuid {
    parse_uuid(REFUND_REJECTED_BUYER_ID)
}

/// Returns the rejected requester ignored after approval is disabled.
fn rejected_request_user_id() -> Uuid {
    parse_uuid(REJECTED_REQUEST_USER_ID)
}

/// Returns the invitation request event identifier used by the contract fixture.
fn request_event_id() -> Uuid {
    parse_uuid(REQUEST_EVENT_ID)
}

/// Returns the requester identifier used by the contract fixture.
fn requester_id() -> Uuid {
    parse_uuid(REQUESTER_ID)
}

/// Returns the revoked user badge identifier used by the contract fixture.
fn revoked_user_badge_id() -> Uuid {
    parse_uuid(REVOKED_USER_BADGE_ID)
}

/// Returns the session proposal identifier used by the contract fixture.
fn session_proposal_id() -> Uuid {
    parse_uuid(SESSION_PROPOSAL_ID)
}

/// Returns the site identifier used by the contract fixture.
fn site_id() -> Uuid {
    parse_uuid(SITE_ID)
}

/// Returns the canceled-offer user used by the status contract.
fn status_canceled_user_id() -> Uuid {
    parse_uuid(STATUS_CANCELED_USER_ID)
}

/// Returns the declined-offer user used by the status contract.
fn status_declined_user_id() -> Uuid {
    parse_uuid(STATUS_DECLINED_USER_ID)
}

/// Returns the event dedicated to enrollment status contracts.
fn status_event_id() -> Uuid {
    parse_uuid(STATUS_EVENT_ID)
}

/// Returns the expired-offer user used by the status contract.
fn status_expired_user_id() -> Uuid {
    parse_uuid(STATUS_EXPIRED_USER_ID)
}

/// Returns the pending-purchase user used by the status contract.
fn status_pending_payment_user_id() -> Uuid {
    parse_uuid(STATUS_PENDING_PAYMENT_USER_ID)
}

/// Returns the ticket used by the pending payment contract.
fn status_ticket_type_id() -> Uuid {
    parse_uuid(STATUS_TICKET_TYPE_ID)
}

/// Returns the subgroup identifier used by the contract fixture.
fn subgroup_id() -> Uuid {
    parse_uuid(SUBGROUP_ID)
}

/// Returns the purchase summary identifier used by the contract fixture.
fn summary_purchase_id() -> Uuid {
    parse_uuid(SUMMARY_PURCHASE_ID)
}

/// Returns the synchronized event identifier used by the contract fixture.
fn sync_event_id() -> Uuid {
    parse_uuid(SYNC_EVENT_ID)
}

/// Returns the paid event identifier used by the contract fixture.
fn paid_event_id() -> Uuid {
    parse_uuid(TICKETED_EVENT_ID)
}

/// Returns the event dedicated to queue-offer invitation allocation.
fn queue_invite_event_id() -> Uuid {
    parse_uuid(QUEUE_INVITE_EVENT_ID)
}

/// Returns the queued invitation target used by the allocation contract.
fn queue_invitee_id() -> Uuid {
    parse_uuid(QUEUE_INVITEE_ID)
}

/// Waits until one contract-test backend is blocked by another.
async fn wait_for_backend_blocker(
    client: &tokio_postgres::Client,
    owner_pid: i32,
    waiter_pid: i32,
) -> Result<()> {
    tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            // Check whether the expected backend owns the blocking lock
            let is_blocked = client
                .query_one(
                    "select $1::int = any(pg_blocking_pids($2::int))",
                    &[&owner_pid, &waiter_pid],
                )
                .await?
                .get::<_, bool>(0);

            // Finish once the intended lock wait is observable
            if is_blocked {
                return Ok::<(), tokio_postgres::Error>(());
            }

            // Yield briefly before polling the lock graph again
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .context("backend should reach the expected lock wait")??;

    Ok(())
}

/// Returns the waitlist identifier used by the contract fixture.
fn waitlist_id() -> Uuid {
    parse_uuid(WAITLIST_ID)
}
