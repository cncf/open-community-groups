//! This module defines the HTTP handlers for the group site.

use askama::Template;
use axum::{
    extract::Path,
    response::{Html, IntoResponse},
};
use tracing::{debug, instrument};

use crate::templates::group::Index;

use super::{error::HandlerError, extractors::CommunityId};

/// Handler that returns the group index page.
#[instrument(skip_all)]
pub(crate) async fn index(
    CommunityId(community_id): CommunityId,
    Path(group_slug): Path<String>,
) -> Result<impl IntoResponse, HandlerError> {
    debug!("community_id: {}, group: {}", community_id, group_slug);

    Ok(Html(Index {}.render()?))
}
