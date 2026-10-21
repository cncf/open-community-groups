//! HTTP handlers for the event surveys tab in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::{Html, IntoResponse},
};
use chrono::Utc;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        csv::{
            attachment_response, csv_optional_timestamp, csv_timestamp, csv_writer, finish_csv,
            write_safe_record,
        },
        error::HandlerError,
        extractors::{
            CurrentUser, SelectedCommunityId, SelectedGroupId, ValidatedForm, ValidatedFormQs,
            ValidatedQuery,
        },
    },
    templates::dashboard::group::surveys,
    types::{
        dashboard::group::surveys::{
            EventSurveyExport, EventSurveyInput, EventSurveyResponseNavigationFilters,
            EventSurveyResponsesFilters, EventSurveyStatusForm, EventSurveyTextAnswersFilters,
        },
        pagination::NavigationLinks,
        permissions::GroupPermission,
    },
};

#[cfg(test)]
mod tests;

/// HTMX event that refreshes the event surveys tab after a survey mutation.
const EVENT_SURVEYS_REFRESH_TRIGGER: &str = "refresh-event-surveys";

/// Maximum bytes of stored answer JSON the survey CSV export supports.
///
/// The export loads every response and builds the file in memory, and the
/// database rejects larger surveys before the payload is built. Measured with
/// 10,000 identified responses of five free-text answers each, 52.4 MB of
/// answer JSON in total: the database query took about 0.3 s and returned a
/// 54.5 MB payload, loading and deserializing it took about 0.5 s, and the
/// 49.4 MB CSV was built in about 30 ms, with a peak RSS of about 160 MB for
/// the whole export. Raising this bound or [`MAX_EVENT_SURVEY_EXPORT_ROWS`]
/// needs a new measurement.
const MAX_EVENT_SURVEY_EXPORT_ANSWER_BYTES: usize = 50 * 1024 * 1024;

/// Maximum number of responses the survey CSV export supports.
///
/// Measured together with [`MAX_EVENT_SURVEY_EXPORT_ANSWER_BYTES`]; surveys
/// with more responses are rejected instead of streamed.
const MAX_EVENT_SURVEY_EXPORT_ROWS: usize = 10_000;

// Pages handlers.

/// Displays the form to add a survey to an event.
#[instrument(skip_all)]
pub(crate) async fn add_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the permission and the event concurrently
    let (can_manage_events, event) = tokio::try_join!(
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user.user_id,
            GroupPermission::EventsWrite
        ),
        db.get_event_summary_dashboard(community_id, group_id, event_id),
    )?;

    // Prepare template
    let template = surveys::FormPage {
        can_manage_surveys: can_manage_events && !event.canceled,
        event,

        survey: None,
    };

    Ok(Html(template.render()?))
}

/// Displays the surveys of an event.
#[instrument(skip_all)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the permission, the event and its surveys concurrently
    let (can_manage_events, event, surveys) = tokio::try_join!(
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user.user_id,
            GroupPermission::EventsWrite
        ),
        db.get_event_summary_dashboard(community_id, group_id, event_id),
        db.list_event_surveys(group_id, event_id),
    )?;

    // Prepare template
    let template = surveys::ListPage {
        can_manage_surveys: can_manage_events && !event.canceled,
        event,
        now: Utc::now(),
        surveys,
    };

    Ok(Html(template.render()?))
}

/// Displays the responses of one respondent to an identified survey, with
/// links to the previous and next respondents matching the search.
#[instrument(skip_all)]
pub(crate) async fn response_modal(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path((event_id, event_survey_id, user_id)): Path<(Uuid, Uuid, Uuid)>,
    ValidatedQuery(filters): ValidatedQuery<EventSurveyResponseNavigationFilters>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the event and the survey concurrently
    let (event, survey) = tokio::try_join!(
        db.get_event_summary_dashboard(community_id, group_id, event_id),
        db.get_event_survey(group_id, event_id, event_survey_id),
    )?;
    let survey = survey.ok_or(HandlerError::NotFound)?;

    // Keep respondent identities of anonymous surveys hidden
    reject_anonymous_survey_responses(survey.summary.anonymous)?;

    // Load the response with its neighbors among the matching respondents
    let response = db
        .get_event_survey_response(group_id, event_id, event_survey_id, user_id, &filters)
        .await?
        .ok_or(HandlerError::NotFound)?;

    // Prepare template
    let template = surveys::ResponseModal {
        event,
        navigation_filters: filters,
        response,
        survey,
    };

    Ok(Html(template.render()?))
}

