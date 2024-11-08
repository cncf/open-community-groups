//! This module defines the HTTP handlers for the group site.

use super::extractors::CommunityId;
use crate::templates::group::Index;
use axum::{extract::Path, response::IntoResponse};
use tracing::debug;

/// Handler that returns the group index page.
pub(crate) async fn index(
    CommunityId(community_id): CommunityId,
    Path(group_slug): Path<String>,
) -> impl IntoResponse {
    debug!("community_id: {}, group: {}", community_id, group_slug);

    Index {}
}
