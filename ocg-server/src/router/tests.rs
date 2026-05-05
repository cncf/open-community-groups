use anyhow::anyhow;
use axum::{
    body::{Body, to_bytes},
    http::{HeaderValue, StatusCode, Uri, header::LOCATION},
};
use tower::ServiceExt;

use crate::{db::mock::MockDB, handlers::tests::*, services::notifications::MockNotificationsManager};

use super::*;

#[tokio::test]
async fn test_favicon_route_returns_not_found_without_configured_url() {
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
        .uri("/favicon.ico")
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
async fn test_favicon_route_returns_redirect_with_cache_header() {
    // Setup database mock
    let favicon_url = "https://example.test/favicon.ico".to_string();
    let mut site_settings = sample_site_settings();
    site_settings.favicon_url = Some(favicon_url.clone());

    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/favicon.ico")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static("public, max-age=604800")
    );
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_str(&favicon_url).unwrap()
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_favicon_route_surfaces_db_errors_as_internal_server_error() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Err(anyhow!("db error")));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/favicon.ico")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();

    // Check response matches expectations
    assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_health_check_returns_ok() {
    let response = health_check().await.into_response();
    let (parts, body) = response.into_parts();

    assert_eq!(parts.status, StatusCode::OK);
    assert!(to_bytes(body, usize::MAX).await.unwrap().is_empty());
}

#[tokio::test]
async fn test_missing_route_returns_not_found_page() {
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
        .uri("/missing/page")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NOT_FOUND);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static("max-age=300")
    );
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("We could not find that page"));
    assert!(body.contains("Go to home page"));
}

#[tokio::test]
async fn test_payments_webhook_route_is_not_mounted_without_payments_config() {
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
        .method("POST")
        .uri("/webhooks/payments")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NOT_FOUND);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static("max-age=300")
    );
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("We could not find that page"));
}

#[tokio::test]
async fn test_redirect_old_hosts_redirects_matching_host() {
    let server_cfg = HttpServerConfig {
        base_url: "https://example.com".to_string(),
        redirect_hosts: Some(vec!["old.example.com".to_string()]),
        ..Default::default()
    };
    let router: Router<()> = Router::new()
        .route("/", get(|| async { "ok" }))
        .layer(middleware::from_fn_with_state(
            server_cfg.clone(),
            redirect_old_hosts,
        ))
        .with_state(server_cfg);

    let request = Request::builder()
        .uri("/some/path?query=value")
        .header(HOST, "old.example.com:8080")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();

    assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
    assert_eq!(
        response.headers().get(LOCATION).unwrap(),
        &HeaderValue::from_static("https://example.com")
    );
}

#[tokio::test]
async fn test_static_handler_serves_existing_asset() {
    let uri = Uri::from_static("/static/images/icons/arrow_left.svg");
    let response = static_handler(uri).await.into_response();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("image/svg+xml")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static("max-age=604800")
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_static_handler_missing_asset_returns_not_found() {
    let uri = Uri::from_static("/static/does/not/exist.txt");
    let response = static_handler(uri).await.into_response();
    let (parts, body) = response.into_parts();

    assert_eq!(parts.status, StatusCode::NOT_FOUND);
    assert!(to_bytes(body, usize::MAX).await.unwrap().is_empty());
}

#[tokio::test]
async fn test_zoom_webhook_route_is_not_mounted_when_zoom_is_disabled() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup disabled Zoom configuration
    let mut meetings_cfg = sample_zoom_meetings_cfg("zoom-secret");
    if let Some(zoom_cfg) = meetings_cfg.zoom.as_mut() {
        zoom_cfg.enabled = false;
    }

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_meetings_cfg(meetings_cfg)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri("/webhooks/zoom")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NOT_FOUND);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static("max-age=300")
    );
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("We could not find that page"));
}
