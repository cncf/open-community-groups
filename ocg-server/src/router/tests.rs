use axum::{
    body::{Body, to_bytes},
    http::{HeaderValue, StatusCode, Uri, header::LOCATION},
};
use tower::ServiceExt;

use super::*;

#[tokio::test]
async fn test_health_check_returns_ok() {
    let response = health_check().await.into_response();
    let (parts, body) = response.into_parts();

    assert_eq!(parts.status, StatusCode::OK);
    assert!(to_bytes(body, usize::MAX).await.unwrap().is_empty());
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
