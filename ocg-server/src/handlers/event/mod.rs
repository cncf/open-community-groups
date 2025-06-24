//! HTTP handlers for the event page.

use askama::Template;
use axum::{
    extract::Path,
    response::{Html, IntoResponse},
};
use tracing::{debug, instrument};

use crate::templates::event::Page;

use super::{error::HandlerError, extractors::CommunityId};

/// Handler that renders the event page.
#[instrument(skip_all)]
pub(crate) async fn page(
    CommunityId(community_id): CommunityId,
    Path((group_slug, event_slug)): Path<(String, String)>,
) -> Result<impl IntoResponse, HandlerError> {
    debug!(
        "community_id: {}, group: {}, event: {}",
        community_id, group_slug, event_slug
    );

    Ok(Html(Page {}.render()?))
}
