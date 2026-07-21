//! HTTP handlers for alliance partner integrations.

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
        extractors::{CurrentUser, SelectedAllianceId, ValidatedForm},
    },
    templates::dashboard::alliance::partner_integrations::{Page, PartnerIntegrationInput},
    types::permissions::AlliancePermission,
};

/// Displays partner integrations configured for the selected alliance.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    Ok(Html(
        prepare_page(&db, alliance_id, user.user_id).await?.render()?,
    ))
}

/// Creates a partner integration.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    ValidatedForm(input): ValidatedForm<PartnerIntegrationInput>,
) -> Result<impl IntoResponse, HandlerError> {
    db.add_partner_integration(user.user_id, alliance_id, &input).await?;
    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-alliance-dashboard-table")],
    ))
}

/// Updates a partner integration.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    Path(partner_integration_id): Path<Uuid>,
    ValidatedForm(input): ValidatedForm<PartnerIntegrationInput>,
) -> Result<impl IntoResponse, HandlerError> {
    db.update_partner_integration(user.user_id, alliance_id, partner_integration_id, &input)
        .await?;
    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-alliance-dashboard-table")],
    ))
}

/// Deletes a partner integration.
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    Path(partner_integration_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    db.delete_partner_integration(user.user_id, alliance_id, partner_integration_id)
        .await?;
    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-alliance-dashboard-table")],
    ))
}

pub(crate) async fn prepare_page(
    db: &DynDB,
    alliance_id: Uuid,
    user_id: Uuid,
) -> Result<Page, HandlerError> {
    let (can_manage_settings, integrations) = tokio::try_join!(
        db.user_has_alliance_permission(&alliance_id, &user_id, AlliancePermission::SettingsWrite),
        db.list_partner_integrations(alliance_id),
    )?;
    Ok(Page {
        can_manage_settings,
        integrations,
    })
}
