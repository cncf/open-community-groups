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
    handlers::{
        auth::{SELECTED_COMMUNITY_ID_KEY, SELECTED_GROUP_ID_KEY},
        error::HandlerError,
    },
};

#[cfg(test)]
mod tests;

pub(crate) mod analytics;
pub(crate) mod event_categories;
pub(crate) mod group_categories;
pub(crate) mod groups;
pub(crate) mod home;
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

    // Get user's groups and find groups in the selected community
    let groups_by_community = db.list_user_groups(&user.user_id).await?;
    let community_groups = groups_by_community
        .iter()
        .find(|c| c.community.community_id == community_id);

    // Update the selected community and group in the session
    session.insert(SELECTED_COMMUNITY_ID_KEY, community_id).await?;
    if let Some(first_group_id) = community_groups.and_then(|c| c.groups.first()).map(|g| g.group_id) {
        session.insert(SELECTED_GROUP_ID_KEY, first_group_id).await?;
    } else {
        session.remove::<Uuid>(SELECTED_GROUP_ID_KEY).await?;
    }

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}
