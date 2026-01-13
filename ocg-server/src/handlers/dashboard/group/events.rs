//! HTTP handlers for managing events in the group dashboard.

use std::collections::{HashMap, HashSet};

use anyhow::Result;
use askama::Template;
use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
    response::{Html, IntoResponse},
};
use chrono::{TimeDelta, Utc};
use garde::Validate;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    auth::AuthSession,
    config::{HttpServerConfig, MeetingsConfig},
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{SelectedCommunityId, SelectedGroupId, ValidatedFormQs},
    },
    services::{
        meetings::MeetingProvider,
        notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    },
    templates::{
        dashboard::group::events::{self, Event, PastEventUpdate},
        notifications::{EventCanceled, EventPublished, EventRescheduled, SpeakerWelcome},
    },
    types::event::EventSummary,
    util::{build_event_calendar_attachment, build_event_page_link},
};

// Minimum shift required to notify a reschedule.
const MIN_RESCHEDULE_SHIFT: TimeDelta = TimeDelta::minutes(15);

// Pages handlers.

/// Displays the page to add a new event.
#[instrument(skip_all, err)]
pub(crate) async fn add_page(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(meetings_cfg): State<Option<MeetingsConfig>>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let meetings_enabled = meetings_cfg.as_ref().is_some_and(MeetingsConfig::meetings_enabled);
    let meetings_max_participants = build_meetings_max_participants(meetings_cfg.as_ref());
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
        meetings_enabled,
        meetings_max_participants,
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
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(meetings_cfg): State<Option<MeetingsConfig>>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let meetings_enabled = meetings_cfg.as_ref().is_some_and(MeetingsConfig::meetings_enabled);
    let meetings_max_participants = build_meetings_max_participants(meetings_cfg.as_ref());
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
        meetings_enabled,
        meetings_max_participants,
        session_kinds,
        sponsors,
        timezones,
    };

    Ok(Html(template.render()?))
}

// JSON handlers.

/// Returns full event details in JSON format.
#[instrument(skip_all, err)]
pub(crate) async fn details(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    let event = db.get_event_full(community_id, group_id, event_id).await?;

    Ok(Json(event).into_response())
}

// Actions handlers.

/// Adds a new event to the database.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(meetings_cfg): State<Option<MeetingsConfig>>,
    ValidatedFormQs(event): ValidatedFormQs<Event>,
) -> Result<impl IntoResponse, HandlerError> {
    // Add event to database
    let cfg_max_participants = build_meetings_max_participants(meetings_cfg.as_ref());
    db.add_event(group_id, &event, &cfg_max_participants).await?;

    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    )
        .into_response())
}

