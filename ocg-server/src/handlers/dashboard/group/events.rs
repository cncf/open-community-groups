//! HTTP handlers for managing events in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::{Html, IntoResponse},
};
use chrono::{TimeDelta, Utc};
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
    templates::{
        dashboard::group::events::{self, Event},
        notifications::{EventCanceled, EventPublished, EventRescheduled},
    },
};

// Minimum shift required to notify a reschedule.
const MIN_RESCHEDULE_SHIFT: TimeDelta = TimeDelta::minutes(15);

// Pages handlers.

/// Displays the page to add a new event.
#[instrument(skip_all, err)]
pub(crate) async fn add_page(
    CommunityId(community_id): CommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (categories, event_kinds, session_kinds, sponsors, timezones) = tokio::try_join!(
        db.list_event_categories(community_id),
        db.list_event_kinds(),
        db.list_session_kinds(),
        db.list_group_sponsors(group_id),
        db.list_timezones()
    )?;
    let template = events::AddPage {
        group_id,
        categories,
        event_kinds,
        session_kinds,
        sponsors,
        timezones,
    };

    Ok(Html(template.render()?))
}

/// Displays the list of events for the group dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let events = db.list_group_events(group_id).await?;
    let template = events::ListPage { events };

    Ok(Html(template.render()?))
}

/// Displays the page to update an existing event.
#[instrument(skip_all, err)]
pub(crate) async fn update_page(
    CommunityId(community_id): CommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (event, categories, event_kinds, session_kinds, sponsors, timezones) = tokio::try_join!(
        db.get_event_full(community_id, group_id, event_id),
        db.list_event_categories(community_id),
        db.list_event_kinds(),
        db.list_session_kinds(),
        db.list_group_sponsors(group_id),
        db.list_timezones()
    )?;
    let template = events::UpdatePage {
        group_id,
        event,
        categories,
        event_kinds,
        session_kinds,
        sponsors,
        timezones,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Adds a new event to the database.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(serde_qs_de): State<serde_qs::Config>,
    body: String,
) -> Result<impl IntoResponse, HandlerError> {
    // Parse event information from body
    let event: Event = match serde_qs_de.deserialize_str(&body).map_err(anyhow::Error::new) {
        Ok(event) => event,
        Err(e) => return Ok((StatusCode::UNPROCESSABLE_ENTITY, e.to_string()).into_response()),
    };

    // Add event to database
    db.add_event(group_id, &event).await?;

    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    )
        .into_response())
}

/// Cancels an event (sets canceled=true).
#[instrument(skip_all, err)]
pub(crate) async fn cancel(
    CommunityId(community_id): CommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(cfg): State<HttpServerConfig>,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load event summary before canceling
    let mut event = db.get_event_summary(community_id, group_id, event_id).await?;

    // Mark event as canceled in database
    db.cancel_event(group_id, event_id).await?;

    // Notify attendees about canceled event
    let should_notify = matches!(
        (event.published, event.canceled, event.starts_at),
        (true, false, Some(starts_at)) if starts_at > Utc::now()
    );
    if should_notify {
        let user_ids = db.list_event_attendees_ids(event_id).await?;
        if !user_ids.is_empty() {
            event.canceled = true; // Update local event to reflect canceled status
            let base_url = cfg.base_url.strip_suffix('/').unwrap_or(&cfg.base_url);
            let link = format!("{}/group/{}/event/{}", base_url, event.group_slug, event.slug);
            let community = db.get_community(community_id).await?;
            let template_data = EventCanceled {
                event,
                link,
                theme: community.theme,
            };
            let notification = NewNotification {
                attachments: vec![],
                kind: NotificationKind::EventCanceled,
                recipients: user_ids,
                template_data: Some(serde_json::to_value(&template_data)?),
            };
            notifications_manager.enqueue(&notification).await?;
        }
    }

    Ok((
        StatusCode::NO_CONTENT,
        [(
            "HX-Location",
            r#"{"path":"/dashboard/group?tab=events", "target":"body"}"#,
        )],
    ))
}

