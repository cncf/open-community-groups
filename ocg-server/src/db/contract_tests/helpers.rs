//! Shared fixtures, identifiers and connection helpers for the contract tests.

use std::{env, time::Duration};

use anyhow::{Context, Result};
use chrono::{DateTime, NaiveDate};
use deadpool_postgres::{Config as DeadpoolDbConfig, Pool, Runtime};
use tokio_postgres::NoTls;
use uuid::Uuid;

use crate::{
    db::PgDB,
    templates::dashboard::group::events::Event as EventUpdate,
    types::{
        badges::{BadgeSnapshot, BadgeSnapshotIssuer, UserBadge},
        payments::{EventTicketType, EventTicketTypeAvailability},
    },
};

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
/// Buyer fixture used to prepare a new external checkout hold.
const EXTERNAL_CHECKOUT_BUYER_ID: &str = "00000000-0000-0000-0000-00000000c12a";
/// Pending external purchase dedicated to the completion mutation contract.
const EXTERNAL_COMPLETE_PURCHASE_ID: &str = "00000000-0000-0000-0000-00000000c133";
/// Buyer fixture dedicated to the external completion mutation contract.
const EXTERNAL_COMPLETE_USER_ID: &str = "00000000-0000-0000-0000-00000000c132";
/// Completed externally managed purchase used by document and attendee contracts.
const EXTERNAL_COMPLETED_PURCHASE_ID: &str = "00000000-0000-0000-0000-00000000c12f";
/// Buyer fixture with a completed externally managed purchase.
const EXTERNAL_COMPLETED_USER_ID: &str = "00000000-0000-0000-0000-00000000c128";
/// Event fixture dedicated to external-payments contracts.
const EXTERNAL_EVENT_ID: &str = "00000000-0000-0000-0000-00000000c12b";
const EXTERNAL_LOOKUP_ID: &str = "00000000-0000-0000-0000-00000000c046";
/// Pending external purchase awaiting organizer confirmation.
const EXTERNAL_PENDING_PURCHASE_ID: &str = "00000000-0000-0000-0000-00000000c12e";
/// Buyer fixture with a pending external purchase.
const EXTERNAL_PENDING_USER_ID: &str = "00000000-0000-0000-0000-00000000c127";
/// External purchase waiting for local refund approval.
const EXTERNAL_REFUND_PURCHASE_ID: &str = "00000000-0000-0000-0000-00000000c130";
/// Buyer fixture whose external refund request is ready for approval.
const EXTERNAL_REFUND_USER_ID: &str = "00000000-0000-0000-0000-00000000c129";
/// Ticket fixture used by the external-payments event.
const EXTERNAL_TICKET_TYPE_ID: &str = "00000000-0000-0000-0000-00000000c12c";
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
pub(super) fn activation_id() -> Uuid {
    parse_uuid(ACTIVATION_ID)
}

/// Returns the active user badge identifier used by the contract fixture.
pub(super) fn active_user_badge_id() -> Uuid {
    parse_uuid(ACTIVE_USER_BADGE_ID)
}

/// Checks the complete paid ticket type JSON contract.
pub(super) fn assert_contract_paid_ticket_type(ticket_type: &EventTicketType) {
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
        parse_uuid("00000000-0000-0000-0000-00000000c082")
    );
    assert_eq!(ticket_type.price_windows[0].ends_at, None);
    assert_eq!(ticket_type.price_windows[0].starts_at, None);
    assert_eq!(ticket_type.remaining_seats, Some(98));
    assert_eq!(ticket_type.seats_total, Some(100));
    assert!(!ticket_type.sold_out);
}

/// Returns the attendee identifier used by the contract fixture.
pub(super) fn attendee_id() -> Uuid {
    parse_uuid(ATTENDEE_ID)
}

/// Returns the automatically ended meeting identifier used by the contract fixture.
pub(super) fn auto_end_meeting_id() -> Uuid {
    parse_uuid(AUTO_END_MEETING_ID)
}

/// Returns the badge artwork identifier used by the contract fixture.
pub(super) fn badge_artwork_id() -> Uuid {
    parse_uuid(BADGE_ARTWORK_ID)
}

/// Returns the badge award job identifier used by the contract fixture.
pub(super) fn badge_award_job_id() -> Uuid {
    parse_uuid(BADGE_AWARD_JOB_ID)
}

/// Returns the badge identifier used by the contract fixture.
pub(super) fn badge_id() -> Uuid {
    parse_uuid(BADGE_ID)
}

