use axum::http::{
    HeaderValue, StatusCode,
    header::{CONTENT_DISPOSITION, CONTENT_TYPE},
};
use chrono::{NaiveDate, TimeZone, Utc};
use serde_json::json;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    test_util::normalize_whitespace,
    types::{
        dashboard::{
            EVENT_SURVEY_RESPONSES_PAGINATION_LIMIT, EVENT_SURVEY_TEXT_ANSWERS_PAGINATION_LIMIT,
            group::surveys::{
                EventSurveyExport, EventSurveyExportRespondent, EventSurveyExportResponse,
                EventSurveyFull, EventSurveyResponseFull, EventSurveyResponseSummary,
                EventSurveyResponsesOutput, EventSurveyResults, EventSurveyResultsQuestion,
                EventSurveyStatusAction, EventSurveySummary, EventSurveyTextAnswers,
                EventSurveyTextAnswersOutput,
            },
        },
        event_survey::{EventSurveyAudience, EventSurveyState},
        permissions::GroupPermission,
        questionnaire::{QuestionnaireAnswers, QuestionnaireQuestionKind},
    },
    validation::MAX_LEN_M,
};

use super::{
    EVENT_SURVEYS_REFRESH_TRIGGER, MAX_EVENT_SURVEY_EXPORT_ANSWER_BYTES,
    MAX_EVENT_SURVEY_EXPORT_ROWS,
};

#[tokio::test]
async fn test_add_accepts_draft_without_questions() {
    // Setup identifiers and a draft submitted without questions
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let body = "anonymous=true&audience=confirmed&title=Feedback&questions_present=true";

    // Setup database expectations
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);
    db.expect_add_event_survey()
        .times(1)
        .withf(move |actor_user_id, group_id, survey_event_id, survey| {
            *actor_user_id == ids.user_id
                && *group_id == ids.group_id
                && *survey_event_id == event_id
                && survey.questions.is_empty()
                && survey.revision.is_none()
        })
        .returning(|_, _, _, _| Ok(Uuid::new_v4()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "POST",
        &format!("/dashboard/group/events/{event_id}/surveys/add"),
        ids.session_id,
        body,
    );
    let (parts, bytes) = send(router, request).await;

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
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
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
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);
    db.expect_add_event_survey()
        .times(1)
        .withf(move |actor_user_id, group_id, survey_event_id, survey| {
            *actor_user_id == ids.user_id
                && *group_id == ids.group_id
                && *survey_event_id == event_id
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

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "POST",
        &format!("/dashboard/group/events/{event_id}/surveys/add"),
        ids.session_id,
        body,
    );
    let (parts, bytes) = send(router, request).await;

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
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);
    expect_event_summary(&mut db, &ids, event_id);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/surveys/add"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the response renders an empty form with its own submit target
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8_lossy(&bytes);
    assert!(html.contains(&format!(
        r#"hx-post="/dashboard/group/events/{event_id}/surveys/add""#
    )));
    assert!(html.contains("data-event-survey-form"));
    assert!(!html.contains("data-event-form"));
    assert!(!html.contains(r#"name="revision""#));
}

#[tokio::test]
async fn test_add_rejects_invalid_form() {
    // Setup identifiers and database expectations
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);
    db.expect_add_event_survey().never();

    // Setup router and send request with a blank title
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "POST",
        &format!("/dashboard/group/events/{event_id}/surveys/add"),
        ids.session_id,
        "anonymous=true&audience=confirmed&title=%20",
    );
    let (parts, bytes) = send(router, request).await;

    // Check the response
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        std::str::from_utf8(&bytes).unwrap(),
        "title: value cannot be empty or whitespace-only\n"
    );
}

