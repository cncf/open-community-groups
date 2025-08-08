//! HTTP handlers for the event page.

use askama::Template;
use axum::{
    extract::{Path, State},
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{db::DynDB, templates::event::Page};

use super::{error::HandlerError, extractors::CommunityId};

// Pages handlers.

/// Handler that renders the event page.
#[instrument(skip_all)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path((group_slug, event_slug)): Path<(String, String)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (community, event) = tokio::try_join!(
        db.get_community(community_id),
        db.get_event(community_id, &group_slug, &event_slug)
    )?;
    let template = Page { community, event };

    Ok(Html(template.render()?))
}
