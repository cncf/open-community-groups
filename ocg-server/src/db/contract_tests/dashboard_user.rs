//! Contract tests for the `DBDashboardUser` functions.

use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use tokio_postgres::{error::SqlState, types::Json};

use crate::{
    db::dashboard::user::DBDashboardUser,
    templates::dashboard::{
        audit::AuditLogFilters,
        user::{
            events::{UserEventRole, UserEventsFilters},
            groups::UserGroupsFilters,
            purchases::PurchaseDocumentsFilters,
            session_proposals::SessionProposalsFilters,
            submissions::CfsSubmissionsFilters as UserCfsSubmissionsFilters,
        },
    },
    types::{
        community::CommunityRole,
        event::{
            EventAdmissionOfferSource, EventAdmissionOfferStatus, EventEnrollmentStatus, EventKind,
        },
        group::GroupRole,
        payments::{EventRefundRequestStatus, ExternalPaymentInfo},
        questionnaire::QuestionnaireAnswerValue,
    },
    util::compute_hash,
};

use super::helpers::{
    attendee_id, cfs_delete_lock_proposal_id, cfs_update_lock_proposal_id, claim_group_id,
    co_speaker_proposal_id, community_id, contract_tests_db, contract_tests_pool,
    document_credit_note_id, document_purchase_id, event_id, external_completed_purchase_id,
    external_completed_user_id, external_event_id, external_pending_purchase_id,
    external_pending_user_id, free_buyer_id, group_id, invitation_offer_id,
    invitation_ticket_type_id, offer_decline_event_id, offer_decline_offer_id, offer_decliner_id,
    organizer_id, pre_registered_id, rebind_user_badge_id, refund_rejected_buyer_id,
    status_event_id, status_pending_payment_user_id, status_ticket_type_id, subgroup_id,
    wait_for_backend_blocker, waitlist_id,
};

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
    assert!(invitations[0].external_payment.is_none());
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
#[allow(clippy::too_many_lines)]
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
    assert!(output.events[0].external_payment.is_none());
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
    assert!(pending_checkout.external_payment.is_none());
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
async fn db_contracts_list_user_events_external_payment_deserializes() -> Result<()> {
    // Setup the contract database and pending external buyer fixture
    let db = contract_tests_db()?;
    let filters = UserEventsFilters {
        limit: Some(10),
        offset: Some(0),
    };

    // Load the pending external purchase through the Rust contract
    let output = db.list_user_events(external_pending_user_id(), &filters).await?;

    // Check pending external purchases expose payment instructions without a checkout URL
    assert_eq!(output.total, 1);
    assert_eq!(output.events.len(), 1);
    let event = &output.events[0];
    assert_eq!(event.event.event_id, external_event_id());
    assert_eq!(
        event.enrollment_status,
        Some(EventEnrollmentStatus::PendingPayment)
    );
    assert_eq!(event.amount_minor, Some(5000));
    assert_eq!(event.currency_code.as_deref(), Some("USD"));
    assert!(event.resume_checkout_url.is_none());
    assert_eq!(
        event.external_payment,
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
async fn db_contracts_list_user_purchase_documents_deserializes() -> Result<()> {
    // Setup the contract database and attendee document filters
    let db = contract_tests_db()?;
    let filters = PurchaseDocumentsFilters {
        limit: Some(10),
        offset: Some(0),
    };

    // Load invoice and credit-note history through the production wrapper
    let output = db.list_user_purchase_documents(free_buyer_id(), &filters).await?;
    let external_output = db
        .list_user_purchase_documents(external_completed_user_id(), &filters)
        .await?;

    // Check the purchase and nested credit-note JSON contracts
    assert_eq!(output.total, 1);
    assert_eq!(output.purchases.len(), 1);
    let purchase = &output.purchases[0];
    assert_eq!(purchase.amount_minor, 2500);
    assert_eq!(purchase.event_purchase_id, document_purchase_id());
    assert!(!purchase.externally_managed);
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

    // Check externally managed purchases omit provider invoice routing
    assert_eq!(external_output.total, 1);
    assert_eq!(external_output.purchases.len(), 1);
    let external_purchase = &external_output.purchases[0];
    assert_eq!(external_purchase.amount_minor, 5000);
    assert_eq!(
        external_purchase.event_purchase_id,
        external_completed_purchase_id()
    );
    assert!(external_purchase.externally_managed);
    assert!(external_purchase.provider_invoice_id.is_none());
    assert!(external_purchase.seller_display_name.is_none());
    assert!(external_purchase.credit_notes.is_empty());

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
