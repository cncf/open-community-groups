//! HTTP handlers for the group site.

use askama::Template;
use axum::{
    Json,
    extract::{Path, State},
    http::{StatusCode, Uri},
    response::{Html, IntoResponse},
};
use chrono::Duration;
use serde_json::json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    auth::AuthSession,
    config::HttpServerConfig,
    db::DynDB,
    handlers::prepare_headers,
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::{
        PageId,
        auth::User,
        group::{self, Page},
        notifications::GroupWelcome,
    },
    types::event::EventKind,
};

use super::{error::HandlerError, extractors::CommunityId};

// Pages handlers.

/// Handler that renders the group home page.
#[instrument(skip_all)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path(group_slug): Path<String>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let event_kinds = vec![EventKind::InPerson, EventKind::Virtual, EventKind::Hybrid];
    let (community, group, upcoming_events, past_events) = tokio::try_join!(
        db.get_community(community_id),
        db.get_group(community_id, &group_slug),
        db.get_group_upcoming_events(community_id, &group_slug, event_kinds.clone(), 9),
        db.get_group_past_events(community_id, &group_slug, event_kinds, 9)
    )?;
    let template = Page {
        community,
        group,
        page_id: PageId::Group,
        past_events: past_events
            .into_iter()
            .map(|event| group::PastEventCard { event })
            .collect(),
        path: uri.path().to_string(),
        upcoming_events: upcoming_events
            .into_iter()
            .map(|event| group::UpcomingEventCard { event })
            .collect(),
        user: User::default(),
    };

    // Prepare response headers
    let headers = prepare_headers(Duration::hours(1), &[])?;

    Ok((headers, Html(template.render()?)))
}

// Actions handlers.

/// Handler for joining a group.
#[instrument(skip_all)]
pub(crate) async fn join_group(
    auth_session: AuthSession,
    State(cfg): State<HttpServerConfig>,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    CommunityId(community_id): CommunityId,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Join the group
    db.join_group(community_id, group_id, user.user_id).await?;

    // Enqueue welcome to group notification
    let group = db.get_group_summary(community_id, group_id).await?;
    let base_url = cfg.base_url.strip_suffix('/').unwrap_or(&cfg.base_url);
    let template_data = GroupWelcome {
        link: format!("{}/group/{}", base_url, group.slug),
        group,
    };
    let notification = NewNotification {
        kind: NotificationKind::GroupWelcome,
        recipients: vec![user.user_id],
        template_data: Some(serde_json::to_value(&template_data)?),
    };
    notifications_manager.enqueue(&notification).await?;

    Ok(StatusCode::NO_CONTENT)
}

/// Handler for leaving a group.
#[instrument(skip_all)]
pub(crate) async fn leave_group(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Leave the group
    db.leave_group(community_id, group_id, user.user_id).await?;

    Ok(StatusCode::NO_CONTENT)
}

/// Handler for checking group membership status.
#[instrument(skip_all)]
pub(crate) async fn membership_status(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Check membership
    let is_member = db.is_group_member(community_id, group_id, user.user_id).await?;

    Ok(Json(json!({
        "is_member": is_member
    })))
}

// Tests.

#[cfg(test)]
mod tests {
    use std::collections::{BTreeMap, HashMap};

    use anyhow::anyhow;
    use axum::{
        body::{Body, to_bytes},
        http::{
            HeaderValue, Request, StatusCode,
            header::{CACHE_CONTROL, CONTENT_TYPE, COOKIE, HOST},
        },
    };
    use axum_login::tower_sessions::session;
    use chrono::{TimeZone, Utc};
    use chrono_tz::UTC;
    use serde_json::{from_slice, json};
    use time::{Duration as TimeDuration, OffsetDateTime};
    use tower::ServiceExt;
    use uuid::Uuid;

    use crate::{
        auth::User as AuthUser,
        db::mock::MockDB,
        router::setup_test_router,
        services::notifications::{MockNotificationsManager, NotificationKind},
        templates::{common::User as TemplateUser, notifications::GroupWelcome},
        types::{
            community::{Community, Theme},
            event::{EventDetailed, EventKind, EventSummary},
            group::{GroupCategory, GroupFull, GroupSummary},
        },
    };

