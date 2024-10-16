//! This module defines the HTTP handlers for the explore page of the community
//! site.

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::CommunityId},
    templates::community::explore::{self, EventsFilters, GroupsFilters, NavigationLinks},
};
use anyhow::Result;
use askama_axum::IntoResponse;
use axum::{
    extract::{Query, RawQuery, State},
    http::Uri,
};
use std::collections::HashMap;

/// Handler that returns the explore index page.
pub(crate) async fn index(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Query(query): Query<HashMap<String, String>>,
    RawQuery(raw_query): RawQuery,
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
            let filters = EventsFilters::try_from_raw_query(&raw_query.unwrap_or_default())?;
            let (filters_options, (events, total)) = tokio::try_join!(
                db.get_community_filters_options(community_id),
                db.search_community_events(community_id, &filters)
            )?;
            let offset = filters.offset;
            template.events_section = Some(explore::EventsSection {
                filters: filters.clone(),
                filters_options,
                results_section: explore::EventsResultsSection {
                    events,
                    navigation_links: NavigationLinks::from_events_filters(&filters, total)?,
                    offset,
                    total,
                },
            });
        }
        explore::Entity::Groups => {
            let filters = GroupsFilters::try_from_raw_query(&raw_query.unwrap_or_default())?;
            let (filters_options, (groups, total)) = tokio::try_join!(
                db.get_community_filters_options(community_id),
                db.search_community_groups(community_id, &filters)
            )?;
            let offset = filters.offset;
            template.groups_section = Some(explore::GroupsSection {
                filters: filters.clone(),
                filters_options,
                results_section: explore::GroupsResultsSection {
                    groups,
                    navigation_links: NavigationLinks::from_groups_filters(&filters, total)?,
                    offset,
                    total,
                },
            });
        }
    }

    Ok(template)
}

/// Handler that returns the events section of the explore page.
pub(crate) async fn events_section(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare events section template
    let filters = EventsFilters::try_from_raw_query(&raw_query.unwrap_or_default())?;
    let (filters_options, (events, total)) = tokio::try_join!(
        db.get_community_filters_options(community_id),
        db.search_community_events(community_id, &filters)
    )?;
    let template = explore::EventsSection {
        filters: filters.clone(),
        filters_options,
        results_section: explore::EventsResultsSection {
            events,
            navigation_links: NavigationLinks::from_events_filters(&filters, total)?,
            offset: filters.offset,
            total,
        },
    };

    // Prepare response headers
    let headers = [(
        "HX-Push-Url",
        explore::build_url("/explore?entity=events", &filters)?,
    )];

    Ok((headers, template))
}

/// Handler that returns the events results section of the explore page.
pub(crate) async fn events_results_section(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare events results section template
    let filters = EventsFilters::try_from_raw_query(&raw_query.unwrap_or_default())?;
    let (events, total) = db.search_community_events(community_id, &filters).await?;
    let template = explore::EventsResultsSection {
        events,
        navigation_links: NavigationLinks::from_events_filters(&filters, total)?,
        offset: filters.offset,
        total,
    };

    // Prepare response headers
    let headers = [(
        "HX-Push-Url",
        explore::build_url("/explore?entity=events", &filters)?,
    )];

    Ok((headers, template))
}

/// Handler that returns the groups section of the explore page.
pub(crate) async fn groups_section(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare groups section template
    let filters = GroupsFilters::try_from_raw_query(&raw_query.unwrap_or_default())?;
    let (filters_options, (groups, total)) = tokio::try_join!(
        db.get_community_filters_options(community_id),
        db.search_community_groups(community_id, &filters)
    )?;
    let template = explore::GroupsSection {
        filters: filters.clone(),
        filters_options,
        results_section: explore::GroupsResultsSection {
            groups,
            navigation_links: NavigationLinks::from_groups_filters(&filters, total)?,
            offset: filters.offset,
            total,
        },
    };

    // Prepare response headers
    let headers = [(
        "HX-Push-Url",
        explore::build_url("/explore?entity=groups", &filters)?,
    )];

    Ok((headers, template))
}

/// Handler that returns the groups results section of the explore page.
pub(crate) async fn groups_results_section(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare groups section template
    let filters = GroupsFilters::try_from_raw_query(&raw_query.unwrap_or_default())?;
    let (groups, total) = db.search_community_groups(community_id, &filters).await?;
    let template = explore::GroupsResultsSection {
        groups,
        navigation_links: NavigationLinks::from_groups_filters(&filters, total)?,
        offset: filters.offset,
        total,
    };

    // Prepare response headers
    let headers = [(
        "HX-Push-Url",
        explore::build_url("/explore?entity=groups", &filters)?,
    )];

    Ok((headers, template))
}
