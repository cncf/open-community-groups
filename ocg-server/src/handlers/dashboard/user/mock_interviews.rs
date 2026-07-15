//! HTTP handlers for user mock interview matches.

use askama::Template;
use axum::{
    extract::{Path, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use axum_messages::Messages;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, ValidatedForm},
    },
    templates::dashboard::user::mock_interviews,
    types::mock_interviews::{
        MockInterviewParticipantFeedbackInput, MockInterviewParticipantScheduleInput,
    },
};

const DASHBOARD_URL: &str = "/dashboard/user?tab=mock-interviews";

/// Returns mock interview matches assigned to the current user.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    let template = prepare_list_page(&db, user.user_id).await?;
    let headers = [(
        HeaderName::from_static("hx-push-url"),
        DASHBOARD_URL.to_string(),
    )];

    Ok((headers, Html(template.render()?)))
}

/// Saves schedule details for one assigned match.
#[instrument(skip_all, err)]
pub(crate) async fn update_schedule(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(match_id): Path<Uuid>,
    ValidatedForm(input): ValidatedForm<MockInterviewParticipantScheduleInput>,
) -> Result<impl IntoResponse, HandlerError> {
    let updated = db
        .update_user_mock_interview_schedule(user.user_id, match_id, &input)
        .await?;

    if !updated {
        return Err(HandlerError::NotFound);
    }

    messages.success("Mock interview schedule saved.");
    Ok((
        StatusCode::SEE_OTHER,
        [("Location", DASHBOARD_URL.to_string())],
    ))
}

/// Saves feedback for the current user's role in one assigned match.
#[instrument(skip_all, err)]
pub(crate) async fn update_feedback(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(match_id): Path<Uuid>,
    ValidatedForm(input): ValidatedForm<MockInterviewParticipantFeedbackInput>,
) -> Result<impl IntoResponse, HandlerError> {
    let updated = db
        .update_user_mock_interview_feedback(user.user_id, match_id, &input)
        .await?;

    if !updated {
        return Err(HandlerError::NotFound);
    }

    messages.success("Mock interview feedback saved.");
    Ok((
        StatusCode::SEE_OTHER,
        [("Location", DASHBOARD_URL.to_string())],
    ))
}

/// Prepares the mock interviews list page.
#[instrument(skip(db), err)]
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    user_id: Uuid,
) -> Result<mock_interviews::ListPage, HandlerError> {
    let (requests, matches) = tokio::try_join!(
        db.list_user_mock_interview_requests(user_id),
        db.list_user_mock_interview_matches(user_id),
    )?;

    Ok(mock_interviews::ListPage {
        requests,
        matches,
    })
}
