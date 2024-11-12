//! This module defines the HTTP handlers for the event page.

use axum::{extract::Path, response::IntoResponse};
use tracing::debug;

use crate::templates::event::Index;

use super::extractors::CommunityId;

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
