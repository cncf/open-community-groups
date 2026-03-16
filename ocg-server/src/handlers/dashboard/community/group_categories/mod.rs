//! HTTP handlers for managing group categories in the community dashboard.

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
    templates::dashboard::community::group_categories::{self, GroupCategoryInput},
    types::permissions::CommunityPermission,
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Displays the list of group categories for the selected community.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (can_manage_taxonomy, categories) = tokio::try_join!(
        db.user_has_community_permission(&community_id, &user.user_id, CommunityPermission::TaxonomyWrite),
        db.list_group_categories(community_id)
    )?;
    let template = group_categories::ListPage {
        can_manage_taxonomy,
        categories,
    };

    Ok(Html(template.render()?))
}

/// Displays the form to create a new group category.
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
    let template = group_categories::AddPage { can_manage_taxonomy };

    Ok(Html(template.render()?))
}

/// Displays the form to update an existing group category.
#[instrument(skip_all, err)]
pub(crate) async fn update_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    Path(group_category_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (can_manage_taxonomy, categories) = tokio::try_join!(
        db.user_has_community_permission(&community_id, &user.user_id, CommunityPermission::TaxonomyWrite),
        db.list_group_categories(community_id)
    )?;
    let Some(category) = categories
        .into_iter()
        .find(|category| category.group_category_id == group_category_id)
    else {
        return Err(HandlerError::Database("group category not found".to_string()));
    };
    let template = group_categories::UpdatePage {
        can_manage_taxonomy,
        category,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Adds a new group category to the selected community.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    ValidatedForm(group_category): ValidatedForm<GroupCategoryInput>,
) -> Result<impl IntoResponse, HandlerError> {
    db.add_group_category(community_id, &group_category).await?;

    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-community-dashboard-table")],
    ))
}

/// Deletes a group category from the selected community.
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    Path(group_category_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    db.delete_group_category(community_id, group_category_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-community-dashboard-table")],
    ))
}

/// Updates a group category in the selected community.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    Path(group_category_id): Path<Uuid>,
    ValidatedForm(group_category): ValidatedForm<GroupCategoryInput>,
) -> Result<impl IntoResponse, HandlerError> {
    db.update_group_category(community_id, group_category_id, &group_category)
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-community-dashboard-table")],
    ))
}
