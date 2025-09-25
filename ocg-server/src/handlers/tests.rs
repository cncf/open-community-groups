//! Shared sample data builders for handlers tests.

use std::collections::{BTreeMap, HashMap};

use axum_login::tower_sessions::session;
use chrono::{TimeZone, Utc};
use chrono_tz::UTC;
use serde_json::json;
use time::{Duration as TimeDuration, OffsetDateTime};
use uuid::Uuid;

use crate::{
    auth::User as AuthUser,
    db::{
        BBox,
        common::{SearchCommunityEventsOutput, SearchCommunityGroupsOutput},
        dashboard::common::User as DashboardUser,
    },
    handlers::auth::SELECTED_GROUP_ID_KEY,
    templates::{
        common::User as TemplateUser,
        community::explore::{self, FilterOption},
        dashboard::{
            community::{groups::Group, settings::CommunityUpdate, team::CommunityTeamMember},
            group::{
                attendees::Attendee,
                events::{Event as GroupEventForm, GroupEvents},
                members::GroupMember,
                settings::GroupUpdate,
                sponsors::Sponsor,
                team::GroupTeamMember,
            },
            user::invitations::{CommunityTeamInvitation, GroupTeamInvitation},
        },
    },
    types::{
        community::{Community, Theme},
        event::{
            EventCategory, EventDetailed, EventFull, EventKind, EventKindSummary, EventSummary,
            SessionKindSummary,
        },
        group::{
            GroupCategory, GroupDetailed, GroupFull, GroupRegion, GroupRole, GroupRoleSummary, GroupSponsor,
            GroupSummary,
        },
    },
};

/// Sample attendee used in dashboard group home tests.
pub(crate) fn sample_attendee() -> Attendee {
    Attendee {
        checked_in: true,
        created_at: Utc.with_ymd_and_hms(2024, 1, 1, 12, 0, 0).unwrap(),
        username: "attendee".to_string(),

        company: Some("Example".to_string()),
        name: Some("Event Attendee".to_string()),
        photo_url: Some("https://example.test/avatar.png".to_string()),
        title: Some("Engineer".to_string()),
    }
}

