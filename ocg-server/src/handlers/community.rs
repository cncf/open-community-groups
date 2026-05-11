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
use tracing::instrument;
use uuid::Uuid;

use crate::{
    activity_tracker::{Activity, DynActivityTracker},
    db::DynDB,
    handlers::{error::HandlerError, request_matches_site, site::not_found, trim_public_gallery_images},
    router::PUBLIC_SHARED_CACHE_HEADERS,
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
    Path(community_name): Path<String>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Get community and site settings
    let (community_id, site_settings) = tokio::try_join!(
        db.get_community_id_by_name(&community_name),
        db.get_site_settings()
    )?;
    let Some(community_id) = community_id else {
        return not_found::render(site_settings);
    };

    // Prepare template
    let (mut community, recently_added_groups, upcoming_in_person_events, upcoming_virtual_events, stats) = tokio::try_join!(
        db.get_community_full(community_id),
        db.get_community_recently_added_groups(community_id),
        db.get_community_upcoming_events(community_id, vec![EventKind::InPerson, EventKind::Hybrid]),
        db.get_community_upcoming_events(community_id, vec![EventKind::Virtual, EventKind::Hybrid]),
        db.get_community_site_stats(community_id),
    )?;
    trim_public_gallery_images(&mut community.photos_urls);
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

    Ok((PUBLIC_SHARED_CACHE_HEADERS, Html(template.render()?)).into_response())
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
