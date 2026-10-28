//! Shared fixtures, identifiers and connection helpers for the contract tests.

use std::{env, time::Duration};

use anyhow::{Context, Result};
use chrono::{DateTime, NaiveDate};
use deadpool_postgres::{Config as DeadpoolDbConfig, Pool, Runtime};
use tokio_postgres::{NoTls, error::SqlState, types::ToSql};
use uuid::{Uuid, uuid};

use crate::{
    db::{PgDB, PgExecutor, PgUnitOfWork, user_facing_message},
    types::{
        badges::{BadgeSnapshot, BadgeSnapshotIssuer, UserBadge},
        dashboard::group::events::EventInput,
        event::EventLabel,
        payments::{EventTicketType, EventTicketTypeAvailability},
    },
};

/// Number of attendees who answer the export growth survey.
pub(super) const SURVEY_EXPORT_RESPONDENTS: u8 = 12;

/// Returns the activation identifier used by the contract fixture.
pub(super) const fn activation_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c045")
}

/// Returns the pre-registered user activated by the email/password contract.
pub(super) const fn activation_password_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c048")
}

/// Returns the active user badge identifier used by the contract fixture.
pub(super) const fn active_user_badge_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0bd")
}

/// Returns the past paid event used by the event analytics contracts.
pub(super) const fn analytics_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f205")
}

/// Returns the group owning the event analytics fixture.
pub(super) const fn analytics_group_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f203")
}

/// Returns the select registration question of the event analytics fixture.
pub(super) const fn analytics_question_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f20b")
}

/// Returns the paid ticket type of the event analytics fixture.
pub(super) const fn analytics_ticket_type_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f208")
}

/// Checks the complete ticket type JSON contract shared by event projections.
pub(super) fn assert_contract_ticket_type(ticket_type: &EventTicketType) {
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
        invitation_ticket_price_window_id()
    );
    assert_eq!(ticket_type.price_windows[0].ends_at, None);
    assert_eq!(ticket_type.price_windows[0].starts_at, None);
    assert_eq!(ticket_type.remaining_seats, Some(98));
    assert_eq!(ticket_type.seats_total, Some(100));
    assert!(!ticket_type.sold_out);
}

/// Asserts an error is a user-facing `OCG01` database rejection with the
/// given message, classified through the production [`user_facing_message`].
#[track_caller]
pub(super) fn assert_ocg01(err: &anyhow::Error, message: &str) {
    assert_eq!(
        user_facing_message(err).as_deref(),
        Some(message),
        "expected an OCG01 rejection, got {err:#}"
    );
}

/// Asserts a raw database error is a user-facing `OCG01` rejection with the
/// given message.
#[track_caller]
pub(super) fn assert_pg_ocg01(err: tokio_postgres::Error, message: &str) {
    assert_ocg01(&err.into(), message);
}

/// Returns the attendee identifier used by the contract fixture.
pub(super) const fn attendee_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c042")
}

/// Returns the automatically ended meeting identifier used by the contract fixture.
pub(super) const fn auto_end_meeting_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0a3")
}

/// Returns the backend process ID of a raw contract-test connection.
pub(super) async fn backend_pid(client: &tokio_postgres::Client) -> Result<i32> {
    Ok(client.query_one("select pg_backend_pid()", &[]).await?.get(0))
}

/// Returns the badge artwork identifier used by the contract fixture.
pub(super) const fn badge_artwork_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0ba")
}

/// Returns the badge award job identifier used by the contract fixture.
pub(super) const fn badge_award_job_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0bf")
}

/// Returns the badge identifier used by the contract fixture.
pub(super) const fn badge_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0bb")
}

/// Returns the badge status list identifier used by the contract fixture.
pub(super) const fn badge_status_list_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0bc")
}

/// Returns the event cancellation target identifier used by the contract fixture.
pub(super) const fn cancelee_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0e9")
}

/// Returns the attendee fixture that races event cancellation.
pub(super) const fn cancellation_lock_attendee_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0ec")
}

