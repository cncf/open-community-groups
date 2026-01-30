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
    auth::AuthSession,
    db::DynDB,
    handlers::{error::HandlerError, extractors::ValidatedForm},
    router::serde_qs_config,
    templates::{
        dashboard::user::session_proposals::{self, SessionProposalInput},
        pagination,
        pagination::NavigationLinks,
    },
};

// Pages handlers.

/// Returns the session proposals list page for the user dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Fetch session proposals and levels
    let filters: session_proposals::SessionProposalsFilters =
        serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
    let (session_proposal_levels, session_proposals_output) = tokio::try_join!(
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
        session_proposal_levels,
        session_proposals: session_proposals_output.session_proposals,
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

/// Adds a session proposal for the authenticated user.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    auth_session: AuthSession,
    messages: Messages,
    State(db): State<DynDB>,
    ValidatedForm(session_proposal): ValidatedForm<SessionProposalInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Add session proposal to database
    db.add_session_proposal(user.user_id, &session_proposal).await?;
    messages.success("Session proposal added.");

    Ok((StatusCode::CREATED, [("HX-Trigger", "refresh-body")]))
}

/// Deletes a session proposal for the authenticated user.
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    auth_session: AuthSession,
    messages: Messages,
    State(db): State<DynDB>,
    Path(session_proposal_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Delete session proposal from database
    db.delete_session_proposal(user.user_id, session_proposal_id).await?;
    messages.success("Session proposal deleted.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Updates a session proposal for the authenticated user.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    auth_session: AuthSession,
    messages: Messages,
    State(db): State<DynDB>,
    Path(session_proposal_id): Path<Uuid>,
    ValidatedForm(session_proposal): ValidatedForm<SessionProposalInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Update session proposal in database
    db.update_session_proposal(user.user_id, session_proposal_id, &session_proposal)
        .await?;
    messages.success("Session proposal updated.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}
