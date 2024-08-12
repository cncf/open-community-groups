//! This module defines the HTTP handlers for the group site.

use super::extractor::Community;
use askama::Template;
use askama_axum::IntoResponse;
use axum::extract::Path;
use tracing::debug;

/// Template for the index document.
#[derive(Debug, Clone, Template)]
#[template(path = "group/index.html")]
pub(crate) struct Index {}

/// Handler that returns the index document.
#[allow(clippy::unused_async)]
pub(crate) async fn index(
    Community(community): Community,
    Path(group_slug): Path<String>,
) -> impl IntoResponse {
    debug!("community: {}, group: {}", community, group_slug);

    Index {}
}
