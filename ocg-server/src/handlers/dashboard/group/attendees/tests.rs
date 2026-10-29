use std::fmt::Write as _;

use axum::{
    body::Body,
    http::{
        HeaderValue, Request, StatusCode,
        header::{CONTENT_DISPOSITION, CONTENT_TYPE},
    },
};
use chrono::{TimeZone, Utc};
use mockall::Sequence;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::{
        dashboard::group::attendees::{
            EventCustomNotification, EventCustomNotificationRecipientScope,
        },
        error::{HandlerError, INVALID_REQUEST_PAYLOAD},
        tests::*,
    },
    services::{
        enrollment::{AdmissionAllocationOutcome, EnrollmentError, MockEnrollmentManager},
        payments::{MockPaymentsManager, PaymentsError},
    },
    types::{
        dashboard::{
            DASHBOARD_PAGINATION_LIMIT,
            group::{
                PresenceFilter,
                attendees::{
                    AttendeeEnrollmentStatus, AttendeeEnrollmentStatusFilter, AttendeesOutput,
                    AttendeesSort,
                },
            },
        },
        event::{EventAdmissionOfferStatus, EventEnrollmentReconciliationOutcome, EventSummary},
        notifications::{CustomNotificationContent, NotificationKind},
        payments::EventTicketType,
        permissions::GroupPermission,
        questionnaire::{
            QuestionnaireAnswer, QuestionnaireAnswerValue, QuestionnaireAnswers,
            QuestionnaireOption, QuestionnaireQuestion, QuestionnaireQuestionKind,
        },
    },
};

use super::MAX_ATTENDEES_EXPORT_ROWS;

