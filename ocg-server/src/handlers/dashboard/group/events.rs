//! HTTP handlers for managing events in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::{Html, IntoResponse},
};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CommunityId, SelectedGroupId},
    },
    templates::dashboard::group::events::{self, Event},
};

// Pages handlers.

/// Displays the page to add a new event.
#[instrument(skip_all, err)]
pub(crate) async fn add_page(
    CommunityId(community_id): CommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    let (categories, kinds, timezones) = tokio::try_join!(
        db.list_event_categories(community_id),
        db.list_event_kinds(),
        db.list_timezones()
    )?;
    let template = events::AddPage {
        group_id,
        categories,
        kinds,
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
    let (event, categories, kinds, timezones) = tokio::try_join!(
        db.get_event_full(event_id),
        db.list_event_categories(community_id),
        db.list_event_kinds(),
        db.list_timezones()
    )?;
    let template = events::UpdatePage {
        group_id,
        event,
        categories,
        kinds,
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
        [(
            "HX-Location",
            r#"{"path":"/dashboard/group?tab=events", "target":"body"}"#,
        )],
    )
        .into_response())
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
        [(
            "HX-Location",
            r#"{"path":"/dashboard/group?tab=events", "target":"body"}"#,
        )],
    )
        .into_response())
}

/// Updates an existing event's information in the database.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(serde_qs_de): State<serde_qs::Config>,
    Path(event_id): Path<Uuid>,
    body: String,
) -> Result<impl IntoResponse, HandlerError> {
    // Parse event information from body
    let event: Event = match serde_qs_de.deserialize_str(&body).map_err(anyhow::Error::new) {
        Ok(event) => event,
        Err(e) => return Ok((StatusCode::UNPROCESSABLE_ENTITY, e.to_string()).into_response()),
    };

    // Update event in database
    db.update_event(group_id, event_id, &event).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [(
            "HX-Location",
            r#"{"path":"/dashboard/group?tab=events", "target":"body"}"#,
        )],
    )
        .into_response())
}
