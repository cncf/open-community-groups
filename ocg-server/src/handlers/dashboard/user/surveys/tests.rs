use axum::http::StatusCode;
use chrono::{TimeZone, Utc};
use serde_json::json;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    types::{
        dashboard::{USER_EVENT_SURVEYS_PAGINATION_LIMIT, user::surveys::UserEventSurveysOutput},
        event_survey::EventSurveyState,
    },
};

#[tokio::test]
async fn test_list_page_rejects_limit_above_page_limit() {
    // Setup identifiers
    let ids = DashboardIds::new();

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_list_user_event_surveys().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user/surveys?limit=51", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the validation error names the limit
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        std::str::from_utf8(&bytes).unwrap(),
        "limit: greater than 50\n"
    );
}

#[tokio::test]
async fn test_list_page_renders_requested_page() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
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
    expect_session(&mut db, &ids);
    db.expect_list_user_event_surveys()
        .times(1)
        .withf(move |uid, filters| {
            *uid == ids.user_id
                && filters.limit == Some(USER_EVENT_SURVEYS_PAGINATION_LIMIT)
                && filters.offset == Some(10)
        })
        .returning(move |_, _| Ok(output.clone()));
    db.expect_get_user_event_survey().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user/surveys?offset=10", ids.session_id);
    let (parts, bytes) = send(router, request).await;

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
    let ids = DashboardIds::new();
    let output = UserEventSurveysOutput {
        surveys: vec![sample_user_event_survey_item(Uuid::from_u128(1), false)],
        total: 1,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_list_user_event_surveys()
        .times(1)
        .withf(move |uid, filters| {
            *uid == ids.user_id
                && filters.limit == Some(USER_EVENT_SURVEYS_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user/surveys", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the survey to answer is listed with its modal link
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("Session feedback"));
    assert!(body.contains("To answer"));
    assert!(
        body.contains(r#"hx-get="/dashboard/user/surveys/00000000-0000-0000-0000-000000000001""#)
    );
}

#[tokio::test]
async fn test_submit_response_rejects_invalid_answers() {
    // Setup identifiers and a form with answers to the same question twice
    let event_survey_id = Uuid::new_v4();
    let question_id = Uuid::new_v4();
    let ids = DashboardIds::new();
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
    expect_session(&mut db, &ids);
    db.expect_submit_event_survey_response().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/user/surveys/{event_survey_id}/response"),
        ids.session_id,
        form_body,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the validation error names the duplicated answers
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        std::str::from_utf8(&bytes).unwrap(),
        "answers: questionnaire answers must include each question at most once\n"
    );
}

#[tokio::test]
async fn test_submit_response_success() {
    // Setup identifiers and data structures
    let event_survey_id = Uuid::new_v4();
    let question_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let answers = json!({
        "answers": [{"question_id": question_id, "value": "Great"}]
    });
    let form_body =
        serde_urlencoded::to_string([("answers", answers.to_string()), ("revision", "4".into())])
            .unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_submit_event_survey_response()
        .times(1)
        .withf(move |sid, uid, revision, answers| {
            *sid == event_survey_id
                && *uid == ids.user_id
                && *revision == 4
                && answers
                    .answers
                    .first()
                    .is_some_and(|answer| answer.question_id == question_id)
        })
        .returning(|_, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/user/surveys/{event_survey_id}/response"),
        ids.session_id,
        form_body,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the answers were stored and the surveys reload
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-user-surveys",
    );
}

#[tokio::test]
async fn test_survey_modal_renders_open_survey() {
    // Setup identifiers and data structures
    let event_survey_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let survey = sample_user_event_survey(event_survey_id, Uuid::new_v4());

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_get_user_event_survey()
        .times(1)
        .withf(move |sid, uid| *sid == event_survey_id && *uid == ids.user_id)
        .returning(move |_, _| Ok(Some(survey.clone())));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/user/surveys/{event_survey_id}"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

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
    let ids = DashboardIds::new();

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_get_user_event_survey()
        .times(1)
        .withf(move |sid, uid| *sid == event_survey_id && *uid == ids.user_id)
        .returning(|_, _| Ok(None));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/user/surveys/{event_survey_id}"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the survey is not found
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}
