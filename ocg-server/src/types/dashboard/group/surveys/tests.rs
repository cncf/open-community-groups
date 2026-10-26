use chrono::{DateTime, NaiveDate};
use garde::Validate;
use serde_json::json;
use uuid::Uuid;

use crate::{
    types::{
        dashboard::{
            EVENT_SURVEY_RESPONSES_PAGINATION_LIMIT, EVENT_SURVEY_TEXT_ANSWERS_PAGINATION_LIMIT,
        },
        event_survey::{EventSurveyAudience, EventSurveyState},
        questionnaire::{QuestionnaireQuestion, QuestionnaireQuestionKind},
        tests::sample_event_survey_summary,
    },
    validation::{
        MAX_EVENT_SURVEY_QUESTIONS, MAX_EVENT_SURVEYS, MAX_LEN_DESCRIPTION_SHORT,
        MAX_LEN_ENTITY_NAME, MAX_LEN_M, MAX_SURVEY_PAGE_LIMIT,
    },
};

use super::{
    EventSurveyInput, EventSurveyResponseNavigationFilters, EventSurveyResponsesFilters,
    EventSurveyStatusAction, EventSurveyStatusForm, EventSurveySummary,
    EventSurveyTextAnswersFilters,
};

#[test]
fn test_event_survey_input_accepts_question_limit() {
    let input = EventSurveyInput {
        questions: sample_questions(MAX_EVENT_SURVEY_QUESTIONS),
        ..sample_input()
    };

    assert!(input.validate().is_ok());
}

#[test]
fn test_event_survey_input_deserializes_blank_optional_fields_as_none() {
    // Deserialize a form that clears the dates and the description
    let input: EventSurveyInput = serde_qs::from_str(
        "anonymous=true&audience=confirmed&title=Feedback&closes_at=&description=%20%20&opens_at=",
    )
    .unwrap();

    // Check blank values mean none and missing questions mean no questions
    assert!(input.closes_at.is_none());
    assert!(input.description.is_none());
    assert!(input.opens_at.is_none());
    assert!(input.questions.is_empty());
    assert!(input.revision.is_none());
}

#[test]
fn test_event_survey_input_deserializes_form() {
    // Deserialize a form with dates in the normalized browser format
    let input: EventSurveyInput = serde_qs::from_str(
        "anonymous=false&audience=checked-in&title=Feedback&\
closes_at=2099-05-20T18%3A30%3A00&description=Tell%20us&opens_at=2099-05-10T09%3A00%3A00&\
questions[0][id]=00000000-0000-0000-0000-000000000001&questions[0][kind]=single-select&\
questions[0][prompt]=Rating&questions[0][required]=true&\
questions[0][options][0][id]=00000000-0000-0000-0000-000000000002&\
questions[0][options][0][label]=Good&revision=3",
    )
    .unwrap();

    // Check every field was decoded
    assert!(!input.anonymous);
    assert_eq!(input.audience, EventSurveyAudience::CheckedIn);
    assert_eq!(input.title, "Feedback");
    assert_eq!(
        input.closes_at,
        NaiveDate::from_ymd_opt(2099, 5, 20).unwrap().and_hms_opt(18, 30, 0)
    );
    assert_eq!(input.description.as_deref(), Some("Tell us"));
    assert_eq!(
        input.opens_at,
        NaiveDate::from_ymd_opt(2099, 5, 10).unwrap().and_hms_opt(9, 0, 0)
    );
    assert_eq!(input.questions.len(), 1);
    assert_eq!(
        input.questions[0].kind,
        QuestionnaireQuestionKind::SingleSelect
    );
    assert_eq!(input.questions[0].options[0].label, "Good");
    assert_eq!(input.revision, Some(3));
}

#[test]
fn test_event_survey_input_deserializes_dates_without_seconds() {
    // Deserialize a form with dates as browsers send datetime-local values
    let input: EventSurveyInput = serde_qs::from_str(
        "anonymous=true&audience=confirmed&title=Feedback&\
closes_at=2099-05-20T18%3A30&opens_at=2099-05-10T09%3A00",
    )
    .unwrap();

    // Check both dates were decoded at whole minutes
    assert_eq!(
        input.closes_at,
        NaiveDate::from_ymd_opt(2099, 5, 20).unwrap().and_hms_opt(18, 30, 0)
    );
    assert_eq!(
        input.opens_at,
        NaiveDate::from_ymd_opt(2099, 5, 10).unwrap().and_hms_opt(9, 0, 0)
    );
}

