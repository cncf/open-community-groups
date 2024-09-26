//! This module defines the HTTP handlers for the group site.

use super::extractor::CommunityId;
use askama::Template;
use askama_axum::IntoResponse;
use axum::extract::Path;
use tracing::debug;

/// Handler that returns the home page.
pub(crate) async fn home(
    CommunityId(community_id): CommunityId,
    Path(group_slug): Path<String>,
) -> impl IntoResponse {
    debug!("community_id: {}, group: {}", community_id, group_slug);

    Home {}
}

/// Home page template.
#[derive(Debug, Clone, Template)]
#[template(path = "group/home.html")]
pub(crate) struct Home {}
