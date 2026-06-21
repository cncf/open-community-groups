//! HTTP handlers for the global site explore page.
//!
//! The explore page provides a searchable interface for discovering groups and events
//! across all alliances.

use std::collections::HashMap;

use anyhow::Result;
use askama::Template;
use axum::{
    Json,
    extract::{Query, RawQuery, State},
    http::{HeaderMap, HeaderName, HeaderValue, Uri, header::CACHE_CONTROL},
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    db::{
        DynDB,
        common::{SearchEventsOutput, SearchGroupsOutput},
    },
    handlers::{error::HandlerError, extend_public_shared_cache_headers},
    router::CACHE_CONTROL_NO_STORE,
    templates::{
        PageId,
        auth::User,
        site::explore::{
            self, render_calendar_event_popover, render_event_popover, render_group_popover,
        },
    },
    types::{
        pagination::{self, NavigationLinks},
        search::{SearchEventsFilters, SearchGroupsFilters, ViewMode},
    },
};

#[cfg(test)]
mod tests;

// Pages and sections handlers.

/// Handler that renders the global explore page with either events or groups section.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let site_settings = db.get_site_settings().await?;
    let entity: explore::Entity = query.get("entity").map(String::as_str).into();
    let mut template = explore::Page {
        entity: entity.clone(),
        page_id: PageId::SiteExplore,
        path: uri.path().to_string(),
        site_settings,
        user: User::default(),
        events_section: None,
        groups_section: None,
    };

    // Attach events or groups section template to the page template
    match entity {
        explore::Entity::Events => {
            let filters = SearchEventsFilters::new(&headers, &raw_query.unwrap_or_default())?;
            let events_section = prepare_events_section(&db, &filters).await?;
            template.events_section = Some(events_section);
        }
        explore::Entity::Groups => {
            let filters = SearchGroupsFilters::new(&headers, &raw_query.unwrap_or_default())?;
            let groups_section = prepare_groups_section(&db, &filters).await?;
            template.groups_section = Some(groups_section);
        }
    }

    // Prepare response headers after the active section has resolved its filters
    let headers = search_response_headers(match &entity {
        explore::Entity::Events => template
            .events_section
            .as_ref()
            .is_some_and(|section| section.filters.uses_viewer_location()),
        explore::Entity::Groups => template
            .groups_section
            .as_ref()
            .is_some_and(|section| section.filters.uses_viewer_location()),
    })?;

    Ok((headers, Html(template.render()?)))
}

/// Handler that renders the events section of the explore page.
#[instrument(skip_all, err)]
pub(crate) async fn events_section(
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare events section template
    let filters = SearchEventsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    let template = prepare_events_section(&db, &filters).await?;

    // Prepare response headers
    let url = pagination::build_url("/explore?entity=events", &filters)?;
    let headers = search_response_headers_with_extra(
        filters.uses_viewer_location(),
        &[("HX-Push-Url", url.as_str())],
    )?;

    Ok((headers, Html(template.render()?)))
}

/// Handler that renders the events results section of the explore page.
#[instrument(skip_all, err)]
pub(crate) async fn events_results_section(
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare events results section template
    let filters = SearchEventsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    let template = prepare_events_result_section(&db, &filters).await?;

    // Prepare response headers
    let url = pagination::build_url("/explore?entity=events", &filters)?;
    let headers = search_response_headers_with_extra(
        filters.uses_viewer_location(),
        &[("HX-Push-Url", url.as_str())],
    )?;

    Ok((headers, Html(template.render()?)))
}

/// Prepares the events section template.
#[instrument(skip(db), err)]
async fn prepare_events_section(
    db: &DynDB,
    filters: &SearchEventsFilters,
) -> Result<explore::EventsSection> {
    // Pass alliance_name to get_filters_options only when exactly one is selected
    let alliance_name = if filters.alliance.len() == 1 {
        Some(filters.alliance[0].clone())
    } else {
        None
    };

    // Prepare template
    let (filters_options, results_section) = tokio::try_join!(
        db.get_filters_options(alliance_name, Some(explore::Entity::Events)),
        prepare_events_result_section(db, filters)
    )?;
    let template = explore::EventsSection {
        filters: filters.clone(),
        filters_options,
        results_section,
    };

    Ok(template)
}