    #[tokio::test]
    async fn test_page_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community()
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community(community_id)));
        db.expect_get_group()
            .withf(move |id, slug| *id == community_id && slug == "test-group")
            .returning(move |_, _| Ok(sample_group(group_id)));
        db.expect_get_group_upcoming_events()
            .withf(move |id, slug, kinds, limit| {
                *id == community_id
                    && slug == "test-group"
                    && kinds == &vec![EventKind::InPerson, EventKind::Virtual, EventKind::Hybrid]
                    && *limit == 9
            })
            .returning(move |_, _, _, _| Ok(vec![sample_event_detailed(event_id)]));
        db.expect_get_group_past_events()
            .withf(move |id, slug, kinds, limit| {
                *id == community_id
                    && slug == "test-group"
                    && kinds == &vec![EventKind::InPerson, EventKind::Virtual, EventKind::Hybrid]
                    && *limit == 9
            })
            .returning(move |_, _, _, _| Ok(vec![sample_event_summary(event_id)]));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/group/test-group")
            .header(HOST, "example.test")
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::OK);
        assert_eq!(
            parts.headers.get(CONTENT_TYPE).unwrap(),
            &HeaderValue::from_static("text/html; charset=utf-8")
        );
        assert_eq!(
            parts.headers.get(CACHE_CONTROL).unwrap(),
            &HeaderValue::from_static("max-age=0")
        );
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_page_db_error() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community()
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community(community_id)));
        db.expect_get_group()
            .withf(move |id, slug| *id == community_id && slug == "test-group")
            .returning(move |_, _| Err(anyhow!("db error")));
        db.expect_get_group_upcoming_events()
            .withf(move |id, slug, kinds, limit| {
                *id == community_id
                    && slug == "test-group"
                    && kinds == &vec![EventKind::InPerson, EventKind::Virtual, EventKind::Hybrid]
                    && *limit == 9
            })
            .returning(move |_, _, _, _| Ok(vec![sample_event_detailed(event_id)]));
        db.expect_get_group_past_events()
            .withf(move |id, slug, kinds, limit| {
                *id == community_id
                    && slug == "test-group"
                    && kinds == &vec![EventKind::InPerson, EventKind::Virtual, EventKind::Hybrid]
                    && *limit == 9
            })
            .returning(move |_, _, _, _| Ok(vec![sample_event_summary(event_id)]));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/group/test-group")
            .header(HOST, "example.test")
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_join_group_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_join_group()
            .withf(move |id, gid, uid| *id == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(()));
        db.expect_get_group_summary()
            .withf(move |cid, gid| *cid == community_id && *gid == group_id)
            .returning(move |_, _| Ok(sample_group_summary(group_id)));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue()
            .withf(move |notification| {
                matches!(notification.kind, NotificationKind::GroupWelcome)
                    && notification.recipients == vec![user_id]
                    && notification.template_data.as_ref().is_some_and(|data| {
                        serde_json::from_value::<GroupWelcome>(data.clone())
                            .map(|welcome| {
                                welcome.group.group_id == group_id && welcome.link == "/group/test-group"
                            })
                            .unwrap_or(false)
                    })
            })
            .returning(|_| Box::pin(async { Ok(()) }));

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("POST")
            .uri(format!("/group/{group_id}/join"))
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::NO_CONTENT);
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_leave_group_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_leave_group()
            .withf(move |id, gid, uid| *id == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("DELETE")
            .uri(format!("/group/{group_id}/leave"))
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::NO_CONTENT);
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_membership_status_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_is_group_member()
            .withf(move |id, gid, uid| *id == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri(format!("/group/{group_id}/membership"))
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::OK);
        assert_eq!(
            parts.headers.get(CONTENT_TYPE).unwrap(),
            &HeaderValue::from_static("application/json")
        );
        assert_eq!(
            parts.headers.get(CACHE_CONTROL).unwrap(),
            &HeaderValue::from_static("max-age=0")
        );
        let body: serde_json::Value = from_slice(&bytes).unwrap();
        assert_eq!(body, json!({ "is_member": true }));
    }

    // Helpers

    /// Helper to create a sample community for tests.
    fn sample_community(community_id: Uuid) -> Community {
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

    /// Helper to create a sample group for tests.
    fn sample_group(group_id: Uuid) -> GroupFull {
        GroupFull {
            active: true,
            category: GroupCategory {
                group_category_id: group_id,
                name: "Cloud Native".to_string(),
                normalized_name: "cloud-native".to_string(),
                order: Some(1),
            },
            color: "#336699".to_string(),
            created_at: Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap(),
            group_id,
            members_count: 42,
            name: "Test Group".to_string(),
            organizers: vec![sample_template_user()],
            slug: "test-group".to_string(),
            city: Some("San Francisco".to_string()),
            country_code: Some("US".to_string()),
            country_name: Some("United States".to_string()),
            description: Some("A test group".to_string()),
            description_short: Some("Test group".to_string()),
            latitude: Some(37.0),
            logo_url: Some("https://example.test/logo.png".to_string()),
            longitude: Some(-122.0),
            state: Some("CA".to_string()),
            ..Default::default()
        }
    }

    /// Helper to create a sample group summary for tests.
    fn sample_group_summary(group_id: Uuid) -> GroupSummary {
        GroupSummary {
            active: true,
            category: GroupCategory {
                group_category_id: group_id,
                name: "Cloud Native".to_string(),
                normalized_name: "cloud-native".to_string(),
                order: Some(1),
            },
            color: "#336699".to_string(),
            created_at: Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap(),
            group_id,
            name: "Test Group".to_string(),
            slug: "test-group".to_string(),
            city: Some("San Francisco".to_string()),
            country_code: Some("US".to_string()),
            country_name: Some("United States".to_string()),
            logo_url: Some("https://example.test/logo.png".to_string()),
            state: Some("CA".to_string()),
            ..Default::default()
        }
    }

    /// Helper to create a sample detailed event for tests.
    fn sample_event_detailed(event_id: Uuid) -> EventDetailed {
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
            ends_at: Some(Utc.with_ymd_and_hms(2024, 1, 1, 13, 0, 0).unwrap()),
            group_city: Some("San Francisco".to_string()),
            group_country_code: Some("US".to_string()),
            group_country_name: Some("United States".to_string()),
            group_state: Some("CA".to_string()),
            latitude: Some(37.0),
            logo_url: Some("https://example.test/logo.png".to_string()),
            longitude: Some(-122.0),
            starts_at: Some(Utc.with_ymd_and_hms(2024, 1, 1, 12, 0, 0).unwrap()),
            venue_address: Some("123 Main St".to_string()),
            venue_city: Some("San Francisco".to_string()),
            venue_name: Some("Main Venue".to_string()),
            ..Default::default()
        }
    }

    /// Helper to create a sample event summary for tests.
    fn sample_event_summary(event_id: Uuid) -> EventSummary {
        EventSummary::from(sample_event_detailed(event_id))
    }

    /// Helper to create a sample authenticated user for tests.
    fn sample_auth_user(user_id: Uuid, auth_hash: &str) -> AuthUser {
        AuthUser {
            user_id,
            auth_hash: auth_hash.to_string(),
            email: "user@example.test".to_string(),
            email_verified: true,
            name: "Test User".to_string(),
            username: "test-user".to_string(),
            ..Default::default()
        }
    }

    /// Helper to create a sample session record for tests.
    fn sample_session_record(session_id: session::Id, user_id: Uuid, auth_hash: &str) -> session::Record {
        let mut data = HashMap::new();
        data.insert(
            "axum-login.data".to_string(),
            json!({
                "user_id": user_id,
                "auth_hash": auth_hash.as_bytes(),
            }),
        );
        session::Record {
            id: session_id,
            data,
            expiry_date: OffsetDateTime::now_utc().saturating_add(TimeDuration::days(1)),
        }
    }

    /// Helper to create a sample template user for tests.
    fn sample_template_user() -> TemplateUser {
        TemplateUser {
            user_id: Uuid::new_v4(),
            username: "organizer".to_string(),
            name: Some("Organizer".to_string()),
            ..Default::default()
        }
    }
}