#[tokio::test]
async fn test_accept_invitation_request_returns_conflict_when_queue_has_priority() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let target_user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager
        .expect_accept_invitation_request()
        .times(1)
        .returning(|_| {
            Box::pin(async {
                Ok(AdmissionAllocationOutcome::Conflict(
                    "queue-has-priority".to_string(),
                ))
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = form_request(
        "PUT",
        &format!(
            "/dashboard/group/events/{event_id}/attendees/{target_user_id}/invitation-request/accept"
        ),
        ids.session_id,
        "",
    );
    let (parts, bytes) = send(router, request).await;

    // Check the conflict payload and refresh triggers
    assert_eq!(parts.status, StatusCode::CONFLICT);
    assert_eq!(
        parts.headers.get("HX-Trigger").unwrap(),
        &HeaderValue::from_static(
            "refresh-event-attendees, refresh-event-invitation-requests, refresh-event-waitlist"
        ),
    );
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&bytes).unwrap(),
        serde_json::json!({
            "conflict": "queue-has-priority",
        })
    );
}

#[tokio::test]
async fn test_accept_invitation_request_returns_no_content() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let target_user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager
        .expect_accept_invitation_request()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == ids.user_id
                && input.event_id == event_id
                && input.group_id == ids.group_id
                && input.user_id == target_user_id
                && input.event_ticket_type_id == Some(event_ticket_type_id)
        })
        .returning(|_| Box::pin(async { Ok(AdmissionAllocationOutcome::Allocated) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = form_request(
        "PUT",
        &format!(
            "/dashboard/group/events/{event_id}/attendees/{target_user_id}/invitation-request/accept"
        ),
        ids.session_id,
        format!("event_ticket_type_id={event_ticket_type_id}"),
    );
    let (parts, bytes) = send(router, request).await;

    // Check the refresh triggers
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-event-attendees, refresh-event-invitation-requests, refresh-event-waitlist",
    );
}

#[tokio::test]
async fn test_accept_invitation_request_returns_rejection_message() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let target_user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup enrollment manager mock rejecting the acceptance
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager
        .expect_accept_invitation_request()
        .times(1)
        .withf(move |input| input.event_id == event_id && input.user_id == target_user_id)
        .returning(|_| {
            Box::pin(async {
                Err(EnrollmentError::Rejected(
                    "pending invitation request not found".to_string(),
                ))
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = form_request(
        "PUT",
        &format!(
            "/dashboard/group/events/{event_id}/attendees/{target_user_id}/invitation-request/accept"
        ),
        ids.session_id,
        "",
    );
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "pending invitation request not found"
    );
}

#[tokio::test]
async fn test_approve_refund_request_returns_no_content_when_payments_manager_succeeds() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_purchase_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup payments manager mock
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_approve_refund_request()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == ids.user_id
                && input.event_purchase_id == event_purchase_id
                && input.group_id == ids.group_id
                && input.review_note.is_none()
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/group/refunds/{event_purchase_id}/approve"),
        ids.session_id,
        "",
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-event-attendees, refresh-event-invitation-requests, refresh-event-waitlist, refresh-group-refunds",
    );
}

#[tokio::test]
async fn test_approve_refund_request_returns_rejection_message() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_purchase_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup payments manager mock rejecting the approval
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_approve_refund_request()
        .times(1)
        .withf(move |input| input.event_purchase_id == event_purchase_id)
        .returning(|_| {
            Box::pin(async {
                Err(PaymentsError::Rejected(
                    "refund request not found".to_string(),
                ))
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/group/refunds/{event_purchase_id}/approve"),
        ids.session_id,
        "",
    );
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "refund request not found"
    );
}

#[tokio::test]
async fn test_cancel_event_attendee_attendance_returns_no_content() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let target_user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager
        .expect_cancel_attendance_as_organizer()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == ids.user_id
                && input.community_id == ids.community_id
                && input.event_id == event_id
                && input.group_id == ids.group_id
                && input.user_id == target_user_id
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = empty_request(
        "DELETE",
        &format!("/dashboard/group/events/{event_id}/attendees/{target_user_id}/attendance"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the refresh triggers
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-event-attendees, refresh-event-invitation-requests, refresh-event-waitlist, refresh-group-refunds",
    );
}

#[tokio::test]
async fn test_cancel_event_attendee_attendance_returns_rejection_message() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let target_user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup enrollment manager mock rejecting the cancellation
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager
        .expect_cancel_attendance_as_organizer()
        .times(1)
        .withf(move |input| input.event_id == event_id && input.user_id == target_user_id)
        .returning(|_| {
            Box::pin(async {
                Err(EnrollmentError::Rejected(
                    "confirmed event attendee not found".to_string(),
                ))
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = empty_request(
        "DELETE",
        &format!("/dashboard/group/events/{event_id}/attendees/{target_user_id}/attendance"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "confirmed event attendee not found"
    );
}

#[tokio::test]
async fn test_cancel_event_offer_returns_no_content() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let admission_offer_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);
    db.expect_cancel_event_admission_offer()
        .times(1)
        .withf(move |actor_id, gid, oid, payment_provider| {
            *actor_id == ids.user_id
                && *gid == ids.group_id
                && *oid == admission_offer_id
                && payment_provider.is_none()
        })
        .returning(move |_, _, _, _| {
            Ok(EventEnrollmentReconciliationOutcome {
                community_id: ids.community_id,
                event_id: Uuid::from_u128(1),
                group_id: ids.group_id,
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/group/admission-offers/{admission_offer_id}/cancel"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-event-attendees, refresh-event-invitation-requests, refresh-event-waitlist",
    );
}

#[tokio::test]
async fn test_download_csv_rejects_event_above_supported_export_size() {
    // Setup identifiers and an attendee total above the export bound
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let output = AttendeesOutput {
        all_attendees_email_recipient_total: MAX_ATTENDEES_EXPORT_ROWS + 1,
        attendees: vec![sample_attendee()],
        total: MAX_ATTENDEES_EXPORT_ROWS + 1,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_export_reads(&mut db, &ids, event_id, output);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/attendees.csv"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the export is rejected with the supported size
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "attendee export supports up to 10000 confirmed attendees; this event has 10001",
    );
}

#[tokio::test]
async fn test_download_csv_returns_not_found_for_event_of_another_group() {
    // Setup identifiers
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();

    // Setup database mock without an event summary for the selected group
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    db.expect_find_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == ids.community_id && *gid == ids.group_id && *eid == event_id
        })
        .returning(|_, _, _| Ok(None));
    db.expect_search_event_attendees()
        .times(1)
        .withf(move |gid, eid, _| *gid == ids.group_id && *eid == event_id)
        .returning(|_, _, _| {
            Ok(AttendeesOutput {
                all_attendees_email_recipient_total: 0,
                attendees: vec![],
                total: 0,
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/attendees.csv"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the export is not found
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_download_csv_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut attendee = sample_attendee();
    attendee.created_at = Utc.with_ymd_and_hms(2024, 2, 3, 4, 5, 0).unwrap();
    attendee.user.name = Some("Doe, Jane".to_string());
    attendee.user.company = Some("Example \"Cloud\"".to_string());
    attendee.manually_invited = true;
    attendee.user.title = Some("Principal\nEngineer".to_string());
    let mut attendee_without_name = sample_attendee();
    attendee_without_name.user.name = None;
    attendee_without_name.user.username = "anonymous-attendee".to_string();
    attendee_without_name.user.company = None;
    attendee_without_name.user.title = None;
    let output = AttendeesOutput {
        all_attendees_email_recipient_total: 2,
        attendees: vec![attendee, attendee_without_name],
        total: 2,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_export_reads(&mut db, &ids, event_id, output);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/attendees.csv"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/csv; charset=utf-8"),
    );
    assert_eq!(
        parts.headers.get(CONTENT_DISPOSITION).unwrap(),
        &HeaderValue::from_static("attachment; filename=\"event-ghi9abc-attendees.csv\""),
    );
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "Name,Company,Title,Invited,Enrollment date,Payment method,Amount,Payment deadline,Paid at,Marked by,Payment details\n\"Doe, Jane\",\"Example \"\"Cloud\"\"\",\"Principal\nEngineer\",Yes,2024-02-03 04:05 UTC,,,,,,\nanonymous-attendee,,,No,2024-01-01 12:00 UTC,,,,,,\n",
    );
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_download_csv_with_answers_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let multi_option_id_1 = Uuid::new_v4();
    let multi_option_id_2 = Uuid::new_v4();
    let question_id_1 = Uuid::new_v4();
    let question_id_2 = Uuid::new_v4();
    let question_id_3 = Uuid::new_v4();
    let single_option_id = Uuid::new_v4();

    // Prefix a header, user fields and a free-text answer with formula characters
    let mut attendee = sample_attendee();
    attendee.user.name = Some("=HYPERLINK(\"https://example.com\")".to_string());
    attendee.user.company = Some("+Corp".to_string());
    attendee.user.title = Some("@Lead".to_string());
    attendee.registration_answers = Some(QuestionnaireAnswers {
        answers: vec![
            QuestionnaireAnswer {
                question_id: question_id_1,
                value: QuestionnaireAnswerValue::One("\tNo peanuts".to_string()),
            },
            QuestionnaireAnswer {
                question_id: question_id_2,
                value: QuestionnaireAnswerValue::One(single_option_id.to_string()),
            },
            QuestionnaireAnswer {
                question_id: question_id_3,
                value: QuestionnaireAnswerValue::Many(vec![multi_option_id_1, multi_option_id_2]),
            },
        ],
    });
    let mut attendee_without_answers = sample_attendee();
    attendee_without_answers.user.name = Some("No Answers".to_string());
    attendee_without_answers.registration_answers = None;
    let registration_questions = vec![
        QuestionnaireQuestion {
            id: question_id_1,
            kind: QuestionnaireQuestionKind::FreeText,
            prompt: "-Dietary restrictions?".to_string(),
            required: false,

            options: vec![],
        },
        QuestionnaireQuestion {
            id: question_id_2,
            kind: QuestionnaireQuestionKind::SingleSelect,
            prompt: "Meal preference".to_string(),
            required: true,

            options: vec![QuestionnaireOption {
                id: single_option_id,
                label: "Vegetarian".to_string(),
            }],
        },
        QuestionnaireQuestion {
            id: question_id_3,
            kind: QuestionnaireQuestionKind::MultiSelect,
            prompt: "Topics".to_string(),
            required: false,

            options: vec![
                QuestionnaireOption {
                    id: multi_option_id_1,
                    label: "Rust".to_string(),
                },
                QuestionnaireOption {
                    id: multi_option_id_2,
                    label: "Databases".to_string(),
                },
            ],
        },
    ];
    let output = AttendeesOutput {
        all_attendees_email_recipient_total: 2,
        attendees: vec![attendee, attendee_without_answers],
        total: 2,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_export_reads(&mut db, &ids, event_id, output);
    db.expect_get_event_registration_questions()
        .times(1)
        .withf(move |cid, eid| *cid == ids.community_id && *eid == event_id)
        .returning(move |_, _| Ok(registration_questions.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/attendees-with-answers.csv"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations, with every formula cell neutralized
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/csv; charset=utf-8"),
    );
    assert_eq!(
        parts.headers.get(CONTENT_DISPOSITION).unwrap(),
        &HeaderValue::from_static(
            "attachment; filename=\"event-ghi9abc-attendees-with-answers.csv\""
        ),
    );
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        concat!(
            "Name,Company,Title,Invited,Enrollment date,Payment method,Amount,Payment deadline,",
            "Paid at,Marked by,Payment details,'-Dietary restrictions?,Meal preference,Topics\n",
            "\"'=HYPERLINK(\"\"https://example.com\"\")\",'+Corp,'@Lead,No,2024-01-01 12:00 UTC,",
            ",,,,,,'\tNo peanuts,Vegetarian,\"Rust, Databases\"\n",
            "No Answers,Example,Engineer,No,2024-01-01 12:00 UTC,,,,,,,,,\n",
        ),
    );
}

#[tokio::test]
async fn test_download_csv_with_answers_returns_not_found_for_event_of_another_group() {
    // Setup identifiers
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();

    // Setup database mock without an event summary for the selected group
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    db.expect_find_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == ids.community_id && *gid == ids.group_id && *eid == event_id
        })
        .returning(|_, _, _| Ok(None));
    db.expect_get_event_registration_questions().never();
    db.expect_search_event_attendees().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/attendees-with-answers.csv"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the export is not found before loading attendee data
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_invite_event_attendee_returns_bad_request_when_target_conflicts() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let invited_user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager.expect_invite_event_attendee().times(0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = form_request(
        "POST",
        &format!("/dashboard/group/events/{event_id}/attendees/invite"),
        ids.session_id,
        format!("user_id={invited_user_id}&email=invitee%40example.com"),
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "provide exactly one invite target"
    );
}

#[tokio::test]
async fn test_invite_event_attendee_returns_bad_request_when_target_missing() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager.expect_invite_event_attendee().times(0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = form_request(
        "POST",
        &format!("/dashboard/group/events/{event_id}/attendees/invite"),
        ids.session_id,
        "",
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "provide exactly one invite target"
    );
}

#[tokio::test]
async fn test_invite_event_attendee_returns_created_for_email_target() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let ticket_type_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager
        .expect_invite_event_attendee()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == ids.user_id
                && input.event_id == event_id
                && input.group_id == ids.group_id
                && input.email.as_deref() == Some("Invitee@Example.com")
                && input.event_ticket_type_id == Some(ticket_type_id)
                && input.user_id.is_none()
        })
        .returning(|_| Box::pin(async { Ok(AdmissionAllocationOutcome::Allocated) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = form_request(
        "POST",
        &format!("/dashboard/group/events/{event_id}/attendees/invite"),
        ids.session_id,
        format!("email=Invitee%40Example.com&event_ticket_type_id={ticket_type_id}"),
    );
    let (parts, bytes) = send(router, request).await;

    // Check the refresh triggers
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::CREATED,
        "refresh-event-attendees, refresh-event-invitation-requests, refresh-event-waitlist",
    );
}

#[tokio::test]
async fn test_invite_event_attendee_returns_created_for_registered_user() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let invitee_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager
        .expect_invite_event_attendee()
        .times(1)
        .withf(move |input| {
            input.email.is_none()
                && input.event_ticket_type_id.is_none()
                && input.user_id == Some(invitee_id)
        })
        .returning(|_| Box::pin(async { Ok(AdmissionAllocationOutcome::Allocated) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = form_request(
        "POST",
        &format!("/dashboard/group/events/{event_id}/attendees/invite"),
        ids.session_id,
        format!("user_id={invitee_id}"),
    );
    let (parts, bytes) = send(router, request).await;

    // Check the refresh triggers
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::CREATED,
        "refresh-event-attendees, refresh-event-invitation-requests, refresh-event-waitlist",
    );
}

#[tokio::test]
async fn test_invite_event_attendee_returns_rejection_message() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let invitee_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup enrollment manager mock rejecting the invitation
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager
        .expect_invite_event_attendee()
        .times(1)
        .withf(move |input| input.event_id == event_id && input.user_id == Some(invitee_id))
        .returning(|_| {
            Box::pin(async {
                Err(EnrollmentError::Rejected(
                    "user is already attending this event".to_string(),
                ))
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = form_request(
        "POST",
        &format!("/dashboard/group/events/{event_id}/attendees/invite"),
        ids.session_id,
        format!("user_id={invitee_id}"),
    );
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "user is already attending this event"
    );
}

#[tokio::test]
async fn test_invite_event_attendee_returns_ticket_type_sold_out_conflict() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let ticket_type_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager
        .expect_invite_event_attendee()
        .times(1)
        .returning(|_| {
            Box::pin(async {
                Ok(AdmissionAllocationOutcome::Conflict(
                    "ticket-type-sold-out".to_string(),
                ))
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = form_request(
        "POST",
        &format!("/dashboard/group/events/{event_id}/attendees/invite"),
        ids.session_id,
        format!("email=invitee%40example.com&event_ticket_type_id={ticket_type_id}"),
    );
    let (parts, bytes) = send(router, request).await;

    // Check the conflict payload and refresh triggers
    assert_eq!(parts.status, StatusCode::CONFLICT);
    assert_eq!(
        parts.headers.get("HX-Trigger").unwrap(),
        &HeaderValue::from_static(
            "refresh-event-attendees, refresh-event-invitation-requests, refresh-event-waitlist"
        ),
    );
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&bytes).unwrap(),
        serde_json::json!({
            "conflict": "ticket-type-sold-out",
        }),
    );
}

#[tokio::test]
async fn test_invite_event_attendee_returns_unprocessable_entity_when_email_is_invalid() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager.expect_invite_event_attendee().times(0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = form_request(
        "POST",
        &format!("/dashboard/group/events/{event_id}/attendees/invite"),
        ids.session_id,
        "email=not-an-email",
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "email: not a valid email: value is missing `@`\n"
    );
}

#[tokio::test]
async fn test_list_page_disables_reissue_for_sold_out_ticket_type() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let available_ticket_type_id = Uuid::from_u128(1);
    let event_id = Uuid::new_v4();
    let sold_out_ticket_type_id = Uuid::from_u128(2);
    let event = EventSummary {
        ticket_types: Some(vec![
            EventTicketType {
                active: true,
                event_ticket_type_id: available_ticket_type_id,
                title: "General admission".to_string(),
                ..Default::default()
            },
            EventTicketType {
                active: true,
                event_ticket_type_id: sold_out_ticket_type_id,
                title: "Early bird".to_string(),

                sold_out: true,
                ..Default::default()
            },
        ]),
        ..sample_event_summary(event_id)
    };
    let mut available_attendee = sample_attendee();
    available_attendee.checked_in = false;
    available_attendee.enrollment_status = AttendeeEnrollmentStatus::InvitationExpired;
    available_attendee.admission_offer_status = Some(EventAdmissionOfferStatus::Expired);
    available_attendee.event_ticket_type_id = Some(available_ticket_type_id);
    let mut sold_out_attendee = sample_attendee();
    sold_out_attendee.checked_in = false;
    sold_out_attendee.enrollment_status = AttendeeEnrollmentStatus::InvitationExpired;
    sold_out_attendee.user.user_id = Uuid::new_v4();
    sold_out_attendee.admission_offer_status = Some(EventAdmissionOfferStatus::Expired);
    sold_out_attendee.event_ticket_type_id = Some(sold_out_ticket_type_id);
    let output = AttendeesOutput {
        all_attendees_email_recipient_total: 2,
        attendees: vec![available_attendee, sold_out_attendee],
        total: 2,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_list_page_context(&mut db, &ids, event, true);
    db.expect_search_event_attendees()
        .times(1)
        .withf(move |gid, eid, _| *gid == ids.group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/attendees"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check both reissue actions render and only the sold-out one is disabled
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert_eq!(body.matches("Reissue invitation").count(), 2);
    assert_eq!(
        body.matches(
            "disabled title=\"This ticket type is sold out. Add seats or cancel a pending offer before reissuing this invitation.\""
        )
        .count(),
        1
    );
}

#[tokio::test]
async fn test_list_page_rejects_too_many_ticket_type_ids() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);

    // Setup router and send request with one ticket type over the limit
    let router = TestRouterBuilder::new(db).build().await;
    let mut query = String::new();
    for index in 0..=25 {
        if !query.is_empty() {
            query.push('&');
        }
        write!(
            &mut query,
            "event_ticket_type_ids[{index}]=00000000-0000-0000-0000-000000000000"
        )
        .unwrap();
    }
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/attendees?{query}"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "event_ticket_type_ids: length is greater than 25\n"
    );
}

#[tokio::test]
async fn test_list_page_rejects_zero_pagination_limit() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/attendees?limit=0"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "limit: lower than 1\n"
    );
}

#[tokio::test]
async fn test_list_page_returns_not_found_for_event_of_another_group() {
    // Setup identifiers
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();

    // Setup database mock without an event summary for the selected group
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    db.expect_find_event_summary_dashboard()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == ids.community_id && *gid == ids.group_id && *eid == event_id
        })
        .returning(|_, _, _| Ok(None));
    db.expect_get_event_registration_questions().never();
    db.expect_search_event_attendees().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/attendees"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the page is not found before loading attendee data
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_list_page_steps_back_to_last_page_when_offset_is_past_end() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let empty_page = AttendeesOutput {
        all_attendees_email_recipient_total: 0,
        attendees: vec![],
        total: 6,
    };
    let last_page = AttendeesOutput {
        all_attendees_email_recipient_total: 0,
        attendees: vec![sample_attendee()],
        total: 6,
    };

    // Setup session, permission, and event context expectations
    let mut db = MockDB::new();
    expect_list_page_context(&mut db, &ids, sample_event_summary(event_id), true);

    // Setup the empty requested page followed by the last page with rows
    let mut sequence = Sequence::new();
    db.expect_search_event_attendees()
        .times(1)
        .in_sequence(&mut sequence)
        .withf(move |gid, eid, filters| {
            *gid == ids.group_id
                && *eid == event_id
                && filters.limit == Some(5)
                && filters.offset == Some(10)
        })
        .return_once(move |_, _, _| Ok(empty_page));
    db.expect_search_event_attendees()
        .times(1)
        .in_sequence(&mut sequence)
        .withf(move |gid, eid, filters| {
            *gid == ids.group_id
                && *eid == event_id
                && filters.limit == Some(5)
                && filters.offset == Some(5)
        })
        .return_once(move |_, _, _| Ok(last_page));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/attendees?limit=5&offset=10"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the last page with rows is rendered and refreshed in place
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("Event Attendee"));
    assert!(body.contains("offset=5"));
    assert!(!body.contains("offset=10"));

    // Check the email action explains the missing recipients
    assert!(body.contains(
        "No attendees with verified email addresses who accept messages from event organizers."
    ));
}

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut attendee = sample_attendee();
    attendee.checked_in = false;
    attendee.manually_invited = true;
    let pending_questions_attendee_id = Uuid::new_v4();
    let mut pending_questions_attendee = sample_attendee();
    pending_questions_attendee.checked_in = false;
    pending_questions_attendee.enrollment_status = AttendeeEnrollmentStatus::RegistrationPending;
    pending_questions_attendee.manually_invited = false;
    pending_questions_attendee.user.user_id = pending_questions_attendee_id;
    let output = AttendeesOutput {
        all_attendees_email_recipient_total: 2,
        attendees: vec![attendee, pending_questions_attendee],
        total: 2,
    };

    // Setup database mock for a user who cannot manage events
    let mut db = MockDB::new();
    expect_list_page_context(&mut db, &ids, sample_event_summary(event_id), false);
    db.expect_search_event_attendees()
        .times(1)
        .withf(move |gid, eid, filters| {
            *gid == ids.group_id
                && *eid == event_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && filters.status.is_none()
        })
        .returning(move |_, _, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/attendees"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("id=\"attendees-enrollment-status\""));
    assert!(body.contains("name=\"status\"") && !body.contains("name=\"attendance\""));
    assert!(body.contains(&pending_questions_attendee_id.to_string()));
    assert!(body.contains("Invited"));
    assert!(body.contains("Check in attendee"));
    assert!(!body.contains("Your role cannot manage check-in"));
    let email_actions = body.find("id=\"attendee-email-actions-button\"").unwrap();
    let management_container = body[..email_actions].rfind("<div class=").unwrap();
    assert!(body[management_container..email_actions].contains("hidden"));
    assert!(!body.contains("id=\"open-attendee-invitation-modal\""));
}

#[tokio::test]
async fn test_list_page_with_search_query() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let ticket_type_id = Uuid::new_v4();
    let mut attendee = sample_attendee();
    attendee.email = "ana@example.test".to_string();
    attendee.user.name = Some("Ana Lopez".to_string());
    attendee.user.company = Some("Example Co".to_string());
    let output = AttendeesOutput {
        all_attendees_email_recipient_total: 1,
        attendees: vec![attendee],
        total: 1,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_list_page_context(&mut db, &ids, sample_event_summary(event_id), true);
    db.expect_search_event_attendees()
        .times(1)
        .withf(move |gid, eid, filters| {
            *gid == ids.group_id
                && *eid == event_id
                && filters.checked_in == Some(true)
                && filters.event_ticket_type_ids.as_deref() == Some(&[ticket_type_id][..])
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && filters.sort == Some(AttendeesSort::CreatedAtDesc)
                && filters.status == Some(AttendeeEnrollmentStatusFilter::History)
                && filters.title == Some(PresenceFilter::Present)
                && filters.ts_query.as_deref() == Some("ana")
        })
        .returning(move |_, _, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!(
            concat!(
                "/dashboard/group/events/{event_id}/attendees?",
                "checked_in=true&event_ticket_type_ids[0]={ticket_type_id}&",
                "sort=created-at-desc&status=history&title=present&ts_query=ana"
            ),
            event_id = event_id,
            ticket_type_id = ticket_type_id,
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("name=\"ts_query\"") && body.contains("value=\"ana\""));
    assert!(body.contains("Ana Lopez"));
    assert!(body.contains("ana@example.test"));
    assert!(body.contains("Example Co"));
    assert!(body.contains("refresh-event-attendees"));
}

#[tokio::test]
async fn test_manual_check_in_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let target_user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::CheckInsWrite);
    db.expect_check_in_event()
        .times(1)
        .withf(move |actor_uid, cid, eid, gid, uid| {
            *actor_uid == ids.user_id
                && *cid == ids.community_id
                && *eid == event_id
                && *gid == ids.group_id
                && *uid == target_user_id
        })
        .returning(|_, _, _, _, _| Ok(true));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "POST",
        &format!("/dashboard/group/events/{event_id}/attendees/{target_user_id}/check-in"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_mark_external_payment_returns_rejection_message() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Reject the purchase from the payments manager
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_complete_external_checkout()
        .times(1)
        .withf(move |actor_uid, gid, purchase_id, _details| {
            *actor_uid == ids.user_id && *gid == ids.group_id && *purchase_id == event_purchase_id
        })
        .returning(|_, _, _, _| {
            Box::pin(async { Err(PaymentsError::Rejected("purchase not found".to_string())) })
        });

    // Submit the mark-paid form
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = external_payment_request(&ids, event_id, event_purchase_id, "details=wire+123");
    let (parts, bytes) = send(router, request).await;

    // Check the rejection is returned as a user-facing error
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "purchase not found"
    );
}

