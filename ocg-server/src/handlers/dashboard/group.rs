//! HTTP handlers for the group dashboard.

use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
};
use tower_sessions::Session;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        auth::{SELECTED_GROUP_ID_KEY, SelectedGroupPolicy, sync_selected_community_and_group},
        error::HandlerError,
        extractors::CurrentUser,
    },
};

#[cfg(test)]
mod tests;

pub(crate) mod analytics;
pub(crate) mod attendees;
pub(crate) mod events;
pub(crate) mod home;
pub(crate) mod invitation_requests;
pub(crate) mod logs;
pub(crate) mod members;
pub(crate) mod settings;
pub(crate) mod sponsors;
pub(crate) mod submissions;
pub(crate) mod team;
pub(crate) mod waitlist;

/// Sets the selected community and auto-selects the first group in session.
#[instrument(skip_all, err)]
pub(crate) async fn select_community(
    CurrentUser(user): CurrentUser,
    session: Session,
    State(db): State<DynDB>,
    Path(community_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Update the selected community and group in the session
    sync_selected_community_and_group(
        &db,
        &session,
        &user.user_id,
        community_id,
        SelectedGroupPolicy::Required,
    )
    .await?;

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Sets the selected group in the session for the current user.
#[instrument(skip_all, err)]
pub(crate) async fn select_group(
    session: Session,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Update the selected group in the session
    session.insert(SELECTED_GROUP_ID_KEY, group_id).await?;

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}