/// Returns the event fixture used to verify cancellation locking.
pub(super) const fn cancellation_lock_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0d6")
}

/// Returns the proposal used to verify submission share locking.
pub(super) const fn cfs_add_lock_proposal_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c124")
}

/// Returns the proposal used to verify deletion lock ordering.
pub(super) const fn cfs_delete_lock_proposal_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c125")
}

/// Returns the session identifier used to verify CFS submission locking.
pub(super) const fn cfs_lock_session_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c123")
}

/// Returns the call-for-speakers submission identifier used by the contract fixture.
pub(super) const fn cfs_submission_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0c5")
}

/// Returns the proposal used to verify update lock strength.
pub(super) const fn cfs_update_lock_proposal_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c126")
}

/// Returns the attendee check-in code used by the contract fixture.
pub(super) const fn check_in_code() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c084")
}

/// Returns the checkout buyer identifier used by the contract fixture.
pub(super) const fn checkout_buyer_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0e1")
}

/// Returns the claim group identifier used by the contract fixture.
pub(super) const fn claim_group_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0a0")
}

/// Returns the co-speaker proposal identifier used by the contract fixture.
pub(super) const fn co_speaker_proposal_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0c2")
}

/// Returns the group admin notified about co-hosting lifecycle changes.
pub(super) const fn cohost_admin_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000d401")
}

/// Returns the group with an approved co-hosting of the matrix event.
pub(super) const fn cohost_approved_group_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000d022")
}

/// Returns the canceled event with an event-canceled co-hosting.
pub(super) const fn cohost_canceled_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000d202")
}

/// Returns the group that withdrew its co-hosting of the matrix event.
pub(super) const fn cohost_canceled_group_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000d023")
}

/// Returns the inactive community holding every co-host group fixture.
pub(super) const fn cohost_community_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000d101")
}

/// Returns the active cross-community group with an approved co-hosting.
pub(super) const fn cohost_cross_community_group_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000d121")
}

/// Returns the approved invitation of the cross-community co-host.
pub(super) const fn cohost_cross_community_invitation_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000d309")
}

/// Returns the deleted event with an event-deleted co-hosting.
pub(super) const fn cohost_deleted_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000d203")
}

/// Returns the group whose co-hosting ended with the event cancellation.
pub(super) const fn cohost_event_canceled_group_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000d024")
}

/// Returns the group whose co-hosting ended with the event deletion.
pub(super) const fn cohost_event_deleted_group_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000d025")
}

/// Returns the invitation closed by the event deletion.
pub(super) const fn cohost_event_deleted_invitation_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000d305")
}

/// Returns the group sorting after the low lock-order group.
pub(super) const fn cohost_lock_order_high_group_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000d02a")
}

/// Returns the group sorting before the high lock-order group.
pub(super) const fn cohost_lock_order_low_group_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000d029")
}

/// Returns the unpublished event holding one co-hosting per editable status.
pub(super) const fn cohost_matrix_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000d201")
}

/// Returns the group with a pending co-hosting invitation.
pub(super) const fn cohost_pending_group_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000d021")
}

/// Returns the pending invitation of the matrix event.
pub(super) const fn cohost_pending_invitation_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000d301")
}

/// Returns the unpublished event used to race publication against an invitation.
pub(super) const fn cohost_publish_race_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000d204")
}

/// Returns the event whose pending co-host is re-invited while an approval waits.
pub(super) const fn cohost_reinvite_race_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000d205")
}

/// Returns the pending invitation rotated by the re-invite race.
pub(super) const fn cohost_reinvite_race_invitation_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000d310")
}

/// Returns the inactive group re-invited to co-host the matrix event, which the
/// notification preferences fixture also mutes as an unavailable group.
pub(super) const fn cohost_reinvited_group_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000d028")
}

/// Returns the community identifier used by the contract fixture.
pub(crate) const fn community_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c001")
}

