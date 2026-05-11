//! Shared sample data builders for handlers tests.

use std::{
    collections::{BTreeMap, HashMap},
    sync::Arc,
};

use axum::Router;
use axum_login::tower_sessions::session;
use chrono::{TimeZone, Utc};
use chrono_tz::UTC;
use serde_json::json;
use time::{Duration as TimeDuration, OffsetDateTime};
use uuid::Uuid;

use crate::{
    activity_tracker::DynActivityTracker,
    auth::User as AuthUser,
    config::{HttpServerConfig, MeetingsConfig, MeetingsZoomConfig, PaymentsConfig},
    db::{
        BBox, DynDB,
        common::{SearchEventsOutput, SearchGroupsOutput},
        dashboard::common::User as DashboardUser,
        mock::MockDB,
    },
    handlers::auth::{SELECTED_COMMUNITY_ID_KEY, SELECTED_GROUP_ID_KEY},
    router,
    services::{
        images::{DynImageStorage, MockImageStorage},
        notifications::{DynNotificationsManager, MockNotificationsManager},
        payments::{DynPaymentsManager, MockPaymentsManager},
    },
    templates::{
        dashboard::{
            audit::{AuditLogRecord, AuditLogsOutput},
            community::{
                analytics::{
                    AttendeesStats, CommunityDashboardStats, CommunityPageViewsStats, EventsStats,
                    GroupsStats, MembersStats, PageViewsStats as CommunityPageViewsEntry,
                },
                groups::Group,
                settings::CommunityUpdate,
                team::CommunityTeamMember,
            },
            group::{
                analytics::{
                    GroupAttendeesStats, GroupDashboardStats, GroupEventsStats, GroupMembersStats,
                    GroupPageViewsStats, PageViewsStats as GroupPageViewsEntry,
                },
                attendees::Attendee,
                events::{CfsSubmissionStatus, Event as GroupEventForm, GroupEvents},
                home::UserGroupsByCommunity,
                invitation_requests::InvitationRequest,
                members::GroupMember,
                settings::GroupUpdate,
                sponsors::Sponsor,
                submissions::{
                    CfsSessionProposal as GroupCfsSessionProposal, CfsSubmission as GroupCfsSubmission,
                },
                team::GroupTeamMember,
                waitlist::WaitlistEntry,
            },
            user::{
                invitations::{CommunityTeamInvitation, GroupTeamInvitation},
                session_proposals::{
                    PendingCoSpeakerInvitation, SessionProposal as UserSessionProposal,
                    SessionProposalLevel as UserSessionProposalLevel,
                },
                submissions::{
                    CfsSessionProposal as UserCfsSessionProposal, CfsSubmission as UserCfsSubmission,
                },
            },
        },
        event::SessionProposal as EventSessionProposal,
    },
    types::{
        community::{CommunityFull, CommunityRole, CommunityRoleSummary, CommunitySummary},
        event::{EventCategory, EventFull, EventKind, EventKindSummary, EventSummary, SessionKindSummary},
        group::{
            GroupCategory, GroupFull, GroupMinimal, GroupRegion, GroupRole, GroupRoleSummary, GroupSponsor,
            GroupSummary,
        },
        payments::{EventPurchaseStatus, EventPurchaseSummary},
        site::{SiteSettings, Theme},
        user::{User as TemplateUser, UserSummary},
    },
};

/// Helper to check the flash message stored in the session record.
pub(crate) fn message_matches(record: &session::Record, expected_message: &str) -> bool {
    record
        .data
        .get("axum-messages.data")
        .and_then(|value| value.get("pending_messages"))
        .and_then(|messages| messages.as_array())
        .and_then(|messages| messages.first())
        .and_then(|message| message.get("m"))
        .and_then(|message| message.as_str())
        == Some(expected_message)
}

/// Sample attendee used in dashboard group home tests.
pub(crate) fn sample_attendee() -> Attendee {
    Attendee {
        amount_minor: None,
        checked_in: true,
        created_at: Utc.with_ymd_and_hms(2024, 1, 1, 12, 0, 0).unwrap(),
        currency_code: None,
        discount_code: None,
        event_purchase_id: None,
        user_id: Uuid::new_v4(),
        username: "attendee".to_string(),

        checked_in_at: Some(Utc.with_ymd_and_hms(2024, 1, 1, 13, 0, 0).unwrap()),
        company: Some("Example".to_string()),
        name: Some("Event Attendee".to_string()),
        photo_url: Some("https://example.test/avatar.png".to_string()),
        refund_request_status: None,
        ticket_title: None,
        title: Some("Engineer".to_string()),
    }
}

/// Sample audit log output used across dashboard audit tests.
pub(crate) fn sample_audit_logs_output() -> AuditLogsOutput {
    AuditLogsOutput {
        logs: vec![AuditLogRecord {
            action: "community_updated".to_string(),
            audit_log_id: Uuid::new_v4(),
            created_at: Utc.with_ymd_and_hms(2024, 1, 1, 12, 0, 0).unwrap(),
            details: BTreeMap::from([("subject".to_string(), json!("Schedule updated"))]),
            resource_id: Uuid::new_v4(),
            resource_type: "community".to_string(),

            actor_username: Some("test-user".to_string()),
            resource_name: Some("Test".to_string()),
        }],
        total: 1,
    }
}

