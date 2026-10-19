use axum::{
    Router,
    body::{Body, to_bytes},
    http::{
        HeaderValue, Request, StatusCode,
        header::{CONTENT_DISPOSITION, CONTENT_TYPE, COOKIE},
        response::Parts,
    },
};
use axum_login::tower_sessions::session;
use chrono::{NaiveDate, TimeZone, Utc};
use serde_json::json;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    services::notifications::MockNotificationsManager,
    types::{
        dashboard::{
            EVENT_SURVEY_RESPONSES_PAGINATION_LIMIT, EVENT_SURVEY_TEXT_ANSWERS_PAGINATION_LIMIT,
            group::surveys::{
                EventSurveyExport, EventSurveyExportRespondent, EventSurveyExportResponse,
                EventSurveyFull, EventSurveyResponse, EventSurveyResponsesOutput,
                EventSurveyResults, EventSurveyResultsQuestion, EventSurveyStatusAction,
                EventSurveySummary, EventSurveyTextAnswers,
            },
        },
        event_survey::{EventSurveyAudience, EventSurveyState},
        permissions::GroupPermission,
        questionnaire::{QuestionnaireAnswers, QuestionnaireQuestionKind},
    },
};

use super::{
    EVENT_SURVEYS_REFRESH_TRIGGER, MAX_EVENT_SURVEY_EXPORT_ANSWER_BYTES,
    MAX_EVENT_SURVEY_EXPORT_ROWS,
};

#[tokio::test]
async fn test_add_accepts_draft_without_questions() {
    // Setup identifiers and a draft submitted without questions
    let ids = TestIds::new();
    let body = "anonymous=true&audience=confirmed&title=Feedback&questions_present=true";

    // Setup database expectations
    let mut db = setup_db(&ids, GroupPermission::EventsWrite);
    db.expect_add_event_survey()
        .times(1)
        .withf(move |actor_user_id, group_id, event_id, survey| {
            *actor_user_id == ids.user_id
                && *group_id == ids.group_id
                && *event_id == ids.event_id
                && survey.questions.is_empty()
                && survey.revision.is_none()
        })
        .returning(|_, _, _, _| Ok(Uuid::new_v4()));

    // Run the request
    let (parts, bytes) = send(
        db,
        ids.session_id,
        "POST",
        &format!("/dashboard/group/events/{}/surveys/add", ids.event_id),
        Some(body),
    )
    .await;

    // Check the response
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        EVENT_SURVEYS_REFRESH_TRIGGER,
    );
}

#[tokio::test]
async fn test_add_accepts_normalized_browser_dates() {
    // Setup identifiers and a survey with dates in the normalized browser format
    // and a percent-encoded single-select question
    let ids = TestIds::new();
    let body = "anonymous=false&audience=checked-in&title=Feedback&description=Tell%20us&\
opens_at=2099-05-10T09%3A00%3A00&closes_at=2099-05-20T18%3A30%3A00&questions_present=true&\
questions%5B0%5D%5Bid%5D=00000000-0000-0000-0000-000000000001&\
questions%5B0%5D%5Bkind%5D=free-text&questions%5B0%5D%5Bprompt%5D=Comments&\
questions%5B0%5D%5Brequired%5D=false&\
questions%5B1%5D%5Bid%5D=00000000-0000-0000-0000-000000000002&\
questions%5B1%5D%5Bkind%5D=single-select&questions%5B1%5D%5Bprompt%5D=Rating&\
questions%5B1%5D%5Brequired%5D=true&\
questions%5B1%5D%5Boptions%5D%5B0%5D%5Bid%5D=00000000-0000-0000-0000-000000000003&\
questions%5B1%5D%5Boptions%5D%5B0%5D%5Blabel%5D=Good";

    // Setup database expectations
    let mut db = setup_db(&ids, GroupPermission::EventsWrite);
    db.expect_add_event_survey()
        .times(1)
        .withf(move |actor_user_id, group_id, event_id, survey| {
            *actor_user_id == ids.user_id
                && *group_id == ids.group_id
                && *event_id == ids.event_id
                && !survey.anonymous
                && survey.audience == EventSurveyAudience::CheckedIn
                && survey.title == "Feedback"
                && survey.closes_at
                    == NaiveDate::from_ymd_opt(2099, 5, 20).unwrap().and_hms_opt(18, 30, 0)
                && survey.description.as_deref() == Some("Tell us")
                && survey.opens_at
                    == NaiveDate::from_ymd_opt(2099, 5, 10).unwrap().and_hms_opt(9, 0, 0)
                && survey.questions.len() == 2
                && survey.questions[0].kind == QuestionnaireQuestionKind::FreeText
                && survey.questions[0].options.is_empty()
                && survey.questions[1].kind == QuestionnaireQuestionKind::SingleSelect
                && survey.questions[1].options.len() == 1
                && survey.questions[1].options[0].label == "Good"
        })
        .returning(|_, _, _, _| Ok(Uuid::new_v4()));

    // Run the request
    let (parts, bytes) = send(
        db,
        ids.session_id,
        "POST",
        &format!("/dashboard/group/events/{}/surveys/add", ids.event_id),
        Some(body),
    )
    .await;

    // Check the response
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        EVENT_SURVEYS_REFRESH_TRIGGER,
    );
}

