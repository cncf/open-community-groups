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
        db.get_group_full_by_slug(community_id, &group_slug),
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
    let (community, group) = tokio::try_join!(
        db.get_community(community_id),
        db.get_group_summary(community_id, group_id)
    )?;
    let base_url = cfg.base_url.strip_suffix('/').unwrap_or(&cfg.base_url);
    let template_data = GroupWelcome {
        link: format!("{}/group/{}", base_url, group.slug),
        group,
        theme: community.theme,
    };
    let notification = NewNotification {
        attachments: vec![],
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
    use anyhow::anyhow;
    use axum::{
        body::{Body, to_bytes},
        http::{
            HeaderValue, Request, StatusCode,
            header::{CACHE_CONTROL, CONTENT_TYPE, COOKIE, HOST},
        },
    };
    use axum_login::tower_sessions::session;
    use serde_json::{from_slice, json};
    use tower::ServiceExt;
    use uuid::Uuid;

    use crate::{
        db::mock::MockDB,
        handlers::tests::*,
        router::CACHE_CONTROL_NO_CACHE,
        services::notifications::{MockNotificationsManager, NotificationKind},
        templates::notifications::GroupWelcome,
        types::event::EventKind,
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
        db.expect_get_group_full_by_slug()
            .times(1)
            .withf(move |id, slug| *id == community_id && slug == "test-group")
            .returning(move |_, _| Ok(sample_group_full(group_id)));
        db.expect_get_group_upcoming_events()
            .times(1)
            .withf(move |id, slug, kinds, limit| {
                *id == community_id
                    && slug == "test-group"
                    && kinds == &vec![EventKind::InPerson, EventKind::Virtual, EventKind::Hybrid]
                    && *limit == 9
            })
            .returning(move |_, _, _, _| Ok(vec![sample_event_summary(event_id, group_id)]));
        db.expect_get_group_past_events()
            .times(1)
            .withf(move |id, slug, kinds, limit| {
                *id == community_id
                    && slug == "test-group"
                    && kinds == &vec![EventKind::InPerson, EventKind::Virtual, EventKind::Hybrid]
                    && *limit == 9
            })
            .returning(move |_, _, _, _| Ok(vec![sample_event_summary(event_id, group_id)]));

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
        db.expect_get_group_full_by_slug()
            .times(1)
            .withf(move |id, slug| *id == community_id && slug == "test-group")
            .returning(move |_, _| Ok(sample_group_full(group_id)));
        db.expect_get_group_upcoming_events()
            .times(1)
            .withf(move |id, slug, kinds, limit| {
                *id == community_id
                    && slug == "test-group"
                    && kinds == &vec![EventKind::InPerson, EventKind::Virtual, EventKind::Hybrid]
                    && *limit == 9
            })
            .returning(move |_, _, _, _| Ok(vec![sample_event_summary(event_id, group_id)]));
        db.expect_get_group_past_events()
            .times(1)
            .withf(move |id, slug, kinds, limit| {
                *id == community_id
                    && slug == "test-group"
                    && kinds == &vec![EventKind::InPerson, EventKind::Virtual, EventKind::Hybrid]
                    && *limit == 9
            })
            .returning(move |_, _, _, _| Err(anyhow!("db error")));

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
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);
        let community = sample_community(community_id);
        let community_for_notifications = community.clone();
        let community_for_db = community;

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
        db.expect_join_group()
            .times(1)
            .withf(move |id, gid, uid| *id == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(()));
        db.expect_get_group_summary()
            .times(1)
            .withf(move |cid, gid| *cid == community_id && *gid == group_id)
            .returning(move |_, _| Ok(sample_group_summary(group_id)));
        db.expect_get_community()
            .times(1)
            .withf(move |cid| *cid == community_id)
            .returning({
                let community = community_for_db;
                move |_| Ok(community.clone())
            });

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue()
            .times(1)
            .withf(move |notification| {
                matches!(notification.kind, NotificationKind::GroupWelcome)
                    && notification.recipients == vec![user_id]
                    && notification.template_data.as_ref().is_some_and(|data| {
                        serde_json::from_value::<GroupWelcome>(data.clone())
                            .map(|welcome| {
                                welcome.group.group_id == group_id
                                    && welcome.link == "/group/test-group"
                                    && welcome.theme.primary_color
                                        == community_for_notifications.theme.primary_color
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
        db.expect_leave_group()
            .times(1)
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
        db.expect_is_group_member()
            .times(1)
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
            &HeaderValue::from_static(CACHE_CONTROL_NO_CACHE)
        );
        let body: serde_json::Value = from_slice(&bytes).unwrap();
        assert_eq!(body, json!({ "is_member": true }));
    }
}
