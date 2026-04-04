//! HTTP handlers for community settings management.

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
        extractors::{CurrentUser, SelectedCommunityId, ValidatedFormQs},
    },
    templates::dashboard::community::settings::{self, CommunityUpdate},
    types::permissions::CommunityPermission,
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Displays the page to update community settings.
#[instrument(skip_all, err)]
pub(crate) async fn update_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (can_manage_settings, community) = tokio::try_join!(
        db.user_has_community_permission(&community_id, &user.user_id, CommunityPermission::SettingsWrite),
        db.get_community_full(community_id)
    )?;
    let template = settings::UpdatePage {
        can_manage_settings,
        community,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Updates community settings in the database.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    ValidatedFormQs(community_update): ValidatedFormQs<CommunityUpdate>,
) -> Result<impl IntoResponse, HandlerError> {
    // Update community in database
    db.update_community(user.user_id, community_id, &community_update)
        .await?;

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]).into_response())
}
