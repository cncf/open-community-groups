//! HTTP handlers for managing groups in the community dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::{Html, IntoResponse},
};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::CommunityId},
    templates::dashboard::community::groups::{self, Group},
};

// Pages handlers.

/// Displays the list of groups for the community dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    let groups = db.list_community_groups(community_id).await?;
    let template = groups::ListPage { groups };

    Ok(Html(template.render()?))
}

/// Displays the page to add a new group.
#[instrument(skip_all, err)]
pub(crate) async fn add_page(
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
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
    let (group, categories, regions) = tokio::try_join!(
        db.get_group_full(group_id),
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
        [(
            "HX-Location",
            r#"{"path":"/dashboard/community?tab=groups", "target":"body"}"#,
        )],
    )
        .into_response())
}

/// Updates an existing group's information in the database.
#[instrument(skip_all, err)]
pub(crate) async fn update(
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
    db.update_group(group_id, &group).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [(
            "HX-Location",
            r#"{"path":"/dashboard/community?tab=groups", "target":"body"}"#,
        )],
    )
        .into_response())
}

/// Deletes a group from the database (soft delete).
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Delete group from database (soft delete)
    db.delete_group(group_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [(
            "HX-Location",
            r#"{"path":"/dashboard/community?tab=groups", "target":"body"}"#,
        )],
    )
        .into_response())
}
