use anyhow::anyhow;
use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderValue, Request, StatusCode,
        header::{CONTENT_TYPE, COOKIE},
    },
};
use axum_login::tower_sessions::session;
use serde_json::{from_value, json};
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    services::notifications::{MockNotificationsManager, NotificationKind},
    templates::dashboard::DASHBOARD_PAGINATION_LIMIT,
    templates::notifications::{EventAttendanceCanceled, EventWaitlistPromoted, EventWelcome},
    types::event::{EventAttendanceInfo, EventAttendanceStatus, EventLeaveOutcome},
};

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and data structures.
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let output = crate::templates::dashboard::user::events::UserEventsOutput {
        events: vec![crate::templates::dashboard::user::events::UserEvent {
            can_cancel_attendance: false,
            can_complete_registration_questions: false,
            event: sample_event_summary(event_id, group_id),
            registration_answers: None,
            registration_questions: vec![],
            registration_questions_pending: false,
            roles: vec!["Attendee".to_string(), "Host".to_string()],
        }],
        total: 1,
    };

    // Setup database mock.
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_list_user_events()
        .times(1)
        .withf(move |uid, filters| {
            *uid == user_id && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT) && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(output.clone()));

    // Setup notifications manager mock.
    let nm = MockNotificationsManager::new();

    // Setup router and send request.
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

    // Check response matches expectations.
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8"),
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_list_page_with_pagination_params() {
    // Setup identifiers and data structures.
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let output = crate::templates::dashboard::user::events::UserEventsOutput {
        events: vec![],
        total: 0,
    };

    // Setup database mock.
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_list_user_events()
        .times(1)
        .withf(move |uid, filters| *uid == user_id && filters.limit == Some(5) && filters.offset == Some(10))
        .returning(move |_, _| Ok(output.clone()));

    // Setup notifications manager mock.
    let nm = MockNotificationsManager::new();

    // Setup router and send request.
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

    // Check response matches expectations.
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8"),
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_list_page_db_error() {
    // Setup identifiers and data structures.
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock.
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_list_user_events()
        .times(1)
        .withf(move |uid, filters| {
            *uid == user_id && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT) && filters.offset == Some(0)
        })
        .returning(|_, _| Err(anyhow!("db error")));

    // Setup notifications manager mock.
    let nm = MockNotificationsManager::new();

    // Setup router and send request.
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

    // Check response matches expectations.
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_cancel_attendance_promotes_waitlisted_users_and_enqueues_notification() {
    // Setup identifiers and data structures.
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let promoted_user_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let event = sample_event_summary(event_id, group_id);
    let site_settings = sample_site_settings();
    let primary_color = site_settings.theme.primary_color.clone();

    // Setup database mock.
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));
    db.expect_get_event_attendance()
        .times(1)
        .withf(move |cid, eid, uid| *cid == community_id && *eid == event_id && *uid == user_id)
        .returning(|_, _, _| {
            Ok(EventAttendanceInfo {
                is_checked_in: false,
                status: EventAttendanceStatus::Attendee,

                purchase_amount_minor: None,
                refund_request_status: None,
                resume_checkout_url: None,
            })
        });
    db.expect_leave_event()
        .times(1)
        .withf(move |cid, eid, uid| *cid == community_id && *eid == event_id && *uid == user_id)
        .returning(move |_, _, _| {
            Ok(EventLeaveOutcome {
                left_status: EventAttendanceStatus::Attendee,
                promoted_user_ids: vec![promoted_user_id],
            })
        });
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event.clone()));

    // Setup notifications manager mock.
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventAttendanceCanceled)
                && notification.recipients == vec![user_id]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventAttendanceCanceled>(value.clone()).is_ok_and(|template| {
                        template.dashboard_link == "/dashboard/user?tab=events"
                            && template.link == "/test-community/group/def5678/event/ghi9abc"
                    })
                })
        })
        .returning(|_| Box::pin(async { Ok(()) }));
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventWaitlistPromoted)
                && notification.recipients == vec![promoted_user_id]
                && notification.attachments.len() == 1
                && notification.attachments[0].file_name == "event-ghi9abc.ics"
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventWaitlistPromoted>(value.clone()).is_ok_and(|template| {
                        template.link == "/test-community/group/def5678/event/ghi9abc"
                            && template.theme.primary_color == primary_color
                    })
                })
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request.
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

    // Check response matches expectations.
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get("HX-Trigger"),
        Some(&HeaderValue::from_static("refresh-user-dashboard-content"))
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_submit_registration_answers_success() {
    // Setup identifiers and data structures.
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let question_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let event = sample_event_summary(event_id, group_id);
    let site_settings = sample_site_settings();
    let answers = json!({
        "answers": [
            {
                "question_id": question_id,
                "value": "Vegetarian"
            }
        ]
    });
    let form_body = serde_urlencoded::to_string([("registration_answers", answers.to_string())]).unwrap();

    // Setup database mock.
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));
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
        .returning(|_, _, _, _| Ok(true));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event.clone()));

    // Setup notifications manager mock.
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventWelcome)
                && notification.recipients == vec![user_id]
                && notification.attachments.len() == 1
                && notification
                    .template_data
                    .as_ref()
                    .is_some_and(|value| from_value::<EventWelcome>(value.clone()).is_ok())
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request.
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

    // Check response matches expectations.
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get("hx-trigger").unwrap(),
        &HeaderValue::from_static("refresh-user-dashboard-content"),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_submit_registration_answers_update_skips_welcome_notification() {
    // Setup identifiers and data structures.
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let question_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let answers = json!({
        "answers": [
            {
                "question_id": question_id,
                "value": "Vegetarian"
            }
        ]
    });
    let form_body = serde_urlencoded::to_string([("registration_answers", answers.to_string())]).unwrap();

    // Setup database mock.
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));
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
        .returning(|_, _, _, _| Ok(false));
    db.expect_get_site_settings().times(0);
    db.expect_get_event_summary_by_id().times(0);

    // Setup notifications manager mock.
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().times(0);

    // Setup router and send request.
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

    // Check response matches expectations.
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get("hx-trigger").unwrap(),
        &HeaderValue::from_static("refresh-user-dashboard-content"),
    );
    assert!(bytes.is_empty());
}
