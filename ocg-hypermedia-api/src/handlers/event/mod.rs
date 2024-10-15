//! This module defines the HTTP handlers for the event page.

use super::extractors::CommunityId;
use crate::templates::event::Index;
use askama_axum::IntoResponse;
use axum::extract::Path;
use tracing::debug;

/// Handler that returns the event index page.
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
