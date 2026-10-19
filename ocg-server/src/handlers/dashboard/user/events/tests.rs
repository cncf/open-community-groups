use anyhow::anyhow;
use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderValue, Request, StatusCode,
        header::{CONTENT_TYPE, COOKIE},
    },
};
use axum_login::tower_sessions::session;
use serde_json::json;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    services::{
        enrollment::{EnrollmentError, MockEnrollmentManager},
        notifications::MockNotificationsManager,
    },
    types::{
        dashboard::{
            DASHBOARD_PAGINATION_LIMIT, USER_EVENT_SURVEYS_PAGINATION_LIMIT,
            user::events::{UserEventRole, UserEventSurveysFilters, UserEventSurveysOutput},
        },
        event::{EventEnrollmentState, EventEnrollmentStatus, EventLeaveOutcome},
        questionnaire::{QuestionnaireQuestion, QuestionnaireQuestionKind},
    },
    validation::MAX_LEN_QUESTIONNAIRE_ANSWER,
};

#[tokio::test]
async fn test_cancel_attendance_leaves_event_for_attendee() {
    // Setup identifiers and the attendee enrollment
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));
    db.expect_get_event_enrollment()
        .times(1)
        .withf(move |cid, eid, uid| *cid == community_id && *eid == event_id && *uid == user_id)
        .returning(|_, _, _| Ok(sample_enrollment_state(EventEnrollmentStatus::Attendee)));

    // Setup the enrollment manager expectation
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager
        .expect_leave_event()
        .times(1)
        .withf(move |input| {
            input.community_id == community_id
                && input.event_id == event_id
                && input.user_id == user_id
        })
        .returning(|_| {
            Box::pin(async {
                Ok(EventLeaveOutcome {
                    left_status: EventEnrollmentStatus::Attendee,
                })
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!(
            "/dashboard/user/events/test-community/{event_id}/attendance"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get("HX-Trigger"),
        Some(&HeaderValue::from_static("refresh-user-dashboard-content"))
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_cancel_attendance_returns_internal_server_error_when_manager_fails() {
    // Setup identifiers and an internal manager failure
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .returning(move |_| Ok(Some(community_id)));
    db.expect_get_event_enrollment()
        .times(1)
        .returning(|_, _, _| Ok(sample_enrollment_state(EventEnrollmentStatus::Attendee)));

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager.expect_leave_event().times(1).returning(|_| {
        Box::pin(async { Err(EnrollmentError::Other(anyhow!("queue unavailable"))) })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!(
            "/dashboard/user/events/test-community/{event_id}/attendance"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the internal failure is hidden
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_cancel_attendance_rejects_non_attendee_status() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));
    db.expect_get_event_enrollment()
        .times(1)
        .withf(move |cid, eid, uid| *cid == community_id && *eid == event_id && *uid == user_id)
        .returning(|_, _, _| {
            Ok(EventEnrollmentState {
                is_checked_in: false,
                status: EventEnrollmentStatus::Waitlisted,

                admission_offer_id: None,
                event_ticket_type_id: None,
                external_payment: None,
                manually_invited: false,
                purchase_amount_minor: None,
                purchase_charge_model: None,
                refund_rejection_reason: None,
                refund_request_status: None,
                resume_checkout_url: None,
            })
        });
    db.expect_leave_event().times(0);

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().times(0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!(
            "/dashboard/user/events/test-community/{event_id}/attendance"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the user-state rejection is surfaced instead of a 500
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        bytes.as_ref(),
        b"only attendee attendance can be canceled from My Events"
    );
}

#[tokio::test]
async fn test_cancel_attendance_returns_not_found_when_community_is_unknown() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "missing-community")
        .returning(|_| Ok(None));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().times(0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!(
            "/dashboard/user/events/missing-community/{event_id}/attendance"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NOT_FOUND);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_list_page_renders_labelled_free_text_answer_fields() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let question_id = Uuid::new_v4();
    let output = crate::types::dashboard::user::events::UserEventsOutput {
        events: vec![crate::types::dashboard::user::events::UserEvent {
            event: sample_event_summary(event_id, group_id),
            has_paid_purchase: false,
            manually_invited: true,
            registration_questions: vec![QuestionnaireQuestion {
                id: question_id,
                kind: QuestionnaireQuestionKind::FreeText,
                prompt: "What do you want to learn?".to_string(),
                required: false,

                options: vec![],
            }],
            roles: vec![UserEventRole::Attendee],

            admission_offer_id: None,
            admission_offer_source: None,
            admission_offer_status: None,
            amount_minor: None,
            currency_code: None,
            enrollment_status: Some(EventEnrollmentStatus::Attendee),
            event_ticket_type_id: None,
            external_payment: None,
            offer_expires_at: None,
            registration_answers: None,
            refund_rejection_reason: None,
            refund_request_status: None,
            resume_checkout_url: None,
            ticket_title: None,
        }],
        total: 1,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_list_user_events()
        .times(1)
        .withf(move |uid, _| *uid == user_id)
        .returning(move |_, _| Ok(output.clone()));
    expect_list_user_event_surveys(&mut db, user_id, empty_surveys_output());

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/user/events")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the free-text field is labelled by its prompt and bounded
    let prompt_id = format!("question-{event_id}-{question_id}-prompt");
    assert_eq!(parts.status, StatusCode::OK);
    assert!(body.contains(&format!("<legend id=\"{prompt_id}\"")));
    assert!(body.contains(&format!("aria-labelledby=\"{prompt_id}\"")));
    assert!(body.contains(&format!("maxlength=\"{MAX_LEN_QUESTIONNAIRE_ANSWER}\"")));
}

#[tokio::test]
async fn test_list_page_renders_surveys_panel() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let events_output = crate::types::dashboard::user::events::UserEventsOutput {
        events: vec![],
        total: 0,
    };
    let surveys_output = UserEventSurveysOutput {
        surveys: vec![sample_user_event_survey_item(Uuid::from_u128(1), false)],
        total: 11,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_list_user_events()
        .times(1)
        .withf(move |uid, _| *uid == user_id)
        .returning(move |_, _| Ok(events_output.clone()));
    expect_list_user_event_surveys(&mut db, user_id, surveys_output);

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/user/events")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the panel lists the survey and offers the next page
    assert_eq!(parts.status, StatusCode::OK);
    assert!(body.contains("Surveys to answer"));
    assert!(body.contains("Session feedback"));
    assert!(body.contains(r#"hx-get="/dashboard/user/events/surveys?offset=1""#));
}

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let output = crate::types::dashboard::user::events::UserEventsOutput {
        events: vec![crate::types::dashboard::user::events::UserEvent {
            event: sample_event_summary(event_id, group_id),
            has_paid_purchase: false,
            manually_invited: false,
            registration_questions: vec![],
            roles: vec![UserEventRole::Attendee, UserEventRole::Host],

            admission_offer_id: None,
            admission_offer_source: None,
            admission_offer_status: None,
            amount_minor: None,
            currency_code: None,
            enrollment_status: Some(EventEnrollmentStatus::Attendee),
            event_ticket_type_id: None,
            external_payment: None,
            offer_expires_at: None,
            registration_answers: None,
            refund_rejection_reason: None,
            refund_request_status: None,
            resume_checkout_url: None,
            ticket_title: None,
        }],
        total: 1,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_list_user_events()
        .times(1)
        .withf(move |uid, filters| {
            *uid == user_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(output.clone()));
    expect_list_user_event_surveys(&mut db, user_id, empty_surveys_output());

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/user/events")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8"),
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_list_page_with_pagination_params() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let output = crate::types::dashboard::user::events::UserEventsOutput {
        events: vec![],
        total: 0,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_list_user_events()
        .times(1)
        .withf(move |uid, filters| {
            *uid == user_id && filters.limit == Some(5) && filters.offset == Some(10)
        })
        .returning(move |_, _| Ok(output.clone()));
    expect_list_user_event_surveys(&mut db, user_id, empty_surveys_output());

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/user/events?limit=5&offset=10")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8"),
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_submit_registration_answers_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let question_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let answers = json!({
        "answers": [
            {
                "question_id": question_id,
                "value": "Vegetarian"
            }
        ]
    });
    let form_body =
        serde_urlencoded::to_string([("registration_answers", answers.to_string())]).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));

    // Setup the registration answers write without a transaction
    db.expect_begin().never();
    db.expect_submit_event_registration_answers()
        .times(1)
        .withf(move |actor_uid, cid, eid, registration_answers| {
            *actor_uid == user_id
                && *cid == community_id
                && *eid == event_id
                && registration_answers
                    .answers
                    .first()
                    .is_some_and(|answer| answer.question_id == question_id)
        })
        .returning(|_, _, _, _| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!(
            "/dashboard/user/events/test-community/{event_id}/registration-answers"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(form_body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get("hx-trigger").unwrap(),
        &HeaderValue::from_static("refresh-user-dashboard-content"),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_submit_registration_answers_update_skips_welcome_notification() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let question_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let answers = json!({
        "answers": [
            {
                "question_id": question_id,
                "value": "Vegetarian"
            }
        ]
    });
    let form_body =
        serde_urlencoded::to_string([("registration_answers", answers.to_string())]).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));

    // Setup the registration answers write without a transaction
    db.expect_begin().never();
    db.expect_submit_event_registration_answers()
        .times(1)
        .withf(move |actor_uid, cid, eid, registration_answers| {
            *actor_uid == user_id
                && *cid == community_id
                && *eid == event_id
                && registration_answers
                    .answers
                    .first()
                    .is_some_and(|answer| answer.question_id == question_id)
        })
        .returning(|_, _, _, _| Ok(()));
    db.expect_get_site_settings().times(0);
    db.expect_get_event_summary_by_id().times(0);

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().times(0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!(
            "/dashboard/user/events/test-community/{event_id}/registration-answers"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(form_body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get("hx-trigger").unwrap(),
        &HeaderValue::from_static("refresh-user-dashboard-content"),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_submit_survey_response_rejects_invalid_answers() {
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

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!(
            "/dashboard/user/events/surveys/{event_survey_id}/response"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(form_body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the validation error
    assert_non_empty_response(&parts, &bytes, StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_submit_survey_response_success() {
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

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!(
            "/dashboard/user/events/surveys/{event_survey_id}/response"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(form_body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the answers were stored and the dashboard refreshes
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get("hx-trigger").unwrap(),
        &HeaderValue::from_static("refresh-user-dashboard-content"),
    );
    assert!(bytes.is_empty());
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

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/dashboard/user/events/surveys/{event_survey_id}"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the modal content submits to the survey response endpoint
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("Session feedback"));
    assert!(body.contains(&format!(
        r#"hx-put="/dashboard/user/events/surveys/{event_survey_id}/response""#
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

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/dashboard/user/events/surveys/{event_survey_id}"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();

    // Check the survey is not found
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_surveys_page_rejects_limit_above_page_limit() {
    // Setup identifiers
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_list_user_event_surveys().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/user/events/surveys?limit=51")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the validation error
    assert_non_empty_response(&parts, &bytes, StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_surveys_page_renders_requested_page() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let event_survey_id = Uuid::from_u128(11);
    let output = UserEventSurveysOutput {
        surveys: vec![sample_user_event_survey_item(event_survey_id, true)],
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

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/user/events/surveys?offset=10")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the page items render without the panel or the next page button
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(parts.headers.get("hx-push-url").is_none());
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains(&format!(r#"data-user-event-survey="{event_survey_id}""#)));
    assert!(body.contains("Edit answers"));
    assert!(!body.contains("Surveys to answer"));
    assert!(!body.contains("Show more"));
}

// Helpers.

/// Returns an empty surveys panel page.
fn empty_surveys_output() -> UserEventSurveysOutput {
    UserEventSurveysOutput {
        surveys: vec![],
        total: 0,
    }
}

/// Expects the first surveys panel page read of the events list page.
fn expect_list_user_event_surveys(db: &mut MockDB, user_id: Uuid, output: UserEventSurveysOutput) {
    db.expect_list_user_event_surveys()
        .times(1)
        .withf(move |uid, filters: &UserEventSurveysFilters| {
            *uid == user_id
                && filters.limit == Some(USER_EVENT_SURVEYS_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(output.clone()));
}

/// Builds an enrollment state with the given status and no purchase data.
fn sample_enrollment_state(status: EventEnrollmentStatus) -> EventEnrollmentState {
    EventEnrollmentState {
        is_checked_in: false,
        status,

        admission_offer_id: None,
        event_ticket_type_id: None,
        external_payment: None,
        manually_invited: false,
        purchase_amount_minor: None,
        purchase_charge_model: None,
        refund_rejection_reason: None,
        refund_request_status: None,
        resume_checkout_url: None,
    }
}
