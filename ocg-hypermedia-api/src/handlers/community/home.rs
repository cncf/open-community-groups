//! This module defines the HTTP handlers for the home page of the community
//! site.

use anyhow::Result;
use axum::{extract::State, http::Uri, response::IntoResponse};
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::CommunityId},
    templates::community::{explore::EventKind, home},
};

/// Handler that returns the home index page.
#[instrument(skip_all, err)]
pub(crate) async fn index(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare home index template
    #[rustfmt::skip]
    let (community, recently_added_groups, upcoming_in_person_events, upcoming_virtual_events) = tokio::try_join!(
        db.get_community(community_id),
        db.get_community_recently_added_groups(community_id),
        db.get_community_upcoming_events(community_id, vec![EventKind::InPerson, EventKind::Hybrid]),
        db.get_community_upcoming_events(community_id, vec![EventKind::Virtual, EventKind::Hybrid]),
    )?;
    let template = home::Index {
        community,
        path: uri.path().to_string(),
        recently_added_groups,
        upcoming_in_person_events,
        upcoming_virtual_events,
    };

    Ok(template)
}