/// Sample authenticated user used across handler tests.
pub(crate) fn sample_auth_user(user_id: Uuid, auth_hash: &str) -> AuthUser {
    AuthUser {
        auth_hash: auth_hash.to_string(),
        email: "user@example.test".to_string(),
        email_verified: true,
        name: "Test User".to_string(),
        optional_notifications_enabled: true,
        user_id,
        username: "test-user".to_string(),

        belongs_to_any_group_team: Some(true),
        has_password: Some(true),
        ..Default::default()
    }
}

/// Sample bounding box output used by explore handlers.
pub(crate) fn sample_bbox() -> BBox {
    BBox {
        ne_lat: 1.0,
        ne_lon: 2.0,
        sw_lat: -1.0,
        sw_lon: -2.0,
    }
}

/// Sample community used across tests.
pub(crate) fn sample_community_full(community_id: Uuid) -> CommunityFull {
    CommunityFull {
        active: true,
        banner_url: "https://example.test/banner.png".to_string(),
        community_id,
        community_site_layout_id: "default".to_string(),
        created_at: 0,
        description: "Test community".to_string(),
        display_name: "Test".to_string(),
        logo_url: "/static/images/placeholder_cncf.png".to_string(),
        name: "test".to_string(),
        ..Default::default()
    }
}

/// Sample community summary used across tests.
pub(crate) fn sample_community_summary(community_id: Uuid) -> CommunitySummary {
    CommunitySummary {
        banner_mobile_url: "https://example.test/banner_mobile.png".to_string(),
        banner_url: "https://example.test/banner.png".to_string(),
        community_id,
        display_name: "Test".to_string(),
        logo_url: "/static/images/placeholder_cncf.png".to_string(),
        name: "test".to_string(),
    }
}

/// Sample community invitation for dashboard user tests.
pub(crate) fn sample_community_invitation(community_id: Uuid) -> CommunityTeamInvitation {
    CommunityTeamInvitation {
        community_id,
        community_name: "test-community".to_string(),
        role: CommunityRole::Admin,
        created_at: Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap(),
    }
}

/// Sample community role summary used in dashboards.
pub(crate) fn sample_community_role_summary() -> CommunityRoleSummary {
    CommunityRoleSummary {
        community_role_id: "admin".to_string(),
        display_name: "Admin".to_string(),
    }
}

/// Sample community team member entry.
pub(crate) fn sample_community_team_member(accepted: bool) -> CommunityTeamMember {
    CommunityTeamMember {
        accepted,
        role: Some(CommunityRole::Admin),
        user_id: Uuid::new_v4(),
        username: "team-member".to_string(),

        company: Some("Example".to_string()),
        name: Some("Team Member".to_string()),
        photo_url: Some("https://example.test/photo.png".to_string()),
        title: Some("Organizer".to_string()),
    }
}

/// Sample community stats used in analytics tests.
pub(crate) fn sample_community_stats() -> CommunityDashboardStats {
    CommunityDashboardStats {
        attendees: AttendeesStats {
            per_month: vec![("2024-01".to_string(), 5)],
            per_month_by_event_category: HashMap::from([(
                "meetup".to_string(),
                vec![("2024-01".to_string(), 5)],
            )]),
            per_month_by_group_category: HashMap::new(),
            per_month_by_group_region: HashMap::new(),
            running_total: vec![(1, 5)],
            running_total_by_event_category: HashMap::new(),
            running_total_by_group_category: HashMap::new(),
            running_total_by_group_region: HashMap::new(),
            total: 5,
            total_by_event_category: vec![("meetup".to_string(), 5)],
            total_by_group_category: vec![],
            total_by_group_region: vec![],
        },
        events: EventsStats {
            per_month: vec![("2024-01".to_string(), 3)],
            per_month_by_event_category: HashMap::from([(
                "webinar".to_string(),
                vec![("2024-01".to_string(), 3)],
            )]),
            per_month_by_group_category: HashMap::new(),
            per_month_by_group_region: HashMap::new(),
            running_total: vec![(1, 3)],
            running_total_by_event_category: HashMap::new(),
            running_total_by_group_category: HashMap::new(),
            running_total_by_group_region: HashMap::new(),
            total: 3,
            total_by_event_category: vec![("webinar".to_string(), 3)],
            total_by_group_category: vec![],
            total_by_group_region: vec![],
        },
        groups: GroupsStats {
            per_month: vec![("2024-01".to_string(), 2)],
            per_month_by_category: HashMap::from([("dev".to_string(), vec![("2024-01".to_string(), 2)])]),
            per_month_by_region: HashMap::new(),
            running_total: vec![(1, 2)],
            running_total_by_category: HashMap::new(),
            running_total_by_region: HashMap::new(),
            total: 2,
            total_by_category: vec![("dev".to_string(), 2)],
            total_by_region: vec![],
        },
        members: MembersStats {
            per_month: vec![("2024-01".to_string(), 8)],
            per_month_by_category: HashMap::new(),
            per_month_by_region: HashMap::new(),
            running_total: vec![(1, 8)],
            running_total_by_category: HashMap::new(),
            running_total_by_region: HashMap::new(),
            total: 8,
            total_by_category: vec![],
            total_by_region: vec![],
        },
        page_views: CommunityPageViewsStats {
            community: CommunityPageViewsEntry {
                per_day_views: vec![("2024-01-10".to_string(), 2), ("2024-01-20".to_string(), 2)],
                per_month_views: vec![("2024-01".to_string(), 4)],
                total_views: 4,
            },
            events: CommunityPageViewsEntry {
                per_day_views: vec![("2024-01-11".to_string(), 5), ("2024-01-21".to_string(), 7)],
                per_month_views: vec![("2024-01".to_string(), 12)],
                total_views: 12,
            },
            groups: CommunityPageViewsEntry {
                per_day_views: vec![("2024-01-12".to_string(), 4), ("2024-01-22".to_string(), 5)],
                per_month_views: vec![("2024-01".to_string(), 9)],
                total_views: 9,
            },
            total_views: 25,
        },
    }
}

