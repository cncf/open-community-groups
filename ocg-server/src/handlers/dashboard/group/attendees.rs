//! HTTP handlers for the attendees section in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::{StatusCode, header::CONTENT_TYPE},
    response::{Html, IntoResponse},
};
use chrono::Duration;
use garde::Validate;
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
        extractors::{SelectedCommunityId, SelectedGroupId, ValidatedForm},
        prepare_headers,
    },
    router::serde_qs_config,
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::{
        dashboard::group::attendees::{self, AttendeesFilters, AttendeesPaginationFilters},
        notifications::EventCustom,
        pagination::NavigationLinks,
    },
    validation::{MAX_LEN_M, MAX_LEN_XL, trimmed_non_empty},
};

// Pages handlers.

/// Displays the list of attendees for a specific event.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Fetch event summary and attendees
    let mut page_filters: AttendeesPaginationFilters =
        serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
    page_filters = page_filters.with_defaults();
    let filters = AttendeesFilters {
        event_id,
        limit: page_filters.limit,
        offset: page_filters.offset,
    }
    .with_defaults();
    let (event, attendees) = tokio::try_join!(
        db.get_event_summary(community_id, group_id, event_id),
        db.search_event_attendees(group_id, &filters)
    )?;

    // Prepare template
    let navigation_links = NavigationLinks::from_filters(
        &page_filters,
        attendees.total,
        &format!("/dashboard/group/events/{event_id}/attendees"),
        &format!("/dashboard/group/events/{event_id}/attendees"),
    )?;
    let template = attendees::ListPage {
        attendees: attendees.attendees,
        event,
        navigation_links,
        total: attendees.total,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Generates a QR code for event check-in.
#[instrument(skip_all, err)]
pub(crate) async fn generate_check_in_qr_code(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get community name (cached) and ensure event belongs to selected group
    let (community_name, _) = tokio::try_join!(
        db.get_community_name_by_id(community_id),
        db.get_event_summary(community_id, group_id, event_id)
    )?;
    let Some(community_name) = community_name else {
        return Err(anyhow::anyhow!("community not found").into());
    };

    // Get base URL from configuration
    let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);

    // Construct check-in URL
    let check_in_url = format!("{base_url}/{community_name}/check-in/{event_id}");

    // Generate QR code
    let code = qrcode::QrCode::new(check_in_url.as_bytes())
        .map_err(|e| anyhow::anyhow!("Failed to generate QR code: {e}"))?;
    let svg = code
        .render()
        .min_dimensions(500, 500)
        .dark_color(svg::Color("#000000"))
        .light_color(svg::Color("#ffffff"))
        .build();

    // Prepare response headers
    let headers = prepare_headers(Duration::hours(1), &[(CONTENT_TYPE.as_str(), "image/svg+xml")])?;

    // Return SVG response
    Ok((StatusCode::OK, headers, svg))
}