#[test]
fn test_event_survey_input_rejects_invalid_fields() {
    let mut invalid_question = sample_questions(1);
    invalid_question[0].prompt = " ".to_string();
    // (case, input, invalid field)
    let cases = [
        (
            "blank title",
            EventSurveyInput {
                title: "   ".to_string(),
                ..sample_input()
            },
            "title",
        ),
        (
            "long title",
            EventSurveyInput {
                title: "a".repeat(MAX_LEN_ENTITY_NAME + 1),
                ..sample_input()
            },
            "title",
        ),
        (
            "long description",
            EventSurveyInput {
                description: Some("a".repeat(MAX_LEN_DESCRIPTION_SHORT + 1)),
                ..sample_input()
            },
            "description",
        ),
        (
            "invalid question",
            EventSurveyInput {
                questions: invalid_question,
                ..sample_input()
            },
            "questions[0].prompt",
        ),
        (
            "questions above limit",
            EventSurveyInput {
                questions: sample_questions(MAX_EVENT_SURVEY_QUESTIONS + 1),
                ..sample_input()
            },
            "questions",
        ),
        (
            "zero revision",
            EventSurveyInput {
                revision: Some(0),
                ..sample_input()
            },
            "revision",
        ),
    ];

    for (case, input, field) in cases {
        assert_eq!(invalid_fields(&input), [field], "{case}");
    }
}

#[test]
fn test_event_survey_input_serializes_database_payload() {
    // Setup an input with dates, a description and a revision
    let input = EventSurveyInput {
        closes_at: NaiveDate::from_ymd_opt(2099, 5, 20).unwrap().and_hms_opt(18, 30, 0),
        description: Some("Tell us".to_string()),
        questions: sample_questions(1),
        revision: Some(3),
        ..sample_input()
    };

    // Serialize the input as the database payload
    let payload = serde_json::to_value(&input).unwrap();

    // Check dates are local times and the revision is left out
    assert_eq!(
        payload,
        json!({
            "anonymous": true,
            "audience": "confirmed",
            "title": "Feedback",
            "closes_at": "2099-05-20T18:30:00",
            "description": "Tell us",
            "opens_at": null,
            "questions": [{
                "id": "00000000-0000-0000-0000-000000000001",
                "kind": "free-text",
                "prompt": "Question 1",
                "required": false,
                "options": []
            }]
        })
    );
}

#[test]
fn test_event_survey_response_navigation_filters_deserialize_blank_search_as_none() {
    let filters: EventSurveyResponseNavigationFilters =
        serde_qs::from_str("ts_query=%20%20").unwrap();

    assert!(filters.ts_query.is_none());
    assert!(filters.validate().is_ok());
}

#[test]
fn test_event_survey_response_navigation_filters_reject_long_search() {
    let filters = EventSurveyResponseNavigationFilters {
        ts_query: Some("a".repeat(MAX_LEN_M + 1)),
    };

    assert!(filters.validate().is_err());
}

#[test]
fn test_event_survey_responses_filters_deserialize_defaults_and_blank_search() {
    let filters: EventSurveyResponsesFilters = serde_qs::from_str("ts_query=%20").unwrap();

    assert_eq!(filters.limit, Some(EVENT_SURVEY_RESPONSES_PAGINATION_LIMIT));
    assert_eq!(filters.offset, Some(0));
    assert!(filters.ts_query.is_none());
}

#[test]
fn test_event_survey_responses_filters_navigation_filters_keep_search_only() {
    let filters: EventSurveyResponsesFilters =
        serde_qs::from_str("limit=5&offset=10&ts_query=jane").unwrap();

    assert_eq!(
        filters.navigation_filters().ts_query.as_deref(),
        Some("jane")
    );
}

#[test]
fn test_event_survey_responses_filters_validate_page_bounds() {
    for (case, limit, ts_query, valid) in page_bounds_cases() {
        let filters = EventSurveyResponsesFilters {
            limit,
            offset: Some(10),
            ts_query,
        };

        assert_eq!(filters.validate().is_ok(), valid, "{case}");
    }
}

