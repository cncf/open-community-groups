use anyhow::anyhow;
use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderValue, Request, StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE, COOKIE},
    },
};
use axum_login::tower_sessions::session;
use serde_json::{from_slice, from_value, json};
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    activity_tracker::{Activity, MockActivityTracker},
    db::mock::MockDB,
    handlers::tests::*,
    router::CACHE_CONTROL_NO_CACHE,
    services::{
        notifications::{MockNotificationsManager, NotificationKind},
        payments::MockPaymentsManager,
    },
    templates::notifications::{EventWaitlistJoined, EventWaitlistLeft, EventWaitlistPromoted, EventWelcome},
    types::{
        event::{EventAttendanceInfo, EventAttendanceStatus, EventLeaveOutcome},
        payments::{EventPurchaseStatus, EventTicketCurrentPrice, EventTicketType, PreparedEventCheckout},
    },
};

#[tokio::test]
async fn test_page_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));
    db.expect_get_event_full_by_slug()
        .times(1)
        .withf(move |id, group_slug, event_slug| {
            *id == community_id && group_slug == "test-group" && event_slug == "test-event"
        })
        .returning(move |_, _, _| Ok(sample_event_full(community_id, event_id, group_id)));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/test-community/group/test-group/event/test-event")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static("max-age=3600")
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_page_db_error() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));
    db.expect_get_event_full_by_slug()
        .times(1)
        .withf(move |id, group_slug, event_slug| {
            *id == community_id && group_slug == "test-group" && event_slug == "test-event"
        })
        .returning(move |_, _, _| Err(anyhow!("db error")));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/test-community/group/test-group/event/test-event")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_check_in_page_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let event_summary = sample_event_summary(event_id, group_id);

    // Setup database mock
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
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event_summary.clone()));
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
    db.expect_is_event_check_in_window_open()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(|_, _| Ok(true));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/test-community/check-in/{event_id}"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE),
        Some(&HeaderValue::from_static("text/html; charset=utf-8"))
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL),
        Some(&HeaderValue::from_static(CACHE_CONTROL_NO_CACHE))
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_cfs_modal_success_anonymous() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let event_summary = sample_event_summary(event_id, group_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event_summary.clone()));
    db.expect_list_event_cfs_labels()
        .times(1)
        .withf(move |eid| *eid == event_id)
        .returning(|_| Ok(vec![]));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/test-community/event/{event_id}/cfs-modal"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL),
        Some(&HeaderValue::from_static(CACHE_CONTROL_NO_CACHE))
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_cfs_modal_success_authenticated() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let session_proposal_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let event_summary = sample_event_summary(event_id, group_id);
    let proposals = vec![sample_event_cfs_session_proposal(session_proposal_id)];

    // Setup database mock
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
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event_summary.clone()));
    db.expect_list_event_cfs_labels()
        .times(1)
        .withf(move |eid| *eid == event_id)
        .returning(|_| Ok(vec![]));
    db.expect_list_user_session_proposals_for_cfs_event()
        .times(1)
        .withf(move |uid, eid| *uid == user_id && *eid == event_id)
        .returning(move |_, _| Ok(proposals.clone()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/test-community/event/{event_id}/cfs-modal"))
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
        &HeaderValue::from_static("text/html; charset=utf-8")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL),
        Some(&HeaderValue::from_static(CACHE_CONTROL_NO_CACHE))
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_cfs_modal_db_error() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Err(anyhow!("db error")));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/test-community/event/{event_id}/cfs-modal"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_attend_event_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let event_summary = sample_event_summary(event_id, group_id);
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
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
    db.expect_ensure_event_is_active()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(|_, _| Ok(()));
    db.expect_attend_event()
        .times(1)
        .withf(move |id, eid, uid| *id == community_id && *eid == event_id && *uid == user_id)
        .returning(|_, _, _| Ok(EventAttendanceStatus::Attendee));
    db.expect_get_event_summary_by_id()
        .times(2)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event_summary.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventWelcome)
                && notification.recipients == vec![user_id]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventWelcome>(value.clone())
                        .map(|template| template.link == "/test-community/group/def5678/event/ghi9abc")
                        .unwrap_or(false)
                })
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/attend"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "status": "attendee" }));
}

