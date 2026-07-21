//! Group event discovery configuration handlers.

use askama::Template;
use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
    response::{Html, IntoResponse},
};
use garde::Validate;
use serde::{Deserialize, Serialize};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedAllianceId, SelectedGroupId, ValidatedForm},
    },
    integrations::you_com::validate_source_url,
    services::event_discovery::ManualEventDiscovery,
    templates::dashboard::group::integrations::Page,
    types::permissions::GroupPermission,
};

/// Displays source URLs, settings, and the latest ingestion result.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    Ok(Html(
        prepare_page(&db, alliance_id, group_id, user.user_id)
            .await?
            .render()?,
    ))
}

/// Starts an authorized discovery run for the selected group.
#[instrument(skip_all, err)]
pub(crate) async fn run(
    SelectedGroupId(group_id): SelectedGroupId,
    State(manual_event_discovery): State<Option<ManualEventDiscovery>>,
) -> Result<impl IntoResponse, HandlerError> {
    let Some(manual_event_discovery) = manual_event_discovery else {
        return Ok(StatusCode::NOT_FOUND.into_response());
    };
    if !manual_event_discovery.enabled() {
        return Ok(StatusCode::NOT_FOUND.into_response());
    }

    manual_event_discovery.spawn_group_run(group_id);
    Ok((
        StatusCode::ACCEPTED,
        [("HX-Trigger", "event-discovery-run-started")],
        Json(ManualRunResponse {
            group_id,
            status: "accepted",
        }),
    )
        .into_response())
}

/// Updates enabled state and location settings.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    ValidatedForm(input): ValidatedForm<SettingsInput>,
) -> Result<impl IntoResponse, HandlerError> {
    validate_settings(&input)?;
    db.update_group_event_integration(
        user.user_id,
        group_id,
        input.enabled,
        input.city.trim(),
        input.timezone.trim(),
    )
    .await?;
    Ok(Html(
        prepare_page(&db, alliance_id, group_id, user.user_id)
            .await?
            .render()?,
    ))
}

/// Adds a source URL after server-side URL validation.
#[instrument(skip_all, err)]
pub(crate) async fn add_source(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    ValidatedForm(input): ValidatedForm<SourceInput>,
) -> Result<impl IntoResponse, HandlerError> {
    validate_source_url(input.url.trim()).map_err(HandlerError::from)?;
    db.add_group_event_integration_source(group_id, input.url.trim())
        .await?;
    Ok(Html(
        prepare_page(&db, alliance_id, group_id, user.user_id)
            .await?
            .render()?,
    ))
}

/// Deletes one source URL from the selected group only.
#[instrument(skip_all, err)]
pub(crate) async fn delete_source(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(source_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    db.delete_group_event_integration_source(group_id, source_id).await?;
    Ok(Html(
        prepare_page(&db, alliance_id, group_id, user.user_id)
            .await?
            .render()?,
    ))
}

pub(crate) async fn prepare_page(
    db: &DynDB,
    alliance_id: Uuid,
    group_id: Uuid,
    user_id: Uuid,
) -> Result<Page, HandlerError> {
    let (can_manage_events, mut integration) = tokio::try_join!(
        db.user_has_group_permission(
            &alliance_id,
            &group_id,
            &user_id,
            GroupPermission::EventsWrite
        ),
        db.get_group_event_integration(group_id),
    )?;
    integration.can_manage_events = can_manage_events;
    Ok(Page { integration })
}

#[derive(Debug, Deserialize, Validate)]
pub(crate) struct SettingsInput {
    #[serde(default)]
    #[garde(skip)]
    enabled: bool,
    #[garde(skip)]
    city: String,
    #[garde(skip)]
    timezone: String,
}

#[derive(Debug, Deserialize, Validate)]
pub(crate) struct SourceInput {
    #[garde(skip)]
    url: String,
}

#[derive(Debug, Serialize)]
struct ManualRunResponse {
    group_id: Uuid,
    status: &'static str,
}

fn validate_settings(input: &SettingsInput) -> Result<(), HandlerError> {
    if input.city.trim().is_empty() || input.city.len() > 100 {
        return Err(HandlerError::Database(
            "city must be between 1 and 100 characters".into(),
        ));
    }
    input
        .timezone
        .trim()
        .parse::<chrono_tz::Tz>()
        .map_err(|_| HandlerError::Database("timezone must be a valid IANA timezone".into()))?;
    Ok(())
}
