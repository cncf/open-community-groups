//! HTTP handlers for the alliance site.
//!
//! The home page displays an overview of the alliance including recent groups,
//! upcoming events (both in-person and virtual), and alliance statistics.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::{HeaderMap, StatusCode, Uri},
    response::{Html, IntoResponse},
};
use garde::Validate;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    activity_tracker::{Activity, DynActivityTracker},
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        error::HandlerError, extractors::CurrentUser, request_matches_site, site::not_found,
        trim_public_gallery_images,
    },
    router::{PUBLIC_SHARED_CACHE_HEADERS, serde_qs_config},
    templates::{PageId, alliance, auth::User},
    types::{event::EventKind, pagination::NavigationLinks},
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

/// Handler that renders the logged-in alliance member directory.
#[instrument(skip_all, err)]
pub(crate) async fn members_page(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Path(alliance_name): Path<String>,
    RawQuery(raw_query): RawQuery,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    let (alliance_id, site_settings) = tokio::try_join!(
        db.get_alliance_id_by_name(&alliance_name),
        db.get_site_settings()
    )?;
    let Some(alliance_id) = alliance_id else {
        return not_found::render(site_settings);
    };

    let is_member = db.is_alliance_group_member(alliance_id, user.user_id).await?;
    if !is_member {
        return Ok((
            StatusCode::FORBIDDEN,
            "Join one of this alliance's groups first to see members.",
        )
            .into_response());
    }

    let mut alliance = db.get_alliance_full(alliance_id).await?;
    trim_public_gallery_images(&mut alliance.photos_urls);
    let filters: alliance::AllianceMembersFilters =
        serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
    filters.validate()?;
    let results = db.list_alliance_members(alliance_id, &filters).await?;
    let page_url = format!("/{}/members", alliance.name);
    let navigation_links =
        NavigationLinks::from_filters(&filters, results.total, &page_url, &page_url)?;
    let template_user = User {
        logged_in: true,
        auth_provider: None,
        belongs_to_any_group_team: user.belongs_to_any_group_team,
        belongs_to_alliance_team: user.belongs_to_alliance_team,
        name: Some(user.name),
        platform_admin: user.platform_admin,
        username: Some(user.username),
    };

    let template = alliance::MembersPage {
        base_url: server_cfg.base_url,
        alliance,
        members: results.members,
        navigation_links,
        offset: filters.offset,
        page_id: PageId::Alliance,
        path: uri.path().to_string(),
        query: filters.query.clone(),
        site_settings,
        total: results.total,
        user: template_user,
    };

    Ok(Html(template.render()?).into_response())
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