#[tokio::test]
async fn test_mark_external_payment_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Mark the purchase paid through the payments manager
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_complete_external_checkout()
        .times(1)
        .withf(move |actor_uid, gid, purchase_id, details| {
            *actor_uid == ids.user_id
                && *gid == ids.group_id
                && *purchase_id == event_purchase_id
                && details.as_deref() == Some("wire 123")
        })
        .returning(|_, _, _, _| Box::pin(async { Ok(()) }));

    // Submit the mark-paid form
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = external_payment_request(&ids, event_id, event_purchase_id, "details=wire+123");
    let (parts, bytes) = send(router, request).await;

    // Check the enrollment tabs refresh trigger
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-event-attendees, refresh-event-invitation-requests, refresh-event-waitlist",
    );
}

#[tokio::test]
async fn test_mark_external_payment_success_with_blank_details() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Mark the purchase paid without optional details
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_complete_external_checkout()
        .times(1)
        .withf(move |actor_uid, gid, purchase_id, details| {
            *actor_uid == ids.user_id
                && *gid == ids.group_id
                && *purchase_id == event_purchase_id
                && details.is_none()
        })
        .returning(|_, _, _, _| Box::pin(async { Ok(()) }));

    // Submit the mark-paid form with an empty details field
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = external_payment_request(&ids, event_id, event_purchase_id, "details=");
    let (parts, bytes) = send(router, request).await;

    // Check the enrollment tabs refresh trigger
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-event-attendees, refresh-event-invitation-requests, refresh-event-waitlist",
    );
}

