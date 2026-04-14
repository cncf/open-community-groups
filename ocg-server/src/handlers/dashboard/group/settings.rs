//! HTTP handlers for group settings management.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::State,
    http::StatusCode,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    config::PaymentsConfig,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedCommunityId, SelectedGroupId, ValidatedFormQs},
    },
    templates::dashboard::group::settings::{self, GroupUpdate},
    types::permissions::GroupPermission,
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Displays the page to update group settings.
#[instrument(skip_all, err)]
pub(crate) async fn update_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(payments_cfg): State<Option<PaymentsConfig>>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (can_manage_settings, group, categories, regions) = tokio::try_join!(
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user.user_id,
            GroupPermission::SettingsWrite
        ),
        db.get_group_full(community_id, group_id),
        db.list_group_categories(community_id),
        db.list_regions(community_id)
    )?;
    let template = settings::UpdatePage {
        can_manage_settings,
        categories,
        group,
        payments_enabled: payments_cfg.is_some(),
        regions,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Updates group settings in the database.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    ValidatedFormQs(group_update): ValidatedFormQs<GroupUpdate>,
) -> Result<impl IntoResponse, HandlerError> {
    // Update group in database
    db.update_group(user.user_id, community_id, group_id, &group_update)
        .await?;

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]).into_response())
}
