use askama::Template;
use chrono::{DateTime, Duration, TimeZone, Utc};
use chrono_tz::{Europe::Madrid, Tz};
use uuid::Uuid;

use crate::{
    types::{
        dashboard::group::surveys::{
            EventSurveyFull, EventSurveyResults, EventSurveyResultsQuestion,
            EventSurveyStatusAction, EventSurveySummary, EventSurveyTextAnswers,
        },
        event::EventSummary,
        event_survey::{EventSurveyAudience, EventSurveyState},
        questionnaire::QuestionnaireQuestionKind,
        tests::{sample_event_summary, sample_event_survey_full, sample_event_survey_summary},
    },
    validation::MAX_EVENT_SURVEYS,
};

use super::{
    FEW_RESPONSES_THRESHOLD, FormPage, ListPage, MarkReadyBlocker, ResultsPage, TextAnswersPage,
    closes_label, few_anonymous_responses, format_date, mark_ready_blocker, opening_label,
    responses_label, status_action,
};

#[test]
fn test_closes_label_formats_closing_date_in_event_timezone() {
    let survey = EventSurveySummary {
        closes_at: Some(sample_date()),
        ..sample_survey(EventSurveyState::Open)
    };

    assert_eq!(closes_label(&survey, Madrid), "May 10, 2099 11:00 AM CEST");
}

#[test]
fn test_closes_label_without_closing_date() {
    let survey = sample_survey(EventSurveyState::Open);

    assert_eq!(closes_label(&survey, Madrid), "No closing date");
}

#[test]
fn test_few_anonymous_responses_ignores_identified_surveys() {
    let survey = EventSurveySummary {
        anonymous: false,
        responses_count: 1,
        ..sample_survey(EventSurveyState::Open)
    };

    assert!(!few_anonymous_responses(&survey));
}

#[test]
fn test_few_anonymous_responses_ignores_surveys_without_responses() {
    let survey = EventSurveySummary {
        responses_count: 0,
        ..sample_survey(EventSurveyState::Open)
    };

    assert!(!few_anonymous_responses(&survey));
}