/// Sample community update payload for dashboard community settings tests.
pub(crate) fn sample_community_update() -> CommunityUpdate {
    CommunityUpdate {
        banner_mobile_url: "https://example.test/banner_mobile.png".to_string(),
        banner_url: "https://example.test/banner.png".to_string(),
        description: "Updated description".to_string(),
        display_name: "Test".to_string(),
        logo_url: "https://example.test/logo.png".to_string(),
        ..Default::default()
    }
}

/// Sample dashboard user entry returned by search endpoints.
pub(crate) fn sample_dashboard_user(user_id: Uuid) -> DashboardUser {
    DashboardUser {
        user_id,
        username: "test-user".to_string(),

        name: Some("Test User".to_string()),
        photo_url: Some("https://example.test/avatar.png".to_string()),
    }
}

/// Sample session record with no stored values.
pub(crate) fn sample_empty_session_record(session_id: session::Id) -> session::Record {
    session::Record {
        data: HashMap::default(),
        expiry_date: OffsetDateTime::now_utc(),
        id: session_id,
    }
}

/// Sample event category used in group event tests.
pub(crate) fn sample_event_category() -> EventCategory {
    EventCategory {
        events_count: None,
        event_category_id: Uuid::new_v4(),
        name: "Meetup".to_string(),
        slug: "meetup".to_string(),
    }
}

/// Sample CFS session proposal used in event handlers tests.
pub(crate) fn sample_event_cfs_session_proposal(session_proposal_id: Uuid) -> EventSessionProposal {
    EventSessionProposal {
        created_at: Utc.with_ymd_and_hms(2024, 1, 1, 12, 0, 0).unwrap(),
        description: "Talk description".to_string(),
        duration_minutes: 45,
        is_submitted: false,
        session_proposal_id,
        session_proposal_level_id: "intermediate".to_string(),
        session_proposal_level_name: "Intermediate".to_string(),
        session_proposal_status_id: "ready-for-submission".to_string(),
        status_name: "Ready for submission".to_string(),
        title: "Sample Proposal".to_string(),

        co_speaker: None,
        submission_status_id: None,
        submission_status_name: None,
        updated_at: None,
    }
}

/// Sample event form payload submitted from the dashboard.
pub(crate) fn sample_event_form() -> GroupEventForm {
    GroupEventForm {
        category_id: Uuid::new_v4(),
        description: "Event description".to_string(),
        kind_id: "virtual".to_string(),
        name: "Sample Event".to_string(),
        timezone: "UTC".to_string(),

        banner_url: Some("https://example.test/banner.png".to_string()),
        capacity: Some(100),
        description_short: Some("Short".to_string()),
        registration_required: Some(true),
        waitlist_enabled: Some(false),
        ..Default::default()
    }
}

/// Sample full event with hosts, sponsors, and schedule.
pub(crate) fn sample_event_full(community_id: Uuid, event_id: Uuid, group_id: Uuid) -> EventFull {
    let starts_at = Utc::now() + chrono::Duration::hours(1);
    let mut sessions = BTreeMap::new();
    sessions.insert(starts_at.date_naive(), Vec::new());

    EventFull {
        canceled: false,
        category_name: "Cloud Native".to_string(),
        community: sample_community_summary(community_id),
        created_at: Utc::now(),
        description: "A detailed event description".to_string(),
        event_id,
        group: sample_group_summary(group_id),
        hosts: vec![sample_template_user()],
        kind: EventKind::InPerson,
        logo_url: "https://example.test/logo.png".to_string(),
        name: "Test Event".to_string(),
        organizers: vec![sample_template_user()],
        published: true,
        sessions,
        slug: "abc1234".to_string(),
        timezone: UTC,

        banner_url: Some("https://example.test/banner.png".to_string()),
        capacity: Some(100),
        description_short: Some("A test event".to_string()),
        ends_at: Some(starts_at + chrono::Duration::hours(1)),
        latitude: Some(37.0),
        longitude: Some(-122.0),
        registration_required: Some(true),
        starts_at: Some(starts_at),
        venue_address: Some("123 Main St".to_string()),
        venue_city: Some("San Francisco".to_string()),
        venue_country_code: Some("US".to_string()),
        venue_country_name: Some("United States".to_string()),
        venue_name: Some("Main Venue".to_string()),
        venue_state: Some("CA".to_string()),
        waitlist_count: 0,
        waitlist_enabled: false,
        ..Default::default()
    }
}

/// Sample event kind summary for drop-downs.
pub(crate) fn sample_event_kind_summary() -> EventKindSummary {
    EventKindSummary {
        display_name: "Virtual".to_string(),
        event_kind_id: "virtual".to_string(),
    }
}

