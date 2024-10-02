//! This module defines the HTTP handlers for the group site.

use super::extractor::CommunityId;
use askama_axum::IntoResponse;
use axum::extract::Path;
use templates::Home;
use tracing::debug;

pub(crate) mod templates;

/// Handler that returns the home page.
pub(crate) async fn home(
    CommunityId(community_id): CommunityId,
    Path(group_slug): Path<String>,
) -> impl IntoResponse {
    debug!("community_id: {}, group: {}", community_id, group_slug);

    Home {}
}