#[tokio::test]
async fn test_mark_external_payment_success_with_empty_body() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Mark the purchase paid without optional details
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_complete_external_checkout()
        .times(1)
        .withf(move |actor_uid, gid, purchase_id, details| {
            *actor_uid == ids.user_id
                && *gid == ids.group_id
                && *purchase_id == event_purchase_id
                && details.is_none()
        })
        .returning(|_, _, _, _| Box::pin(async { Ok(()) }));

    // Submit the mark-paid form with an empty body
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = external_payment_request(&ids, event_id, event_purchase_id, "");
    let (parts, bytes) = send(router, request).await;

    // Check the enrollment tabs refresh trigger
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-event-attendees, refresh-event-invitation-requests, refresh-event-waitlist",
    );
}

#[tokio::test]
async fn test_reject_invitation_request_returns_no_content() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let target_user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);
    db.expect_reject_event_invitation_request()
        .times(1)
        .withf(move |actor_id, gid, eid, uid| {
            *actor_id == ids.user_id
                && *gid == ids.group_id
                && *eid == event_id
                && *uid == target_user_id
        })
        .returning(|_, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "PUT",
        &format!(
            "/dashboard/group/events/{event_id}/attendees/{target_user_id}/invitation-request/reject"
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-event-attendees, refresh-event-invitation-requests, refresh-event-waitlist",
    );
}