/// Sample event summary used in listings.
pub(crate) fn sample_event_summary(event_id: Uuid, _group_id: Uuid) -> EventSummary {
    let starts_at = Utc::now() + chrono::Duration::hours(1);
    EventSummary {
        attendee_approval_required: false,
        canceled: false,
        community_display_name: "Test Community".to_string(),
        community_name: "test-community".to_string(),
        event_id,
        group_category_name: "Meetup".to_string(),
        group_name: "Test Group".to_string(),
        group_slug: "def5678".to_string(),
        has_related_events: false,
        kind: EventKind::Virtual,
        logo_url: "https://example.test/logo.png".to_string(),
        name: "Sample Event".to_string(),
        published: true,
        slug: "ghi9abc".to_string(),
        timezone: UTC,

        capacity: None,
        created_by_display_name: None,
        created_by_username: None,
        description_short: Some("A brief summary of the sample event".to_string()),
        ends_at: Some(starts_at + chrono::Duration::hours(2)),
        event_series_id: None,
        latitude: Some(42.3601),
        longitude: Some(-71.0589),
        meeting_join_instructions: None,
        meeting_join_url: Some("https://example.test/meeting".to_string()),
        meeting_password: None,
        meeting_provider: None,
        payment_currency_code: None,
        popover_html: None,
        remaining_capacity: None,
        starts_at: Some(starts_at),
        ticket_types: None,
        venue_address: Some("456 Sample Rd".to_string()),
        venue_city: Some("Boston".to_string()),
        venue_country_code: Some("US".to_string()),
        venue_country_name: Some("United States".to_string()),
        venue_name: Some("Sample Venue".to_string()),
        venue_state: Some("MA".to_string()),
        waitlist_count: 0,
        waitlist_enabled: false,
        zip_code: Some("02101".to_string()),
    }
}

/// Sample filters options for explore page tests.
pub(crate) fn sample_filters_options() -> crate::templates::site::explore::FiltersOptions {
    crate::templates::site::explore::FiltersOptions::default()
}

/// Sample group category reused across tests.
pub(crate) fn sample_group_category() -> GroupCategory {
    GroupCategory {
        groups_count: Some(0),
        group_category_id: Uuid::new_v4(),
        name: "Meetup".to_string(),
        normalized_name: "meetup".to_string(),
        order: Some(1),
    }
}

/// Sample CFS session proposal used in group dashboard tests.
pub(crate) fn sample_group_cfs_session_proposal(session_proposal_id: Uuid) -> GroupCfsSessionProposal {
    GroupCfsSessionProposal {
        session_proposal_id,
        title: "Proposal title".to_string(),

        co_speaker: None,
        description: Some("Proposal description".to_string()),
        duration_minutes: Some(45),
        session_proposal_level_id: Some("intermediate".to_string()),
        session_proposal_level_name: Some("Intermediate".to_string()),
    }
}

/// Sample CFS submission used in group dashboard tests.
pub(crate) fn sample_group_cfs_submission(
    cfs_submission_id: Uuid,
    session_proposal_id: Uuid,
    speaker_id: Uuid,
) -> GroupCfsSubmission {
    GroupCfsSubmission {
        cfs_submission_id,
        created_at: Utc.with_ymd_and_hms(2024, 1, 2, 12, 0, 0).unwrap(),
        labels: vec![],
        ratings: vec![],
        ratings_count: 0,
        session_proposal: sample_group_cfs_session_proposal(session_proposal_id),
        speaker: sample_user_summary(speaker_id, "speaker"),
        status_id: "submitted".to_string(),
        status_name: "Submitted".to_string(),

        action_required_message: None,
        average_rating: None,
        linked_session_id: None,
        reviewed_by: None,
        updated_at: None,
    }
}

/// Sample CFS submission status used in group dashboard tests.
pub(crate) fn sample_group_cfs_submission_status(status_id: &str, display_name: &str) -> CfsSubmissionStatus {
    CfsSubmissionStatus {
        cfs_submission_status_id: status_id.to_string(),
        display_name: display_name.to_string(),
    }
}

/// Sample group events aggregation for dashboard pages.
pub(crate) fn sample_group_events(event_id: Uuid, group_id: Uuid) -> GroupEvents {
    let summary = sample_event_summary(event_id, group_id);
    GroupEvents {
        past: crate::templates::dashboard::group::events::PaginatedEvents {
            events: vec![summary.clone()],
            total: 1,
        },
        upcoming: crate::templates::dashboard::group::events::PaginatedEvents {
            events: vec![summary],
            total: 1,
        },
    }
}

/// Sample group form payload for community dashboard tests.
pub(crate) fn sample_group_form(category_id: Uuid) -> Group {
    Group {
        category_id,
        description: "Group description".to_string(),
        name: "Test Group".to_string(),
        ..Default::default()
    }
}

/// Sample full group record used in group pages.
pub(crate) fn sample_group_full(community_id: Uuid, group_id: Uuid) -> GroupFull {
    GroupFull {
        active: true,
        category: sample_group_category(),
        community: sample_community_summary(community_id),
        created_at: Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap(),
        group_id,
        logo_url: "https://example.test/logo.png".to_string(),
        members_count: 0,
        name: "Test Group".to_string(),
        organizers: Vec::new(),
        slug: "jkm2345".to_string(),
        sponsors: Vec::new(),

        city: Some("Test City".to_string()),
        country_code: Some("US".to_string()),
        country_name: Some("United States".to_string()),
        region: Some(sample_group_region()),
        state: Some("MA".to_string()),
        ..Default::default()
    }
}

/// Sample group team invitation used by user dashboard tests.
pub(crate) fn sample_group_invitation(group_id: Uuid) -> GroupTeamInvitation {
    GroupTeamInvitation {
        community_name: "test-community".to_string(),
        group_id,
        group_name: "Test Group".to_string(),
        role: GroupRole::Admin,
        created_at: Utc.with_ymd_and_hms(2024, 1, 2, 0, 0, 0).unwrap(),
    }
}

