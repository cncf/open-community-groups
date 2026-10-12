//! HTTP handlers for the global site explore page.
//!
//! The explore page provides a searchable interface for discovering groups and events
//! across all communities.

use std::collections::HashMap;

use anyhow::Result;
use askama::Template;
use axum::{
    Json,
    extract::{Path, Query, RawQuery, State},
    http::{HeaderMap, HeaderName, HeaderValue, Uri, header::CACHE_CONTROL},
    response::{Html, IntoResponse},
};
use chrono::Utc;
use garde::Validate;
use serde::Deserialize;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError, extend_public_shared_cache_headers, extractors::ValidatedQuery,
    },
    router::CACHE_CONTROL_NO_STORE,
    templates::{
        PageId,
        auth::UserMenuState,
        site::explore::{
            self, render_calendar_event_popover, render_event_popover, render_group_popover,
        },
    },
    types::{
        pagination::{self, NavigationLinks},
        search::{
            EXPLORE_WIDGET_MAX_ITEMS, SearchEventsFilters, SearchEventsOutput, SearchGroupsFilters,
            SearchGroupsOutput, ViewMode,
        },
        site::explore::Entity,
    },
};

#[cfg(test)]
mod tests;

// Pages and sections handlers.

/// Handler that renders the global explore page with either events or groups section.
#[instrument(skip_all)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let site_settings = db.get_site_settings().await?;
    let entity: Entity = query.get("entity").map(String::as_str).into();
    let mut template = explore::Page {
        entity: entity.clone(),
        page_id: PageId::SiteExplore,
        path: uri.path().to_string(),
        site_settings,
        user: UserMenuState::default(),
        events_section: None,
        groups_section: None,
    };

    // Attach events or groups section template to the page template
    match entity {
        Entity::Events => {
            let filters = parse_events_filters(&headers, &raw_query.unwrap_or_default())?;
            let events_section = prepare_events_section(&db, &filters).await?;
            template.events_section = Some(events_section);
        }
        Entity::Groups => {
            let filters = parse_groups_filters(&headers, &raw_query.unwrap_or_default())?;
            let groups_section = prepare_groups_section(&db, &filters).await?;
            template.groups_section = Some(groups_section);
        }
    }

    // Prepare response headers after the active section has resolved its filters
    let headers = search_response_headers(match &entity {
        Entity::Events => template
            .events_section
            .as_ref()
            .is_some_and(|section| section.filters.uses_viewer_location()),
        Entity::Groups => template
            .groups_section
            .as_ref()
            .is_some_and(|section| section.filters.uses_viewer_location()),
    })?;

    Ok((headers, Html(template.render()?)))
}

/// Handler that renders the card of a public event for the explore map or calendar.
#[instrument(skip_all)]
pub(crate) async fn event_card(
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
    ValidatedQuery(query): ValidatedQuery<EventCardQuery>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the event only when its public page is available
    let Some(event) = db.get_public_event_summary(event_id).await? else {
        return Err(HandlerError::NotFound);
    };

    // Render the card for the requested view
    let html = match query.view_mode {
        EventCardView::Calendar => render_calendar_event_popover(&event)?,
        EventCardView::Map => render_event_popover(&event)?,
    };

    // Prepare response headers
    let headers = extend_public_shared_cache_headers(&[])?;

    Ok((headers, Html(html)))
}

/// Handler that renders the events results section of the explore page.
#[instrument(skip_all)]
pub(crate) async fn events_results_section(
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare events results section template
    let filters = parse_events_filters(&headers, &raw_query.unwrap_or_default())?;
    let template = prepare_events_result_section(&db, &filters).await?;

    // Prepare response headers
    let url = pagination::build_url("/explore?entity=events", &filters)?;
    let headers = search_response_headers_with_extra(
        filters.uses_viewer_location(),
        &[("HX-Push-Url", url.as_str())],
    )?;

    Ok((headers, Html(template.render()?)))
}

