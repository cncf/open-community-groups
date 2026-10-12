use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderMap, HeaderValue, Request, StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE},
    },
};
use chrono::{Months, Utc};
use serde_json::Value;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::{
        error::{HandlerError, INVALID_REQUEST_PAYLOAD},
        tests::*,
    },
    router::{CACHE_CONTROL_NO_STORE, CACHE_CONTROL_PUBLIC_SHARED},
    services::notifications::MockNotificationsManager,
    types::{
        pagination,
        search::{EXPLORE_WIDGET_MAX_ITEMS, SearchEventsFilters, SearchGroupsFilters, ViewMode},
        site::explore::Entity,
    },
};

use super::{parse_events_filters, parse_groups_filters, viewer_location};

/// Title class only rendered by the calendar variant of the event card.
const CALENDAR_CARD_TITLE_CLASS: &str = "!text-[0.9rem]/[1.25rem]";

#[tokio::test]
async fn test_event_card_calendar_renders_calendar_card() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_public_event_summary()
        .times(1)
        .withf(move |id| *id == event_id)
        .returning(move |_| Ok(Some(sample_event_summary(event_id, Uuid::new_v4()))));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!(
            "/explore/events/{event_id}/card?view_mode=calendar"
        ))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the calendar card is rendered with public cache headers
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
    );
    assert!(body.contains("Sample Event"));
    assert!(body.contains(CALENDAR_CARD_TITLE_CLASS));
}

#[tokio::test]
async fn test_event_card_invalid_view_mode_returns_422() {
    // Setup database mock (the event must not be loaded)
    let mut db = MockDB::new();
    db.expect_get_public_event_summary().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!(
            "/explore/events/{}/card?view_mode=list",
            Uuid::new_v4()
        ))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the request is rejected without exposing parser details
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(body, INVALID_REQUEST_PAYLOAD);
}

#[tokio::test]
async fn test_event_card_map_renders_event_card() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_public_event_summary()
        .times(1)
        .withf(move |id| *id == event_id)
        .returning(move |_| Ok(Some(sample_event_summary(event_id, Uuid::new_v4()))));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/explore/events/{event_id}/card?view_mode=map"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the map card is rendered with public cache headers
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
    );
    assert!(body.contains("Sample Event"));
    assert!(!body.contains(CALENDAR_CARD_TITLE_CLASS));
}

