//! HTTP handlers for the jobs dashboard.

use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::StatusCode,
    response::{Html, IntoResponse},
};
use axum_messages::Messages;
use garde::Validate;
use tracing::{instrument, warn};
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
        PageId,
        auth::User,
        dashboard::jobs::{MockInterviewsPage, Page},
        notifications::MockInterviewMatched,
    },
    types::{
        jobs::{DashboardJobsFilters, JobInput},
        mock_interviews::{
            MockInterviewFeedbackInput, MockInterviewFilters, MockInterviewMatchInput,
            MockInterviewMatchNotificationContext, option_label,
        },
        pagination::NavigationLinks,
    },
};

const DASHBOARD_JOBS_URL: &str = "/dashboard/jobs";
const DASHBOARD_MOCK_INTERVIEWS_URL: &str = "/dashboard/jobs/mock-interviews";

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

/// Render the mock interviews dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn mock_interviews_page(
    auth_session: crate::auth::AuthSession,
    messages: Messages,
    CurrentUser(_user): CurrentUser,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    let filters = parse_mock_interview_filters(raw_query.as_deref().unwrap_or_default())?;
    let output = db.get_mock_interview_dashboard(&filters).await?;
    let site_settings = db.get_site_settings().await?;
    let navigation_links = NavigationLinks::from_filters(
        &filters,
        output.total,
        DASHBOARD_MOCK_INTERVIEWS_URL,
        DASHBOARD_MOCK_INTERVIEWS_URL,
    )?;

    let template = MockInterviewsPage::new(
        messages.into_iter().collect(),
        DASHBOARD_MOCK_INTERVIEWS_URL.to_string(),
        site_settings,
        User::from_session(auth_session).await?,
        filters,
        output,
        navigation_links,
    );

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

/// Create or update a mock interview match and notify participants.
#[instrument(skip_all, err)]
pub(crate) async fn upsert_mock_interview_match(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    State(notifications_manager): State<DynNotificationsManager>,
    Path(request_id): Path<Uuid>,
    ValidatedForm(input): ValidatedForm<MockInterviewMatchInput>,
) -> Result<impl IntoResponse, HandlerError> {
    let match_id = db
        .upsert_mock_interview_match(user.user_id, request_id, &input)
        .await?;
    let context = db
        .get_mock_interview_match_notification_context(match_id)
        .await?
        .ok_or(HandlerError::NotFound)?;
    let site_settings = db.get_site_settings().await?;
    enqueue_mock_interview_match_notifications(
        &notifications_manager,
        &server_cfg,
        &site_settings,
        &context,
    )
    .await;

    messages.success("Mock interview match saved and participants notified.");
    Ok((
        StatusCode::SEE_OTHER,
        [("Location", DASHBOARD_MOCK_INTERVIEWS_URL)],
    ))
}

/// Update mock interview feedback.
#[instrument(skip_all, err)]
pub(crate) async fn update_mock_interview_feedback(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(match_id): Path<Uuid>,
    ValidatedForm(input): ValidatedForm<MockInterviewFeedbackInput>,
) -> Result<impl IntoResponse, HandlerError> {
    let updated = db
        .update_mock_interview_feedback(user.user_id, match_id, &input)
        .await?;
    if !updated {
        return Err(HandlerError::NotFound);
    }

    messages.success("Mock interview feedback saved.");
    Ok((
        StatusCode::SEE_OTHER,
        [("Location", DASHBOARD_MOCK_INTERVIEWS_URL)],
    ))
}

async fn enqueue_mock_interview_match_notifications(
    notifications_manager: &DynNotificationsManager,
    server_cfg: &HttpServerConfig,
    site_settings: &crate::types::site::SiteSettings,
    context: &MockInterviewMatchNotificationContext,
) {
    let Some(host_user_id) = context.interviewer_user_id else {
        warn!(
            match_id = %context.mock_interview_match_id,
            "mock interview match notification skipped because interviewer is missing"
        );
        return;
    };
    let Some(candidate_user_id) = context.interviewee_user_id else {
        warn!(
            match_id = %context.mock_interview_match_id,
            "mock interview match notification skipped because interviewee is missing"
        );
        return;
    };

    let dashboard_link = format!(
        "{}/dashboard/user?tab=mock-interviews",
        server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url)
    );
    let interview_type = option_label(&context.interview_type).to_string();
    let notifications = [
        (
            host_user_id,
            MockInterviewMatched {
                dashboard_link: dashboard_link.clone(),
                interview_type: interview_type.clone(),
                recipient_role: "interviewer".to_string(),
                partner_name: context.interviewee_label(),
                partner_username: context.interviewee_username.clone(),
                theme: site_settings.theme.clone(),
            },
        ),
        (
            candidate_user_id,
            MockInterviewMatched {
                dashboard_link,
                interview_type,
                recipient_role: "interviewee".to_string(),
                partner_name: context.interviewer_label(),
                partner_username: context.interviewer_username.clone(),
                theme: site_settings.theme.clone(),
            },
        ),
    ];

    for (recipient, template_data) in notifications {
        let notification = NewNotification {
            attachments: vec![],
            kind: NotificationKind::MockInterviewMatched,
            recipients: vec![recipient],
            template_data: match serde_json::to_value(&template_data) {
                Ok(value) => Some(value),
                Err(err) => {
                    warn!(error = %err, "failed to serialize mock interview match notification");
                    continue;
                }
            },
        };
        if let Err(err) = notifications_manager.enqueue(&notification).await {
            warn!(
                error = %err,
                recipient = %recipient,
                "failed to enqueue mock interview match notification"
            );
        }
    }
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

fn parse_mock_interview_filters(raw_query: &str) -> Result<MockInterviewFilters, HandlerError> {
    let filters: MockInterviewFilters = if raw_query.is_empty() {
        MockInterviewFilters::default()
    } else {
        serde_qs_config().deserialize_str(raw_query)?
    };
    filters.validate()?;
    Ok(filters)
}