#[test]
fn test_few_anonymous_responses_matches_anonymous_surveys_below_threshold() {
    let below = EventSurveySummary {
        responses_count: FEW_RESPONSES_THRESHOLD - 1,
        ..sample_survey(EventSurveyState::Open)
    };
    let at_threshold = EventSurveySummary {
        responses_count: FEW_RESPONSES_THRESHOLD,
        ..sample_survey(EventSurveyState::Open)
    };

    assert!(few_anonymous_responses(&below));
    assert!(!few_anonymous_responses(&at_threshold));
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
fn test_list_page_limit_reached_at_survey_limit() {
    let page = sample_list_page(vec![
        sample_survey(EventSurveyState::Draft);
        MAX_EVENT_SURVEYS
    ]);

    assert!(page.limit_reached());
}

#[test]
fn test_list_page_limit_reached_below_survey_limit() {
    let page = sample_list_page(vec![
        sample_survey(EventSurveyState::Draft);
        MAX_EVENT_SURVEYS - 1
    ]);

    assert!(!page.limit_reached());
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
fn test_mark_ready_blocker_allows_drafts_with_a_valid_schedule() {
    let survey = EventSurveySummary {
        closes_at: Some(sample_date() + Duration::days(1)),
        effective_opens_at: Some(sample_date()),
        ..sample_survey(EventSurveyState::Draft)
    };

    assert_eq!(mark_ready_blocker(&survey, sample_now()), None);
}

#[test]
fn test_mark_ready_blocker_ignores_surveys_that_are_not_drafts() {
    let survey = EventSurveySummary {
        closes_at: Some(sample_now() - Duration::hours(1)),
        questions_count: 0,
        ..sample_survey(EventSurveyState::Closed)
    };

    assert_eq!(mark_ready_blocker(&survey, sample_now()), None);
}

#[test]
fn test_mark_ready_blocker_rejects_closing_dates_in_the_past() {
    // Setup drafts closing before and exactly at the render time
    let closed = EventSurveySummary {
        closes_at: Some(sample_now() - Duration::hours(1)),
        ..sample_survey(EventSurveyState::Draft)
    };
    let closing = EventSurveySummary {
        closes_at: Some(sample_now()),
        ..sample_survey(EventSurveyState::Draft)
    };

    // Check both are blocked by the closing date
    assert_eq!(
        mark_ready_blocker(&closed, sample_now()),
        Some(MarkReadyBlocker::ClosingDatePassed)
    );
    assert_eq!(
        mark_ready_blocker(&closing, sample_now()),
        Some(MarkReadyBlocker::ClosingDatePassed)
    );
}

#[test]
fn test_mark_ready_blocker_rejects_closing_dates_before_the_opening() {
    let survey = EventSurveySummary {
        closes_at: Some(sample_date()),
        effective_opens_at: Some(sample_date()),
        ..sample_survey(EventSurveyState::Draft)
    };

    assert_eq!(
        mark_ready_blocker(&survey, sample_now()),
        Some(MarkReadyBlocker::ClosesBeforeOpening)
    );
}

#[test]
fn test_mark_ready_blocker_rejects_drafts_without_questions() {
    let survey = EventSurveySummary {
        closes_at: Some(sample_now() - Duration::hours(1)),
        questions_count: 0,
        ..sample_survey(EventSurveyState::Draft)
    };

    assert_eq!(
        mark_ready_blocker(&survey, sample_now()),
        Some(MarkReadyBlocker::NoQuestions)
    );
}

#[test]
fn test_opening_label_describes_future_and_unknown_openings() {
    // Setup surveys opening in the future and without event dates
    let scheduled = EventSurveySummary {
        effective_opens_at: Some(sample_date()),
        ..sample_survey(EventSurveyState::Scheduled)
    };
    let undated = sample_survey(EventSurveyState::Draft);

    // Check each label in the event timezone
    assert_eq!(
        opening_label(&scheduled, &sample_event(), sample_now()),
        "Opens May 10, 2099 11:00 AM CEST"
    );
    assert_eq!(
        opening_label(&undated, &sample_event(), sample_now()),
        "Opens once the event has a date"
    );
}

#[test]
fn test_opening_label_opens_now_for_past_scheduled_openings() {
    let survey = EventSurveySummary {
        effective_opens_at: Some(sample_now() - Duration::days(1)),
        ..sample_survey(EventSurveyState::Scheduled)
    };

    assert_eq!(
        opening_label(&survey, &sample_event(), sample_now()),
        "Opens now"
    );
}

#[test]
fn test_opening_label_waits_for_mark_ready_on_past_draft_openings() {
    let survey = EventSurveySummary {
        effective_opens_at: Some(sample_now() - Duration::days(1)),
        ..sample_survey(EventSurveyState::Draft)
    };

    assert_eq!(
        opening_label(&survey, &sample_event(), sample_now()),
        "Opens when marked ready"
    );
}

#[test]
fn test_opening_label_waits_for_publication_on_past_openings() {
    // Setup draft and scheduled surveys of an unpublished event
    let mut event = sample_event();
    event.published = false;
    let draft = EventSurveySummary {
        effective_opens_at: Some(sample_now() - Duration::days(1)),
        ..sample_survey(EventSurveyState::Draft)
    };
    let scheduled = EventSurveySummary {
        effective_opens_at: Some(sample_now() - Duration::days(1)),
        ..sample_survey(EventSurveyState::Scheduled)
    };

    // Check both wait for the event to be published
    assert_eq!(
        opening_label(&draft, &event, sample_now()),
        "Opens once the event is published"
    );
    assert_eq!(
        opening_label(&scheduled, &event, sample_now()),
        "Opens once the event is published"
    );
}

#[test]
fn test_responses_label_adds_stored_total_when_it_differs() {
    let survey = EventSurveySummary {
        responses_count: 14,
        ..sample_survey(EventSurveyState::Open)
    };

    assert_eq!(responses_label(&survey), "12 / 40 (30%) · 14 total");
}

#[test]
fn test_responses_label_shows_dash_when_nobody_is_eligible() {
    let survey = EventSurveySummary {
        eligible_count: 0,
        eligible_respondents_count: 0,
        responses_count: 0,
        ..sample_survey(EventSurveyState::Open)
    };
    let survey_with_responses = EventSurveySummary {
        responses_count: 3,
        ..survey.clone()
    };

    assert_eq!(responses_label(&survey), "-");
    assert_eq!(responses_label(&survey_with_responses), "- · 3 total");
}

#[test]
fn test_responses_label_shows_eligible_respondents_and_rate() {
    let survey = sample_survey(EventSurveyState::Open);

    assert_eq!(responses_label(&survey), "12 / 40 (30%)");
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
    assert!(html.contains("Show more answers (2 left)"));
    assert!(html.contains("Something went wrong loading more answers."));
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
fn test_status_action_back_to_draft_unavailable_after_opening_email() {
    let survey = EventSurveySummary {
        open_notification_processed_at: Some(sample_now()),
        responses_count: 0,
        ..sample_survey(EventSurveyState::Scheduled)
    };

    let action = status_action(&survey, &sample_event(), sample_now());

    assert_eq!(
        action.disabled_reason,
        Some("The opening email was already sent.")
    );
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
fn test_status_action_mark_ready_now_for_past_openings() {
    let survey = EventSurveySummary {
        effective_opens_at: Some(sample_now() - Duration::days(1)),
        ..sample_survey(EventSurveyState::Draft)
    };

    let action = status_action(&survey, &sample_event(), sample_now());

    assert_eq!(
        action.confirm_message,
        "This will email eligible attendees (currently 40) now."
    );
}

#[test]
fn test_status_action_mark_ready_on_future_opening_date() {
    // Setup a draft survey opening in the future
    let survey = EventSurveySummary {
        effective_opens_at: Some(sample_date()),
        ..sample_survey(EventSurveyState::Draft)
    };

    // Describe its status action
    let action = status_action(&survey, &sample_event(), sample_now());

    // Check the confirmation and the confirmed opening sent with the request
    assert_eq!(action.action, EventSurveyStatusAction::MarkReady);
    assert_eq!(
        action.confirm_message,
        "This will email eligible attendees (currently 40) on May 10, 2099 11:00 AM CEST."
    );
    assert_eq!(
        action.request_values,
        format!(
            r#"{{"action":"mark-ready","expected_effective_opens_at":"{}","revision":"3"}}"#,
            sample_date().timestamp()
        )
    );
    assert_eq!(action.disabled_reason, None);
}

#[test]
fn test_status_action_mark_ready_once_event_is_published() {
    // Setup a draft survey of an unpublished event with a past opening
    let mut event = sample_event();
    event.published = false;
    let survey = EventSurveySummary {
        effective_opens_at: Some(sample_now() - Duration::days(1)),
        ..sample_survey(EventSurveyState::Draft)
    };

    // Describe its status action
    let action = status_action(&survey, &event, sample_now());

    // Check the confirmation waits for the publication
    assert_eq!(
        action.confirm_message,
        "This will email eligible attendees (currently 40) once the event is published."
    );
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
fn test_status_action_mark_ready_unavailable_when_closing_before_opening() {
    let survey = EventSurveySummary {
        closes_at: Some(sample_date()),
        effective_opens_at: Some(sample_date() + Duration::hours(1)),
        ..sample_survey(EventSurveyState::Draft)
    };

    let action = status_action(&survey, &sample_event(), sample_now());

    assert_eq!(
        action.disabled_reason,
        Some("Edit the closing date so it is after the survey opens.")
    );
}

#[test]
fn test_status_action_mark_ready_unavailable_without_questions() {
    let survey = EventSurveySummary {
        questions_count: 0,
        ..sample_survey(EventSurveyState::Draft)
    };

    let action = status_action(&survey, &sample_event(), sample_now());

    assert_eq!(
        action.disabled_reason,
        Some("Add a question before marking the survey ready.")
    );
}

#[test]
fn test_status_action_mark_ready_on_test_events() {
    // Setup a draft survey of a test event opening in the future
    let survey = EventSurveySummary {
        effective_opens_at: Some(sample_date()),
        ..sample_survey(EventSurveyState::Draft)
    };
    let mut event = sample_event();
    event.test_event = true;

    // Describe its status action
    let action = status_action(&survey, &event, sample_now());

    // Check the confirmation says no email is sent
    assert_eq!(action.action, EventSurveyStatusAction::MarkReady);
    assert_eq!(
        action.confirm_message,
        "Mark this survey ready? Test events do not email attendees."
    );
}

#[test]
fn test_status_action_mark_ready_without_event_dates() {
    // Setup a draft survey of an event without dates
    let survey = sample_survey(EventSurveyState::Draft);

    // Describe its status action
    let action = status_action(&survey, &sample_event(), sample_now());

    // Check the confirmation and the blank confirmed opening
    assert_eq!(
        action.confirm_message,
        "This will email eligible attendees (currently 40) once the event has a date and ends."
    );
    assert_eq!(
        action.request_values,
        r#"{"action":"mark-ready","expected_effective_opens_at":"","revision":"3"}"#
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
fn test_text_answers_page_next_offset_when_answers_remain() {
    let page = sample_text_answers_page(Some(10), 2, 13);

    assert_eq!(page.next_offset(), Some(12));
}

#[test]
fn test_text_answers_page_remaining_counts_answers_after_the_page() {
    let page = sample_text_answers_page(Some(10), 2, 13);
    let past_end_page = sample_text_answers_page(Some(20), 0, 13);

    assert_eq!(page.remaining(), 1);
    assert_eq!(past_end_page.remaining(), 0);
}

#[test]
fn test_text_answers_page_renders_remaining_answers_on_show_more() {
    let page = sample_text_answers_page(Some(10), 2, 15);

    let html = page.render().unwrap();

    assert!(html.contains("Show more answers (3 left)"));
    assert!(html.contains("answers?offset=12&limit=10"));
}

#[test]
fn test_text_answers_page_without_more_answers() {
    let page = sample_text_answers_page(Some(10), 3, 13);
    let empty_page = sample_text_answers_page(Some(20), 0, 13);

    assert_eq!(page.next_offset(), None);
    assert_eq!(empty_page.next_offset(), None);
}

// Helpers.

/// Collapses whitespace runs so rendered attributes can be matched exactly.
fn normalize_whitespace(html: &str) -> String {
    html.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Returns a fixed future date used by the survey dates.
fn sample_date() -> DateTime<Utc> {
    Utc.with_ymd_and_hms(2099, 5, 10, 9, 0, 0).unwrap()
}

/// Returns an event in Madrid that is not a test event.
fn sample_event() -> EventSummary {
    let mut event = sample_event_summary(Uuid::from_u128(1), Uuid::from_u128(2));
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

/// Returns the fixed time the pages are rendered at.
fn sample_now() -> DateTime<Utc> {
    Utc.with_ymd_and_hms(2099, 5, 1, 12, 0, 0).unwrap()
}

/// Returns a survey summary in the given state.
fn sample_survey(state: EventSurveyState) -> EventSurveySummary {
    sample_event_survey_summary(Uuid::from_u128(1), state)
}

/// Returns a page of free-text answers.
fn sample_text_answers_page(
    offset: Option<usize>,
    answers: usize,
    total: usize,
) -> TextAnswersPage {
    TextAnswersPage {
        answers: EventSurveyTextAnswers {
            answers: (0..answers).map(|index| format!("Answer {index}")).collect(),
            total,
        },
        event_id: Uuid::from_u128(1),
        event_survey_id: Uuid::from_u128(2),
        limit: 10,
        question_id: Uuid::from_u128(3),

        offset,
    }
}
