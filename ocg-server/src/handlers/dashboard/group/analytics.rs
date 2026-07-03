//! HTTP handlers for the group analytics page.

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
        extractors::{CurrentUser, SelectedAllianceId, SelectedGroupId},
    },
    templates::dashboard::group::analytics,
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Displays the group analytics dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    let (group, stats) = tokio::try_join!(
        db.get_group_full(alliance_id, group_id),
        db.get_group_stats(alliance_id, group_id)
    )?;
    let page = analytics::Page { group, stats };

    Ok(Html(page.render()?))
}

/// Publishes the group report to the public group page.
#[instrument(skip_all, err)]
pub(crate) async fn publish_report(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    db.update_group_report_public_enabled(user.user_id, alliance_id, group_id, true)
        .await?;

    Ok((StatusCode::NO_CONTENT, [("HX-Refresh", "true")]))
}

/// Unpublishes the group report from the public group page.
#[instrument(skip_all, err)]
pub(crate) async fn unpublish_report(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    db.update_group_report_public_enabled(user.user_id, alliance_id, group_id, false)
        .await?;

    Ok((StatusCode::NO_CONTENT, [("HX-Refresh", "true")]))
}
