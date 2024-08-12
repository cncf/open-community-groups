//! This module defines the HTTP handlers for the event page.

use super::extractor::Community;
use askama::Template;
use askama_axum::IntoResponse;
use axum::extract::Path;
use tracing::debug;

/// Template for the index document.
#[derive(Debug, Clone, Template)]
#[template(path = "event/index.html")]
pub(crate) struct Index {}

/// Handler that returns the index document.
#[allow(clippy::unused_async)]
pub(crate) async fn index(
    Community(community): Community,
    Path((group_slug, event_slug)): Path<(String, String)>,
) -> impl IntoResponse {
    debug!(
        "community: {}, group: {}, event: {}",
        community, group_slug, event_slug
    );

    Index {}
}
