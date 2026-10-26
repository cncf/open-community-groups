use axum::{
    body::Body,
    http::{HeaderValue, Request, StatusCode, header::CONTENT_TYPE},
};
use serde_json::{from_slice, json, to_value};
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::{error::INVALID_REQUEST_PAYLOAD, tests::*},
    types::permissions::CommunityPermission,
};

#[tokio::test]
async fn test_search_user_missing_query() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::TeamWrite);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/community/users/search", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), INVALID_REQUEST_PAYLOAD.as_bytes());
}

#[tokio::test]
async fn test_search_user_short_query_returns_empty_list() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::TeamWrite);
    db.expect_search_user().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, search_request(&ids, "a")).await;

    // Check an empty JSON list is returned without searching
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("application/json")
    );
    assert_eq!(from_slice::<serde_json::Value>(&bytes).unwrap(), json!([]));
}

#[tokio::test]
async fn test_search_user_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let expected_users = vec![sample_user_search_result(Uuid::new_v4())];
    let expected_body = to_value(&expected_users).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::TeamWrite);
    db.expect_search_user()
        .times(1)
        .withf(|query| query == "ab")
        .returning(move |_| Ok(expected_users.clone()));

    // Setup router and send a query of exactly the minimum length
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, search_request(&ids, "ab")).await;

    // Check the users found are returned
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
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::TeamWrite);
    db.expect_search_user().never();

    // Setup router and send a single code point encoded as four bytes
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, search_request(&ids, "%F0%9F%98%80")).await;

    // Check an empty JSON list is returned without searching
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("application/json")
    );
    assert_eq!(from_slice::<serde_json::Value>(&bytes).unwrap(), json!([]));
}

#[tokio::test]
async fn test_search_user_whitespace_padded_short_query_returns_empty_list() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::TeamWrite);
    db.expect_search_user().never();

    // Setup router and send a one character query padded with spaces
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, search_request(&ids, "%20a%20")).await;

    // Check an empty JSON list is returned without searching
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("application/json")
    );
    assert_eq!(from_slice::<serde_json::Value>(&bytes).unwrap(), json!([]));
}

// Helpers.

/// Builds a community dashboard user search request for the encoded query.
fn search_request(ids: &DashboardIds, encoded_query: &str) -> Request<Body> {
    get_request(
        &format!("/dashboard/community/users/search?q={encoded_query}"),
        ids.session_id,
    )
}
