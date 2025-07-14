//! HTTP handlers for the group site.

use askama::Template;
use axum::{
    extract::{Path, State},
    response::{Html, IntoResponse},
};
use tokio::try_join;
use tracing::instrument;

use crate::{
    db::DynDB,
    templates::{community::common::EventKind, group::Page},
};

use super::{error::HandlerError, extractors::CommunityId};

/// Handler that renders the group home page.
#[instrument(skip_all)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path(group_slug): Path<String>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let event_kinds = vec![EventKind::InPerson, EventKind::Virtual, EventKind::Hybrid];
    let (group, upcoming_events, past_events) = try_join!(
        db.get_group(community_id, &group_slug),
        db.get_group_upcoming_events(community_id, &group_slug, event_kinds.clone(), 9),
        db.get_group_past_events(community_id, &group_slug, event_kinds, 9)
    )?;
    let template = Page {
        group,
        past_events,
        upcoming_events,
    };

    Ok(Html(template.render()?))
}
