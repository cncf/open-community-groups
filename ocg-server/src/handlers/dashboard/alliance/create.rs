//! HTTP handlers for creating alliances.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::State,
    http::StatusCode,
    response::{Html, IntoResponse},
};
use tower_sessions::Session;
use tracing::instrument;

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::{
        auth::{SelectedGroupPolicy, sync_selected_alliance_and_group},
        error::HandlerError,
        extractors::{CurrentUser, ValidatedForm},
    },
    templates::dashboard::alliance::create::{self, AllianceCreate},
};

/// Displays the form to create a new alliance.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    CurrentUser(user): CurrentUser,
) -> Result<impl IntoResponse, HandlerError> {
    if !user.platform_admin {
        return Err(HandlerError::Forbidden);
    }

    Ok(Html(create::Page.render()?))
}

/// Creates a new alliance and selects it for the creator.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    auth_session: AuthSession,
    session: Session,
    State(db): State<DynDB>,
    ValidatedForm(alliance): ValidatedForm<AllianceCreate>,
) -> Result<impl IntoResponse, HandlerError> {
    let user = auth_session.user.expect("user to be logged in");
    if !user.platform_admin {
        return Err(HandlerError::Forbidden);
    }

    let alliance_id = db.add_alliance(user.user_id, &alliance).await?;
    sync_selected_alliance_and_group(
        &db,
        &session,
        &user.user_id,
        alliance_id,
        SelectedGroupPolicy::Optional,
    )
    .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [(
            "HX-Location",
            r#"{"path":"/dashboard/alliance?tab=settings", "target":"body"}"#,
        )],
    )
        .into_response())
}
