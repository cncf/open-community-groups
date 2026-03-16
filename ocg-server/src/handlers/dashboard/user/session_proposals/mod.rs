//! HTTP handlers for session proposals in the user dashboard.

use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use axum_messages::Messages;
use serde_json::to_value;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, ValidatedForm},
    },
    router::serde_qs_config,
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::{
        dashboard::user::session_proposals::{self, SessionProposalInput},
        notifications::SessionProposalCoSpeakerInvitation,
    },
    types::pagination::{self, NavigationLinks},
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Returns the session proposals list page for the user dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Fetch pending invitations, session proposal levels, and session proposals
    let filters: session_proposals::SessionProposalsFilters =
        serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
    let (pending_co_speaker_invitations, session_proposal_levels, session_proposals_output) = tokio::try_join!(
        db.list_user_pending_session_proposal_co_speaker_invitations(user.user_id),
        db.list_session_proposal_levels(),
        db.list_user_session_proposals(user.user_id, &filters)
    )?;

    // Prepare template
    let navigation_links = NavigationLinks::from_filters(
        &filters,
        session_proposals_output.total,
        "/dashboard/user?tab=session-proposals",
        "/dashboard/user/session-proposals",
    )?;
    let template = session_proposals::ListPage {
        current_user_id: user.user_id,
        session_proposal_levels,
        session_proposals: session_proposals_output.session_proposals,
        pending_co_speaker_invitations,
        navigation_links,
        total: session_proposals_output.total,
        limit: filters.limit,
        offset: filters.offset,
    };

    // Prepare response headers
    let url = pagination::build_url("/dashboard/user?tab=session-proposals", &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

// Actions handlers.

/// Accepts a pending co-speaker invitation.
#[instrument(skip_all, err)]
pub(crate) async fn accept_co_speaker_invitation(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(session_proposal_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Accept invitation
    db.accept_session_proposal_co_speaker_invitation(user.user_id, session_proposal_id)
        .await?;
    messages.success("Co-speaker invitation accepted.");

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-user-dashboard-content")],
    ))
}

/// Adds a session proposal for the authenticated user.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    ValidatedForm(session_proposal): ValidatedForm<SessionProposalInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Add session proposal to database
    db.add_session_proposal(user.user_id, &session_proposal).await?;

    // Notify co-speaker when invitation is created
    if let Some(co_speaker_user_id) = session_proposal.co_speaker_user_id {
        send_co_speaker_invitation_notification(
            &db,
            &notifications_manager,
            &server_cfg,
            co_speaker_user_id,
            session_proposal.title.as_str(),
            get_speaker_name(&user),
        )
        .await?;
    }

    messages.success("Session proposal added.");

    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-user-dashboard-content")],
    ))
}

/// Deletes a session proposal for the authenticated user.
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(session_proposal_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Delete session proposal from database
    db.delete_session_proposal(user.user_id, session_proposal_id).await?;
    messages.success("Session proposal deleted.");

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-user-dashboard-content")],
    ))
}

/// Rejects a pending co-speaker invitation.
#[instrument(skip_all, err)]
pub(crate) async fn reject_co_speaker_invitation(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(session_proposal_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Reject invitation
    db.reject_session_proposal_co_speaker_invitation(user.user_id, session_proposal_id)
        .await?;
    messages.success("Co-speaker invitation declined.");

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-user-dashboard-content")],
    ))
}

/// Updates a session proposal for the authenticated user.
#[instrument(skip_all, err)]
#[allow(clippy::too_many_arguments)]
pub(crate) async fn update(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    Path(session_proposal_id): Path<Uuid>,
    ValidatedForm(session_proposal): ValidatedForm<SessionProposalInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load proposal record to detect invitation target changes
    let previous_session_proposal = db
        .get_session_proposal_co_speaker_user_id(user.user_id, session_proposal_id)
        .await?;
    let Some(previous_session_proposal) = previous_session_proposal else {
        return Err(HandlerError::Database("session proposal not found".to_string()));
    };
    let previous_co_speaker_user_id = previous_session_proposal.co_speaker_user_id;

    // Update session proposal in database
    db.update_session_proposal(user.user_id, session_proposal_id, &session_proposal)
        .await?;

    // Notify new co-speaker when invitation target changed
    if let Some(co_speaker_user_id) = session_proposal.co_speaker_user_id
        && Some(co_speaker_user_id) != previous_co_speaker_user_id
    {
        send_co_speaker_invitation_notification(
            &db,
            &notifications_manager,
            &server_cfg,
            co_speaker_user_id,
            session_proposal.title.as_str(),
            get_speaker_name(&user),
        )
        .await?;
    }

    messages.success("Session proposal updated.");

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-user-dashboard-content")],
    ))
}

// Helpers.

/// Returns the display name used as session proposal speaker.
fn get_speaker_name(user: &crate::auth::User) -> &str {
    if user.name.trim().is_empty() {
        user.username.as_str()
    } else {
        user.name.as_str()
    }
}

/// Sends a co-speaker invitation notification for a session proposal.
async fn send_co_speaker_invitation_notification(
    db: &DynDB,
    notifications_manager: &DynNotificationsManager,
    server_cfg: &HttpServerConfig,
    co_speaker_user_id: Uuid,
    session_proposal_title: &str,
    speaker_name: &str,
) -> Result<(), HandlerError> {
    // Build invitation link and template data
    let site_settings = db.get_site_settings().await?;
    let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
    let link = format!("{base_url}/dashboard/user?tab=session-proposals");
    let template_data = SessionProposalCoSpeakerInvitation {
        link,
        session_proposal_title: session_proposal_title.to_string(),
        speaker_name: speaker_name.to_string(),
        theme: site_settings.theme,
    };

    // Enqueue invitation notification
    let notification = NewNotification {
        attachments: vec![],
        kind: NotificationKind::SessionProposalCoSpeakerInvitation,
        recipients: vec![co_speaker_user_id],
        template_data: Some(to_value(&template_data)?),
    };
    notifications_manager.enqueue(&notification).await?;

    Ok(())
}
