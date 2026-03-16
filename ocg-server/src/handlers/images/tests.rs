use std::sync::Arc;

use axum::http::header::{CACHE_CONTROL, CONTENT_TYPE, COOKIE, HOST, REFERER};
use axum::{
    Router,
    body::{Body, to_bytes},
    http::{Request, StatusCode},
    routing::get,
};
use axum_login::tower_sessions::session;
use serde_json::Value;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::{DynDB, mock::MockDB},
    handlers::tests::{TestRouterBuilder, sample_auth_user, sample_session_record},
    router::{State as RouterState, serde_qs_config},
    services::{
        images::{DynImageStorage, Image, MockImageStorage},
        notifications::{DynNotificationsManager, MockNotificationsManager},
    },
};

use super::*;

const PNG_BYTES: &[u8] = &[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00,
    0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00,
    0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01,
    0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

#[test]
fn test_is_svg_accepts_valid_svg() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
        <circle cx="50" cy="50" r="40" fill="blue"/>
    </svg>"#;
    assert!(is_svg(svg, "svg"));
}

#[test]
fn test_is_svg_accepts_valid_svg_with_data_image_url() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg">
        <image href="data:image/png;base64,iVBORw0KGgoAAAANS=" />
    </svg>"#;
    assert!(is_svg(svg, "svg"));
}

#[test]
fn test_is_svg_rejects_data_url_without_image_prefix() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg">
        <image href="data:text/html,<script>alert('xss')</script>" />
    </svg>"#;
    assert!(!is_svg(svg, "svg"));
}

#[test]
fn test_is_svg_rejects_foreign_object_element() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg">
        <foreignObject><body/></foreignObject>
    </svg>"#;
    assert!(!is_svg(svg, "svg"));
}

#[test]
fn test_is_svg_rejects_javascript_url_in_href() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg">
        <a href="javascript:alert('xss')">click</a>
    </svg>"#;
    assert!(!is_svg(svg, "svg"));
}

#[test]
fn test_is_svg_rejects_javascript_url_in_xlink_href() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg">
        <image xlink:href="javascript:alert('xss')" />
    </svg>"#;
    assert!(!is_svg(svg, "svg"));
}

#[test]
fn test_is_svg_rejects_malformed_xml() {
    let malformed = b"<svg xmlns=\"http://www.w3.org/2000/svg\"><unclosed";
    assert!(!is_svg(malformed, "svg"));
}

#[test]
fn test_is_svg_rejects_missing_namespace() {
    let svg = b"<svg><circle cx=\"50\" cy=\"50\" r=\"40\"/></svg>";
    assert!(!is_svg(svg, "svg"));
}

#[test]
fn test_is_svg_rejects_non_svg_extension() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg"><circle/></svg>"#;
    assert!(!is_svg(svg, "png"));
}

#[test]
fn test_is_svg_rejects_non_svg_root_element() {
    let xml = br#"<html xmlns="http://www.w3.org/2000/svg"><body/></html>"#;
    assert!(!is_svg(xml, "svg"));
}

#[test]
fn test_is_svg_rejects_onclick_attribute() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg">
        <circle onclick="alert('xss')" cx="50" cy="50" r="40"/>
    </svg>"#;
    assert!(!is_svg(svg, "svg"));
}

#[test]
fn test_is_svg_rejects_onload_attribute() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg" onload="alert('xss')">
        <circle cx="50" cy="50" r="40"/>
    </svg>"#;
    assert!(!is_svg(svg, "svg"));
}

#[test]
fn test_is_svg_rejects_script_element() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg">
        <script>alert('xss')</script>
    </svg>"#;
    assert!(!is_svg(svg, "svg"));
}

