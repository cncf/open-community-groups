use chrono::{DateTime, NaiveDate, TimeZone, Utc};
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
    },
    validation::{
        MAX_EVENT_SURVEY_QUESTIONS, MAX_EVENT_SURVEYS, MAX_LEN_DESCRIPTION_SHORT,
        MAX_LEN_ENTITY_NAME, MAX_LEN_M, MAX_SURVEY_PAGE_LIMIT,
    },
};

use super::{
    EventSurveyInput, EventSurveyResponseFull, EventSurveyResponseNavigationFilters,
    EventSurveyResponsesFilters, EventSurveyResultsQuestion, EventSurveyStatusAction,
    EventSurveyStatusForm, EventSurveySummary, EventSurveyTextAnswersFilters,
    EventSurveyTextAnswersOutput,
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
fn test_event_survey_input_rejects_blank_title() {
    let input = EventSurveyInput {
        title: "   ".to_string(),
        ..sample_input()
    };

    assert!(input.validate().is_err());
}

#[test]
fn test_event_survey_input_rejects_invalid_question() {
    let mut questions = sample_questions(1);
    questions[0].prompt = " ".to_string();
    let input = EventSurveyInput {
        questions,
        ..sample_input()
    };

    assert!(input.validate().is_err());
}

#[test]
fn test_event_survey_input_rejects_long_description() {
    let input = EventSurveyInput {
        description: Some("a".repeat(MAX_LEN_DESCRIPTION_SHORT + 1)),
        ..sample_input()
    };

    assert!(input.validate().is_err());
}

#[test]
fn test_event_survey_input_rejects_long_title() {
    let input = EventSurveyInput {
        title: "a".repeat(MAX_LEN_ENTITY_NAME + 1),
        ..sample_input()
    };

    assert!(input.validate().is_err());
}

#[test]
fn test_event_survey_input_rejects_questions_above_limit() {
    let input = EventSurveyInput {
        questions: sample_questions(MAX_EVENT_SURVEY_QUESTIONS + 1),
        ..sample_input()
    };

    assert!(input.validate().is_err());
}

#[test]
fn test_event_survey_input_rejects_zero_revision() {
    let input = EventSurveyInput {
        revision: Some(0),
        ..sample_input()
    };

    assert!(input.validate().is_err());
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
fn test_event_survey_response_full_deserializes_database_payload() {
    // Deserialize the response of a respondent without a ticket or edits
    let response: EventSurveyResponseFull = serde_json::from_value(json!({
        "answered_questions_count": 1,
        "answers": {"answers": [
            {"question_id": "00000000-0000-0000-0000-000000000001", "value": "More time"}
        ]},
        "created_at": 1_735_808_400,
        "user": {"user_id": "00000000-0000-0000-0000-000000000002", "username": "jane"},

        "ticket_title": null,
        "updated_at": null,

        "next_user_id": "00000000-0000-0000-0000-000000000003",
        "position": 1,
        "previous_user_id": null,
        "total": 2
    }))
    .unwrap();

    // Check the answers and the navigation
    assert_eq!(response.answers.answers.len(), 1);
    assert_eq!(response.position, 1);
    assert_eq!(response.total, 2);
    assert_eq!(response.next_user_id, Some(Uuid::from_u128(3)));
    assert!(response.previous_user_id.is_none());

    // Check the flattened respondent details
    assert_eq!(response.summary.answered_questions_count, 1);
    assert_eq!(
        response.summary.created_at,
        Utc.with_ymd_and_hms(2025, 1, 2, 9, 0, 0).unwrap()
    );
    assert_eq!(response.summary.user.username, "jane");
    assert!(response.summary.ticket_title.is_none());
    assert!(response.summary.updated_at.is_none());
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
fn test_event_survey_responses_filters_accept_page_limit() {
    let filters = EventSurveyResponsesFilters {
        limit: Some(MAX_SURVEY_PAGE_LIMIT),
        offset: Some(10),
        ts_query: Some("jane".to_string()),
    };

    assert!(filters.validate().is_ok());
}

#[test]
fn test_event_survey_responses_filters_apply_default_bounds() {
    let filters: EventSurveyResponsesFilters = serde_qs::from_str("").unwrap();

    assert_eq!(filters.limit, Some(EVENT_SURVEY_RESPONSES_PAGINATION_LIMIT));
    assert_eq!(filters.offset, Some(0));
    assert!(filters.ts_query.is_none());
}

#[test]
fn test_event_survey_responses_filters_deserialize_blank_search_as_none() {
    let filters: EventSurveyResponsesFilters = serde_qs::from_str("ts_query=%20").unwrap();

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
fn test_event_survey_responses_filters_reject_empty_pages() {
    let filters: EventSurveyResponsesFilters = serde_qs::from_str("limit=0").unwrap();

    assert!(filters.validate().is_err());
}

#[test]
fn test_event_survey_responses_filters_reject_limit_above_page_limit() {
    let filters = EventSurveyResponsesFilters {
        limit: Some(MAX_SURVEY_PAGE_LIMIT + 1),
        offset: None,
        ts_query: None,
    };

    assert!(filters.validate().is_err());
}

#[test]
fn test_event_survey_responses_filters_reject_long_search() {
    let filters = EventSurveyResponsesFilters {
        limit: None,
        offset: None,
        ts_query: Some("a".repeat(MAX_LEN_M + 1)),
    };

    assert!(filters.validate().is_err());
}

#[test]
fn test_event_survey_results_questions_deserialize_database_payload() {
    // Deserialize the questions of a results payload
    let questions: Vec<EventSurveyResultsQuestion> = serde_json::from_value(json!([
        {
            "kind": "free-text",
            "position": 1,
            "prompt": "What should we improve?",
            "question_id": "00000000-0000-0000-0000-000000000001",
            "required": false,

            "breakdown": null,
            "text_answers": {"answers": ["More time"], "total": 3}
        },
        {
            "kind": "single-select",
            "position": 2,
            "prompt": "Rating",
            "question_id": "00000000-0000-0000-0000-000000000002",
            "required": true,

            "breakdown": {
                "kind": "single-select",
                "options": [{
                    "count": 2,
                    "label": "Good",
                    "option_id": "00000000-0000-0000-0000-000000000003"
                }],
                "position": 2,
                "prompt": "Rating",
                "question_id": "00000000-0000-0000-0000-000000000002",
                "respondents": 2,
                "selections": 2
            },
            "text_answers": null
        }
    ]))
    .unwrap();

    // Check the free-text question carries its answers only
    assert_eq!(questions[0].kind, QuestionnaireQuestionKind::FreeText);
    assert_eq!(questions[0].position, 1);
    assert!(!questions[0].required);
    assert!(questions[0].breakdown.is_none());
    let text_answers = questions[0].text_answers.as_ref().unwrap();
    assert_eq!(text_answers.answers, vec!["More time".to_string()]);
    assert_eq!(text_answers.total, 3);

    // Check the select question carries its breakdown only
    assert_eq!(questions[1].kind, QuestionnaireQuestionKind::SingleSelect);
    assert_eq!(questions[1].question_id, Uuid::from_u128(2));
    assert!(questions[1].required);
    assert!(questions[1].text_answers.is_none());
    let breakdown = questions[1].breakdown.as_ref().unwrap();
    assert_eq!(breakdown.options[0].count, 2);
    assert_eq!(breakdown.respondents, 2);
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
    let surveys = vec![sample_summary(); MAX_EVENT_SURVEYS];

    assert!(EventSurveySummary::limit_reached(&surveys));
}

#[test]
fn test_event_survey_summary_limit_reached_below_survey_limit() {
    let surveys = vec![sample_summary(); MAX_EVENT_SURVEYS - 1];

    assert!(!EventSurveySummary::limit_reached(&surveys));
}

#[test]
fn test_event_survey_text_answers_filters_apply_default_bounds() {
    let filters: EventSurveyTextAnswersFilters = serde_qs::from_str("").unwrap();

    assert_eq!(
        filters.limit,
        Some(EVENT_SURVEY_TEXT_ANSWERS_PAGINATION_LIMIT)
    );
    assert_eq!(filters.offset, Some(0));
}

#[test]
fn test_event_survey_text_answers_filters_deserialize_blank_search_as_none() {
    let filters: EventSurveyTextAnswersFilters = serde_qs::from_str("ts_query=%20").unwrap();

    assert!(filters.ts_query.is_none());
}

#[test]
fn test_event_survey_text_answers_filters_reject_empty_pages() {
    let filters: EventSurveyTextAnswersFilters = serde_qs::from_str("limit=0").unwrap();

    assert!(filters.validate().is_err());
}

#[test]
fn test_event_survey_text_answers_filters_reject_limit_above_page_limit() {
    let filters = EventSurveyTextAnswersFilters {
        limit: Some(MAX_SURVEY_PAGE_LIMIT + 1),
        offset: None,
        ts_query: None,
    };

    assert!(filters.validate().is_err());
}

#[test]
fn test_event_survey_text_answers_filters_reject_long_search() {
    let filters = EventSurveyTextAnswersFilters {
        limit: None,
        offset: None,
        ts_query: Some("a".repeat(MAX_LEN_M + 1)),
    };

    assert!(filters.validate().is_err());
}

#[test]
fn test_event_survey_text_answers_output_deserializes_database_payload() {
    // Deserialize a page of answers matching a search
    let output: EventSurveyTextAnswersOutput = serde_json::from_value(json!({
        "answers": ["More breaks", "Longer breaks"],
        "position": 2,
        "prompt": "What should we improve?",
        "total": 12
    }))
    .unwrap();

    // Check the answers and the question they answer
    assert_eq!(
        output.answers,
        vec!["More breaks".to_string(), "Longer breaks".to_string()]
    );
    assert_eq!(output.position, 2);
    assert_eq!(output.prompt, "What should we improve?");
    assert_eq!(output.total, 12);
}

// Helpers.

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

/// Returns a summary of a draft survey.
fn sample_summary() -> EventSurveySummary {
    EventSurveySummary {
        anonymous: true,
        anonymous_locked: false,
        audience: EventSurveyAudience::Confirmed,
        closed_manually: false,
        eligible_count: 0,
        eligible_respondents_count: 0,
        event_survey_id: Uuid::from_u128(1),
        locked: false,
        questions_count: 0,
        responses_count: 0,
        revision: 1,
        state: EventSurveyState::Draft,
        title: "Feedback".to_string(),

        closes_at: None,
        effective_opens_at: None,
        open_notification_processed_at: None,
    }
}