/// Cancels an event (sets canceled=true).
#[instrument(skip_all, err)]
pub(crate) async fn cancel(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load event summary before canceling
    let event = db.get_event_summary(community_id, group_id, event_id).await?;

    // Mark event as canceled in database
    db.cancel_event(group_id, event_id).await?;

    // Notify attendees and speakers about canceled event
    let should_notify = matches!(
        (event.published, event.canceled, event.starts_at),
        (true, false, Some(starts_at)) if starts_at > Utc::now()
    );
    if should_notify {
        // Fetch event full and attendee IDs concurrently
        let (event_full, attendee_ids) = tokio::try_join!(
            db.get_event_full(community_id, group_id, event_id),
            db.list_event_attendees_ids(group_id, event_id)
        )?;

        // Combine attendee and speaker IDs (deduplicated)
        let speaker_ids = event_full.speakers_ids();
        let recipients: Vec<Uuid> = attendee_ids
            .into_iter()
            .chain(speaker_ids)
            .collect::<HashSet<_>>()
            .into_iter()
            .collect();

        if !recipients.is_empty() {
            let site_settings = db.get_site_settings().await?;
            let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
            let event_summary = EventSummary::from(&event_full);
            let link = build_event_page_link(base_url, &event_summary);
            let calendar_ics = build_event_calendar_attachment(base_url, &event_summary);
            let template_data = EventCanceled {
                event: event_summary,
                link,
                theme: site_settings.theme,
            };
            let notification = NewNotification {
                attachments: vec![calendar_ics],
                kind: NotificationKind::EventCanceled,
                recipients,
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
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Load event summary before publishing
    let event = db.get_event_summary(community_id, group_id, event_id).await?;

    // Mark event as published in database
    db.publish_event(group_id, event_id, user.user_id).await?;

    // Notify group members and speakers about published event
    let should_notify = matches!(
        (event.published, event.starts_at),
        (false, Some(starts_at)) if starts_at > Utc::now()
    );
    if should_notify {
        // Fetch event full and group member IDs concurrently
        let (event_full, all_member_ids) = tokio::try_join!(
            db.get_event_full(community_id, group_id, event_id),
            db.list_group_members_ids(group_id)
        )?;

        // Extract speaker IDs
        let speaker_ids = event_full.speakers_ids();
        let has_speakers = !speaker_ids.is_empty();

        // Filter out speakers from member IDs (they get a separate notification)
        let member_ids: Vec<Uuid> = all_member_ids
            .into_iter()
            .filter(|id| !speaker_ids.contains(id))
            .collect();
        let has_members = !member_ids.is_empty();

        if has_members || has_speakers {
            // Prepare common data for notifications
            let site_settings = db.get_site_settings().await?;
            let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
            let event_summary = EventSummary::from(&event_full);
            let link = build_event_page_link(base_url, &event_summary);
            let calendar_ics = build_event_calendar_attachment(base_url, &event_summary);

            // Notify group members about published event
            if has_members {
                let template_data = EventPublished {
                    event: event_summary.clone(),
                    link: link.clone(),
                    theme: site_settings.theme.clone(),
                };
                let notification = NewNotification {
                    attachments: vec![calendar_ics.clone()],
                    kind: NotificationKind::EventPublished,
                    recipients: member_ids,
                    template_data: Some(serde_json::to_value(&template_data)?),
                };
                notifications_manager.enqueue(&notification).await?;
            }

            // Notify speakers about being added to the event
            if has_speakers {
                let template_data = SpeakerWelcome {
                    event: event_summary,
                    link,
                    theme: site_settings.theme,
                };
                let notification = NewNotification {
                    attachments: vec![calendar_ics],
                    kind: NotificationKind::SpeakerWelcome,
                    recipients: speaker_ids,
                    template_data: Some(serde_json::to_value(&template_data)?),
                };
                notifications_manager.enqueue(&notification).await?;
            }
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
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(meetings_cfg): State<Option<MeetingsConfig>>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(serde_qs_de): State<serde_qs::Config>,
    State(server_cfg): State<HttpServerConfig>,
    Path(event_id): Path<Uuid>,
    body: String,
) -> Result<impl IntoResponse, HandlerError> {
    // Load event summary before update to detect reschedule and if it is past
    let before = db.get_event_summary(community_id, group_id, event_id).await?;

    // For past events, deserialize as PastEventUpdate (limited fields)
    if before.is_past() {
        let event: PastEventUpdate = serde_qs_de
            .deserialize_str(&body)
            .map_err(|e| HandlerError::Deserialization(e.to_string()))?;
        event.validate()?;

        // Update event in database (no reschedule notifications for past events)
        let event_json = serde_json::to_value(&event)?;
        db.update_event(group_id, event_id, &event_json, &HashMap::new())
            .await?;

        return Ok((
            StatusCode::NO_CONTENT,
            [("HX-Trigger", "refresh-group-dashboard-table")],
        )
            .into_response());
    }

    // For non-past events, deserialize as full Event
    let event: Event = serde_qs_de
        .deserialize_str(&body)
        .map_err(|e| HandlerError::Deserialization(e.to_string()))?;
    event.validate()?;

    // Update event in database
    let cfg_max_participants = build_meetings_max_participants(meetings_cfg.as_ref());
    let event_json = serde_json::to_value(&event)?;
    db.update_event(group_id, event_id, &event_json, &cfg_max_participants)
        .await?;

    // Notify attendees and speakers if event was rescheduled
    let after = db.get_event_summary(community_id, group_id, event_id).await?;
    let should_notify = match (before.published, before.starts_at, after.starts_at) {
        (true, Some(b_starts_at), Some(a_starts_at)) if a_starts_at > Utc::now() => {
            (a_starts_at - b_starts_at).abs() >= MIN_RESCHEDULE_SHIFT
        }
        _ => false,
    };
    if should_notify {
        // Fetch event full and attendee IDs concurrently
        let (event_full, attendee_ids) = tokio::try_join!(
            db.get_event_full(community_id, group_id, event_id),
            db.list_event_attendees_ids(group_id, event_id)
        )?;

        // Combine attendee and speaker IDs (deduplicated)
        let speaker_ids = event_full.speakers_ids();
        let recipients: Vec<Uuid> = attendee_ids
            .into_iter()
            .chain(speaker_ids)
            .collect::<HashSet<_>>()
            .into_iter()
            .collect();

        if !recipients.is_empty() {
            let site_settings = db.get_site_settings().await?;
            let base = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
            let event_summary = EventSummary::from(&event_full);
            let link = build_event_page_link(base, &event_summary);
            let calendar_ics = build_event_calendar_attachment(base, &event_summary);
            let template_data = EventRescheduled {
                event: event_summary,
                link,
                theme: site_settings.theme,
            };
            let notification = NewNotification {
                attachments: vec![calendar_ics],
                kind: NotificationKind::EventRescheduled,
                recipients,
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

// Helpers.

/// Builds a `HashMap` of meeting provider to max participants from config.
fn build_meetings_max_participants(meetings_cfg: Option<&MeetingsConfig>) -> HashMap<MeetingProvider, i32> {
    let mut map = HashMap::new();
    if let Some(cfg) = meetings_cfg
        && let Some(zoom) = &cfg.zoom
    {
        map.insert(MeetingProvider::Zoom, zoom.max_participants);
    }
    map
}

// Tests.

#[cfg(test)]
mod tests {
    use axum::{
        body::{Body, to_bytes},
        http::{
            HeaderValue, Request, StatusCode,
            header::{CACHE_CONTROL, CONTENT_TYPE, COOKIE},
        },
    };
    use axum_login::tower_sessions::session;
    use chrono::Utc;
    use serde_json::{from_slice, from_value, to_value};
    use tower::ServiceExt;
    use uuid::Uuid;

    use crate::{
        config::{MeetingsConfig, MeetingsZoomConfig},
        db::mock::MockDB,
        handlers::tests::*,
        router::CACHE_CONTROL_NO_CACHE,
        services::{
            meetings::MeetingProvider,
            notifications::{MockNotificationsManager, NotificationKind},
        },
        templates::{
            dashboard::group::events::PastEventUpdate,
            notifications::{EventCanceled, EventPublished, EventRescheduled, SpeakerWelcome},
        },
        types::event::{EventFull, EventSummary, Speaker},
    };

    #[tokio::test]
    async fn test_add_page_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));
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
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/group/events/add")
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
        let community_id = Uuid::new_v4();
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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));
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
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/group/events")
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
        let session_record = sample_session_record(
            session_id,
            user_id,
            &auth_hash,
            Some(community_id),
            Some(group_id),
        );
        let event_full = sample_event_full(community_id, event_id, group_id);
        let event_full_db = event_full.clone();
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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));
        db.expect_get_event_full()
            .times(1)
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(event_full_db.clone()));
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
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri(format!("/dashboard/group/events/{event_id}/update"))
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
    async fn test_details_success() {
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
        let event_full = sample_event_full(community_id, event_id, group_id);
        let event_full_db = event_full.clone();

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
        db.expect_get_event_full()
            .times(1)
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(event_full_db.clone()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri(format!("/dashboard/group/events/{event_id}/details"))
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();
        let payload: EventFull = from_slice(&bytes).unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::OK);
        assert_eq!(
            parts.headers.get(CONTENT_TYPE).unwrap(),
            &HeaderValue::from_static("application/json"),
        );
        assert_eq!(to_value(payload).unwrap(), to_value(event_full).unwrap());
    }

    #[tokio::test]
    async fn test_add_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));
        db.expect_add_event()
            .times(1)
            .withf(move |id, event, cfg_max_participants| {
                *id == group_id
                    && event.name == event_form.name
                    && cfg_max_participants.get(&MeetingProvider::Zoom) == Some(&100)
            })
            .returning(move |_, _, _| Ok(Uuid::new_v4()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup meetings config with Zoom
        let meetings_cfg = MeetingsConfig {
            zoom: Some(MeetingsZoomConfig {
                account_id: "test-account".to_string(),
                client_id: "test-client".to_string(),
                client_secret: "test-secret".to_string(),
                enabled: true,
                max_participants: 100,
                webhook_secret_token: "test-token".to_string(),
            }),
        };

        // Setup router with meetings config and send request
        let router = TestRouterBuilder::new(db, nm)
            .with_meetings_cfg(meetings_cfg)
            .build()
            .await;
        let request = Request::builder()
            .method("POST")
            .uri("/dashboard/group/events/add")
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
        let community_id = Uuid::new_v4();
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

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("POST")
            .uri("/dashboard/group/events/add")
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
        let attendee_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let speaker_id = Uuid::new_v4();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(
            session_id,
            user_id,
            &auth_hash,
            Some(community_id),
            Some(group_id),
        );
        let event_summary = sample_event_summary(event_id, group_id);
        let event_full = EventFull {
            speakers: vec![Speaker {
                featured: false,
                user: sample_template_user_with_id(speaker_id),
            }],
            ..sample_event_full(community_id, event_id, group_id)
        };
        let site_settings = sample_site_settings();
        let site_settings_for_notifications = site_settings.clone();

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
            .returning(move |_, _, _| Ok(event_summary.clone()));
        db.expect_cancel_event()
            .times(1)
            .withf(move |id, eid| *id == group_id && *eid == event_id)
            .returning(move |_, _| Ok(()));
        db.expect_get_event_full()
            .times(1)
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(event_full.clone()));
        db.expect_list_event_attendees_ids()
            .times(1)
            .withf(move |gid, eid| *gid == group_id && *eid == event_id)
            .returning(move |_, _| Ok(vec![attendee_id]));
        db.expect_get_site_settings()
            .times(1)
            .returning(move || Ok(site_settings.clone()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue()
            .times(1)
            .withf(move |notification| {
                matches!(notification.kind, NotificationKind::EventCanceled)
                    && notification.recipients.len() == 2
                    && notification.recipients.contains(&attendee_id)
                    && notification.recipients.contains(&speaker_id)
                    && notification.template_data.as_ref().is_some_and(|value| {
                        from_value::<EventCanceled>(value.clone())
                            .map(|template| {
                                template.link == "/test/group/npq6789/event/abc1234"
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
            .method("PUT")
            .uri(format!("/dashboard/group/events/{event_id}/cancel"))
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

    #[allow(clippy::too_many_lines)]
    #[tokio::test]
    async fn test_publish_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let member_id = Uuid::new_v4();
        let speaker_id = Uuid::new_v4();
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
        let unpublished_event = EventSummary {
            published: false,
            ..sample_event_summary(event_id, group_id)
        };
        let event_full = EventFull {
            speakers: vec![Speaker {
                featured: false,
                user: sample_template_user_with_id(speaker_id),
            }],
            ..sample_event_full(community_id, event_id, group_id)
        };
        let site_settings = sample_site_settings();
        let site_settings_for_member_notification = site_settings.clone();
        let site_settings_for_speaker_notification = site_settings.clone();

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
            .returning(move |_, _, _| Ok(unpublished_event.clone()));
        db.expect_publish_event()
            .times(1)
            .withf(move |gid, eid, uid| *gid == group_id && *eid == event_id && *uid == user_id)
            .returning(move |_, _, _| Ok(()));
        db.expect_get_event_full()
            .times(1)
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(event_full.clone()));
        db.expect_list_group_members_ids()
            .times(1)
            .withf(move |gid| *gid == group_id)
            .returning(move |_| Ok(vec![member_id]));
        db.expect_get_site_settings()
            .times(1)
            .returning(move || Ok(site_settings.clone()));

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
                                template.theme.primary_color
                                    == site_settings_for_member_notification.theme.primary_color
                            })
                            .unwrap_or(false)
                    })
            })
            .returning(|_| Box::pin(async { Ok(()) }));
        nm.expect_enqueue()
            .times(1)
            .withf(move |notification| {
                matches!(notification.kind, NotificationKind::SpeakerWelcome)
                    && notification.recipients == vec![speaker_id]
                    && notification.template_data.as_ref().is_some_and(|value| {
                        from_value::<SpeakerWelcome>(value.clone())
                            .map(|template| {
                                template.theme.primary_color
                                    == site_settings_for_speaker_notification.theme.primary_color
                            })
                            .unwrap_or(false)
                    })
            })
            .returning(|_| Box::pin(async { Ok(()) }));

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!("/dashboard/group/events/{event_id}/publish"))
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
    async fn test_publish_already_published_no_notification() {
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
        // Event is already published, so no notification should be sent
        let already_published_event = EventSummary {
            published: true,
            ..sample_event_summary(event_id, group_id)
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
        db.expect_get_event_summary()
            .times(1)
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(already_published_event.clone()));
        db.expect_publish_event()
            .times(1)
            .withf(move |gid, eid, uid| *gid == group_id && *eid == event_id && *uid == user_id)
            .returning(move |_, _, _| Ok(()));

        // Setup notifications manager mock (no enqueue expected)
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!("/dashboard/group/events/{event_id}/publish"))
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
    async fn test_publish_speakers_only() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let speaker_id = Uuid::new_v4();
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
        let unpublished_event = EventSummary {
            published: false,
            ..sample_event_summary(event_id, group_id)
        };
        let event_full = EventFull {
            speakers: vec![Speaker {
                featured: false,
                user: sample_template_user_with_id(speaker_id),
            }],
            ..sample_event_full(community_id, event_id, group_id)
        };
        let site_settings = sample_site_settings();
        let site_settings_for_speaker_notification = site_settings.clone();

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
            .returning(move |_, _, _| Ok(unpublished_event.clone()));
        db.expect_publish_event()
            .times(1)
            .withf(move |gid, eid, uid| *gid == group_id && *eid == event_id && *uid == user_id)
            .returning(move |_, _, _| Ok(()));
        db.expect_get_event_full()
            .times(1)
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(event_full.clone()));
        // No group members
        db.expect_list_group_members_ids()
            .times(1)
            .withf(move |gid| *gid == group_id)
            .returning(move |_| Ok(vec![]));
        db.expect_get_site_settings()
            .times(1)
            .returning(move || Ok(site_settings.clone()));

        // Setup notifications manager mock - only speaker notification expected
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue()
            .times(1)
            .withf(move |notification| {
                matches!(notification.kind, NotificationKind::SpeakerWelcome)
                    && notification.recipients == vec![speaker_id]
                    && notification.template_data.as_ref().is_some_and(|value| {
                        from_value::<SpeakerWelcome>(value.clone())
                            .map(|template| {
                                template.theme.primary_color
                                    == site_settings_for_speaker_notification.theme.primary_color
                            })
                            .unwrap_or(false)
                    })
            })
            .returning(|_| Box::pin(async { Ok(()) }));

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!("/dashboard/group/events/{event_id}/publish"))
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
        db.expect_delete_event()
            .times(1)
            .withf(move |gid, eid| *gid == group_id && *eid == event_id)
            .returning(move |_, _| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("DELETE")
            .uri(format!("/dashboard/group/events/{event_id}/delete"))
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
        db.expect_unpublish_event()
            .times(1)
            .withf(move |gid, eid| *gid == group_id && *eid == event_id)
            .returning(move |_, _| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!("/dashboard/group/events/{event_id}/unpublish"))
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
    #[allow(clippy::too_many_lines)]
    async fn test_update_success() {
        // Setup identifiers and data structures
        let attendee_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let speaker_id = Uuid::new_v4();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(
            session_id,
            user_id,
            &auth_hash,
            Some(community_id),
            Some(group_id),
        );
        let before = sample_event_summary(event_id, group_id);
        let after = EventSummary {
            starts_at: before.starts_at.map(|ts| ts + chrono::Duration::minutes(30)),
            ..before.clone()
        };
        let event_full = EventFull {
            speakers: vec![Speaker {
                featured: false,
                user: sample_template_user_with_id(speaker_id),
            }],
            ..sample_event_full(community_id, event_id, group_id)
        };
        let site_settings = sample_site_settings();
        let site_settings_for_notifications = site_settings.clone();
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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));
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
            .withf(move |gid, eid, event, cfg_max_participants| {
                *gid == group_id
                    && *eid == event_id
                    && event.get("name").and_then(|v| v.as_str()) == Some(event_form.name.as_str())
                    && cfg_max_participants.is_empty()
            })
            .returning(move |_, _, _, _| Ok(()));
        db.expect_get_event_full()
            .times(1)
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(event_full.clone()));
        db.expect_list_event_attendees_ids()
            .times(1)
            .withf(move |gid, eid| *gid == group_id && *eid == event_id)
            .returning(move |_, _| Ok(vec![attendee_id]));
        db.expect_get_site_settings()
            .times(1)
            .returning(move || Ok(site_settings.clone()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue()
            .times(1)
            .withf(move |notification| {
                matches!(notification.kind, NotificationKind::EventRescheduled)
                    && notification.recipients.len() == 2
                    && notification.recipients.contains(&attendee_id)
                    && notification.recipients.contains(&speaker_id)
                    && notification.template_data.as_ref().is_some_and(|value| {
                        from_value::<EventRescheduled>(value.clone())
                            .map(|template| {
                                template.link == "/test/group/npq6789/event/abc1234"
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
            .method("PUT")
            .uri(format!("/dashboard/group/events/{event_id}/update"))
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

    #[tokio::test]
    async fn test_update_no_notification_when_shift_too_small() {
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
        let before = sample_event_summary(event_id, group_id);
        // Shift by only 10 minutes (below MIN_RESCHEDULE_SHIFT of 15 minutes)
        let after = EventSummary {
            starts_at: before.starts_at.map(|ts| ts + chrono::Duration::minutes(10)),
            ..before.clone()
        };
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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));
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
            .withf(move |gid, eid, event, cfg_max_participants| {
                *gid == group_id
                    && *eid == event_id
                    && event.get("name").and_then(|v| v.as_str()) == Some(event_form.name.as_str())
                    && cfg_max_participants.is_empty()
            })
            .returning(move |_, _, _, _| Ok(()));

        // Setup notifications manager mock (no enqueue expected - shift too small)
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!("/dashboard/group/events/{event_id}/update"))
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

    #[tokio::test]
    async fn test_update_no_notification_when_unpublished() {
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
        // Event is unpublished, so no reschedule notification should be sent
        let before = EventSummary {
            published: false,
            ..sample_event_summary(event_id, group_id)
        };
        // Significant reschedule (30 minutes), but event is unpublished
        let after = EventSummary {
            starts_at: before.starts_at.map(|ts| ts + chrono::Duration::minutes(30)),
            ..before.clone()
        };
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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));
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
            .withf(move |gid, eid, event, cfg_max_participants| {
                *gid == group_id
                    && *eid == event_id
                    && event.get("name").and_then(|v| v.as_str()) == Some(event_form.name.as_str())
                    && cfg_max_participants.is_empty()
            })
            .returning(move |_, _, _, _| Ok(()));

        // Setup notifications manager mock (no enqueue expected - event unpublished)
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!("/dashboard/group/events/{event_id}/update"))
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

    #[tokio::test]
    async fn test_update_past_event_success() {
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
        let past_event = {
            let past_time = Utc::now() - chrono::Duration::hours(2);
            EventSummary {
                ends_at: Some(past_time + chrono::Duration::hours(1)),
                starts_at: Some(past_time),
                ..sample_event_summary(event_id, group_id)
            }
        };
        let past_event_update = PastEventUpdate {
            description: "Updated past event description".to_string(),
            banner_url: Some("https://example.test/new-banner.png".to_string()),
            description_short: Some("Updated short".to_string()),
            ..Default::default()
        };
        let body = serde_qs::to_string(&past_event_update).unwrap();

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
            .returning(move |_, _, _| Ok(past_event.clone()));
        db.expect_update_event()
            .times(1)
            .withf(move |gid, eid, event, cfg_max_participants| {
                *gid == group_id
                    && *eid == event_id
                    && event.get("description").and_then(|v| v.as_str())
                        == Some("Updated past event description")
                    && cfg_max_participants.is_empty()
            })
            .returning(move |_, _, _, _| Ok(()));

        // Setup notifications manager mock (no expectations - past events don't notify)
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!("/dashboard/group/events/{event_id}/update"))
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
