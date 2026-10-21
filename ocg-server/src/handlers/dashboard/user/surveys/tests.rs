use axum::{
    body::{Body, to_bytes},
    http::{
        Request, StatusCode,
        header::{CONTENT_TYPE, COOKIE},
        response::Parts,
    },
};
use axum_login::tower_sessions::session;
use chrono::{TimeZone, Utc};
use serde_json::json;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    services::notifications::MockNotificationsManager,
    types::{
        dashboard::{
            USER_EVENT_SURVEYS_PAGINATION_LIMIT,
            user::surveys::{UserEventSurveyResponse, UserEventSurveysOutput},
        },
        event_survey::EventSurveyState,
        questionnaire::{QuestionnaireAnswer, QuestionnaireAnswerValue, QuestionnaireAnswers},
    },
};

#[tokio::test]
async fn test_list_page_rejects_limit_above_page_limit() {
    // Setup identifiers
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_list_user_event_surveys().never();

    // Send the request
    let (parts, bytes) = send_request(
        db,
        session_id,
        "GET",
        "/dashboard/user/surveys?limit=51",
        Body::empty(),
    )
    .await;

    // Check the validation error
    assert_non_empty_response(&parts, &bytes, StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_list_page_renders_requested_page() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let event_survey_id = Uuid::from_u128(11);
    let mut closed = sample_user_event_survey_item(event_survey_id, true);
    closed.closed_at = Some(Utc.with_ymd_and_hms(2025, 5, 4, 8, 0, 0).unwrap());
    closed.state = EventSurveyState::Closed;
    let output = UserEventSurveysOutput {
        surveys: vec![closed],
        total: 11,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_list_user_event_surveys()
        .times(1)
        .withf(move |uid, filters| {
            *uid == user_id
                && filters.limit == Some(USER_EVENT_SURVEYS_PAGINATION_LIMIT)
                && filters.offset == Some(10)
        })
        .returning(move |_, _| Ok(output.clone()));
    db.expect_get_user_event_survey().never();

    // Send the request
    let (parts, bytes) = send_request(
        db,
        session_id,
        "GET",
        "/dashboard/user/surveys?offset=10",
        Body::empty(),
    )
    .await;

    // Check the page pushes its URL and lists the closed survey to review
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url").unwrap(),
        "/dashboard/user?tab=surveys&limit=10&offset=10"
    );
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains(&format!(r#"data-user-event-survey="{event_survey_id}""#)));
    assert!(body.contains("View answers"));
    assert!(body.contains("11 - 11 of"));
    assert!(body.contains(r#"hx-get="/dashboard/user?tab=surveys&#38;limit=10&#38;offset=10""#));
}

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let output = UserEventSurveysOutput {
        surveys: vec![sample_user_event_survey_item(Uuid::from_u128(1), false)],
        total: 1,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_list_user_event_surveys()
        .times(1)
        .withf(move |uid, filters| {
            *uid == user_id
                && filters.limit == Some(USER_EVENT_SURVEYS_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(output.clone()));

    // Send the request
    let (parts, bytes) = send_request(
        db,
        session_id,
        "GET",
        "/dashboard/user/surveys",
        Body::empty(),
    )
    .await;

    // Check the survey to answer is listed with its modal shell
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("Session feedback"));
    assert!(body.contains("To answer"));
    assert!(
        body.contains(r#"hx-get="/dashboard/user/surveys/00000000-0000-0000-0000-000000000001""#)
    );
    assert!(body.contains(r#"id="user-event-survey-modal""#));
    assert!(!body.contains("data-open-on-load"));
}

#[tokio::test]
async fn test_submit_response_rejects_invalid_answers() {
    // Setup identifiers and a form with answers to the same question twice
    let event_survey_id = Uuid::new_v4();
    let question_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let answers = json!({
        "answers": [
            {"question_id": question_id, "value": "Great"},
            {"question_id": question_id, "value": "Fine"}
        ]
    });
    let form_body =
        serde_urlencoded::to_string([("answers", answers.to_string()), ("revision", "4".into())])
            .unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_submit_event_survey_response().never();

    // Send the request
    let (parts, bytes) = send_request(
        db,
        session_id,
        "PUT",
        &format!("/dashboard/user/surveys/{event_survey_id}/response"),
        Body::from(form_body),
    )
    .await;

    // Check the validation error
    assert_non_empty_response(&parts, &bytes, StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_submit_response_success() {
    // Setup identifiers and data structures
    let event_survey_id = Uuid::new_v4();
    let question_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let answers = json!({
        "answers": [{"question_id": question_id, "value": "Great"}]
    });
    let form_body =
        serde_urlencoded::to_string([("answers", answers.to_string()), ("revision", "4".into())])
            .unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_submit_event_survey_response()
        .times(1)
        .withf(move |sid, uid, revision, answers| {
            *sid == event_survey_id
                && *uid == user_id
                && *revision == 4
                && answers
                    .answers
                    .first()
                    .is_some_and(|answer| answer.question_id == question_id)
        })
        .returning(|_, _, _, _| Ok(()));

    // Send the request
    let (parts, bytes) = send_request(
        db,
        session_id,
        "PUT",
        &format!("/dashboard/user/surveys/{event_survey_id}/response"),
        Body::from(form_body),
    )
    .await;

    // Check the answers were stored and the surveys reload
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-user-surveys",
    );
}

#[tokio::test]
async fn test_survey_modal_renders_closed_survey_read_only() {
    // Setup identifiers and a closed survey the user answered
    let event_survey_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut survey = sample_user_event_survey(event_survey_id, Uuid::new_v4());
    survey.closed_at = Some(Utc.with_ymd_and_hms(2025, 5, 4, 8, 0, 0).unwrap());
    survey.response = Some(UserEventSurveyResponse {
        answers: QuestionnaireAnswers {
            answers: vec![QuestionnaireAnswer {
                question_id: Uuid::from_u128(0x5d01),
                value: QuestionnaireAnswerValue::One("Well organized".to_string()),
            }],
        },
        created_at: Utc.with_ymd_and_hms(2025, 5, 1, 9, 0, 0).unwrap(),

        updated_at: None,
    });
    survey.state = EventSurveyState::Closed;

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_user_event_survey()
        .times(1)
        .withf(move |sid, uid| *sid == event_survey_id && *uid == user_id)
        .returning(move |_, _| Ok(Some(survey.clone())));

    // Send the request
    let (parts, bytes) = send_request(
        db,
        session_id,
        "GET",
        &format!("/dashboard/user/surveys/{event_survey_id}"),
        Body::empty(),
    )
    .await;

    // Check the answers are shown without a form to change them
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("Well organized"));
    assert!(body.contains("This survey is closed, so your answers can no longer be changed."));
    assert!(!body.contains("hx-put"));
}

#[tokio::test]
async fn test_survey_modal_renders_open_survey() {
    // Setup identifiers and data structures
    let event_survey_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let survey = sample_user_event_survey(event_survey_id, Uuid::new_v4());

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_user_event_survey()
        .times(1)
        .withf(move |sid, uid| *sid == event_survey_id && *uid == user_id)
        .returning(move |_, _| Ok(Some(survey.clone())));

    // Send the request
    let (parts, bytes) = send_request(
        db,
        session_id,
        "GET",
        &format!("/dashboard/user/surveys/{event_survey_id}"),
        Body::empty(),
    )
    .await;

    // Check the modal content submits to the survey response endpoint
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("Session feedback"));
    assert!(body.contains(&format!(
        r#"hx-put="/dashboard/user/surveys/{event_survey_id}/response""#
    )));
    assert!(!body.contains("data-user-event-survey-modal"));
}

#[tokio::test]
async fn test_survey_modal_returns_not_found_for_unavailable_survey() {
    // Setup identifiers
    let event_survey_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_user_event_survey()
        .times(1)
        .withf(move |sid, uid| *sid == event_survey_id && *uid == user_id)
        .returning(|_, _| Ok(None));

    // Send the request
    let (parts, bytes) = send_request(
        db,
        session_id,
        "GET",
        &format!("/dashboard/user/surveys/{event_survey_id}"),
        Body::empty(),
    )
    .await;

    // Check the survey is not found
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

// Helpers.

/// Sends an authenticated user dashboard request through the router.
async fn send_request(
    db: MockDB,
    session_id: session::Id,
    method: &str,
    uri: &str,
    body: Body,
) -> (Parts, axum::body::Bytes) {
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method(method)
        .uri(uri)
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(body)
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    (parts, bytes)
}
