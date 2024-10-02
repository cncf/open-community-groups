//! This module defines the HTTP handlers for the community site.

use super::extractors::CommunityId;
use crate::{
    db::DynDB,
    templates::community::{
        explore::{self, Explore},
        home::Home,
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

/// Handler that returns the home page.
pub(crate) async fn home(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Query(params): Query<HashMap<String, String>>,
    request: Request,
) -> Result<impl IntoResponse, StatusCode> {
    let json_data = db
        .get_community_home_data(community_id)
        .await
        .map_err(internal_error)?;
    let template = Home {
        params,
        path: request.uri().path().to_string(),
        ..Home::try_from(json_data).map_err(internal_error)?
    };

    Ok(template)
}

/// Handler that returns the explore page.
pub(crate) async fn explore(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Query(params): Query<HashMap<String, String>>,
    request: Request,
) -> Result<impl IntoResponse, StatusCode> {
    let json_data = db
        .get_community_explore_data(community_id)
        .await
        .map_err(internal_error)?;
    let template = Explore {
        params,
        path: request.uri().path().to_string(),
        ..Explore::try_from(json_data).map_err(internal_error)?
    };

    Ok(template)
}

/// Handler that returns the explore events section.
pub(crate) async fn explore_events(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
) -> Result<impl IntoResponse, StatusCode> {
    let json_data = db
        .search_community_events(community_id)
        .await
        .map_err(internal_error)?;
    let template = explore::Events::try_from(json_data).map_err(internal_error)?;

    Ok(template)
}

/// Handler that returns the explore groups section.
pub(crate) async fn explore_groups(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
) -> Result<impl IntoResponse, StatusCode> {
    let json_data = db
        .search_community_groups(community_id)
        .await
        .map_err(internal_error)?;
    let template = explore::Groups::try_from(json_data).map_err(internal_error)?;

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