/// Displays the respondents of an identified survey, searchable and paginated.
#[instrument(skip_all)]
pub(crate) async fn responses_page(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path((event_id, event_survey_id)): Path<(Uuid, Uuid)>,
    ValidatedQuery(filters): ValidatedQuery<EventSurveyResponsesFilters>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the event and the survey concurrently
    let (event, survey) = tokio::try_join!(
        db.get_event_summary_dashboard(community_id, group_id, event_id),
        db.get_event_survey(group_id, event_id, event_survey_id),
    )?;
    let survey = survey.ok_or(HandlerError::NotFound)?;

    // Keep respondent identities of anonymous surveys hidden
    reject_anonymous_survey_responses(survey.summary.anonymous)?;

    // Load the requested page of matching respondents
    let responses = db
        .list_event_survey_responses(group_id, event_id, event_survey_id, &filters)
        .await?
        .ok_or(HandlerError::NotFound)?;

    // Prepare template
    let url = format!("/dashboard/group/events/{event_id}/surveys/{event_survey_id}/responses");
    let navigation_links = NavigationLinks::from_filters(&filters, responses.total, &url, &url)?;
    let template = surveys::ResponsesPage {
        event,
        navigation_links,
        navigation_filters: filters.navigation_filters(),
        responses,
        survey,

        offset: filters.offset,
        ts_query: filters.ts_query,
    };

    Ok(Html(template.render()?))
}

/// Displays the aggregated results of a survey.
#[instrument(skip_all)]
pub(crate) async fn results_page(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path((event_id, event_survey_id)): Path<(Uuid, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the event and the survey results concurrently
    let (event, results) = tokio::try_join!(
        db.get_event_summary_dashboard(community_id, group_id, event_id),
        db.get_event_survey_results(group_id, event_id, event_survey_id),
    )?;
    let results = results.ok_or(HandlerError::NotFound)?;

    // Prepare template
    let template = surveys::ResultsPage { event, results };

    Ok(Html(template.render()?))
}

/// Displays a page of the answers to a free-text survey question matching
/// the search, rendered inside the answers modal of the Summary view.
///
/// Answers carry no respondent identities, so anonymous surveys can be
/// searched too.
#[instrument(skip_all)]
pub(crate) async fn text_answers_modal(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path((event_id, event_survey_id, question_id)): Path<(Uuid, Uuid, Uuid)>,
    ValidatedQuery(filters): ValidatedQuery<EventSurveyTextAnswersFilters>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the requested page of matching answers
    let answers = db
        .list_event_survey_text_answers(group_id, event_id, event_survey_id, question_id, &filters)
        .await?
        .ok_or(HandlerError::NotFound)?;

    // Prepare template
    let url = surveys::text_answers_url(event_id, event_survey_id, question_id);
    let navigation_links = NavigationLinks::from_filters(&filters, answers.total, &url, &url)?;
    let template = surveys::TextAnswersModal {
        answers,
        event_id,
        event_survey_id,
        navigation_links,
        question_id,

        offset: filters.offset,
        ts_query: filters.ts_query,
    };

    Ok(Html(template.render()?))
}

/// Displays the form to update a survey.
#[instrument(skip_all)]
pub(crate) async fn update_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path((event_id, event_survey_id)): Path<(Uuid, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the permission, the event and the survey concurrently
    let (can_manage_events, event, survey) = tokio::try_join!(
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user.user_id,
            GroupPermission::EventsWrite
        ),
        db.get_event_summary_dashboard(community_id, group_id, event_id),
        db.get_event_survey(group_id, event_id, event_survey_id),
    )?;
    let survey = survey.ok_or(HandlerError::NotFound)?;

    // Prepare template
    let template = surveys::FormPage {
        can_manage_surveys: can_manage_events && !event.canceled,
        event,

        survey: Some(survey),
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Adds a draft survey to an event.
#[instrument(skip_all)]
pub(crate) async fn add(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
    ValidatedFormQs(survey): ValidatedFormQs<EventSurveyInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Add the survey to the event
    db.add_event_survey(user.user_id, group_id, event_id, &survey).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", EVENT_SURVEYS_REFRESH_TRIGGER)],
    ))
}