/// Sample authenticated user used across handler tests.
pub(crate) fn sample_auth_user(user_id: Uuid, auth_hash: &str) -> AuthUser {
    AuthUser {
        auth_hash: auth_hash.to_string(),
        email: "user@example.test".to_string(),
        email_verified: true,
        name: "Test User".to_string(),
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
pub(crate) fn sample_community(community_id: Uuid) -> Community {
    Community {
        active: true,
        community_id,
        community_site_layout_id: "default".to_string(),
        created_at: 0,
        description: "Test community".to_string(),
        display_name: "Test".to_string(),
        header_logo_url: "/static/images/placeholder_cncf.png".to_string(),
        host: "example.test".to_string(),
        name: "test".to_string(),
        theme: Theme {
            palette: BTreeMap::new(),
            primary_color: "#000000".to_string(),
        },
        title: "Test Community".to_string(),
        ..Default::default()
    }
}

/// Sample community invitation for dashboard user tests.
pub(crate) fn sample_community_invitation() -> CommunityTeamInvitation {
    CommunityTeamInvitation {
        community_name: "test-community".to_string(),
        created_at: Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap(),
    }
}

/// Sample community team member entry.
pub(crate) fn sample_community_team_member(accepted: bool) -> CommunityTeamMember {
    CommunityTeamMember {
        accepted,
        user_id: Uuid::new_v4(),
        username: "team-member".to_string(),

        company: Some("Example".to_string()),
        name: Some("Team Member".to_string()),
        photo_url: Some("https://example.test/photo.png".to_string()),
        title: Some("Organizer".to_string()),
    }
}

/// Sample community update payload for dashboard community settings tests.
pub(crate) fn sample_community_update() -> CommunityUpdate {
    CommunityUpdate {
        description: "Updated description".to_string(),
        display_name: "Test".to_string(),
        header_logo_url: "/logo.png".to_string(),
        name: "test".to_string(),
        primary_color: "#000000".to_string(),
        title: "Test Community".to_string(),
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

/// Sample event category used in group event tests.
pub(crate) fn sample_event_category() -> EventCategory {
    EventCategory {
        event_category_id: Uuid::new_v4(),
        name: "Meetup".to_string(),
        slug: "meetup".to_string(),
    }
}

/// Sample detailed event returned from listings.
pub(crate) fn sample_event_detailed(event_id: Uuid) -> EventDetailed {
    let starts_at = Utc::now() + chrono::Duration::hours(1);
    EventDetailed {
        canceled: false,
        event_id,
        group_category_name: "Cloud Native".to_string(),
        group_color: "#336699".to_string(),
        group_name: "Test Group".to_string(),
        group_slug: "test-group".to_string(),
        kind: EventKind::InPerson,
        name: "Test Event".to_string(),
        published: true,
        slug: "test-event".to_string(),
        timezone: UTC,

        description_short: Some("A test event".to_string()),
        ends_at: Some(starts_at + chrono::Duration::hours(1)),
        group_city: Some("San Francisco".to_string()),
        group_country_code: Some("US".to_string()),
        group_country_name: Some("United States".to_string()),
        group_state: Some("CA".to_string()),
        latitude: Some(37.0),
        logo_url: Some("https://example.test/logo.png".to_string()),
        longitude: Some(-122.0),
        starts_at: Some(starts_at),
        venue_address: Some("123 Main St".to_string()),
        venue_city: Some("San Francisco".to_string()),
        venue_name: Some("Main Venue".to_string()),
        ..Default::default()
    }
}

/// Sample event form payload submitted from the dashboard.
pub(crate) fn sample_event_form() -> GroupEventForm {
    GroupEventForm {
        category_id: Uuid::new_v4(),
        description: "Event description".to_string(),
        kind_id: "virtual".to_string(),
        name: "Sample Event".to_string(),
        slug: "sample-event".to_string(),
        timezone: "UTC".to_string(),

        banner_url: Some("https://example.test/banner.png".to_string()),
        capacity: Some(100),
        description_short: Some("Short".to_string()),
        registration_required: Some(true),
        ..Default::default()
    }
}

/// Sample full event with hosts, sponsors, and schedule.
pub(crate) fn sample_event_full(event_id: Uuid, group_id: Uuid) -> EventFull {
    let starts_at = Utc::now() + chrono::Duration::hours(1);
    let mut sessions = BTreeMap::new();
    sessions.insert(starts_at.date_naive(), Vec::new());

    EventFull {
        canceled: false,
        category_name: "Cloud Native".to_string(),
        color: "#336699".to_string(),
        created_at: Utc::now(),
        description: "A detailed event description".to_string(),
        event_id,
        group: sample_group_summary(group_id),
        hosts: vec![sample_template_user()],
        kind: EventKind::InPerson,
        name: "Test Event".to_string(),
        organizers: vec![sample_template_user()],
        published: true,
        sessions,
        slug: "test-event".to_string(),
        timezone: UTC,

        banner_url: Some("https://example.test/banner.png".to_string()),
        capacity: Some(100),
        description_short: Some("A test event".to_string()),
        ends_at: Some(starts_at + chrono::Duration::hours(1)),
        latitude: Some(37.0),
        logo_url: Some("https://example.test/logo.png".to_string()),
        longitude: Some(-122.0),
        registration_required: Some(true),
        starts_at: Some(starts_at),
        venue_address: Some("123 Main St".to_string()),
        venue_city: Some("San Francisco".to_string()),
        venue_name: Some("Main Venue".to_string()),
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
        canceled: false,
        event_id,
        group_category_name: "Meetup".to_string(),
        group_color: "#123456".to_string(),
        group_name: "Test Group".to_string(),
        group_slug: "test-group".to_string(),
        kind: EventKind::Virtual,
        name: "Sample Event".to_string(),
        published: true,
        slug: "sample-event".to_string(),
        timezone: UTC,

        group_city: Some("Test City".to_string()),
        group_country_code: Some("US".to_string()),
        group_country_name: Some("United States".to_string()),
        group_state: Some("MA".to_string()),
        logo_url: Some("https://example.test/logo.png".to_string()),
        starts_at: Some(starts_at),
        venue_city: Some("Boston".to_string()),
    }
}

/// Sample filters options used by explore tests.
pub(crate) fn sample_filters_options() -> explore::FiltersOptions {
    explore::FiltersOptions {
        distance: vec![FilterOption {
            name: "5 km".to_string(),
            value: "5".to_string(),
        }],
        event_category: vec![FilterOption {
            name: "Category".to_string(),
            value: "category".to_string(),
        }],
        group_category: vec![FilterOption {
            name: "Category".to_string(),
            value: "category".to_string(),
        }],
        region: vec![FilterOption {
            name: "Region".to_string(),
            value: "region".to_string(),
        }],
    }
}

/// Sample group category reused across tests.
pub(crate) fn sample_group_category() -> GroupCategory {
    GroupCategory {
        group_category_id: Uuid::new_v4(),
        name: "Meetup".to_string(),
        normalized_name: "meetup".to_string(),
        order: Some(1),
    }
}

/// Sample detailed group record for explore results.
pub(crate) fn sample_group_detailed(group_id: Uuid) -> GroupDetailed {
    GroupDetailed {
        active: true,
        category: sample_group_category(),
        created_at: Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap(),
        group_id,
        name: "Sample Group".to_string(),
        slug: "sample-group".to_string(),

        city: Some("City".to_string()),
        country_code: Some("US".to_string()),
        country_name: Some("United States".to_string()),
        latitude: Some(1.0),
        longitude: Some(2.0),
        region: Some(sample_group_region()),
        state: Some("CA".to_string()),
        ..Default::default()
    }
}

/// Sample group events aggregation for dashboard pages.
pub(crate) fn sample_group_events(event_id: Uuid, group_id: Uuid) -> GroupEvents {
    let summary = sample_event_summary(event_id, group_id);
    GroupEvents {
        past: vec![summary.clone()],
        upcoming: vec![summary],
    }
}

/// Sample group form payload for community dashboard tests.
pub(crate) fn sample_group_form(category_id: Uuid) -> Group {
    Group {
        category_id,
        description: "Group description".to_string(),
        name: "Test Group".to_string(),
        slug: "test-group".to_string(),
        ..Default::default()
    }
}

/// Sample full group record used in group pages.
pub(crate) fn sample_group_full(group_id: Uuid) -> GroupFull {
    GroupFull {
        active: true,
        category: sample_group_category(),
        created_at: Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap(),
        group_id,
        members_count: 0,
        name: "Test Group".to_string(),
        organizers: Vec::new(),
        slug: "test-group".to_string(),
        sponsors: Vec::new(),

        city: Some("Test City".to_string()),
        country_code: Some("US".to_string()),
        country_name: Some("United States".to_string()),
        logo_url: Some("https://example.test/logo.png".to_string()),
        region: Some(sample_group_region()),
        state: Some("MA".to_string()),
        ..Default::default()
    }
}

/// Sample group team invitation used by user dashboard tests.
pub(crate) fn sample_group_invitation(group_id: Uuid) -> GroupTeamInvitation {
    GroupTeamInvitation {
        created_at: Utc.with_ymd_and_hms(2024, 1, 2, 0, 0, 0).unwrap(),
        group_id,
        group_name: "Test Group".to_string(),
        role: GroupRole::Organizer,
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

/// Sample group region definition reused across tests.
pub(crate) fn sample_group_region() -> GroupRegion {
    GroupRegion {
        name: "North America".to_string(),
        normalized_name: "north-america".to_string(),
        order: Some(1),
        region_id: Uuid::new_v4(),
    }
}

/// Sample group role summary used in dashboards.
pub(crate) fn sample_group_role_summary() -> GroupRoleSummary {
    GroupRoleSummary {
        display_name: "Organizer".to_string(),
        group_role_id: "organizer".to_string(),
    }
}

/// Sample group sponsor entry.
pub(crate) fn sample_group_sponsor() -> GroupSponsor {
    GroupSponsor {
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
        color: "#336699".to_string(),
        created_at: Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap(),
        group_id,
        name: "Test Group".to_string(),
        slug: "test-group".to_string(),

        city: Some("San Francisco".to_string()),
        country_code: Some("US".to_string()),
        country_name: Some("United States".to_string()),
        logo_url: Some("https://example.test/logo.png".to_string()),
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
        slug: "updated-group".to_string(),

        banner_url: Some("https://example.test/banner.png".to_string()),
        city: Some("Test City".to_string()),
        country_code: Some("US".to_string()),
        country_name: Some("United States".to_string()),
        extra_links: Some(BTreeMap::new()),
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

/// Sample search output for community events.
pub(crate) fn sample_search_community_events_output(event_id: Uuid) -> SearchCommunityEventsOutput {
    SearchCommunityEventsOutput {
        events: vec![sample_event_detailed(event_id)],
        bbox: Some(sample_bbox()),
        total: 1,
    }
}

/// Sample search output for community groups.
pub(crate) fn sample_search_community_groups_output(group_id: Uuid) -> SearchCommunityGroupsOutput {
    SearchCommunityGroupsOutput {
        groups: vec![sample_group_detailed(group_id)],
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

/// Sample session record used across tests.
pub(crate) fn sample_session_record(
    session_id: session::Id,
    user_id: Uuid,
    auth_hash: &str,
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
    if let Some(group_id) = selected_group_id {
        data.insert(SELECTED_GROUP_ID_KEY.to_string(), json!(group_id));
    }

    session::Record {
        data,
        expiry_date: OffsetDateTime::now_utc().saturating_add(TimeDuration::days(1)),
        id: session_id,
    }
}

/// Sample sponsor form payload used by dashboard group sponsors tests.
pub(crate) fn sample_sponsor_form() -> Sponsor {
    Sponsor {
        logo_url: "https://example.test/logo.png".to_string(),
        name: "Example".to_string(),

        website_url: Some("https://example.test".to_string()),
    }
}

/// Sample team member listing entry.
pub(crate) fn sample_team_member(accepted: bool) -> GroupTeamMember {
    GroupTeamMember {
        accepted,
        user_id: Uuid::new_v4(),
        username: "team-member".to_string(),

        company: Some("Example".to_string()),
        name: Some("Team Member".to_string()),
        photo_url: Some("https://example.test/photo.png".to_string()),
        role: Some(GroupRole::Organizer),
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
