use askama::Template;
use chrono::{DateTime, Duration, TimeZone, Utc};
use chrono_tz::{Europe::Madrid, Tz};
use uuid::Uuid;

use crate::{
    test_util::normalize_whitespace,
    types::{
        dashboard::group::surveys::{
            EventSurveyFull, EventSurveyResponseFull, EventSurveyResponseNavigationFilters,
            EventSurveyResponseSummary, EventSurveyResponsesOutput, EventSurveyResults,
            EventSurveyResultsQuestion, EventSurveyStatusAction, EventSurveySummary,
            EventSurveyTextAnswers, EventSurveyTextAnswersFilters, EventSurveyTextAnswersOutput,
        },
        event::EventSummary,
        event_survey::{EventSurveyAudience, EventSurveyState},
        pagination::NavigationLinks,
        questionnaire::{QuestionnaireAnswers, QuestionnaireQuestionKind},
        tests::{
            sample_event_summary, sample_event_survey_full, sample_event_survey_summary,
            sample_user_summary,
        },
        user::UserSummary,
    },
    validation::MAX_EVENT_SURVEYS,
};

use super::{
    FEW_RESPONSES_THRESHOLD, FormPage, ListPage, MarkReadyBlocker, ResponseModal, ResponsesPage,
    ResultsPage, TextAnswersModal, answered_label, closes_label, few_anonymous_responses,
    format_date, mark_ready_blocker, opening_label, respondent_details, respondent_name,
    responses_label, status_action, text_answers_url, view_all_answers_label,
};

#[test]
fn test_answered_label_describes_answered_questions() {
    assert_eq!(answered_label(7, 10), "7 of 10");
    assert_eq!(answered_label(0, 1), "0 of 1");
}

#[test]
fn test_closes_label_formats_closing_date_in_event_timezone() {
    let cases = [
        (
            "closing date",
            Some(sample_date()),
            "May 10, 2099 11:00 AM CEST",
        ),
        ("no closing date", None, "No closing date"),
    ];

    for (case, closes_at, expected) in cases {
        let survey = EventSurveySummary {
            closes_at,
            ..sample_survey(EventSurveyState::Open)
        };

        assert_eq!(closes_label(&survey, Madrid), expected, "{case}");
    }
}

#[test]
fn test_few_anonymous_responses_matches_anonymous_surveys_below_threshold() {
    // (case, anonymous, responses_count, expected)
    let cases = [
        (
            "anonymous below threshold",
            true,
            FEW_RESPONSES_THRESHOLD - 1,
            true,
        ),
        (
            "anonymous at threshold",
            true,
            FEW_RESPONSES_THRESHOLD,
            false,
        ),
        ("anonymous without responses", true, 0, false),
        ("identified with one response", false, 1, false),
    ];

    for (case, anonymous, responses_count, expected) in cases {
        let survey = EventSurveySummary {
            anonymous,
            responses_count,
            ..sample_survey(EventSurveyState::Open)
        };

        assert_eq!(few_anonymous_responses(&survey), expected, "{case}");
    }
}

#[test]
fn test_form_page_defaults_new_surveys_to_anonymous_confirmed_attendees() {
    let page = sample_form_page(None);

    assert!(page.anonymous());
    assert!(!page.anonymous_locked());
    assert_eq!(page.audience(), EventSurveyAudience::Confirmed);
    assert_eq!(page.closes_at_value(), "");
    assert!(!page.locked());
    assert_eq!(page.opens_at_value(), "");
}

#[test]
fn test_form_page_keeps_anonymity_editable_for_opened_identified_surveys() {
    // Setup an opened identified survey without responses
    let mut survey = sample_event_survey_full(Uuid::from_u128(1));
    survey.summary.anonymous = false;
    survey.summary.state = EventSurveyState::Open;
    let page = sample_form_page(Some(survey));

    // Render the form
    let html = normalize_whitespace(&page.render().unwrap());

    // Check the anonymous toggle stays editable
    assert!(!page.anonymous_locked());
    assert!(html.contains(
        r#"<input id="event-survey-anonymous-toggle" type="checkbox" class="sr-only peer" data-event-survey-toggle="event-survey-anonymous" >"#
    ));
    assert!(!html.contains("data-event-survey-anonymous-locked-notice"));
}

