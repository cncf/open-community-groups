//! HTTP handlers for managing event categories in the community dashboard.

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
    templates::dashboard::community::event_categories::{self, EventCategoryInput},
    types::permissions::CommunityPermission,
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Displays the list of event categories for the selected community.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (can_manage_taxonomy, categories) = tokio::try_join!(
        db.user_has_community_permission(&community_id, &user.user_id, CommunityPermission::TaxonomyWrite),
        db.list_event_categories(community_id)
    )?;
    let template = event_categories::ListPage {
        can_manage_taxonomy,
        categories,
    };

    Ok(Html(template.render()?))
}

/// Displays the form to create a new event category.
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
    let template = event_categories::AddPage { can_manage_taxonomy };

    Ok(Html(template.render()?))
}

/// Displays the form to update an existing event category.
#[instrument(skip_all, err)]
pub(crate) async fn update_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    Path(event_category_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (can_manage_taxonomy, categories) = tokio::try_join!(
        db.user_has_community_permission(&community_id, &user.user_id, CommunityPermission::TaxonomyWrite),
        db.list_event_categories(community_id)
    )?;
    let Some(category) = categories
        .into_iter()
        .find(|category| category.event_category_id == event_category_id)
    else {
        return Err(HandlerError::Database("event category not found".to_string()));
    };
    let template = event_categories::UpdatePage {
        can_manage_taxonomy,
        category,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Adds a new event category to the selected community.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    ValidatedForm(event_category): ValidatedForm<EventCategoryInput>,
) -> Result<impl IntoResponse, HandlerError> {
    db.add_event_category(user.user_id, community_id, &event_category)
        .await?;

    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-community-dashboard-table")],
    ))
}

/// Deletes an event category from the selected community.
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    Path(event_category_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    db.delete_event_category(user.user_id, community_id, event_category_id)
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-community-dashboard-table")],
    ))
}

/// Updates an event category in the selected community.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    Path(event_category_id): Path<Uuid>,
    ValidatedForm(event_category): ValidatedForm<EventCategoryInput>,
) -> Result<impl IntoResponse, HandlerError> {
    db.update_event_category(user.user_id, community_id, event_category_id, &event_category)
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-community-dashboard-table")],
    ))
}