#[tokio::test]
async fn test_attend_event_waitlist_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let event_summary = sample_event_summary(event_id, group_id);
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
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
    db.expect_ensure_event_is_active()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(|_, _| Ok(()));
    db.expect_attend_event()
        .times(1)
        .withf(move |id, eid, uid| *id == community_id && *eid == event_id && *uid == user_id)
        .returning(|_, _, _| Ok(EventAttendanceStatus::Waitlisted));
    db.expect_get_event_summary_by_id()
        .times(2)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event_summary.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventWaitlistJoined)
                && notification.recipients == vec![user_id]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventWaitlistJoined>(value.clone())
                        .map(|template| template.link == "/test-community/group/def5678/event/ghi9abc")
                        .unwrap_or(false)
                })
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/attend"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "status": "waitlisted" }));
}

#[tokio::test]
async fn test_attend_event_success_when_notification_context_load_fails() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let event_summary = sample_event_summary(event_id, group_id);
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
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
    db.expect_ensure_event_is_active()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(|_, _| Ok(()));
    db.expect_attend_event()
        .times(1)
        .withf(move |id, eid, uid| *id == community_id && *eid == event_id && *uid == user_id)
        .returning(|_, _, _| Ok(EventAttendanceStatus::Attendee));
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event_summary.clone()));
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(|_, _| Err(anyhow!("db error")));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/attend"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "status": "attendee" }));
}

#[tokio::test]
async fn test_attend_event_returns_inactive_error_before_ticketed_check() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
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
    db.expect_ensure_event_is_active()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(|_, _| Err(anyhow!("event not found or inactive")));
    db.expect_get_event_summary_by_id().times(0);
    db.expect_attend_event().times(0);

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/attend"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "event not found or inactive"
    );
}

#[tokio::test]
async fn test_attendance_status_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
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
        .withf(move |id, eid, uid| *id == community_id && *eid == event_id && *uid == user_id)
        .returning(|_, _, _| {
            Ok(EventAttendanceInfo {
                is_checked_in: false,
                status: EventAttendanceStatus::Attendee,

                purchase_amount_minor: None,
                refund_request_status: None,
                resume_checkout_url: None,
            })
        });

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/test-community/event/{event_id}/attendance"))
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
        &HeaderValue::from_static("application/json")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_NO_CACHE)
    );
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(
        body,
        json!({
            "can_request_refund": false,
            "is_checked_in": false,
            "purchase_amount_minor": null,
            "refund_request_status": null,
            "resume_checkout_url": null,
            "status": "attendee",
        })
    );
}

#[tokio::test]
async fn test_attendance_status_stale_event_returns_none_without_summary_lookup() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
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
        .withf(move |id, eid, uid| *id == community_id && *eid == event_id && *uid == user_id)
        .returning(|_, _, _| {
            Ok(EventAttendanceInfo {
                is_checked_in: false,
                status: EventAttendanceStatus::None,

                purchase_amount_minor: None,
                refund_request_status: None,
                resume_checkout_url: None,
            })
        });

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/test-community/event/{event_id}/attendance"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(
        body,
        json!({
            "can_request_refund": false,
            "is_checked_in": false,
            "purchase_amount_minor": null,
            "refund_request_status": null,
            "resume_checkout_url": null,
            "status": "none",
        })
    );
}

#[tokio::test]
async fn test_check_in_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
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
    db.expect_check_in_event()
        .times(1)
        .withf(move |cid, eid, uid, bypass_window| {
            *cid == community_id && *eid == event_id && *uid == user_id && !bypass_window
        })
        .returning(|_, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/check-in/{event_id}"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_leave_event_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
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
    db.expect_leave_event()
        .times(1)
        .withf(move |id, eid, uid| *id == community_id && *eid == event_id && *uid == user_id)
        .returning(|_, _, _| {
            Ok(EventLeaveOutcome {
                left_status: EventAttendanceStatus::Attendee,
                promoted_user_ids: vec![],
            })
        });
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(sample_event_summary(event_id, Uuid::new_v4())));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!("/test-community/event/{event_id}/leave"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "left_status": "attendee" }));
}

#[tokio::test]
async fn test_leave_waitlist_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let event_summary = sample_event_summary(event_id, group_id);

    // Setup database mock
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
    db.expect_leave_event()
        .times(1)
        .withf(move |id, eid, uid| *id == community_id && *eid == event_id && *uid == user_id)
        .returning(|_, _, _| {
            Ok(EventLeaveOutcome {
                left_status: EventAttendanceStatus::Waitlisted,
                promoted_user_ids: vec![],
            })
        });
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event_summary.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventWaitlistLeft)
                && notification.recipients == vec![user_id]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventWaitlistLeft>(value.clone())
                        .map(|template| template.link == "/test-community/group/def5678/event/ghi9abc")
                        .unwrap_or(false)
                })
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!("/test-community/event/{event_id}/leave"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "left_status": "waitlisted" }));
}