#[tokio::test]
async fn test_event_card_not_found_returns_404() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_public_event_summary()
        .times(1)
        .withf(move |id| *id == event_id)
        .returning(|_| Ok(None));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/explore/events/{event_id}/card?view_mode=map"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the response is an empty not found
    assert_eq!(parts.status, StatusCode::NOT_FOUND);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_events_results_section_calendar_uses_widget_data() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_search_events_minimal()
        .times(1)
        .withf(|filters, limit| {
            *limit == EXPLORE_WIDGET_MAX_ITEMS && filters.view_mode == Some(ViewMode::Calendar)
        })
        .returning(move |_, _| Ok(sample_search_events_minimal_output(event_id)));
    db.expect_search_events().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore/events-results-section?view_mode=calendar")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the calendar embeds the minimal events and hides the notice
    assert_eq!(parts.status, StatusCode::OK);
    assert!(body.contains("data-explore-calendar-data"));
    assert!(body.contains(&event_id.to_string()));
    assert!(body.contains("Sample Minimal Event"));
    assert!(body.contains(r#"aria-label="Previous month""#));
    assert!(body.contains(r#"aria-label="Next month""#));
    assert!(truncation_notice_is_hidden(&body));
}

#[tokio::test]
async fn test_events_results_section_map_shows_truncation_notice() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();
    let mut output = sample_search_events_minimal_output(event_id);
    output.total = 1284;
    output.truncated = true;

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_search_events_minimal()
        .times(1)
        .withf(|filters, limit| {
            *limit == EXPLORE_WIDGET_MAX_ITEMS && filters.view_mode == Some(ViewMode::Map)
        })
        .returning(move |_, _| Ok(output.clone()));
    db.expect_search_events().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore/events-results-section?view_mode=map")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the map embeds the minimal events and shows the notice
    assert_eq!(parts.status, StatusCode::OK);
    assert!(body.contains(r#"data-explore-map-data data-entity="events""#));
    assert!(body.contains(&event_id.to_string()));
    assert!(!truncation_notice_is_hidden(&body));
    assert!(body.contains("<span data-truncation-shown>1</span>"));
    assert!(body.contains("<span data-truncation-total>1284</span>"));
    assert!(body.contains("Zoom in or refine your filters to see them all."));
}

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
        &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
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
        .withf(|c, e| c.is_none() && e == &Some(Entity::Events))
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
        &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
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
        .withf(|c, e| c == &Some("test-community".to_string()) && e == &Some(Entity::Events))
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
async fn test_group_card_not_found_returns_404() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_public_group_summary()
        .times(1)
        .withf(move |id| *id == group_id)
        .returning(|_| Ok(None));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/explore/groups/{group_id}/card"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the response is an empty not found
    assert_eq!(parts.status, StatusCode::NOT_FOUND);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_group_card_success() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_public_group_summary()
        .times(1)
        .withf(move |id| *id == group_id)
        .returning(move |_| Ok(Some(sample_group_summary(group_id))));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/explore/groups/{group_id}/card"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the group card is rendered with public cache headers
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
    );
    assert!(body.contains("Test Group"));
}

#[tokio::test]
async fn test_groups_results_section_calendar_renders_list() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_search_groups()
        .times(1)
        .withf(|filters| filters.view_mode == Some(ViewMode::Calendar))
        .returning(move |_| Ok(sample_search_groups_output(group_id)));
    db.expect_search_groups_minimal().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore/groups-results-section?view_mode=calendar")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check groups have no calendar view and render as a list
    assert_eq!(parts.status, StatusCode::OK);
    assert!(body.contains("Test Group"));
    assert!(body.contains("data-results-summary"));
    assert!(!body.contains("data-explore-map-data"));
}

#[tokio::test]
async fn test_groups_results_section_map_uses_widget_data() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_search_groups_minimal()
        .times(1)
        .withf(|filters, limit| {
            *limit == EXPLORE_WIDGET_MAX_ITEMS && filters.view_mode == Some(ViewMode::Map)
        })
        .returning(move |_, _| Ok(sample_search_groups_minimal_output(group_id)));
    db.expect_search_groups().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore/groups-results-section?view_mode=map")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the map embeds the minimal groups and hides the notice
    assert_eq!(parts.status, StatusCode::OK);
    assert!(body.contains(r#"data-explore-map-data data-entity="groups""#));
    assert!(body.contains(&group_id.to_string()));
    assert!(body.contains("Test Group"));
    assert!(truncation_notice_is_hidden(&body));
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
        &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
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
        .withf(|c, e| c.is_none() && e == &Some(Entity::Groups))
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
        &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
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
        .withf(|c, e| c == &Some("test-community".to_string()) && e == &Some(Entity::Groups))
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
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(body, INVALID_REQUEST_PAYLOAD);
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
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(body, INVALID_REQUEST_PAYLOAD);
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
        .withf(|c, e| c.is_none() && e == &Some(Entity::Events))
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
        &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
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
        .withf(|c, e| c.is_none() && e == &Some(Entity::Groups))
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
        &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
    );
    assert!(!bytes.is_empty());
}

#[test]
fn test_parse_events_filters_applies_location_and_defaults() {
    // Setup query and viewer location headers
    let raw_query = "event_category[0]=&event_category[1]=conference&latitude=1.0&view_mode=list";
    let headers = sample_location_headers("51.5", "-0.12");

    // Parse the filters
    let filters = parse_events_filters(&headers, raw_query).expect("filters to be parsed");

    // Check the headers location and the normalized defaults were applied
    let date_from = filters.date_from.expect("date_from to exist");
    assert_eq!(filters.event_category, vec!["conference".to_string()]);
    assert_eq!(filters.latitude, Some(51.5));
    assert_eq!(filters.longitude, Some(-0.12));
    assert_eq!(
        filters.date_to,
        date_from.checked_add_months(Months::new(12))
    );
    assert_eq!(filters.view_mode, Some(ViewMode::List));
}

#[test]
fn test_parse_events_filters_rejects_invalid_dates() {
    // Check malformed dates fail at deserialization
    for raw_query in [
        "date_from=not-a-date",
        "date_to=2031-13-45",
        "date_from=2031/01/15",
    ] {
        let err = parse_events_filters(&HeaderMap::new(), raw_query)
            .expect_err("invalid date to be rejected");
        assert!(
            matches!(err, HandlerError::Deserialization(_)),
            "{raw_query} should fail with a deserialization error, got: {err}"
        );
    }

    // Check years PostgreSQL cannot cast fail at validation
    for raw_query in [
        "date_from=0000-01-01",
        "date_from=-5000-01-01",
        "date_to=%2B12345-01-01",
    ] {
        let err = parse_events_filters(&HeaderMap::new(), raw_query)
            .expect_err("out of range year to be rejected");
        assert!(
            matches!(err, HandlerError::Validation(_)),
            "{raw_query} should fail with a validation error, got: {err}"
        );
    }
}

#[test]
fn test_parse_events_filters_treats_blank_dates_as_missing() {
    // Capture the dates around parsing
    let before = Utc::now().date_naive();
    let filters = parse_events_filters(&HeaderMap::new(), "date_from=&date_to=&view_mode=list")
        .expect("filters to be parsed");
    let after = Utc::now().date_naive();

    // Check the default date range was applied
    let date_from = filters.date_from.expect("date_from to exist");
    assert!(
        date_from == before || date_from == after,
        "date_from should match today"
    );
    assert_eq!(
        filters.date_to,
        date_from.checked_add_months(Months::new(12))
    );
}

#[test]
fn test_parse_groups_filters_applies_location_and_defaults() {
    // Setup query and viewer location headers
    let raw_query = "region[0]=&region[1]=europe&view_mode=list";
    let headers = sample_location_headers("51.5", "-0.12");

    // Parse the filters
    let filters = parse_groups_filters(&headers, raw_query).expect("filters to be parsed");

    // Check the headers location and the normalized defaults were applied
    assert_eq!(filters.latitude, Some(51.5));
    assert_eq!(filters.longitude, Some(-0.12));
    assert_eq!(filters.region, vec!["europe".to_string()]);
    assert_eq!(filters.view_mode, Some(ViewMode::List));
}

#[test]
fn test_parse_groups_filters_rejects_invalid_limit() {
    let err = parse_groups_filters(&HeaderMap::new(), "limit=invalid")
        .expect_err("invalid limit to be rejected");

    assert!(matches!(err, HandlerError::Deserialization(_)));
}

#[tokio::test]
async fn test_search_events_calendar_success() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_search_events_minimal()
        .times(1)
        .withf(|filters, limit| {
            *limit == EXPLORE_WIDGET_MAX_ITEMS
                && filters.view_mode == Some(ViewMode::Calendar)
                && filters.date_from.map(|d| d.to_string()) == Some("2031-03-01".to_string())
                && filters.date_to.map(|d| d.to_string()) == Some("2031-03-31".to_string())
        })
        .returning(move |_, _| Ok(sample_search_events_minimal_output(event_id)));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore/events/search?date_from=2031-03-01&date_to=2031-03-31&view_mode=calendar")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let body: Value = serde_json::from_slice(&bytes).unwrap();

    // Check the minimal events are returned with shared cache headers
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("application/json")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
    );
    assert_eq!(body["events"][0]["event_id"], event_id.to_string());
    assert_eq!(body["events"][0]["name"], "Sample Minimal Event");
    assert_eq!(body["total"], 1);
    assert_eq!(body["truncated"], false);
}

