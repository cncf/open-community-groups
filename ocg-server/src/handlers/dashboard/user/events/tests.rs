use axum::{
    body::Body,
    http::{HeaderValue, Request, StatusCode},
};
use serde_json::json;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    services::enrollment::{EnrollmentError, MockEnrollmentManager},
    types::{
        dashboard::user::events::{UserEvent, UserEventRole, UserEventsOutput},
        event::{EventEnrollmentStatus, EventLeaveOutcome},
        questionnaire::{QuestionnaireQuestion, QuestionnaireQuestionKind},
    },
    validation::MAX_LEN_QUESTIONNAIRE_ANSWER,
};

#[tokio::test]
async fn test_cancel_attendance_leaves_event_for_attendee() {
    // Setup identifiers and database mock
    let event_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);
    expect_attendance_reads(&mut db, &ids, event_id, EventEnrollmentStatus::Attendee);

    // Setup the enrollment manager expectation
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager
        .expect_leave_event()
        .times(1)
        .withf(move |input| {
            input.community_id == ids.community_id
                && input.event_id == event_id
                && input.user_id == ids.user_id
        })
        .returning(|_| {
            Box::pin(async {
                Ok(EventLeaveOutcome {
                    left_status: EventEnrollmentStatus::Attendee,
                })
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = attendance_request(event_id, &ids);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-user-dashboard-content",
    );
}

#[tokio::test]
async fn test_cancel_attendance_rejects_non_attendee_status() {
    // Setup identifiers and database mock for a waitlisted user
    let event_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);
    expect_attendance_reads(&mut db, &ids, event_id, EventEnrollmentStatus::Waitlisted);

    // Setup the enrollment manager, which must not leave the event
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager.expect_leave_event().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = attendance_request(event_id, &ids);
    let (parts, bytes) = send(router, request).await;

    // Check the user-state rejection is surfaced instead of a 500
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        bytes.as_ref(),
        b"only attendee attendance can be canceled from My Events"
    );
}

#[tokio::test]
async fn test_cancel_attendance_returns_manager_rejection() {
    // Setup identifiers and database mock
    let event_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);
    expect_attendance_reads(&mut db, &ids, event_id, EventEnrollmentStatus::Attendee);

    // Setup the enrollment manager rejecting the leave
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager.expect_leave_event().times(1).returning(|_| {
        Box::pin(async {
            Err(EnrollmentError::Rejected(
                "event has already started".to_string(),
            ))
        })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = attendance_request(event_id, &ids);
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), b"event has already started");
}

#[tokio::test]
async fn test_cancel_attendance_returns_not_found_when_community_is_unknown() {
    // Setup identifiers and database mock
    let event_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "missing-community")
        .returning(|_| Ok(None));

    // Setup the enrollment manager, which must not leave the event
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager.expect_leave_event().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = empty_request(
        "DELETE",
        &format!("/dashboard/user/events/missing-community/{event_id}/attendance"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_list_page_renders_labelled_free_text_answer_fields() {
    // Setup identifiers and an event with a free-text question
    let event_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let question_id = Uuid::new_v4();
    let output = UserEventsOutput {
        events: vec![UserEvent {
            manually_invited: true,
            registration_questions: vec![QuestionnaireQuestion {
                id: question_id,
                kind: QuestionnaireQuestionKind::FreeText,
                prompt: "What do you want to learn?".to_string(),
                required: false,

                options: vec![],
            }],
            roles: vec![UserEventRole::Attendee],
            ..sample_user_event(event_id)
        }],
        total: 1,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_list_user_events()
        .times(1)
        .withf(move |uid, _| *uid == ids.user_id)
        .returning(move |_, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user/events", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the free-text field is labelled by its prompt and bounded
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    let prompt_id = format!("question-{event_id}-{question_id}-prompt");
    assert!(body.contains(&format!("<legend id=\"{prompt_id}\"")));
    assert!(body.contains(&format!("aria-labelledby=\"{prompt_id}\"")));
    assert!(body.contains(&format!("maxlength=\"{MAX_LEN_QUESTIONNAIRE_ANSWER}\"")));
}

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and one listed event
    let event_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let output = UserEventsOutput {
        events: vec![sample_user_event(event_id)],
        total: 11,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_list_user_events()
        .times(1)
        .withf(move |uid, filters| {
            *uid == ids.user_id && filters.limit == Some(5) && filters.offset == Some(10)
        })
        .returning(move |_, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user/events?limit=5&offset=10", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the requested page renders and pushes the full dashboard URL
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url"),
        Some(&HeaderValue::from_static(
            "/dashboard/user?tab=events&limit=5&offset=10"
        )),
    );
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("Sample Event"));
}

#[tokio::test]
async fn test_submit_registration_answers_success() {
    // Setup identifiers and form data
    let event_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let question_id = Uuid::new_v4();
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
    expect_member_context(&mut db, &ids);

    // Setup the registration answers write without a transaction
    db.expect_begin().never();
    db.expect_submit_event_registration_answers()
        .times(1)
        .withf(move |actor_uid, cid, eid, registration_answers| {
            *actor_uid == ids.user_id
                && *cid == ids.community_id
                && *eid == event_id
                && registration_answers
                    .answers
                    .first()
                    .is_some_and(|answer| answer.question_id == question_id)
        })
        .returning(|_, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/user/events/test-community/{event_id}/registration-answers"),
        ids.session_id,
        form_body,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-user-dashboard-content",
    );
}

// Helpers.

/// Builds the request canceling the attendance in the test community.
fn attendance_request(event_id: Uuid, ids: &DashboardIds) -> Request<Body> {
    empty_request(
        "DELETE",
        &format!("/dashboard/user/events/test-community/{event_id}/attendance"),
        ids.session_id,
    )
}

/// Expects the enrollment read of the attendance route, returning the given
/// enrollment status.
fn expect_attendance_reads(
    db: &mut MockDB,
    ids: &DashboardIds,
    event_id: Uuid,
    status: EventEnrollmentStatus,
) {
    let DashboardIds {
        community_id,
        user_id,
        ..
    } = *ids;
    db.expect_get_event_enrollment()
        .times(1)
        .withf(move |cid, eid, uid| *cid == community_id && *eid == event_id && *uid == user_id)
        .returning(move |_, _, _| Ok(sample_enrollment_state(status.clone())));
}
