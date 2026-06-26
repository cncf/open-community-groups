//! HTTP handlers for the alliance site.
//!
//! The home page displays an overview of the alliance including recent groups,
//! upcoming events (both in-person and virtual), and alliance statistics.

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
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        error::HandlerError, request_matches_site, site::not_found, trim_public_gallery_images,
    },
    router::PUBLIC_SHARED_CACHE_HEADERS,
    templates::{PageId, alliance, auth::User},
    types::event::EventKind,
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Handler that renders the alliance page.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Path(alliance_name): Path<String>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Get alliance and site settings
    let (alliance_id, site_settings) = tokio::try_join!(
        db.get_alliance_id_by_name(&alliance_name),
        db.get_site_settings()
    )?;
    let Some(alliance_id) = alliance_id else {
        return not_found::render(site_settings);
    };

    // Prepare template
    let (
        mut alliance,
        recently_added_groups,
        upcoming_in_person_events,
        upcoming_virtual_events,
        stats,
    ) = tokio::try_join!(
        db.get_alliance_full(alliance_id),
        db.get_alliance_recently_added_groups(alliance_id),
        db.get_alliance_upcoming_events(alliance_id, vec![EventKind::InPerson, EventKind::Hybrid]),
        db.get_alliance_upcoming_events(alliance_id, vec![EventKind::Virtual, EventKind::Hybrid]),
        db.get_alliance_site_stats(alliance_id),
    )?;
    trim_public_gallery_images(&mut alliance.photos_urls);
    let template = alliance::Page {
        base_url: server_cfg.base_url,
        alliance,
        page_id: PageId::Alliance,
        path: uri.path().to_string(),
        recently_added_groups: recently_added_groups
            .into_iter()
            .map(|group| alliance::GroupCard { group })
            .collect(),
        site_settings,
        stats,
        upcoming_in_person_events: upcoming_in_person_events
            .into_iter()
            .map(|event| alliance::EventCard { event })
            .collect(),
        upcoming_virtual_events: upcoming_virtual_events
            .into_iter()
            .map(|event| alliance::EventCard { event })
            .collect(),
        user: User::default(),
    };

    Ok((PUBLIC_SHARED_CACHE_HEADERS, Html(template.render()?)).into_response())
}

/// Handler that renders the alliance brand assets page.
#[instrument(skip_all, err)]
pub(crate) async fn brand_page(
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Path(alliance_name): Path<String>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Get alliance and site settings.
    let (alliance_id, site_settings) = tokio::try_join!(
        db.get_alliance_id_by_name(&alliance_name),
        db.get_site_settings()
    )?;
    let Some(alliance_id) = alliance_id else {
        return not_found::render(site_settings);
    };

    let alliance = db.get_alliance_full(alliance_id).await?;
    let template = alliance::BrandPage {
        base_url: server_cfg.base_url,
        alliance,
        page_id: PageId::Alliance,
        path: uri.path().to_string(),
        site_settings,
        user: User::default(),
    };

    Ok((PUBLIC_SHARED_CACHE_HEADERS, Html(template.render()?)).into_response())
}

// Actions handlers.

/// Tracks a alliance page view.
#[instrument(skip_all)]
pub(crate) async fn track_view(
    headers: HeaderMap,
    State(activity_tracker): State<DynActivityTracker>,
    State(server_cfg): State<crate::config::HttpServerConfig>,
    Path(alliance_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    if request_matches_site(&server_cfg, &headers)? {
        activity_tracker.track(Activity::AllianceView { alliance_id }).await?;
    }

    Ok(StatusCode::NO_CONTENT)
}