#[tokio::test]
async fn test_search_events_map_success() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_search_events_minimal()
        .times(1)
        .withf(|filters, limit| {
            *limit == EXPLORE_WIDGET_MAX_ITEMS
                && filters.view_mode == Some(ViewMode::Map)
                && filters.bbox_ne_lat == Some(45.0)
                && filters.bbox_sw_lon == Some(5.0)
        })
        .returning(move |_, _| Ok(sample_search_events_minimal_output(event_id)));
    db.expect_search_events().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(
            "/explore/events/search?bbox_ne_lat=45.0&bbox_ne_lon=10.0&bbox_sw_lat=40.0\
             &bbox_sw_lon=5.0&view_mode=map",
        )
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let body: Value = serde_json::from_slice(&bytes).unwrap();

    // Check the minimal events are returned with shared cache headers
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("application/json")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
    );
    assert_eq!(body["events"][0]["event_id"], event_id.to_string());
    assert_eq!(body["events"][0]["latitude"], 42.3601);
    assert_eq!(body["total"], 1);
    assert_eq!(body["bbox"]["ne_lat"], 1.0);
    assert_eq!(body["truncated"], false);
}

#[tokio::test]
async fn test_search_events_rejects_list_view_mode() {
    // Setup database mock (the search must not be reached)
    let mut db = MockDB::new();
    db.expect_search_events_minimal().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore/events/search?view_mode=list")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the request is rejected with the view mode message
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(body, "view_mode must be calendar or map");
}

