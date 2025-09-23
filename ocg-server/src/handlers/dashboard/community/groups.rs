//! HTTP handlers for managing groups in the community dashboard.

use std::collections::HashMap;

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::{Html, IntoResponse},
};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::CommunityId},
    templates::{
        community::explore,
        dashboard::community::groups::{self, Group},
    },
};

/// Maximum number of groups returned when listing dashboard groups.
pub(crate) const MAX_GROUPS_LISTED: usize = 1000;

// Pages handlers.

/// Displays the list of groups for the community dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let ts_query = query.get("ts_query").cloned();
    let filters = explore::GroupsFilters {
        limit: Some(MAX_GROUPS_LISTED),
        sort_by: Some(String::from("name")),
        ts_query: ts_query.clone(),
        ..explore::GroupsFilters::default()
    };
    let groups = db.search_community_groups(community_id, &filters).await?.groups;
    let template = groups::ListPage { groups, ts_query };

    Ok(Html(template.render()?))
}

/// Displays the page to add a new group.
#[instrument(skip_all, err)]
pub(crate) async fn add_page(
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (categories, regions) = tokio::try_join!(
        db.list_group_categories(community_id),
        db.list_regions(community_id)
    )?;
    let template = groups::AddPage { categories, regions };

    Ok(Html(template.render()?))
}

/// Displays the page to update an existing group.
#[instrument(skip_all, err)]
pub(crate) async fn update_page(
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (group, categories, regions) = tokio::try_join!(
        db.get_group_full(community_id, group_id),
        db.list_group_categories(community_id),
        db.list_regions(community_id)
    )?;
    let template = groups::UpdatePage {
        group,
        categories,
        regions,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Activates a group (sets active=true).
#[instrument(skip_all, err)]
pub(crate) async fn activate(
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Mark group as active in database
    db.activate_group(community_id, group_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-community-dashboard-table")],
    ))
}

/// Adds a new group to the database.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
    State(serde_qs_de): State<serde_qs::Config>,
    body: String,
) -> Result<impl IntoResponse, HandlerError> {
    // Parse group information from body
    let group: Group = match serde_qs_de.deserialize_str(&body).map_err(anyhow::Error::new) {
        Ok(group) => group,
        Err(e) => return Ok((StatusCode::UNPROCESSABLE_ENTITY, e.to_string()).into_response()),
    };

    // Add group to database
    db.add_group(community_id, &group).await?;

    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-community-dashboard-table")],
    )
        .into_response())
}

/// Deactivates a group (sets active=false without deleting).
#[instrument(skip_all, err)]
pub(crate) async fn deactivate(
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Mark group as not active in database
    db.deactivate_group(community_id, group_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-community-dashboard-table")],
    ))
}

/// Deletes a group from the database (soft delete).
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Delete group from database (soft delete)
    db.delete_group(community_id, group_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-community-dashboard-table")],
    ))
}

/// Updates an existing group's information in the database.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
    State(serde_qs_de): State<serde_qs::Config>,
    Path(group_id): Path<Uuid>,
    body: String,
) -> Result<impl IntoResponse, HandlerError> {
    // Parse group information from body
    let group: Group = match serde_qs_de.deserialize_str(&body).map_err(anyhow::Error::new) {
        Ok(group) => group,
        Err(e) => return Ok((StatusCode::UNPROCESSABLE_ENTITY, e.to_string()).into_response()),
    };

    // Update group in database
    db.update_group(community_id, group_id, &group).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-community-dashboard-table")],
    )
        .into_response())
}
