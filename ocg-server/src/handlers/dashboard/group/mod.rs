//! HTTP handlers for the group dashboard.

use axum::{extract::Path, http::StatusCode, response::IntoResponse};
use tower_sessions::Session;
use tracing::instrument;
use uuid::Uuid;

use crate::handlers::{auth::SELECTED_GROUP_ID_KEY, error::HandlerError};

pub(crate) mod events;
pub(crate) mod home;
pub(crate) mod settings;
pub(crate) mod team;

/// Sets the selected group in the session for the current user.
#[instrument(skip_all, err)]
pub(crate) async fn select_group(
    session: Session,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Update the selected group in the session
    session.insert(SELECTED_GROUP_ID_KEY, group_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Location", r#"{"path":"/dashboard/group", "target":"body"}"#)],
    )
        .into_response())
}
