//! HTTP handlers for the jobs dashboard.

use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::StatusCode,
    response::{Html, IntoResponse},
};
use axum_messages::Messages;
use garde::Validate;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, ValidatedForm},
    },
    router::serde_qs_config,
    templates::{PageId, auth::User, dashboard::jobs::Page},
    types::{
        jobs::{DashboardJobsFilters, JobInput},
        pagination::NavigationLinks,
    },
};

const DASHBOARD_JOBS_URL: &str = "/dashboard/jobs";

/// Render the jobs dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    auth_session: crate::auth::AuthSession,
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    let filters = parse_filters(raw_query.as_deref().unwrap_or_default())?;
    let output = db.list_user_jobs(user.user_id, &filters).await?;
    let site_settings = db.get_site_settings().await?;
    let navigation_links = NavigationLinks::from_filters(
        &filters,
        output.total,
        DASHBOARD_JOBS_URL,
        DASHBOARD_JOBS_URL,
    )?;

    let template = Page {
        messages: messages.into_iter().collect(),
        page_id: PageId::JobsDashboard,
        path: DASHBOARD_JOBS_URL.to_string(),
        site_settings,
        user: User::from_session(auth_session).await?,
        filters,
        jobs: output.jobs,
        total: output.total,
        navigation_links,
    };

    Ok(Html(template.render()?))
}

/// Add a job.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    ValidatedForm(input): ValidatedForm<JobInput>,
) -> Result<impl IntoResponse, HandlerError> {
    db.add_job(user.user_id, &input).await?;
    messages.success("Job posted.");
    Ok((StatusCode::SEE_OTHER, [("Location", DASHBOARD_JOBS_URL)]))
}

/// Update a job.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(job_id): Path<Uuid>,
    ValidatedForm(input): ValidatedForm<JobInput>,
) -> Result<impl IntoResponse, HandlerError> {
    db.update_job(user.user_id, job_id, &input).await?;
    messages.success("Job updated.");
    Ok((StatusCode::SEE_OTHER, [("Location", DASHBOARD_JOBS_URL)]))
}

/// Delete a job.
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(job_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    db.delete_job(user.user_id, job_id).await?;
    messages.success("Job deleted.");
    Ok((StatusCode::SEE_OTHER, [("Location", DASHBOARD_JOBS_URL)]))
}

/// Publish a job.
#[instrument(skip_all, err)]
pub(crate) async fn publish(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(job_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    db.update_job_published(user.user_id, job_id, true).await?;
    messages.success("Job published.");
    Ok((StatusCode::SEE_OTHER, [("Location", DASHBOARD_JOBS_URL)]))
}

/// Unpublish a job.
#[instrument(skip_all, err)]
pub(crate) async fn unpublish(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(job_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    db.update_job_published(user.user_id, job_id, false).await?;
    messages.success("Job unpublished.");
    Ok((StatusCode::SEE_OTHER, [("Location", DASHBOARD_JOBS_URL)]))
}

fn parse_filters(raw_query: &str) -> Result<DashboardJobsFilters, HandlerError> {
    let filters: DashboardJobsFilters = if raw_query.is_empty() {
        DashboardJobsFilters::default()
    } else {
        serde_qs_config().deserialize_str(raw_query)?
    };
    filters.validate()?;
    Ok(filters)
}