/// Sample group member entry for dashboard listings.
pub(crate) fn sample_group_member() -> GroupMember {
    GroupMember {
        created_at: Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap(),
        username: "member".to_string(),

        company: Some("Example".to_string()),
        name: Some("Group Member".to_string()),
        photo_url: Some("https://example.test/photo.png".to_string()),
        title: Some("Engineer".to_string()),
    }
}

/// Sample minimal group used in dashboard group selector tests.
pub(crate) fn sample_group_minimal(group_id: Uuid) -> GroupMinimal {
    GroupMinimal {
        active: true,
        group_id,
        name: "Test Group".to_string(),
        slug: "test-group".to_string(),
    }
}

/// Sample group region definition reused across tests.
pub(crate) fn sample_group_region() -> GroupRegion {
    GroupRegion {
        groups_count: Some(0),
        name: "North America".to_string(),
        normalized_name: "north-america".to_string(),
        order: Some(1),
        region_id: Uuid::new_v4(),
    }
}

/// Sample group stats used in analytics tests.
pub(crate) fn sample_group_stats() -> GroupDashboardStats {
    GroupDashboardStats {
        attendees: GroupAttendeesStats {
            per_month: vec![("2024-01".to_string(), 5)],
            running_total: vec![(1, 5)],
            total: 5,
        },
        events: GroupEventsStats {
            per_month: vec![("2024-01".to_string(), 3)],
            running_total: vec![(1, 3)],
            total: 3,
        },
        members: GroupMembersStats {
            per_month: vec![("2024-01".to_string(), 2)],
            running_total: vec![(1, 2)],
            total: 2,
        },
        page_views: GroupPageViewsStats {
            events: GroupPageViewsEntry {
                per_day_views: vec![("2024-01-10".to_string(), 3), ("2024-01-20".to_string(), 4)],
                per_month_views: vec![("2024-01".to_string(), 7)],
                total_views: 7,
            },
            group: GroupPageViewsEntry {
                per_day_views: vec![("2024-01-11".to_string(), 1), ("2024-01-21".to_string(), 3)],
                per_month_views: vec![("2024-01".to_string(), 4)],
                total_views: 4,
            },
            total_views: 11,
        },
    }
}

/// Sample group role summary used in dashboards.
pub(crate) fn sample_group_role_summary() -> GroupRoleSummary {
    GroupRoleSummary {
        display_name: "Admin".to_string(),
        group_role_id: "admin".to_string(),
    }
}

/// Sample group sponsor entry.
pub(crate) fn sample_group_sponsor() -> GroupSponsor {
    GroupSponsor {
        featured: true,
        group_sponsor_id: Uuid::new_v4(),
        logo_url: "https://example.test/logo.png".to_string(),
        name: "Sponsor".to_string(),

        website_url: Some("https://example.test".to_string()),
    }
}

/// Sample group summary used by multiple fixtures.
pub(crate) fn sample_group_summary(group_id: Uuid) -> GroupSummary {
    GroupSummary {
        active: true,
        category: sample_group_category(),
        community_display_name: "Test Community".to_string(),
        community_name: "test-community".to_string(),
        created_at: Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap(),
        group_id,
        logo_url: "https://example.test/logo.png".to_string(),
        name: "Test Group".to_string(),
        slug: "npq6789".to_string(),

        banner_mobile_url: Some("https://example.test/banner_mobile.png".to_string()),
        banner_url: Some("https://example.test/banner.png".to_string()),
        city: Some("San Francisco".to_string()),
        country_code: Some("US".to_string()),
        country_name: Some("United States".to_string()),
        description_short: Some("An example summary for the sample group".to_string()),
        latitude: Some(37.0),
        longitude: Some(-122.0),
        popover_html: None,
        region: Some(sample_group_region()),
        state: Some("CA".to_string()),
    }
}

/// Sample group update payload for dashboard group settings.
pub(crate) fn sample_group_update() -> GroupUpdate {
    GroupUpdate {
        category_id: Uuid::new_v4(),
        description: "Updated description".to_string(),
        name: "Updated Group".to_string(),

        banner_url: Some("https://example.test/banner.png".to_string()),
        city: Some("Test City".to_string()),
        country_code: Some("US".to_string()),
        country_name: Some("United States".to_string()),
        extra_links: Some(BTreeMap::new()),
        bluesky_url: Some("https://bsky.app/profile/test".to_string()),
        facebook_url: Some("https://facebook.com/test".to_string()),
        github_url: Some("https://github.com/test".to_string()),
        linkedin_url: Some("https://linkedin.com/company/test".to_string()),
        logo_url: Some("https://example.test/logo.png".to_string()),
        region_id: Some(Uuid::new_v4()),
        state: Some("MA".to_string()),
        website_url: Some("https://example.test".to_string()),

        ..Default::default()
    }
}

/// Sample pending co-speaker invitation used in user dashboard tests.
pub(crate) fn sample_pending_co_speaker_invitation(session_proposal_id: Uuid) -> PendingCoSpeakerInvitation {
    PendingCoSpeakerInvitation {
        session_proposal: UserSessionProposal {
            created_at: Utc.with_ymd_and_hms(2024, 1, 3, 12, 0, 0).unwrap(),
            description: "Session about Rust ownership".to_string(),
            duration_minutes: 45,
            has_submissions: false,
            session_proposal_id,
            session_proposal_level_id: "intermediate".to_string(),
            session_proposal_level_name: "Intermediate".to_string(),
            session_proposal_status_id: "pending-co-speaker-response".to_string(),
            status_name: "Pending co-speaker response".to_string(),
            title: "Rust 201".to_string(),

            co_speaker: Some(sample_user_summary(Uuid::new_v4(), "co-speaker")),
            linked_session_id: None,
            updated_at: Some(Utc.with_ymd_and_hms(2024, 1, 4, 12, 0, 0).unwrap()),
        },
        speaker_name: "Speaker".to_string(),

        speaker_photo_url: Some("https://example.test/speaker.png".to_string()),
    }
}