/// Returns the verified contact user who is admin of one group and viewer of another.
pub(super) const fn contact_admin_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e141")
}

/// Returns the contact group category holding the active and inactive groups.
pub(super) const fn contact_category_a_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e112")
}

/// Returns the contact group category holding the group without a region.
pub(super) const fn contact_category_b_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e113")
}

/// Returns the inactive community used by the community contact contracts.
pub(super) const fn contact_community_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e101")
}

/// Returns the active contact group with a region.
pub(super) const fn contact_group_a_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e121")
}

/// Returns the active contact group without a region whose only seat is a viewer.
pub(super) const fn contact_group_b_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e122")
}

/// Returns the inactive contact group excluded from contact.
pub(super) const fn contact_inactive_group_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e123")
}

/// Returns the verified contact user who is events manager of one active group.
pub(super) const fn contact_manager_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e142")
}

/// Returns the region of the contact community.
pub(super) const fn contact_region_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e111")
}

/// Builds an active user badge from the supplied contract snapshot and identity fields.
pub(super) fn contract_active_user_badge(
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
pub(super) fn contract_badge_snapshot() -> BadgeSnapshot {
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

/// Builds a future virtual test event input on the given August 2099 day.
pub(super) fn contract_event_input(name: &str, day: u32) -> EventInput {
    let starts_at = NaiveDate::from_ymd_opt(2099, 8, day)
        .expect("date should be valid")
        .and_hms_opt(10, 0, 0)
        .expect("time should be valid");
    let ends_at = NaiveDate::from_ymd_opt(2099, 8, day)
        .expect("date should be valid")
        .and_hms_opt(11, 0, 0)
        .expect("time should be valid");

    EventInput {
        category_id: event_category_id(),
        description: "An event used by Rust database contract tests".to_string(),
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

/// Returns the label assigned to the contract session and submission.
pub(super) fn contract_event_label() -> EventLabel {
    EventLabel {
        color: "#DBEAFE".to_string(),
        event_label_id: event_label_id(),
        name: "track / backend".to_string(),
    }
}

/// Builds the shared `PostgreSQL` configuration for contract tests.
pub(super) fn contract_tests_config() -> Result<DeadpoolDbConfig> {
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
pub(crate) fn contract_tests_db() -> Result<PgDB> {
    Ok(PgDB::new(contract_tests_pool()?))
}

/// Creates an independent `PostgreSQL` connection pool for concurrency tests.
pub(crate) fn contract_tests_pool() -> Result<Pool> {
    Ok(contract_tests_config()?.create_pool(Some(Runtime::Tokio1), NoTls)?)
}

/// Begins a unit of work that rolls back when dropped.
pub(super) async fn contract_unit_of_work() -> Result<PgUnitOfWork> {
    let client = contract_tests_pool()?.get().await?;
    client.batch_execute("begin").await?;

    Ok(PgUnitOfWork {
        client: Some(client),
    })
}

/// Returns the pending application-fee adjustment used by worker contracts.
pub(super) const fn document_adjustment_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c11d")
}

/// Returns the pending application-fee adjustment job used by worker contracts.
pub(super) const fn document_adjustment_job_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c134")
}

/// Returns the credit note used by worker and attendee document contracts.
pub(super) const fn document_credit_note_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c11e")
}

/// Returns the credit-note job used by worker and attendee document contracts.
pub(super) const fn document_credit_note_job_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c135")
}

/// Returns the provider-backed purchase used by attendee document contracts.
pub(super) const fn document_purchase_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c11b")
}

/// Returns the provider refund used by credit-note worker contracts.
pub(super) const fn document_refund_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c11c")
}

/// Returns the provider refund job used by credit-note worker contracts.
pub(super) const fn document_refund_job_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c136")
}

/// Returns the user who attends the enrollment race event.
pub(super) const fn enrollment_race_attendee_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f370")
}

/// Returns the user who declines the enrollment race offer.
pub(super) const fn enrollment_race_decliner_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f371")
}