#[tokio::test]
async fn test_search_events_rejects_unsupported_view_modes() {
    for uri in [
        "/explore/events/search",
        "/explore/events/search?view_mode=",
        "/explore/events/search?view_mode=unknown",
        "/explore/events/search?view_mode=map&view_mode=list",
    ] {
        // Setup database mock (the search must not be reached)
        let mut db = MockDB::new();
        db.expect_search_events_minimal().never();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
            .build()
            .await;
        let request = Request::builder().method("GET").uri(uri).body(Body::empty()).unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();
        let body = String::from_utf8(bytes.to_vec()).unwrap();

        // Check the request is rejected with the view mode message
        assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY, "{uri}");
        assert_eq!(body, "view_mode must be calendar or map", "{uri}");
    }
}

#[tokio::test]
async fn test_search_events_with_distance_sort_and_location_headers_is_not_cached() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_search_events_minimal()
        .times(1)
        .withf(|filters, limit| {
            *limit == EXPLORE_WIDGET_MAX_ITEMS && filters.uses_viewer_location()
        })
        .returning(move |_, _| Ok(sample_search_events_minimal_output(event_id)));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore/events/search?sort_by=distance&view_mode=map")
        .header("CloudFront-Viewer-Latitude", "51.5")
        .header("CloudFront-Viewer-Longitude", "-0.12")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let body: Value = serde_json::from_slice(&bytes).unwrap();

    // Check the location dependent response is not stored
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_NO_STORE)
    );
    assert_eq!(body["events"][0]["event_id"], event_id.to_string());
}

#[tokio::test]
async fn test_events_results_section_with_distance_sort_and_location_headers_is_not_cached() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_search_events()
        .times(1)
        .withf(SearchEventsFilters::uses_viewer_location)
        .returning(move |_| Ok(sample_search_events_output(event_id)));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore/events-results-section?sort_by=distance")
        .header("CloudFront-Viewer-Latitude", "51.5")
        .header("CloudFront-Viewer-Longitude", "-0.12")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_NO_STORE)
    );
    assert_eq!(
        parts.headers.get("HX-Push-Url").unwrap().to_str().unwrap(),
        expected_events_push_url("sort_by=distance")
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_search_groups_success() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_search_groups_minimal()
        .times(1)
        .withf(|filters, limit| {
            *limit == EXPLORE_WIDGET_MAX_ITEMS && filters.region == vec!["europe".to_string()]
        })
        .returning(move |_, _| Ok(sample_search_groups_minimal_output(group_id)));
    db.expect_search_groups().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore/groups/search?region[0]=europe&view_mode=map")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let body: Value = serde_json::from_slice(&bytes).unwrap();

    // Check the minimal groups are returned with shared cache headers
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("application/json")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
    );
    assert_eq!(body["groups"][0]["group_id"], group_id.to_string());
    assert_eq!(body["groups"][0]["name"], "Test Group");
    assert_eq!(body["total"], 1);
    assert_eq!(body["bbox"]["sw_lon"], -2.0);
    assert_eq!(body["truncated"], false);
}