#[tokio::test]
async fn test_add_page_success() {
    // Setup identifiers and database expectations
    let ids = TestIds::new();
    let mut db = setup_db(&ids, GroupPermission::Read);
    expect_events_write_permission(&mut db, &ids, true);
    expect_event_summary(&mut db, &ids);

    // Run the request
    let (parts, bytes) = send(
        db,
        ids.session_id,
        "GET",
        &format!("/dashboard/group/events/{}/surveys/add", ids.event_id),
        None,
    )
    .await;

    // Check the response renders an empty form with its own submit target
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8_lossy(&bytes);
    assert!(html.contains(&format!(
        r#"hx-post="/dashboard/group/events/{}/surveys/add""#,
        ids.event_id
    )));
    assert!(html.contains("data-event-survey-form"));
    assert!(!html.contains("data-event-form"));
    assert!(!html.contains(r#"name="revision""#));
}

#[tokio::test]
async fn test_add_rejects_invalid_form() {
    // Setup identifiers and database expectations
    let ids = TestIds::new();
    let mut db = setup_db(&ids, GroupPermission::EventsWrite);
    db.expect_add_event_survey().never();

    // Run the request with a blank title
    let (parts, bytes) = send(
        db,
        ids.session_id,
        "POST",
        &format!("/dashboard/group/events/{}/surveys/add", ids.event_id),
        Some("anonymous=true&audience=confirmed&title=%20"),
    )
    .await;

    // Check the response
    assert_non_empty_response(&parts, &bytes, StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_change_status_success() {
    // Setup identifiers and the confirmed Mark ready values
    let ids = TestIds::new();
    let event_survey_id = Uuid::new_v4();
    let opens_at = Utc.with_ymd_and_hms(2099, 5, 10, 9, 0, 0).unwrap();
    let body = format!(
        "action=mark-ready&revision=3&expected_effective_opens_at={}",
        opens_at.timestamp()
    );

    // Setup database expectations
    let mut db = setup_db(&ids, GroupPermission::EventsWrite);
    db.expect_change_event_survey_status()
        .times(1)
        .withf(
            move |actor_user_id, group_id, event_id, survey_id, status| {
                *actor_user_id == ids.user_id
                    && *group_id == ids.group_id
                    && *event_id == ids.event_id
                    && *survey_id == event_survey_id
                    && status.action == EventSurveyStatusAction::MarkReady
                    && status.revision == 3
                    && status.expected_effective_opens_at == Some(opens_at)
            },
        )
        .returning(|_, _, _, _, _| Ok(()));

    // Run the request
    let (parts, bytes) = send(
        db,
        ids.session_id,
        "PUT",
        &format!(
            "/dashboard/group/events/{}/surveys/{event_survey_id}/status",
            ids.event_id
        ),
        Some(&body),
    )
    .await;

    // Check the response
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        EVENT_SURVEYS_REFRESH_TRIGGER,
    );
}

#[tokio::test]
async fn test_delete_success() {
    // Setup identifiers and database expectations
    let ids = TestIds::new();
    let event_survey_id = Uuid::new_v4();
    let mut db = setup_db(&ids, GroupPermission::EventsWrite);
    db.expect_delete_event_survey()
        .times(1)
        .withf(move |actor_user_id, group_id, event_id, survey_id| {
            *actor_user_id == ids.user_id
                && *group_id == ids.group_id
                && *event_id == ids.event_id
                && *survey_id == event_survey_id
        })
        .returning(|_, _, _, _| Ok(()));

    // Run the request
    let (parts, bytes) = send(
        db,
        ids.session_id,
        "DELETE",
        &format!(
            "/dashboard/group/events/{}/surveys/{event_survey_id}/delete",
            ids.event_id
        ),
        None,
    )
    .await;

    // Check the response
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        EVENT_SURVEYS_REFRESH_TRIGGER,
    );
}

#[tokio::test]
async fn test_download_csv_anonymous_survey_exports_dates_and_answers_only() {
    // Setup identifiers and an anonymous export
    let ids = TestIds::new();
    let event_survey_id = Uuid::new_v4();
    let export = EventSurveyExport {
        anonymous: true,
        questions: sample_event_survey_full(event_survey_id).questions,
        responses: vec![EventSurveyExportResponse {
            answers: sample_answers(),
            created_at: Utc.with_ymd_and_hms(2099, 5, 10, 9, 0, 0).unwrap(),

            updated_at: None,
            user: None,
        }],
        title: "Feedback".to_string(),
    };

    // Setup database expectations
    let mut db = setup_db(&ids, GroupPermission::Read);
    expect_event_summary(&mut db, &ids);
    expect_survey_export(&mut db, &ids, event_survey_id, export);

    // Run the request
    let (parts, bytes) = send(
        db,
        ids.session_id,
        "GET",
        &format!(
            "/dashboard/group/events/{}/surveys/{event_survey_id}/responses.csv",
            ids.event_id
        ),
        None,
    )
    .await;

    // Check the CSV has no respondent columns
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/csv; charset=utf-8"),
    );
    assert_eq!(
        String::from_utf8(bytes).unwrap(),
        "Submitted,Updated,What should we improve?,How would you rate the sessions?\n\
2099-05-10 09:00 UTC,,'=SUM(A1),Excellent\n",
    );
}

#[tokio::test]
async fn test_download_csv_identified_survey_exports_protected_respondent_columns() {
    // Setup identifiers and an identified export with formula-like cells
    let ids = TestIds::new();
    let event_survey_id = Uuid::new_v4();
    let mut questions = sample_event_survey_full(event_survey_id).questions;
    questions[0].prompt = "@Comments".to_string();
    let export = EventSurveyExport {
        anonymous: false,
        questions,
        responses: vec![EventSurveyExportResponse {
            answers: sample_answers(),
            created_at: Utc.with_ymd_and_hms(2099, 5, 10, 9, 0, 0).unwrap(),

            updated_at: Some(Utc.with_ymd_and_hms(2099, 5, 11, 10, 30, 0).unwrap()),
            user: Some(EventSurveyExportRespondent {
                username: "jane".to_string(),

                company: Some("+Example".to_string()),
                name: Some("Jane Doe".to_string()),
                title: None,
            }),
        }],
        title: "Feedback".to_string(),
    };

    // Setup database expectations
    let mut db = setup_db(&ids, GroupPermission::Read);
    expect_event_summary(&mut db, &ids);
    expect_survey_export(&mut db, &ids, event_survey_id, export);

    // Run the request
    let (parts, bytes) = send(
        db,
        ids.session_id,
        "GET",
        &format!(
            "/dashboard/group/events/{}/surveys/{event_survey_id}/responses.csv",
            ids.event_id
        ),
        None,
    )
    .await;

    // Check the attachment and its protected cells
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_DISPOSITION).unwrap(),
        &HeaderValue::from_str(&format!(
            "attachment; filename=\"event-ghi9abc-survey-{event_survey_id}.csv\""
        ))
        .unwrap(),
    );
    assert_eq!(
        String::from_utf8(bytes).unwrap(),
        "Name,Company,Title,Submitted,Updated,'@Comments,How would you rate the sessions?\n\
Jane Doe,'+Example,,2099-05-10 09:00 UTC,2099-05-11 10:30 UTC,'=SUM(A1),Excellent\n",
    );
}

