//! Shared router, request, session and permission helpers and sample data
//! builders for handlers tests.

use std::{
    collections::{BTreeMap, HashMap},
    sync::{Arc, LazyLock},
};

use axum::{
    Router,
    body::{Body, Bytes, to_bytes},
    http::{
        HeaderValue, Request, StatusCode,
        header::{CONTENT_TYPE, COOKIE},
        request::Builder as RequestBuilder,
        response::Parts,
    },
};
use axum_login::tower_sessions::{Session, session};
use chrono::{DateTime, TimeZone, Utc};
use serde_json::json;
use time::{Duration as TimeDuration, OffsetDateTime};
use tokio_util::sync::CancellationToken;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    activity_tracker::DynActivityTracker,
    auth::User as AuthUser,
    config::{BadgesConfig, HttpServerConfig, PaymentsConfig},
    db::{DynDB, mock::MockDB},
    handlers::auth::session_context::{SELECTED_COMMUNITY_ID_KEY, SELECTED_GROUP_ID_KEY},
    router,
    services::{
        blocking::BlockingExecutor,
        enrollment::{DynEnrollmentManager, MockEnrollmentManager},
        events::{DynEventsManager, MockEventsManager},
        images::{DynImageStorage, MockImageStorage},
        inbox::{DynInboxManager, MockInboxManager},
        notifications::{DynNotificationsManager, MockNotificationsManager},
        payments::{DynPaymentsManager, MockPaymentsManager},
    },
    types::{
        analytics::PageViewsStats,
        community::{CommunityFull, CommunityRole, CommunityRoleSummary, CommunitySummary},
        dashboard::{
            common::{AuditLogRecord, AuditLogsOutput},
            community::{
                analytics::{
                    CommunityAttendeesStats, CommunityDashboardStats, CommunityMembersStats,
                    CommunityPageViewsStats, EventsStats, GroupsStats,
                },
                groups::GroupInput,
                settings::CommunityUpdate,
                team::CommunityTeamMember,
            },
            group::{
                analytics::{
                    GroupAttendeesStats, GroupDashboardStats, GroupEventsStats, GroupMembersStats,
                    GroupPageViewsStats,
                },
                attendees::Attendee,
                events::GroupEvents,
                home::UserGroupsByCommunity,
                invitation_requests::InvitationRequest,
                members::GroupMember,
                sponsors::SponsorInput,
                submissions::CfsSubmission as GroupCfsSubmission,
                team::GroupTeamMember,
                waitlist::WaitlistEntry,
            },
            user::{
                invitations::{CommunityTeamInvitation, GroupTeamInvitation},
                session_proposals::{
                    PendingCoSpeakerInvitation, SessionProposal as UserSessionProposal,
                    SessionProposalLevel as UserSessionProposalLevel,
                },
                submissions::CfsSubmission as UserCfsSubmission,
            },
        },
        event::{
            CfsSessionProposal, EventCategory, EventKindSummary, EventMinimal, SessionKindSummary,
            SessionProposal as EventSessionProposal,
        },
        group::{GroupFull, GroupMinimal, GroupRole, GroupRoleSummary, GroupSponsor},
        permissions::{CommunityPermission, GroupPermission},
        search::{BBox, SearchEventsOutput, SearchGroupsOutput},
        tests::sample_event_minimal,
        user::User as TemplateUser,
    },
};

pub(crate) use crate::{
    config::tests::{
        sample_badges_cfg, sample_payments_cfg, sample_server_cfg, sample_zoom_meetings_cfg,
    },
    types::tests::{
        sample_community_summary, sample_enrollment_state, sample_event_analytics,
        sample_event_cohost_group, sample_event_form, sample_event_full, sample_event_invitation,
        sample_event_purchase_summary, sample_event_summary, sample_event_survey_full,
        sample_event_survey_summary, sample_event_utm_allowlist, sample_group_category,
        sample_group_minimal, sample_group_payment_recipient, sample_group_region,
        sample_group_summary, sample_inbox_conversation, sample_inbox_conversation_summary,
        sample_site_settings, sample_user_event, sample_user_event_survey,
        sample_user_event_survey_item, sample_user_search_result, sample_user_summary,
    },
};