/// Handler that renders the events section of the explore page.
#[instrument(skip_all)]
pub(crate) async fn events_section(
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare events section template
    let filters = parse_events_filters(&headers, &raw_query.unwrap_or_default())?;
    let template = prepare_events_section(&db, &filters).await?;

    // Prepare response headers
    let url = pagination::build_url("/explore?entity=events", &filters)?;
    let headers = search_response_headers_with_extra(
        filters.uses_viewer_location(),
        &[("HX-Push-Url", url.as_str())],
    )?;

    Ok((headers, Html(template.render()?)))
}

/// Handler that renders the card of a public group for the explore map.
#[instrument(skip_all)]
pub(crate) async fn group_card(
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the group only when its public page is available
    let Some(group) = db.get_public_group_summary(group_id).await? else {
        return Err(HandlerError::NotFound);
    };

    // Render the card
    let html = render_group_popover(&group)?;

    // Prepare response headers
    let headers = extend_public_shared_cache_headers(&[])?;

    Ok((headers, Html(html)))
}

/// Handler that renders the groups results section of the explore page.
#[instrument(skip_all)]
pub(crate) async fn groups_results_section(
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare groups results section template
    let filters = parse_groups_filters(&headers, &raw_query.unwrap_or_default())?;
    let template = prepare_groups_result_section(&db, &filters).await?;

    // Prepare response headers
    let url = pagination::build_url("/explore?entity=groups", &filters)?;
    let headers = search_response_headers_with_extra(
        filters.uses_viewer_location(),
        &[("HX-Push-Url", url.as_str())],
    )?;

    Ok((headers, Html(template.render()?)))
}

/// Handler that renders the groups section of the explore page.
#[instrument(skip_all)]
pub(crate) async fn groups_section(
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare groups section template
    let filters = parse_groups_filters(&headers, &raw_query.unwrap_or_default())?;
    let template = prepare_groups_section(&db, &filters).await?;

    // Prepare response headers
    let url = pagination::build_url("/explore?entity=groups", &filters)?;
    let headers = search_response_headers_with_extra(
        filters.uses_viewer_location(),
        &[("HX-Push-Url", url.as_str())],
    )?;

    Ok((headers, Html(template.render()?)))
}

/// Prepares the events result section template.
#[instrument(skip_all)]
async fn prepare_events_result_section(
    db: &DynDB,
    filters: &SearchEventsFilters,
) -> Result<explore::EventsResultsSection> {
    // Search the minimal events drawn by the map and calendar views
    if matches!(filters.view_mode, Some(ViewMode::Calendar | ViewMode::Map)) {
        let widget_data = db.search_events_minimal(filters, EXPLORE_WIDGET_MAX_ITEMS).await?;
        return Ok(explore::EventsResultsSection {
            events: vec![],
            navigation_links: NavigationLinks::default(),
            total: widget_data.total,
            offset: filters.offset,
            view_mode: filters.view_mode.clone(),
            widget_data: Some(widget_data),
        });
    }

    // Search a page of events for the list view
    let SearchEventsOutput { events, total, .. } = db.search_events(filters).await?;

    // Prepare template
    Ok(explore::EventsResultsSection {
        events: events.into_iter().map(|event| explore::EventCard { event }).collect(),
        navigation_links: NavigationLinks::from_filters(
            filters,
            total,
            "/explore?entity=events",
            "/explore/events-results-section",
        )?,
        total,
        offset: filters.offset,
        view_mode: filters.view_mode.clone(),
        widget_data: None,
    })
}

