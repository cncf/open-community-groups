//! This module defines the HTTP handlers for the community site.

use super::extractors::CommunityId;
use crate::{
    db::DynDB,
    templates::community::{
        explore::{self, EventsFilters, GroupsFilters},
        home,
    },
};
use anyhow::{Error, Result};
use askama_axum::IntoResponse;
use axum::{
    extract::{Query, Request, State},
    http::StatusCode,
};
use std::{collections::HashMap, fmt::Debug};
use tracing::error;

/// Handler that returns the home index page.
pub(crate) async fn home_index(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    request: Request,
) -> Result<impl IntoResponse, StatusCode> {
    // Prepare home index template
    let json_data = db
        .get_community_home_index_data(community_id)
        .await
        .map_err(internal_error)?;
    let template = home::Index {
        path: request.uri().path().to_string(),
        ..home::Index::try_from(json_data).map_err(internal_error)?
    };

    Ok(template)
}

/// Handler that returns the explore index page.
pub(crate) async fn explore_index(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Query(params): Query<HashMap<String, String>>,
    request: Request,
) -> Result<impl IntoResponse, StatusCode> {
    // Prepare explore index template
    let entity: explore::Entity = params.get("entity").into();
    let json_data = db
        .get_community_explore_index_data(community_id)
        .await
        .map_err(internal_error)?;
    let mut template = explore::Index {
        entity: entity.clone(),
        path: request.uri().path().to_string(),
        ..explore::Index::try_from(json_data).map_err(internal_error)?
    };

    // Attach events or groups section template to the index template
    match entity {
        explore::Entity::Events => {
            let filters = EventsFilters::try_from_query(request.uri().query().unwrap_or_default())
                .map_err(internal_error)?;
            let events_json = db
                .search_community_events(community_id)
                .await
                .map_err(internal_error)?;
            template.events_section =
                Some(explore::EventsSection::new(filters, &events_json).map_err(internal_error)?);
        }
        explore::Entity::Groups => {
            let filters = GroupsFilters::try_from_query(request.uri().query().unwrap_or_default())
                .map_err(internal_error)?;
            let groups_json = db
                .search_community_groups(community_id)
                .await
                .map_err(internal_error)?;
            template.groups_section =
                Some(explore::GroupsSection::new(filters, &groups_json).map_err(internal_error)?);
        }
    }

    Ok(template)
}

/// Handler that returns the events section of the explore page.
pub(crate) async fn explore_events(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    request: Request,
) -> Result<impl IntoResponse, StatusCode> {
    // Prepare events section template
    let filters = EventsFilters::try_from_query(request.uri().query().unwrap_or_default())
        .map_err(internal_error)?;
    let events_json = db
        .search_community_events(community_id)
        .await
        .map_err(internal_error)?;
    let template = explore::EventsSection::new(filters, &events_json).map_err(internal_error)?;

    Ok(template)
}

/// Handler that returns the groups section of the explore page.
pub(crate) async fn explore_groups(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    request: Request,
) -> Result<impl IntoResponse, StatusCode> {
    // Prepare groups section template
    let filters = GroupsFilters::try_from_query(request.uri().query().unwrap_or_default())
        .map_err(internal_error)?;
    let groups_json = db
        .search_community_groups(community_id)
        .await
        .map_err(internal_error)?;
    let template = explore::GroupsSection::new(filters, &groups_json).map_err(internal_error)?;

    Ok(template)
}

/// Helper for mapping any error into a `500 Internal Server Error` response.
#[allow(clippy::needless_pass_by_value)]
fn internal_error<E>(err: E) -> StatusCode
where
    E: Into<Error> + Debug,
{
    error!(?err);
    StatusCode::INTERNAL_SERVER_ERROR
}
