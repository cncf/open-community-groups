//! HTTP handlers for the alliance analytics page.

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
        extractors::{CurrentUser, SelectedAllianceId},
    },
    templates::dashboard::alliance::analytics,
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Displays the alliance analytics dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    let (alliance, stats) = tokio::try_join!(
        db.get_alliance_full(alliance_id),
        db.get_alliance_stats(alliance_id)
    )?;
    let page = analytics::Page { alliance, stats };

    Ok(Html(page.render()?))
}

/// Publishes the alliance report to the public alliance page.
#[instrument(skip_all, err)]
pub(crate) async fn publish_report(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    db.update_alliance_report_public_enabled(user.user_id, alliance_id, true)
        .await?;

    Ok((StatusCode::NO_CONTENT, [("HX-Refresh", "true")]))
}

/// Unpublishes the alliance report from the public alliance page.
#[instrument(skip_all, err)]
pub(crate) async fn unpublish_report(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    db.update_alliance_report_public_enabled(user.user_id, alliance_id, false)
        .await?;

    Ok((StatusCode::NO_CONTENT, [("HX-Refresh", "true")]))
}
