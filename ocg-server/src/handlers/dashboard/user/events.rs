//! HTTP handlers for user upcoming events.

use std::collections::HashMap;

use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, ValidatedForm, ValidatedQuery},
    },
    services::enrollment::{DynEnrollmentManager, LeaveEventInput},
    templates::dashboard::user::events,
    types::{
        dashboard::{
            self,
            user::events::{EventSurveyAnswersForm, UserEventSurveysFilters, UserEventsFilters},
        },
        event::EventEnrollmentStatus,
        pagination::{self, NavigationLinks},
        questionnaire::RequiredQuestionnaireAnswersForm,
    },
};

#[cfg(test)]
mod tests;

/// URL used by the full dashboard page.
const DASHBOARD_URL: &str = "/dashboard/user?tab=events";

/// Warning shown when the requested survey can't be answered.
const EVENT_SURVEY_NOT_AVAILABLE_WARNING: &str = "This survey is closed or isn't available to you.";

/// URL used by the events tab partial.
const PARTIAL_URL: &str = "/dashboard/user/events";

// Pages handlers.

/// Returns the upcoming events list page for the user dashboard.
#[instrument(skip_all)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare list page content
    let (filters, template) = prepare_list_page(
        &db,
        user.user_id,
        raw_query.as_deref().unwrap_or_default(),
        None,
    )
    .await?;

    // Prepare response headers
    let url = pagination::build_url(DASHBOARD_URL, &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

/// Returns the modal content of an open survey the user can answer.
#[instrument(skip_all)]
pub(crate) async fn survey_modal(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(event_survey_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the survey as the current user answers it
    let survey = db
        .get_user_event_survey(event_survey_id, user.user_id)
        .await?
        .ok_or(HandlerError::NotFound)?;

    // Prepare template
    let template = events::SurveyModal { survey };

    Ok(Html(template.render()?))
}

/// Returns a page of the surveys panel, requested by its "Show more" button.
#[instrument(skip_all)]
pub(crate) async fn surveys_page(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    ValidatedQuery(filters): ValidatedQuery<UserEventSurveysFilters>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the requested page of surveys
    let surveys = db.list_user_event_surveys(user.user_id, &filters).await?;

    // Prepare template
    let template = events::SurveysPage {
        surveys,

        offset: filters.offset,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Cancels the current user's event attendance from the dashboard.
#[instrument(skip_all)]
pub(crate) async fn cancel_attendance(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(enrollment_manager): State<DynEnrollmentManager>,
    Path((community_name, event_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve the community from the dashboard route
    let community_id = db
        .get_community_id_by_name(&community_name)
        .await?
        .ok_or(HandlerError::NotFound)?;

    // Validate the row still represents cancelable attendance
    let enrollment = db.get_event_enrollment(community_id, event_id, user.user_id).await?;
    if enrollment.status != EventEnrollmentStatus::Attendee {
        return Err(HandlerError::Rejected(
            "only attendee attendance can be canceled from My Events".to_string(),
        ));
    }

    // Cancel attendance with its required notifications
    enrollment_manager
        .leave_event(&LeaveEventInput {
            community_id,
            event_id,
            user_id: user.user_id,
        })
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-user-dashboard-content")],
    ))
}

/// Submits registration question answers from the user dashboard.
#[instrument(skip_all)]
pub(crate) async fn submit_registration_answers(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path((community_name, event_id)): Path<(String, Uuid)>,
    ValidatedForm(input): ValidatedForm<RequiredQuestionnaireAnswersForm>,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve the community from the dashboard route
    let community_id = db
        .get_community_id_by_name(&community_name)
        .await?
        .ok_or(HandlerError::NotFound)?;

    // Persist answers; checkout retains ownership of pending confirmation
    db.submit_event_registration_answers(
        user.user_id,
        community_id,
        event_id,
        &input.registration_answers,
    )
    .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-user-dashboard-content")],
    )
        .into_response())
}

/// Stores the current user's answers to an open event survey.
#[instrument(skip_all)]
pub(crate) async fn submit_survey_response(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(event_survey_id): Path<Uuid>,
    ValidatedForm(form): ValidatedForm<EventSurveyAnswersForm>,
) -> Result<impl IntoResponse, HandlerError> {
    // Store the answers given to the survey revision the user saw
    db.submit_event_survey_response(event_survey_id, user.user_id, form.revision, &form.answers)
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-user-dashboard-content")],
    ))
}

// Helpers.

/// Prepares the events list page and filters for the user dashboard.
///
/// A requested survey opens on load when the user can answer it; otherwise
/// the page warns that it isn't available.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    user_id: Uuid,
    raw_query: &str,
    event_survey_id: Option<Uuid>,
) -> Result<(UserEventsFilters, events::ListPage), HandlerError> {
    // Fetch upcoming events, the first page of the surveys panel and the
    // requested survey
    let filters: UserEventsFilters = ValidatedQuery::parse(raw_query)?;
    let surveys_filters = UserEventSurveysFilters {
        limit: dashboard::default_user_event_surveys_limit(),
        offset: dashboard::default_offset(),
    };
    let (results, surveys, survey) = tokio::try_join!(
        db.list_user_events(user_id, &filters),
        db.list_user_event_surveys(user_id, &surveys_filters),
        async {
            match event_survey_id {
                Some(event_survey_id) => Ok(db
                    .get_user_event_survey(event_survey_id, user_id)
                    .await?
                    .map(Box::new)),
                None => Ok(None),
            }
        },
    )?;

    // Warn when the requested survey can't be answered
    let warning = event_survey_id
        .filter(|_| survey.is_none())
        .map(|_| EVENT_SURVEY_NOT_AVAILABLE_WARNING.to_string());

    // Prepare template
    let navigation_links =
        NavigationLinks::from_filters(&filters, results.total, DASHBOARD_URL, PARTIAL_URL)?;
    let template = events::ListPage {
        events: results.events,
        navigation_links,
        surveys,
        total: results.total,
        offset: filters.offset,
        survey,
        warning,
    };

    Ok((filters, template))
}

/// Returns the survey requested in a dashboard home query, ignoring malformed
/// identifiers.
pub(crate) fn requested_event_survey_id(query: &HashMap<String, String>) -> Option<Uuid> {
    query.get("event_survey_id").and_then(|id| id.parse().ok())
}