/// Publishes an event (sets published=true and records publication metadata).
#[instrument(skip_all, err)]
pub(crate) async fn publish(
    auth_session: AuthSession,
    CommunityId(community_id): CommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(cfg): State<HttpServerConfig>,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Load event summary before publishing
    let event = db.get_event_summary(community_id, group_id, event_id).await?;

    // Mark event as published in database
    db.publish_event(group_id, event_id, user.user_id).await?;

    // Notify group members about published event
    let should_notify = matches!(
        (event.published, event.starts_at),
        (false, Some(starts_at)) if starts_at > Utc::now()
    );
    if should_notify {
        let user_ids = db.list_group_members_ids(group_id).await?;
        if !user_ids.is_empty() {
            let (community, event) = tokio::try_join!(
                db.get_community(community_id),
                db.get_event_summary(community_id, group_id, event_id),
            )?;
            let base_url = cfg.base_url.strip_suffix('/').unwrap_or(&cfg.base_url);
            let link = format!("{}/group/{}/event/{}", base_url, event.group_slug, event.slug);
            let template_data = EventPublished {
                event,
                link,
                theme: community.theme,
            };
            let notification = NewNotification {
                attachments: vec![],
                kind: NotificationKind::EventPublished,
                recipients: user_ids,
                template_data: Some(serde_json::to_value(&template_data)?),
            };
            notifications_manager.enqueue(&notification).await?;
        }
    }

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Deletes an event from the database (soft delete).
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Delete event from database (soft delete)
    db.delete_event(group_id, event_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Unpublishes an event (sets published=false and clears publication metadata).
#[instrument(skip_all, err)]
pub(crate) async fn unpublish(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Mark event as unpublished in database
    db.unpublish_event(group_id, event_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Updates an existing event's information in the database.
#[allow(clippy::too_many_arguments)]
#[instrument(skip_all, err)]
pub(crate) async fn update(
    CommunityId(community_id): CommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(cfg): State<HttpServerConfig>,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(serde_qs_de): State<serde_qs::Config>,
    Path(event_id): Path<Uuid>,
    body: String,
) -> Result<impl IntoResponse, HandlerError> {
    // Parse event information from body
    let event: Event = match serde_qs_de.deserialize_str(&body).map_err(anyhow::Error::new) {
        Ok(event) => event,
        Err(e) => return Ok((StatusCode::UNPROCESSABLE_ENTITY, e.to_string()).into_response()),
    };

    // Load event summary before update to detect reschedule
    let before = db.get_event_summary(community_id, group_id, event_id).await?;

    // Update event in database
    db.update_event(group_id, event_id, &event).await?;

    // Notify attendees if event was rescheduled
    let after = db.get_event_summary(community_id, group_id, event_id).await?;
    let should_notify = match (before.published, before.starts_at, after.starts_at) {
        (true, Some(b_starts_at), Some(a_starts_at)) if a_starts_at > Utc::now() => {
            (a_starts_at - b_starts_at).abs() >= MIN_RESCHEDULE_SHIFT
        }
        _ => false,
    };
    if should_notify {
        let user_ids = db.list_event_attendees_ids(event_id).await?;
        if !user_ids.is_empty() {
            let base = cfg.base_url.strip_suffix('/').unwrap_or(&cfg.base_url);
            let link = format!("{}/group/{}/event/{}", base, after.group_slug, after.slug);
            let community = db.get_community(community_id).await?;
            let template_data = EventRescheduled {
                event: after,
                link,
                theme: community.theme,
            };
            let notification = NewNotification {
                attachments: vec![],
                kind: NotificationKind::EventRescheduled,
                recipients: user_ids,
                template_data: Some(serde_json::to_value(&template_data)?),
            };
            notifications_manager.enqueue(&notification).await?;
        }
    }

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    )
        .into_response())
}

// Tests.

#[cfg(test)]
mod tests {
    use axum::{
        body::{Body, to_bytes},
        http::{
            HeaderValue, Request, StatusCode,
            header::{CACHE_CONTROL, CONTENT_TYPE, COOKIE, HOST},
        },
    };
    use axum_login::tower_sessions::session;
    use serde_json::from_value;
    use tower::ServiceExt;
    use uuid::Uuid;

    use crate::{
        db::mock::MockDB,
        handlers::tests::*,
        router::CACHE_CONTROL_NO_CACHE,
        services::notifications::{MockNotificationsManager, NotificationKind},
        templates::notifications::{EventCanceled, EventPublished, EventRescheduled},
        types::event::EventSummary,
    };

    #[tokio::test]
    async fn test_add_page_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(group_id));
        let category = sample_event_category();
        let kind = sample_event_kind_summary();
        let session_kind = sample_session_kind_summary();
        let sponsor = sample_group_sponsor();
        let timezones = vec!["UTC".to_string()];

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
        db.expect_list_event_categories()
            .times(1)
            .withf(move |cid| *cid == community_id)
            .returning(move |_| Ok(vec![category.clone()]));
        db.expect_list_event_kinds()
            .times(1)
            .returning(move || Ok(vec![kind.clone()]));
        db.expect_list_session_kinds()
            .times(1)
            .returning(move || Ok(vec![session_kind.clone()]));
        db.expect_list_group_sponsors()
            .times(1)
            .withf(move |id| *id == group_id)
            .returning(move |_| Ok(vec![sponsor.clone()]));
        db.expect_list_timezones()
            .times(1)
            .returning(move || Ok(timezones.clone()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/group/events/add")
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
    async fn test_list_page_success() {
        // Setup identifiers and data structures
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(group_id));
        let group_events = sample_group_events(Uuid::new_v4(), group_id);

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
        db.expect_list_group_events()
            .times(1)
            .withf(move |id| *id == group_id)
            .returning({
                let group_events = group_events.clone();
                move |_| Ok(group_events.clone())
            });

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/group/events")
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
    async fn test_update_page_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(group_id));
        let event_full = sample_event_full(event_id, group_id);
        let category = sample_event_category();
        let kind = sample_event_kind_summary();
        let session_kind = sample_session_kind_summary();
        let sponsor = sample_group_sponsor();
        let timezones = vec!["UTC".to_string()];

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
        db.expect_get_event_full()
            .times(1)
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(event_full.clone()));
        db.expect_list_event_categories()
            .times(1)
            .withf(move |cid| *cid == community_id)
            .returning(move |_| Ok(vec![category.clone()]));
        db.expect_list_event_kinds()
            .times(1)
            .returning(move || Ok(vec![kind.clone()]));
        db.expect_list_session_kinds()
            .times(1)
            .returning(move || Ok(vec![session_kind.clone()]));
        db.expect_list_group_sponsors()
            .times(1)
            .withf(move |id| *id == group_id)
            .returning(move |_| Ok(vec![sponsor.clone()]));
        db.expect_list_timezones()
            .times(1)
            .returning(move || Ok(timezones.clone()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri(format!("/dashboard/group/events/{event_id}/update"))
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
    async fn test_add_success() {
        // Setup identifiers and data structures
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(group_id));
        let event_form = sample_event_form();
        let body = serde_qs::to_string(&event_form).unwrap();

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
        db.expect_add_event()
            .times(1)
            .withf(move |id, event| {
                *id == group_id && event.name == event_form.name && event.slug == event_form.slug
            })
            .returning(move |_, _| Ok(Uuid::new_v4()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("POST")
            .uri("/dashboard/group/events/add")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(Body::from(body))
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::CREATED);
        assert_eq!(
            parts.headers.get("HX-Trigger").unwrap(),
            &HeaderValue::from_static("refresh-group-dashboard-table"),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_add_invalid_body() {
        // Setup identifiers and data structures
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

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("POST")
            .uri("/dashboard/group/events/add")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(Body::from("invalid"))
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_cancel_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let recipient_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(group_id));
        let event_summary = sample_event_summary(event_id, group_id);
        let community = sample_community(community_id);
        let community_copy = community.clone();

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
        db.expect_get_event_summary()
            .times(1)
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(event_summary.clone()));
        db.expect_cancel_event()
            .times(1)
            .withf(move |id, eid| *id == group_id && *eid == event_id)
            .returning(move |_, _| Ok(()));
        db.expect_list_event_attendees_ids()
            .times(1)
            .withf(move |eid| *eid == event_id)
            .returning(move |_| Ok(vec![recipient_id]));
        db.expect_get_community()
            .times(1)
            .withf(move |cid| *cid == community_id)
            .returning(move |_| Ok(community_copy.clone()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue()
            .times(1)
            .withf(move |notification| {
                matches!(notification.kind, NotificationKind::EventCanceled)
                    && notification.recipients == vec![recipient_id]
                    && notification.template_data.as_ref().is_some_and(|value| {
                        from_value::<EventCanceled>(value.clone())
                            .map(|template| {
                                template.link == "/group/test-group/event/sample-event"
                                    && template.theme.primary_color == community.theme.primary_color
                            })
                            .unwrap_or(false)
                    })
            })
            .returning(|_| Box::pin(async { Ok(()) }));

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!("/dashboard/group/events/{event_id}/cancel"))
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::NO_CONTENT);
        assert_eq!(
            parts.headers.get("HX-Location").unwrap(),
            &HeaderValue::from_static(r#"{"path":"/dashboard/group?tab=events", "target":"body"}"#,),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_publish_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let member_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(group_id));
        let unpublished_event = EventSummary {
            published: false,
            ..sample_event_summary(event_id, group_id)
        };
        let published_event = sample_event_summary(event_id, group_id);
        let community = sample_community(community_id);
        let community_copy = community.clone();

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
        db.expect_get_event_summary()
            .times(2)
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning({
                let mut first_call = true;
                move |_, _, _| {
                    let result = if first_call {
                        first_call = false;
                        unpublished_event.clone()
                    } else {
                        published_event.clone()
                    };
                    Ok(result)
                }
            });
        db.expect_publish_event()
            .times(1)
            .withf(move |gid, eid, uid| *gid == group_id && *eid == event_id && *uid == user_id)
            .returning(move |_, _, _| Ok(()));
        db.expect_list_group_members_ids()
            .times(1)
            .withf(move |gid| *gid == group_id)
            .returning(move |_| Ok(vec![member_id]));
        db.expect_get_community()
            .times(1)
            .withf(move |cid| *cid == community_id)
            .returning(move |_| Ok(community_copy.clone()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue()
            .times(1)
            .withf(move |notification| {
                matches!(notification.kind, NotificationKind::EventPublished)
                    && notification.recipients == vec![member_id]
                    && notification.template_data.as_ref().is_some_and(|value| {
                        from_value::<EventPublished>(value.clone())
                            .map(|template| {
                                template.link == "/group/test-group/event/sample-event"
                                    && template.theme.primary_color == community.theme.primary_color
                            })
                            .unwrap_or(false)
                    })
            })
            .returning(|_| Box::pin(async { Ok(()) }));

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!("/dashboard/group/events/{event_id}/publish"))
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::NO_CONTENT);
        assert_eq!(
            parts.headers.get("HX-Trigger").unwrap(),
            &HeaderValue::from_static("refresh-group-dashboard-table"),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_delete_success() {
        // Setup identifiers and data structures
        let event_id = Uuid::new_v4();
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
        db.expect_delete_event()
            .times(1)
            .withf(move |gid, eid| *gid == group_id && *eid == event_id)
            .returning(move |_, _| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("DELETE")
            .uri(format!("/dashboard/group/events/{event_id}/delete"))
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::NO_CONTENT);
        assert_eq!(
            parts.headers.get("HX-Trigger").unwrap(),
            &HeaderValue::from_static("refresh-group-dashboard-table"),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_unpublish_success() {
        // Setup identifiers and data structures
        let event_id = Uuid::new_v4();
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
        db.expect_unpublish_event()
            .times(1)
            .withf(move |gid, eid| *gid == group_id && *eid == event_id)
            .returning(move |_, _| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!("/dashboard/group/events/{event_id}/unpublish"))
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::NO_CONTENT);
        assert_eq!(
            parts.headers.get("HX-Trigger").unwrap(),
            &HeaderValue::from_static("refresh-group-dashboard-table"),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_update_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let recipient_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(group_id));
        let before = sample_event_summary(event_id, group_id);
        let after = EventSummary {
            starts_at: before.starts_at.map(|ts| ts + chrono::Duration::minutes(30)),
            ..before.clone()
        };
        let community = sample_community(community_id);
        let community_copy = community.clone();
        let event_form = sample_event_form();
        let body = serde_qs::to_string(&event_form).unwrap();

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
        db.expect_get_event_summary()
            .times(2)
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning({
                let mut first_call = true;
                move |_, _, _| {
                    let result = if first_call {
                        first_call = false;
                        before.clone()
                    } else {
                        after.clone()
                    };
                    Ok(result)
                }
            });
        db.expect_update_event()
            .times(1)
            .withf(move |gid, eid, event| {
                *gid == group_id && *eid == event_id && event.name == event_form.name
            })
            .returning(move |_, _, _| Ok(()));
        db.expect_list_event_attendees_ids()
            .times(1)
            .withf(move |eid| *eid == event_id)
            .returning(move |_| Ok(vec![recipient_id]));
        db.expect_get_community()
            .times(1)
            .withf(move |cid| *cid == community_id)
            .returning(move |_| Ok(community_copy.clone()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue()
            .times(1)
            .withf(move |notification| {
                matches!(notification.kind, NotificationKind::EventRescheduled)
                    && notification.recipients == vec![recipient_id]
                    && notification.template_data.as_ref().is_some_and(|value| {
                        from_value::<EventRescheduled>(value.clone())
                            .map(|template| {
                                template.link == "/group/test-group/event/sample-event"
                                    && template.theme.primary_color == community.theme.primary_color
                            })
                            .unwrap_or(false)
                    })
            })
            .returning(|_| Box::pin(async { Ok(()) }));

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!("/dashboard/group/events/{event_id}/update"))
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(Body::from(body))
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::NO_CONTENT);
        assert_eq!(
            parts.headers.get("HX-Trigger").unwrap(),
            &HeaderValue::from_static("refresh-group-dashboard-table"),
        );
        assert!(bytes.is_empty());
    }
}
