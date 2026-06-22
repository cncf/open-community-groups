//! HTTP handlers for alliance settings management.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::State,
    http::StatusCode,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedAllianceId, ValidatedFormQs},
    },
    templates::dashboard::alliance::settings::{self, AllianceUpdate},
    types::permissions::AlliancePermission,
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Displays the page to update alliance settings.
#[instrument(skip_all, err)]
pub(crate) async fn update_page(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (can_manage_settings, alliance) = tokio::try_join!(
        db.user_has_alliance_permission(
            &alliance_id,
            &user.user_id,
            AlliancePermission::SettingsWrite
        ),
        db.get_alliance_full(alliance_id)
    )?;
    let template = settings::UpdatePage {
        can_manage_settings,
        alliance,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Updates alliance settings in the database.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    ValidatedFormQs(alliance_update): ValidatedFormQs<AllianceUpdate>,
) -> Result<impl IntoResponse, HandlerError> {
    // Update alliance in database
    db.update_alliance(user.user_id, alliance_id, &alliance_update)
        .await?;

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]).into_response())
}
