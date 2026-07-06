//! HTTP handlers for the group analytics page.

use askama::Template;
use axum::{
    extract::{Query, State},
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
    Query(query): Query<analytics::AnalyticsQuery>,
) -> Result<impl IntoResponse, HandlerError> {
    let include_subgroups = query.include_subgroups.unwrap_or(false);
    let (stats, has_subgroups) = tokio::try_join!(
        db.get_group_stats(community_id, group_id, include_subgroups),
        db.group_has_active_subgroups(community_id, group_id)
    )?;
    let page = analytics::Page {
        include_subgroups,
        has_subgroups,
        stats,
    };

    Ok(Html(page.render()?))
}
