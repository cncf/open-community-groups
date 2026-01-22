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
    auth::User as AuthUser,
    config::HttpServerConfig,
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
    },
    templates::{
        common::User as TemplateUser,
        dashboard::{
            community::{
                analytics::{AttendeesStats, CommunityStats, EventsStats, GroupsStats, MembersStats},
                groups::Group,
                settings::CommunityUpdate,
                team::CommunityTeamMember,
            },
            group::{
                analytics::{GroupAttendeesStats, GroupEventsStats, GroupMembersStats, GroupStats},
                attendees::Attendee,
                events::{Event as GroupEventForm, GroupEvents},
                home::UserGroupsByCommunity,
                members::GroupMember,
                settings::GroupUpdate,
                sponsors::Sponsor,
                team::GroupTeamMember,
            },
            user::invitations::{CommunityTeamInvitation, GroupTeamInvitation},
        },
    },
    types::{
        community::{CommunityFull, CommunitySummary},
        event::{EventCategory, EventFull, EventKind, EventKindSummary, EventSummary, SessionKindSummary},
        group::{
            GroupCategory, GroupFull, GroupRegion, GroupRole, GroupRoleSummary, GroupSponsor, GroupSummary,
        },
        site::{SiteSettings, Theme},
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
        checked_in: true,
        created_at: Utc.with_ymd_and_hms(2024, 1, 1, 12, 0, 0).unwrap(),
        username: "attendee".to_string(),

        checked_in_at: Some(Utc.with_ymd_and_hms(2024, 1, 1, 13, 0, 0).unwrap()),
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
        banner_mobile_url: "https://example.test/banner_mobile.png".to_string(),
        banner_url: "https://example.test/banner.png".to_string(),
        description: "Updated description".to_string(),
        display_name: "Test".to_string(),
        logo_url: "https://example.test/logo.png".to_string(),
        ..Default::default()
    }
}

/// Sample community stats used in analytics tests.
pub(crate) fn sample_community_stats() -> CommunityStats {
    CommunityStats {
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
        color: "#336699".to_string(),
        community: sample_community_summary(community_id),
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
        slug: "abc1234".to_string(),
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
        venue_country_code: Some("US".to_string()),
        venue_country_name: Some("United States".to_string()),
        venue_name: Some("Main Venue".to_string()),
        venue_state: Some("CA".to_string()),
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
        community_display_name: "Test Community".to_string(),
        community_name: "test-community".to_string(),
        event_id,
        group_category_name: "Meetup".to_string(),
        group_color: "#123456".to_string(),
        group_name: "Test Group".to_string(),
        group_slug: "def5678".to_string(),
        kind: EventKind::Virtual,
        name: "Sample Event".to_string(),
        published: true,
        slug: "ghi9abc".to_string(),
        timezone: UTC,

        capacity: None,
        description_short: Some("A brief summary of the sample event".to_string()),
        ends_at: Some(starts_at + chrono::Duration::hours(2)),
        latitude: Some(42.3601),
        logo_url: Some("https://example.test/logo.png".to_string()),
        longitude: Some(-71.0589),
        meeting_join_url: Some("https://example.test/meeting".to_string()),
        meeting_password: None,
        meeting_provider: None,
        popover_html: None,
        remaining_capacity: None,
        starts_at: Some(starts_at),
        venue_address: Some("456 Sample Rd".to_string()),
        venue_city: Some("Boston".to_string()),
        venue_country_code: Some("US".to_string()),
        venue_country_name: Some("United States".to_string()),
        venue_name: Some("Sample Venue".to_string()),
        venue_state: Some("MA".to_string()),
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
        group_category_id: Uuid::new_v4(),
        name: "Meetup".to_string(),
        normalized_name: "meetup".to_string(),
        order: Some(1),
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
        slug: "jkm2345".to_string(),
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
        community_name: "test-community".to_string(),
        group_id,
        group_name: "Test Group".to_string(),
        role: GroupRole::Organizer,
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

/// Sample group region definition reused across tests.
pub(crate) fn sample_group_region() -> GroupRegion {
    GroupRegion {
        name: "North America".to_string(),
        normalized_name: "north-america".to_string(),
        order: Some(1),
        region_id: Uuid::new_v4(),
    }
}

/// Sample group stats used in analytics tests.
pub(crate) fn sample_group_stats() -> GroupStats {
    GroupStats {
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
        community_display_name: "Test Community".to_string(),
        community_name: "test-community".to_string(),
        created_at: Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap(),
        group_id,
        name: "Test Group".to_string(),
        slug: "npq6789".to_string(),

        banner_mobile_url: Some("https://example.test/banner_mobile.png".to_string()),
        banner_url: Some("https://example.test/banner.png".to_string()),
        city: Some("San Francisco".to_string()),
        country_code: Some("US".to_string()),
        country_name: Some("United States".to_string()),
        description_short: Some("An example summary for the sample group".to_string()),
        latitude: Some(37.0),
        logo_url: Some("https://example.test/logo.png".to_string()),
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

/// Sample template user with a specific user ID.
pub(crate) fn sample_template_user_with_id(user_id: Uuid) -> TemplateUser {
    TemplateUser {
        user_id,
        username: "speaker".to_string(),

        name: Some("Speaker".to_string()),
        ..Default::default()
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
        groups: vec![sample_group_summary(group_id)],
    }]
}

/// Builder for test router configuration.
pub(crate) struct TestRouterBuilder {
    db: MockDB,
    image_storage: Option<MockImageStorage>,
    meetings_cfg: Option<crate::config::MeetingsConfig>,
    nm: MockNotificationsManager,
    server_cfg: Option<HttpServerConfig>,
}

impl TestRouterBuilder {
    /// Creates a new test router builder with required dependencies.
    pub(crate) fn new(db: MockDB, nm: MockNotificationsManager) -> Self {
        Self {
            db,
            image_storage: None,
            meetings_cfg: None,
            nm,
            server_cfg: None,
        }
    }

    /// Builds the application router with the configured options.
    pub(crate) async fn build(self) -> Router {
        let db: DynDB = Arc::new(self.db);
        let is: DynImageStorage = Arc::new(self.image_storage.unwrap_or_default());
        let nm: DynNotificationsManager = Arc::new(self.nm);
        let server_cfg = self.server_cfg.unwrap_or_default();

        router::setup(db, is, self.meetings_cfg, nm, &server_cfg)
            .await
            .expect("router setup should succeed")
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

    /// Sets a custom server configuration.
    pub(crate) fn with_server_cfg(mut self, cfg: HttpServerConfig) -> Self {
        self.server_cfg = Some(cfg);
        self
    }
}