/// Manually checks in a user for an event, bypassing the check-in window validation.
#[instrument(skip_all, err)]
pub(crate) async fn manual_check_in(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path((event_id, user_id)): Path<(Uuid, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Validate event belongs to the selected group
    db.get_event_summary(community_id, group_id, event_id).await?;

    // Check-in with bypass_window = true
    db.check_in_event(community_id, event_id, user_id, true).await?;

    Ok(StatusCode::NO_CONTENT)
}

/// Sends a custom notification to event attendees.
#[instrument(skip_all, err)]
#[allow(clippy::too_many_arguments)]
pub(crate) async fn send_event_custom_notification(
    auth_session: AuthSession,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    Path(event_id): Path<Uuid>,
    ValidatedForm(notification): ValidatedForm<EventCustomNotification>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Get event data and site settings
    let (site_settings, event, event_attendees_ids) = tokio::try_join!(
        db.get_site_settings(),
        db.get_event_summary_by_id(community_id, event_id),
        db.list_event_attendees_ids(group_id, event_id),
    )?;

    // If there are no attendees, nothing to do
    if event_attendees_ids.is_empty() {
        return Ok(StatusCode::NO_CONTENT.into_response());
    }

    // Enqueue notification
    let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
    let link = format!(
        "{}/{}/group/{}/event/{}",
        base_url, event.community_name, event.group_slug, event.slug
    );
    let template_data = EventCustom {
        body: notification.body.clone(),
        event,
        link,
        theme: site_settings.theme,
        title: notification.title.clone(),
    };
    let new_notification = NewNotification {
        attachments: vec![],
        kind: NotificationKind::EventCustom,
        recipients: event_attendees_ids,
        template_data: Some(serde_json::to_value(&template_data)?),
    };
    notifications_manager.enqueue(&new_notification).await?;

    // Track custom notification for auditing purposes
    db.track_custom_notification(
        user.user_id,
        Some(event_id),
        None, // group_id is None for event notifications
        &notification.title,
        &notification.body,
    )
    .await?;

    Ok(StatusCode::NO_CONTENT.into_response())
}

// Types.

/// Form data for custom event notifications.
#[derive(Debug, Deserialize, Serialize, Validate)]
pub(crate) struct EventCustomNotification {
    /// Body text for the notification.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_XL))]
    pub body: String,
    /// Title line for the notification email.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub title: String,
}

// Tests.

#[cfg(test)]
mod tests {
    use anyhow::anyhow;
    use axum::{
        body::{Body, to_bytes},
        http::{
            HeaderValue, Request, StatusCode,
            header::{CACHE_CONTROL, CONTENT_TYPE, COOKIE},
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
        templates::dashboard::DASHBOARD_PAGINATION_LIMIT,
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
        let session_record = sample_session_record(
            session_id,
            user_id,
            &auth_hash,
            Some(community_id),
            Some(group_id),
        );
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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));
        db.expect_get_community_name_by_id()
            .times(1)
            .withf(move |cid| *cid == community_id)
            .returning(|_| Ok(Some("test".to_string())));
        db.expect_get_event_summary()
            .times(1)
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(event.clone()));

        // Setup notifications manager mock (not used by this handler)
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let server_cfg = HttpServerConfig {
            base_url: "https://test.example.com".to_string(),
            ..Default::default()
        };
        let router = TestRouterBuilder::new(db, nm)
            .with_server_cfg(server_cfg)
            .build()
            .await;
        let request = Request::builder()
            .method("GET")
            .uri(format!("/dashboard/group/check-in/{event_id}/qr-code"))
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
        #[cfg(debug_assertions)]
        let expected_cache_header = "max-age=0";
        #[cfg(not(debug_assertions))]
        let expected_cache_header = "max-age=3600";
        assert_eq!(
            parts.headers.get(CACHE_CONTROL).unwrap().to_str().unwrap(),
            expected_cache_header
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
        let session_record = sample_session_record(
            session_id,
            user_id,
            &auth_hash,
            Some(community_id),
            Some(group_id),
        );
        let attendee = sample_attendee();
        let event = sample_event_summary(event_id, group_id);
        let output = crate::templates::dashboard::group::attendees::AttendeesOutput {
            attendees: vec![attendee.clone()],
            total: 1,
        };

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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));
        db.expect_search_event_attendees()
            .times(1)
            .withf(move |gid, filters| {
                *gid == group_id
                    && filters.event_id == event_id
                    && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                    && filters.offset == Some(0)
            })
            .returning(move |_, _| Ok(output.clone()));
        db.expect_get_event_summary()
            .times(1)
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(event.clone()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri(format!("/dashboard/group/events/{event_id}/attendees"))
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
    async fn test_manual_check_in_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let target_user_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(
            session_id,
            user_id,
            &auth_hash,
            Some(community_id),
            Some(group_id),
        );
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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));
        db.expect_get_event_summary()
            .times(1)
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(event.clone()));
        db.expect_check_in_event()
            .times(1)
            .withf(move |cid, eid, uid, bypass_window| {
                *cid == community_id && *eid == event_id && *uid == target_user_id && *bypass_window
            })
            .returning(|_, _, _, _| Ok(()));

        // Setup notifications manager mock (not used by this handler)
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("POST")
            .uri(format!(
                "/dashboard/group/events/{event_id}/attendees/{target_user_id}/check-in"
            ))
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
    async fn test_list_page_db_error() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(
            session_id,
            user_id,
            &auth_hash,
            Some(community_id),
            Some(group_id),
        );

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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));
        db.expect_search_event_attendees()
            .times(0..=1)
            .withf(move |gid, filters| {
                *gid == group_id
                    && filters.event_id == event_id
                    && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                    && filters.offset == Some(0)
            })
            .returning(move |_, _| Err(anyhow!("db error")));
        db.expect_get_event_summary()
            .times(1)
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Err(anyhow!("db error")));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri(format!("/dashboard/group/events/{event_id}/attendees"))
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
    #[allow(clippy::too_many_lines)]
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
        let session_record = sample_session_record(
            session_id,
            user_id,
            &auth_hash,
            Some(community_id),
            Some(group_id),
        );
        let site_settings = sample_site_settings();
        let site_settings_for_notifications = site_settings.clone();
        let event = sample_event_summary(event_id, group_id);
        let expected_link = format!(
            "/{}/group/{}/event/{}",
            event.community_name, event.group_slug, event.slug
        );
        let event_for_notifications = event.clone();
        let event_for_db = event.clone();
        let notification_body = "Hello, event attendees!";
        let notification_subject = "Event Update";
        let form_data = serde_qs::to_string(&EventCustomNotification {
            title: notification_subject.to_string(),
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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));
        db.expect_list_event_attendees_ids()
            .times(1)
            .withf(move |gid, eid| *gid == group_id && *eid == event_id)
            .returning(move |_, _| Ok(vec![attendee_id1, attendee_id2]));
        db.expect_get_event_summary_by_id()
            .times(1)
            .withf(move |cid, eid| *cid == community_id && *eid == event_id)
            .returning(move |_, _| Ok(event_for_db.clone()));
        db.expect_get_site_settings()
            .times(1)
            .returning(move || Ok(site_settings.clone()));
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
                                template.title == notification_subject
                                    && template.body == notification_body
                                    && template.event.name == event_for_notifications.name
                                    && template.event.group_name == event_for_notifications.group_name
                                    && template.link == expected_link
                                    && template.theme.primary_color
                                        == site_settings_for_notifications.theme.primary_color
                            })
                            .unwrap_or(false)
                    })
            })
            .returning(|_| Box::pin(async { Ok(()) }));

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("POST")
            .uri(format!("/dashboard/group/notifications/{event_id}"))
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
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(
            session_id,
            user_id,
            &auth_hash,
            Some(community_id),
            Some(group_id),
        );
        let form_data = serde_qs::to_string(&EventCustomNotification {
            title: "Subject".to_string(),
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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));
        db.expect_get_event_summary_by_id()
            .times(1)
            .withf(move |cid, eid| *cid == community_id && *eid == event_id)
            .returning(move |_, _| Ok(sample_event_summary(event_id, group_id)));
        db.expect_list_event_attendees_ids()
            .times(1)
            .withf(move |gid, eid| *gid == group_id && *eid == event_id)
            .returning(move |_, _| Ok(vec![]));
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("POST")
            .uri(format!("/dashboard/group/notifications/{event_id}"))
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
