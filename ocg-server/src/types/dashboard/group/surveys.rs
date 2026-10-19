//! Group dashboard event survey types.

use chrono::{DateTime, NaiveDateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    types::{
        dashboard,
        event_survey::{EventSurveyAudience, EventSurveyState},
        pagination::{Pagination, ToRawQuery},
        questionnaire::{
            QuestionnaireAnswers, QuestionnaireQuestion, QuestionnaireQuestionBreakdown,
            QuestionnaireQuestionKind,
        },
        user::UserSummary,
    },
    validation::{
        MAX_EVENT_SURVEY_QUESTIONS, MAX_EVENT_SURVEYS, MAX_LEN_DESCRIPTION_SHORT,
        MAX_LEN_ENTITY_NAME, MAX_SURVEY_PAGE_LIMIT, blank_naive_datetime_as_none,
        blank_string_as_none, blank_timestamp_seconds_as_none, trimmed_non_empty,
    },
};

#[cfg(test)]
mod tests;

/// Responses of a survey prepared for the CSV export.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventSurveyExport {
    /// Whether respondent identities are hidden from the organizers.
    pub anonymous: bool,
    /// Questions in definition order, one CSV column each.
    pub questions: Vec<QuestionnaireQuestion>,
    /// Responses in creation order, one CSV row each.
    pub responses: Vec<EventSurveyExportResponse>,
    /// Survey title.
    pub title: String,
}

/// Respondent details exported for identified surveys.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventSurveyExportRespondent {
    /// Respondent username.
    pub username: String,

    /// Respondent company.
    pub company: Option<String>,
    /// Respondent display name.
    pub name: Option<String>,
    /// Respondent job title.
    pub title: Option<String>,
}

/// One exported survey response.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventSurveyExportResponse {
    /// Submitted answers.
    pub answers: QuestionnaireAnswers,
    /// First submission time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,

    /// Latest edit time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub updated_at: Option<DateTime<Utc>>,
    /// Respondent details, only exported for identified surveys.
    pub user: Option<EventSurveyExportRespondent>,
}

/// Survey with the settings the dashboard editor needs.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventSurveyFull {
    /// Creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Questions in definition order.
    pub questions: Vec<QuestionnaireQuestion>,
    /// Summary shared with the survey list.
    #[serde(flatten)]
    pub summary: EventSurveySummary,

    /// Manual close time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub closed_at: Option<DateTime<Utc>>,
    /// Plain text introduction.
    pub description: Option<String>,
    /// Custom opening time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub opens_at: Option<DateTime<Utc>>,
    /// Latest update time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub updated_at: Option<DateTime<Utc>>,
}

/// Survey configuration submitted by the dashboard editor.
///
/// Its serialized form is the database survey payload: dates are local times
/// in the event timezone (`YYYY-MM-DDTHH:MM:SS`), and the revision is passed
/// to the database separately.
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct EventSurveyInput {
    /// Whether respondent identities are hidden from the organizers.
    #[garde(skip)]
    pub anonymous: bool,
    /// Attendees the survey is addressed to.
    #[garde(skip)]
    pub audience: EventSurveyAudience,
    /// Survey title.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_ENTITY_NAME))]
    pub title: String,

    /// Scheduled closing time; blank means none.
    #[serde(default, deserialize_with = "blank_naive_datetime_as_none")]
    #[garde(skip)]
    pub closes_at: Option<NaiveDateTime>,
    /// Plain text introduction; blank means none.
    #[serde(default, deserialize_with = "blank_string_as_none")]
    #[garde(length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub description: Option<String>,
    /// Custom earliest opening time; blank means when the event ends.
    #[serde(default, deserialize_with = "blank_naive_datetime_as_none")]
    #[garde(skip)]
    pub opens_at: Option<NaiveDateTime>,
    /// Questions in definition order; none submitted means no questions.
    #[serde(default)]
    #[garde(length(max = MAX_EVENT_SURVEY_QUESTIONS), dive)]
    pub questions: Vec<QuestionnaireQuestion>,
    /// Survey revision the editor loaded, submitted by the update form.
    #[serde(default, skip_serializing)]
    #[garde(range(min = 1))]
    pub revision: Option<i64>,
}

/// One response to an identified survey with its respondent.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventSurveyResponse {
    /// Submitted answers.
    pub answers: QuestionnaireAnswers,
    /// First submission time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Respondent.
    pub user: UserSummary,

    /// Latest edit time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub updated_at: Option<DateTime<Utc>>,
}

/// Pagination filters of the responses to an identified survey.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct EventSurveyResponsesFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_event_survey_responses_limit")]
    #[garde(range(min = 1, max = MAX_SURVEY_PAGE_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(EventSurveyResponsesFilters, limit, offset);

