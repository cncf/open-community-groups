//! HTTP handlers for session proposals in the user dashboard.

use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use axum_messages::Messages;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, ValidatedForm, ValidatedQuery},
    },
    services::notifications::{
        DynNotificationsManager,
        best_effort::{
            CoSpeakerInvitationNotice, enqueue_session_proposal_co_speaker_invitation_best_effort,
        },
    },
    templates::dashboard::user::session_proposals,
    types::{
        dashboard::user::session_proposals::{SessionProposalInput, SessionProposalsFilters},
        pagination::{self, NavigationLinks},
    },
};

#[cfg(test)]
mod tests;

// URLs used by the dashboard page and tab partial
const DASHBOARD_URL: &str = "/dashboard/user?tab=session-proposals";
const PARTIAL_URL: &str = "/dashboard/user/session-proposals";

// Pages handlers.

/// Returns the session proposals list page for the user dashboard.
#[instrument(skip_all)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare list page content
    let (filters, template) =
        prepare_list_page(&db, user.user_id, raw_query.as_deref().unwrap_or_default()).await?;

    // Prepare response headers
    let url = pagination::build_url(DASHBOARD_URL, &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

// Actions handlers.

/// Accepts a pending co-speaker invitation.
#[instrument(skip_all)]
pub(crate) async fn accept_co_speaker_invitation(
    CurrentUser(user): CurrentUser,
    messages: Messages,
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
#[instrument(skip_all)]
pub(crate) async fn add(
    CurrentUser(user): CurrentUser,
    messages: Messages,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    ValidatedForm(session_proposal): ValidatedForm<SessionProposalInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Add session proposal to database
    db.add_session_proposal(user.user_id, &session_proposal).await?;

    // Notify co-speaker when invitation is created
    if let Some(co_speaker_user_id) = session_proposal.co_speaker_user_id {
        enqueue_session_proposal_co_speaker_invitation_best_effort(
            db.as_ref(),
            &notifications_manager,
            &server_cfg,
            CoSpeakerInvitationNotice {
                actor_user_id: user.user_id,
                co_speaker_user_id,
                session_proposal_title: session_proposal.title.as_str(),
                speaker_name: get_speaker_name(&user),
                session_proposal_id: None,
            },
        )
        .await;
    }

    messages.success("Session proposal added.");

    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-user-dashboard-content")],
    ))
}

/// Deletes a session proposal for the authenticated user.
#[instrument(skip_all)]
pub(crate) async fn delete(
    CurrentUser(user): CurrentUser,
    messages: Messages,
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
#[instrument(skip_all)]
pub(crate) async fn reject_co_speaker_invitation(
    CurrentUser(user): CurrentUser,
    messages: Messages,
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
#[instrument(skip_all)]
#[allow(clippy::too_many_arguments)]
pub(crate) async fn update(
    CurrentUser(user): CurrentUser,
    messages: Messages,
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
        return Err(HandlerError::Rejected(
            "session proposal not found".to_string(),
        ));
    };
    let previous_co_speaker_user_id = previous_session_proposal.co_speaker_user_id;

    // Update session proposal in database
    db.update_session_proposal(user.user_id, session_proposal_id, &session_proposal)
        .await?;

    // Notify new co-speaker when invitation target changed
    if let Some(co_speaker_user_id) = session_proposal.co_speaker_user_id
        && Some(co_speaker_user_id) != previous_co_speaker_user_id
    {
        enqueue_session_proposal_co_speaker_invitation_best_effort(
            db.as_ref(),
            &notifications_manager,
            &server_cfg,
            CoSpeakerInvitationNotice {
                actor_user_id: user.user_id,
                co_speaker_user_id,
                session_proposal_title: session_proposal.title.as_str(),
                speaker_name: get_speaker_name(&user),
                session_proposal_id: Some(session_proposal_id),
            },
        )
        .await;
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

/// Prepares the session proposals list page and filters for the user dashboard.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    user_id: Uuid,
    raw_query: &str,
) -> Result<(SessionProposalsFilters, session_proposals::ListPage), HandlerError> {
    // Fetch pending invitations, session proposal levels, and session proposals
    let filters: SessionProposalsFilters = ValidatedQuery::parse(raw_query)?;
    let (pending_co_speaker_invitations, session_proposal_levels, session_proposals_output) = tokio::try_join!(
        db.list_user_pending_session_proposal_co_speaker_invitations(user_id),
        db.list_session_proposal_levels(),
        db.list_user_session_proposals(user_id, &filters)
    )?;

    // Prepare template
    let navigation_links = NavigationLinks::from_filters(
        &filters,
        session_proposals_output.total,
        DASHBOARD_URL,
        PARTIAL_URL,
    )?;
    let template = session_proposals::ListPage {
        current_user_id: user_id,
        session_proposal_levels,
        session_proposals: session_proposals_output.session_proposals,
        pending_co_speaker_invitations,
        navigation_links,
        total: session_proposals_output.total,
        offset: filters.offset,
    };

    Ok((filters, template))
}
