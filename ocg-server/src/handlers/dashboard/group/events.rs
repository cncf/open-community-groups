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
        db.get_event_full(event_id),
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

/// Archives an event (sets published=false and clears publication metadata).
#[instrument(skip_all, err)]
pub(crate) async fn archive(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Mark event as archived in database
    db.archive_event(group_id, event_id).await?;

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-events-table")]))
}

/// Cancels an event (sets canceled=true).
#[instrument(skip_all, err)]
pub(crate) async fn cancel(
    SelectedGroupId(group_id): SelectedGroupId,
    State(cfg): State<HttpServerConfig>,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load event summary before canceling
    let mut event = db.get_event_summary(event_id).await?;

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
    SelectedGroupId(group_id): SelectedGroupId,
    State(cfg): State<HttpServerConfig>,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Load event summary before publishing
    let event = db.get_event_summary(event_id).await?;

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
            let event = db.get_event_summary(event_id).await?;
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

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-events-table")]))
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

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-events-table")]))
}

/// Updates an existing event's information in the database.
#[instrument(skip_all, err)]
pub(crate) async fn update(
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
    let before = db.get_event_summary(event_id).await?;

    // Update event in database
    db.update_event(group_id, event_id, &event).await?;

    // Notify attendees if event was rescheduled
    let after = db.get_event_summary(event_id).await?;
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

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-events-table")]).into_response())
}
