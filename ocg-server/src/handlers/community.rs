//! HTTP handlers for the community site.
//!
//! The home page displays an overview of the community including recent groups,
//! upcoming events (both in-person and virtual), and community statistics.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode, Uri},
    response::{Html, IntoResponse},
};
use chrono::Duration;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    activity_tracker::{Activity, DynActivityTracker},
    db::DynDB,
    handlers::{error::HandlerError, extractors::CommunityId, prepare_headers, request_matches_site},
    templates::{PageId, auth::User, community},
    types::event::EventKind,
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Handler that renders the community page.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (
        community,
        recently_added_groups,
        site_settings,
        upcoming_in_person_events,
        upcoming_virtual_events,
        stats,
    ) = tokio::try_join!(
        db.get_community_full(community_id),
        db.get_community_recently_added_groups(community_id),
        db.get_site_settings(),
        db.get_community_upcoming_events(community_id, vec![EventKind::InPerson, EventKind::Hybrid]),
        db.get_community_upcoming_events(community_id, vec![EventKind::Virtual, EventKind::Hybrid]),
        db.get_community_site_stats(community_id),
    )?;
    let template = community::Page {
        community,
        page_id: PageId::Community,
        path: uri.path().to_string(),
        recently_added_groups: recently_added_groups
            .into_iter()
            .map(|group| community::GroupCard { group })
            .collect(),
        site_settings,
        stats,
        upcoming_in_person_events: upcoming_in_person_events
            .into_iter()
            .map(|event| community::EventCard { event })
            .collect(),
        upcoming_virtual_events: upcoming_virtual_events
            .into_iter()
            .map(|event| community::EventCard { event })
            .collect(),
        user: User::default(),
    };

    // Prepare response headers
    let headers = prepare_headers(Duration::hours(1), &[])?;

    Ok((headers, Html(template.render()?)))
}

// Actions handlers.

/// Tracks a community page view.
#[instrument(skip_all)]
pub(crate) async fn track_view(
    headers: HeaderMap,
    State(activity_tracker): State<DynActivityTracker>,
    State(server_cfg): State<crate::config::HttpServerConfig>,
    Path(community_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    if request_matches_site(&server_cfg, &headers)? {
        activity_tracker
            .track(Activity::CommunityView { community_id })
            .await?;
    }

    Ok(StatusCode::NO_CONTENT)
}