#[tokio::test]
async fn test_reject_refund_request_rejects_missing_reason_as_invalid_payload() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_purchase_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Reject invalid input before calling the payments manager
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_reject_refund_request().never();

    // Submit a rejection without the required reason field
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/group/refunds/{event_purchase_id}/reject"),
        ids.session_id,
        "",
    );
    let (parts, bytes) = send(router, request).await;

    // Check deserialization fails without side effects
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), INVALID_REQUEST_PAYLOAD.as_bytes());
}

#[tokio::test]
async fn test_reject_refund_request_rejects_whitespace_reason_without_calling_payments_manager() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_purchase_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Reject invalid input before calling the payments manager
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_reject_refund_request().never();

    // Submit a rejection with a whitespace-only reason
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/group/refunds/{event_purchase_id}/reject"),
        ids.session_id,
        "review_note=%20%20%20",
    );
    let (parts, bytes) = send(router, request).await;

    // Check validation fails without side effects
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "review_note: value cannot be empty or whitespace-only\n"
    );
}

#[tokio::test]
async fn test_reject_refund_request_returns_no_content_when_payments_manager_succeeds() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_purchase_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup payments manager mock
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_reject_refund_request()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == ids.user_id
                && input.event_purchase_id == event_purchase_id
                && input.group_id == ids.group_id
                && input.review_note == "Outside the refund policy window"
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/group/refunds/{event_purchase_id}/reject"),
        ids.session_id,
        "review_note=Outside+the+refund+policy+window",
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-event-attendees, refresh-group-refunds",
    );
}

