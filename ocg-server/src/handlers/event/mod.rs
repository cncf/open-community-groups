//! This module defines the HTTP handlers for the event page.

use askama::Template;
use axum::{
    extract::Path,
    response::{Html, IntoResponse},
};
use tracing::{debug, instrument};

use crate::templates::event::Index;

use super::{error::HandlerError, extractors::CommunityId};

/// Handler that returns the event index page.
#[instrument(skip_all)]
pub(crate) async fn index(
    CommunityId(community_id): CommunityId,
    Path((group_slug, event_slug)): Path<(String, String)>,
) -> Result<impl IntoResponse, HandlerError> {
    debug!(
        "community_id: {}, group: {}, event: {}",
        community_id, group_slug, event_slug
    );

    Ok(Html(Index {}.render()?))
}
