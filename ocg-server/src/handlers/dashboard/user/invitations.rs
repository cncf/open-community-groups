//! HTTP handlers to manage invitations in the user dashboard.

use askama::Template;
use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::{Html, IntoResponse},
};
use axum_messages::Messages;
use tower_sessions::Session;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    config::PaymentsConfig,
    db::DynDB,
    handlers::{
        auth::{SELECTED_COMMUNITY_ID_KEY, select_first_community_and_group},
        error::HandlerError,
        extractors::CurrentUser,
    },
    templates::dashboard::user::invitations,
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Returns the invitations list page for the user dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare list page content
    let template = prepare_list_page(&db, user.user_id).await?;

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Accepts a pending community team invitation.
#[instrument(skip_all, err)]
pub(crate) async fn accept_community_team_invitation(
    CurrentUser(user): CurrentUser,
    messages: Messages,
    session: Session,
    State(db): State<DynDB>,
    Path(community_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Accept community team invitation
    db.accept_community_team_invitation(user.user_id, community_id)
        .await?;
    messages.success("Team invitation accepted.");

    // Select first community and group if none selected
    if session.get::<Uuid>(SELECTED_COMMUNITY_ID_KEY).await?.is_none() {
        select_first_community_and_group(&db, &session, &user.user_id).await?;
    }

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Accepts a pending group team invitation.
#[instrument(skip_all, err)]
pub(crate) async fn accept_group_team_invitation(
    CurrentUser(user): CurrentUser,
    messages: Messages,
    session: Session,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Mark invitation as accepted
    db.accept_group_team_invitation(user.user_id, group_id).await?;
    messages.success("Team invitation accepted.");

    // Select first community and group if none selected
    if session.get::<Uuid>(SELECTED_COMMUNITY_ID_KEY).await?.is_none() {
        select_first_community_and_group(&db, &session, &user.user_id).await?;
    }

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Declines an active admission offer owned by the current user.
#[instrument(skip_all, err)]
pub(crate) async fn decline_event_admission_offer(
    CurrentUser(user): CurrentUser,
    messages: Messages,
    State(db): State<DynDB>,
    State(payments_cfg): State<Option<PaymentsConfig>>,
    Path(admission_offer_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Decline the admission offer and reconcile released inventory
    db.decline_event_admission_offer(
        user.user_id,
        admission_offer_id,
        payments_cfg.as_ref().map(PaymentsConfig::provider),
    )
    .await?;
    messages.success("Event offer declined.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Rejects a pending community team invitation.
#[instrument(skip_all, err)]
pub(crate) async fn reject_community_team_invitation(
    CurrentUser(user): CurrentUser,
    messages: Messages,
    State(db): State<DynDB>,
    Path(community_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Reject the pending invitation
    db.reject_community_team_invitation(user.user_id, community_id)
        .await?;
    messages.success("Team invitation rejected.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Rejects a pending group team invitation.
#[instrument(skip_all, err)]
pub(crate) async fn reject_group_team_invitation(
    CurrentUser(user): CurrentUser,
    messages: Messages,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Reject the pending invitation
    db.reject_group_team_invitation(user.user_id, group_id).await?;
    messages.success("Team invitation rejected.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

// Helpers.

/// Prepares the invitations list page for the user dashboard.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    user_id: Uuid,
) -> Result<invitations::ListPage, HandlerError> {
    // Prepare template fetching both lists concurrently
    let (community_invitations, event_invitations, group_invitations) = tokio::try_join!(
        db.list_user_community_team_invitations(user_id),
        db.list_user_event_invitations(user_id),
        db.list_user_group_team_invitations(user_id)
    )?;

    Ok(invitations::ListPage {
        community_invitations,
        event_invitations,
        group_invitations,
    })
}
