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
    db::DynDB,
    handlers::{
        auth::{SelectedGroupPolicy, sync_selected_community_and_group},
        error::HandlerError,
        extractors::CurrentUser,
    },
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
        SelectedGroupPolicy::Optional,
    )
    .await?;

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}