#[tokio::test]
async fn test_search_groups_with_distance_filter_and_location_headers_is_not_cached() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_search_groups_minimal()
        .times(1)
        .withf(|filters, limit| {
            *limit == EXPLORE_WIDGET_MAX_ITEMS && filters.uses_viewer_location()
        })
        .returning(move |_, _| Ok(sample_search_groups_minimal_output(group_id)));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore/groups/search?distance=25000&view_mode=map")
        .header("CloudFront-Viewer-Latitude", "51.5")
        .header("CloudFront-Viewer-Longitude", "-0.12")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let body: Value = serde_json::from_slice(&bytes).unwrap();

    // Check the location dependent response is not stored
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_NO_STORE)
    );
    assert_eq!(body["groups"][0]["group_id"], group_id.to_string());
}

#[tokio::test]
async fn test_groups_results_section_with_distance_filter_and_location_headers_is_not_cached() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_search_groups()
        .times(1)
        .withf(SearchGroupsFilters::uses_viewer_location)
        .returning(move |_| Ok(sample_search_groups_output(group_id)));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/explore/groups-results-section?distance=25000")
        .header("CloudFront-Viewer-Latitude", "51.5")
        .header("CloudFront-Viewer-Longitude", "-0.12")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_NO_STORE)
    );
    assert_eq!(
        parts.headers.get("HX-Push-Url").unwrap().to_str().unwrap(),
        expected_groups_push_url("distance=25000")
    );
    assert!(!bytes.is_empty());
}

#[test]
fn test_viewer_location_invalid_values() {
    let headers = sample_location_headers("invalid", "10.0");

    assert_eq!(viewer_location(&headers), (None, None));
}

#[test]
fn test_viewer_location_missing_headers() {
    assert_eq!(viewer_location(&HeaderMap::new()), (None, None));
}

#[test]
fn test_viewer_location_valid_headers() {
    let headers = sample_location_headers("10.123", "-20.456");

    assert_eq!(viewer_location(&headers), (Some(10.123), Some(-20.456)));
}

// Helpers

/// Helper to compute the expected events HX-Push-Url for tests.
fn expected_events_push_url(raw_query: &str) -> String {
    let filters = parse_events_filters(&HeaderMap::new(), raw_query).unwrap();
    pagination::build_url("/explore?entity=events", &filters).unwrap()
}

/// Helper to compute the expected groups HX-Push-Url for tests.
fn expected_groups_push_url(raw_query: &str) -> String {
    let filters = parse_groups_filters(&HeaderMap::new(), raw_query).unwrap();
    pagination::build_url("/explore?entity=groups", &filters).unwrap()
}

/// Returns `CloudFront` viewer location headers with the given values.
fn sample_location_headers(latitude: &'static str, longitude: &'static str) -> HeaderMap {
    let mut headers = HeaderMap::new();
    headers.insert(
        "CloudFront-Viewer-Latitude",
        HeaderValue::from_static(latitude),
    );
    headers.insert(
        "CloudFront-Viewer-Longitude",
        HeaderValue::from_static(longitude),
    );
    headers
}

/// Returns whether the rendered truncation notice is hidden.
fn truncation_notice_is_hidden(body: &str) -> bool {
    let start = body
        .find("data-explore-truncation-notice")
        .expect("truncation notice to be rendered");
    let tag_end = start + body[start..].find('>').expect("notice tag to be closed");
    body[start..tag_end].contains("hidden")
}
