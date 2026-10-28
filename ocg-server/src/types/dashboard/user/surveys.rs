//! User dashboard event survey types.

use chrono::{DateTime, Utc};
use chrono_tz::Tz;
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    types::{
        dashboard,
        event::EventSummary,
        event_survey::EventSurveyState,
        pagination::{Pagination, ToRawQuery},
        questionnaire::{
            QuestionnaireAnswers, QuestionnaireQuestion,
            deserialize_required_questionnaire_answers, validate_questionnaire_answers,
        },
    },
    validation::MAX_SURVEY_PAGE_LIMIT,
};

/// Event survey a user reaches from the dashboard: an open survey to answer,
/// or a closed survey the user answered.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct UserEventSurvey {
    /// Whether respondent identities are hidden from the organizers.
    pub anonymous: bool,
    /// Event the survey belongs to.
    pub event: EventSummary,
    /// Survey identifier.
    pub event_survey_id: Uuid,
    /// Questions in definition order.
    pub questions: Vec<QuestionnaireQuestion>,
    /// Revision the answers are given to.
    pub revision: i64,
    /// Live state of the survey: open or closed.
    pub state: EventSurveyState,
    /// Survey title.
    pub title: String,

    /// Time a closed survey closed.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub closed_at: Option<DateTime<Utc>>,
    /// Scheduled closing time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub closes_at: Option<DateTime<Utc>>,
    /// Plain text introduction.
    pub description: Option<String>,
    /// Response the user already submitted.
    pub response: Option<UserEventSurveyResponse>,
}

impl UserEventSurvey {
    /// Returns true when the survey no longer accepts answers.
    pub(crate) fn is_closed(&self) -> bool {
        self.state == EventSurveyState::Closed
    }
}

/// Survey listed in the user dashboard Surveys tab.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct UserEventSurveyItem {
    /// Whether the user already answered the survey.
    pub answered: bool,
    /// Event name.
    pub event_name: String,
    /// Survey identifier.
    pub event_survey_id: Uuid,
    /// Name of the group hosting the event.
    pub group_name: String,
    /// Live state of the survey: open or closed.
    pub state: EventSurveyState,
    /// Event timezone.
    pub timezone: Tz,
    /// Survey title.
    pub title: String,

    /// Time a closed survey closed.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub closed_at: Option<DateTime<Utc>>,
    /// Scheduled closing time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub closes_at: Option<DateTime<Utc>>,
}

impl UserEventSurveyItem {
    /// Returns true when the survey no longer accepts answers.
    pub(crate) fn is_closed(&self) -> bool {
        self.state == EventSurveyState::Closed
    }
}

/// Response a user submitted to an event survey.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct UserEventSurveyResponse {
    /// Submitted answers.
    pub answers: QuestionnaireAnswers,
    /// First submission time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,

    /// Latest edit time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub updated_at: Option<DateTime<Utc>>,
}

/// Filter parameters for the Surveys tab pagination.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct UserEventSurveysFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_user_event_surveys_limit")]
    #[garde(range(min = 1, max = MAX_SURVEY_PAGE_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(UserEventSurveysFilters, limit, offset);

/// Paginated Surveys tab data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct UserEventSurveysOutput {
    /// Open surveys the user can answer, unanswered first, followed by the
    /// closed surveys the user answered.
    pub surveys: Vec<UserEventSurveyItem>,
    /// Total number of surveys before pagination.
    pub total: usize,
}

// Form types.

/// Answers to an event survey submitted by a user.
#[derive(Debug, Deserialize, Validate)]
pub(crate) struct EventSurveyAnswersForm {
    /// Answers decoded from the form field JSON.
    #[serde(deserialize_with = "deserialize_required_questionnaire_answers")]
    #[garde(custom(validate_questionnaire_answers))]
    pub answers: QuestionnaireAnswers,
    /// Survey revision the answers were given to.
    #[garde(range(min = 1))]
    pub revision: i64,
}

#[cfg(test)]
mod tests {
    use garde::Validate;
    use serde_json::json;
    use uuid::Uuid;

    use crate::{
        types::{
            dashboard::USER_EVENT_SURVEYS_PAGINATION_LIMIT,
            event_survey::EventSurveyState,
            questionnaire::QuestionnaireAnswerValue,
            tests::{sample_user_event_survey, sample_user_event_survey_item},
        },
        validation::MAX_SURVEY_PAGE_LIMIT,
    };

