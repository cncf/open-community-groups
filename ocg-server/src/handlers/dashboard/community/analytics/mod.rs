//! HTTP handlers for the community analytics page.

use askama::Template;
use axum::{
    extract::State,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::SelectedCommunityId},
    templates::dashboard::community::analytics,
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Displays the community analytics dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    let stats = db.get_community_stats(community_id).await?;
    let page = analytics::Page { stats };

    Ok(Html(page.render()?))
}