#[tokio::test]
async fn test_serve_allows_missing_referer_when_checks_disabled() {
    // Setup mocks
    let mut storage = MockImageStorage::new();
    storage
        .expect_get()
        .times(1)
        .withf(|file_name| file_name == "foo.png")
        .returning(|_| Box::pin(async { Ok(None) }));
    let image_storage: DynImageStorage = Arc::new(storage);

    // Setup router and send request without referer
    let mut state = build_state(Arc::clone(&image_storage));
    state.server_cfg.disable_referer_checks = true;
    let router = Router::new()
        .route("/images/{file_name}", get(serve))
        .with_state(state);
    let response = router
        .oneshot(Request::builder().uri("/images/foo.png").body(Body::empty()).unwrap())
        .await
        .unwrap();

    // Check response matches expectations
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_serve_rejects_mismatched_referer() {
    // Setup mocks
    let mut storage = MockImageStorage::new();
    storage.expect_get().never();

    // Setup router and send request
    let router = Router::new()
        .route("/images/{file_name}", get(serve))
        .with_state(build_state(Arc::new(storage)));
    let response = router
        .oneshot(
            Request::builder()
                .uri("/images/foo.png")
                .header(REFERER, "https://unauthorized.test/images/foo.png")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // Check response matches expectations
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_serve_returns_bytes_with_headers() {
    // Setup mocks
    let mut storage = MockImageStorage::new();
    storage
        .expect_get()
        .times(1)
        .withf(|file_name| file_name == "foo.png")
        .returning(|_| {
            let image = Image {
                bytes: PNG_BYTES.to_vec(),
                content_type: "image/png".to_string(),
            };
            Box::pin(async move { Ok(Some(image)) })
        });

    // Setup router and send request
    let router = Router::new()
        .route("/images/{file_name}", get(serve))
        .with_state(build_state(Arc::new(storage)));
    let response = router
        .oneshot(
            Request::builder()
                .uri("/images/foo.png")
                .header(REFERER, "https://example.test/images/foo.png")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // Check response matches expectations
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(
        response
            .headers()
            .get(CACHE_CONTROL)
            .and_then(|value| value.to_str().ok()),
        Some(CACHE_CONTROL_IMMUTABLE)
    );
    assert_eq!(
        response
            .headers()
            .get(CONTENT_TYPE)
            .and_then(|value| value.to_str().ok()),
        Some("image/png")
    );
    let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    assert_eq!(bytes.as_ref(), PNG_BYTES);
}

#[tokio::test]
async fn test_serve_returns_not_found_for_missing_image() {
    // Setup mocks
    let mut storage = MockImageStorage::new();
    storage
        .expect_get()
        .times(1)
        .withf(|file_name| file_name == "missing.png")
        .returning(|_| Box::pin(async { Ok(None) }));

    // Setup router and send request
    let router = Router::new()
        .route("/images/{file_name}", get(serve))
        .with_state(build_state(Arc::new(storage)));
    let response = router
        .oneshot(
            Request::builder()
                .uri("/images/missing.png")
                .header(REFERER, "https://example.test/images/missing.png")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // Check response matches expectations
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_upload_allows_missing_referer_when_checks_disabled() {
    // Setup identifiers and data structures
    let expected_hash = compute_hash(PNG_BYTES);
    let expected_file_name = format!("{expected_hash}.png");
    let boundary = "X-BOUNDARY";
    let body = build_multipart_body(boundary, PNG_BYTES);
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

    // Setup image storage mock
    let expected_file_name_for_mock = expected_file_name.clone();
    let mut storage = MockImageStorage::new();
    storage
        .expect_save()
        .times(1)
        .withf(move |image| {
            image.file_name == expected_file_name_for_mock
                && image.content_type == "image/png"
                && image.bytes == PNG_BYTES
                && image.user_id == user_id
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router with referer checks disabled
    let server_cfg = HttpServerConfig {
        base_url: "https://example.test".to_string(),
        disable_referer_checks: true,
        ..HttpServerConfig::default()
    };
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_image_storage(storage)
        .with_server_cfg(server_cfg)
        .build()
        .await;

    // Send request without referer
    let request = Request::builder()
        .method("POST")
        .uri("/images")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, format!("multipart/form-data; boundary={boundary}"))
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let status = response.status();
    let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    let value: Value = serde_json::from_slice(&bytes).unwrap();

    // Check response matches expectations
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(
        value.get("url"),
        Some(&Value::String(format!("/images/{expected_file_name}")))
    );
}

#[tokio::test]
async fn test_upload_rejects_missing_referer() {
    // Setup identifiers and data structures
    let boundary = "X-BOUNDARY";
    let body = build_multipart_body(boundary, PNG_BYTES);
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

    // Setup image storage mock
    let mut storage = MockImageStorage::new();
    storage.expect_save().never();

    // Setup router with referer checks enabled
    let server_cfg = HttpServerConfig {
        base_url: "https://example.test".to_string(),
        ..HttpServerConfig::default()
    };
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_image_storage(storage)
        .with_server_cfg(server_cfg)
        .build()
        .await;

    // Send request without referer
    let request = Request::builder()
        .method("POST")
        .uri("/images")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, format!("multipart/form-data; boundary={boundary}"))
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();

    // Check response matches expectations
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_upload_stores_image_and_returns_url() {
    // Setup identifiers and data structures
    let expected_hash = compute_hash(PNG_BYTES);
    let expected_file_name = format!("{expected_hash}.png");
    let boundary = "X-BOUNDARY";
    let body = build_multipart_body(boundary, PNG_BYTES);
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

    // Setup image storage mock
    let expected_file_name_for_mock = expected_file_name.clone();
    let mut storage = MockImageStorage::new();
    storage
        .expect_save()
        .times(1)
        .withf(move |image| {
            image.file_name == expected_file_name_for_mock
                && image.content_type == "image/png"
                && image.bytes == PNG_BYTES
                && image.user_id == user_id
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let server_cfg = HttpServerConfig {
        base_url: "https://example.test".to_string(),
        ..HttpServerConfig::default()
    };
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_image_storage(storage)
        .with_server_cfg(server_cfg)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri("/images")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, format!("multipart/form-data; boundary={boundary}"))
        .header(REFERER, "https://example.test/dashboard")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let status = response.status();
    let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    let value: Value = serde_json::from_slice(&bytes).unwrap();

    // Check response matches expectations
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(
        value.get("url"),
        Some(&Value::String(format!("/images/{expected_file_name}")))
    );
}

#[test]
fn test_validate_image_dimensions_rejects_wrong_dimensions() {
    // PNG_BYTES is 1x1 pixel, should fail for any target
    let result = validate_image_dimensions(PNG_BYTES, ImageTarget::Logo);
    assert_eq!(
        result.unwrap_err().to_string(),
        "image dimensions 1x1 do not match required 360x360"
    );
}

// Helpers

fn build_multipart_body(boundary: &str, bytes: &[u8]) -> Vec<u8> {
    let mut body = Vec::new();
    body.extend_from_slice(
        format!(
            "--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"example.png\"\r\nContent-Type: image/png\r\n\r\n"
        )
        .as_bytes(),
    );
    body.extend_from_slice(bytes);
    body.extend_from_slice(format!("\r\n--{boundary}--\r\n").as_bytes());
    body
}

fn build_state(image_storage: DynImageStorage) -> RouterState {
    let activity_tracker = Arc::new(crate::activity_tracker::MockActivityTracker::new());
    let db: DynDB = Arc::new(MockDB::new());
    let notifications_manager: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

    RouterState {
        activity_tracker,
        db,
        image_storage,
        meetings_cfg: None,
        notifications_manager,
        serde_qs_de: serde_qs_config(),
        server_cfg: HttpServerConfig {
            base_url: "https://example.test".to_string(),
            ..HttpServerConfig::default()
        },
    }
}