/// Sample purchase summary used in event handler tests.
pub(crate) fn sample_purchase_summary(status: EventPurchaseStatus) -> EventPurchaseSummary {
    EventPurchaseSummary {
        amount_minor: 2_500,
        currency_code: "USD".to_string(),
        discount_amount_minor: 0,
        event_purchase_id: Uuid::new_v4(),
        event_ticket_type_id: Uuid::new_v4(),
        status,
        ticket_title: "General admission".to_string(),

        completed_at: None,
        discount_code: None,
        hold_expires_at: None,
        provider_checkout_url: None,
        provider_payment_reference: None,
        provider_session_id: None,
        refunded_at: None,
    }
}

/// Sample search output for events.
pub(crate) fn sample_search_events_output(event_id: Uuid) -> SearchEventsOutput {
    SearchEventsOutput {
        events: vec![sample_event_summary(event_id, Uuid::new_v4())],
        bbox: Some(sample_bbox()),
        total: 1,
    }
}

/// Sample search output for groups.
pub(crate) fn sample_search_groups_output(group_id: Uuid) -> SearchGroupsOutput {
    SearchGroupsOutput {
        groups: vec![sample_group_summary(group_id)],
        bbox: Some(sample_bbox()),
        total: 1,
    }
}

/// Sample session kind summary for event forms.
pub(crate) fn sample_session_kind_summary() -> SessionKindSummary {
    SessionKindSummary {
        display_name: "Keynote".to_string(),
        session_kind_id: "hybrid".to_string(),
    }
}

/// Sample session proposal used in user session proposals tests.
pub(crate) fn sample_session_proposal(session_proposal_id: Uuid) -> UserSessionProposal {
    UserSessionProposal {
        created_at: Utc.with_ymd_and_hms(2024, 1, 2, 12, 0, 0).unwrap(),
        description: "Session about Rust".to_string(),
        duration_minutes: 45,
        has_submissions: false,
        session_proposal_id,
        session_proposal_level_id: "beginner".to_string(),
        session_proposal_level_name: "Beginner".to_string(),
        session_proposal_status_id: "ready-for-submission".to_string(),
        status_name: "Ready for submission".to_string(),
        title: "Rust 101".to_string(),

        co_speaker: None,
        linked_session_id: None,
        updated_at: None,
    }
}

/// Sample session proposal levels used in user session proposals tests.
pub(crate) fn sample_session_proposal_levels() -> Vec<UserSessionProposalLevel> {
    vec![UserSessionProposalLevel {
        display_name: "Beginner".to_string(),
        session_proposal_level_id: "beginner".to_string(),
    }]
}

/// Sample session record used across tests.
pub(crate) fn sample_session_record(
    session_id: session::Id,
    user_id: Uuid,
    auth_hash: &str,
    selected_community_id: Option<Uuid>,
    selected_group_id: Option<Uuid>,
) -> session::Record {
    let mut data = HashMap::new();
    data.insert(
        "axum-login.data".to_string(),
        json!({
            "user_id": user_id,
            "auth_hash": auth_hash.as_bytes(),
        }),
    );
    if let Some(community_id) = selected_community_id {
        data.insert(SELECTED_COMMUNITY_ID_KEY.to_string(), json!(community_id));
    }
    if let Some(group_id) = selected_group_id {
        data.insert(SELECTED_GROUP_ID_KEY.to_string(), json!(group_id));
    }

    session::Record {
        data,
        expiry_date: OffsetDateTime::now_utc().saturating_add(TimeDuration::days(1)),
        id: session_id,
    }
}

/// Sample site home stats for home page tests.
pub(crate) fn sample_site_home_stats() -> crate::types::site::SiteHomeStats {
    crate::types::site::SiteHomeStats::default()
}

/// Sample site settings used across tests.
pub(crate) fn sample_site_settings() -> SiteSettings {
    SiteSettings {
        description: "Test site".to_string(),
        site_id: Uuid::new_v4(),
        theme: Theme {
            palette: BTreeMap::new(),
            primary_color: "#000000".to_string(),
        },
        title: "Test Site".to_string(),
        ..Default::default()
    }
}

/// Sample site stats for stats page tests.
pub(crate) fn sample_site_stats() -> crate::templates::site::stats::SiteStats {
    crate::templates::site::stats::SiteStats {
        attendees: crate::templates::site::stats::SiteStatsSection {
            per_month: vec![],
            running_total: vec![],
            total: 0,
        },
        events: crate::templates::site::stats::SiteStatsSection {
            per_month: vec![],
            running_total: vec![],
            total: 0,
        },
        groups: crate::templates::site::stats::SiteStatsSection {
            per_month: vec![],
            running_total: vec![],
            total: 0,
        },
        members: crate::templates::site::stats::SiteStatsSection {
            per_month: vec![],
            running_total: vec![],
            total: 0,
        },
    }
}

/// Sample sponsor form payload used by dashboard group sponsors tests.
pub(crate) fn sample_sponsor_form() -> Sponsor {
    Sponsor {
        featured: true,
        logo_url: "https://example.test/logo.png".to_string(),
        name: "Example".to_string(),

        website_url: Some("https://example.test".to_string()),
    }
}

