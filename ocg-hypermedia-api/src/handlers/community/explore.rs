//! This module defines the HTTP handlers for the explore page of the community
//! site.

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::CommunityId},
    templates::community::explore::{self, EventsFilters, GroupsFilters},
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
                filters,
                filters_options,
                results_section: explore::EventsResultsSection {
                    events,
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
                filters,
                filters_options,
                results_section: explore::GroupsResultsSection {
                    groups,
                    offset,
                    total,
                },
            });
        }
    }

    Ok(template)
}

/// Handler that returns the events section (filters + events) of the explore
/// page.
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
            offset: filters.offset,
            total,
        },
    };

    // Prepare response headers
    let filters_params = serde_html_form::to_string(&filters)?;
    let mut hx_push_url = "/explore?entity=events".to_string();
    if !filters_params.is_empty() {
        hx_push_url.push_str(&format!("&{filters_params}"));
    }
    let headers = [("HX-Push-Url", hx_push_url)];

    Ok((headers, template))
}

/// Handler that returns the groups section (filters + groups) of the explore
/// page.
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
            offset: filters.offset,
            total,
        },
    };

    // Prepare response headers
    let filters_params = serde_html_form::to_string(&filters)?;
    let mut hx_push_url = "/explore?entity=groups".to_string();
    if !filters_params.is_empty() {
        hx_push_url.push_str(&format!("&{filters_params}"));
    }
    let headers = [("HX-Push-Url", hx_push_url)];

    Ok((headers, template))
}
