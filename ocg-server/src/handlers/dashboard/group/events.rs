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
            let template_data = EventCanceled { link, event };
            let notification = NewNotification {
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
            let event = db.get_event_summary(community_id, group_id, event_id).await?;
            let base_url = cfg.base_url.strip_suffix('/').unwrap_or(&cfg.base_url);
            let link = format!("{}/group/{}/event/{}", base_url, event.group_slug, event.slug);
            let template_data = EventPublished { link, event };
            let notification = NewNotification {
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
            let template_data = EventRescheduled { event: after, link };
            let notification = NewNotification {
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
    use std::collections::{BTreeMap, HashMap};

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
    use serde_json::{from_value, json};
    use time::{Duration as TimeDuration, OffsetDateTime};
    use tower::ServiceExt;
    use uuid::Uuid;

    use crate::{
        auth::User as AuthUser,
        db::mock::MockDB,
        handlers::auth::SELECTED_GROUP_ID_KEY,
        router::setup_test_router,
        services::notifications::{MockNotificationsManager, NotificationKind},
        templates::{
            dashboard::group::events::{Event, GroupEvents},
            notifications::{EventCanceled, EventPublished, EventRescheduled},
        },
        types::{
            event::{
                EventCategory, EventFull, EventKind, EventKindSummary, EventSummary, SessionKindSummary,
            },
            group::{GroupCategory, GroupRegion, GroupSponsor, GroupSummary},
        },
    };

    #[tokio::test]
    async fn test_add_page_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, group_id, &auth_hash);
        let category = sample_event_category();
        let kind = sample_event_kind_summary();
        let session_kind = sample_session_kind_summary();
        let sponsor = sample_group_sponsor();
        let timezones = vec!["UTC".to_string()];

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
        db.expect_list_event_categories()
            .withf(move |cid| *cid == community_id)
            .returning(move |_| Ok(vec![category.clone()]));
        db.expect_list_event_kinds().returning(move || Ok(vec![kind.clone()]));
        db.expect_list_session_kinds()
            .returning(move || Ok(vec![session_kind.clone()]));
        db.expect_list_group_sponsors()
            .withf(move |id| *id == group_id)
            .returning(move |_| Ok(vec![sponsor.clone()]));
        db.expect_list_timezones().returning(move || Ok(timezones.clone()));

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
            &HeaderValue::from_static("max-age=0"),
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
        let session_record = sample_session_record(session_id, user_id, group_id, &auth_hash);
        let group_events = sample_group_events();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_list_group_events()
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
            &HeaderValue::from_static("max-age=0"),
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
        let session_record = sample_session_record(session_id, user_id, group_id, &auth_hash);
        let event_full = sample_event_full(event_id, group_id);
        let category = sample_event_category();
        let kind = sample_event_kind_summary();
        let session_kind = sample_session_kind_summary();
        let sponsor = sample_group_sponsor();
        let timezones = vec!["UTC".to_string()];

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
        db.expect_get_event_full()
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(event_full.clone()));
        db.expect_list_event_categories()
            .withf(move |cid| *cid == community_id)
            .returning(move |_| Ok(vec![category.clone()]));
        db.expect_list_event_kinds().returning(move || Ok(vec![kind.clone()]));
        db.expect_list_session_kinds()
            .returning(move || Ok(vec![session_kind.clone()]));
        db.expect_list_group_sponsors()
            .withf(move |id| *id == group_id)
            .returning(move |_| Ok(vec![sponsor.clone()]));
        db.expect_list_timezones().returning(move || Ok(timezones.clone()));

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
            &HeaderValue::from_static("max-age=0"),
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
        let session_record = sample_session_record(session_id, user_id, group_id, &auth_hash);
        let event_form = sample_event_form();
        let body = serde_qs::to_string(&event_form).unwrap();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_add_event()
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
        let session_record = sample_session_record(session_id, user_id, group_id, &auth_hash);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
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
        let session_record = sample_session_record(session_id, user_id, group_id, &auth_hash);
        let event_summary = sample_event_summary(event_id, group_id);

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
        db.expect_get_event_summary()
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(event_summary.clone()));
        db.expect_cancel_event()
            .withf(move |id, eid| *id == group_id && *eid == event_id)
            .returning(move |_, _| Ok(()));
        db.expect_list_event_attendees_ids()
            .withf(move |eid| *eid == event_id)
            .returning(move |_| Ok(vec![recipient_id]));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue()
            .withf(move |notification| {
                matches!(notification.kind, NotificationKind::EventCanceled)
                    && notification.recipients == vec![recipient_id]
                    && notification.template_data.as_ref().is_some_and(|value| {
                        from_value::<EventCanceled>(value.clone())
                            .map(|template| template.link == "/group/test-group/event/sample-event")
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
        let session_record = sample_session_record(session_id, user_id, group_id, &auth_hash);
        let unpublished_event = EventSummary {
            published: false,
            ..sample_event_summary(event_id, group_id)
        };
        let published_event = sample_event_summary(event_id, group_id);

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
        db.expect_get_event_summary()
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .times(2)
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
            .withf(move |gid, eid, uid| *gid == group_id && *eid == event_id && *uid == user_id)
            .returning(move |_, _, _| Ok(()));
        db.expect_list_group_members_ids()
            .withf(move |gid| *gid == group_id)
            .returning(move |_| Ok(vec![member_id]));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue()
            .withf(move |notification| {
                matches!(notification.kind, NotificationKind::EventPublished)
                    && notification.recipients == vec![member_id]
                    && notification.template_data.as_ref().is_some_and(|value| {
                        from_value::<EventPublished>(value.clone())
                            .map(|template| template.link == "/group/test-group/event/sample-event")
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
        let session_record = sample_session_record(session_id, user_id, group_id, &auth_hash);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_delete_event()
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
        let session_record = sample_session_record(session_id, user_id, group_id, &auth_hash);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_unpublish_event()
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
        let session_record = sample_session_record(session_id, user_id, group_id, &auth_hash);
        let before = sample_event_summary(event_id, group_id);
        let after = EventSummary {
            starts_at: before.starts_at.map(|ts| ts + chrono::Duration::minutes(30)),
            ..before.clone()
        };
        let event_form = sample_event_form();
        let body = serde_qs::to_string(&event_form).unwrap();

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
        db.expect_get_event_summary()
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .times(2)
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
            .withf(move |gid, eid, event| {
                *gid == group_id && *eid == event_id && event.name == event_form.name
            })
            .returning(move |_, _, _| Ok(()));
        db.expect_list_event_attendees_ids()
            .withf(move |eid| *eid == event_id)
            .returning(move |_| Ok(vec![recipient_id]));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue()
            .withf(move |notification| {
                matches!(notification.kind, NotificationKind::EventRescheduled)
                    && notification.recipients == vec![recipient_id]
                    && notification.template_data.as_ref().is_some_and(|value| {
                        from_value::<EventRescheduled>(value.clone())
                            .map(|template| template.link == "/group/test-group/event/sample-event")
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

    // Helpers.

    /// Helper to create a sample authenticated user for tests.
    fn sample_auth_user(user_id: Uuid, auth_hash: &str) -> AuthUser {
        AuthUser {
            auth_hash: auth_hash.to_string(),
            email: "user@example.test".to_string(),
            email_verified: true,
            name: "Test User".to_string(),
            user_id,
            username: "test-user".to_string(),
            belongs_to_any_group_team: Some(true),
            ..Default::default()
        }
    }

    /// Helper to create a sample event category for tests.
    fn sample_event_category() -> EventCategory {
        EventCategory {
            event_category_id: Uuid::new_v4(),
            name: "Meetup".to_string(),
            slug: "meetup".to_string(),
        }
    }

    /// Helper to create a sample event form payload.
    fn sample_event_form() -> Event {
        Event {
            name: "Sample Event".to_string(),
            slug: "sample-event".to_string(),
            description: "Event description".to_string(),
            timezone: "UTC".to_string(),
            category_id: Uuid::new_v4(),
            kind_id: "virtual".to_string(),

            banner_url: Some("https://example.test/banner.png".to_string()),
            capacity: Some(100),
            description_short: Some("Short".to_string()),
            ends_at: None,
            hosts: None,
            logo_url: None,
            meetup_url: None,
            photos_urls: None,
            recording_url: None,
            registration_required: Some(true),
            sessions: None,
            sponsors: None,
            starts_at: None,
            streaming_url: None,
            tags: None,
            venue_address: None,
            venue_city: None,
            venue_name: None,
            venue_zip_code: None,
        }
    }

    /// Helper to create a sample event full record for tests.
    fn sample_event_full(event_id: Uuid, group_id: Uuid) -> EventFull {
        let group = sample_group_summary(group_id);
        let mut sessions = BTreeMap::new();
        sessions.insert(
            Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap().date_naive(),
            vec![],
        );
        EventFull {
            canceled: false,
            category_name: "Meetup".to_string(),
            color: "#123456".to_string(),
            created_at: Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap(),
            description: "Event description".to_string(),
            group,
            hosts: Vec::new(),
            event_id,
            kind: EventKind::Virtual,
            name: "Sample Event".to_string(),
            organizers: Vec::new(),
            published: true,
            sessions,
            slug: "sample-event".to_string(),
            sponsors: Vec::new(),
            timezone: UTC,

            banner_url: Some("https://example.test/banner.png".to_string()),
            capacity: Some(100),
            description_short: Some("Short".to_string()),
            ends_at: None,
            latitude: None,
            legacy_hosts: None,
            legacy_speakers: None,
            logo_url: Some("https://example.test/logo.png".to_string()),
            longitude: None,
            meetup_url: None,
            photos_urls: None,
            published_at: None,
            recording_url: None,
            registration_required: Some(true),
            starts_at: Some(Utc::now() + chrono::Duration::hours(1)),
            streaming_url: None,
            tags: None,
            venue_address: None,
            venue_city: None,
            venue_name: None,
            venue_zip_code: None,
        }
    }

    /// Helper to create a sample event kind summary for tests.
    fn sample_event_kind_summary() -> EventKindSummary {
        EventKindSummary {
            event_kind_id: "virtual".to_string(),
            display_name: "Virtual".to_string(),
        }
    }

    /// Helper to create sample group events for tests.
    fn sample_group_events() -> GroupEvents {
        let summary = sample_event_summary(Uuid::new_v4(), Uuid::new_v4());
        GroupEvents {
            past: vec![summary.clone()],
            upcoming: vec![summary],
        }
    }

    /// Helper to create a sample group sponsor for tests.
    fn sample_group_sponsor() -> GroupSponsor {
        GroupSponsor {
            group_sponsor_id: Uuid::new_v4(),
            logo_url: "https://example.test/logo.png".to_string(),
            name: "Sponsor".to_string(),

            website_url: Some("https://example.test".to_string()),
        }
    }

    /// Helper to create a sample group summary for tests.
    fn sample_group_summary(group_id: Uuid) -> GroupSummary {
        GroupSummary {
            active: true,
            category: sample_group_category(),
            color: "#123456".to_string(),
            created_at: Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap(),
            group_id,
            name: "Test Group".to_string(),
            slug: "test-group".to_string(),

            city: Some("Test City".to_string()),
            country_code: Some("US".to_string()),
            country_name: Some("United States".to_string()),
            logo_url: Some("https://example.test/logo.png".to_string()),
            region: Some(sample_group_region()),
            state: Some("MA".to_string()),
        }
    }

    /// Helper to create a sample event summary for tests.
    fn sample_event_summary(event_id: Uuid, _group_id: Uuid) -> EventSummary {
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
            starts_at: Some(Utc::now() + chrono::Duration::hours(1)),
            venue_city: Some("Boston".to_string()),
        }
    }

    /// Helper to create a sample group category for tests.
    fn sample_group_category() -> GroupCategory {
        GroupCategory {
            group_category_id: Uuid::new_v4(),
            name: "Meetup".to_string(),
            normalized_name: "meetup".to_string(),
            order: Some(1),
        }
    }

    /// Helper to create a sample group region for tests.
    fn sample_group_region() -> GroupRegion {
        GroupRegion {
            name: "North America".to_string(),
            normalized_name: "north-america".to_string(),
            order: Some(1),
            region_id: Uuid::new_v4(),
        }
    }

    /// Helper to create a sample session kind summary for tests.
    fn sample_session_kind_summary() -> SessionKindSummary {
        SessionKindSummary {
            display_name: "Keynote".to_string(),
            session_kind_id: "hybrid".to_string(),
        }
    }

    /// Helper to create a sample session record with selected group ID.
    fn sample_session_record(
        session_id: session::Id,
        user_id: Uuid,
        group_id: Uuid,
        auth_hash: &str,
    ) -> session::Record {
        let mut data = HashMap::new();
        data.insert(
            "axum-login.data".to_string(),
            json!({
                "user_id": user_id,
                "auth_hash": auth_hash.as_bytes(),
            }),
        );
        data.insert(SELECTED_GROUP_ID_KEY.to_string(), json!(group_id));
        session::Record {
            data,
            expiry_date: OffsetDateTime::now_utc().saturating_add(TimeDuration::days(1)),
            id: session_id,
        }
    }
}
