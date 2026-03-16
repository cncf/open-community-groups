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
    db::DynDB,
    handlers::{error::HandlerError, extractors::CurrentUser},
    router::serde_qs_config,
    templates::dashboard::user::submissions,
    types::pagination::{self, NavigationLinks},
};

#[cfg(test)]
mod tests;

// URLs used by the dashboard page and tab partial
const DASHBOARD_URL: &str = "/dashboard/user?tab=submissions";
const PARTIAL_URL: &str = "/dashboard/user/submissions";

// Pages handlers.

/// Returns the submissions list page for the user dashboard.
#[instrument(skip_all, err)]
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

/// Resubmits a CFS submission for the authenticated user.
#[instrument(skip_all, err)]
pub(crate) async fn resubmit(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(cfs_submission_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Resubmit CFS submission
    db.resubmit_cfs_submission(user.user_id, cfs_submission_id).await?;
    messages.success("Submission resubmitted.");

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-user-dashboard-content")],
    ))
}

/// Withdraws a CFS submission for the authenticated user.
#[instrument(skip_all, err)]
pub(crate) async fn withdraw(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(cfs_submission_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Withdraw CFS submission
    db.withdraw_cfs_submission(user.user_id, cfs_submission_id).await?;
    messages.success("Submission withdrawn.");

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-user-dashboard-content")],
    ))
}

// Helpers.

/// Prepares the submissions list page and filters for the user dashboard.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    user_id: Uuid,
    raw_query: &str,
) -> Result<(submissions::CfsSubmissionsFilters, submissions::ListPage), HandlerError> {
    // Fetch submissions
    let filters: submissions::CfsSubmissionsFilters = serde_qs_config().deserialize_str(raw_query)?;
    let results = db.list_user_cfs_submissions(user_id, &filters).await?;

    // Prepare template
    let navigation_links =
        NavigationLinks::from_filters(&filters, results.total, DASHBOARD_URL, PARTIAL_URL)?;
    let template = submissions::ListPage {
        submissions: results.submissions,
        navigation_links,
        total: results.total,
        limit: filters.limit,
        offset: filters.offset,
    };

    Ok((filters, template))
}