#[tokio::test]
async fn test_download_csv_unknown_survey_returns_not_found() {
    // Setup identifiers and database expectations
    let ids = TestIds::new();
    let event_survey_id = Uuid::new_v4();
    let mut db = setup_db(&ids, GroupPermission::Read);
    expect_event_summary(&mut db, &ids);
    db.expect_get_event_survey_export()
        .times(1)
        .returning(|_, _, _, _, _| Ok(None));

    // Run the request
    let (parts, bytes) = send(
        db,
        ids.session_id,
        "GET",
        &format!(
            "/dashboard/group/events/{}/surveys/{event_survey_id}/responses.csv",
            ids.event_id
        ),
        None,
    )
    .await;

    // Check the response
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_list_page_read_only_disables_mutation_controls() {
    // Setup identifiers and a survey listed for a read-only role
    let ids = TestIds::new();
    let survey = sample_event_survey_summary(Uuid::new_v4(), EventSurveyState::Draft);

    // Setup database expectations
    let mut db = setup_db(&ids, GroupPermission::Read);
    expect_events_write_permission(&mut db, &ids, false);
    expect_event_summary(&mut db, &ids);
    expect_list_event_surveys(&mut db, &ids, vec![survey]);

    // Run the request
    let (parts, bytes) = send(
        db,
        ids.session_id,
        "GET",
        &format!("/dashboard/group/events/{}/surveys", ids.event_id),
        None,
    )
    .await;

    // Check results, the CSV and the read-only form stay available while
    // mutation controls are disabled with the role reason
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = normalize_whitespace(&String::from_utf8_lossy(&bytes));
    assert!(html.contains("Session feedback"));
    assert!(html.contains("/results\""));
    assert!(html.contains("/responses.csv\""));
    assert!(html.contains("/update\""));
    assert!(html.contains("Your role cannot manage surveys."));
    assert_eq!(
        html.matches(r#"disabled title="Your role cannot add, update or delete surveys.""#)
            .count(),
        3
    );
}

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and a draft survey
    let ids = TestIds::new();
    let event_survey_id = Uuid::new_v4();
    let survey = sample_event_survey_summary(event_survey_id, EventSurveyState::Draft);

    // Setup database expectations
    let mut db = setup_db(&ids, GroupPermission::Read);
    expect_events_write_permission(&mut db, &ids, true);
    expect_event_summary(&mut db, &ids);
    expect_list_event_surveys(&mut db, &ids, vec![survey]);

    // Run the request
    let (parts, bytes) = send(
        db,
        ids.session_id,
        "GET",
        &format!("/dashboard/group/events/{}/surveys", ids.event_id),
        None,
    )
    .await;

    // Check the row and its mutation controls
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8_lossy(&bytes);
    assert!(html.contains("Session feedback"));
    assert!(html.contains("12 / 40 (30%)"));
    assert!(html.contains("add-event-survey-button"));
    assert!(html.contains(&format!(r#"id="event-survey-status-{event_survey_id}""#)));
    assert!(html.contains(&format!(r#"id="delete-event-survey-{event_survey_id}""#)));
    assert!(html.contains(
        "This will email eligible attendees (currently 40) once the event has a date and ends."
    ));
}

#[tokio::test]
async fn test_responses_page_applies_default_bounds() {
    // Setup identifiers and an identified survey without responses
    let ids = TestIds::new();
    let event_survey_id = Uuid::new_v4();
    let mut survey = sample_event_survey_full(event_survey_id);
    survey.summary.anonymous = false;
    let responses = EventSurveyResponsesOutput {
        responses: vec![],
        total: 0,
    };

    // Setup database expectations
    let mut db = setup_db(&ids, GroupPermission::Read);
    expect_event_summary(&mut db, &ids);
    expect_get_event_survey(&mut db, &ids, event_survey_id, survey);
    db.expect_list_event_survey_responses()
        .times(1)
        .withf(move |_, _, survey_id, filters| {
            *survey_id == event_survey_id
                && filters.limit == Some(EVENT_SURVEY_RESPONSES_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _, _, _| Ok(Some(responses.clone())));

    // Run the request without a query string
    let (parts, _) = send(
        db,
        ids.session_id,
        "GET",
        &format!(
            "/dashboard/group/events/{}/surveys/{event_survey_id}/responses",
            ids.event_id
        ),
        None,
    )
    .await;

    // Check the page was rendered with the default bounds
    assert_eq!(parts.status, StatusCode::OK);
}

#[tokio::test]
async fn test_responses_page_rejects_anonymous_survey() {
    // Setup identifiers and an anonymous survey
    let ids = TestIds::new();
    let event_survey_id = Uuid::new_v4();
    let survey = sample_event_survey_full(event_survey_id);

    // Setup database expectations
    let mut db = setup_db(&ids, GroupPermission::Read);
    expect_event_summary(&mut db, &ids);
    expect_get_event_survey(&mut db, &ids, event_survey_id, survey);
    db.expect_list_event_survey_responses().never();

    // Run the request
    let (parts, bytes) = send(
        db,
        ids.session_id,
        "GET",
        &format!(
            "/dashboard/group/events/{}/surveys/{event_survey_id}/responses",
            ids.event_id
        ),
        None,
    )
    .await;

    // Check the rejection
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8_lossy(&bytes),
        "individual responses are not available for anonymous surveys"
    );
}

#[tokio::test]
async fn test_responses_page_success() {
    // Setup identifiers and an identified survey with one response
    let ids = TestIds::new();
    let event_survey_id = Uuid::new_v4();
    let mut survey = sample_event_survey_full(event_survey_id);
    survey.summary.anonymous = false;
    let responses = EventSurveyResponsesOutput {
        responses: vec![
            EventSurveyResponse {
                answers: sample_answers(),
                created_at: Utc.with_ymd_and_hms(2099, 5, 10, 9, 0, 0).unwrap(),
                user: sample_user_summary(Uuid::new_v4(), "jane"),

                updated_at: None,
            },
            EventSurveyResponse {
                answers: serde_json::from_value(json!({
                    "answers": [
                        {"question_id": "00000000-0000-0000-0000-000000005d01", "value": "The <b>talks</b>"}
                    ]
                }))
                .unwrap(),
                created_at: Utc.with_ymd_and_hms(2099, 5, 10, 10, 0, 0).unwrap(),
                user: sample_user_summary(Uuid::new_v4(), "john"),

                updated_at: None,
            },
        ],
        total: 2,
    };

    // Setup database expectations
    let mut db = setup_db(&ids, GroupPermission::Read);
    expect_event_summary(&mut db, &ids);
    expect_get_event_survey(&mut db, &ids, event_survey_id, survey);
    db.expect_list_event_survey_responses()
        .times(1)
        .withf(move |group_id, event_id, survey_id, filters| {
            *group_id == ids.group_id
                && *event_id == ids.event_id
                && *survey_id == event_survey_id
                && filters.limit == Some(EVENT_SURVEY_RESPONSES_PAGINATION_LIMIT)
                && filters.offset == Some(20)
        })
        .returning(move |_, _, _, _| Ok(Some(responses.clone())));

    // Run the request
    let (parts, bytes) = send(
        db,
        ids.session_id,
        "GET",
        &format!(
            "/dashboard/group/events/{}/surveys/{event_survey_id}/responses?offset=20",
            ids.event_id
        ),
        None,
    )
    .await;

    // Check the Individual view renders the escaped responses
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8_lossy(&bytes);
    assert!(html.contains("data-event-survey-responses"));
    assert!(html.contains("=SUM(A1)"));
    assert!(html.contains("The &#60;b&#62;talks&#60;/b&#62;"));
    assert!(!html.contains("<b>talks</b>"));
    assert!(html.contains(r#"id="event-survey-individual-view""#));
}

#[tokio::test]
async fn test_results_page_success() {
    // Setup identifiers and the results of an anonymous survey with few responses
    let ids = TestIds::new();
    let event_survey_id = Uuid::new_v4();
    let question_id = Uuid::new_v4();
    let mut survey = sample_event_survey_summary(event_survey_id, EventSurveyState::Open);
    survey.eligible_respondents_count = 2;
    survey.responses_count = 2;
    let results = EventSurveyResults {
        questions: vec![EventSurveyResultsQuestion {
            kind: QuestionnaireQuestionKind::FreeText,
            position: 1,
            prompt: "What should we improve?".to_string(),
            question_id,
            required: false,

            breakdown: None,
            text_answers: Some(EventSurveyTextAnswers {
                answers: vec!["The <b>talks</b>".to_string()],
                total: 11,
            }),
        }],
        survey,
    };

    // Setup database expectations
    let mut db = setup_db(&ids, GroupPermission::Read);
    expect_event_summary(&mut db, &ids);
    db.expect_get_event_survey_results()
        .times(1)
        .withf(move |group_id, event_id, survey_id| {
            *group_id == ids.group_id && *event_id == ids.event_id && *survey_id == event_survey_id
        })
        .returning(move |_, _, _| Ok(Some(results.clone())));

    // Run the request
    let (parts, bytes) = send(
        db,
        ids.session_id,
        "GET",
        &format!(
            "/dashboard/group/events/{}/surveys/{event_survey_id}/results",
            ids.event_id
        ),
        None,
    )
    .await;

    // Check the escaped results, the "Show more" link and the anonymity notice
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8_lossy(&bytes);
    assert!(html.contains("The &#60;b&#62;talks&#60;/b&#62;"));
    assert!(!html.contains("<b>talks</b>"));
    assert!(html.contains("Show more answers (10 left)"));
    assert!(html.contains(&format!(
        "/surveys/{event_survey_id}/results/questions/{question_id}/answers?offset=1"
    )));
    assert!(html.contains("data-event-survey-few-responses-notice"));
    assert!(html.contains("Anonymous surveys only show aggregated results."));
}

#[tokio::test]
async fn test_results_page_unknown_survey_returns_not_found() {
    // Setup identifiers and database expectations
    let ids = TestIds::new();
    let mut db = setup_db(&ids, GroupPermission::Read);
    expect_event_summary(&mut db, &ids);
    db.expect_get_event_survey_results()
        .times(1)
        .returning(|_, _, _| Ok(None));

    // Run the request
    let (parts, bytes) = send(
        db,
        ids.session_id,
        "GET",
        &format!(
            "/dashboard/group/events/{}/surveys/{}/results",
            ids.event_id,
            Uuid::new_v4()
        ),
        None,
    )
    .await;

    // Check the response
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_text_answers_page_success() {
    // Setup identifiers and a page of answers with more remaining
    let ids = TestIds::new();
    let event_survey_id = Uuid::new_v4();
    let question_id = Uuid::new_v4();
    let answers = EventSurveyTextAnswers {
        answers: vec!["More <b>breaks</b>".to_string()],
        total: 15,
    };

    // Setup database expectations
    let mut db = setup_db(&ids, GroupPermission::Read);
    db.expect_list_event_survey_text_answers()
        .times(1)
        .withf(move |group_id, event_id, survey_id, qid, filters| {
            *group_id == ids.group_id
                && *event_id == ids.event_id
                && *survey_id == event_survey_id
                && *qid == question_id
                && filters.limit == Some(EVENT_SURVEY_TEXT_ANSWERS_PAGINATION_LIMIT)
                && filters.offset == Some(10)
        })
        .returning(move |_, _, _, _, _| Ok(Some(answers.clone())));

    // Run the request
    let (parts, bytes) = send(
        db,
        ids.session_id,
        "GET",
        &format!(
            "/dashboard/group/events/{}/surveys/{event_survey_id}/results/questions/{question_id}/answers?offset=10",
            ids.event_id
        ),
        None,
    )
    .await;

    // Check the escaped answers and the next "Show more" page
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8_lossy(&bytes);
    assert!(html.contains("More &#60;b&#62;breaks&#60;/b&#62;"));
    assert!(!html.contains("<b>breaks</b>"));
    assert!(html.contains("answers?offset=11&limit=10"));
}

#[tokio::test]
async fn test_text_answers_page_last_page_omits_show_more() {
    // Setup identifiers and the last page of answers
    let ids = TestIds::new();
    let event_survey_id = Uuid::new_v4();
    let question_id = Uuid::new_v4();
    let answers = EventSurveyTextAnswers {
        answers: vec!["Last answer".to_string()],
        total: 11,
    };

    // Setup database expectations
    let mut db = setup_db(&ids, GroupPermission::Read);
    db.expect_list_event_survey_text_answers()
        .times(1)
        .withf(move |_, _, survey_id, qid, filters| {
            *survey_id == event_survey_id && *qid == question_id && filters.offset == Some(10)
        })
        .returning(move |_, _, _, _, _| Ok(Some(answers.clone())));

    // Run the request
    let (parts, bytes) = send(
        db,
        ids.session_id,
        "GET",
        &format!(
            "/dashboard/group/events/{}/surveys/{event_survey_id}/results/questions/{question_id}/answers?offset=10",
            ids.event_id
        ),
        None,
    )
    .await;

    // Check the last answer renders without another "Show more" button
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8_lossy(&bytes);
    assert!(html.contains("Last answer"));
    assert!(!html.contains("Show more"));
}

#[tokio::test]
async fn test_text_answers_page_unknown_question_returns_not_found() {
    // Setup identifiers and database expectations
    let ids = TestIds::new();
    let event_survey_id = Uuid::new_v4();
    let question_id = Uuid::new_v4();
    let mut db = setup_db(&ids, GroupPermission::Read);
    db.expect_list_event_survey_text_answers()
        .times(1)
        .withf(move |group_id, event_id, survey_id, qid, _| {
            *group_id == ids.group_id
                && *event_id == ids.event_id
                && *survey_id == event_survey_id
                && *qid == question_id
        })
        .returning(|_, _, _, _, _| Ok(None));

    // Run the request
    let (parts, bytes) = send(
        db,
        ids.session_id,
        "GET",
        &format!(
            "/dashboard/group/events/{}/surveys/{event_survey_id}/results/questions/{question_id}/answers",
            ids.event_id
        ),
        None,
    )
    .await;

    // Check the response
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_update_clears_custom_opening_and_closing_date() {
    // Setup identifiers and a form clearing both dates
    let ids = TestIds::new();
    let event_survey_id = Uuid::new_v4();
    let body = "anonymous=true&audience=confirmed&title=Feedback&opens_at=&closes_at=&revision=4";

    // Setup database expectations
    let mut db = setup_db(&ids, GroupPermission::EventsWrite);
    db.expect_update_event_survey()
        .times(1)
        .withf(
            move |actor_user_id, group_id, event_id, survey_id, expected_revision, survey| {
                *actor_user_id == ids.user_id
                    && *group_id == ids.group_id
                    && *event_id == ids.event_id
                    && *survey_id == event_survey_id
                    && *expected_revision == 4
                    && survey.closes_at.is_none()
                    && survey.opens_at.is_none()
            },
        )
        .returning(|_, _, _, _, _, _| Ok(()));

    // Run the request
    let (parts, bytes) = send(
        db,
        ids.session_id,
        "PUT",
        &format!(
            "/dashboard/group/events/{}/surveys/{event_survey_id}/update",
            ids.event_id
        ),
        Some(body),
    )
    .await;

    // Check the response
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        EVENT_SURVEYS_REFRESH_TRIGGER,
    );
}

#[tokio::test]
async fn test_update_page_locked_survey_disables_locked_fields() {
    // Setup identifiers and a survey locked by responses
    let ids = TestIds::new();
    let event_survey_id = Uuid::new_v4();
    let mut survey = sample_event_survey_full(event_survey_id);
    survey.summary.locked = true;

    // Setup database expectations
    let mut db = setup_db(&ids, GroupPermission::Read);
    expect_events_write_permission(&mut db, &ids, true);
    expect_event_summary(&mut db, &ids);
    expect_get_event_survey(&mut db, &ids, event_survey_id, survey);

    // Run the request
    let (parts, bytes) = send(
        db,
        ids.session_id,
        "GET",
        &format!(
            "/dashboard/group/events/{}/surveys/{event_survey_id}/update",
            ids.event_id
        ),
        None,
    )
    .await;

    // Check the form targets the update route and carries the revision
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8_lossy(&bytes);
    assert!(html.contains(&format!(
        r#"hx-put="/dashboard/group/events/{}/surveys/{event_survey_id}/update""#,
        ids.event_id
    )));
    assert!(html.contains(r#"name="revision" value="3""#));
    assert!(html.contains("data-event-survey-locked-notice"));
}

#[tokio::test]
async fn test_update_page_unknown_survey_returns_not_found() {
    // Setup identifiers and database expectations
    let ids = TestIds::new();
    let mut db = setup_db(&ids, GroupPermission::Read);
    expect_events_write_permission(&mut db, &ids, true);
    expect_event_summary(&mut db, &ids);
    db.expect_get_event_survey().times(1).returning(|_, _, _| Ok(None));

    // Run the request
    let (parts, bytes) = send(
        db,
        ids.session_id,
        "GET",
        &format!(
            "/dashboard/group/events/{}/surveys/{}/update",
            ids.event_id,
            Uuid::new_v4()
        ),
        None,
    )
    .await;

    // Check the response
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_update_rejects_missing_revision() {
    // Setup identifiers and database expectations
    let ids = TestIds::new();
    let mut db = setup_db(&ids, GroupPermission::EventsWrite);
    db.expect_update_event_survey().never();

    // Run the request without the loaded revision
    let (parts, bytes) = send(
        db,
        ids.session_id,
        "PUT",
        &format!(
            "/dashboard/group/events/{}/surveys/{}/update",
            ids.event_id,
            Uuid::new_v4()
        ),
        Some("anonymous=true&audience=confirmed&title=Feedback"),
    )
    .await;

    // Check the rejection
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8_lossy(&bytes),
        "survey revision is required"
    );
}

#[tokio::test]
async fn test_update_removing_last_question() {
    // Setup identifiers and a form whose editor has no questions left
    let ids = TestIds::new();
    let event_survey_id = Uuid::new_v4();
    let body = "anonymous=true&audience=confirmed&title=Feedback&questions_present=true&revision=2";

    // Setup database expectations
    let mut db = setup_db(&ids, GroupPermission::EventsWrite);
    db.expect_update_event_survey()
        .times(1)
        .withf(move |_, _, _, survey_id, expected_revision, survey| {
            *survey_id == event_survey_id && *expected_revision == 2 && survey.questions.is_empty()
        })
        .returning(|_, _, _, _, _, _| Ok(()));

    // Run the request
    let (parts, bytes) = send(
        db,
        ids.session_id,
        "PUT",
        &format!(
            "/dashboard/group/events/{}/surveys/{event_survey_id}/update",
            ids.event_id
        ),
        Some(body),
    )
    .await;

    // Check the response
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        EVENT_SURVEYS_REFRESH_TRIGGER,
    );
}

// Helpers.

/// Identifiers shared by the requests of one test.
#[derive(Clone, Copy)]
struct TestIds {
    /// Selected community.
    community_id: Uuid,
    /// Event the surveys belong to.
    event_id: Uuid,
    /// Selected group.
    group_id: Uuid,
    /// Authenticated session.
    session_id: session::Id,
    /// Authenticated user.
    user_id: Uuid,
}

impl TestIds {
    /// Generates the identifiers of a test.
    fn new() -> Self {
        Self {
            community_id: Uuid::new_v4(),
            event_id: Uuid::new_v4(),
            group_id: Uuid::new_v4(),
            session_id: session::Id::default(),
            user_id: Uuid::new_v4(),
        }
    }
}

/// Expects the event summary read by survey pages.
fn expect_event_summary(db: &mut MockDB, ids: &TestIds) {
    let ids = *ids;
    let event = sample_event_summary(ids.event_id, ids.group_id);
    db.expect_get_event_summary_dashboard()
        .times(1)
        .withf(move |community_id, group_id, event_id| {
            *community_id == ids.community_id
                && *group_id == ids.group_id
                && *event_id == ids.event_id
        })
        .returning(move |_, _, _| Ok(event.clone()));
}

/// Expects the events write permission check made by pages with mutations.
fn expect_events_write_permission(db: &mut MockDB, ids: &TestIds, allowed: bool) {
    let ids = *ids;
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |community_id, group_id, user_id, permission| {
            *community_id == ids.community_id
                && *group_id == ids.group_id
                && *user_id == ids.user_id
                && *permission == GroupPermission::EventsWrite
        })
        .returning(move |_, _, _, _| Ok(allowed));
}

/// Expects the survey read by the update form and the Individual view.
fn expect_get_event_survey(
    db: &mut MockDB,
    ids: &TestIds,
    event_survey_id: Uuid,
    survey: EventSurveyFull,
) {
    let ids = *ids;
    db.expect_get_event_survey()
        .times(1)
        .withf(move |group_id, event_id, survey_id| {
            *group_id == ids.group_id && *event_id == ids.event_id && *survey_id == event_survey_id
        })
        .returning(move |_, _, _| Ok(Some(survey.clone())));
}

/// Expects the surveys read by the list page.
fn expect_list_event_surveys(db: &mut MockDB, ids: &TestIds, surveys: Vec<EventSurveySummary>) {
    let ids = *ids;
    db.expect_list_event_surveys()
        .times(1)
        .withf(move |group_id, event_id| *group_id == ids.group_id && *event_id == ids.event_id)
        .returning(move |_, _| Ok(surveys.clone()));
}

/// Expects the export read by the CSV download, within the export bounds.
fn expect_survey_export(
    db: &mut MockDB,
    ids: &TestIds,
    event_survey_id: Uuid,
    export: EventSurveyExport,
) {
    let ids = *ids;
    db.expect_get_event_survey_export()
        .times(1)
        .withf(move |group_id, event_id, survey_id, max_rows, max_bytes| {
            *group_id == ids.group_id
                && *event_id == ids.event_id
                && *survey_id == event_survey_id
                && *max_rows == MAX_EVENT_SURVEY_EXPORT_ROWS
                && *max_bytes == MAX_EVENT_SURVEY_EXPORT_ANSWER_BYTES
        })
        .returning(move |_, _, _, _, _| Ok(Some(export.clone())));
}

/// Collapses whitespace runs so rendered attributes can be matched exactly.
fn normalize_whitespace(html: &str) -> String {
    html.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Returns answers to the sample survey questions, with a formula-like text.
fn sample_answers() -> QuestionnaireAnswers {
    serde_json::from_value(json!({
        "answers": [
            {"question_id": "00000000-0000-0000-0000-000000005d01", "value": "=SUM(A1)"},
            {"question_id": "00000000-0000-0000-0000-000000005d02", "value": "00000000-0000-0000-0000-000000005e01"}
        ]
    }))
    .unwrap()
}

/// Sends a request to the dashboard router and returns its parts and body.
async fn send(
    db: MockDB,
    session_id: session::Id,
    method: &str,
    uri: &str,
    form: Option<&str>,
) -> (Parts, Vec<u8>) {
    let router: Router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let mut request = Request::builder()
        .method(method)
        .uri(uri)
        .header(COOKIE, format!("id={session_id}"));
    if form.is_some() {
        request = request.header(CONTENT_TYPE, "application/x-www-form-urlencoded");
    }
    let request = request
        .body(form.map_or_else(Body::empty, |form| Body::from(form.to_string())))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    (parts, bytes.to_vec())
}

/// Returns a database mock with an authenticated group session holding the
/// permission the route requires.
fn setup_db(ids: &TestIds, permission: GroupPermission) -> MockDB {
    let mut db = MockDB::new();
    expect_authenticated_group_session(
        &mut db,
        ids.session_id,
        ids.user_id,
        ids.community_id,
        ids.group_id,
    );
    expect_group_permission(
        &mut db,
        ids.community_id,
        ids.group_id,
        ids.user_id,
        permission,
    );
    db
}