#[tokio::test]
async fn test_reject_refund_request_returns_rejection_message() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_purchase_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup payments manager mock rejecting the refund rejection
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_reject_refund_request()
        .times(1)
        .withf(move |input| input.event_purchase_id == event_purchase_id)
        .returning(|_| {
            Box::pin(async {
                Err(HandlerError::Database("refund request not found".to_string()).into())
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/group/refunds/{event_purchase_id}/reject"),
        ids.session_id,
        "review_note=Outside+the+refund+policy+window",
    );
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "refund request not found"
    );
}

#[tokio::test]
async fn test_send_event_custom_notification_no_recipients() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);
    db.expect_get_event_summary_by_id().never();
    db.expect_resolve_event_custom_notification_recipient_ids()
        .times(1)
        .withf(move |gid, eid, recipient_scope, requested_user_ids| {
            *gid == ids.group_id
                && *eid == event_id
                && recipient_scope == "all-attendees"
                && requested_user_ids.is_none()
        })
        .returning(move |_, _, _, _| Ok(vec![]));
    db.expect_get_site_settings().never();
    db.expect_enqueue_tracked_custom_notification().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = custom_notification_request(
        &ids,
        event_id,
        EventCustomNotificationRecipientScope::All,
        vec![],
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "No attendees with verified email addresses who accept messages from event organizers."
    );
}