/// Changes the status of a survey.
#[instrument(skip_all)]
pub(crate) async fn change_status(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path((event_id, event_survey_id)): Path<(Uuid, Uuid)>,
    ValidatedForm(status): ValidatedForm<EventSurveyStatusForm>,
) -> Result<impl IntoResponse, HandlerError> {
    // Apply the requested status transition
    db.change_event_survey_status(user.user_id, group_id, event_id, event_survey_id, &status)
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", EVENT_SURVEYS_REFRESH_TRIGGER)],
    ))
}

/// Deletes a survey together with its responses.
#[instrument(skip_all)]
pub(crate) async fn delete(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path((event_id, event_survey_id)): Path<(Uuid, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Delete the survey and its responses
    db.delete_event_survey(user.user_id, group_id, event_id, event_survey_id)
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", EVENT_SURVEYS_REFRESH_TRIGGER)],
    ))
}

/// Updates the settings of a survey.
#[instrument(skip_all)]
pub(crate) async fn update(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path((event_id, event_survey_id)): Path<(Uuid, Uuid)>,
    ValidatedFormQs(survey): ValidatedFormQs<EventSurveyInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Require the revision the editor loaded
    let Some(expected_revision) = survey.revision else {
        return Err(HandlerError::Rejected(
            "survey revision is required".to_string(),
        ));
    };

    // Update the survey when it did not change since it was loaded
    db.update_event_survey(
        user.user_id,
        group_id,
        event_id,
        event_survey_id,
        expected_revision,
        &survey,
    )
    .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", EVENT_SURVEYS_REFRESH_TRIGGER)],
    ))
}

// Download handlers.

/// Downloads a CSV file with the responses to a survey.
#[instrument(skip_all)]
pub(crate) async fn download_csv(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path((event_id, event_survey_id)): Path<(Uuid, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the event and the responses within the export bounds
    let (event, export) = tokio::try_join!(
        db.get_event_summary_dashboard(community_id, group_id, event_id),
        db.get_event_survey_export(
            group_id,
            event_id,
            event_survey_id,
            MAX_EVENT_SURVEY_EXPORT_ROWS,
            MAX_EVENT_SURVEY_EXPORT_ANSWER_BYTES,
        ),
    )?;
    let export = export.ok_or(HandlerError::NotFound)?;

    // Build the CSV payload
    let csv = build_survey_csv(&export)?;
    let file_name = format!("event-{}-survey-{event_survey_id}.csv", event.slug);

    Ok(attachment_response(&file_name, csv))
}

// Helpers.

/// Builds the CSV payload of a survey export, with one row per response and
/// one column per question. Identified surveys also export the respondent
/// name, company and title. Every cell, headers included, is protected against
/// spreadsheet formula evaluation.
fn build_survey_csv(export: &EventSurveyExport) -> Result<Vec<u8>, HandlerError> {
    let mut writer = csv_writer();

    // Write the header row, adding respondent columns for identified surveys
    let mut headers = Vec::new();
    if !export.anonymous {
        headers.extend(["Name", "Company", "Title"].map(str::to_string));
    }
    headers.extend(["Submitted", "Updated"].map(str::to_string));
    headers.extend(export.questions.iter().map(|question| question.prompt.clone()));
    write_safe_record(&mut writer, headers)?;

    // Write one row per response
    for response in &export.responses {
        let mut row = Vec::new();
        if !export.anonymous {
            let user = response.user.as_ref();
            row.extend([
                user.map(|user| user.name.clone().unwrap_or_else(|| user.username.clone()))
                    .unwrap_or_default(),
                user.and_then(|user| user.company.clone()).unwrap_or_default(),
                user.and_then(|user| user.title.clone()).unwrap_or_default(),
            ]);
        }
        row.extend([
            csv_timestamp(response.created_at),
            csv_optional_timestamp(response.updated_at),
        ]);
        row.extend(
            export
                .questions
                .iter()
                .map(|question| question.format_answer(Some(&response.answers))),
        );
        write_safe_record(&mut writer, row)?;
    }

    finish_csv(writer)
}

/// Rejects requests for the respondents of anonymous surveys, whose
/// identities stay hidden from the organizers.
fn reject_anonymous_survey_responses(anonymous: bool) -> Result<(), HandlerError> {
    if anonymous {
        return Err(HandlerError::Rejected(
            "individual responses are not available for anonymous surveys".to_string(),
        ));
    }

    Ok(())
}
