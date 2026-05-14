use std::{env, time::Duration};

use anyhow::{Context, Result};
use deadpool_postgres::{Config as DbConfig, Runtime};
use tokio_postgres::NoTls;
use uuid::Uuid;

use crate::{
    db::{PgDB, common::DBCommon, dashboard::group::DBDashboardGroup, event::DBEvent, meetings::DBMeetings},
    services::meetings::MeetingProvider,
    templates::dashboard::{
        audit::AuditLogFilters,
        group::{
            attendees::AttendeesFilters, events::EventsListFilters,
            invitation_requests::InvitationRequestsFilters, members::GroupMembersFilters,
            sponsors::GroupSponsorsFilters, team::GroupTeamFilters, waitlist::WaitlistFilters,
        },
    },
    types::{
        event::{EventAttendanceStatus, EventInvitationRequestStatus, EventKind},
        group::GroupRole,
        payments::PaymentProvider,
        search::{SearchEventsFilters, SearchGroupsFilters},
    },
};

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_claim_meeting_for_auto_end_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let candidate = db
        .claim_meeting_for_auto_end()
        .await?
        .expect("contract auto-end candidate should exist");

    assert_eq!(candidate.meeting_id, auto_end_meeting_id());
    assert_eq!(candidate.provider, MeetingProvider::Zoom);
    assert_eq!(candidate.provider_meeting_id, "contract-auto-end");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_claim_meeting_out_of_sync_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let meeting = db
        .claim_meeting_out_of_sync()
        .await?
        .expect("contract meeting sync candidate should exist");

    assert_eq!(meeting.duration, Some(Duration::from_hours(1)));
    assert_eq!(meeting.event_id, Some(sync_event_id()));
    assert_eq!(meeting.provider, MeetingProvider::Zoom);
    assert!(meeting.sync_claimed_at.is_some());
    assert!(meeting.sync_state_hash.is_some());
    assert_eq!(meeting.topic.as_deref(), Some("Contract Meeting Sync Event"));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_attendance_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let attendance = db
        .get_event_attendance(community_id(), event_id(), attendee_id())
        .await?;

    assert_eq!(attendance.status, EventAttendanceStatus::Attendee);
    assert!(attendance.is_checked_in);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_full_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let event = db.get_event_full(community_id(), group_id(), event_id()).await?;

    assert_eq!(event.event_id, event_id());
    assert_eq!(event.sessions.len(), 1);
    assert_eq!(event.sponsors.len(), 1);
    assert_eq!(
        event.hosts[0].github_url.as_deref(),
        Some("https://github.com/contract-organizer")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_summary_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let event = db.get_event_summary(community_id(), group_id(), event_id()).await?;

    assert_eq!(event.event_id, event_id());
    assert_eq!(event.kind, EventKind::Hybrid);
    assert_eq!(event.waitlist_count, 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_full_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let group = db.get_group_full(community_id(), group_id()).await?;

    assert_eq!(group.group_id, group_id());
    assert_eq!(group.organizers.len(), 1);
    assert_eq!(group.sponsors.len(), 1);
    assert_eq!(
        group.organizers[0].github_url.as_deref(),
        Some("https://github.com/contract-organizer")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_payment_recipient_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let payment_recipient = db
        .get_group_payment_recipient(community_id(), group_id())
        .await?
        .expect("contract group should have a payment recipient");

    assert_eq!(payment_recipient.provider, PaymentProvider::Stripe);
    assert_eq!(payment_recipient.recipient_id, "acct_contract_group");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_sponsor_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let sponsor = db.get_group_sponsor(group_id(), group_sponsor_id()).await?;

    assert_eq!(sponsor.group_sponsor_id, group_sponsor_id());
    assert_eq!(sponsor.name, "Contract Sponsor");
    assert!(sponsor.featured);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_stats_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let stats = db.get_group_stats(community_id(), group_id()).await?;

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
    let db = contract_tests_db()?;
    let group = db.get_group_summary(community_id(), group_id()).await?;

    assert_eq!(group.group_id, group_id());
    assert_eq!(group.community_name, "contract-community");
    assert!(group.region.is_some());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_group_audit_logs_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = AuditLogFilters {
        limit: Some(10),
        offset: Some(0),

        ..Default::default()
    };
    let output = db.list_group_audit_logs(group_id(), &filters).await?;

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
async fn db_contracts_list_group_events_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = EventsListFilters {
        limit: Some(10),
        past_offset: Some(0),
        upcoming_offset: Some(0),

        ..Default::default()
    };
    let events = db.list_group_events(group_id(), &filters).await?;

    assert_eq!(events.past.total, 1);
    assert_eq!(events.upcoming.total, 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_group_members_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = GroupMembersFilters {
        limit: Some(10),
        offset: Some(0),
    };
    let output = db.list_group_members(group_id(), &filters).await?;

    assert_eq!(output.total, 1);
    assert_eq!(output.members.len(), 1);
    assert_eq!(output.members[0].username, "contract-attendee");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_group_sponsors_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = GroupSponsorsFilters {
        limit: Some(10),
        offset: Some(0),
    };
    let output = db.list_group_sponsors(group_id(), &filters, false).await?;

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
    let db = contract_tests_db()?;
    let filters = GroupTeamFilters {
        limit: Some(10),
        offset: Some(0),
    };
    let output = db.list_group_team_members(group_id(), &filters).await?;

    assert_eq!(output.total, 1);
    assert_eq!(output.total_accepted, 1);
    assert_eq!(output.total_admins_accepted, 1);
    assert_eq!(output.members[0].role, Some(GroupRole::Admin));
    assert_eq!(output.members[0].user_id, organizer_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_event_attendees_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = AttendeesFilters {
        event_id: event_id(),

        limit: Some(10),
        offset: Some(0),
    };
    let output = db.search_event_attendees(group_id(), &filters).await?;

    assert_eq!(output.total, 1);
    assert_eq!(output.attendees.len(), 1);
    assert_eq!(output.attendees[0].user_id, attendee_id());
    assert_eq!(output.attendees[0].username, "contract-attendee");
    assert!(output.attendees[0].checked_in);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_events_deserializes() -> Result<()> {
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
    let output = db.search_events(&filters).await?;

    assert_eq!(output.total, 1);
    assert_eq!(output.events.len(), 1);
    assert!(output.bbox.is_some());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_event_invitation_requests_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = InvitationRequestsFilters {
        event_id: event_id(),

        limit: Some(10),
        offset: Some(0),
    };
    let output = db.search_event_invitation_requests(group_id(), &filters).await?;

    assert_eq!(output.total, 1);
    assert_eq!(output.invitation_requests.len(), 1);
    assert_eq!(
        output.invitation_requests[0].invitation_request_status,
        EventInvitationRequestStatus::Pending
    );
    assert_eq!(output.invitation_requests[0].user_id, waitlist_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_event_waitlist_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = WaitlistFilters {
        event_id: event_id(),

        limit: Some(10),
        offset: Some(0),
    };
    let output = db.search_event_waitlist(group_id(), &filters).await?;

    assert_eq!(output.total, 1);
    assert_eq!(output.waitlist.len(), 1);
    assert_eq!(output.waitlist[0].user_id, waitlist_id());
    assert_eq!(output.waitlist[0].username, "contract-waitlist");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_groups_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = SearchGroupsFilters {
        community: vec!["contract-community".to_string()],

        include_bbox: Some(true),
        limit: Some(10),
        offset: Some(0),

        ..Default::default()
    };
    let output = db.search_groups(&filters).await?;

    assert_eq!(output.total, 1);
    assert_eq!(output.groups.len(), 1);
    assert!(output.bbox.is_some());

    Ok(())
}

// Helpers.

const ATTENDEE_ID: &str = "00000000-0000-0000-0000-00000000c042";
const AUTO_END_MEETING_ID: &str = "00000000-0000-0000-0000-00000000c0a3";
const COMMUNITY_ID: &str = "00000000-0000-0000-0000-00000000c001";
const EVENT_ID: &str = "00000000-0000-0000-0000-00000000c031";
const GROUP_ID: &str = "00000000-0000-0000-0000-00000000c021";
const GROUP_SPONSOR_ID: &str = "00000000-0000-0000-0000-00000000c061";
const ORGANIZER_ID: &str = "00000000-0000-0000-0000-00000000c041";
const SYNC_EVENT_ID: &str = "00000000-0000-0000-0000-00000000c0a1";
const WAITLIST_ID: &str = "00000000-0000-0000-0000-00000000c043";

fn attendee_id() -> Uuid {
    parse_uuid(ATTENDEE_ID)
}

fn auto_end_meeting_id() -> Uuid {
    parse_uuid(AUTO_END_MEETING_ID)
}

fn community_id() -> Uuid {
    parse_uuid(COMMUNITY_ID)
}

fn contract_tests_db() -> Result<PgDB> {
    let port = env_or_default("OCG_DB_PORT", "5432")
        .parse()
        .context("OCG_DB_PORT must be a valid port number")?;

    let mut cfg = DbConfig::new();
    cfg.dbname = Some(env_or_default("OCG_DB_NAME_TESTS_CONTRACT", "ocg_tests_contract"));
    cfg.host = Some(env_or_default("OCG_DB_HOST", "localhost"));
    cfg.port = Some(port);
    cfg.user = Some(env_or_default("OCG_DB_USER", "postgres"));

    if let Ok(password) = env::var("OCG_DB_PASSWORD")
        && !password.is_empty()
    {
        cfg.password = Some(password);
    }

    let pool = cfg.create_pool(Some(Runtime::Tokio1), NoTls)?;
    Ok(PgDB::new(pool))
}

fn env_or_default(name: &str, default: &str) -> String {
    env::var(name).unwrap_or_else(|_| default.to_string())
}

fn event_id() -> Uuid {
    parse_uuid(EVENT_ID)
}

fn group_id() -> Uuid {
    parse_uuid(GROUP_ID)
}

fn group_sponsor_id() -> Uuid {
    parse_uuid(GROUP_SPONSOR_ID)
}

fn organizer_id() -> Uuid {
    parse_uuid(ORGANIZER_ID)
}

fn parse_uuid(value: &str) -> Uuid {
    Uuid::parse_str(value).expect("contract fixture UUID should be valid")
}

fn sync_event_id() -> Uuid {
    parse_uuid(SYNC_EVENT_ID)
}

fn waitlist_id() -> Uuid {
    parse_uuid(WAITLIST_ID)
}
