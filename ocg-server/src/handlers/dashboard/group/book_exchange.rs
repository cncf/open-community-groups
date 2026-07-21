//! HTTP handlers for group book exchange.

use askama::Template;
use axum::{
    extract::State,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{SelectedAllianceId, SelectedGroupId},
    },
    templates::dashboard::group::book_exchange,
    types::permissions::GroupPermission,
};

#[cfg(test)]
mod tests;

/// Displays group book exchange member lists for opted-in members.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    auth_session: AuthSession,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    let user = auth_session.user.as_ref().expect("user to be logged in");
    let can_manage_book_exchange = db
        .user_has_group_permission(
            &alliance_id,
            &group_id,
            &user.user_id,
            GroupPermission::SettingsWrite,
        )
        .await?;
    let members = db.list_book_exchange_members(alliance_id, Some(group_id)).await?;
    let template = book_exchange::ListPage {
        can_manage_book_exchange,
        members,
    };

    Ok(Html(template.render()?))
}