/// Prepares the events result section template.
#[instrument(skip(db), err)]
async fn prepare_events_result_section(
    db: &DynDB,
    filters: &SearchEventsFilters,
) -> Result<explore::EventsResultsSection> {
    // Search for events based on filters
    let SearchEventsOutput {
        mut events,
        bbox,
        total,
    } = db.search_events(filters).await?;

    // Render popover HTML for map and calendar views
    if filters.view_mode == Some(ViewMode::Map) {
        for event in &mut events {
            event.popover_html = Some(render_event_popover(event)?);
        }
    } else if filters.view_mode == Some(ViewMode::Calendar) {
        for event in &mut events {
            event.popover_html = Some(render_calendar_event_popover(event)?);
        }
    }

    // Prepare template
    let template = explore::EventsResultsSection {
        events: events.into_iter().map(|event| explore::EventCard { event }).collect(),
        navigation_links: NavigationLinks::from_filters(
            filters,
            total,
            "/explore?entity=events",
            "/explore/events-results-section",
        )?,
        total,
        bbox,
        offset: filters.offset,
        view_mode: filters.view_mode.clone(),
    };

    Ok(template)
}

/// Handler that renders the groups section of the explore page.
#[instrument(skip_all, err)]
pub(crate) async fn groups_section(
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare groups section template
    let filters = SearchGroupsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    let template = prepare_groups_section(&db, &filters).await?;

    // Prepare response headers
    let url = pagination::build_url("/explore?entity=groups", &filters)?;
    let headers = search_response_headers_with_extra(
        filters.uses_viewer_location(),
        &[("HX-Push-Url", url.as_str())],
    )?;

    Ok((headers, Html(template.render()?)))
}

/// Handler that renders the groups results section of the explore page.
#[instrument(skip_all, err)]
pub(crate) async fn groups_results_section(
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare groups section template
    let filters = SearchGroupsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    let template = prepare_groups_result_section(&db, &filters).await?;

    // Prepare response headers
    let url = pagination::build_url("/explore?entity=groups", &filters)?;
    let headers = search_response_headers_with_extra(
        filters.uses_viewer_location(),
        &[("HX-Push-Url", url.as_str())],
    )?;

    Ok((headers, Html(template.render()?)))
}

/// Prepares groups section template.
#[instrument(skip(db), err)]
async fn prepare_groups_section(
    db: &DynDB,
    filters: &SearchGroupsFilters,
) -> Result<explore::GroupsSection> {
    // Pass alliance_name to get_filters_options only when exactly one is selected
    let alliance_name = if filters.alliance.len() == 1 {
        Some(filters.alliance[0].clone())
    } else {
        None
    };

    // Prepare template
    let (filters_options, results_section) = tokio::try_join!(
        db.get_filters_options(alliance_name, Some(explore::Entity::Groups)),
        prepare_groups_result_section(db, filters)
    )?;
    let template = explore::GroupsSection {
        filters: filters.clone(),
        filters_options,
        results_section,
    };

    Ok(template)
}

/// Prepares the groups result section template.
#[instrument(skip(db), err)]
async fn prepare_groups_result_section(
    db: &DynDB,
    filters: &SearchGroupsFilters,
) -> Result<explore::GroupsResultsSection> {
    // Search for groups based on filters
    let SearchGroupsOutput {
        mut groups,
        bbox,
        total,
    } = db.search_groups(filters).await?;

    // Render popover HTML for map and calendar views
    if filters.view_mode == Some(ViewMode::Map) || filters.view_mode == Some(ViewMode::Calendar) {
        for group in &mut groups {
            group.popover_html = Some(render_group_popover(group)?);
        }
    }

    // Prepare template
    let template = explore::GroupsResultsSection {
        groups: groups.into_iter().map(|group| explore::GroupCard { group }).collect(),
        navigation_links: NavigationLinks::from_filters(
            filters,
            total,
            "/explore?entity=groups",
            "/explore/groups-results-section",
        )?,
        total,
        bbox,
        offset: filters.offset,
        view_mode: filters.view_mode.clone(),
    };

    Ok(template)
}

// JSON search handlers.

/// Handler for the events search endpoint (JSON format).
#[instrument(skip_all, err)]
pub(crate) async fn search_events(
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Search events
    let filters = SearchEventsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    let mut search_events_output = db.search_events(&filters).await?;

    // Render popover HTML for each event
    for event in &mut search_events_output.events {
        event.popover_html = Some(render_event_popover(event)?);
    }

    // Prepare response headers
    let headers = search_response_headers(filters.uses_viewer_location())?;

    Ok((headers, Json(search_events_output)).into_response())
}

/// Handler for the groups search endpoint (JSON format).
#[instrument(skip_all, err)]
pub(crate) async fn search_groups(
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Search groups
    let filters = SearchGroupsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    let mut search_groups_output = db.search_groups(&filters).await?;

    // Render popover HTML for each group
    for group in &mut search_groups_output.groups {
        group.popover_html = Some(render_group_popover(group)?);
    }

    // Prepare response headers
    let headers = search_response_headers(filters.uses_viewer_location())?;

    Ok((headers, Json(search_groups_output)).into_response())
}

// Helpers.

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
