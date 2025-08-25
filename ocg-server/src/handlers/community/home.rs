//! HTTP handlers for the community home page.
//!
//! The home page displays an overview of the community including recent groups,
//! upcoming events (both in-person and virtual), and community statistics.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::State,
    http::Uri,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::CommunityId},
    templates::{PageId, auth::User, community::home},
    types::event::EventKind,
};

// Pages handlers.

/// Handler that renders the community home page.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (community, recently_added_groups, upcoming_in_person_events, upcoming_virtual_events, stats) = tokio::try_join!(
        db.get_community(community_id),
        db.get_community_recently_added_groups(community_id),
        db.get_community_upcoming_events(community_id, vec![EventKind::InPerson, EventKind::Hybrid]),
        db.get_community_upcoming_events(community_id, vec![EventKind::Virtual, EventKind::Hybrid]),
        db.get_community_home_stats(community_id),
    )?;
    let template = home::Page {
        community,
        page_id: PageId::CommunityHome,
        path: uri.path().to_string(),
        recently_added_groups: recently_added_groups
            .into_iter()
            .map(|group| home::GroupCard { group })
            .collect(),
        stats,
        upcoming_in_person_events: upcoming_in_person_events
            .into_iter()
            .map(|event| home::EventCard { event })
            .collect(),
        upcoming_virtual_events: upcoming_virtual_events
            .into_iter()
            .map(|event| home::EventCard { event })
            .collect(),
        user: User::default(),
    };

    Ok(Html(template.render()?))
}
