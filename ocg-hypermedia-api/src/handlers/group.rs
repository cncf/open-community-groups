//! This module defines the HTTP handlers for the group site.

use super::extractor::CommunityId;
use askama::Template;
use askama_axum::IntoResponse;
use axum::extract::Path;
use tracing::debug;

/// Handler that returns the index document.
#[allow(clippy::unused_async)]
pub(crate) async fn index(
    CommunityId(community_id): CommunityId,
    Path(group_slug): Path<String>,
) -> impl IntoResponse {
    debug!("community_id: {}, group: {}", community_id, group_slug);

    Index {}
}

/// Template for the index document.
#[derive(Debug, Clone, Template)]
#[template(path = "group/index.html")]
pub(crate) struct Index {}