/// Returns the free one-seat event used by the enrollment lock order race.
pub(super) const fn enrollment_race_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f372")
}

/// Returns the pending approval offer declined by the enrollment race.
pub(super) const fn enrollment_race_offer_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f375")
}

/// Returns an environment value or its contract-test default.
fn env_or_default(name: &str, default: &str) -> String {
    env::var(name).unwrap_or_else(|_| default.to_string())
}

/// Returns the event category identifier used by the contract fixture.
pub(super) const fn event_category_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c013")
}

/// Returns the event identifier used by the contract fixture.
pub(super) const fn event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c031")
}

/// Returns the label assigned to the contract session and submission.
pub(super) const fn event_label_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0c8")
}

/// Returns the buyer used to prepare a new external checkout hold.
pub(super) const fn external_checkout_buyer_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c12a")
}

/// Returns the pending external purchase dedicated to completion.
pub(super) const fn external_complete_purchase_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c133")
}

/// Returns the buyer dedicated to the external completion contract.
pub(super) const fn external_complete_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c132")
}

/// Returns the completed externally managed purchase identifier.
pub(super) const fn external_completed_purchase_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c12f")
}

/// Returns the buyer with a completed externally managed purchase.
pub(super) const fn external_completed_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c128")
}

/// Returns the event dedicated to external-payments contracts.
pub(super) const fn external_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c12b")
}

/// Returns the external identity lookup identifier used by the contract fixture.
pub(super) const fn external_lookup_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c046")
}

/// Returns the pending external purchase awaiting organizer confirmation.
pub(super) const fn external_pending_purchase_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c12e")
}

/// Returns the buyer with a pending external purchase.
pub(super) const fn external_pending_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c127")
}

/// Returns the external purchase waiting for local refund approval.
pub(super) const fn external_refund_purchase_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c130")
}

/// Returns the buyer whose external refund request is ready for approval.
pub(super) const fn external_refund_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c129")
}

/// Returns the ticket used by the external-payments event.
pub(super) const fn external_ticket_type_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c12c")
}

/// Returns the external identity update identifier used by the contract fixture.
pub(super) const fn external_update_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c047")
}

/// Returns the exhausted application-fee recovery job identifier.
pub(super) const fn financial_recovery_adjustment_job_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c137")
}

/// Returns the exhausted credit-note recovery job identifier.
pub(super) const fn financial_recovery_credit_note_job_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c138")
}

/// Returns the free checkout buyer identifier used by the contract fixture.
pub(super) const fn free_buyer_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0e4")
}

/// Returns the free purchase identifier used by the contract fixture.
pub(super) const fn free_purchase_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0f3")
}

/// Returns the group identifier used by the contract fixture.
pub(crate) const fn group_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c021")
}

/// Returns the first event used to verify group-level mutation locks.
pub(super) const fn group_lock_first_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c121")
}

/// Returns the second event used to verify group-level mutation locks.
pub(super) const fn group_lock_second_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c122")
}

/// Returns the group sponsor identifier used by the contract fixture.
pub(super) const fn group_sponsor_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c061")
}

/// Returns the group team member with the admin role in the read and write groups.
pub(crate) const fn inbox_admin_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e021")
}

/// Returns the closed read conversation without event.
pub(super) const fn inbox_closed_conversation_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e042")
}

/// Returns the published event owned by the co-host group.
pub(super) const fn inbox_cohost_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e033")
}

/// Returns the inactive community holding every inbox fixture.
pub(crate) const fn inbox_community_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e001")
}

/// Returns the read conversation whose user account was deleted.
pub(super) const fn inbox_deleted_user_conversation_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e043")
}

/// Returns the group team member with the events-manager role in the read and write groups.
pub(crate) const fn inbox_events_manager_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e022")
}

/// Returns the open conversation of the follow-up limit user.
pub(super) const fn inbox_follow_up_conversation_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e045")
}

/// Returns the user with nine follow-ups sent today.
pub(super) const fn inbox_follow_up_limit_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e028")
}

