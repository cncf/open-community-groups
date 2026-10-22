//! HTTP handlers for the user dashboard Surveys tab.

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
    templates::dashboard::user::surveys,
    types::{
        dashboard::user::surveys::{EventSurveyAnswersForm, UserEventSurveysFilters},
        pagination::{self, NavigationLinks},
    },
};

#[cfg(test)]
mod tests;

/// URL used by the full dashboard page.
const DASHBOARD_URL: &str = "/dashboard/user?tab=surveys";

/// Warning shown when the requested survey isn't available.
const EVENT_SURVEY_NOT_AVAILABLE_WARNING: &str = "This survey is closed or isn't available to you.";

/// URL used by the surveys tab partial.
const PARTIAL_URL: &str = "/dashboard/user/surveys";

// Pages handlers.

/// Returns the surveys list page for the user dashboard.
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

/// Returns the modal content of a survey the user answers or reviews.
#[instrument(skip_all)]
pub(crate) async fn survey_modal(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(event_survey_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the survey as the current user reaches it
    let survey = db
        .get_user_event_survey(event_survey_id, user.user_id)
        .await?
        .ok_or(HandlerError::NotFound)?;

    // Prepare template
    let template = surveys::SurveyModal { survey };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Stores the current user's answers to an open event survey.
#[instrument(skip_all)]
pub(crate) async fn submit_response(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(event_survey_id): Path<Uuid>,
    ValidatedForm(form): ValidatedForm<EventSurveyAnswersForm>,
) -> Result<impl IntoResponse, HandlerError> {
    // Store the answers given to the survey revision the user saw
    db.submit_event_survey_response(event_survey_id, user.user_id, form.revision, &form.answers)
        .await?;

    // Reload the surveys list and the unanswered surveys badge
    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-user-surveys")],
    ))
}

// Helpers.

/// Prepares the surveys list page and filters for the user dashboard.
///
/// A requested survey opens on load when the user can reach it; otherwise the
/// page warns that it isn't available.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    user_id: Uuid,
    raw_query: &str,
    event_survey_id: Option<Uuid>,
) -> Result<(UserEventSurveysFilters, surveys::ListPage), HandlerError> {
    // Fetch the requested page of surveys and the requested survey
    let filters: UserEventSurveysFilters = ValidatedQuery::parse(raw_query)?;
    let (results, survey) =
        tokio::try_join!(db.list_user_event_surveys(user_id, &filters), async {
            match event_survey_id {
                Some(event_survey_id) => Ok(db
                    .get_user_event_survey(event_survey_id, user_id)
                    .await?
                    .map(Box::new)),
                None => Ok(None),
            }
        },)?;

    // Warn when the requested survey isn't available
    let warning = event_survey_id
        .filter(|_| survey.is_none())
        .map(|_| EVENT_SURVEY_NOT_AVAILABLE_WARNING.to_string());

    // Prepare template
    let navigation_links =
        NavigationLinks::from_filters(&filters, results.total, DASHBOARD_URL, PARTIAL_URL)?;
    let template = surveys::ListPage {
        navigation_links,
        refresh_url: pagination::build_url(DASHBOARD_URL, &filters)?,
        surveys: results.surveys,
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