// Helpers.

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

// Expectations helpers.

/// Assert an empty HTMX location response with the expected status.
pub(crate) fn assert_empty_hx_location_response(
    parts: &Parts,
    bytes: &[u8],
    status: StatusCode,
    location: &str,
) {
    assert_empty_response(parts, bytes, status);
    assert_eq!(
        parts.headers.get("HX-Location").and_then(|value| value.to_str().ok()),
        Some(location),
    );
}

/// Assert an empty HTMX redirect response with the expected status.
pub(crate) fn assert_empty_hx_redirect_response(
    parts: &Parts,
    bytes: &[u8],
    status: StatusCode,
    redirect: &'static str,
) {
    assert_empty_response(parts, bytes, status);
    assert_eq!(
        parts.headers.get("HX-Redirect"),
        Some(&HeaderValue::from_static(redirect)),
    );
}

/// Assert an empty HTMX trigger response with the expected status.
pub(crate) fn assert_empty_hx_trigger_response(
    parts: &Parts,
    bytes: &[u8],
    status: StatusCode,
    trigger: &'static str,
) {
    assert_empty_response(parts, bytes, status);
    assert_eq!(
        parts.headers.get("HX-Trigger"),
        Some(&HeaderValue::from_static(trigger)),
    );
}

/// Assert an empty response with the expected status.
pub(crate) fn assert_empty_response(parts: &Parts, bytes: &[u8], status: StatusCode) {
    assert_eq!(parts.status, status);
    assert!(
        bytes.is_empty(),
        "response body should be empty, got {:?}",
        String::from_utf8_lossy(bytes)
    );
}

/// Assert an HTML response with the expected status.
pub(crate) fn assert_html_response(parts: &Parts, bytes: &[u8], status: StatusCode) {
    assert_eq!(parts.status, status);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE),
        Some(&HeaderValue::from_static("text/html; charset=utf-8")),
    );
    assert!(!bytes.is_empty(), "response body should not be empty");
}

/// Assert a non-empty response with the expected status.
pub(crate) fn assert_non_empty_response(parts: &Parts, bytes: &[u8], status: StatusCode) {
    assert_eq!(parts.status, status);
    assert!(!bytes.is_empty(), "response body should not be empty");
}

/// Expect an authenticated community session granted the permission.
pub(crate) fn expect_community_access(
    db: &mut MockDB,
    ids: &DashboardIds,
    permission: CommunityPermission,
) {
    expect_community_session(db, ids);
    expect_community_permission_result(db, ids, permission, true);
}

/// Expect one community permission check that returns `allowed`.
pub(crate) fn expect_community_permission_result(
    db: &mut MockDB,
    ids: &DashboardIds,
    permission: CommunityPermission,
    allowed: bool,
) {
    let ids = *ids;
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |community_id, user_id, requested_permission| {
            *community_id == ids.community_id
                && *user_id == ids.user_id
                && *requested_permission == permission
        })
        .returning(move |_, _, _| Ok(allowed));
}

/// Expect an authenticated session scoped to the community of the identifiers.
pub(crate) fn expect_community_session(db: &mut MockDB, ids: &DashboardIds) {
    expect_session_record(
        db,
        ids.session_id,
        ids.user_id,
        Some(ids.community_id),
        None,
    );
}

/// Expect an authenticated group session granted the permission.
pub(crate) fn expect_group_access(
    db: &mut MockDB,
    ids: &DashboardIds,
    permission: GroupPermission,
) {
    expect_group_session(db, ids);
    expect_group_permission_result(db, ids, permission, true);
}

/// Expect one group permission check that returns `allowed`.
pub(crate) fn expect_group_permission_result(
    db: &mut MockDB,
    ids: &DashboardIds,
    permission: GroupPermission,
    allowed: bool,
) {
    let ids = *ids;
    db.expect_user_has_group_permission()
        .times(1)
        .withf(
            move |community_id, group_id, user_id, requested_permission| {
                *community_id == ids.community_id
                    && *group_id == ids.group_id
                    && *user_id == ids.user_id
                    && *requested_permission == permission
            },
        )
        .returning(move |_, _, _, _| Ok(allowed));
}

