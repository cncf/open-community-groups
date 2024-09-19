//! This module defines the HTTP handlers for the event page.

use super::extractor::CommunityId;
use askama::Template;
use askama_axum::IntoResponse;
use axum::extract::Path;
use tracing::debug;

/// Handler that returns the index document.
#[allow(clippy::unused_async)]
pub(crate) async fn index(
    CommunityId(community_id): CommunityId,
    Path((group_slug, event_slug)): Path<(String, String)>,
) -> impl IntoResponse {
    debug!(
        "community_id: {}, group: {}, event: {}",
        community_id, group_slug, event_slug
    );

    Index {}
}
/// Template for the index document.
#[derive(Debug, Clone, Template)]
#[template(path = "event/index.html")]
pub(crate) struct Index {}
