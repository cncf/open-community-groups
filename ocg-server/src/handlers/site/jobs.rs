//! HTTP handlers for the public jobs pages.

use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::{StatusCode, header::CACHE_CONTROL},
    response::{Html, IntoResponse},
};
use axum_messages::Messages;
use garde::Validate;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, ValidatedForm},
    },
    router::{CACHE_CONTROL_PRIVATE_NO_STORE, serde_qs_config},
    templates::{PageId, auth::User, site::jobs},
    types::{
        jobs::{JobApplicationInput, JobsFilters},
        pagination::NavigationLinks,
    },
};

const JOBS_URL: &str = "/jobs";

/// Render the public jobs listing page.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    let mut filters = parse_filters(raw_query.as_deref().unwrap_or_default())?;
    filters.include_members_only = auth_session.user.is_some();
    let output = db.search_jobs(&filters).await?;
    let site_settings = db.get_site_settings().await?;
    let navigation_links =
        NavigationLinks::from_filters(&filters, output.total, JOBS_URL, JOBS_URL)?;

    let template = jobs::Page {
        page_id: PageId::SiteJobs,
        path: JOBS_URL.to_string(),
        site_settings,
        user: User::from_session(auth_session).await?,
        filters,
        jobs: output.jobs,
        total: output.total,
        navigation_links,
    };

    Ok((
        [(CACHE_CONTROL, CACHE_CONTROL_PRIVATE_NO_STORE)],
        Html(template.render()?),
    ))
}

/// Render a public job details page.
#[instrument(skip_all, err)]
pub(crate) async fn details(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    Path(slug): Path<String>,
) -> Result<impl IntoResponse, HandlerError> {
    let viewer_user_id = auth_session.user.as_ref().map(|user| user.user_id);
    let job = db.get_job_by_slug(&slug, viewer_user_id).await?;
    let site_settings = db.get_site_settings().await?;

    let template = jobs::DetailsPage {
        page_id: PageId::SiteJobs,
        path: format!("{JOBS_URL}/{slug}"),
        site_settings,
        user: User::from_session(auth_session).await?,
        job,
    };

    Ok((
        [(CACHE_CONTROL, CACHE_CONTROL_PRIVATE_NO_STORE)],
        Html(template.render()?),
    ))
}

/// Apply to a job as the current user.
#[instrument(skip_all, err)]
pub(crate) async fn apply(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(job_id): Path<Uuid>,
    ValidatedForm(input): ValidatedForm<JobApplicationInput>,
) -> Result<impl IntoResponse, HandlerError> {
    db.add_job_application(user.user_id, job_id, &input).await?;
    messages.success("Application saved.");

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-job-details")],
    ))
}

fn parse_filters(raw_query: &str) -> Result<JobsFilters, HandlerError> {
    let filters: JobsFilters = if raw_query.is_empty() {
        JobsFilters::default()
    } else {
        serde_qs_config().deserialize_str(raw_query)?
    };
    filters.validate()?;
    Ok(filters)
}
