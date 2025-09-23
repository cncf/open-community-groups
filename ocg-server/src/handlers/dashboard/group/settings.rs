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
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CommunityId, SelectedGroupId},
    },
    templates::dashboard::group::settings::{self, GroupUpdate},
};

// Pages handlers.

/// Displays the page to update group settings.
#[instrument(skip_all, err)]
pub(crate) async fn update_page(
    CommunityId(community_id): CommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (group, categories, regions) = tokio::try_join!(
        db.get_group_full(community_id, group_id),
        db.list_group_categories(community_id),
        db.list_regions(community_id)
    )?;
    let template = settings::UpdatePage {
        categories,
        group,
        regions,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Updates group settings in the database.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    CommunityId(community_id): CommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(serde_qs_de): State<serde_qs::Config>,
    body: String,
) -> Result<impl IntoResponse, HandlerError> {
    // Get group update information from body
    let group_update: GroupUpdate = match serde_qs_de.deserialize_str(&body).map_err(anyhow::Error::new) {
        Ok(update) => update,
        Err(e) => return Ok((StatusCode::UNPROCESSABLE_ENTITY, e.to_string()).into_response()),
    };

    // Update group in database
    db.update_group(community_id, group_id, &group_update).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    )
        .into_response())
}