#[tokio::test]
async fn test_change_status_success() {
    // Setup identifiers and the confirmed Mark ready values
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_survey_id = Uuid::new_v4();
    let opens_at = Utc.with_ymd_and_hms(2099, 5, 10, 9, 0, 0).unwrap();
    let body = format!(
        "action=mark-ready&revision=3&expected_effective_opens_at={}",
        opens_at.timestamp()
    );

    // Setup database expectations
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);
    db.expect_change_event_survey_status()
        .times(1)
        .withf(
            move |actor_user_id, group_id, survey_event_id, survey_id, status| {
                *actor_user_id == ids.user_id
                    && *group_id == ids.group_id
                    && *survey_event_id == event_id
                    && *survey_id == event_survey_id
                    && status.action == EventSurveyStatusAction::MarkReady
                    && status.revision == 3
                    && status.expected_effective_opens_at == Some(opens_at)
            },
        )
        .returning(|_, _, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/group/events/{event_id}/surveys/{event_survey_id}/status"),
        ids.session_id,
        body,
    );
    let (parts, bytes) = send(router, request).await;

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
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_survey_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);
    db.expect_delete_event_survey()
        .times(1)
        .withf(move |actor_user_id, group_id, survey_event_id, survey_id| {
            *actor_user_id == ids.user_id
                && *group_id == ids.group_id
                && *survey_event_id == event_id
                && *survey_id == event_survey_id
        })
        .returning(|_, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "DELETE",
        &format!("/dashboard/group/events/{event_id}/surveys/{event_survey_id}/delete"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

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
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
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
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_event_summary(&mut db, &ids, event_id);
    expect_survey_export(&mut db, &ids, event_id, event_survey_id, export);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/surveys/{event_survey_id}/responses.csv"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the CSV has no respondent columns
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/csv; charset=utf-8"),
    );
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "Submitted,Updated,What should we improve?,How would you rate the sessions?\n\
2099-05-10 09:00 UTC,,'=SUM(A1),Excellent\n",
    );
}

#[tokio::test]
async fn test_download_csv_identified_survey_exports_protected_respondent_columns() {
    // Setup identifiers and an identified export with formula-like cells
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
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
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_event_summary(&mut db, &ids, event_id);
    expect_survey_export(&mut db, &ids, event_id, event_survey_id, export);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/surveys/{event_survey_id}/responses.csv"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

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
        String::from_utf8(bytes.to_vec()).unwrap(),
        "Name,Company,Title,Submitted,Updated,'@Comments,How would you rate the sessions?\n\
Jane Doe,'+Example,,2099-05-10 09:00 UTC,2099-05-11 10:30 UTC,'=SUM(A1),Excellent\n",
    );
}

#[tokio::test]
async fn test_download_csv_unknown_survey_returns_not_found() {
    // Setup identifiers and database expectations
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_survey_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_event_summary(&mut db, &ids, event_id);
    db.expect_get_event_survey_export()
        .times(1)
        .returning(|_, _, _, _, _| Ok(None));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/surveys/{event_survey_id}/responses.csv"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the response
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_list_page_read_only_disables_mutation_controls() {
    // Setup identifiers and a survey listed for a read-only role
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let survey = sample_event_survey_summary(Uuid::new_v4(), EventSurveyState::Draft);

    // Setup database expectations
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, false);
    expect_event_summary(&mut db, &ids, event_id);
    expect_list_event_surveys(&mut db, &ids, event_id, vec![survey]);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/surveys"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the survey is listed with the role reason; the disabled controls
    // are covered by the template tests
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8_lossy(&bytes);
    assert!(html.contains("Session feedback"));
    assert!(html.contains("Your role cannot manage surveys."));
}

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and a draft survey
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_survey_id = Uuid::new_v4();
    let survey = sample_event_survey_summary(event_survey_id, EventSurveyState::Draft);

    // Setup database expectations
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);
    expect_event_summary(&mut db, &ids, event_id);
    expect_list_event_surveys(&mut db, &ids, event_id, vec![survey]);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/surveys"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

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
async fn test_response_modal_rejects_anonymous_survey() {
    // Setup identifiers and an anonymous survey
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_survey_id = Uuid::new_v4();
    let survey = sample_event_survey_full(event_survey_id);

    // Setup database expectations
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_event_summary(&mut db, &ids, event_id);
    expect_get_event_survey(&mut db, &ids, event_id, event_survey_id, survey);
    db.expect_get_event_survey_response().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!(
            "/dashboard/group/events/{event_id}/surveys/{event_survey_id}/responses/{}",
            Uuid::new_v4()
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the rejection
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8_lossy(&bytes),
        "individual responses are not available for anonymous surveys"
    );
}

