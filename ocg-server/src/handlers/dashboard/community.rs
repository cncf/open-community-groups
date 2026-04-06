//! HTTP handlers for the community dashboard.

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
    handlers::{auth::sync_selected_community_and_group, error::HandlerError},
};

#[cfg(test)]
mod tests;

pub(crate) mod analytics;
pub(crate) mod event_categories;
pub(crate) mod group_categories;
pub(crate) mod groups;
pub(crate) mod home;
pub(crate) mod logs;
pub(crate) mod regions;
pub(crate) mod settings;
pub(crate) mod team;

/// Sets the selected community and auto-selects the first group in session.
#[instrument(skip_all, err)]
pub(crate) async fn select_community(
    auth_session: AuthSession,
    session: Session,
    State(db): State<DynDB>,
    Path(community_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Update the selected community and group in the session
    sync_selected_community_and_group(&db, &session, &user.user_id, community_id).await?;

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}
