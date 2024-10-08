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
    let json_data = db.get_community_home_index_data(community_id).await?;
    let template = home::Index {
        path: uri.path().to_string(),
        ..home::Index::try_from(json_data)?
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
    let entity: explore::Entity = params.get("entity").into();
    let json_data = db.get_community_explore_index_data(community_id).await?;
    let mut template = explore::Index {
        entity: entity.clone(),
        path: uri.path().to_string(),
        ..explore::Index::try_from(json_data)?
    };

    // Attach events or groups section template to the index template
    match entity {
        explore::Entity::Events => {
            let filters = EventsFilters::try_from_form(&form)?;
            let events_json = db.search_community_events(community_id, &filters).await?;
            template.events_section = Some(explore::EventsSection::new(&filters, &events_json)?);
        }
        explore::Entity::Groups => {
            let filters = GroupsFilters::try_from_form(&form)?;
            let groups_json = db.search_community_groups(community_id, &filters).await?;
            template.groups_section = Some(explore::GroupsSection::new(&filters, &groups_json)?);
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
    let events_json = db.search_community_events(community_id, &filters).await?;
    let template = explore::EventsSection::new(&filters, &events_json)?;

    // Prepare response headers
    let filters_params = serde_html_form::to_string(&filters)?;
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
    let groups_json = db.search_community_groups(community_id, &filters).await?;
    let template = explore::GroupsSection::new(&filters, &groups_json)?;

    // Prepare response headers
    let filters_params = serde_html_form::to_string(&filters)?;
    let mut hx_push_url = "/explore?entity=groups".to_string();
    if !filters_params.is_empty() {
        hx_push_url.push_str(&format!("&{filters_params}"));
    }
    let headers = [("HX-Push-Url", hx_push_url)];

    Ok((headers, template))
}