/// Page of the responses to an identified survey.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventSurveyResponsesOutput {
    /// Responses in creation order.
    pub responses: Vec<EventSurveyResponse>,
    /// Total number of responses.
    pub total: usize,
}

/// Aggregated results of a survey.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventSurveyResults {
    /// Question results in definition order.
    pub questions: Vec<EventSurveyResultsQuestion>,
    /// Survey summary.
    pub survey: EventSurveySummary,
}

/// Results of one survey question.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventSurveyResultsQuestion {
    /// Question kind.
    pub kind: QuestionnaireQuestionKind,
    /// One-based position of the question among all questions.
    pub position: i64,
    /// Question prompt.
    pub prompt: String,
    /// Question identifier.
    pub question_id: Uuid,
    /// Whether attendees must answer the question.
    pub required: bool,

    /// Option breakdown of a select question.
    #[serde(default)]
    pub breakdown: Option<QuestionnaireQuestionBreakdown>,
    /// First non-blank answers of a free-text question and their total.
    #[serde(default)]
    pub text_answers: Option<EventSurveyTextAnswers>,
}

/// Status change requested from the survey list.
#[derive(Debug, Clone, Deserialize, Validate)]
pub(crate) struct EventSurveyStatusForm {
    /// Requested transition.
    #[garde(skip)]
    pub action: EventSurveyStatusAction,
    /// Survey revision the list showed.
    #[garde(range(min = 1))]
    pub revision: i64,

    /// Opening time the Mark ready confirmation showed; blank when the event
    /// has no dates yet.
    #[serde(default, deserialize_with = "blank_timestamp_seconds_as_none")]
    #[garde(skip)]
    pub expected_effective_opens_at: Option<DateTime<Utc>>,
}

/// Status transitions organizers can request.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, strum::Display, strum::EnumString,
)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum EventSurveyStatusAction {
    /// Moves a scheduled survey back to draft.
    BackToDraft,
    /// Closes an open survey.
    Close,
    /// Marks a draft survey ready.
    MarkReady,
    /// Reopens a closed survey.
    Reopen,
}

/// Summary of a survey shown in the dashboard list.
#[allow(clippy::struct_excessive_bools)]
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventSurveySummary {
    /// Whether respondent identities are hidden from the organizers.
    pub anonymous: bool,
    /// Whether the survey must stay anonymous because it opened or its
    /// opening email was handled.
    pub anonymous_locked: bool,
    /// Attendees the survey is addressed to.
    pub audience: EventSurveyAudience,
    /// Whether the survey was closed manually.
    pub closed_manually: bool,
    /// Attendees currently in the survey audience.
    pub eligible_count: i64,
    /// Attendees currently in the survey audience who responded.
    pub eligible_respondents_count: i64,
    /// Survey identifier.
    pub event_survey_id: Uuid,
    /// Whether responses lock the questions, audience and anonymity.
    pub locked: bool,
    /// Number of questions.
    pub questions_count: i64,
    /// Stored responses, including those of users no longer eligible.
    pub responses_count: i64,
    /// Revision that status changes and edits must match.
    pub revision: i64,
    /// Live survey state.
    pub state: EventSurveyState,
    /// Survey title.
    pub title: String,

    /// Scheduled closing time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub closes_at: Option<DateTime<Utc>>,
    /// Opening time, missing while the event has no dates.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub effective_opens_at: Option<DateTime<Utc>>,
    /// Time the opening email was handled.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub open_notification_processed_at: Option<DateTime<Utc>>,
}

impl EventSurveySummary {
    /// Returns whether an event with these surveys cannot get another one.
    pub(crate) fn limit_reached(surveys: &[Self]) -> bool {
        surveys.len() >= MAX_EVENT_SURVEYS
    }

    /// Returns the share of eligible attendees who answered, or none when
    /// nobody is eligible.
    #[allow(clippy::cast_precision_loss)]
    pub(crate) fn response_rate(&self) -> Option<f64> {
        (self.eligible_count > 0)
            .then(|| self.eligible_respondents_count as f64 / self.eligible_count as f64)
    }
}

/// Page of the answers to a free-text survey question.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventSurveyTextAnswers {
    /// Non-blank answers in response creation order.
    pub answers: Vec<String>,
    /// Total number of non-blank answers.
    pub total: usize,
}

/// Pagination filters of the answers to a free-text survey question.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct EventSurveyTextAnswersFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_event_survey_text_answers_limit")]
    #[garde(range(min = 1, max = MAX_SURVEY_PAGE_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(EventSurveyTextAnswersFilters, limit, offset);