/// Returns the user starting a conversation through the manager.
pub(crate) const fn inbox_manager_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e02a")
}

/// Returns the open read conversation with three messages.
pub(super) const fn inbox_open_conversation_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e041")
}

/// Returns the opted-out inbox admin used by the contract fixture.
pub(crate) const fn inbox_opt_out_admin_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e02c")
}

/// Returns the event whose inbox recipients opted out of group-inbox emails.
pub(crate) const fn inbox_opt_out_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e034")
}

/// Returns the opted-out inbox events manager used by the contract fixture.
pub(crate) const fn inbox_opt_out_events_manager_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e02d")
}

/// Returns the group whose inbox recipients opted out of group-inbox emails.
pub(crate) const fn inbox_opt_out_group_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e014")
}

/// Returns the user who writes to the opted-out inbox fixture.
pub(crate) const fn inbox_opt_out_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e02e")
}

/// Returns the open conversation raced by a reply and a close.
pub(super) const fn inbox_race_conversation_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e044")
}

/// Returns the user owning the reply-close race conversation.
pub(super) const fn inbox_race_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e029")
}

/// Returns the published event owned by the read group and co-hosted by the co-host group.
pub(super) const fn inbox_read_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e031")
}

/// Returns the group whose conversations are only read by the contracts.
pub(super) const fn inbox_read_group_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e011")
}

/// Returns the read conversation marked as spam by the read group.
pub(super) const fn inbox_spam_conversation_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e048")
}

/// Returns the open conversation of the spam user marked and unmarked by the contracts.
pub(super) const fn inbox_spam_round_trip_conversation_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e049")
}

/// Returns the user whose read group conversation was marked as spam.
pub(super) const fn inbox_spam_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e02b")
}

/// Returns the user with two conversations started today.
pub(super) const fn inbox_start_limit_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e026")
}

/// Returns the user starting two conversations with the same group at once.
pub(super) const fn inbox_start_race_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e027")
}

/// Returns the user owning the open and closed read conversations.
pub(super) const fn inbox_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e024")
}

/// Returns the group team member with the viewer role in the read and write groups.
pub(super) const fn inbox_viewer_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e023")
}

/// Returns the published event owned by the write group.
pub(crate) const fn inbox_write_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e032")
}

/// Returns the group receiving conversations written by the contracts.
pub(super) const fn inbox_write_group_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000e012")
}

/// Returns the invitation offer identifier used by the contract fixture.
pub(super) const fn invitation_offer_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c083")
}

/// Returns the price window of the contract event general admission ticket.
pub(super) const fn invitation_ticket_price_window_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c082")
}

/// Returns the invitation ticket type identifier used by the contract fixture.
pub(super) const fn invitation_ticket_type_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c081")
}

/// Returns the invited event identifier used by the contract fixture.
pub(super) const fn invite_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0d8")
}

/// Returns the invitee identifier used by the contract fixture.
pub(super) const fn invitee_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0ed")
}

/// Returns the departing attendee identifier used by the contract fixture.
pub(super) const fn leaver_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0e8")
}

/// Returns the attendee canceled by the enrollment manager lifecycle contract.
pub(crate) const fn lifecycle_cancelee_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c1f0")
}

/// Returns the attendee whose manager cancellation is rolled back by the lifecycle contract.
pub(crate) const fn lifecycle_rollback_cancelee_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c1f1")
}

/// Returns the mutation event identifier used by the contract fixture.
pub(crate) const fn mutation_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0d5")
}

/// Returns the mutation offer identifier used by the contract fixture.
pub(super) const fn mutation_offer_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0d7")
}

/// Returns the user used by notification mute concurrency contracts.
pub(super) const fn notification_concurrency_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f004")
}

/// Returns the recipient that accepts notification filtering contracts.
pub(super) const fn notification_eligible_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f002")
}

/// Returns the notification identifier used by the contract fixture.
///
/// The purchase summary fixture reuses this UUID in `event_purchase`, a
/// different table.
pub(super) const fn notification_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0f1")
}

