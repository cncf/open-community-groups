use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderValue, Request, StatusCode,
        header::{CONTENT_TYPE, COOKIE, HOST},
    },
};
use axum_login::tower_sessions::session;
use serde_json::{from_slice, to_value};
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::{error::INVALID_REQUEST_PAYLOAD, tests::*},
    services::notifications::MockNotificationsManager,
    types::permissions::CommunityPermission,
};

#[tokio::test]
async fn test_search_user_missing_query() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let session_user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, session_user_id, community_id);
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id
                && *uid == session_user_id
                && permission == CommunityPermission::TeamWrite
        })
        .returning(|_, _, _| Ok(true));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/community/users/search")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), INVALID_REQUEST_PAYLOAD.as_bytes());
}

#[tokio::test]
async fn test_search_user_short_query_returns_empty_list() {
    assert_short_search_query_returns_empty_list("a").await;
}

#[tokio::test]
async fn test_search_user_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let session_user_id = Uuid::new_v4();
    let search_user_id = Uuid::new_v4();
    let expected_users = vec![sample_user_search_result(search_user_id)];
    let expected_body = to_value(&expected_users).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, session_user_id, community_id);
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id
                && *uid == session_user_id
                && permission == CommunityPermission::TeamWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_search_user()
        .times(1)
        .withf(move |query| query == "john")
        .returning(move |_| Ok(expected_users.clone()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/community/users/search?q=john")
        .header(HOST, "example.test")
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
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, expected_body);
}

#[tokio::test]
async fn test_search_user_supplementary_character_query_returns_empty_list() {
    assert_short_search_query_returns_empty_list("%F0%9F%98%80").await;
}

#[tokio::test]
async fn test_search_user_whitespace_padded_short_query_returns_empty_list() {
    assert_short_search_query_returns_empty_list("%20a%20").await;
}

// Helpers.

/// Checks a search query shorter than the minimum returns an empty list
/// without searching the database.
async fn assert_short_search_query_returns_empty_list(encoded_query: &str) {
    // Setup identifiers
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let session_user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, session_user_id, community_id);
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id
                && *uid == session_user_id
                && permission == CommunityPermission::TeamWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_search_user().never();

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(format!(
            "/dashboard/community/users/search?q={encoded_query}"
        ))
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check an empty JSON list is returned
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("application/json")
    );
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, serde_json::json!([]));
}