#[tokio::test]
async fn test_send_event_custom_notification_parses_flattened_content() {
    // Setup identifiers and a raw form using the legacy title field
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let attendee_id = Uuid::new_v4();
    let form_data = format!(
        "body=Hello+there&recipient_scope=selected\
         &recipient_user_ids%5B0%5D={attendee_id}&title=Legacy+Title"
    );

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);
    db.expect_resolve_event_custom_notification_recipient_ids()
        .times(1)
        .withf(move |_, _, recipient_scope, requested_user_ids| {
            recipient_scope == "selected-attendees"
                && requested_user_ids.as_deref() == Some(&[attendee_id][..])
        })
        .returning(move |_, _, _, _| Ok(vec![attendee_id]));
    expect_custom_notification_context(&mut db, &ids, event_id);
    db.expect_enqueue_tracked_custom_notification()
        .times(1)
        .withf(|_, tracking| tracking.body == "Hello there" && tracking.subject == "Legacy Title")
        .returning(|_, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "POST",
        &format!("/dashboard/group/notifications/{event_id}"),
        ids.session_id,
        form_data,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_send_event_custom_notification_selected_recipients_no_eligible_recipients() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let requested_attendee_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);
    db.expect_get_event_summary_by_id().never();
    db.expect_resolve_event_custom_notification_recipient_ids()
        .times(1)
        .withf(move |gid, eid, recipient_scope, requested_user_ids| {
            *gid == ids.group_id
                && *eid == event_id
                && recipient_scope == "selected-attendees"
                && requested_user_ids.as_deref() == Some(&[requested_attendee_id][..])
        })
        .returning(move |_, _, _, _| Ok(vec![]));
    db.expect_get_site_settings().never();
    db.expect_enqueue_tracked_custom_notification().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = custom_notification_request(
        &ids,
        event_id,
        EventCustomNotificationRecipientScope::Selected,
        vec![requested_attendee_id],
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "No selected attendees can receive this email."
    );
}

#[tokio::test]
async fn test_send_event_custom_notification_selected_recipients_requires_selection() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = custom_notification_request(
        &ids,
        event_id,
        EventCustomNotificationRecipientScope::Selected,
        vec![],
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "Select at least one attendee."
    );
}