/// Returns the user with seeded notification preferences.
pub(super) const fn notification_preferences_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f001")
}

/// Returns the user used by notification unmute concurrency contracts.
pub(super) const fn notification_unmute_concurrency_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f005")
}

/// Returns the user dedicated to notification preference update contracts.
pub(super) const fn notification_update_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f003")
}

/// Returns the declined offer event identifier used by the contract fixture.
pub(super) const fn offer_decline_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0dc")
}

/// Returns the declined offer identifier used by the contract fixture.
pub(super) const fn offer_decline_offer_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0dd")
}

/// Returns the offer decliner identifier used by the contract fixture.
pub(super) const fn offer_decliner_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0f0")
}

/// Returns the organizer identifier used by the contract fixture.
pub(crate) const fn organizer_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c041")
}

/// Returns the purchase used by paid attendance cancellation contracts.
pub(super) const fn paid_cancellation_purchase_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c118")
}

/// Returns the attendee used by paid attendance cancellation contracts.
pub(super) const fn paid_cancellation_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c117")
}

/// Returns the paid event that also holds the refund fixtures.
pub(super) const fn paid_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0d0")
}

/// Returns the paid ticket price window identifier used by the contract fixture.
pub(super) const fn paid_ticket_price_window_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0d2")
}

/// Returns the paid ticket type identifier used by the contract fixture.
pub(super) const fn paid_ticket_type_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0d1")
}

/// Returns the past event identifier used by the contract fixture.
pub(super) const fn past_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c032")
}

/// Returns the admin of the group payment lock order fixture group.
pub(super) const fn payment_lock_admin_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f408")
}

/// Returns the unpublished paid event of the group payment lock order fixture.
pub(super) const fn payment_lock_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f405")
}

/// Returns the external-payments group of the group payment lock order fixture.
pub(super) const fn payment_lock_group_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f404")
}

/// Returns the pre-registered attendee identifier used by the contract fixture.
pub(super) const fn pre_registered_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c044")
}

/// Runs a lock probe in its own transaction with a 250 ms lock timeout, rolls
/// it back, and returns the SQLSTATE the probe failed with, if any.
pub(super) async fn probe_lock(
    client: &tokio_postgres::Client,
    sql: &str,
    params: &[&(dyn ToSql + Sync)],
) -> Result<Option<SqlState>> {
    client
        .batch_execute("begin; set local lock_timeout = '250ms'")
        .await?;
    let result = client.query_one(sql, params).await;
    client.batch_execute("rollback").await?;

    Ok(result.err().and_then(|err| err.code().cloned()))
}

/// Returns the event dedicated to queue-offer invitation allocation.
pub(super) const fn queue_invite_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c105")
}

/// Returns the queued invitation target used by the allocation contract.
pub(super) const fn queue_invitee_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c103")
}

/// Returns the award fixture dedicated to the identity rebind contract.
pub(super) const fn rebind_user_badge_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0b9")
}

/// Returns the reconciliation buyer identifier used by the contract fixture.
pub(super) const fn reconcile_buyer_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0e3")
}

/// Returns the due reconciliation event identifier used by the contract fixture.
pub(super) const fn reconcile_due_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0de")
}

/// Returns the payment job fixture ready for local refund finalization.
pub(super) const fn refund_approve_job_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c139")
}

/// Returns the purchase fixture ready for local refund finalization.
pub(super) const fn refund_approve_purchase_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0f6")
}

/// Returns the purchase fixture ready to begin refund processing.
pub(super) const fn refund_begin_purchase_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0f4")
}

/// Returns the purchase identifier used by the refund lifecycle fixture.
pub(super) const fn refund_lifecycle_purchase_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0fb")
}

/// Returns the user whose linked offer is hidden during refund processing.
pub(super) const fn refund_offer_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c101")
}

/// Returns the payment job identifier for the refund recovery fixture.
pub(super) const fn refund_recovery_job_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c13a")
}

