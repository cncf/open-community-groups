use axum::{
    body::{Body, to_bytes},
    http::{Request, StatusCode, header::COOKIE},
};
use axum_login::tower_sessions::session;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::{
        TestRouterBuilder, assert_html_response, sample_auth_user, sample_session_record,
    },
    services::notifications::MockNotificationsManager,
};

#[tokio::test]
async fn test_list_page_returns_current_user_events() {
    // Setup an authenticated user and empty credential list
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_list_user_check_in_events()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(|_| Ok(vec![]));

    // Request the user's check-in fragment
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/user/check-in")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let body = to_bytes(body, usize::MAX).await.unwrap();

    // Verify the fragment renders successfully
    assert_html_response(&parts, &body, StatusCode::OK);
}

#[tokio::test]
async fn test_qr_code_returns_private_uncacheable_svg() {
    // Setup a confirmed credential owned by the current user
    let check_in_code = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_get_user_check_in_code()
        .times(1)
        .withf(move |eid, uid| *eid == event_id && *uid == user_id)
        .returning(move |_, _| Ok(Some(check_in_code)));

    // Request the credential image
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/dashboard/user/check-in/{event_id}/qr-code"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let body = to_bytes(body, usize::MAX).await.unwrap();

    // Verify the private SVG response contract
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(parts.headers["cache-control"], "private, no-store");
    assert_eq!(parts.headers["content-type"], "image/svg+xml");
    assert!(String::from_utf8_lossy(&body).contains("<svg"));
}

#[tokio::test]
async fn test_qr_code_returns_unavailable_for_non_confirmed_attendance() {
    // Setup a user without a confirmed credential for the selected event
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_get_user_check_in_code()
        .times(1)
        .withf(move |eid, uid| *eid == event_id && *uid == user_id)
        .returning(|_, _| Ok(None));

    // Request the unavailable credential image
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/dashboard/user/check-in/{event_id}/qr-code"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();

    // Verify credential ownership is not disclosed
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}
