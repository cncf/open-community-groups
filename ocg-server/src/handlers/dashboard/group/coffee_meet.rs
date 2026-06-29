//! HTTP handlers for `CoffeeMeet` in the group dashboard.

use askama::Template;
use axum::{
    extract::State,
    response::{Html, IntoResponse},
};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedAllianceId, SelectedGroupId},
    },
    templates::dashboard::group::coffee_meet,
    types::permissions::GroupPermission,
};

/// Returns the `CoffeeMeet` subscribers page.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    let template = prepare_list_page(&db, alliance_id, group_id, user.user_id).await?;

    Ok(Html(template.render()?))
}

/// Prepares the group `CoffeeMeet` page.
#[instrument(skip(db), err)]
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    alliance_id: Uuid,
    group_id: Uuid,
    user_id: Uuid,
) -> Result<coffee_meet::ListPage, HandlerError> {
    let (can_manage_members, subscribers) = tokio::try_join!(
        db.user_has_group_permission(
            &alliance_id,
            &group_id,
            &user_id,
            GroupPermission::MembersWrite,
        ),
        db.list_group_coffee_meet_subscribers(group_id),
    )?;

    Ok(coffee_meet::ListPage {
        can_manage_members,
        subscribers,
    })
}
