//! HTTP handlers for the event page.

use askama::Template;
use axum::{
    Json,
    extract::{Path, State},
    http::{StatusCode, Uri},
    response::{Html, IntoResponse},
};
use chrono::Duration;
use serde_json::{json, to_value};
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
        event::{CheckInPage, Page},
        notifications::EventWelcome,
    },
    util::{build_event_calendar_attachment, build_event_page_link},
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
        db.get_event_full_by_slug(community_id, &group_slug, &event_slug)
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

/// Handler that renders the check-in page.
#[instrument(skip_all, err)]
pub(crate) async fn check_in_page(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path(event_id): Path<Uuid>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.as_ref().expect("user to be logged in").clone();

    // Get community and event details
    let (community, event, (user_is_attendee, user_is_checked_in), check_in_window_open) = tokio::try_join!(
        db.get_community(community_id),
        db.get_event_summary_by_id(community_id, event_id),
        db.is_event_attendee(community_id, event_id, user.user_id),
        db.is_event_check_in_window_open(community_id, event_id),
    )?;

    let template = CheckInPage {
        check_in_window_open,
        community,
        event,
        page_id: PageId::CheckIn,
        path: uri.path().to_string(),
        user: User::from_session(auth_session).await?,
        user_is_attendee,
        user_is_checked_in,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Handler for attending an event.
#[instrument(skip_all)]
pub(crate) async fn attend_event(
    auth_session: AuthSession,
    State(cfg): State<HttpServerConfig>,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    CommunityId(community_id): CommunityId,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Attend event
    db.attend_event(community_id, event_id, user.user_id).await?;

    // Enqueue welcome to event notification
    let (community, event) = tokio::try_join!(
        db.get_community(community_id),
        db.get_event_summary_by_id(community_id, event_id),
    )?;
    let base_url = cfg.base_url.strip_suffix('/').unwrap_or(&cfg.base_url);
    let link = build_event_page_link(base_url, &event);
    let calendar_ics = build_event_calendar_attachment(base_url, &event);
    let template_data = EventWelcome {
        link,
        event,
        theme: community.theme,
    };
    let notification = NewNotification {
        attachments: vec![calendar_ics],
        kind: NotificationKind::EventWelcome,
        recipients: vec![user.user_id],
        template_data: Some(to_value(&template_data)?),
    };
    notifications_manager.enqueue(&notification).await?;

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

    // Check attendance and check-in status
    let (is_attendee, is_checked_in) = db.is_event_attendee(community_id, event_id, user.user_id).await?;

    Ok(Json(json!({
        "is_attendee": is_attendee,
        "is_checked_in": is_checked_in
    })))
}

/// Handler that marks the authenticated attendee as checked in.
#[instrument(skip_all)]
pub(crate) async fn check_in(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Check in event
    db.check_in_event(community_id, event_id, user.user_id).await?;

    Ok(StatusCode::NO_CONTENT)
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
    use anyhow::anyhow;
    use axum::{
        body::{Body, to_bytes},
        http::{
            HeaderValue, Request, StatusCode,
            header::{CACHE_CONTROL, CONTENT_TYPE, COOKIE, HOST},
        },
    };
    use axum_login::tower_sessions::session;
    use serde_json::{from_slice, from_value, json};
    use tower::ServiceExt;
    use uuid::Uuid;

    use crate::{
        db::mock::MockDB,
        handlers::tests::*,
        router::CACHE_CONTROL_NO_CACHE,
        services::notifications::{MockNotificationsManager, NotificationKind},
        templates::notifications::EventWelcome,
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
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community(community_id)));
        db.expect_get_event_full_by_slug()
            .times(1)
            .withf(move |id, group_slug, event_slug| {
                *id == community_id && group_slug == "test-group" && event_slug == "test-event"
            })
            .returning(move |_, _, _| Ok(sample_event_full(event_id, group_id)));

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
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community(community_id)));
        db.expect_get_event_full_by_slug()
            .times(1)
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
    async fn test_check_in_page_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);
        let event_summary = sample_event_summary(event_id, group_id);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community(community_id)));
        db.expect_get_event_summary_by_id()
            .times(1)
            .withf(move |cid, eid| *cid == community_id && *eid == event_id)
            .returning(move |_, _| Ok(event_summary.clone()));
        db.expect_is_event_attendee()
            .times(1)
            .withf(move |cid, eid, uid| *cid == community_id && *eid == event_id && *uid == user_id)
            .returning(|_, _, _| Ok((true, false)));
        db.expect_is_event_check_in_window_open()
            .times(1)
            .withf(move |cid, eid| *cid == community_id && *eid == event_id)
            .returning(|_, _| Ok(true));

        // Setup router and send request
        let router = setup_test_router(db, MockNotificationsManager::new()).await;
        let request = Request::builder()
            .method("GET")
            .uri(format!("/check-in/{event_id}"))
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
            parts.headers.get(CONTENT_TYPE),
            Some(&HeaderValue::from_static("text/html; charset=utf-8"))
        );
        assert_eq!(
            parts.headers.get(CACHE_CONTROL),
            Some(&HeaderValue::from_static(CACHE_CONTROL_NO_CACHE))
        );
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_attend_event_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let event_summary = sample_event_summary(event_id, group_id);
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_attend_event()
            .times(1)
            .withf(move |id, eid, uid| *id == community_id && *eid == event_id && *uid == user_id)
            .returning(|_, _, _| Ok(()));
        db.expect_get_community()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community(community_id)));
        db.expect_get_event_summary_by_id()
            .times(1)
            .withf(move |cid, eid| *cid == community_id && *eid == event_id)
            .returning(move |_, _| Ok(event_summary.clone()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue()
            .times(1)
            .withf(move |notification| {
                matches!(notification.kind, NotificationKind::EventWelcome)
                    && notification.recipients == vec![user_id]
                    && notification.template_data.as_ref().is_some_and(|value| {
                        from_value::<EventWelcome>(value.clone())
                            .map(|template| template.link == "/group/test-group/event/sample-event")
                            .unwrap_or(false)
                    })
            })
            .returning(|_| Box::pin(async { Ok(()) }));

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
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_is_event_attendee()
            .times(1)
            .withf(move |id, eid, uid| *id == community_id && *eid == event_id && *uid == user_id)
            .returning(|_, _, _| Ok((true, false)));

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
            &HeaderValue::from_static(CACHE_CONTROL_NO_CACHE)
        );
        let body: serde_json::Value = from_slice(&bytes).unwrap();
        assert_eq!(body, json!({ "is_attendee": true, "is_checked_in": false }));
    }

    #[tokio::test]
    async fn test_check_in_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_check_in_event()
            .times(1)
            .withf(move |cid, eid, uid| *cid == community_id && *eid == event_id && *uid == user_id)
            .returning(|_, _, _| Ok(()));

        // Setup router and send request
        let router = setup_test_router(db, MockNotificationsManager::new()).await;
        let request = Request::builder()
            .method("POST")
            .uri(format!("/check-in/{event_id}"))
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
    async fn test_leave_event_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_leave_event()
            .times(1)
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
}
