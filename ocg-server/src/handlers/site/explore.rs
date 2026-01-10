//! HTTP handlers for the global site explore page.
//!
//! The explore page provides a searchable interface for discovering groups and events
//! across all communities.

use std::collections::HashMap;

use anyhow::Result;
use askama::Template;
use axum::{
    Json,
    extract::{Query, RawQuery, State},
    http::{HeaderMap, Uri},
    response::{Html, IntoResponse},
};
use chrono::Duration;
use tracing::instrument;

use crate::{
    db::{
        DynDB,
        common::{SearchEventsOutput, SearchGroupsOutput},
    },
    handlers::{error::HandlerError, prepare_headers},
    templates::{
        PageId,
        auth::User,
        site::{
            explore::{
                self, Entity, EventsFilters, GroupsFilters, render_event_popover, render_group_popover,
            },
            pagination::{self, NavigationLinks},
        },
    },
};

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
    let entity: explore::Entity = query.get("entity").into();
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
            let filters = EventsFilters::new(&headers, &raw_query.unwrap_or_default())?;
            let events_section = prepare_events_section(&db, &filters).await?;
            template.events_section = Some(events_section);
        }
        explore::Entity::Groups => {
            let filters = GroupsFilters::new(&headers, &raw_query.unwrap_or_default())?;
            let groups_section = prepare_groups_section(&db, &filters).await?;
            template.groups_section = Some(groups_section);
        }
    }

    // Prepare response headers
    let headers = prepare_headers(Duration::minutes(10), &[])?;

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
    let filters = EventsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    let template = prepare_events_section(&db, &filters).await?;

    // Prepare response headers
    let url = pagination::build_url("/explore?entity=events", &filters)?;
    let extra_headers = [("HX-Push-Url", url.as_str())];
    let headers = prepare_headers(Duration::minutes(10), &extra_headers)?;

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
    let filters = EventsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    let template = prepare_events_result_section(&db, &filters).await?;

    // Prepare response headers
    let url = pagination::build_url("/explore?entity=events", &filters)?;
    let extra_headers = [("HX-Push-Url", url.as_str())];
    let headers = prepare_headers(Duration::minutes(10), &extra_headers)?;

    Ok((headers, Html(template.render()?)))
}

/// Prepares the events section template.
#[instrument(skip(db), err)]
async fn prepare_events_section(db: &DynDB, filters: &EventsFilters) -> Result<explore::EventsSection> {
    // Prepare template
    let (filters_options, results_section) = tokio::try_join!(
        db.get_filters_options(None),
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
    filters: &EventsFilters,
) -> Result<explore::EventsResultsSection> {
    // Search for events based on filters
    let SearchEventsOutput {
        mut events,
        bbox,
        total,
    } = db.search_events(filters).await?;

    // Render popover HTML for map and calendar views
    if filters.view_mode == Some(explore::ViewMode::Map)
        || filters.view_mode == Some(explore::ViewMode::Calendar)
    {
        for event in &mut events {
            event.popover_html = Some(render_event_popover(event)?);
        }
    }

    // Prepare template
    let template = explore::EventsResultsSection {
        events: events.into_iter().map(|event| explore::EventCard { event }).collect(),
        navigation_links: NavigationLinks::from_filters(&Entity::Events, filters, total)?,
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
    let filters = GroupsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    let template = prepare_groups_section(&db, &filters).await?;

    // Prepare response headers
    let url = pagination::build_url("/explore?entity=groups", &filters)?;
    let extra_headers = [("HX-Push-Url", url.as_str())];
    let headers = prepare_headers(Duration::minutes(10), &extra_headers)?;

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
    let filters = GroupsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    let template = prepare_groups_result_section(&db, &filters).await?;

    // Prepare response headers
    let url = pagination::build_url("/explore?entity=groups", &filters)?;
    let extra_headers = [("HX-Push-Url", url.as_str())];
    let headers = prepare_headers(Duration::minutes(10), &extra_headers)?;

    Ok((headers, Html(template.render()?)))
}

/// Prepares groups section template.
#[instrument(skip(db), err)]
async fn prepare_groups_section(db: &DynDB, filters: &GroupsFilters) -> Result<explore::GroupsSection> {
    // Prepare template
    let (filters_options, results_section) = tokio::try_join!(
        db.get_filters_options(None),
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
    filters: &GroupsFilters,
) -> Result<explore::GroupsResultsSection> {
    // Search for groups based on filters
    let SearchGroupsOutput {
        mut groups,
        bbox,
        total,
    } = db.search_groups(filters).await?;

    // Render popover HTML for map and calendar views
    if filters.view_mode == Some(explore::ViewMode::Map)
        || filters.view_mode == Some(explore::ViewMode::Calendar)
    {
        for group in &mut groups {
            group.popover_html = Some(render_group_popover(group)?);
        }
    }

    // Prepare template
    let template = explore::GroupsResultsSection {
        groups: groups.into_iter().map(|group| explore::GroupCard { group }).collect(),
        navigation_links: NavigationLinks::from_filters(&Entity::Groups, filters, total)?,
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
    let filters = EventsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    let mut search_events_output = db.search_events(&filters).await?;

    // Render popover HTML for each event
    for event in &mut search_events_output.events {
        event.popover_html = Some(render_event_popover(event)?);
    }

    // Prepare response headers
    let headers = prepare_headers(Duration::hours(1), &[])?;

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
    let filters = GroupsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    let mut search_groups_output = db.search_groups(&filters).await?;

    // Render popover HTML for each group
    for group in &mut search_groups_output.groups {
        group.popover_html = Some(render_group_popover(group)?);
    }

    // Prepare response headers
    let headers = prepare_headers(Duration::hours(1), &[])?;

    Ok((headers, Json(search_groups_output)).into_response())
}
