//! HTTP handlers for the event page.

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
    db::DynDB,
    handlers::prepare_headers,
    templates::{PageId, auth::User, event::Page},
};

use super::{error::HandlerError, extractors::CommunityId};

// Pages handlers.

/// Handler that renders the event page.
#[instrument(skip_all)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path((group_slug, event_slug)): Path<(String, String)>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (community, event) = tokio::try_join!(
        db.get_community(community_id),
        db.get_event(community_id, &group_slug, &event_slug)
    )?;
    let template = Page {
        community,
        event,
        page_id: PageId::Event,
        path: uri.path().to_string(),
        user: User::default(),
    };

    // Prepare response headers
    let headers = prepare_headers(Duration::hours(1), &[])?;

    Ok((headers, Html(template.render()?)))
}

// Actions handlers.

/// Handler for attending an event.
#[instrument(skip_all)]
pub(crate) async fn attend_event(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Attend event
    db.attend_event(community_id, event_id, user.user_id).await?;

    Ok(StatusCode::NO_CONTENT)
}

/// Handler for checking event attendance status.
#[instrument(skip_all)]
pub(crate) async fn attendance_status(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Check attendance
    let is_attendee = db.is_event_attendee(community_id, event_id, user.user_id).await?;

    Ok(Json(json!({
        "is_attendee": is_attendee
    })))
}

/// Handler for leaving an event.
#[instrument(skip_all)]
pub(crate) async fn leave_event(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Leave event
    db.leave_event(community_id, event_id, user.user_id).await?;

    Ok(StatusCode::NO_CONTENT)
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
    use chrono::{NaiveDate, TimeZone, Utc};
    use chrono_tz::UTC;
    use serde_json::{from_slice, json};
    use time::{Duration as TimeDuration, OffsetDateTime};
    use tower::ServiceExt;
    use uuid::Uuid;

    use crate::{
        auth::User as AuthUser,
        db::mock::MockDB,
        router::setup_test_router,
        services::notifications::MockNotificationsManager,
        templates::common::User as TemplateUser,
        types::{
            community::{Community, Theme},
            event::{EventFull, EventKind},
            group::{GroupCategory, GroupSummary},
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
        db.expect_get_event()
            .withf(move |id, group_slug, event_slug| {
                *id == community_id && group_slug == "test-group" && event_slug == "test-event"
            })
            .returning(move |_, _, _| Ok(sample_event(event_id, group_id)));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/group/test-group/event/test-event")
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

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community()
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community(community_id)));
        db.expect_get_event()
            .withf(move |id, group_slug, event_slug| {
                *id == community_id && group_slug == "test-group" && event_slug == "test-event"
            })
            .returning(move |_, _, _| Err(anyhow!("db error")));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/group/test-group/event/test-event")
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
    async fn test_attend_event_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
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
        db.expect_attend_event()
            .withf(move |id, eid, uid| *id == community_id && *eid == event_id && *uid == user_id)
            .returning(|_, _, _| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("POST")
            .uri(format!("/event/{event_id}/attend"))
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
    async fn test_attendance_status_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
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
        db.expect_is_event_attendee()
            .withf(move |id, eid, uid| *id == community_id && *eid == event_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri(format!("/event/{event_id}/attendance"))
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
        assert_eq!(body, json!({ "is_attendee": true }));
    }

    #[tokio::test]
    async fn test_leave_event_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
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
        db.expect_leave_event()
            .withf(move |id, eid, uid| *id == community_id && *eid == event_id && *uid == user_id)
            .returning(|_, _, _| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("DELETE")
            .uri(format!("/event/{event_id}/leave"))
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

    // Helpers

    /// Helper to create a sample authenticated user for tests.
    fn sample_auth_user(user_id: Uuid, auth_hash: &str) -> AuthUser {
        AuthUser {
            auth_hash: auth_hash.to_string(),
            email: "user@example.test".to_string(),
            email_verified: true,
            name: "Test User".to_string(),
            user_id,
            username: "test-user".to_string(),
            ..Default::default()
        }
    }

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

    /// Helper to create a sample event for tests.
    fn sample_event(event_id: Uuid, group_id: Uuid) -> EventFull {
        EventFull {
            canceled: false,
            category_name: "Cloud Native".to_string(),
            color: "#336699".to_string(),
            created_at: Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap(),
            description: "A detailed event description".to_string(),
            event_id,
            group: sample_group_summary(group_id),
            hosts: vec![sample_template_user()],
            kind: EventKind::InPerson,
            name: "Test Event".to_string(),
            organizers: vec![sample_template_user()],
            published: true,
            sessions: BTreeMap::from([(NaiveDate::from_ymd_opt(2024, 1, 1).unwrap(), Vec::new())]),
            slug: "test-event".to_string(),
            sponsors: Vec::new(),
            timezone: UTC,
            description_short: Some("A test event".to_string()),
            ends_at: Some(Utc.with_ymd_and_hms(2024, 1, 1, 13, 0, 0).unwrap()),
            starts_at: Some(Utc.with_ymd_and_hms(2024, 1, 1, 12, 0, 0).unwrap()),
            venue_address: Some("123 Main St".to_string()),
            venue_city: Some("San Francisco".to_string()),
            venue_name: Some("Main Venue".to_string()),
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