/// Expect an authenticated session scoped to the group of the identifiers.
pub(crate) fn expect_group_session(db: &mut MockDB, ids: &DashboardIds) {
    expect_session_record(
        db,
        ids.session_id,
        ids.user_id,
        Some(ids.community_id),
        Some(ids.group_id),
    );
}

/// Expects the session and community reads every signed-in public route
/// performs.
pub(crate) fn expect_member_context(db: &mut MockDB, ids: &DashboardIds) {
    expect_session(db, ids);
    expect_test_community(db, ids.community_id);
}

/// Expect an authenticated session of the identifiers without a selected
/// dashboard scope.
pub(crate) fn expect_session(db: &mut MockDB, ids: &DashboardIds) {
    expect_session_record(db, ids.session_id, ids.user_id, None, None);
}

/// Expect an authenticated session of the identifiers, without a selected
/// dashboard scope, whose user lookup returns `user`.
///
/// `user` must carry the `"hash"` auth hash, e.g. built from
/// [`sample_auth_user`].
pub(crate) fn expect_session_with_user(db: &mut MockDB, ids: &DashboardIds, user: AuthUser) {
    let session_record = sample_session_record(ids.session_id, ids.user_id, "hash", None, None);
    expect_session_user_lookup(db, session_record, user);
}

/// Expect the session read to return the stored record, without a user lookup.
pub(crate) fn expect_stored_session(db: &mut MockDB, session_record: session::Record) {
    let session_id = session_record.id;
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
}

/// Expects the test community to resolve to the given identifier.
pub(crate) fn expect_test_community(db: &mut MockDB, community_id: Uuid) {
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));
}

/// Expect the session read and user lookup of an authenticated request.
fn expect_session_record(
    db: &mut MockDB,
    session_id: session::Id,
    user_id: Uuid,
    selected_community_id: Option<Uuid>,
    selected_group_id: Option<Uuid>,
) {
    let session_record = sample_session_record(
        session_id,
        user_id,
        "hash",
        selected_community_id,
        selected_group_id,
    );
    expect_session_user_lookup(db, session_record, sample_auth_user(user_id, "hash"));
}

/// Expect the session read returning the record and the lookup of its user.
fn expect_session_user_lookup(db: &mut MockDB, session_record: session::Record, user: AuthUser) {
    let session_id = session_record.id;
    let user_id = user.user_id;
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(user.clone())));
}

// Request helpers.

/// Content type of form-encoded request bodies.
const FORM_CONTENT_TYPE: &str = "application/x-www-form-urlencoded";

/// Start a request builder that carries the session cookie.
pub(crate) fn authenticated_request(
    method: &str,
    uri: &str,
    session_id: session::Id,
) -> RequestBuilder {
    request(method, uri).header(COOKIE, format!("id={session_id}"))
}

/// Build an authenticated request with an empty body.
pub(crate) fn empty_request(method: &str, uri: &str, session_id: session::Id) -> Request<Body> {
    authenticated_request(method, uri, session_id)
        .body(Body::empty())
        .unwrap()
}

/// Build an authenticated form-encoded request.
pub(crate) fn form_request(
    method: &str,
    uri: &str,
    session_id: session::Id,
    body: impl Into<Body>,
) -> Request<Body> {
    authenticated_request(method, uri, session_id)
        .header(CONTENT_TYPE, FORM_CONTENT_TYPE)
        .body(body.into())
        .unwrap()
}

/// Build an authenticated GET request with an empty body.
pub(crate) fn get_request(uri: &str, session_id: session::Id) -> Request<Body> {
    empty_request("GET", uri, session_id)
}

/// Build an authenticated JSON request.
pub(crate) fn json_request(
    method: &str,
    uri: &str,
    session_id: session::Id,
    body: &serde_json::Value,
) -> Request<Body> {
    authenticated_request(method, uri, session_id)
        .header(CONTENT_TYPE, "application/json")
        .body(Body::from(body.to_string()))
        .unwrap()
}

