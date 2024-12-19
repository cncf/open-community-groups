//! This module defines the HTTP handlers for the explore page of the community
//! site.

use std::collections::HashMap;

use anyhow::Result;
use axum::{
    extract::{Query, RawQuery, State},
    http::{HeaderMap, Uri},
    response::{Html, IntoResponse},
};
use rinja::Template;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::{DynDB, SearchCommunityEventsOutput, SearchCommunityGroupsOutput},
    handlers::{error::HandlerError, extractors::CommunityId},
    templates::community::explore::{self, Entity, EventsFilters, GroupsFilters, NavigationLinks},
};

/// Handler that returns the explore index page.
#[instrument(skip_all, err)]
pub(crate) async fn index(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Query(query): Query<HashMap<String, String>>,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare explore index template
    let community = db.get_community(community_id).await?;
    let entity: explore::Entity = query.get("entity").into();
    let mut template = explore::Index {
        community,
        entity: entity.clone(),
        path: uri.path().to_string(),
        events_section: None,
        groups_section: None,
    };

    // Attach events or groups section template to the index template
    match entity {
        explore::Entity::Events => {
            let filters = EventsFilters::new(&headers, &raw_query.unwrap_or_default())?;
            let events_section = prepare_events_section(&db, community_id, &filters).await?;
            template.events_section = Some(events_section);
        }
        explore::Entity::Groups => {
            let filters = GroupsFilters::new(&headers, &raw_query.unwrap_or_default())?;
            let groups_section = prepare_groups_section(&db, community_id, &filters).await?;
            template.groups_section = Some(groups_section);
        }
    }

    Ok(Html(template.render()?))
}

/// Handler that returns the events section of the explore page.
#[instrument(skip_all, err)]
pub(crate) async fn events_section(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare events section template
    let filters = EventsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    let template = prepare_events_section(&db, community_id, &filters).await?;

    // Prepare response headers
    let headers = [(
        "HX-Push-Url",
        explore::build_url("/explore?entity=events", &filters)?,
    )];

    Ok((headers, Html(template.render()?)))
}

/// Handler that returns the events results section of the explore page.
#[instrument(skip_all, err)]
pub(crate) async fn events_results_section(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare events results section template
    let filters = EventsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    let SearchCommunityEventsOutput { events, bbox, total } =
        db.search_community_events(community_id, &filters).await?;
    let template = explore::EventsResultsSection {
        events,
        navigation_links: NavigationLinks::from_filters(&Entity::Events, &filters, total)?,
        total,
        bbox,
        offset: filters.offset,
        view_mode: filters.view_mode.clone(),
    };

    // Prepare response headers
    let headers = [(
        "HX-Push-Url",
        explore::build_url("/explore?entity=events", &filters)?,
    )];

    Ok((headers, Html(template.render()?)))
}

/// Handler that returns the groups section of the explore page.
#[instrument(skip_all, err)]
pub(crate) async fn groups_section(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare groups section template
    let filters = GroupsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    let template = prepare_groups_section(&db, community_id, &filters).await?;

    // Prepare response headers
    let headers = [(
        "HX-Push-Url",
        explore::build_url("/explore?entity=groups", &filters)?,
    )];

    Ok((headers, Html(template.render()?)))
}

/// Handler that returns the groups results section of the explore page.
#[instrument(skip_all, err)]
pub(crate) async fn groups_results_section(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare groups section template
    let filters = GroupsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    let SearchCommunityGroupsOutput { groups, bbox, total } =
        db.search_community_groups(community_id, &filters).await?;
    let template = explore::GroupsResultsSection {
        groups,
        navigation_links: NavigationLinks::from_filters(&Entity::Groups, &filters, total)?,
        total,
        bbox,
        offset: filters.offset,
        view_mode: filters.view_mode.clone(),
    };

    // Prepare response headers
    let headers = [(
        "HX-Push-Url",
        explore::build_url("/explore?entity=groups", &filters)?,
    )];

    Ok((headers, Html(template.render()?)))
}

/// Handler that returns the events search results.
#[instrument(skip_all, err)]
pub(crate) async fn search_events(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Search events
    let mut filters = EventsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    filters.include_popover_html = Some(true);
    let search_events_output = db.search_community_events(community_id, &filters).await?;
    let json_data = serde_json::to_string(&search_events_output)?;

    Ok(json_data)
}

/// Handler that returns the groups search results.
#[instrument(skip_all, err)]
pub(crate) async fn search_groups(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Search groups
    let mut filters = GroupsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    filters.include_popover_html = Some(true);
    let search_groups_output = db.search_community_groups(community_id, &filters).await?;
    let json_data = serde_json::to_string(&search_groups_output)?;

    Ok(json_data)
}

/// Prepare events section template.
#[instrument(skip(db), err)]
async fn prepare_events_section(
    db: &DynDB,
    community_id: Uuid,
    filters: &EventsFilters,
) -> Result<explore::EventsSection> {
    let (filters_options, SearchCommunityEventsOutput { events, bbox, total }) = tokio::try_join!(
        db.get_community_filters_options(community_id),
        db.search_community_events(community_id, filters)
    )?;
    let template = explore::EventsSection {
        filters: filters.clone(),
        filters_options,
        results_section: explore::EventsResultsSection {
            events,
            navigation_links: NavigationLinks::from_filters(&Entity::Events, filters, total)?,
            total,
            bbox,
            offset: filters.offset,
            view_mode: filters.view_mode.clone(),
        },
    };

    Ok(template)
}

/// Prepare groups section template.
#[instrument(skip(db), err)]
async fn prepare_groups_section(
    db: &DynDB,
    community_id: Uuid,
    filters: &GroupsFilters,
) -> Result<explore::GroupsSection> {
    let (filters_options, SearchCommunityGroupsOutput { groups, bbox, total }) = tokio::try_join!(
        db.get_community_filters_options(community_id),
        db.search_community_groups(community_id, filters)
    )?;
    let template = explore::GroupsSection {
        filters: filters.clone(),
        filters_options,
        results_section: explore::GroupsResultsSection {
            groups,
            navigation_links: NavigationLinks::from_filters(&Entity::Groups, filters, total)?,
            total,
            bbox,
            offset: filters.offset,
            view_mode: filters.view_mode.clone(),
        },
    };

    Ok(template)
}
