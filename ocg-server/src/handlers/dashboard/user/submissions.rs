//! HTTP handlers for user CFS submissions.

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
    handlers::error::HandlerError,
    router::serde_qs_config,
    templates::{dashboard::user::submissions, pagination, pagination::NavigationLinks},
};

// Pages handlers.

/// Returns the submissions list page for the user dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Fetch submissions
    let filters: submissions::CfsSubmissionsFilters =
        serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
    let results = db.list_user_cfs_submissions(user.user_id, &filters).await?;

    // Prepare template
    let navigation_links = NavigationLinks::from_filters(
        &filters,
        results.total,
        "/dashboard/user?tab=submissions",
        "/dashboard/user/submissions",
    )?;
    let template = submissions::ListPage {
        submissions: results.submissions,
        navigation_links,
        total: results.total,
        limit: filters.limit,
        offset: filters.offset,
    };

    // Prepare response headers
    let url = pagination::build_url("/dashboard/user?tab=submissions", &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

// Actions handlers.

/// Resubmits a CFS submission for the authenticated user.
#[instrument(skip_all, err)]
pub(crate) async fn resubmit(
    auth_session: AuthSession,
    messages: Messages,
    State(db): State<DynDB>,
    Path(cfs_submission_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Resubmit CFS submission
    db.resubmit_cfs_submission(user.user_id, cfs_submission_id).await?;
    messages.success("Submission resubmitted.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Withdraws a CFS submission for the authenticated user.
#[instrument(skip_all, err)]
pub(crate) async fn withdraw(
    auth_session: AuthSession,
    messages: Messages,
    State(db): State<DynDB>,
    Path(cfs_submission_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Withdraw CFS submission
    db.withdraw_cfs_submission(user.user_id, cfs_submission_id).await?;
    messages.success("Submission withdrawn.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}