/// Start a request builder without a session cookie.
pub(crate) fn request(method: &str, uri: &str) -> RequestBuilder {
    Request::builder().method(method).uri(uri)
}

/// Send the request through the router and return the response parts and body.
pub(crate) async fn send(router: Router, request: Request<Body>) -> (Parts, Bytes) {
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    (parts, bytes)
}

// Sample data helpers.

/// Sample attendee used in dashboard group home tests.
pub(crate) fn sample_attendee() -> Attendee {
    let user_id = Uuid::new_v4();

    Attendee {
        can_receive_attendee_email: true,
        checked_in: true,
        created_at: Utc.with_ymd_and_hms(2024, 1, 1, 12, 0, 0).unwrap(),
        email: "attendee@example.test".to_string(),
        enrollment_status:
            crate::types::dashboard::group::attendees::AttendeeEnrollmentStatus::Confirmed,
        manually_invited: false,
        user: sample_dashboard_user_profile(
            user_id,
            "attendee",
            Some("Event Attendee"),
            Some("https://example.test/avatar.png"),
            Some("Engineer"),
            Some("Example"),
        ),

        admission_offer_id: None,
        admission_offer_source: None,
        admission_offer_status: None,
        amount_minor: None,
        charge_model: None,
        checked_in_at: Some(Utc.with_ymd_and_hms(2024, 1, 1, 13, 0, 0).unwrap()),
        completed_at: None,
        currency_code: None,
        discount_code: None,
        event_purchase_id: None,
        event_ticket_type_id: None,
        external_payment_deadline: None,
        external_payment_details: None,
        external_payment_marked_by: None,
        external_payment_reference: None,
        externally_paid: false,
        offer_expires_at: None,
        refund_payment_job_id: None,
        refund_progress: None,
        refund_request_status: None,
        registration_answers: None,
        ticket_title: None,
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
        registration_status: "registered".to_string(),
        user_id,
        username: "test-user".to_string(),

        belongs_to_any_group_team: Some(true),
        has_password: Some(true),
        ..Default::default()
    }
}

