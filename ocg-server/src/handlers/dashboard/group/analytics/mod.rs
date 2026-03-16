//! HTTP handlers for the group analytics page.

use askama::Template;
use axum::{
    extract::State,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{SelectedCommunityId, SelectedGroupId},
    },
    templates::dashboard::group::analytics,
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Displays the group analytics dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    let stats = db.get_group_stats(community_id, group_id).await?;
    let page = analytics::Page { stats };

    Ok(Html(page.render()?))
}
