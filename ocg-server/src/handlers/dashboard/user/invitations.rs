//! HTTP handlers for the user dashboard invitations tab.

use askama::Template;
use axum::{
    extract::State,
    http::StatusCode,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::{error::HandlerError, extractors::CommunityId},
    templates::dashboard::user::invitations,
};

// Pages handlers.

/// Returns the invitations list page for the user dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    auth_session: AuthSession,
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Prepare template
    let community_invitations = db
        .list_user_community_team_invitations(community_id, user.user_id)
        .await?;
    let template = invitations::ListPage {
        community_invitations,
    };

    Ok(Html(template.render()?).into_response())
}

// Actions handlers.

/// Accepts a pending invitation for the authenticated user.
#[instrument(skip_all, err)]
pub(crate) async fn accept(
    auth_session: AuthSession,
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Accept community team invitation.
    db.accept_community_team_invitation(community_id, user.user_id)
        .await?;

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]).into_response())
}

/// Rejects a pending invitation for the authenticated user.
#[instrument(skip_all, err)]
pub(crate) async fn reject(
    auth_session: AuthSession,
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Delete community team member.
    db.delete_community_team_member(community_id, user.user_id).await?;

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]).into_response())
}