/// Sample bounding box output used by explore handlers.
fn sample_bbox() -> BBox {
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
        created_at: DateTime::UNIX_EPOCH,
        description: "Test community".to_string(),
        display_name: "Test".to_string(),
        group_team_management_restricted: false,
        logo_url: "/static/images/placeholder_cncf.png".to_string(),
        name: "test".to_string(),
        ..Default::default()
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
        attendees: CommunityAttendeesStats {
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
            per_month_by_category: HashMap::from([(
                "dev".to_string(),
                vec![("2024-01".to_string(), 2)],
            )]),
            per_month_by_region: HashMap::new(),
            running_total: vec![(1, 2)],
            running_total_by_category: HashMap::new(),
            running_total_by_region: HashMap::new(),
            total: 2,
            total_by_category: vec![("dev".to_string(), 2)],
            total_by_region: vec![],
        },
        members: CommunityMembersStats {
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
            community: PageViewsStats {
                per_day_views: vec![("2024-01-10".to_string(), 2), ("2024-01-20".to_string(), 2)],
                per_month_views: vec![("2024-01".to_string(), 4)],
                total_views: 4,
            },
            events: PageViewsStats {
                per_day_views: vec![("2024-01-11".to_string(), 5), ("2024-01-21".to_string(), 7)],
                per_month_views: vec![("2024-01".to_string(), 12)],
                total_views: 12,
            },
            groups: PageViewsStats {
                per_day_views: vec![("2024-01-12".to_string(), 4), ("2024-01-22".to_string(), 5)],
                per_month_views: vec![("2024-01".to_string(), 9)],
                total_views: 9,
            },
            total: PageViewsStats {
                per_day_views: vec![
                    ("2024-01-10".to_string(), 2),
                    ("2024-01-11".to_string(), 5),
                    ("2024-01-12".to_string(), 4),
                    ("2024-01-20".to_string(), 2),
                    ("2024-01-21".to_string(), 7),
                    ("2024-01-22".to_string(), 5),
                ],
                per_month_views: vec![("2024-01".to_string(), 25)],
                total_views: 25,
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
        group_team_management_restricted: false,
        logo_url: "https://example.test/logo.png".to_string(),
        ..Default::default()
    }
}

/// Sample public user profile payload used by dashboard row fixtures.
fn sample_dashboard_user_profile(
    user_id: Uuid,
    username: &str,
    name: Option<&str>,
    photo_url: Option<&str>,
    title: Option<&str>,
    company: Option<&str>,
) -> TemplateUser {
    TemplateUser {
        user_id,
        username: username.to_string(),

        bio: None,
        bluesky_url: None,
        company: company.map(str::to_string),
        facebook_url: None,
        github_url: None,
        linkedin_url: None,
        name: name.map(str::to_string),
        photo_url: photo_url.map(str::to_string),
        provider: None,
        title: title.map(str::to_string),
        twitter_url: None,
        website_url: None,
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

/// Sample event kind summary for drop-downs.
pub(crate) fn sample_event_kind_summary() -> EventKindSummary {
    EventKindSummary {
        display_name: "Virtual".to_string(),
        event_kind_id: "virtual".to_string(),
    }
}

/// Sample filters options for explore page tests.
pub(crate) fn sample_filters_options() -> crate::types::site::explore::FiltersOptions {
    crate::types::site::explore::FiltersOptions::default()
}

/// Sample CFS session proposal used in group dashboard tests.
fn sample_group_cfs_session_proposal(session_proposal_id: Uuid) -> CfsSessionProposal {
    CfsSessionProposal {
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

/// Sample group events aggregation for dashboard pages.
pub(crate) fn sample_group_events(event_id: Uuid) -> GroupEvents {
    let summary = sample_event_summary(event_id);
    GroupEvents {
        past: crate::types::dashboard::group::events::PaginatedEvents {
            events: vec![summary.clone()],
            total: 1,
        },
        upcoming: crate::types::dashboard::group::events::PaginatedEvents {
            events: vec![summary],
            total: 1,
        },
    }
}

/// Sample group form payload for community dashboard tests.
pub(crate) fn sample_group_form(category_id: Uuid) -> GroupInput {
    GroupInput {
        category_id,
        description: "Group description".to_string(),
        name: "Test Group".to_string(),

        description_short: Some("Short group description".to_string()),
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

/// Sample group stats used in analytics tests.
pub(crate) fn sample_group_stats() -> GroupDashboardStats {
    GroupDashboardStats {
        attendees: GroupAttendeesStats {
            per_month: vec![("2024-01".to_string(), 5)],
            running_total: vec![(1, 5)],
            total: 5,
        },
        cohosted_events: GroupEventsStats {
            per_month: vec![("2024-02".to_string(), 1)],
            running_total: vec![(1, 1)],
            total: 1,
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
            events: PageViewsStats {
                per_day_views: vec![("2024-01-10".to_string(), 3), ("2024-01-20".to_string(), 4)],
                per_month_views: vec![("2024-01".to_string(), 7)],
                total_views: 7,
            },
            group: PageViewsStats {
                per_day_views: vec![("2024-01-11".to_string(), 1), ("2024-01-21".to_string(), 3)],
                per_month_views: vec![("2024-01".to_string(), 4)],
                total_views: 4,
            },
            total: PageViewsStats {
                per_day_views: vec![
                    ("2024-01-10".to_string(), 3),
                    ("2024-01-11".to_string(), 1),
                    ("2024-01-20".to_string(), 4),
                    ("2024-01-21".to_string(), 3),
                ],
                per_month_views: vec![("2024-01".to_string(), 11)],
                total_views: 11,
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

/// Sample group update payload for dashboard group settings.
pub(crate) fn sample_group_update() -> GroupInput {
    GroupInput {
        category_id: Uuid::new_v4(),
        description: "Updated description".to_string(),
        name: "Updated Group".to_string(),

        banner_url: Some("https://example.test/banner.png".to_string()),
        city: Some("Test City".to_string()),
        country_code: Some("US".to_string()),
        country_name: Some("United States".to_string()),
        description_short: Some("Updated short description".to_string()),
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

/// Sample invitation request used in dashboard group invitation request tests.
pub(crate) fn sample_invitation_request() -> InvitationRequest {
    let user_id = Uuid::new_v4();

    InvitationRequest {
        created_at: Utc.with_ymd_and_hms(2024, 1, 1, 12, 0, 0).unwrap(),
        invitation_request_status: crate::types::event::EventInvitationRequestStatus::Pending,
        requested_event_ticket_type_id: Some(Uuid::new_v4()),
        requested_ticket_title: Some("General admission".to_string()),
        user: sample_dashboard_user_profile(
            user_id,
            "requesting-user",
            Some("Requesting User"),
            Some("https://example.test/avatar.png"),
            Some("Engineer"),
            Some("Example"),
        ),

        admission_offer_id: None,
        admission_offer_status: None,
        offer_expires_at: None,
        offered_event_ticket_type_id: None,
        offered_ticket_title: None,
        registration_answers: None,
        reviewed_at: None,
    }
}

/// Sample pending co-speaker invitation used in user dashboard tests.
pub(crate) fn sample_pending_co_speaker_invitation(
    session_proposal_id: Uuid,
) -> PendingCoSpeakerInvitation {
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

/// Sample minimal search output for events.
pub(crate) fn sample_search_events_minimal_output(
    event_id: Uuid,
) -> SearchEventsOutput<EventMinimal> {
    SearchEventsOutput {
        events: vec![sample_event_minimal(event_id)],
        total: 1,

        bbox: Some(sample_bbox()),
        truncated: false,
    }
}

/// Sample search output for events.
pub(crate) fn sample_search_events_output(event_id: Uuid) -> SearchEventsOutput {
    SearchEventsOutput {
        events: vec![sample_event_summary(event_id)],
        total: 1,

        bbox: None,
        truncated: false,
    }
}

/// Sample minimal search output for groups.
pub(crate) fn sample_search_groups_minimal_output(
    group_id: Uuid,
) -> SearchGroupsOutput<GroupMinimal> {
    SearchGroupsOutput {
        groups: vec![sample_group_minimal(group_id)],
        total: 1,

        bbox: Some(sample_bbox()),
        truncated: false,
    }
}

/// Sample search output for groups.
pub(crate) fn sample_search_groups_output(group_id: Uuid) -> SearchGroupsOutput {
    SearchGroupsOutput {
        groups: vec![sample_group_summary(group_id)],
        total: 1,

        bbox: None,
        truncated: false,
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

/// Sample site stats for stats page tests.
pub(crate) fn sample_site_stats() -> crate::types::site::stats::SiteStats {
    crate::types::site::stats::SiteStats {
        attendees: crate::types::site::stats::SiteStatsSection {
            per_month: vec![],
            running_total: vec![],
            total: 0,
        },
        events: crate::types::site::stats::SiteStatsSection {
            per_month: vec![],
            running_total: vec![],
            total: 0,
        },
        groups: crate::types::site::stats::SiteStatsSection {
            per_month: vec![],
            running_total: vec![],
            total: 0,
        },
        members: crate::types::site::stats::SiteStatsSection {
            per_month: vec![],
            running_total: vec![],
            total: 0,
        },
    }
}

/// Sample sponsor form payload used by dashboard group sponsors tests.
pub(crate) fn sample_sponsor_form() -> SponsorInput {
    SponsorInput {
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

/// Sample CFS session proposal used in user dashboard tests.
fn sample_user_cfs_session_proposal(session_proposal_id: Uuid) -> CfsSessionProposal {
    CfsSessionProposal {
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
    session_proposal_id: Uuid,
) -> UserCfsSubmission {
    UserCfsSubmission {
        cfs_submission_id,
        created_at: Utc.with_ymd_and_hms(2024, 1, 2, 12, 0, 0).unwrap(),
        event: sample_event_summary(event_id),
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
        ad_banner_link_url: None,
        ad_banner_url: None,
        og_image_url: None,
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
            ad_banner_link_url: None,
            ad_banner_url: None,
            og_image_url: None,
        },
        groups: vec![sample_group_minimal(group_id)],
    }]
}

/// Sample waitlist entry used in dashboard group waitlist tests.
pub(crate) fn sample_waitlist_entry() -> WaitlistEntry {
    let user_id = Uuid::new_v4();

    WaitlistEntry {
        created_at: Utc.with_ymd_and_hms(2024, 1, 1, 12, 0, 0).unwrap(),
        event_ticket_type_id: Uuid::new_v4(),
        ticket_title: "General admission".to_string(),
        user: sample_dashboard_user_profile(
            user_id,
            "waitlisted-user",
            Some("Waitlisted User"),
            Some("https://example.test/avatar.png"),
            Some("Engineer"),
            Some("Example"),
        ),
        admission_offer_id: None,
        admission_offer_status: None,
        offer_expires_at: None,
        waitlist_position: Some(1),
    }
}

/// Returns the community and group currently selected in the session.
pub(crate) async fn selected_ids(session: &Session) -> (Option<Uuid>, Option<Uuid>) {
    let community_id = session.get(SELECTED_COMMUNITY_ID_KEY).await.unwrap();
    let group_id = session.get(SELECTED_GROUP_ID_KEY).await.unwrap();
    (community_id, group_id)
}

/// Checks if the session record contains the selected group ID.
pub(crate) fn session_record_contains_selected_group(
    record: &session::Record,
    group_id: Uuid,
) -> bool {
    record
        .data
        .get(SELECTED_GROUP_ID_KEY)
        .and_then(|value| value.as_str())
        .and_then(|value| value.parse::<Uuid>().ok())
        == Some(group_id)
}

/// Identifiers of an authenticated dashboard request.
///
/// User dashboard tests ignore the community and group identifiers.
#[derive(Clone, Copy, Debug)]
pub(crate) struct DashboardIds {
    /// Community selected in the session.
    pub(crate) community_id: Uuid,
    /// Group selected in the session.
    pub(crate) group_id: Uuid,
    /// Session sent in the request cookie.
    pub(crate) session_id: session::Id,
    /// Authenticated user.
    pub(crate) user_id: Uuid,
}

impl DashboardIds {
    /// Generates fresh identifiers for one test.
    pub(crate) fn new() -> Self {
        Self {
            community_id: Uuid::new_v4(),
            group_id: Uuid::new_v4(),
            session_id: session::Id::default(),
            user_id: Uuid::new_v4(),
        }
    }
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
    let badges_config = server_cfg.badges.as_ref().unwrap_or(&TEST_BADGES_CONFIG);
    router::State {
        activity_tracker: Arc::new(crate::activity_tracker::MockActivityTracker::new()),
        badges_manager: Arc::new(crate::services::badges::SsiBadgesManager::new(
            &server_cfg.base_url,
            badges_config,
        )),
        blocking_executor: BlockingExecutor::new(server_cfg.max_blocking_concurrency()),
        db,
        enrollment_manager: Arc::new(MockEnrollmentManager::new()),
        events_manager: Arc::new(MockEventsManager::new()),
        image_storage,
        inbox_manager: Arc::new(MockInboxManager::new()),
        meetings_cfg: None,
        notifications_manager,
        payments_cfg: None,
        payments_manager: Arc::new(MockPaymentsManager::new()),
        serde_qs_de: router::serde_qs_config(),
        server_cfg: server_cfg.clone(),
        shutdown_drain: CancellationToken::new(),
    }
}

/// Builder for test router configuration.
pub(crate) struct TestRouterBuilder {
    activity_tracker: Option<crate::activity_tracker::MockActivityTracker>,
    db: Box<MockDB>,
    enrollment_manager: Option<MockEnrollmentManager>,
    events_manager: Option<MockEventsManager>,
    image_storage: Option<MockImageStorage>,
    inbox_manager: Option<MockInboxManager>,
    meetings_cfg: Option<crate::config::MeetingsConfig>,
    notifications_manager: Option<MockNotificationsManager>,
    payments_cfg: Option<PaymentsConfig>,
    payments_manager: Option<MockPaymentsManager>,
    server_cfg: Option<HttpServerConfig>,
}

impl TestRouterBuilder {
    /// Creates a new test router builder with the database mock.
    ///
    /// The activity tracker, image storage, notifications manager, and the
    /// enrollment, events, and inbox managers default to mocks without
    /// expectations, which panic on any call. The default payments manager
    /// only answers the configured provider and fiscal sponsor validation.
    pub(crate) fn new(db: MockDB) -> Self {
        Self {
            activity_tracker: None,
            db: Box::new(db),
            enrollment_manager: None,
            events_manager: None,
            image_storage: None,
            inbox_manager: None,
            meetings_cfg: None,
            notifications_manager: None,
            payments_cfg: None,
            payments_manager: None,
            server_cfg: None,
        }
    }

    /// Builds the application router with the configured options.
    pub(crate) async fn build(self) -> Router {
        let db: DynDB = Arc::new(*self.db);
        let activity_tracker: DynActivityTracker =
            Arc::new(self.activity_tracker.unwrap_or_default());
        let is: DynImageStorage = Arc::new(self.image_storage.unwrap_or_default());
        let nm: DynNotificationsManager = Arc::new(self.notifications_manager.unwrap_or_default());
        let mut server_cfg = self.server_cfg.unwrap_or_default();
        server_cfg.badges.get_or_insert_with(|| TEST_BADGES_CONFIG.clone());
        let configured_provider = self.payments_cfg.as_ref().map(PaymentsConfig::provider);
        let payments_manager = self.payments_manager.unwrap_or_else(|| {
            let mut payments_manager = MockPaymentsManager::new();
            payments_manager
                .expect_configured_provider()
                .return_const(configured_provider);
            payments_manager
                .expect_validate_fiscal_sponsor()
                .returning(|_, _| Box::pin(async { Ok(()) }));
            payments_manager
        });
        let payments_manager = Arc::new(payments_manager) as DynPaymentsManager;
        let enrollment_manager =
            Arc::new(self.enrollment_manager.unwrap_or_default()) as DynEnrollmentManager;
        let events_manager = Arc::new(self.events_manager.unwrap_or_default()) as DynEventsManager;
        let inbox_manager = Arc::new(self.inbox_manager.unwrap_or_default()) as DynInboxManager;

        router::setup(
            activity_tracker,
            db,
            enrollment_manager,
            events_manager,
            is,
            inbox_manager,
            self.meetings_cfg,
            self.payments_cfg,
            payments_manager,
            nm,
            &server_cfg,
            CancellationToken::new(),
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

    /// Sets a custom enrollment manager.
    pub(crate) fn with_enrollment_manager(
        mut self,
        enrollment_manager: MockEnrollmentManager,
    ) -> Self {
        self.enrollment_manager = Some(enrollment_manager);
        self
    }

    /// Sets a custom events manager.
    pub(crate) fn with_events_manager(mut self, events_manager: MockEventsManager) -> Self {
        self.events_manager = Some(events_manager);
        self
    }

    /// Sets a custom image storage.
    pub(crate) fn with_image_storage(mut self, is: MockImageStorage) -> Self {
        self.image_storage = Some(is);
        self
    }

    /// Sets a custom inbox manager.
    pub(crate) fn with_inbox_manager(mut self, inbox_manager: MockInboxManager) -> Self {
        self.inbox_manager = Some(inbox_manager);
        self
    }

    /// Sets a custom meetings configuration.
    pub(crate) fn with_meetings_cfg(mut self, cfg: crate::config::MeetingsConfig) -> Self {
        self.meetings_cfg = Some(cfg);
        self
    }

    /// Sets a custom notifications manager.
    pub(crate) fn with_notifications_manager(
        mut self,
        notifications_manager: MockNotificationsManager,
    ) -> Self {
        self.notifications_manager = Some(notifications_manager);
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

/// Shared valid signing configuration for tests outside the badge surface.
static TEST_BADGES_CONFIG: LazyLock<BadgesConfig> = LazyLock::new(sample_badges_cfg);
