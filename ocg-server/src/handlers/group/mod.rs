//! HTTP handlers for the group site.

use askama::Template;
use axum::{
    extract::{Path, State},
    http::Uri,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    db::DynDB,
    templates::group::{self, Page},
    types::event::EventKind,
};

use super::{error::HandlerError, extractors::CommunityId};

// Pages handlers.

/// Handler that renders the group home page.
#[instrument(skip_all)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path(group_slug): Path<String>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let event_kinds = vec![EventKind::InPerson, EventKind::Virtual, EventKind::Hybrid];
    let (community, group, upcoming_events, past_events) = tokio::try_join!(
        db.get_community(community_id),
        db.get_group(community_id, &group_slug),
        db.get_group_upcoming_events(community_id, &group_slug, event_kinds.clone(), 9),
        db.get_group_past_events(community_id, &group_slug, event_kinds, 9)
    )?;
    let template = Page {
        community,
        group,
        past_events: past_events
            .into_iter()
            .map(|event| group::PastEventCard { event })
            .collect(),
        path: uri.path().to_string(),
        upcoming_events: upcoming_events
            .into_iter()
            .map(|event| group::UpcomingEventCard { event })
            .collect(),
    };

    Ok(Html(template.render()?))
}
