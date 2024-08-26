//! This module defines the HTTP handlers for the community site.

use std::collections::HashMap;

use super::extractor::Community;
use askama::Template;
use askama_axum::IntoResponse;
use axum::extract::Query;
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
pub(crate) struct Explore {
    params: HashMap<String, String>,
}

/// Handler that returns the explore page.
#[allow(clippy::unused_async)]
pub(crate) async fn explore(
    Community(community): Community,
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    debug!("community: {}, params: {:?}", community, params);

    Explore { params }
}

/// Explore events section template.
#[derive(Debug, Clone, Template)]
#[template(path = "community/events.html")]
pub(crate) struct Events {}

/// Handler that returns the explore events section.
#[allow(clippy::unused_async)]
pub(crate) async fn events(Community(_community): Community) -> impl IntoResponse {
    Events {}
}

/// Explore groups section template.
#[derive(Debug, Clone, Template)]
#[template(path = "community/groups.html")]
pub(crate) struct Groups {}

/// Handler that returns the explore groups section.
#[allow(clippy::unused_async)]
pub(crate) async fn groups(Community(_community): Community) -> impl IntoResponse {
    Groups {}
}