    use super::{EventSurveyAnswersForm, UserEventSurveysFilters};

    #[test]
    fn test_event_survey_answers_form_deserializes_answers_and_revision() {
        // Deserialize a form with JSON-encoded answers
        let form: EventSurveyAnswersForm = serde_urlencoded::from_str(&format!(
            "answers={}&revision=4",
            encode_answers(&json!({
                "answers": [{
                    "question_id": "00000000-0000-0000-0000-000000000001",
                    "value": "More hands-on time"
                }]
            }))
        ))
        .unwrap();

        // Check the answers and the revision were decoded
        assert_eq!(form.answers.answers.len(), 1);
        assert_eq!(form.answers.answers[0].question_id, Uuid::from_u128(1));
        assert!(matches!(
            &form.answers.answers[0].value,
            QuestionnaireAnswerValue::One(value) if value == "More hands-on time"
        ));
        assert_eq!(form.revision, 4);
        assert!(form.validate().is_ok());
    }

    #[test]
    fn test_event_survey_answers_form_rejects_blank_answers() {
        let result = serde_urlencoded::from_str::<EventSurveyAnswersForm>("answers=&revision=1");

        assert!(result.is_err());
    }

    #[test]
    fn test_event_survey_answers_form_rejects_repeated_question() {
        let form: EventSurveyAnswersForm = serde_urlencoded::from_str(&format!(
            "answers={}&revision=1",
            encode_answers(&json!({
                "answers": [
                    {"question_id": "00000000-0000-0000-0000-000000000001", "value": "First"},
                    {"question_id": "00000000-0000-0000-0000-000000000001", "value": "Second"}
                ]
            }))
        ))
        .unwrap();

        let report = form.validate().unwrap_err().to_string();
        assert!(
            report.contains("questionnaire answers must include each question at most once"),
            "{report}"
        );
    }

    #[test]
    fn test_event_survey_answers_form_rejects_zero_revision() {
        let form: EventSurveyAnswersForm = serde_urlencoded::from_str(&format!(
            "answers={}&revision=0",
            encode_answers(&json!({ "answers": [] }))
        ))
        .unwrap();

        let report = form.validate().unwrap_err();
        let fields: Vec<String> = report.iter().map(|(path, _)| path.to_string()).collect();
        assert_eq!(fields, ["revision"]);
    }

    #[test]
    fn test_user_event_survey_is_closed_only_in_closed_state() {
        let mut survey = sample_user_event_survey(Uuid::from_u128(1), Uuid::from_u128(2));

        assert!(!survey.is_closed());

        survey.state = EventSurveyState::Closed;

        assert!(survey.is_closed());
    }

    #[test]
    fn test_user_event_survey_item_is_closed_only_in_closed_state() {
        let mut item = sample_user_event_survey_item(Uuid::from_u128(1), true);

        assert!(!item.is_closed());

        item.state = EventSurveyState::Closed;

        assert!(item.is_closed());
    }

    #[test]
    fn test_user_event_surveys_filters_apply_default_bounds() {
        let filters: UserEventSurveysFilters = serde_qs::from_str("").unwrap();

        assert_eq!(filters.limit, Some(USER_EVENT_SURVEYS_PAGINATION_LIMIT));
        assert_eq!(filters.offset, Some(0));
    }

    #[test]
    fn test_user_event_surveys_filters_validate_page_bounds() {
        let cases = [
            ("default limit", None, true),
            ("page limit", Some(MAX_SURVEY_PAGE_LIMIT), true),
            ("empty page", Some(0), false),
            (
                "limit above page limit",
                Some(MAX_SURVEY_PAGE_LIMIT + 1),
                false,
            ),
        ];

        for (case, limit, valid) in cases {
            let filters = UserEventSurveysFilters {
                limit,
                offset: Some(10),
            };

            assert_eq!(filters.validate().is_ok(), valid, "{case}");
        }
    }

    // Helpers.

    /// Encodes an answers payload as a form field value.
    fn encode_answers(answers: &serde_json::Value) -> String {
        serde_urlencoded::to_string([("v", answers.to_string())])
            .unwrap()
            .trim_start_matches("v=")
            .to_string()
    }
}