#[test]
fn test_event_survey_status_action_displays_database_action() {
    assert_eq!(
        EventSurveyStatusAction::BackToDraft.to_string(),
        "back-to-draft"
    );
    assert_eq!(EventSurveyStatusAction::MarkReady.to_string(), "mark-ready");
}

#[test]
fn test_event_survey_status_form_deserializes_blank_opening_as_none() {
    let form: EventSurveyStatusForm =
        serde_urlencoded::from_str("action=mark-ready&revision=2&expected_effective_opens_at=")
            .unwrap();

    assert_eq!(form.action, EventSurveyStatusAction::MarkReady);
    assert_eq!(form.revision, 2);
    assert!(form.expected_effective_opens_at.is_none());
}

#[test]
fn test_event_survey_status_form_deserializes_confirmed_opening() {
    let form: EventSurveyStatusForm = serde_urlencoded::from_str(
        "action=mark-ready&revision=2&expected_effective_opens_at=4081420800",
    )
    .unwrap();

    assert_eq!(
        form.expected_effective_opens_at,
        DateTime::from_timestamp(4_081_420_800, 0)
    );
}

#[test]
fn test_event_survey_status_form_rejects_zero_revision() {
    let form: EventSurveyStatusForm =
        serde_urlencoded::from_str("action=close&revision=0").unwrap();

    assert!(form.validate().is_err());
}

#[test]
fn test_event_survey_summary_limit_reached_at_survey_limit() {
    let survey = sample_event_survey_summary(Uuid::from_u128(1), EventSurveyState::Draft);
    let surveys = vec![survey; MAX_EVENT_SURVEYS];

    assert!(EventSurveySummary::limit_reached(&surveys));
    assert!(!EventSurveySummary::limit_reached(&surveys[1..]));
}

#[test]
fn test_event_survey_text_answers_filters_deserialize_defaults_and_blank_search() {
    let filters: EventSurveyTextAnswersFilters = serde_qs::from_str("ts_query=%20").unwrap();

    assert_eq!(
        filters.limit,
        Some(EVENT_SURVEY_TEXT_ANSWERS_PAGINATION_LIMIT)
    );
    assert_eq!(filters.offset, Some(0));
    assert!(filters.ts_query.is_none());
}

#[test]
fn test_event_survey_text_answers_filters_validate_page_bounds() {
    for (case, limit, ts_query, valid) in page_bounds_cases() {
        let filters = EventSurveyTextAnswersFilters {
            limit,
            offset: Some(10),
            ts_query,
        };

        assert_eq!(filters.validate().is_ok(), valid, "{case}");
    }
}

// Helpers.

/// Returns the paths of the fields the value fails validation on.
fn invalid_fields(value: &impl Validate<Context = ()>) -> Vec<String> {
    value
        .validate()
        .expect_err("value should be invalid")
        .iter()
        .map(|(path, _)| path.to_string())
        .collect()
}

/// Returns survey page filter cases as (case, limit, search, valid).
fn page_bounds_cases() -> [(&'static str, Option<usize>, Option<String>, bool); 5] {
    [
        ("default limit", None, None, true),
        (
            "page limit with search",
            Some(MAX_SURVEY_PAGE_LIMIT),
            Some("jane".to_string()),
            true,
        ),
        ("empty page", Some(0), None, false),
        (
            "limit above page limit",
            Some(MAX_SURVEY_PAGE_LIMIT + 1),
            None,
            false,
        ),
        ("long search", None, Some("a".repeat(MAX_LEN_M + 1)), false),
    ]
}

/// Returns a valid survey input without questions or dates.
fn sample_input() -> EventSurveyInput {
    EventSurveyInput {
        anonymous: true,
        audience: EventSurveyAudience::Confirmed,
        title: "Feedback".to_string(),

        closes_at: None,
        description: None,
        opens_at: None,
        questions: vec![],
        revision: None,
    }
}

/// Returns the given number of valid free-text questions.
fn sample_questions(count: usize) -> Vec<QuestionnaireQuestion> {
    (1..=count)
        .map(|position| QuestionnaireQuestion {
            id: Uuid::from_u128(u128::try_from(position).unwrap()),
            kind: QuestionnaireQuestionKind::FreeText,
            prompt: format!("Question {position}"),
            required: false,

            options: vec![],
        })
        .collect()
}
