//! HTTP handlers for group member spotlights.

use askama::Template;
use axum::{
    extract::{Path, State},
    http::HeaderName,
    response::{Html, IntoResponse},
};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedAllianceId, SelectedGroupId, ValidatedForm},
    },
    templates::dashboard::group::{
        members::GroupMembersFilters,
        spotlights::{self, SpotlightInput},
    },
    types::permissions::GroupPermission,
};

const DASHBOARD_URL: &str = "/dashboard/group?tab=spotlights";

/// Displays group member spotlights.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    let template = prepare_list_page(&db, alliance_id, group_id, user.user_id).await?;
    let headers = [(
        HeaderName::from_static("hx-push-url"),
        DASHBOARD_URL.to_string(),
    )];

    Ok((headers, Html(template.render()?)))
}

/// Adds a group member spotlight.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    ValidatedForm(input): ValidatedForm<SpotlightInput>,
) -> Result<impl IntoResponse, HandlerError> {
    db.add_group_member_spotlight(user.user_id, group_id, &input).await?;
    let template = prepare_list_page(&db, alliance_id, group_id, user.user_id).await?;

    Ok(Html(template.render()?))
}

/// Updates a group member spotlight.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(spotlight_id): Path<Uuid>,
    ValidatedForm(input): ValidatedForm<SpotlightInput>,
) -> Result<impl IntoResponse, HandlerError> {
    db.update_group_member_spotlight(user.user_id, group_id, spotlight_id, &input)
        .await?;
    let template = prepare_list_page(&db, alliance_id, group_id, user.user_id).await?;

    Ok(Html(template.render()?))
}

/// Deletes a group member spotlight.
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(spotlight_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    db.delete_group_member_spotlight(user.user_id, group_id, spotlight_id)
        .await?;
    let template = prepare_list_page(&db, alliance_id, group_id, user.user_id).await?;

    Ok(Html(template.render()?))
}

/// Prepares the spotlights list template.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    alliance_id: Uuid,
    group_id: Uuid,
    user_id: Uuid,
) -> Result<spotlights::ListPage, HandlerError> {
    let member_filters = GroupMembersFilters {
        limit: Some(500),
        offset: Some(0),
        query: None,
    };
    let (can_manage_spotlights, spotlights, members) = tokio::try_join!(
        db.user_has_group_permission(
            &alliance_id,
            &group_id,
            &user_id,
            GroupPermission::MembersWrite,
        ),
        db.list_group_member_spotlights(group_id, true),
        db.list_group_members(group_id, &member_filters),
    )?;

    Ok(spotlights::ListPage {
        can_manage_spotlights,
        spotlights,
        members: members.members,
    })
}