#[test]
fn test_form_page_locks_anonymity_of_opened_anonymous_surveys() {
    // Setup an opened anonymous survey without responses
    let mut survey = sample_event_survey_full(Uuid::from_u128(1));
    survey.summary.anonymous_locked = true;
    survey.summary.state = EventSurveyState::Open;
    let page = sample_form_page(Some(survey));

    // Render the form
    let html = normalize_whitespace(&page.render().unwrap());

    // Check the toggle is read-only, explained, and its value still submitted
    assert!(page.anonymous_locked());
    assert!(!page.locked());
    assert!(html.contains(
        r#"data-event-survey-toggle="event-survey-anonymous" aria-describedby="event-survey-anonymous-locked-notice" checked disabled>"#
    ));
    assert!(html.contains(
        r#"<input type="hidden" id="event-survey-anonymous" name="anonymous" value="true">"#
    ));
    assert!(html.contains(r#"id="event-survey-anonymous-locked-notice""#));
    assert!(html.contains("data-event-survey-anonymous-locked-notice"));
    assert!(!html.contains("data-event-survey-locked-notice"));
}

#[test]
fn test_form_page_renders_dates_in_event_timezone() {
    // Setup a survey with a custom opening and a closing date
    let mut survey = sample_event_survey_full(Uuid::from_u128(1));
    survey.opens_at = Some(sample_date());
    survey.summary.closes_at = Some(sample_date() + Duration::days(7));
    let page = sample_form_page(Some(survey));

    // Check the datetime-local values use the event timezone
    assert_eq!(page.opens_at_value(), "2099-05-10T11:00");
    assert_eq!(page.closes_at_value(), "2099-05-17T11:00");
}

#[test]
fn test_form_page_renders_locked_fields_with_hidden_values() {
    // Setup a locked identified survey for checked-in attendees
    let mut survey = sample_event_survey_full(Uuid::from_u128(1));
    survey.summary.anonymous = false;
    survey.summary.audience = EventSurveyAudience::CheckedIn;
    survey.summary.locked = true;
    let page = sample_form_page(Some(survey));

    // Render the form
    let html = normalize_whitespace(&page.render().unwrap());

    // Check locked fields are disabled and their values travel as hidden inputs
    assert!(page.locked());
    assert!(html.contains("data-event-survey-locked-notice"));
    assert!(html.contains(
        r#"<input type="hidden" id="event-survey-anonymous" name="anonymous" value="false">"#
    ));
    assert!(html.contains(r#"<input type="hidden" name="audience" value="checked-in">"#));
    assert!(html.contains(r#"<input type="hidden" name="revision" value="3">"#));
    assert!(html.contains("data-event-survey-form"));
    assert!(!html.contains("data-event-form"));
}

#[test]
fn test_format_date_uses_event_timezone() {
    let timezone: Tz = "America/New_York".parse().unwrap();

    assert_eq!(
        format_date(sample_date(), timezone),
        "May 10, 2099 5:00 AM EDT"
    );
}

#[test]
fn test_list_page_limit_reached_matches_survey_limit() {
    let cases = [
        ("below the limit", MAX_EVENT_SURVEYS - 1, false),
        ("at the limit", MAX_EVENT_SURVEYS, true),
    ];

    for (case, surveys, expected) in cases {
        let page = sample_list_page(vec![sample_survey(EventSurveyState::Draft); surveys]);

        assert_eq!(page.limit_reached(), expected, "{case}");
    }
}

#[test]
fn test_list_page_renders_mark_ready_confirmation_contract() {
    // Setup a draft survey that opens on a future date
    let survey = EventSurveySummary {
        effective_opens_at: Some(sample_date()),
        event_survey_id: Uuid::from_u128(7),
        ..sample_survey(EventSurveyState::Draft)
    };
    let page = sample_list_page(vec![survey]);

    // Render the list
    let html = normalize_whitespace(&page.render().unwrap());

    // Check the confirmation carries the opening time and the revision
    let opens_at = sample_date().timestamp();
    assert!(html.contains(r#"id="event-survey-status-00000000-0000-0000-0000-000000000007""#));
    assert!(html.contains(r#"hx-trigger="confirmed""#));
    assert!(html.contains("data-confirm-action"));
    assert!(html.contains(r#"hx-disabled-elt="this""#));
    assert!(html.contains(&format!(
        "hx-vals=\"{{&#34;action&#34;:&#34;mark-ready&#34;,&#34;expected_effective_opens_at&#34;:&#34;{opens_at}&#34;,&#34;revision&#34;:&#34;3&#34;}}\""
    )));
    assert!(html.contains(
        "data-confirm-message=\"This will email eligible attendees (currently 40) on May 10, 2099 11:00 AM CEST.\""
    ));
}

#[test]
fn test_list_page_renders_count_header_and_opening_labels() {
    // Setup a scheduled survey and a draft of an event without dates
    let scheduled = EventSurveySummary {
        effective_opens_at: Some(sample_date()),
        ..sample_survey(EventSurveyState::Scheduled)
    };
    let draft = EventSurveySummary {
        event_survey_id: Uuid::from_u128(2),
        ..sample_survey(EventSurveyState::Draft)
    };
    let page = sample_list_page(vec![scheduled, draft]);

    // Render the list
    let html = normalize_whitespace(&page.render().unwrap());

    // Check the header, the survey count and the opening labels
    assert!(html.contains("/docs#/guides/event-operations?id=surveys"));
    assert!(html.contains(&format!("2 of {MAX_EVENT_SURVEYS} surveys")));
    assert!(html.contains("Opens May 10, 2099 11:00 AM CEST"));
    assert!(html.contains("Opens once the event has a date"));
}

#[test]
fn test_list_page_renders_mark_ready_blocker_instead_of_opening_label() {
    // Setup a draft survey whose closing date has passed
    let survey = EventSurveySummary {
        closes_at: Some(sample_now() - Duration::hours(1)),
        effective_opens_at: Some(sample_now() - Duration::days(1)),
        ..sample_survey(EventSurveyState::Draft)
    };
    let page = sample_list_page(vec![survey]);

    // Render the list
    let html = normalize_whitespace(&page.render().unwrap());

    // Check the hint is shown in the state badge tooltip instead of the opening label
    assert!(html.contains(r#"aria-describedby="event-survey-state-details-"#));
    assert!(html.contains("Cannot mark ready"));
    assert!(html.contains(r#"<span class="block text-stone-900">Closing date has passed</span>"#));
    assert!(!html.contains("Opens when marked ready"));

    // Check Mark ready is disabled with the reason
    assert!(html.contains(r#"disabled title="Edit the closing date to mark the survey ready.""#));
}

#[test]
fn test_list_page_without_manage_permission_disables_mutation_controls() {
    // Setup a read-only list
    let mut page = sample_list_page(vec![sample_survey(EventSurveyState::Open)]);
    page.can_manage_surveys = false;

    // Render the list
    let html = normalize_whitespace(&page.render().unwrap());

    // Check results, the CSV and the read-only form stay available
    assert!(html.contains("/results\""));
    assert!(html.contains("/responses.csv\""));
    assert!(html.contains("/update\""));

    // Check add, status and delete are disabled with the role reason
    assert!(html.contains("add-event-survey-button"));
    assert!(html.contains("event-survey-status-"));
    assert!(html.contains("delete-event-survey-"));
    assert_eq!(
        html.matches(r#"disabled title="Your role cannot add, update or delete surveys.""#)
            .count(),
        3
    );
}

#[test]
fn test_mark_ready_blocker_matches_draft_schedule() {
    use MarkReadyBlocker::{ClosesBeforeOpening, ClosingDatePassed, NoQuestions};

    let past = sample_now() - Duration::hours(1);
    // (case, survey, expected Option<(blocker, hint, reason)>)
    let cases = [
        (
            "valid schedule",
            EventSurveySummary {
                closes_at: Some(sample_date() + Duration::days(1)),
                effective_opens_at: Some(sample_date()),
                ..sample_survey(EventSurveyState::Draft)
            },
            None,
        ),
        (
            "no closing date",
            sample_survey(EventSurveyState::Draft),
            None,
        ),
        (
            "not a draft",
            EventSurveySummary {
                closes_at: Some(past),
                questions_count: 0,
                ..sample_survey(EventSurveyState::Closed)
            },
            None,
        ),
        (
            "closing date in the past",
            EventSurveySummary {
                closes_at: Some(past),
                ..sample_survey(EventSurveyState::Draft)
            },
            Some((
                ClosingDatePassed,
                "Closing date has passed",
                "Edit the closing date to mark the survey ready.",
            )),
        ),
        (
            "closing exactly at render time",
            EventSurveySummary {
                closes_at: Some(sample_now()),
                ..sample_survey(EventSurveyState::Draft)
            },
            Some((
                ClosingDatePassed,
                "Closing date has passed",
                "Edit the closing date to mark the survey ready.",
            )),
        ),
        (
            "closing at the opening",
            EventSurveySummary {
                closes_at: Some(sample_date()),
                effective_opens_at: Some(sample_date()),
                ..sample_survey(EventSurveyState::Draft)
            },
            Some((
                ClosesBeforeOpening,
                "Closes before it opens",
                "Edit the closing date so it is after the survey opens.",
            )),
        ),
        (
            "no questions takes precedence over a past closing date",
            EventSurveySummary {
                closes_at: Some(past),
                questions_count: 0,
                ..sample_survey(EventSurveyState::Draft)
            },
            Some((
                NoQuestions,
                "No questions yet",
                "Add a question before marking the survey ready.",
            )),
        ),
    ];

    for (case, survey, expected) in cases {
        let blocker = mark_ready_blocker(&survey, sample_now());

        assert_eq!(blocker, expected.map(|(blocker, _, _)| blocker), "{case}");
        if let (Some(blocker), Some((_, hint, reason))) = (blocker, expected) {
            assert_eq!(blocker.hint(), hint, "{case}: hint");
            assert_eq!(blocker.reason(), reason, "{case}: reason");
        }
    }
}

#[test]
fn test_opening_label_describes_survey_opening() {
    let past = Some(sample_now() - Duration::days(1));
    // (case, state, effective_opens_at, published, expected)
    let cases = [
        (
            "future opening",
            EventSurveyState::Scheduled,
            Some(sample_date()),
            true,
            "Opens May 10, 2099 11:00 AM CEST",
        ),
        (
            "event without dates",
            EventSurveyState::Draft,
            None,
            true,
            "Opens once the event has a date",
        ),
        (
            "past scheduled opening",
            EventSurveyState::Scheduled,
            past,
            true,
            "Opens now",
        ),
        (
            "past draft opening",
            EventSurveyState::Draft,
            past,
            true,
            "Opens when marked ready",
        ),
        (
            "past draft opening of an unpublished event",
            EventSurveyState::Draft,
            past,
            false,
            "Opens once the event is published",
        ),
        (
            "past scheduled opening of an unpublished event",
            EventSurveyState::Scheduled,
            past,
            false,
            "Opens once the event is published",
        ),
    ];

    for (case, state, effective_opens_at, published, expected) in cases {
        let mut event = sample_event();
        event.published = published;
        let survey = EventSurveySummary {
            effective_opens_at,
            ..sample_survey(state)
        };

        assert_eq!(
            opening_label(&survey, &event, sample_now()),
            expected,
            "{case}"
        );
    }
}

#[test]
fn test_respondent_details_joins_title_and_company() {
    let mut user = sample_user();
    user.company = Some("Example Corp".to_string());
    user.title = Some("Engineer".to_string());

    assert_eq!(
        respondent_details(&user).as_deref(),
        Some("Engineer · Example Corp")
    );
}

#[test]
fn test_respondent_details_keeps_the_available_detail() {
    let mut with_company = sample_user();
    with_company.company = Some("Example Corp".to_string());
    let mut with_title = sample_user();
    with_title.title = Some("Engineer".to_string());

    assert_eq!(
        respondent_details(&with_company).as_deref(),
        Some("Example Corp")
    );
    assert_eq!(respondent_details(&with_title).as_deref(), Some("Engineer"));
    assert!(respondent_details(&sample_user()).is_none());
}

#[test]
fn test_respondent_name_falls_back_to_username() {
    let mut named = sample_user();
    named.name = Some("Jane Doe".to_string());

    assert_eq!(respondent_name(&named), "Jane Doe");
    assert_eq!(respondent_name(&sample_user()), "jane");
}

#[test]
fn test_response_modal_links_neighbors_keeping_search() {
    // Setup a response between two respondents matching a search
    let modal = ResponseModal {
        event: sample_event(),
        navigation_filters: EventSurveyResponseNavigationFilters {
            ts_query: Some("jane".to_string()),
        },
        response: EventSurveyResponseFull {
            answers: QuestionnaireAnswers::default(),
            position: 2,
            summary: sample_respondent(),
            total: 3,

            next_user_id: Some(Uuid::from_u128(7)),
            previous_user_id: Some(Uuid::from_u128(6)),
        },
        survey: sample_event_survey_full(Uuid::from_u128(2)),
    };

    // Check the neighbors link to their responses keeping the search
    let base_url = "/dashboard/group/events/00000000-0000-0000-0000-000000000001/surveys/00000000-0000-0000-0000-000000000002/responses";
    assert_eq!(
        modal.next_url().unwrap(),
        Some(format!(
            "{base_url}/00000000-0000-0000-0000-000000000007?ts_query=jane"
        ))
    );
    assert_eq!(
        modal.previous_url().unwrap(),
        Some(format!(
            "{base_url}/00000000-0000-0000-0000-000000000006?ts_query=jane"
        ))
    );
}

#[test]
fn test_response_modal_without_neighbors_has_no_links() {
    let modal = ResponseModal {
        event: sample_event(),
        navigation_filters: EventSurveyResponseNavigationFilters::default(),
        response: EventSurveyResponseFull {
            answers: QuestionnaireAnswers::default(),
            position: 1,
            summary: sample_respondent(),
            total: 1,

            next_user_id: None,
            previous_user_id: None,
        },
        survey: sample_event_survey_full(Uuid::from_u128(2)),
    };

    assert!(modal.next_url().unwrap().is_none());
    assert!(modal.previous_url().unwrap().is_none());
}

#[test]
fn test_responses_label_describes_eligible_responses() {
    // (case, eligible_count, eligible_respondents_count, responses_count, expected)
    let cases = [
        ("eligible respondents and rate", 40, 12, 12, "12 / 40 (30%)"),
        (
            "stored total differs",
            40,
            12,
            14,
            "12 / 40 (30%) · 14 total",
        ),
        ("nobody eligible", 0, 0, 0, "-"),
        ("nobody eligible with responses", 0, 0, 3, "- · 3 total"),
    ];

    for (case, eligible_count, eligible_respondents_count, responses_count, expected) in cases {
        let survey = EventSurveySummary {
            eligible_count,
            eligible_respondents_count,
            responses_count,
            ..sample_survey(EventSurveyState::Open)
        };

        assert_eq!(responses_label(&survey), expected, "{case}");
    }
}

#[test]
fn test_responses_page_response_url_keeps_search() {
    let page = sample_responses_page(Some("jane doe"));

    assert_eq!(
        page.response_url(&Uuid::from_u128(5)).unwrap(),
        "/dashboard/group/events/00000000-0000-0000-0000-000000000001/surveys/00000000-0000-0000-0000-000000000002/responses/00000000-0000-0000-0000-000000000005?ts_query=jane+doe"
    );
}

#[test]
fn test_responses_page_response_url_without_search() {
    let page = sample_responses_page(None);

    assert_eq!(
        page.response_url(&Uuid::from_u128(5)).unwrap(),
        "/dashboard/group/events/00000000-0000-0000-0000-000000000001/surveys/00000000-0000-0000-0000-000000000002/responses/00000000-0000-0000-0000-000000000005"
    );
}

#[test]
fn test_results_page_renders_overview_cards_and_question_sections() {
    // Setup the results of an identified checked-in survey with one free-text question
    let question_id = Uuid::from_u128(9);
    let page = ResultsPage {
        event: sample_event(),
        results: EventSurveyResults {
            questions: vec![EventSurveyResultsQuestion {
                kind: QuestionnaireQuestionKind::FreeText,
                position: 1,
                prompt: "What should we improve?".to_string(),
                question_id,
                required: false,

                breakdown: None,
                text_answers: Some(EventSurveyTextAnswers {
                    answers: vec!["More breaks".to_string()],
                    total: 3,
                }),
            }],
            survey: EventSurveySummary {
                anonymous: false,
                audience: EventSurveyAudience::CheckedIn,
                closes_at: Some(sample_date()),
                ..sample_survey(EventSurveyState::Open)
            },
        },
    };

    // Render the results
    let html = normalize_whitespace(&page.render().unwrap());

    // Check the title heading and the overview cards
    assert!(html.contains("<h2"));
    assert!(html.contains("Eligible attendees who answered"));
    assert!(html.contains("Checked-in attendees"));
    assert!(html.contains("Identified responses"));
    assert!(html.contains("May 10, 2099 11:00 AM CEST"));
    assert!(html.contains("Shown in the event timezone"));

    // Check the question section is labelled by its heading
    let answers_id = format!("event-survey-question-{question_id}-answers");
    assert!(html.contains(&format!(r#"aria-labelledby="{answers_id}-prompt""#)));
    assert!(html.contains(&format!(r#"<h3 id="{answers_id}-prompt""#)));

    // Check the compact preview and the button opening every answer in the modal
    assert!(html.contains("data-event-survey-text-answers-preview"));
    assert!(html.contains("line-clamp-3"));
    assert!(html.contains("Showing 1 of 3 answers"));
    assert!(html.contains(&format!(
        r#"hx-get="{}""#,
        text_answers_url(Uuid::from_u128(1), Uuid::from_u128(1), question_id)
    )));
    assert!(html.contains(r##"hx-target="#event-survey-text-answers-modal-content""##));
    assert!(html.contains("View all 3 answers"));
    assert!(html.contains(r#"aria-label="View all 3 answers: What should we improve?""#));
    assert!(!html.contains("Show more"));

    // Check the answers modal shell
    assert!(html.contains(r#"id="event-survey-text-answers-modal""#));
    assert!(html.contains(r#"aria-labelledby="event-survey-text-answers-modal-title""#));
}

#[test]
fn test_status_action_back_to_draft_for_scheduled_surveys() {
    let survey = EventSurveySummary {
        responses_count: 0,
        ..sample_survey(EventSurveyState::Scheduled)
    };

    let action = status_action(&survey, &sample_event(), sample_now());

    assert_eq!(action.action, EventSurveyStatusAction::BackToDraft);
    assert_eq!(action.icon, "undo");
    assert_eq!(
        action.request_values,
        r#"{"action":"back-to-draft","revision":"3"}"#
    );
    assert_eq!(action.disabled_reason, None);
}

#[test]
fn test_status_action_back_to_draft_disabled_reasons() {
    // (case, open_notification_processed_at, responses_count, expected)
    let cases = [
        ("not emailed and no responses", None, 0, None),
        (
            "opening email sent",
            Some(sample_now()),
            0,
            Some("The opening email was already sent."),
        ),
        (
            "survey has responses",
            None,
            1,
            Some("The survey already has responses."),
        ),
        (
            "opening email sent and survey has responses",
            Some(sample_now()),
            1,
            Some("The opening email was already sent."),
        ),
    ];

    for (case, open_notification_processed_at, responses_count, expected) in cases {
        let survey = EventSurveySummary {
            responses_count,
            open_notification_processed_at,
            ..sample_survey(EventSurveyState::Scheduled)
        };

        let action = status_action(&survey, &sample_event(), sample_now());

        assert_eq!(
            action.action,
            EventSurveyStatusAction::BackToDraft,
            "{case}"
        );
        assert_eq!(action.disabled_reason, expected, "{case}");
    }
}

#[test]
fn test_status_action_close_for_open_surveys() {
    let action = status_action(
        &sample_survey(EventSurveyState::Open),
        &sample_event(),
        sample_now(),
    );

    assert_eq!(action.action, EventSurveyStatusAction::Close);
    assert_eq!(action.label, "Close");
    assert_eq!(
        action.confirm_message,
        "Close this survey? Attendees will no longer be able to answer or edit their answers."
    );
    assert_eq!(action.disabled_reason, None);
}

#[test]
fn test_status_action_mark_ready_confirms_when_attendees_are_emailed() {
    let opens_at = sample_date().timestamp().to_string();
    let mut unpublished = sample_event();
    unpublished.published = false;
    let mut test_event = sample_event();
    test_event.test_event = true;
    // (case, effective_opens_at, event, confirm_message, expected_effective_opens_at)
    let cases = [
        (
            "past opening",
            Some(sample_now() - Duration::days(1)),
            sample_event(),
            "This will email eligible attendees (currently 40) now.",
            (sample_now() - Duration::days(1)).timestamp().to_string(),
        ),
        (
            "future opening",
            Some(sample_date()),
            sample_event(),
            "This will email eligible attendees (currently 40) on May 10, 2099 11:00 AM CEST.",
            opens_at.clone(),
        ),
        (
            "past opening of an unpublished event",
            Some(sample_now() - Duration::days(1)),
            unpublished,
            "This will email eligible attendees (currently 40) once the event is published.",
            (sample_now() - Duration::days(1)).timestamp().to_string(),
        ),
        (
            "future opening of a test event",
            Some(sample_date()),
            test_event,
            "Mark this survey ready? Test events do not email attendees.",
            opens_at,
        ),
        (
            "event without dates",
            None,
            sample_event(),
            "This will email eligible attendees (currently 40) once the event has a date and ends.",
            String::new(),
        ),
    ];

    for (case, effective_opens_at, event, confirm_message, expected_effective_opens_at) in cases {
        let survey = EventSurveySummary {
            effective_opens_at,
            ..sample_survey(EventSurveyState::Draft)
        };

        let action = status_action(&survey, &event, sample_now());

        assert_eq!(action.action, EventSurveyStatusAction::MarkReady, "{case}");
        assert_eq!(action.confirm_message, confirm_message, "{case}");
        assert_eq!(
            action.request_values,
            format!(
                r#"{{"action":"mark-ready","expected_effective_opens_at":"{expected_effective_opens_at}","revision":"3"}}"#
            ),
            "{case}"
        );
        assert_eq!(action.disabled_reason, None, "{case}");
    }
}

#[test]
fn test_status_action_mark_ready_unavailable_after_closing_date() {
    let survey = EventSurveySummary {
        closes_at: Some(sample_now() - Duration::hours(1)),
        ..sample_survey(EventSurveyState::Draft)
    };

    let action = status_action(&survey, &sample_event(), sample_now());

    assert_eq!(
        action.disabled_reason,
        Some("Edit the closing date to mark the survey ready.")
    );
}

#[test]
fn test_status_action_reopen_for_manually_closed_surveys() {
    let survey = EventSurveySummary {
        closed_manually: true,
        closes_at: Some(sample_date()),
        ..sample_survey(EventSurveyState::Closed)
    };

    let action = status_action(&survey, &sample_event(), sample_now());

    assert_eq!(action.action, EventSurveyStatusAction::Reopen);
    assert_eq!(
        action.confirm_message,
        "Reopen this survey? Attendees will be able to answer it again. No new email is sent."
    );
    assert_eq!(action.disabled_reason, None);
}

#[test]
fn test_status_action_reopen_unavailable_after_closing_date() {
    let survey = EventSurveySummary {
        closes_at: Some(sample_now() - Duration::hours(1)),
        ..sample_survey(EventSurveyState::Closed)
    };

    let action = status_action(&survey, &sample_event(), sample_now());

    assert_eq!(action.action, EventSurveyStatusAction::Reopen);
    assert_eq!(
        action.disabled_reason,
        Some("Edit the closing date to reopen.")
    );
}

#[test]
fn test_text_answers_modal_links_pages_keeping_search() {
    // Setup the second page of answers matching a search
    let modal = sample_text_answers_modal(Some(10), 10, 25, Some("breaks"));

    // Render the modal content
    let html = normalize_whitespace(&modal.render().unwrap());

    // Check the header, the search and the range
    assert!(html.contains(r#"<h3 id="event-survey-text-answers-modal-title""#));
    assert!(html.contains("What should we improve?"));
    assert!(html.contains("Question 3 · Free-text answers"));
    assert!(html.contains(r#"id="event-survey-text-answers-search" name="ts_query""#));
    assert!(html.contains(r#"value="breaks""#));
    assert!(html.contains("11 - 20 of <span class=\"font-semibold\">25</span> answers"));
    assert!(html.contains("Answer 0"));
    assert!(html.contains("Answer 9"));

    // Check both neighbors load into the modal keeping the search
    let url = modal.answers_url();
    assert!(html.contains(&format!(
        r#"hx-get="{url}?limit=10&#38;offset=0&#38;ts_query=breaks""#
    )));
    assert!(html.contains(&format!(
        r#"hx-get="{url}?limit=10&#38;offset=20&#38;ts_query=breaks""#
    )));
    assert!(html.contains(r#"data-event-survey-text-answers-nav="previous" data-htmx-response"#));
    assert!(html.contains(r#"data-event-survey-text-answers-nav="next" data-htmx-response"#));
}

#[test]
fn test_text_answers_modal_renders_search_without_matches() {
    // Setup a search without matching answers
    let modal = sample_text_answers_modal(None, 0, 0, Some("missing"));

    // Render the modal content
    let html = normalize_whitespace(&modal.render().unwrap());

    // Check the empty search state and the disabled navigation
    assert!(html.contains("No answers found matching your search."));
    assert!(html.contains("0 answers"));
    assert!(html.contains(r#"disabled data-event-survey-text-answers-nav="previous""#));
    assert!(html.contains(r#"disabled data-event-survey-text-answers-nav="next""#));
}

#[test]
fn test_text_answers_modal_without_search_or_answers() {
    let modal = sample_text_answers_modal(None, 0, 0, None);

    let html = modal.render().unwrap();

    assert!(html.contains("No answers yet."));
    assert!(!html.contains("No answers found matching your search."));
}

#[test]
fn test_text_answers_url_points_to_question_answers() {
    assert_eq!(
        text_answers_url(Uuid::from_u128(1), Uuid::from_u128(2), Uuid::from_u128(3)),
        "/dashboard/group/events/00000000-0000-0000-0000-000000000001/surveys/00000000-0000-0000-0000-000000000002/results/questions/00000000-0000-0000-0000-000000000003/answers"
    );
}

#[test]
fn test_view_all_answers_label_counts_answers() {
    assert_eq!(view_all_answers_label(1), "View 1 answer");
    assert_eq!(view_all_answers_label(12), "View all 12 answers");
    assert_eq!(view_all_answers_label(1234), "View all 1,234 answers");
}

// Helpers.

/// Returns a fixed future date used by the survey dates.
fn sample_date() -> DateTime<Utc> {
    Utc.with_ymd_and_hms(2099, 5, 10, 9, 0, 0).unwrap()
}

/// Returns an event in Madrid that is not a test event.
fn sample_event() -> EventSummary {
    let mut event = sample_event_summary(Uuid::from_u128(1));
    event.test_event = false;
    event.timezone = Madrid;
    event
}

/// Returns a form page of an event in Madrid.
fn sample_form_page(survey: Option<EventSurveyFull>) -> FormPage {
    FormPage {
        can_manage_surveys: true,
        event: sample_event(),

        survey,
    }
}

/// Returns a list page of an event in Madrid that the user can manage.
fn sample_list_page(surveys: Vec<EventSurveySummary>) -> ListPage {
    ListPage {
        can_manage_surveys: true,
        event: sample_event(),
        now: sample_now(),
        surveys,
    }
}

/// Returns a respondent without a ticket or edits.
fn sample_respondent() -> EventSurveyResponseSummary {
    EventSurveyResponseSummary {
        answered_questions_count: 1,
        created_at: sample_date(),
        user: sample_user(),

        ticket_title: None,
        updated_at: None,
    }
}

/// Returns a respondents page of an identified survey with one respondent.
fn sample_responses_page(ts_query: Option<&str>) -> ResponsesPage {
    let mut survey = sample_event_survey_full(Uuid::from_u128(2));
    survey.summary.anonymous = false;
    ResponsesPage {
        event: sample_event(),
        navigation_links: NavigationLinks::default(),
        navigation_filters: EventSurveyResponseNavigationFilters {
            ts_query: ts_query.map(str::to_string),
        },
        responses: EventSurveyResponsesOutput {
            responses: vec![sample_respondent()],
            total: 1,
        },
        survey,

        offset: None,
        ts_query: None,
    }
}

/// Returns the fixed time the pages are rendered at.
fn sample_now() -> DateTime<Utc> {
    Utc.with_ymd_and_hms(2099, 5, 1, 12, 0, 0).unwrap()
}

/// Returns a survey summary in the given state.
fn sample_survey(state: EventSurveyState) -> EventSurveySummary {
    sample_event_survey_summary(Uuid::from_u128(1), state)
}

/// Returns the answers modal of the third question showing a page of
/// free-text answers.
fn sample_text_answers_modal(
    offset: Option<usize>,
    answers: usize,
    total: usize,
    ts_query: Option<&str>,
) -> TextAnswersModal {
    // Setup the filters of the requested page
    let filters = EventSurveyTextAnswersFilters {
        limit: Some(10),
        offset,
        ts_query: ts_query.map(str::to_string),
    };
    let url = text_answers_url(Uuid::from_u128(1), Uuid::from_u128(2), Uuid::from_u128(3));

    // Build the modal with its page links
    TextAnswersModal {
        answers: EventSurveyTextAnswersOutput {
            answers: (0..answers).map(|index| format!("Answer {index}")).collect(),
            position: 3,
            prompt: "What should we improve?".to_string(),
            total,
        },
        event_id: Uuid::from_u128(1),
        event_survey_id: Uuid::from_u128(2),
        navigation_links: NavigationLinks::from_filters(&filters, total, &url, &url).unwrap(),
        question_id: Uuid::from_u128(3),

        offset,
        ts_query: filters.ts_query,
    }
}

/// Returns a respondent with only a username.
fn sample_user() -> UserSummary {
    sample_user_summary(Uuid::from_u128(4), "jane")
}