#[tokio::test]
async fn test_leave_event_promotes_waitlisted_users_and_enqueues_notification() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let promoted_user_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let event_summary = sample_event_summary(event_id, group_id);
    let site_settings = sample_site_settings();
    let site_settings_for_notification = site_settings.clone();

    // Setup database mock
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
    db.expect_leave_event()
        .times(1)
        .withf(move |id, eid, uid| *id == community_id && *eid == event_id && *uid == user_id)
        .returning(move |_, _, _| {
            Ok(EventLeaveOutcome {
                left_status: EventAttendanceStatus::Attendee,
                promoted_user_ids: vec![promoted_user_id],
            })
        });
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event_summary.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventWaitlistPromoted)
                && notification.recipients == vec![promoted_user_id]
                && notification.attachments.len() == 1
                && notification.attachments[0].file_name == "event-ghi9abc.ics"
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventWaitlistPromoted>(value.clone())
                        .map(|template| {
                            template.link == "/test-community/group/def5678/event/ghi9abc"
                                && template.theme.primary_color
                                    == site_settings_for_notification.theme.primary_color
                        })
                        .unwrap_or(false)
                })
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!("/test-community/event/{event_id}/leave"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "left_status": "attendee" }));
}

#[tokio::test]
async fn test_leave_event_success_when_notification_context_load_fails() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
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
    db.expect_leave_event()
        .times(1)
        .withf(move |id, eid, uid| *id == community_id && *eid == event_id && *uid == user_id)
        .returning(|_, _, _| {
            Ok(EventLeaveOutcome {
                left_status: EventAttendanceStatus::Attendee,
                promoted_user_ids: vec![],
            })
        });
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Err(anyhow!("db error")));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!("/test-community/event/{event_id}/leave"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "left_status": "attendee" }));
}

#[tokio::test]
async fn test_request_refund_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
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

    // Setup payments manager mock
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_request_refund()
        .times(1)
        .withf(move |input| {
            input.community_id == community_id
                && input.event_id == event_id
                && input.requested_reason.as_deref() == Some("Need to cancel")
                && input.user_id == user_id
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/refund-request"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from("requested_reason=Need%20to%20cancel"))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "status": "refund-requested" }));
}

#[tokio::test]
async fn test_request_refund_returns_internal_server_error_when_payments_manager_fails() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
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

    // Setup payments manager mock
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_request_refund()
        .times(1)
        .withf(move |input| {
            input.community_id == community_id
                && input.event_id == event_id
                && input.requested_reason.as_deref() == Some("Need to cancel")
                && input.user_id == user_id
        })
        .returning(|_| Box::pin(async { Err(anyhow!("payments error")) }));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/refund-request"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from("requested_reason=Need%20to%20cancel"))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_start_checkout_rejects_refund_requested_purchase() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let ticket_type_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let mut event_summary = sample_event_summary(event_id, group_id);
    event_summary.payment_currency_code = Some("USD".to_string());
    event_summary.ticket_types = Some(vec![EventTicketType {
        active: true,
        event_ticket_type_id: ticket_type_id,
        order: 1,
        title: "General admission".to_string(),

        current_price: Some(EventTicketCurrentPrice {
            amount_minor: 2_500,
            ends_at: None,
            starts_at: None,
        }),
        description: None,
        price_windows: vec![],
        remaining_seats: Some(10),
        seats_total: Some(10),
        sold_out: false,
    }]);

    // Setup database mock
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
    db.expect_ensure_event_is_active()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(|_, _| Ok(()));
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event_summary.clone()));
    db.expect_prepare_event_checkout_purchase()
        .times(1)
        .withf(move |cid, input| {
            *cid == community_id
                && input.event_id == event_id
                && input.event_ticket_type_id == ticket_type_id
                && input.user_id == user_id
        })
        .returning(move |_, _| {
            Ok(PreparedEventCheckout {
                community_name: "test-community".to_string(),
                event_id,
                event_slug: "event".to_string(),
                group_slug: "group".to_string(),
                purchase: sample_purchase_summary(EventPurchaseStatus::RefundRequested),
                recipient: crate::types::payments::GroupPaymentRecipient {
                    provider: crate::types::payments::PaymentProvider::Stripe,
                    recipient_id: "acct_test_123".to_string(),
                },
            })
        });

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/checkout"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(format!("event_ticket_type_id={ticket_type_id}")))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "checkout is unavailable while a refund is in progress"
    );
}