/// Returns the purchase identifier for the refund recovery fixture.
pub(super) const fn refund_recovery_purchase_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0fd")
}

/// Returns the durable refund identifier for the recovery fixture.
pub(super) const fn refund_recovery_refund_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0fe")
}

/// Returns the refund rejection buyer identifier used by the contract fixture.
pub(super) const fn refund_reject_buyer_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0e7")
}

/// Returns the purchase fixture ready for refund rejection.
pub(super) const fn refund_reject_purchase_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0f8")
}

/// Returns the buyer whose rejected refund is visible on attendee surfaces.
pub(super) const fn refund_rejected_buyer_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c114")
}

/// Returns the single-select meal preference question of the contract event.
pub(super) const fn registration_question_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c071")
}

/// Returns the vegetarian option of the contract event meal preference question.
pub(super) const fn registration_question_option_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c072")
}

/// Returns the rejected requester ignored after approval is disabled.
pub(super) const fn rejected_request_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c102")
}

/// Returns the invitation request event identifier used by the contract fixture.
pub(super) const fn request_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0d9")
}

/// Returns the requester identifier used by the contract fixture.
pub(super) const fn requester_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0ee")
}

/// Returns the revoked user badge identifier used by the contract fixture.
pub(super) const fn revoked_user_badge_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0be")
}

/// Returns the labeled session identifier used by the contract fixture.
pub(super) const fn session_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c051")
}

/// Returns the session proposal identifier used by the contract fixture.
pub(super) const fn session_proposal_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0c1")
}

/// Returns the site identifier used by the contract fixture.
pub(super) const fn site_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0b1")
}

/// Returns the community used by the stats cache contract.
pub(super) const fn stats_cache_community_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f101")
}

/// Returns the group used by the stats cache contract.
pub(super) const fn stats_cache_group_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f103")
}

/// Returns the user added by the stats cache contract.
pub(super) const fn stats_cache_joiner_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f105")
}

/// Returns the canceled-offer user used by the status contract.
pub(super) const fn status_canceled_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c10e")
}

/// Returns the declined-offer user used by the status contract.
pub(super) const fn status_declined_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c10f")
}

/// Returns the event dedicated to enrollment status contracts.
pub(super) const fn status_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c109")
}

/// Returns the expired-offer user used by the status contract.
pub(super) const fn status_expired_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c10d")
}

/// Returns the pending-purchase user used by the status contract.
pub(super) const fn status_pending_payment_user_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c10c")
}

/// Returns the ticket used by the pending payment contract.
pub(super) const fn status_ticket_type_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c10a")
}

/// Returns the subgroup identifier used by the contract fixture.
pub(super) const fn subgroup_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c022")
}

/// Returns the purchase summary identifier used by the contract fixture.
///
/// The notification fixture reuses this UUID in `notification`, a different
/// table.
pub(super) const fn summary_purchase_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0f1")
}

/// Returns the open anonymous survey of the survey event.
pub(super) const fn survey_anonymous_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f306")
}

/// Returns the survey closed while an attendee submits answers.
pub(super) const fn survey_close_race_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f323")
}

/// Returns the survey deleted while a submission holds its lock.
pub(super) const fn survey_delete_after_submission_race_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f327")
}

/// Returns the survey deleted while an attendee submits answers.
pub(super) const fn survey_delete_race_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f324")
}

/// Returns the draft survey of the survey event.
pub(super) const fn survey_draft_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f307")
}

/// Returns the survey closed while the opening email job runs.
pub(super) const fn survey_email_close_race_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f344")
}

/// Returns the event whose survey opening emails reach its attendees.
pub(super) const fn survey_email_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f340")
}

/// Returns the survey waiting for its opening email.
pub(super) const fn survey_email_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f343")
}

/// Returns the survey whose event is rescheduled while the opening email job runs.
pub(super) const fn survey_email_reschedule_race_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f351")
}

