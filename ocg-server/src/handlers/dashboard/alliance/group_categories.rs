//! HTTP handlers for managing group categories in the alliance dashboard.

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
        extractors::{CurrentUser, SelectedAllianceId, ValidatedForm},
    },
    templates::dashboard::alliance::group_categories::{self, GroupCategoryInput},
    types::permissions::AlliancePermission,
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Displays the list of group categories for the selected alliance.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (can_manage_taxonomy, categories) = tokio::try_join!(
        db.user_has_alliance_permission(
            &alliance_id,
            &user.user_id,
            AlliancePermission::TaxonomyWrite
        ),
        db.list_group_categories(alliance_id)
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
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let can_manage_taxonomy = db
        .user_has_alliance_permission(
            &alliance_id,
            &user.user_id,
            AlliancePermission::TaxonomyWrite,
        )
        .await?;
    let template = group_categories::AddPage {
        can_manage_taxonomy,
    };

    Ok(Html(template.render()?))
}

/// Displays the form to update an existing group category.
#[instrument(skip_all, err)]
pub(crate) async fn update_page(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    Path(group_category_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (can_manage_taxonomy, categories) = tokio::try_join!(
        db.user_has_alliance_permission(
            &alliance_id,
            &user.user_id,
            AlliancePermission::TaxonomyWrite
        ),
        db.list_group_categories(alliance_id)
    )?;
    let Some(category) = categories
        .into_iter()
        .find(|category| category.group_category_id == group_category_id)
    else {
        return Err(HandlerError::Database(
            "group category not found".to_string(),
        ));
    };
    let template = group_categories::UpdatePage {
        can_manage_taxonomy,
        category,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Adds a new group category to the selected alliance.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    ValidatedForm(group_category): ValidatedForm<GroupCategoryInput>,
) -> Result<impl IntoResponse, HandlerError> {
    db.add_group_category(user.user_id, alliance_id, &group_category)
        .await?;

    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-alliance-dashboard-table")],
    ))
}

/// Deletes a group category from the selected alliance.
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    Path(group_category_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    db.delete_group_category(user.user_id, alliance_id, group_category_id)
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-alliance-dashboard-table")],
    ))
}

/// Updates a group category in the selected alliance.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    Path(group_category_id): Path<Uuid>,
    ValidatedForm(group_category): ValidatedForm<GroupCategoryInput>,
) -> Result<impl IntoResponse, HandlerError> {
    db.update_group_category(
        user.user_id,
        alliance_id,
        group_category_id,
        &group_category,
    )
    .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-alliance-dashboard-table")],
    ))
}
