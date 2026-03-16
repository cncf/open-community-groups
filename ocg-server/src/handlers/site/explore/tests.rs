use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderMap, HeaderValue, Request, StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE},
    },
};
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    services::notifications::MockNotificationsManager,
    templates::site::explore::{self},
    types::{
        pagination,
        search::{SearchEventsFilters, SearchGroupsFilters},
    },
};

#[tokio::test]
async fn test_events_results_section_success() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_search_events()
        .times(1)
        .returning(move |_| Ok(sample_search_events_output(event_id)));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore/events-results-section")
        .body(Body::empty())
        .unwrap();
    let raw_query = request.uri().query().map(str::to_string).unwrap_or_default();
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
        &HeaderValue::from_static("max-age=600")
    );
    assert_eq!(
        parts.headers.get("HX-Push-Url").unwrap().to_str().unwrap(),
        expected_events_push_url(&raw_query)
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_events_section_success() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_filters_options()
        .times(1)
        .withf(|c, e| c.is_none() && e == &Some(explore::Entity::Events))
        .returning(|_, _| Ok(sample_filters_options()));
    db.expect_search_events()
        .times(1)
        .returning(move |_| Ok(sample_search_events_output(event_id)));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore/events-section")
        .body(Body::empty())
        .unwrap();
    let raw_query = request.uri().query().map(str::to_string).unwrap_or_default();
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
        &HeaderValue::from_static("max-age=600")
    );
    assert_eq!(
        parts.headers.get("HX-Push-Url").unwrap().to_str().unwrap(),
        expected_events_push_url(&raw_query)
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_events_section_with_single_community() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_filters_options()
        .times(1)
        .withf(|c, e| c == &Some("test-community".to_string()) && e == &Some(explore::Entity::Events))
        .returning(|_, _| Ok(sample_filters_options()));
    db.expect_search_events()
        .times(1)
        .returning(move |_| Ok(sample_search_events_output(event_id)));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore/events-section?community[0]=test-community")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_groups_results_section_success() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_search_groups()
        .times(1)
        .returning(move |_| Ok(sample_search_groups_output(group_id)));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore/groups-results-section")
        .body(Body::empty())
        .unwrap();
    let raw_query = request.uri().query().map(str::to_string).unwrap_or_default();
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
        &HeaderValue::from_static("max-age=600")
    );
    assert_eq!(
        parts.headers.get("HX-Push-Url").unwrap().to_str().unwrap(),
        expected_groups_push_url(&raw_query)
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_groups_section_success() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_filters_options()
        .times(1)
        .withf(|c, e| c.is_none() && e == &Some(explore::Entity::Groups))
        .returning(|_, _| Ok(sample_filters_options()));
    db.expect_search_groups()
        .times(1)
        .returning(move |_| Ok(sample_search_groups_output(group_id)));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore/groups-section")
        .body(Body::empty())
        .unwrap();
    let raw_query = request.uri().query().map(str::to_string).unwrap_or_default();
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
        &HeaderValue::from_static("max-age=600")
    );
    assert_eq!(
        parts.headers.get("HX-Push-Url").unwrap().to_str().unwrap(),
        expected_groups_push_url(&raw_query)
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_groups_section_with_single_community() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_filters_options()
        .times(1)
        .withf(|c, e| c == &Some("test-community".to_string()) && e == &Some(explore::Entity::Groups))
        .returning(|_, _| Ok(sample_filters_options()));
    db.expect_search_groups()
        .times(1)
        .returning(move |_| Ok(sample_search_groups_output(group_id)));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore/groups-section?community[0]=test-community")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_page_db_error() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Err(anyhow::anyhow!("db error")));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore?entity=events")
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
async fn test_page_events_invalid_filters() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore?entity=events&limit=invalid")
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
async fn test_page_groups_invalid_filters() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore?entity=groups&limit=invalid")
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
async fn test_page_success_events() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_get_filters_options()
        .times(1)
        .withf(|c, e| c.is_none() && e == &Some(explore::Entity::Events))
        .returning(|_, _| Ok(sample_filters_options()));
    db.expect_search_events()
        .times(1)
        .returning(move |_| Ok(sample_search_events_output(event_id)));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore?entity=events")
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
        &HeaderValue::from_static("max-age=600")
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_page_success_groups() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_get_filters_options()
        .times(1)
        .withf(|c, e| c.is_none() && e == &Some(explore::Entity::Groups))
        .returning(|_, _| Ok(sample_filters_options()));
    db.expect_search_groups()
        .times(1)
        .returning(move |_| Ok(sample_search_groups_output(group_id)));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore?entity=groups")
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
        &HeaderValue::from_static("max-age=600")
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_search_events_success() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_search_events()
        .times(1)
        .returning(move |_| Ok(sample_search_events_output(event_id)));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore/events/search")
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
        &HeaderValue::from_static("max-age=3600")
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_search_groups_success() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_search_groups()
        .times(1)
        .returning(move |_| Ok(sample_search_groups_output(group_id)));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore/groups/search")
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
        &HeaderValue::from_static("max-age=3600")
    );
    assert!(!bytes.is_empty());
}

// Helpers

/// Helper to compute the expected events HX-Push-Url for tests.
fn expected_events_push_url(raw_query: &str) -> String {
    let headers = HeaderMap::new();
    let filters = SearchEventsFilters::new(&headers, raw_query).unwrap();
    pagination::build_url("/explore?entity=events", &filters).unwrap()
}

/// Helper to compute the expected groups HX-Push-Url for tests.
fn expected_groups_push_url(raw_query: &str) -> String {
    let headers = HeaderMap::new();
    let filters = SearchGroupsFilters::new(&headers, raw_query).unwrap();
    pagination::build_url("/explore?entity=groups", &filters).unwrap()
}
