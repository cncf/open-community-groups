//! This module defines the HTTP handlers for the group site.

use axum::{extract::Path, response::IntoResponse};
use tracing::debug;

use crate::templates::group::Index;

use super::extractors::CommunityId;

/// Handler that returns the group index page.
pub(crate) async fn index(
    CommunityId(community_id): CommunityId,
    Path(group_slug): Path<String>,
) -> impl IntoResponse {
    debug!("community_id: {}, group: {}", community_id, group_slug);

    Index {}
}