/// Sample team member listing entry.
pub(crate) fn sample_team_member(accepted: bool) -> GroupTeamMember {
    GroupTeamMember {
        accepted,
        role: Some(GroupRole::Admin),
        user_id: Uuid::new_v4(),
        username: "team-member".to_string(),

        company: Some("Example".to_string()),
        name: Some("Team Member".to_string()),
        photo_url: Some("https://example.test/photo.png".to_string()),
        title: Some("Organizer".to_string()),
    }
}

/// Sample template user used in event fixtures.
pub(crate) fn sample_template_user() -> TemplateUser {
    TemplateUser {
        user_id: Uuid::new_v4(),
        username: "organizer".to_string(),

        name: Some("Organizer".to_string()),
        ..Default::default()
    }
}

/// Sample template user with a specific user ID.
pub(crate) fn sample_template_user_with_id(user_id: Uuid) -> TemplateUser {
    TemplateUser {
        user_id,
        username: "speaker".to_string(),

        name: Some("Speaker".to_string()),
        ..Default::default()
    }
}

/// Sample ticketed event payload for dashboard group event form tests.
pub(crate) fn sample_ticketed_event_body() -> String {
    let event_form = sample_event_form();

    format!(
        concat!(
            "{}",
            "&payment_currency_code=USD",
            "&ticket_types_present=true",
            "&ticket_types[0][active]=true",
            "&ticket_types[0][order]=1",
            "&ticket_types[0][price_windows][0][amount_minor]=1500",
            "&ticket_types[0][seats_total]=25",
            "&ticket_types[0][title]=General%20admission"
        ),
        serde_qs::to_string(&event_form).unwrap(),
    )
}

/// Sample server configuration for testing `track_view` handlers.
pub(crate) fn sample_tracking_server_cfg() -> HttpServerConfig {
    HttpServerConfig {
        base_url: "https://example.test".to_string(),
        ..Default::default()
    }
}

/// Sample CFS session proposal used in user dashboard tests.
pub(crate) fn sample_user_cfs_session_proposal(session_proposal_id: Uuid) -> UserCfsSessionProposal {
    UserCfsSessionProposal {
        session_proposal_id,
        title: "Proposal title".to_string(),

        co_speaker: Some(sample_user_summary(Uuid::new_v4(), "co-speaker")),
        description: Some("Proposal description".to_string()),
        duration_minutes: Some(30),
        session_proposal_level_id: Some("beginner".to_string()),
        session_proposal_level_name: Some("Beginner".to_string()),
    }
}

/// Sample CFS submission used in user dashboard tests.
pub(crate) fn sample_user_cfs_submission(
    cfs_submission_id: Uuid,
    event_id: Uuid,
    group_id: Uuid,
    session_proposal_id: Uuid,
) -> UserCfsSubmission {
    UserCfsSubmission {
        cfs_submission_id,
        created_at: Utc.with_ymd_and_hms(2024, 1, 2, 12, 0, 0).unwrap(),
        event: sample_event_summary(event_id, group_id),
        labels: vec![],
        session_proposal: sample_user_cfs_session_proposal(session_proposal_id),
        status_id: "submitted".to_string(),
        status_name: "Submitted".to_string(),

        action_required_message: None,
        linked_session_id: None,
        updated_at: None,
    }
}

/// Sample user communities used in dashboard community tests.
pub(crate) fn sample_user_communities(community_id: Uuid) -> Vec<CommunitySummary> {
    vec![CommunitySummary {
        banner_mobile_url: "https://example.com/banner_mobile.png".to_string(),
        banner_url: "https://example.com/banner.png".to_string(),
        community_id,
        display_name: "Test Community".to_string(),
        logo_url: "https://example.com/logo.png".to_string(),
        name: "test-community".to_string(),
    }]
}

/// Sample user groups by community used in dashboard group tests.
pub(crate) fn sample_user_groups_by_community(
    community_id: Uuid,
    group_id: Uuid,
) -> Vec<UserGroupsByCommunity> {
    vec![UserGroupsByCommunity {
        community: CommunitySummary {
            banner_mobile_url: "https://example.com/banner_mobile.png".to_string(),
            banner_url: "https://example.com/banner.png".to_string(),
            community_id,
            display_name: "Test Community".to_string(),
            logo_url: "https://example.com/logo.png".to_string(),
            name: "test-community".to_string(),
        },
        groups: vec![sample_group_minimal(group_id)],
    }]
}

/// Sample user summary used across dashboard tests.
pub(crate) fn sample_user_summary(user_id: Uuid, username: &str) -> UserSummary {
    UserSummary {
        user_id,
        username: username.to_string(),

        company: None,
        name: None,
        photo_url: None,
        provider: None,
        title: None,
    }
}

/// Sample waitlist entry used in dashboard group waitlist tests.
pub(crate) fn sample_waitlist_entry() -> WaitlistEntry {
    WaitlistEntry {
        created_at: Utc.with_ymd_and_hms(2024, 1, 1, 12, 0, 0).unwrap(),
        user_id: Uuid::new_v4(),
        username: "waitlisted-user".to_string(),

        company: Some("Example".to_string()),
        name: Some("Waitlisted User".to_string()),
        photo_url: Some("https://example.test/avatar.png".to_string()),
        title: Some("Engineer".to_string()),
    }
}