#[tokio::test]
async fn test_response_modal_success() {
    // Setup identifiers and an identified survey with three matching respondents
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_survey_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let next_user_id = Uuid::new_v4();
    let previous_user_id = Uuid::new_v4();
    let mut survey = sample_event_survey_full(event_survey_id);
    survey.summary.anonymous = false;
    let mut user = sample_user_summary(user_id, "jane");
    user.company = Some("Example <Corp>".to_string());
    user.name = Some("Jane Doe".to_string());
    user.title = Some("Engineer".to_string());
    let response = EventSurveyResponseFull {
        answers: serde_json::from_value(json!({
            "answers": [
                {"question_id": "00000000-0000-0000-0000-000000005d01", "value": "The <b>talks</b>"}
            ]
        }))
        .unwrap(),
        position: 2,
        summary: EventSurveyResponseSummary {
            answered_questions_count: 1,
            created_at: Utc.with_ymd_and_hms(2099, 5, 10, 9, 0, 0).unwrap(),
            user,

            ticket_title: Some("VIP".to_string()),
            updated_at: Some(Utc.with_ymd_and_hms(2099, 5, 11, 9, 0, 0).unwrap()),
        },
        total: 3,

        next_user_id: Some(next_user_id),
        previous_user_id: Some(previous_user_id),
    };

    // Setup database expectations
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_event_summary(&mut db, &ids, event_id);
    expect_get_event_survey(&mut db, &ids, event_id, event_survey_id, survey);
    db.expect_get_event_survey_response()
        .times(1)
        .withf(
            move |group_id, survey_event_id, survey_id, respondent_id, filters| {
                *group_id == ids.group_id
                    && *survey_event_id == event_id
                    && *survey_id == event_survey_id
                    && *respondent_id == user_id
                    && filters.ts_query.as_deref() == Some("jane doe")
            },
        )
        .returning(move |_, _, _, _, _| Ok(Some(response.clone())));

    // Setup router and send request with the respondents search
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!(
            "/dashboard/group/events/{event_id}/surveys/{event_survey_id}/responses/{user_id}?ts_query=jane+doe"
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the respondent details and escaped answers
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8_lossy(&bytes);
    assert!(html.contains(r#"id="event-survey-response-modal-title""#));
    assert!(html.contains("Jane Doe"));
    assert!(html.contains("Engineer · Example &#60;Corp&#62;"));
    assert!(html.contains("VIP"));
    assert!(html.contains("Edited"));
    assert!(html.contains("Answered 1 of 2 questions"));
    assert!(html.contains("The &#60;b&#62;talks&#60;/b&#62;"));
    assert!(!html.contains("<b>talks</b>"));

    // Check the navigation keeps the search
    assert!(html.contains("Respondent 2 of 3"));
    let base_url =
        format!("/dashboard/group/events/{event_id}/surveys/{event_survey_id}/responses");
    assert!(html.contains(&format!(
        r#"hx-get="{base_url}/{previous_user_id}?ts_query=jane+doe""#
    )));
    assert!(html.contains(&format!(
        r#"hx-get="{base_url}/{next_user_id}?ts_query=jane+doe""#
    )));
}

#[tokio::test]
async fn test_response_modal_unknown_response_returns_not_found() {
    // Setup identifiers and an identified survey
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_survey_id = Uuid::new_v4();
    let mut survey = sample_event_survey_full(event_survey_id);
    survey.summary.anonymous = false;

    // Setup database expectations
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_event_summary(&mut db, &ids, event_id);
    expect_get_event_survey(&mut db, &ids, event_id, event_survey_id, survey);
    db.expect_get_event_survey_response()
        .times(1)
        .withf(move |_, _, survey_id, _, filters| {
            *survey_id == event_survey_id && filters.ts_query.is_none()
        })
        .returning(|_, _, _, _, _| Ok(None));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!(
            "/dashboard/group/events/{event_id}/surveys/{event_survey_id}/responses/{}",
            Uuid::new_v4()
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the response is not found
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_response_modal_without_neighbors_disables_navigation() {
    // Setup identifiers and the only respondent of an identified survey
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_survey_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let mut survey = sample_event_survey_full(event_survey_id);
    survey.summary.anonymous = false;
    let response = EventSurveyResponseFull {
        answers: sample_answers(),
        position: 1,
        summary: EventSurveyResponseSummary {
            answered_questions_count: 2,
            created_at: Utc.with_ymd_and_hms(2099, 5, 10, 9, 0, 0).unwrap(),
            user: sample_user_summary(user_id, "jane"),

            ticket_title: None,
            updated_at: None,
        },
        total: 1,

        next_user_id: None,
        previous_user_id: None,
    };

    // Setup database expectations
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_event_summary(&mut db, &ids, event_id);
    expect_get_event_survey(&mut db, &ids, event_id, event_survey_id, survey);
    db.expect_get_event_survey_response()
        .times(1)
        .returning(move |_, _, _, _, _| Ok(Some(response.clone())));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!(
            "/dashboard/group/events/{event_id}/surveys/{event_survey_id}/responses/{user_id}"
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check both navigation buttons are disabled and the details fall back
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = normalize_whitespace(&String::from_utf8_lossy(&bytes));
    assert!(html.contains("Respondent 1 of 1"));
    assert!(html.contains("No ticket"));
    assert!(!html.contains("Edited"));
    assert!(html.contains(r#"disabled data-event-survey-response-nav="previous""#));
    assert!(html.contains(r#"disabled data-event-survey-response-nav="next""#));
    assert!(!html.contains("/responses/"));
}

#[tokio::test]
async fn test_responses_page_without_responses_uses_default_bounds() {
    // Setup identifiers and an identified survey without responses
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_survey_id = Uuid::new_v4();
    let mut survey = sample_event_survey_full(event_survey_id);
    survey.summary.anonymous = false;
    let responses = EventSurveyResponsesOutput {
        responses: vec![],
        total: 0,
    };

    // Setup database expectations
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_event_summary(&mut db, &ids, event_id);
    expect_get_event_survey(&mut db, &ids, event_id, event_survey_id, survey);
    db.expect_list_event_survey_responses()
        .times(1)
        .withf(move |_, _, survey_id, filters| {
            *survey_id == event_survey_id
                && filters.limit == Some(EVENT_SURVEY_RESPONSES_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && filters.ts_query.is_none()
        })
        .returning(move |_, _, _, _| Ok(Some(responses.clone())));

    // Setup router and send request without a query string
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/surveys/{event_survey_id}/responses"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the empty state replaces the respondents search
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8_lossy(&bytes);
    assert!(html.contains("This survey does not have any responses yet."));
    assert!(!html.contains(r#"name="ts_query""#));
}

#[tokio::test]
async fn test_responses_page_rejects_anonymous_survey() {
    // Setup identifiers and an anonymous survey
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_survey_id = Uuid::new_v4();
    let survey = sample_event_survey_full(event_survey_id);

    // Setup database expectations
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_event_summary(&mut db, &ids, event_id);
    expect_get_event_survey(&mut db, &ids, event_id, event_survey_id, survey);
    db.expect_list_event_survey_responses().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/surveys/{event_survey_id}/responses"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the rejection
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8_lossy(&bytes),
        "individual responses are not available for anonymous surveys"
    );
}

#[tokio::test]
async fn test_responses_page_renders_no_results_for_unmatched_search() {
    // Setup identifiers and an identified survey without matching respondents
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_survey_id = Uuid::new_v4();
    let mut survey = sample_event_survey_full(event_survey_id);
    survey.summary.anonymous = false;
    let responses = EventSurveyResponsesOutput {
        responses: vec![],
        total: 0,
    };

    // Setup database expectations
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_event_summary(&mut db, &ids, event_id);
    expect_get_event_survey(&mut db, &ids, event_id, event_survey_id, survey);
    db.expect_list_event_survey_responses()
        .times(1)
        .withf(|_, _, _, filters| filters.ts_query.as_deref() == Some("nobody"))
        .returning(move |_, _, _, _| Ok(Some(responses.clone())));

    // Setup router and send request with a search
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!(
            "/dashboard/group/events/{event_id}/surveys/{event_survey_id}/responses?ts_query=nobody"
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the search stays editable above the no results state
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8_lossy(&bytes);
    assert!(html.contains(r#"value="nobody""#));
    assert!(html.contains("No respondents found matching your search."));
    assert!(!html.contains("This survey does not have any responses yet."));
}

#[tokio::test]
async fn test_responses_page_success() {
    // Setup identifiers and an identified survey with two respondents
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_survey_id = Uuid::new_v4();
    let jane_id = Uuid::new_v4();
    let mut survey = sample_event_survey_full(event_survey_id);
    survey.summary.anonymous = false;
    let mut jane = sample_user_summary(jane_id, "jane");
    jane.company = Some("Example <Corp>".to_string());
    jane.name = Some("Jane Doe".to_string());
    jane.title = Some("Engineer".to_string());
    let responses = EventSurveyResponsesOutput {
        responses: vec![
            EventSurveyResponseSummary {
                answered_questions_count: 2,
                created_at: Utc.with_ymd_and_hms(2099, 5, 10, 9, 0, 0).unwrap(),
                user: jane,

                ticket_title: Some("VIP <pass>".to_string()),
                updated_at: Some(Utc.with_ymd_and_hms(2099, 5, 12, 9, 0, 0).unwrap()),
            },
            EventSurveyResponseSummary {
                answered_questions_count: 1,
                created_at: Utc.with_ymd_and_hms(2099, 5, 10, 10, 0, 0).unwrap(),
                user: sample_user_summary(Uuid::new_v4(), "john"),

                ticket_title: None,
                updated_at: None,
            },
        ],
        total: 22,
    };

    // Setup database expectations
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_event_summary(&mut db, &ids, event_id);
    expect_get_event_survey(&mut db, &ids, event_id, event_survey_id, survey);
    db.expect_list_event_survey_responses()
        .times(1)
        .withf(move |group_id, survey_event_id, survey_id, filters| {
            *group_id == ids.group_id
                && *survey_event_id == event_id
                && *survey_id == event_survey_id
                && filters.limit == Some(EVENT_SURVEY_RESPONSES_PAGINATION_LIMIT)
                && filters.offset == Some(20)
                && filters.ts_query.as_deref() == Some("j")
        })
        .returning(move |_, _, _, _| Ok(Some(responses.clone())));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!(
            "/dashboard/group/events/{event_id}/surveys/{event_survey_id}/responses?offset=20&ts_query=j"
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the Individual view renders the searchable respondents table
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8_lossy(&bytes);
    assert!(html.contains("data-event-survey-responses"));
    assert!(html.contains(r#"id="event-survey-individual-view""#));
    assert!(html.contains(r#"aria-label="Survey respondents""#));
    assert!(html.contains(r#"name="ts_query""#));
    assert!(html.contains(r#"value="j""#));
    assert!(html.contains(r#"id="event-survey-response-modal""#));

    // Check the escaped respondent details, tickets, answered questions and dates
    assert!(html.contains("Jane Doe"));
    assert!(html.contains("Engineer · Example &#60;Corp&#62;"));
    assert!(html.contains("VIP &#60;pass&#62;"));
    assert!(!html.contains("<pass>"));
    assert!(html.contains("2 of 2"));
    assert!(html.contains("1 of 2"));
    assert!(html.contains("Edited May 12, 2099"));
    assert!(html.contains("john"));

    // Check rows open the responses keeping the search, and pages keep it too
    assert!(html.contains(&format!(
        r#"hx-get="/dashboard/group/events/{event_id}/surveys/{event_survey_id}/responses/{jane_id}?ts_query=j""#
    )));
    assert!(html.contains("ts_query=j"));
    assert!(html.contains("offset=0"));
}

#[tokio::test]
async fn test_results_page_success() {
    // Setup identifiers and the results of an anonymous survey with few responses
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_survey_id = Uuid::new_v4();
    let question_id = Uuid::new_v4();
    let mut survey = sample_event_survey_summary(event_survey_id, EventSurveyState::Open);
    survey.eligible_respondents_count = 2;
    survey.effective_opens_at = Some(Utc.with_ymd_and_hms(2099, 5, 10, 12, 0, 0).unwrap());
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
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_event_summary(&mut db, &ids, event_id);
    db.expect_get_event_survey_results()
        .times(1)
        .withf(move |group_id, survey_event_id, survey_id| {
            *group_id == ids.group_id
                && *survey_event_id == event_id
                && *survey_id == event_survey_id
        })
        .returning(move |_, _, _| Ok(Some(results.clone())));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/surveys/{event_survey_id}/results"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the escaped preview, the modal opener and the anonymity notice
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8_lossy(&bytes);
    assert!(html.contains("The &#60;b&#62;talks&#60;/b&#62;"));
    assert!(!html.contains("<b>talks</b>"));
    assert!(html.contains("View all 11 answers"));
    assert!(html.contains(&format!(
        r#"hx-get="/dashboard/group/events/{event_id}/surveys/{event_survey_id}/results/questions/{question_id}/answers""#
    )));
    assert!(html.contains(r#"id="event-survey-text-answers-modal""#));
    assert!(html.contains("data-event-survey-few-responses-notice"));
    assert!(html.contains("Anonymous surveys only show aggregated results."));

    // Check the header facts of the open survey
    assert!(html.contains("May 10, 2099</time>"));
    assert!(html.contains("1 question</span>"));
}

#[tokio::test]
async fn test_results_page_unknown_survey_returns_not_found() {
    // Setup identifiers and database expectations
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_event_summary(&mut db, &ids, event_id);
    db.expect_get_event_survey_results()
        .times(1)
        .returning(|_, _, _| Ok(None));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!(
            "/dashboard/group/events/{event_id}/surveys/{}/results",
            Uuid::new_v4()
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the response
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_text_answers_modal_rejects_long_search() {
    // Setup identifiers and a search above the length limit
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    db.expect_list_event_survey_text_answers().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!(
            "/dashboard/group/events/{event_id}/surveys/{}/results/questions/{}/answers?ts_query={}",
            Uuid::new_v4(),
            Uuid::new_v4(),
            "a".repeat(MAX_LEN_M + 1)
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the search is rejected before loading answers
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        std::str::from_utf8(&bytes).unwrap(),
        format!("ts_query: length is greater than {MAX_LEN_M}\n")
    );
}

#[tokio::test]
async fn test_text_answers_modal_success() {
    // Setup identifiers and the second page of answers matching a search
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_survey_id = Uuid::new_v4();
    let question_id = Uuid::new_v4();
    let answers = EventSurveyTextAnswersOutput {
        answers: vec!["More <b>breaks</b>".to_string()],
        position: 2,
        prompt: "What should we <i>improve</i>?".to_string(),
        total: 25,
    };

    // Setup database expectations
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    db.expect_list_event_survey_text_answers()
        .times(1)
        .withf(move |group_id, survey_event_id, survey_id, qid, filters| {
            *group_id == ids.group_id
                && *survey_event_id == event_id
                && *survey_id == event_survey_id
                && *qid == question_id
                && filters.limit == Some(EVENT_SURVEY_TEXT_ANSWERS_PAGINATION_LIMIT)
                && filters.offset == Some(10)
                && filters.ts_query.as_deref() == Some("breaks")
        })
        .returning(move |_, _, _, _, _| Ok(Some(answers.clone())));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!(
            "/dashboard/group/events/{event_id}/surveys/{event_survey_id}/results/questions/{question_id}/answers?offset=10&ts_query=breaks"
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the escaped prompt, answers and search
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8_lossy(&bytes);
    assert!(html.contains("What should we &#60;i&#62;improve&#60;/i&#62;?"));
    assert!(html.contains("More &#60;b&#62;breaks&#60;/b&#62;"));
    assert!(!html.contains("<b>breaks</b>"));
    assert!(html.contains(r#"value="breaks""#));

    // Check the previous and next pages keep the search
    assert!(html.contains("answers?limit=10&#38;offset=0&#38;ts_query=breaks"));
    assert!(html.contains("answers?limit=10&#38;offset=20&#38;ts_query=breaks"));
}

#[tokio::test]
async fn test_text_answers_modal_unknown_question_returns_not_found() {
    // Setup identifiers and database expectations
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_survey_id = Uuid::new_v4();
    let question_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    db.expect_list_event_survey_text_answers()
        .times(1)
        .withf(move |group_id, survey_event_id, survey_id, qid, _| {
            *group_id == ids.group_id
                && *survey_event_id == event_id
                && *survey_id == event_survey_id
                && *qid == question_id
        })
        .returning(|_, _, _, _, _| Ok(None));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!(
            "/dashboard/group/events/{event_id}/surveys/{event_survey_id}/results/questions/{question_id}/answers"
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the response
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_update_clears_custom_opening_and_closing_date() {
    // Setup identifiers and a form clearing both dates
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_survey_id = Uuid::new_v4();
    let body = "anonymous=true&audience=confirmed&title=Feedback&opens_at=&closes_at=&revision=4";

    // Setup database expectations
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);
    db.expect_update_event_survey()
        .times(1)
        .withf(
            move |actor_user_id,
                  group_id,
                  survey_event_id,
                  survey_id,
                  expected_revision,
                  survey| {
                *actor_user_id == ids.user_id
                    && *group_id == ids.group_id
                    && *survey_event_id == event_id
                    && *survey_id == event_survey_id
                    && *expected_revision == 4
                    && survey.closes_at.is_none()
                    && survey.opens_at.is_none()
            },
        )
        .returning(|_, _, _, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/group/events/{event_id}/surveys/{event_survey_id}/update"),
        ids.session_id,
        body,
    );
    let (parts, bytes) = send(router, request).await;

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
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_survey_id = Uuid::new_v4();
    let mut survey = sample_event_survey_full(event_survey_id);
    survey.summary.locked = true;

    // Setup database expectations
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);
    expect_event_summary(&mut db, &ids, event_id);
    expect_get_event_survey(&mut db, &ids, event_id, event_survey_id, survey);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/surveys/{event_survey_id}/update"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the form targets the update route and carries the revision
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8_lossy(&bytes);
    assert!(html.contains(&format!(
        r#"hx-put="/dashboard/group/events/{event_id}/surveys/{event_survey_id}/update""#
    )));
    assert!(html.contains(r#"name="revision" value="3""#));
    assert!(html.contains("data-event-survey-locked-notice"));
}

#[tokio::test]
async fn test_update_page_unknown_survey_returns_not_found() {
    // Setup identifiers and database expectations
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);
    expect_event_summary(&mut db, &ids, event_id);
    db.expect_get_event_survey().times(1).returning(|_, _, _| Ok(None));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!(
            "/dashboard/group/events/{event_id}/surveys/{}/update",
            Uuid::new_v4()
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the response
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_update_rejects_missing_revision() {
    // Setup identifiers and database expectations
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);
    db.expect_update_event_survey().never();

    // Setup router and send request without the loaded revision
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!(
            "/dashboard/group/events/{event_id}/surveys/{}/update",
            Uuid::new_v4()
        ),
        ids.session_id,
        "anonymous=true&audience=confirmed&title=Feedback",
    );
    let (parts, bytes) = send(router, request).await;

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
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_survey_id = Uuid::new_v4();
    let body = "anonymous=true&audience=confirmed&title=Feedback&questions_present=true&revision=2";

    // Setup database expectations
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);
    db.expect_update_event_survey()
        .times(1)
        .withf(move |_, _, _, survey_id, expected_revision, survey| {
            *survey_id == event_survey_id && *expected_revision == 2 && survey.questions.is_empty()
        })
        .returning(|_, _, _, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/group/events/{event_id}/surveys/{event_survey_id}/update"),
        ids.session_id,
        body,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the response
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        EVENT_SURVEYS_REFRESH_TRIGGER,
    );
}

// Helpers.

/// Expects the event summary read by survey pages.
fn expect_event_summary(db: &mut MockDB, ids: &DashboardIds, event_id: Uuid) {
    let ids = *ids;
    let event = sample_event_summary(event_id);
    db.expect_get_event_summary_dashboard()
        .times(1)
        .withf(move |community_id, group_id, survey_event_id| {
            *community_id == ids.community_id
                && *group_id == ids.group_id
                && *survey_event_id == event_id
        })
        .returning(move |_, _, _| Ok(event.clone()));
}

/// Expects the survey read by the update form and the Individual view.
fn expect_get_event_survey(
    db: &mut MockDB,
    ids: &DashboardIds,
    event_id: Uuid,
    event_survey_id: Uuid,
    survey: EventSurveyFull,
) {
    let ids = *ids;
    db.expect_get_event_survey()
        .times(1)
        .withf(move |group_id, survey_event_id, survey_id| {
            *group_id == ids.group_id
                && *survey_event_id == event_id
                && *survey_id == event_survey_id
        })
        .returning(move |_, _, _| Ok(Some(survey.clone())));
}

/// Expects the surveys read by the list page.
fn expect_list_event_surveys(
    db: &mut MockDB,
    ids: &DashboardIds,
    event_id: Uuid,
    surveys: Vec<EventSurveySummary>,
) {
    let ids = *ids;
    db.expect_list_event_surveys()
        .times(1)
        .withf(move |group_id, survey_event_id| {
            *group_id == ids.group_id && *survey_event_id == event_id
        })
        .returning(move |_, _| Ok(surveys.clone()));
}

/// Expects the export read by the CSV download, within the export bounds.
fn expect_survey_export(
    db: &mut MockDB,
    ids: &DashboardIds,
    event_id: Uuid,
    event_survey_id: Uuid,
    export: EventSurveyExport,
) {
    let ids = *ids;
    db.expect_get_event_survey_export()
        .times(1)
        .withf(
            move |group_id, survey_event_id, survey_id, max_rows, max_bytes| {
                *group_id == ids.group_id
                    && *survey_event_id == event_id
                    && *survey_id == event_survey_id
                    && *max_rows == MAX_EVENT_SURVEY_EXPORT_ROWS
                    && *max_bytes == MAX_EVENT_SURVEY_EXPORT_ANSWER_BYTES
            },
        )
        .returning(move |_, _, _, _, _| Ok(Some(export.clone())));
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