/// Prepares the events section template.
#[instrument(skip_all)]
async fn prepare_events_section(
    db: &DynDB,
    filters: &SearchEventsFilters,
) -> Result<explore::EventsSection> {
    // Pass community_name to get_filters_options only when exactly one is selected
    let community_name = if filters.community.len() == 1 {
        Some(filters.community[0].clone())
    } else {
        None
    };

    // Prepare template
    let (filters_options, results_section) = tokio::try_join!(
        db.get_filters_options(community_name, Some(Entity::Events)),
        prepare_events_result_section(db, filters)
    )?;

    Ok(explore::EventsSection {
        filters: filters.clone(),
        filters_options,
        results_section,
    })
}

/// Prepares the groups result section template.
#[instrument(skip_all)]
async fn prepare_groups_result_section(
    db: &DynDB,
    filters: &SearchGroupsFilters,
) -> Result<explore::GroupsResultsSection> {
    // Search the minimal groups drawn by the map view
    if filters.view_mode == Some(ViewMode::Map) {
        let widget_data = db.search_groups_minimal(filters, EXPLORE_WIDGET_MAX_ITEMS).await?;
        return Ok(explore::GroupsResultsSection {
            groups: vec![],
            navigation_links: NavigationLinks::default(),
            total: widget_data.total,
            offset: filters.offset,
            view_mode: filters.view_mode.clone(),
            widget_data: Some(widget_data),
        });
    }

    // Search a page of groups for the list view
    let SearchGroupsOutput { groups, total, .. } = db.search_groups(filters).await?;

    // Prepare template
    Ok(explore::GroupsResultsSection {
        groups: groups.into_iter().map(|group| explore::GroupCard { group }).collect(),
        navigation_links: NavigationLinks::from_filters(
            filters,
            total,
            "/explore?entity=groups",
            "/explore/groups-results-section",
        )?,
        total,
        offset: filters.offset,
        view_mode: filters.view_mode.clone(),
        widget_data: None,
    })
}

/// Prepares groups section template.
#[instrument(skip_all)]
async fn prepare_groups_section(
    db: &DynDB,
    filters: &SearchGroupsFilters,
) -> Result<explore::GroupsSection> {
    // Pass community_name to get_filters_options only when exactly one is selected
    let community_name = if filters.community.len() == 1 {
        Some(filters.community[0].clone())
    } else {
        None
    };

    // Prepare template
    let (filters_options, results_section) = tokio::try_join!(
        db.get_filters_options(community_name, Some(Entity::Groups)),
        prepare_groups_result_section(db, filters)
    )?;

    Ok(explore::GroupsSection {
        filters: filters.clone(),
        filters_options,
        results_section,
    })
}

// JSON search handlers.

/// Handler that returns every event to draw on the explore map or calendar, up
/// to the widget items cap (JSON format).
#[instrument(skip_all)]
pub(crate) async fn search_events(
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Require the calendar or map view before parsing the filters
    let raw_query = raw_query.unwrap_or_default();
    require_calendar_or_map_view(&raw_query)?;
    let filters = parse_events_filters(&headers, &raw_query)?;

    // Search the minimal events
    let output = db.search_events_minimal(&filters, EXPLORE_WIDGET_MAX_ITEMS).await?;

    // Prepare response headers
    let headers = search_response_headers(filters.uses_viewer_location())?;

    Ok((headers, Json(output)))
}

/// Handler that returns every group to draw on the explore map, up to the
/// widget items cap (JSON format).
#[instrument(skip_all)]
pub(crate) async fn search_groups(
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Parse the filters
    let filters = parse_groups_filters(&headers, &raw_query.unwrap_or_default())?;

    // Search the minimal groups
    let output = db.search_groups_minimal(&filters, EXPLORE_WIDGET_MAX_ITEMS).await?;

    // Prepare response headers
    let headers = search_response_headers(filters.uses_viewer_location())?;

    Ok((headers, Json(output)))
}

// Types.

/// Query parameters of the explore event card endpoint.
#[derive(Debug, Clone, Deserialize, Validate)]
pub(crate) struct EventCardQuery {
    /// Explore view the card is rendered for.
    #[garde(skip)]
    pub view_mode: EventCardView,
}

