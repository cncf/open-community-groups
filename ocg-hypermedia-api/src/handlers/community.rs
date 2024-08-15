//! This module defines the HTTP handlers for the community site.

use super::extractor::Community;
use askama::Template;
use askama_axum::IntoResponse;
use tracing::debug;

/// Index document template.
#[derive(Debug, Clone, Template)]
#[template(path = "community/index.html")]
pub(crate) struct Index {}

/// Handler that returns the index document.
#[allow(clippy::unused_async)]
pub(crate) async fn index(Community(community): Community) -> impl IntoResponse {
    debug!("community: {}", community);

    Index {}
}

/// Explore page template.
#[derive(Debug, Clone, Template)]
#[template(path = "community/explore.html")]
pub(crate) struct Explore {}

/// Handler that returns the explore page.
#[allow(clippy::unused_async)]
pub(crate) async fn explore(Community(community): Community) -> impl IntoResponse {
    debug!("community: {}", community);

    Explore {}
}