#[tokio::test]
async fn test_start_checkout_rejects_when_tickets_are_unavailable() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let ticket_type_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let mut event_summary = sample_event_summary(event_id, group_id);
    event_summary.payment_currency_code = Some("USD".to_string());
    event_summary.ticket_types = Some(vec![EventTicketType {
        active: true,
        event_ticket_type_id: ticket_type_id,
        order: 1,
        title: "General admission".to_string(),

        current_price: None,
        description: None,
        price_windows: vec![],
        remaining_seats: Some(10),
        seats_total: Some(10),
        sold_out: false,
    }]);

    // Setup database mock
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
    db.expect_ensure_event_is_active()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(|_, _| Ok(()));
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event_summary.clone()));
    db.expect_prepare_event_checkout_purchase().times(0);

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/checkout"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(format!("event_ticket_type_id={ticket_type_id}")))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "tickets are currently unavailable for this event"
    );
}

#[tokio::test]
async fn test_start_checkout_rejects_inactive_event_before_ticket_checks() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let ticket_type_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
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
    db.expect_ensure_event_is_active()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(|_, _| Err(anyhow!("event not found or inactive")));
    db.expect_get_event_summary_by_id().times(0);
    db.expect_prepare_event_checkout_purchase().times(0);

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/checkout"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(format!("event_ticket_type_id={ticket_type_id}")))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "event not found or inactive"
    );
}

#[tokio::test]
async fn test_submit_cfs_submission_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let session_proposal_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let event_summary = sample_event_summary(event_id, group_id);
    let proposals = vec![sample_event_cfs_session_proposal(session_proposal_id)];
    let form_data = format!("session_proposal_id={session_proposal_id}");

    // Setup database mock
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
    db.expect_add_cfs_submission()
        .times(1)
        .withf(move |cid, eid, uid, proposal_id, label_ids| {
            *cid == community_id
                && *eid == event_id
                && *uid == user_id
                && *proposal_id == session_proposal_id
                && label_ids.is_empty()
        })
        .returning(|_, _, _, _, _| Ok(Uuid::new_v4()));
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event_summary.clone()));
    db.expect_list_event_cfs_labels()
        .times(1)
        .withf(move |eid| *eid == event_id)
        .returning(|_| Ok(vec![]));
    db.expect_list_user_session_proposals_for_cfs_event()
        .times(1)
        .withf(move |uid, eid| *uid == user_id && *eid == event_id)
        .returning(move |_, _| Ok(proposals.clone()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/cfs-submissions"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(form_data))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL),
        Some(&HeaderValue::from_static(CACHE_CONTROL_NO_CACHE))
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_submit_cfs_submission_db_error() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let session_proposal_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let form_data = format!("session_proposal_id={session_proposal_id}");

    // Setup database mock
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
    db.expect_add_cfs_submission()
        .times(1)
        .withf(move |cid, eid, uid, proposal_id, label_ids| {
            *cid == community_id
                && *eid == event_id
                && *uid == user_id
                && *proposal_id == session_proposal_id
                && label_ids.is_empty()
        })
        .returning(|_, _, _, _, _| Err(anyhow!("db error")));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/cfs-submissions"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(form_data))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_track_view_success() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();

    // Setup database mock
    let db = MockDB::new();

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup activity tracker mock
    let mut activity_tracker = MockActivityTracker::new();
    activity_tracker
        .expect_track()
        .times(1)
        .withf(move |activity| *activity == Activity::EventView { event_id })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_activity_tracker(activity_tracker)
        .with_server_cfg(sample_tracking_server_cfg())
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/events/{event_id}/views"))
        .header("origin", "https://example.test")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_track_view_ignores_cross_origin_request() {
    // Setup database mock
    let db = MockDB::new();

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup activity tracker mock
    let mut activity_tracker = MockActivityTracker::new();
    activity_tracker.expect_track().times(0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_activity_tracker(activity_tracker)
        .with_server_cfg(sample_tracking_server_cfg())
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/events/{}/views", Uuid::new_v4()))
        .header("origin", "https://evil.test")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert!(bytes.is_empty());
}
