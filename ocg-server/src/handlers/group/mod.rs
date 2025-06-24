//! HTTP handlers for the group site.

use askama::Template;
use axum::{
    extract::Path,
    response::{Html, IntoResponse},
};
use tracing::{debug, instrument};

use crate::templates::group::Page;

use super::{error::HandlerError, extractors::CommunityId};

/// Handler that renders the group home page.
#[instrument(skip_all)]
pub(crate) async fn page(
    CommunityId(community_id): CommunityId,
    Path(group_slug): Path<String>,
) -> Result<impl IntoResponse, HandlerError> {
    debug!("community_id: {}, group: {}", community_id, group_slug);

    Ok(Html(Page {}.render()?))
}
