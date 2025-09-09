//! HTTP handlers to manage invitations in the user dashboard.

use askama::Template;
use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::{Html, IntoResponse},
};
use axum_messages::Messages;
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

    // Prepare template fetching both lists concurrently
    let (community_invitations, group_invitations) = tokio::try_join!(
        db.list_user_community_team_invitations(community_id, user.user_id),
        db.list_user_group_team_invitations(community_id, user.user_id)
    )?;
    let template = invitations::ListPage {
        community_invitations,
        group_invitations,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Accepts a pending community team invitation.
#[instrument(skip_all, err)]
pub(crate) async fn accept_community_team_invitation(
    auth_session: AuthSession,
    messages: Messages,
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Accept community team invitation.
    db.accept_community_team_invitation(community_id, user.user_id)
        .await?;
    messages.success("Team invitation accepted.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Accepts a pending group team invitation.
#[instrument(skip_all, err)]
pub(crate) async fn accept_group_team_invitation(
    auth_session: AuthSession,
    messages: Messages,
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
    Path(group_id): Path<uuid::Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Mark invitation as accepted
    db.accept_group_team_invitation(community_id, group_id, user.user_id)
        .await?;
    messages.success("Team invitation accepted.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Rejects a pending community team invitation.
#[instrument(skip_all, err)]
pub(crate) async fn reject_community_team_invitation(
    auth_session: AuthSession,
    messages: Messages,
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Delete community team member.
    db.delete_community_team_member(community_id, user.user_id).await?;
    messages.success("Team invitation rejected.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Rejects a pending group team invitation.
#[instrument(skip_all, err)]
pub(crate) async fn reject_group_team_invitation(
    auth_session: AuthSession,
    messages: Messages,
    State(db): State<DynDB>,
    Path(group_id): Path<uuid::Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Delete group team member from database
    db.delete_group_team_member(group_id, user.user_id).await?;
    messages.success("Team invitation rejected.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}
