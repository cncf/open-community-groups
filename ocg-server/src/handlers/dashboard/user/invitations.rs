//! HTTP handlers to manage invitations in the user dashboard.

use askama::Template;
use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::{Html, IntoResponse},
};
use axum_messages::Messages;
use tower_sessions::Session;
use tracing::{instrument, warn};
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        auth::{SELECTED_ALLIANCE_ID_KEY, select_first_alliance_and_group},
        error::HandlerError,
        extractors::CurrentUser,
    },
    services::notifications::{DynNotificationsManager, helpers::build_event_welcome_notification},
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

/// Accepts a pending alliance team invitation.
#[instrument(skip_all, err)]
pub(crate) async fn accept_alliance_team_invitation(
    messages: Messages,
    session: Session,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(alliance_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Accept alliance team invitation
    db.accept_alliance_team_invitation(user.user_id, alliance_id)
        .await?;
    messages.success("Team invitation accepted.");

    // Select first alliance and group if none selected
    if session.get::<Uuid>(SELECTED_ALLIANCE_ID_KEY).await?.is_none() {
        select_first_alliance_and_group(&db, &session, &user.user_id).await?;
    }

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Accepts a pending event invitation.
#[instrument(skip_all, err)]
pub(crate) async fn accept_event_attendee_invitation(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Accept event invitation
    let alliance_id = db.accept_event_attendee_invitation(user.user_id, event_id).await?;
    messages.success("Event invitation accepted.");

    // Send the normal attendee welcome notification
    let (site_settings, event) = match tokio::try_join!(
        db.get_site_settings(),
        db.get_event_summary_by_id(alliance_id, event_id)
    ) {
        Ok(context) => context,
        Err(err) => {
            warn!(error = %err, "failed to load event invitation welcome notification context");
            return Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]).into_response());
        }
    };
    match build_event_welcome_notification(&event, user.user_id, &server_cfg, &site_settings, true)
    {
        Ok(notification) => {
            if let Err(err) = notifications_manager.enqueue(&notification).await {
                warn!(error = %err, "failed to enqueue event invitation welcome notification");
            }
        }
        Err(err) => {
            warn!(error = %err, "failed to build event invitation welcome notification");
        }
    }

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]).into_response())
}

/// Accepts a pending group team invitation.
#[instrument(skip_all, err)]
pub(crate) async fn accept_group_team_invitation(
    messages: Messages,
    session: Session,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Mark invitation as accepted
    db.accept_group_team_invitation(user.user_id, group_id).await?;
    messages.success("Team invitation accepted.");

    // Select first alliance and group if none selected
    if session.get::<Uuid>(SELECTED_ALLIANCE_ID_KEY).await?.is_none() {
        select_first_alliance_and_group(&db, &session, &user.user_id).await?;
    }

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Rejects a pending alliance team invitation.
#[instrument(skip_all, err)]
pub(crate) async fn reject_alliance_team_invitation(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(alliance_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Reject the pending invitation
    db.reject_alliance_team_invitation(user.user_id, alliance_id)
        .await?;
    messages.success("Team invitation rejected.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Rejects a pending event invitation.
#[instrument(skip_all, err)]
pub(crate) async fn reject_event_attendee_invitation(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Reject the pending invitation
    db.reject_event_attendee_invitation(user.user_id, event_id).await?;
    messages.success("Event invitation rejected.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Rejects a pending group team invitation.
#[instrument(skip_all, err)]
pub(crate) async fn reject_group_team_invitation(
    messages: Messages,
    CurrentUser(user): CurrentUser,
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
    let (alliance_invitations, event_invitations, group_invitations) = tokio::try_join!(
        db.list_user_alliance_team_invitations(user_id),
        db.list_user_event_invitations(user_id),
        db.list_user_group_team_invitations(user_id)
    )?;

    Ok(invitations::ListPage {
        alliance_invitations,
        event_invitations,
        group_invitations,
    })
}