#[tokio::test]
async fn test_send_event_custom_notification_selected_recipients_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let filtered_out_attendee_id = Uuid::new_v4();
    let selected_attendee_id = Uuid::new_v4();
    let requested_recipient_ids = vec![selected_attendee_id, filtered_out_attendee_id];
    let expected_requested_recipient_ids = requested_recipient_ids.clone();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);
    db.expect_resolve_event_custom_notification_recipient_ids()
        .times(1)
        .withf(move |gid, eid, recipient_scope, requested_user_ids| {
            *gid == ids.group_id
                && *eid == event_id
                && recipient_scope == "selected-attendees"
                && requested_user_ids.as_ref() == Some(&expected_requested_recipient_ids)
        })
        .returning(move |_, _, _, _| Ok(vec![selected_attendee_id]));
    expect_custom_notification_context(&mut db, &ids, event_id);
    db.expect_enqueue_tracked_custom_notification()
        .times(1)
        .withf(move |notification, tracking| {
            matches!(notification.kind, NotificationKind::EventCustom)
                && notification.recipients == vec![selected_attendee_id]
                && tracking.created_by == ids.user_id
        })
        .returning(|_, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = custom_notification_request(
        &ids,
        event_id,
        EventCustomNotificationRecipientScope::Selected,
        requested_recipient_ids,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_send_event_custom_notification_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let attendee_id1 = Uuid::new_v4();
    let attendee_id2 = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);
    db.expect_resolve_event_custom_notification_recipient_ids()
        .times(1)
        .withf(move |gid, eid, recipient_scope, requested_user_ids| {
            *gid == ids.group_id
                && *eid == event_id
                && recipient_scope == "all-attendees"
                && requested_user_ids.is_none()
        })
        .returning(move |_, _, _, _| Ok(vec![attendee_id1, attendee_id2]));
    expect_custom_notification_context(&mut db, &ids, event_id);
    db.expect_enqueue_tracked_custom_notification()
        .times(1)
        .withf(move |notification, tracking| {
            matches!(notification.kind, NotificationKind::EventCustom)
                && notification.recipients == vec![attendee_id1, attendee_id2]
                && tracking.created_by == ids.user_id
        })
        .returning(|_, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = custom_notification_request(
        &ids,
        event_id,
        EventCustomNotificationRecipientScope::All,
        vec![],
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::NO_CONTENT);
}

// Helpers.

/// Builds a custom notification request for the event and recipients.
fn custom_notification_request(
    ids: &DashboardIds,
    event_id: Uuid,
    recipient_scope: EventCustomNotificationRecipientScope,
    recipient_user_ids: Vec<Uuid>,
) -> Request<Body> {
    let form = serde_qs::to_string(&EventCustomNotification {
        content: CustomNotificationContent {
            body: "Body".to_string(),
            subject: "Subject".to_string(),
        },
        recipient_scope,
        recipient_user_ids,
    })
    .unwrap();

    form_request(
        "POST",
        &format!("/dashboard/group/notifications/{event_id}"),
        ids.session_id,
        form,
    )
}

/// Expects the event and site settings reads that compose a custom notification.
fn expect_custom_notification_context(db: &mut MockDB, ids: &DashboardIds, event_id: Uuid) {
    let ids = *ids;
    let event = sample_event_summary(event_id);
    let site_settings = sample_site_settings();

    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == ids.community_id && *eid == event_id)
        .returning(move |_, _| Ok(event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
}

/// Expects the session, permission, event summary and confirmed attendee rows
/// read by the CSV exports.
fn expect_export_reads(
    db: &mut MockDB,
    ids: &DashboardIds,
    event_id: Uuid,
    output: AttendeesOutput,
) {
    let ids = *ids;
    let event = sample_event_summary(event_id);

    expect_group_access(db, &ids, GroupPermission::Read);
    db.expect_find_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == ids.community_id && *gid == ids.group_id && *eid == event_id
        })
        .returning(move |_, _, _| Ok(Some(event.clone())));
    db.expect_search_event_attendees()
        .times(1)
        .withf(move |gid, eid, filters| {
            *gid == ids.group_id
                && *eid == event_id
                && filters.limit == Some(MAX_ATTENDEES_EXPORT_ROWS)
                && filters.offset.is_none()
                && filters.status == Some(AttendeeEnrollmentStatusFilter::Confirmed)
        })
        .returning(move |_, _, _| Ok(output.clone()));
}

/// Expects the session, permissions, event summary and registration questions
/// read by the list page; `can_manage_events` is the events-write read result.
fn expect_list_page_context(
    db: &mut MockDB,
    ids: &DashboardIds,
    event: EventSummary,
    can_manage_events: bool,
) {
    let ids = *ids;
    let event_id = event.event_id;

    expect_group_access(db, &ids, GroupPermission::Read);
    expect_group_permission_result(db, &ids, GroupPermission::CheckInsWrite, true);
    expect_group_permission_result(db, &ids, GroupPermission::EventsWrite, can_manage_events);
    db.expect_find_event_summary_dashboard()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == ids.community_id && *gid == ids.group_id && *eid == event_id
        })
        .returning(move |_, _, _| Ok(Some(event.clone())));
    db.expect_get_event_registration_questions()
        .times(1)
        .withf(move |cid, eid| *cid == ids.community_id && *eid == event_id)
        .returning(|_, _| Ok(vec![]));
}

/// Builds a mark-paid request for the event purchase with the form body.
fn external_payment_request(
    ids: &DashboardIds,
    event_id: Uuid,
    event_purchase_id: Uuid,
    body: &'static str,
) -> Request<Body> {
    form_request(
        "POST",
        &format!(
            "/dashboard/group/events/{event_id}/purchases/{event_purchase_id}/external-payment"
        ),
        ids.session_id,
        body,
    )
}