/// Returns the badge status list identifier used by the contract fixture.
pub(super) fn badge_status_list_id() -> Uuid {
    parse_uuid(BADGE_STATUS_LIST_ID)
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

/// Returns the pending application-fee adjustment used by worker contracts.
pub(super) fn document_adjustment_id() -> Uuid {
    parse_uuid(DOCUMENT_ADJUSTMENT_ID)
}

/// Returns the credit note used by worker and attendee document contracts.
pub(super) fn document_credit_note_id() -> Uuid {
    parse_uuid(DOCUMENT_CREDIT_NOTE_ID)
}

/// Returns the provider-backed purchase used by attendee document contracts.
pub(super) fn document_purchase_id() -> Uuid {
    parse_uuid(DOCUMENT_PURCHASE_ID)
}

/// Returns the provider refund used by credit-note worker contracts.
pub(super) fn document_refund_id() -> Uuid {
    parse_uuid(DOCUMENT_REFUND_ID)
}

/// Returns the event cancellation target identifier used by the contract fixture.
pub(super) fn cancelee_id() -> Uuid {
    parse_uuid(CANCELEE_ID)
}

/// Returns the attendee fixture that races event cancellation.
pub(super) fn cancellation_lock_attendee_id() -> Uuid {
    parse_uuid(CANCELLATION_LOCK_ATTENDEE_ID)
}

/// Returns the event fixture used to verify cancellation locking.
pub(super) fn cancellation_lock_event_id() -> Uuid {
    parse_uuid(CANCELLATION_LOCK_EVENT_ID)
}

/// Returns the proposal used to verify submission share locking.
pub(super) fn cfs_add_lock_proposal_id() -> Uuid {
    parse_uuid(CFS_ADD_LOCK_PROPOSAL_ID)
}

/// Returns the proposal used to verify deletion lock ordering.
pub(super) fn cfs_delete_lock_proposal_id() -> Uuid {
    parse_uuid(CFS_DELETE_LOCK_PROPOSAL_ID)
}

/// Returns the session identifier used to verify CFS submission locking.
pub(super) fn cfs_lock_session_id() -> Uuid {
    parse_uuid(CFS_LOCK_SESSION_ID)
}

/// Returns the call-for-speakers submission identifier used by the contract fixture.
pub(super) fn cfs_submission_id() -> Uuid {
    parse_uuid(CFS_SUBMISSION_ID)
}

/// Returns the proposal used to verify update lock strength.
pub(super) fn cfs_update_lock_proposal_id() -> Uuid {
    parse_uuid(CFS_UPDATE_LOCK_PROPOSAL_ID)
}

/// Returns the attendee check-in code used by the contract fixture.
pub(super) fn check_in_code() -> Uuid {
    parse_uuid(CHECK_IN_CODE)
}

/// Returns the checkout buyer identifier used by the contract fixture.
pub(super) fn checkout_buyer_id() -> Uuid {
    parse_uuid(CHECKOUT_BUYER_ID)
}

/// Returns the claim group identifier used by the contract fixture.
pub(super) fn claim_group_id() -> Uuid {
    parse_uuid(CLAIM_GROUP_ID)
}

/// Returns the co-speaker proposal identifier used by the contract fixture.
pub(super) fn co_speaker_proposal_id() -> Uuid {
    parse_uuid(CO_SPEAKER_PROPOSAL_ID)
}

/// Returns the community identifier used by the contract fixture.
pub(super) fn community_id() -> Uuid {
    parse_uuid(COMMUNITY_ID)
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
pub(super) fn contract_tests_db() -> Result<PgDB> {
    Ok(PgDB::new(contract_tests_pool()?))
}

/// Creates an independent `PostgreSQL` connection pool for concurrency tests.
pub(super) fn contract_tests_pool() -> Result<Pool> {
    Ok(contract_tests_config()?.create_pool(Some(Runtime::Tokio1), NoTls)?)
}

/// Returns an environment value or its contract-test default.
pub(super) fn env_or_default(name: &str, default: &str) -> String {
    env::var(name).unwrap_or_else(|_| default.to_string())
}

/// Returns the event category identifier used by the contract fixture.
pub(super) fn event_category_id() -> Uuid {
    parse_uuid(EVENT_CATEGORY_ID)
}

/// Returns the event identifier used by the contract fixture.
pub(super) fn event_id() -> Uuid {
    parse_uuid(EVENT_ID)
}

/// Returns the buyer used to prepare a new external checkout hold.
pub(super) fn external_checkout_buyer_id() -> Uuid {
    parse_uuid(EXTERNAL_CHECKOUT_BUYER_ID)
}

/// Returns the pending external purchase dedicated to completion.
pub(super) fn external_complete_purchase_id() -> Uuid {
    parse_uuid(EXTERNAL_COMPLETE_PURCHASE_ID)
}

/// Returns the buyer dedicated to the external completion contract.
pub(super) fn external_complete_user_id() -> Uuid {
    parse_uuid(EXTERNAL_COMPLETE_USER_ID)
}

/// Returns the completed externally managed purchase identifier.
pub(super) fn external_completed_purchase_id() -> Uuid {
    parse_uuid(EXTERNAL_COMPLETED_PURCHASE_ID)
}

/// Returns the buyer with a completed externally managed purchase.
pub(super) fn external_completed_user_id() -> Uuid {
    parse_uuid(EXTERNAL_COMPLETED_USER_ID)
}

/// Returns the event dedicated to external-payments contracts.
pub(super) fn external_event_id() -> Uuid {
    parse_uuid(EXTERNAL_EVENT_ID)
}

/// Returns the external identity lookup identifier used by the contract fixture.
pub(super) fn external_lookup_id() -> Uuid {
    parse_uuid(EXTERNAL_LOOKUP_ID)
}

/// Returns the pending external purchase awaiting organizer confirmation.
pub(super) fn external_pending_purchase_id() -> Uuid {
    parse_uuid(EXTERNAL_PENDING_PURCHASE_ID)
}

/// Returns the buyer with a pending external purchase.
pub(super) fn external_pending_user_id() -> Uuid {
    parse_uuid(EXTERNAL_PENDING_USER_ID)
}

/// Returns the external purchase waiting for local refund approval.
pub(super) fn external_refund_purchase_id() -> Uuid {
    parse_uuid(EXTERNAL_REFUND_PURCHASE_ID)
}

/// Returns the buyer whose external refund request is ready for approval.
pub(super) fn external_refund_user_id() -> Uuid {
    parse_uuid(EXTERNAL_REFUND_USER_ID)
}

/// Returns the ticket used by the external-payments event.
pub(super) fn external_ticket_type_id() -> Uuid {
    parse_uuid(EXTERNAL_TICKET_TYPE_ID)
}

/// Returns the external identity update identifier used by the contract fixture.
pub(super) fn external_update_id() -> Uuid {
    parse_uuid(EXTERNAL_UPDATE_ID)
}

/// Returns the exhausted application-fee recovery work identifier.
pub(super) fn financial_recovery_adjustment_id() -> Uuid {
    parse_uuid(FINANCIAL_RECOVERY_ADJUSTMENT_ID)
}

/// Returns the exhausted credit-note recovery work identifier.
pub(super) fn financial_recovery_credit_note_id() -> Uuid {
    parse_uuid(FINANCIAL_RECOVERY_CREDIT_NOTE_ID)
}

/// Returns the free checkout buyer identifier used by the contract fixture.
pub(super) fn free_buyer_id() -> Uuid {
    parse_uuid(FREE_BUYER_ID)
}

/// Returns the free purchase identifier used by the contract fixture.
pub(super) fn free_purchase_id() -> Uuid {
    parse_uuid(FREE_PURCHASE_ID)
}

/// Returns the group identifier used by the contract fixture.
pub(super) fn group_id() -> Uuid {
    parse_uuid(GROUP_ID)
}

/// Returns an event update used by group-level lock contract tests.
pub(super) fn group_lock_event_update(name: &str, day: u32) -> EventUpdate {
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
pub(super) fn group_lock_first_event_id() -> Uuid {
    parse_uuid(GROUP_LOCK_FIRST_EVENT_ID)
}

/// Returns the second event used to verify group-level mutation locks.
pub(super) fn group_lock_second_event_id() -> Uuid {
    parse_uuid(GROUP_LOCK_SECOND_EVENT_ID)
}

/// Returns the group sponsor identifier used by the contract fixture.
pub(super) fn group_sponsor_id() -> Uuid {
    parse_uuid(GROUP_SPONSOR_ID)
}

/// Returns the invitation offer identifier used by the contract fixture.
pub(super) fn invitation_offer_id() -> Uuid {
    parse_uuid(INVITATION_OFFER_ID)
}

/// Returns the invitation ticket type identifier used by the contract fixture.
pub(super) fn invitation_ticket_type_id() -> Uuid {
    parse_uuid(INVITATION_TICKET_TYPE_ID)
}

/// Returns the invited event identifier used by the contract fixture.
pub(super) fn invite_event_id() -> Uuid {
    parse_uuid(INVITE_EVENT_ID)
}

/// Returns the invitee identifier used by the contract fixture.
pub(super) fn invitee_id() -> Uuid {
    parse_uuid(INVITEE_ID)
}

/// Returns the departing attendee identifier used by the contract fixture.
pub(super) fn leaver_id() -> Uuid {
    parse_uuid(LEAVER_ID)
}

/// Returns the mutation event identifier used by the contract fixture.
pub(super) fn mutation_event_id() -> Uuid {
    parse_uuid(MUTATION_EVENT_ID)
}

/// Returns the mutation offer identifier used by the contract fixture.
pub(super) fn mutation_offer_id() -> Uuid {
    parse_uuid(MUTATION_OFFER_ID)
}

/// Returns the notification identifier used by the contract fixture.
pub(super) fn notification_id() -> Uuid {
    parse_uuid("00000000-0000-0000-0000-00000000c0f1")
}

/// Returns the declined offer event identifier used by the contract fixture.
pub(super) fn offer_decline_event_id() -> Uuid {
    parse_uuid(OFFER_DECLINE_EVENT_ID)
}

/// Returns the declined offer identifier used by the contract fixture.
pub(super) fn offer_decline_offer_id() -> Uuid {
    parse_uuid(OFFER_DECLINE_OFFER_ID)
}

/// Returns the offer decliner identifier used by the contract fixture.
pub(super) fn offer_decliner_id() -> Uuid {
    parse_uuid(OFFER_DECLINER_ID)
}

/// Returns the organizer identifier used by the contract fixture.
pub(super) fn organizer_id() -> Uuid {
    parse_uuid(ORGANIZER_ID)
}

/// Returns the purchase used by paid attendance cancellation contracts.
pub(super) fn paid_cancellation_purchase_id() -> Uuid {
    parse_uuid(PAID_CANCELLATION_PURCHASE_ID)
}

/// Returns the attendee used by paid attendance cancellation contracts.
pub(super) fn paid_cancellation_user_id() -> Uuid {
    parse_uuid(PAID_CANCELLATION_USER_ID)
}

/// Returns the paid ticket price window identifier used by the contract fixture.
pub(super) fn paid_ticket_price_window_id() -> Uuid {
    parse_uuid(PAID_TICKET_PRICE_WINDOW_ID)
}

/// Returns the paid ticket type identifier used by the contract fixture.
pub(super) fn paid_ticket_type_id() -> Uuid {
    parse_uuid(PAID_TICKET_TYPE_ID)
}

/// Parses a UUID stored by the contract fixture.
pub(super) fn parse_uuid(value: &str) -> Uuid {
    Uuid::parse_str(value).expect("contract fixture UUID should be valid")
}

/// Returns the past event identifier used by the contract fixture.
pub(super) fn past_event_id() -> Uuid {
    parse_uuid(PAST_EVENT_ID)
}

/// Returns the pre-registered attendee identifier used by the contract fixture.
pub(super) fn pre_registered_id() -> Uuid {
    parse_uuid(PRE_REGISTERED_ID)
}

/// Returns the award fixture dedicated to the identity rebind contract.
pub(super) fn rebind_user_badge_id() -> Uuid {
    parse_uuid(REBIND_USER_BADGE_ID)
}

/// Returns the reconciliation buyer identifier used by the contract fixture.
pub(super) fn reconcile_buyer_id() -> Uuid {
    parse_uuid(RECONCILE_BUYER_ID)
}

/// Returns the due reconciliation event identifier used by the contract fixture.
pub(super) fn reconcile_due_event_id() -> Uuid {
    parse_uuid(RECONCILE_DUE_EVENT_ID)
}

/// Returns the user whose linked offer is hidden during refund processing.
pub(super) fn refund_offer_user_id() -> Uuid {
    parse_uuid(REFUND_OFFER_USER_ID)
}

/// Returns the purchase fixture ready for local refund finalization.
pub(super) fn refund_approve_purchase_id() -> Uuid {
    parse_uuid(REFUND_APPROVE_PURCHASE_ID)
}

/// Returns the purchase fixture ready to begin refund processing.
pub(super) fn refund_begin_purchase_id() -> Uuid {
    parse_uuid(REFUND_BEGIN_PURCHASE_ID)
}

/// Returns the paid event identifier containing the refund fixtures.
pub(super) fn refund_event_id() -> Uuid {
    parse_uuid(REFUND_EVENT_ID)
}

/// Returns the purchase identifier used by the refund lifecycle fixture.
pub(super) fn refund_lifecycle_purchase_id() -> Uuid {
    parse_uuid(REFUND_LIFECYCLE_PURCHASE_ID)
}

/// Returns the purchase identifier for the refund recovery fixture.
pub(super) fn refund_recovery_purchase_id() -> Uuid {
    parse_uuid(REFUND_RECOVERY_PURCHASE_ID)
}

/// Returns the durable refund identifier for the recovery fixture.
pub(super) fn refund_recovery_refund_id() -> Uuid {
    parse_uuid(REFUND_RECOVERY_REFUND_ID)
}

/// Returns the refund rejection buyer identifier used by the contract fixture.
pub(super) fn refund_reject_buyer_id() -> Uuid {
    parse_uuid(REFUND_REJECT_BUYER_ID)
}

/// Returns the purchase fixture ready for refund rejection.
pub(super) fn refund_reject_purchase_id() -> Uuid {
    parse_uuid(REFUND_REJECT_PURCHASE_ID)
}

/// Returns the buyer whose rejected refund is visible on attendee surfaces.
pub(super) fn refund_rejected_buyer_id() -> Uuid {
    parse_uuid(REFUND_REJECTED_BUYER_ID)
}

/// Returns the rejected requester ignored after approval is disabled.
pub(super) fn rejected_request_user_id() -> Uuid {
    parse_uuid(REJECTED_REQUEST_USER_ID)
}

/// Returns the invitation request event identifier used by the contract fixture.
pub(super) fn request_event_id() -> Uuid {
    parse_uuid(REQUEST_EVENT_ID)
}

/// Returns the requester identifier used by the contract fixture.
pub(super) fn requester_id() -> Uuid {
    parse_uuid(REQUESTER_ID)
}

/// Returns the revoked user badge identifier used by the contract fixture.
pub(super) fn revoked_user_badge_id() -> Uuid {
    parse_uuid(REVOKED_USER_BADGE_ID)
}

/// Returns the session proposal identifier used by the contract fixture.
pub(super) fn session_proposal_id() -> Uuid {
    parse_uuid(SESSION_PROPOSAL_ID)
}

/// Returns the site identifier used by the contract fixture.
pub(super) fn site_id() -> Uuid {
    parse_uuid(SITE_ID)
}

/// Returns the canceled-offer user used by the status contract.
pub(super) fn status_canceled_user_id() -> Uuid {
    parse_uuid(STATUS_CANCELED_USER_ID)
}

/// Returns the declined-offer user used by the status contract.
pub(super) fn status_declined_user_id() -> Uuid {
    parse_uuid(STATUS_DECLINED_USER_ID)
}

/// Returns the event dedicated to enrollment status contracts.
pub(super) fn status_event_id() -> Uuid {
    parse_uuid(STATUS_EVENT_ID)
}

/// Returns the expired-offer user used by the status contract.
pub(super) fn status_expired_user_id() -> Uuid {
    parse_uuid(STATUS_EXPIRED_USER_ID)
}

/// Returns the pending-purchase user used by the status contract.
pub(super) fn status_pending_payment_user_id() -> Uuid {
    parse_uuid(STATUS_PENDING_PAYMENT_USER_ID)
}

/// Returns the ticket used by the pending payment contract.
pub(super) fn status_ticket_type_id() -> Uuid {
    parse_uuid(STATUS_TICKET_TYPE_ID)
}

/// Returns the subgroup identifier used by the contract fixture.
pub(super) fn subgroup_id() -> Uuid {
    parse_uuid(SUBGROUP_ID)
}

/// Returns the purchase summary identifier used by the contract fixture.
pub(super) fn summary_purchase_id() -> Uuid {
    parse_uuid(SUMMARY_PURCHASE_ID)
}

/// Returns the synchronized event identifier used by the contract fixture.
pub(super) fn sync_event_id() -> Uuid {
    parse_uuid(SYNC_EVENT_ID)
}

/// Returns the paid event identifier used by the contract fixture.
pub(super) fn paid_event_id() -> Uuid {
    parse_uuid(TICKETED_EVENT_ID)
}

/// Returns the event dedicated to queue-offer invitation allocation.
pub(super) fn queue_invite_event_id() -> Uuid {
    parse_uuid(QUEUE_INVITE_EVENT_ID)
}

/// Returns the queued invitation target used by the allocation contract.
pub(super) fn queue_invitee_id() -> Uuid {
    parse_uuid(QUEUE_INVITEE_ID)
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
pub(super) fn waitlist_id() -> Uuid {
    parse_uuid(WAITLIST_ID)
}
