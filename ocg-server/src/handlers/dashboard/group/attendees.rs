//! HTTP handlers for the attendees section in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Form, Path, Query, State},
    http::{StatusCode, header::CONTENT_TYPE},
    response::{Html, IntoResponse},
};
use qrcode::render::svg;
use serde::{Deserialize, Serialize};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    auth::AuthSession,
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CommunityId, SelectedGroupId},
    },
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::{dashboard::group::attendees, notifications::EventCustom},
};

// Pages handlers.

/// Displays the list of attendees for the selected event and filters.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CommunityId(community_id): CommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Query(filters): Query<attendees::AttendeesFilters>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let attendees = db.search_event_attendees(group_id, &filters).await?;
    let event = if let Some(event_id) = filters.event_id {
        Some(db.get_event_summary(community_id, group_id, event_id).await?)
    } else {
        None
    };
    let template = attendees::ListPage {
        attendees,
        group_id,
        event,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Generates a QR code for event check-in.
#[instrument(skip_all, err)]
pub(crate) async fn generate_check_in_qr_code(
    CommunityId(_community_id): CommunityId,
    SelectedGroupId(_group_id): SelectedGroupId,
    State(cfg): State<HttpServerConfig>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get base URL from configuration
    let base_url = cfg.base_url.strip_suffix('/').unwrap_or(&cfg.base_url);

    // Construct check-in URL
    let check_in_url = format!("{base_url}/check-in/{event_id}");

    // Generate QR code
    let code = qrcode::QrCode::new(check_in_url.as_bytes())
        .map_err(|e| anyhow::anyhow!("Failed to generate QR code: {e}"))?;
    let svg = code
        .render()
        .min_dimensions(500, 500)
        .dark_color(svg::Color("#000000"))
        .light_color(svg::Color("#ffffff"))
        .build();

    // Return SVG response
    Ok((StatusCode::OK, [(CONTENT_TYPE, "image/svg+xml")], svg))
}

/// Sends a custom notification to event attendees.
#[instrument(skip_all, err)]
pub(crate) async fn send_event_custom_notification(
    auth_session: AuthSession,
    CommunityId(community_id): CommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    Path(event_id): Path<Uuid>,
    Form(notification): Form<EventCustomNotification>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Get event attendees
    let user_ids = db.list_event_attendees_ids(group_id, event_id).await?;
    if user_ids.is_empty() {
        // Event has no attendees, nothing to do
        return Ok(StatusCode::NO_CONTENT.into_response());
    }

    // Get community (to get theme)
    let community = db.get_community(community_id).await?;

    // Enqueue notification
    let template_data = EventCustom {
        subject: notification.subject.clone(),
        body: notification.body.clone(),
        theme: community.theme,
    };
    let new_notification = NewNotification {
        attachments: vec![],
        kind: NotificationKind::EventCustom,
        recipients: user_ids,
        template_data: Some(serde_json::to_value(&template_data)?),
    };
    notifications_manager.enqueue(&new_notification).await?;

    // Track custom notification for auditing purposes
    db.track_custom_notification(
        user.user_id,
        Some(event_id),
        None, // group_id is None for event notifications
        &notification.subject,
        &notification.body,
    )
    .await?;

    Ok(StatusCode::NO_CONTENT.into_response())
}

// Types.

/// Form data for custom event notifications.
#[derive(Debug, Deserialize, Serialize)]
pub(crate) struct EventCustomNotification {
    /// Subject line for the notification email.
    pub subject: String,
    /// Body text for the notification.
    pub body: String,
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
    use tower::ServiceExt;
    use uuid::Uuid;

    use crate::{
        config::HttpServerConfig,
        db::mock::MockDB,
        handlers::dashboard::group::attendees::EventCustomNotification,
        handlers::tests::*,
        router::CACHE_CONTROL_NO_CACHE,
        services::notifications::{MockNotificationsManager, NotificationKind},
        templates::notifications::EventCustom,
    };

    #[tokio::test]
    async fn test_generate_check_in_qr_code_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(group_id));

        // Setup database mock (no DB calls expected)
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

        // Setup notifications manager mock (not used by this handler)
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let cfg = HttpServerConfig {
            base_url: "https://test.example.com".to_string(),
            ..Default::default()
        };

        let router = setup_test_router_with_config(cfg, db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri(format!("/dashboard/group/check-in/{event_id}/qr-code"))
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();
        let svg_body = String::from_utf8(bytes.to_vec()).unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::OK);
        assert_eq!(
            parts.headers.get(CONTENT_TYPE).unwrap(),
            &HeaderValue::from_static("image/svg+xml")
        );
        assert!(svg_body.contains("<svg"));
        assert!(svg_body.contains("</svg>"));
        // The QR code should be a valid SVG structure with rect elements for QR modules
        assert!(svg_body.contains("<rect"));
    }

    #[tokio::test]
    async fn test_list_page_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(group_id));
        let attendee = sample_attendee();
        let event = sample_event_summary(event_id, group_id);

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
        db.expect_search_event_attendees()
            .times(1)
            .withf(move |id, filters| *id == group_id && filters.event_id == Some(event_id))
            .returning(move |_, _| Ok(vec![attendee.clone()]));
        db.expect_get_event_summary()
            .times(1)
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(event.clone()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri(format!("/dashboard/group/attendees?event_id={event_id}"))
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
            &HeaderValue::from_static("text/html; charset=utf-8"),
        );
        assert_eq!(
            parts.headers.get(CACHE_CONTROL).unwrap(),
            &HeaderValue::from_static(CACHE_CONTROL_NO_CACHE),
        );
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_list_page_db_error() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(group_id));

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
        db.expect_search_event_attendees()
            .times(1)
            .withf(move |id, filters| *id == group_id && filters.event_id.is_none())
            .returning(move |_, _| Err(anyhow!("db error")));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/group/attendees")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
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
    async fn test_send_event_custom_notification_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let attendee_id1 = Uuid::new_v4();
        let attendee_id2 = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(group_id));
        let community = sample_community(community_id);
        let community_copy = community.clone();
        let notification_body = "Hello, event attendees!";
        let notification_subject = "Event Update";
        let form_data = serde_qs::to_string(&EventCustomNotification {
            subject: notification_subject.to_string(),
            body: notification_body.to_string(),
        })
        .unwrap();

        // Create copies for the track_custom_notification closure
        let track_user_id = user_id;
        let track_event_id = event_id;
        let track_subject = notification_subject.to_string();
        let track_body = notification_body.to_string();

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
        db.expect_list_event_attendees_ids()
            .times(1)
            .withf(move |gid, eid| *gid == group_id && *eid == event_id)
            .returning(move |_, _| Ok(vec![attendee_id1, attendee_id2]));
        db.expect_get_community()
            .times(1)
            .withf(move |cid| *cid == community_id)
            .returning(move |_| Ok(community_copy.clone()));
        db.expect_track_custom_notification()
            .times(1)
            .withf(move |created_by, event_id, group_id, subject, body| {
                *created_by == track_user_id
                    && *event_id == Some(track_event_id)
                    && group_id.is_none()
                    && subject == track_subject
                    && body == track_body
            })
            .returning(|_, _, _, _, _| Ok(()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue()
            .times(1)
            .withf(move |notification| {
                matches!(notification.kind, NotificationKind::EventCustom)
                    && notification.recipients == vec![attendee_id1, attendee_id2]
                    && notification.template_data.as_ref().is_some_and(|value| {
                        serde_json::from_value::<EventCustom>(value.clone())
                            .map(|template| {
                                template.subject == notification_subject
                                    && template.body == notification_body
                                    && template.theme.primary_color == community.theme.primary_color
                            })
                            .unwrap_or(false)
                    })
            })
            .returning(|_| Box::pin(async { Ok(()) }));

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("POST")
            .uri(format!("/dashboard/group/notifications/{event_id}"))
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(Body::from(form_data))
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::NO_CONTENT);
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_send_event_custom_notification_no_attendees() {
        // Setup identifiers and data structures
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(group_id));
        let form_data = serde_qs::to_string(&EventCustomNotification {
            subject: "Subject".to_string(),
            body: "Body".to_string(),
        })
        .unwrap();

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
            .returning(move |_| Ok(Some(Uuid::new_v4())));
        db.expect_list_event_attendees_ids()
            .times(1)
            .withf(move |gid, eid| *gid == group_id && *eid == event_id)
            .returning(move |_, _| Ok(vec![]));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("POST")
            .uri(format!("/dashboard/group/notifications/{event_id}"))
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(Body::from(form_data))
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::NO_CONTENT);
        assert!(bytes.is_empty());
    }
}
