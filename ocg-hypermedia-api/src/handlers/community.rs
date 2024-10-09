//! This module defines the HTTP handlers for the community site.

use super::{error::HandlerError, extractors::CommunityId};
use crate::{
    db::DynDB,
    templates::community::{
        explore::{self, EventsFilters, GroupsFilters},
        home,
    },
};
use anyhow::Result;
use askama_axum::IntoResponse;
use axum::{
    extract::{Query, RawForm, State},
    http::Uri,
};
use std::collections::HashMap;

/// Handler that returns the home index page.
pub(crate) async fn home_index(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare home index template
    #[rustfmt::skip]
    let (
        community,
        recently_added_groups,
        upcoming_in_person_events,
        upcoming_virtual_events
    ) = tokio::try_join!(
        db.get_community(community_id),
        db.get_community_recently_added_groups(community_id),
        db.get_community_upcoming_in_person_events(community_id),
        db.get_community_upcoming_virtual_events(community_id),
    )?;
    let template = home::Index {
        community,
        path: uri.path().to_string(),
        recently_added_groups,
        upcoming_in_person_events,
        upcoming_virtual_events,
    };

    Ok(template)
}

/// Handler that returns the explore index page.
pub(crate) async fn explore_index(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Query(params): Query<HashMap<String, String>>,
    uri: Uri,
    RawForm(form): RawForm,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare explore index template
    let community = db.get_community(community_id).await?;
    let entity: explore::Entity = params.get("entity").into();
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
            let filters = EventsFilters::try_from_form(&form)?;
            let (filters_options, events) = tokio::try_join!(
                db.get_community_events_filters_options(community_id),
                db.search_community_events(community_id, &filters)
            )?;
            template.events_section = Some(explore::EventsSection {
                filters,
                filters_options,
                events,
            });
        }
        explore::Entity::Groups => {
            let filters = GroupsFilters::try_from_form(&form)?;
            let groups = db.search_community_groups(community_id, &filters).await?;
            template.groups_section = Some(explore::GroupsSection { filters, groups });
        }
    }

    Ok(template)
}

/// Handler that returns the events section of the explore page.
pub(crate) async fn explore_events(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    RawForm(form): RawForm,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare events section template
    let filters = EventsFilters::try_from_form(&form)?;
    let filters_params = serde_html_form::to_string(&filters)?;
    let (filters_options, events) = tokio::try_join!(
        db.get_community_events_filters_options(community_id),
        db.search_community_events(community_id, &filters)
    )?;
    let template = explore::EventsSection {
        filters,
        filters_options,
        events,
    };

    // Prepare response headers
    let mut hx_push_url = "/explore?entity=events".to_string();
    if !filters_params.is_empty() {
        hx_push_url.push_str(&format!("&{filters_params}"));
    }
    let headers = [("HX-Push-Url", hx_push_url)];

    Ok((headers, template))
}

/// Handler that returns the groups section of the explore page.
pub(crate) async fn explore_groups(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    RawForm(form): RawForm,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare groups section template
    let filters = GroupsFilters::try_from_form(&form)?;
    let filters_params = serde_html_form::to_string(&filters)?;
    let groups = db.search_community_groups(community_id, &filters).await?;
    let template = explore::GroupsSection { filters, groups };

    // Prepare response headers
    let mut hx_push_url = "/explore?entity=groups".to_string();
    if !filters_params.is_empty() {
        hx_push_url.push_str(&format!("&{filters_params}"));
    }
    let headers = [("HX-Push-Url", hx_push_url)];

    Ok((headers, template))
}
