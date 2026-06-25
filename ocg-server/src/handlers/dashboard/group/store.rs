//! HTTP handlers for the group store dashboard.

use askama::Template;
use axum::{
    extract::{Path, State},
    http::{HeaderName, StatusCode},
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
    templates::dashboard::group::store::{self, StoreItemInput},
    types::permissions::GroupPermission,
};

const DASHBOARD_URL: &str = "/dashboard/group?tab=store";

/// Displays the group store dashboard.
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

/// Adds a store item.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    ValidatedForm(input): ValidatedForm<StoreItemInput>,
) -> Result<impl IntoResponse, HandlerError> {
    db.add_group_store_item(user.user_id, group_id, &input).await?;

    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Updates a store item.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(group_store_item_id): Path<Uuid>,
    ValidatedForm(input): ValidatedForm<StoreItemInput>,
) -> Result<impl IntoResponse, HandlerError> {
    db.update_group_store_item(user.user_id, group_id, group_store_item_id, &input)
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Deletes a store item.
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(group_store_item_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    db.delete_group_store_item(user.user_id, group_id, group_store_item_id)
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Prepares the store list template.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    alliance_id: Uuid,
    group_id: Uuid,
    user_id: Uuid,
) -> Result<store::ListPage, HandlerError> {
    let (can_manage_store, items) = tokio::try_join!(
        db.user_has_group_permission(
            &alliance_id,
            &group_id,
            &user_id,
            GroupPermission::SponsorsWrite,
        ),
        db.list_group_store_items(group_id, true),
    )?;

    Ok(store::ListPage {
        can_manage_store,
        items,
    })
}