/// Sample invitation request used in dashboard group invitation request tests.
pub(crate) fn sample_invitation_request() -> InvitationRequest {
    InvitationRequest {
        created_at: Utc.with_ymd_and_hms(2024, 1, 1, 12, 0, 0).unwrap(),
        invitation_request_status: crate::types::event::EventInvitationRequestStatus::Pending,
        user_id: Uuid::new_v4(),
        username: "requesting-user".to_string(),

        company: Some("Example".to_string()),
        name: Some("Requesting User".to_string()),
        photo_url: Some("https://example.test/avatar.png".to_string()),
        reviewed_at: None,
        title: Some("Engineer".to_string()),
    }
}

/// Sample Zoom meetings configuration used in handler tests.
pub(crate) fn sample_zoom_meetings_cfg(secret: &str) -> MeetingsConfig {
    MeetingsConfig {
        zoom: Some(MeetingsZoomConfig {
            account_id: "account-id".to_string(),
            client_id: "client-id".to_string(),
            client_secret: "client-secret".to_string(),
            enabled: true,
            host_pool_users: vec!["host@example.com".to_string()],
            max_participants: 100,
            max_simultaneous_meetings_per_host: 1,
            webhook_secret_token: secret.to_string(),
        }),
    }
}

/// Checks if the session record contains the selected group ID.
pub(crate) fn session_record_contains_selected_group(record: &session::Record, group_id: Uuid) -> bool {
    record
        .data
        .get(SELECTED_GROUP_ID_KEY)
        .and_then(|value| value.as_str())
        .and_then(|value| value.parse::<Uuid>().ok())
        == Some(group_id)
}

/// Builds test router state with default server configuration.
pub(crate) fn test_state(
    db: DynDB,
    image_storage: DynImageStorage,
    notifications_manager: DynNotificationsManager,
) -> router::State {
    test_state_with_server_cfg(
        db,
        image_storage,
        notifications_manager,
        &HttpServerConfig::default(),
    )
}

/// Builds test router state with the provided server configuration.
pub(crate) fn test_state_with_server_cfg(
    db: DynDB,
    image_storage: DynImageStorage,
    notifications_manager: DynNotificationsManager,
    server_cfg: &HttpServerConfig,
) -> router::State {
    router::State {
        activity_tracker: Arc::new(crate::activity_tracker::MockActivityTracker::new()),
        db,
        image_storage,
        meetings_cfg: None,
        notifications_manager,
        payments_cfg: None,
        payments_manager: Arc::new(MockPaymentsManager::new()),
        serde_qs_de: router::serde_qs_config(),
        server_cfg: server_cfg.clone(),
    }
}

/// Builder for test router configuration.
pub(crate) struct TestRouterBuilder {
    activity_tracker: Option<crate::activity_tracker::MockActivityTracker>,
    db: MockDB,
    image_storage: Option<MockImageStorage>,
    meetings_cfg: Option<crate::config::MeetingsConfig>,
    nm: MockNotificationsManager,
    payments_cfg: Option<PaymentsConfig>,
    payments_manager: Option<MockPaymentsManager>,
    server_cfg: Option<HttpServerConfig>,
}

impl TestRouterBuilder {
    /// Creates a new test router builder with required dependencies.
    pub(crate) fn new(db: MockDB, nm: MockNotificationsManager) -> Self {
        Self {
            activity_tracker: None,
            db,
            image_storage: None,
            meetings_cfg: None,
            nm,
            payments_cfg: None,
            payments_manager: None,
            server_cfg: None,
        }
    }

    /// Builds the application router with the configured options.
    pub(crate) async fn build(self) -> Router {
        let db: DynDB = Arc::new(self.db);
        let activity_tracker: DynActivityTracker = Arc::new(self.activity_tracker.unwrap_or_default());
        let is: DynImageStorage = Arc::new(self.image_storage.unwrap_or_default());
        let nm: DynNotificationsManager = Arc::new(self.nm);
        let server_cfg = self.server_cfg.unwrap_or_default();
        let payments_manager = self.payments_manager.unwrap_or_default();
        let payments_manager = Arc::new(payments_manager) as DynPaymentsManager;

        router::setup(
            activity_tracker,
            db,
            is,
            self.meetings_cfg,
            self.payments_cfg,
            payments_manager,
            nm,
            &server_cfg,
        )
        .await
        .expect("router setup should succeed")
    }

    /// Sets a custom activity tracker.
    pub(crate) fn with_activity_tracker(
        mut self,
        activity_tracker: crate::activity_tracker::MockActivityTracker,
    ) -> Self {
        self.activity_tracker = Some(activity_tracker);
        self
    }

    /// Sets a custom image storage.
    pub(crate) fn with_image_storage(mut self, is: MockImageStorage) -> Self {
        self.image_storage = Some(is);
        self
    }

    /// Sets a custom meetings configuration.
    pub(crate) fn with_meetings_cfg(mut self, cfg: crate::config::MeetingsConfig) -> Self {
        self.meetings_cfg = Some(cfg);
        self
    }

    /// Sets a custom payments configuration.
    pub(crate) fn with_payments_cfg(mut self, cfg: PaymentsConfig) -> Self {
        self.payments_cfg = Some(cfg);
        self
    }

    /// Sets a custom payments manager.
    pub(crate) fn with_payments_manager(mut self, payments_manager: MockPaymentsManager) -> Self {
        self.payments_manager = Some(payments_manager);
        self
    }

    /// Sets a custom server configuration.
    pub(crate) fn with_server_cfg(mut self, cfg: HttpServerConfig) -> Self {
        self.server_cfg = Some(cfg);
        self
    }
}