/// Explore view an event card is rendered for.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum EventCardView {
    /// Card shown when hovering an event in the calendar.
    Calendar,
    /// Card shown when hovering an event on the map.
    Map,
}

// Helpers.

/// Parses, validates, and normalizes the events search filters of a request.
fn parse_events_filters(
    headers: &HeaderMap,
    raw_query: &str,
) -> Result<SearchEventsFilters, HandlerError> {
    // Parse and validate the query string
    let mut filters: SearchEventsFilters = ValidatedQuery::parse(raw_query)?;

    // Replace any client supplied location with the viewer location headers
    (filters.latitude, filters.longitude) = viewer_location(headers);

    // Apply the search defaults
    filters.normalize(Utc::now());

    trace!(?filters);
    Ok(filters)
}

/// Parses, validates, and normalizes the groups search filters of a request.
fn parse_groups_filters(
    headers: &HeaderMap,
    raw_query: &str,
) -> Result<SearchGroupsFilters, HandlerError> {
    // Parse and validate the query string
    let mut filters: SearchGroupsFilters = ValidatedQuery::parse(raw_query)?;

    // Replace any client supplied location with the viewer location headers
    (filters.latitude, filters.longitude) = viewer_location(headers);

    // Apply the search defaults
    filters.normalize();

    trace!(?filters);
    Ok(filters)
}

/// Rejects events search queries unless every `view_mode` is calendar or map.
///
/// The raw query is checked before the filters are parsed, so missing, unknown
/// and unsupported view modes all get the same rejection.
fn require_calendar_or_map_view(raw_query: &str) -> Result<(), HandlerError> {
    // Collect the requested view modes
    let pairs: Vec<(String, String)> = serde_urlencoded::from_str(raw_query).unwrap_or_default();
    let mut view_modes = pairs
        .iter()
        .filter(|(key, _)| key == "view_mode")
        .map(|(_, value)| value.as_str())
        .peekable();

    // Accept only the calendar and map views
    let has_view_mode = view_modes.peek().is_some();
    if has_view_mode && view_modes.all(|view_mode| matches!(view_mode, "calendar" | "map")) {
        return Ok(());
    }
    Err(HandlerError::Rejected(
        "view_mode must be calendar or map".to_string(),
    ))
}

/// Returns search response headers.
fn search_response_headers(uses_viewer_location: bool) -> Result<HeaderMap> {
    search_response_headers_with_extra(uses_viewer_location, &[])
}

/// Returns search response headers with dynamic headers.
fn search_response_headers_with_extra(
    uses_viewer_location: bool,
    extra_headers: &[(&str, &str)],
) -> Result<HeaderMap> {
    // Use shared cache headers when the response does not depend on viewer location
    if !uses_viewer_location {
        return extend_public_shared_cache_headers(extra_headers);
    }

    // Disable storage for location-sensitive search responses
    let mut headers = HeaderMap::new();
    headers.insert(
        CACHE_CONTROL,
        HeaderValue::from_static(CACHE_CONTROL_NO_STORE),
    );

    // Add dynamic response headers
    for (key, value) in extra_headers {
        headers.insert(HeaderName::try_from(*key)?, HeaderValue::try_from(*value)?);
    }

    Ok(headers)
}

/// Returns the viewer coordinates provided by the `CloudFront` location headers.
///
/// Both coordinates are returned only when both headers hold valid numbers.
fn viewer_location(headers: &HeaderMap) -> (Option<f64>, Option<f64>) {
    let parse = |name: &str| -> Option<f64> { headers.get(name)?.to_str().ok()?.parse().ok() };
    match (
        parse("CloudFront-Viewer-Latitude"),
        parse("CloudFront-Viewer-Longitude"),
    ) {
        (Some(latitude), Some(longitude)) => (Some(latitude), Some(longitude)),
        _ => (None, None),
    }
}
