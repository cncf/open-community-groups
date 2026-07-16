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
    auth::AuthSession,
    db::DynDB,
    handlers::{
        auth::{SELECTED_GROUP_ID_KEY, SelectedGroupPolicy, sync_selected_alliance_and_group},
        error::HandlerError,
    },
};

#[cfg(test)]
mod tests;

pub(crate) mod accelerator;
pub(crate) mod analytics;
pub(crate) mod attendees;
pub(crate) mod book_exchange;
pub(crate) mod coffee_meet;
pub(crate) mod events;
pub(crate) mod home;
pub(crate) mod intentional_dating;
pub(crate) mod invitation_requests;
pub(crate) mod logs;
pub(crate) mod members;
pub(crate) mod settings;
pub(crate) mod sponsors;
pub(crate) mod spotlights;
pub(crate) mod store;
pub(crate) mod submissions;
pub(crate) mod team;
pub(crate) mod waitlist;

/// Sets the selected alliance and auto-selects the first group in session.
#[instrument(skip_all, err)]
pub(crate) async fn select_alliance(
    auth_session: AuthSession,
    session: Session,
    State(db): State<DynDB>,
    Path(alliance_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Update the selected alliance and group in the session
    sync_selected_alliance_and_group(
        &db,
        &session,
        &user.user_id,
        alliance_id,
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
