//! This module defines the HTTP handlers for the event page.

use super::extractors::CommunityId;
use crate::templates::event::Home;
use askama_axum::IntoResponse;
use axum::extract::Path;
use tracing::debug;

/// Handler that returns the home page.
pub(crate) async fn home(
    CommunityId(community_id): CommunityId,
    Path((group_slug, event_slug)): Path<(String, String)>,
) -> impl IntoResponse {
    debug!(
        "community_id: {}, group: {}, event: {}",
        community_id, group_slug, event_slug
    );

    Home {}
}
