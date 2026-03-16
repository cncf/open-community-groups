//! HTTP handlers for managing regions in the community dashboard.

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
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedCommunityId, ValidatedForm},
    },
    templates::dashboard::community::regions::{self, RegionInput},
    types::permissions::CommunityPermission,
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Displays the list of regions for the selected community.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (can_manage_taxonomy, regions) = tokio::try_join!(
        db.user_has_community_permission(&community_id, &user.user_id, CommunityPermission::TaxonomyWrite),
        db.list_regions(community_id)
    )?;
    let template = regions::ListPage {
        can_manage_taxonomy,
        regions,
    };

    Ok(Html(template.render()?))
}

/// Displays the form to create a new region.
#[instrument(skip_all, err)]
pub(crate) async fn add_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let can_manage_taxonomy = db
        .user_has_community_permission(&community_id, &user.user_id, CommunityPermission::TaxonomyWrite)
        .await?;
    let template = regions::AddPage { can_manage_taxonomy };

    Ok(Html(template.render()?))
}

/// Displays the form to update an existing region.
#[instrument(skip_all, err)]
pub(crate) async fn update_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    Path(region_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (can_manage_taxonomy, regions) = tokio::try_join!(
        db.user_has_community_permission(&community_id, &user.user_id, CommunityPermission::TaxonomyWrite),
        db.list_regions(community_id)
    )?;
    let Some(region) = regions.into_iter().find(|region| region.region_id == region_id) else {
        return Err(HandlerError::Database("region not found".to_string()));
    };
    let template = regions::UpdatePage {
        can_manage_taxonomy,
        region,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Adds a new region to the selected community.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    ValidatedForm(region): ValidatedForm<RegionInput>,
) -> Result<impl IntoResponse, HandlerError> {
    db.add_region(community_id, &region).await?;

    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-community-dashboard-table")],
    ))
}

/// Deletes a region from the selected community.
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    Path(region_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    db.delete_region(community_id, region_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-community-dashboard-table")],
    ))
}

/// Updates a region in the selected community.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    Path(region_id): Path<Uuid>,
    ValidatedForm(region): ValidatedForm<RegionInput>,
) -> Result<impl IntoResponse, HandlerError> {
    db.update_region(community_id, region_id, &region).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-community-dashboard-table")],
    ))
}
