//! This module defines the HTTP handlers for the community site.

use super::extractor::CommunityId;
use askama::Template;
use askama_axum::IntoResponse;
use axum::extract::Query;
use std::collections::HashMap;
use tracing::debug;

/// Index document template.
#[derive(Debug, Clone, Template)]
#[template(path = "community/index.html")]
pub(crate) struct Index {}

/// Handler that returns the index document.
#[allow(clippy::unused_async)]
pub(crate) async fn index(CommunityId(community_id): CommunityId) -> impl IntoResponse {
    debug!("community_id: {}", community_id);

    Index {}
}

/// Explore page template.
#[derive(Debug, Clone, Template)]
#[template(path = "community/explore.html")]
pub(crate) struct Explore {
    #[allow(dead_code)]
    params: HashMap<String, String>,
}

/// Handler that returns the explore page.
#[allow(clippy::unused_async)]
pub(crate) async fn explore(
    CommunityId(community_id): CommunityId,
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    debug!("community_id: {}, params: {:?}", community_id, params);

    Explore { params }
}

/// Explore events section template.
#[derive(Debug, Clone, Template)]
#[template(path = "community/events.html")]
pub(crate) struct Events {}

/// Handler that returns the explore events section.
#[allow(clippy::unused_async)]
pub(crate) async fn events(CommunityId(_community_id): CommunityId) -> impl IntoResponse {
    Events {}
}

/// Explore groups section template.
#[derive(Debug, Clone, Template)]
#[template(path = "community/groups.html")]
pub(crate) struct Groups {}

/// Handler that returns the explore groups section.
#[allow(clippy::unused_async)]
pub(crate) async fn groups(CommunityId(_community): CommunityId) -> impl IntoResponse {
    Groups {}
}
