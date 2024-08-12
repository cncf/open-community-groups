//! This module defines the HTTP handlers for the community site.

use super::extractor::Community;
use askama::Template;
use askama_axum::IntoResponse;
use tracing::debug;

/// Template for the index document.
#[derive(Debug, Clone, Template)]
#[template(path = "community/index.html")]
pub(crate) struct Index {}

/// Handler that returns the index document.
#[allow(clippy::unused_async)]
pub(crate) async fn index(Community(community): Community) -> impl IntoResponse {
    debug!("community: {}", community);

    Index {}
}
