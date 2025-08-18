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
    handlers::{auth::SELECTED_GROUP_ID_KEY, error::HandlerError},
};

pub(crate) mod events;
pub(crate) mod home;
pub(crate) mod settings;

/// Sets the selected group in the session for the current user.
#[instrument(skip_all, err)]
pub(crate) async fn select_group(
    session: Session,
    State(_db): State<DynDB>,
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