/// Returns the event holding the identified, anonymous and draft surveys.
pub(super) const fn survey_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f301")
}

/// Returns the survey answered while it is exported.
pub(super) const fn survey_export_growth_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f325")
}

/// Returns the attendee numbered `n` (1 to 12) who answers the export growth
/// survey.
pub(super) fn survey_export_respondent_id(n: u8) -> Uuid {
    Uuid::from_u128(0xf37f + u128::from(n))
}

/// Returns the survey answered while its anonymity changes.
pub(super) const fn survey_first_response_race_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f321")
}

/// Returns the former attendee who answered the identified survey.
pub(super) const fn survey_former_attendee_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f317")
}

/// Returns the free-text question of the identified survey.
pub(super) const fn survey_free_text_question_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f308")
}

/// Returns the open identified survey of the survey event.
pub(super) const fn survey_identified_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f305")
}

/// Returns the upcoming event rescheduled while a survey is marked ready.
pub(super) const fn survey_mark_ready_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f360")
}

/// Returns the draft survey marked ready while its event is rescheduled.
pub(super) const fn survey_mark_ready_race_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f361")
}

/// Returns the survey event attendee who did not check in or answer.
pub(super) const fn survey_pending_respondent_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f304")
}

/// Returns the event holding the concurrency contract surveys.
pub(super) const fn survey_race_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f320")
}

/// Returns the free-text question of the concurrency contract surveys.
pub(super) const fn survey_race_question_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f330")
}

/// Returns the attendee answering the concurrency contract surveys.
pub(super) const fn survey_racer_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f316")
}

/// Returns the event rescheduled while the opening email job runs.
pub(super) const fn survey_reschedule_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f350")
}

/// Returns the attendee who answered both open surveys of the survey event.
pub(super) const fn survey_respondent_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f302")
}

/// Returns the changes that make the open surveys of the survey event
/// unreachable on the public site, each with a short description and the
/// identifier bound to its `$1` parameter.
pub(super) fn survey_scope_changes() -> [(&'static str, &'static str, Uuid); 6] {
    [
        (
            "canceled event",
            "update event set canceled = true where event_id = $1::uuid",
            survey_event_id(),
        ),
        (
            "deleted group",
            r#"update "group" set active = false, deleted = true where group_id = $1::uuid"#,
            subgroup_id(),
        ),
        (
            "draft surveys",
            "update event_survey set status = 'draft', closed_at = null, first_response_at = null, open_notification_processed_at = null, open_notification_recipients = null where event_id = $1::uuid",
            survey_event_id(),
        ),
        (
            "inactive community",
            "update community set active = false where community_id = $1::uuid",
            community_id(),
        ),
        (
            "inactive group",
            r#"update "group" set active = false where group_id = $1::uuid"#,
            subgroup_id(),
        ),
        (
            "unpublished event",
            "update event set published = false where event_id = $1::uuid",
            survey_event_id(),
        ),
    ]
}

/// Returns the second attendee who checked in and answered both open surveys.
pub(super) const fn survey_second_respondent_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f303")
}

/// Returns the single-select question of the identified survey.
pub(super) const fn survey_single_select_question_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f309")
}

/// Returns the survey reconfigured while an attendee submits answers.
pub(super) const fn survey_stale_race_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000f322")
}

/// Returns the synchronized event identifier used by the contract fixture.
pub(super) const fn sync_event_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c0a1")
}

/// Returns the unlabeled session identifier used by the contract fixture.
pub(super) const fn unlabeled_session_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c052")
}

/// Returns the backend process ID of a contract-test unit of work.
pub(super) async fn uow_backend_pid(uow: &PgUnitOfWork) -> Result<i32> {
    uow.fetch_scalar_one("select pg_backend_pid()", &[]).await
}

/// Waits until one contract-test backend is blocked by another.
pub(super) async fn wait_for_backend_blocker(
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
pub(super) const fn waitlist_id() -> Uuid {
    uuid!("00000000-0000-0000-0000-00000000c043")
}
