use axum::{
    body::Body,
    http::{
        Request, StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE, HOST, REFERER},
    },
};
use axum_login::tower_sessions::session;
use serde_json::{Value, json};

use crate::{
    db::mock::MockDB,
    handlers::tests::{
        DashboardIds, TestRouterBuilder, assert_empty_response, authenticated_request,
        expect_session, request, sample_server_cfg, send,
    },
    router::CACHE_CONTROL_PRIVATE_NO_STORE,
    services::images::MockImageStorage,
    test_util::sample_png,
    types::images::Image,
};

use super::*;

const PNG_BYTES: &[u8] = &[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
];

#[tokio::test]
async fn test_serve_allows_cross_origin_referer_when_hotlinking_enabled() {
    // Setup an image storage returning the stored image
    let storage = storage_returning("foo.png", sample_image(PNG_BYTES, "image/png"));

    // Setup router with hotlinking enabled and send a cross-origin request
    let router = TestRouterBuilder::new(MockDB::new())
        .with_image_storage(storage)
        .with_server_cfg(HttpServerConfig {
            allow_image_hotlinking: true,
            ..sample_server_cfg("https://example.test")
        })
        .build()
        .await;
    let request = request("GET", "/images/foo.png")
        .header(REFERER, "https://other.test/page")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the image is served for any origin
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers[CROSS_ORIGIN_RESOURCE_POLICY],
        RESOURCE_POLICY_CROSS_ORIGIN
    );
    assert_eq!(bytes.as_ref(), PNG_BYTES);
}

#[tokio::test]
async fn test_serve_badge_returns_referenced_image_without_referer() {
    // Setup a referenced stored badge image
    let mut db = MockDB::new();
    db.expect_is_badge_image()
        .times(1)
        .withf(|file_name| file_name == "badge.png")
        .returning(|_| Ok(true));
    let storage = storage_returning("badge.png", sample_image(PNG_BYTES, "image/png"));

    // Request the public badge image without a referer
    let router = TestRouterBuilder::new(db)
        .with_image_storage(storage)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = request("GET", "/images/badges/badge.png")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the referenced image uses the immutable public response contract
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(parts.headers[CACHE_CONTROL], CACHE_CONTROL_IMMUTABLE);
    assert_eq!(
        parts.headers[CROSS_ORIGIN_RESOURCE_POLICY],
        RESOURCE_POLICY_CROSS_ORIGIN
    );
    assert_eq!(bytes.as_ref(), PNG_BYTES);
}

#[tokio::test]
async fn test_serve_badge_returns_not_found_for_unreferenced_image() {
    // Setup an unreferenced badge basename
    let mut db = MockDB::new();
    db.expect_is_badge_image()
        .times(1)
        .withf(|file_name| file_name == "missing.png")
        .returning(|_| Ok(false));
    let mut storage = MockImageStorage::new();
    storage.expect_get().never();

    // Request the unreferenced public badge image
    let router = TestRouterBuilder::new(db)
        .with_image_storage(storage)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = request("GET", "/images/badges/missing.png")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check storage is not consulted and the route remains private by default
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
    assert_eq!(parts.headers[CACHE_CONTROL], CACHE_CONTROL_PRIVATE_NO_STORE);
}

#[tokio::test]
async fn test_serve_open_graph_returns_not_found_for_unreferenced_image() {
    // Setup an image not configured for previews
    let mut db = MockDB::new();
    db.expect_is_open_graph_image()
        .times(1)
        .withf(|file_name| file_name == "foo.png")
        .returning(|_| Ok(false));
    let mut storage = MockImageStorage::new();
    storage.expect_get().never();

    // Setup router and send request without referer
    let router = TestRouterBuilder::new(db)
        .with_image_storage(storage)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = request("GET", "/images/og/foo.png").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the image is not published
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
    assert_eq!(parts.headers[CACHE_CONTROL], CACHE_CONTROL_PRIVATE_NO_STORE);
}

#[tokio::test]
async fn test_serve_open_graph_returns_referenced_image_without_referer() {
    // Setup an image configured for previews
    let mut db = MockDB::new();
    db.expect_is_open_graph_image()
        .times(1)
        .withf(|file_name| file_name == "foo.png")
        .returning(|_| Ok(true));
    let storage = storage_returning("foo.png", sample_image(PNG_BYTES, "image/png"));

    // Setup router and send request without referer
    let router = TestRouterBuilder::new(db)
        .with_image_storage(storage)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = request("GET", "/images/og/foo.png").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(parts.headers[CACHE_CONTROL], CACHE_CONTROL_IMMUTABLE);
    assert_eq!(
        parts.headers[CROSS_ORIGIN_RESOURCE_POLICY],
        RESOURCE_POLICY_CROSS_ORIGIN
    );
    assert_eq!(bytes.as_ref(), PNG_BYTES);
}

#[tokio::test]
async fn test_serve_rejects_mismatched_referer() {
    // Setup an image storage that must not be read
    let mut storage = MockImageStorage::new();
    storage.expect_get().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(MockDB::new())
        .with_image_storage(storage)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = request("GET", "/images/foo.png")
        .header(REFERER, "https://unauthorized.test/images/foo.png")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_serve_returns_bytes_with_headers() {
    // Setup an image storage returning the stored image
    let storage = storage_returning("foo.png", sample_image(PNG_BYTES, "image/png"));

    // Setup router and send request
    let router = TestRouterBuilder::new(MockDB::new())
        .with_image_storage(storage)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = request("GET", "/images/foo.png")
        .header(REFERER, "https://example.test/images/foo.png")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(parts.headers[CACHE_CONTROL], CACHE_CONTROL_IMMUTABLE);
    assert_eq!(
        parts.headers[CROSS_ORIGIN_RESOURCE_POLICY],
        RESOURCE_POLICY_SAME_ORIGIN
    );
    assert_eq!(parts.headers[CONTENT_TYPE], "image/png");
    assert_eq!(parts.headers[X_CONTENT_TYPE_OPTIONS], "nosniff");
    assert_eq!(bytes.as_ref(), PNG_BYTES);
}

#[tokio::test]
async fn test_serve_returns_isolated_svg() {
    // Setup an image storage returning a stored SVG
    let svg_bytes = br#"<svg xmlns="http://www.w3.org/2000/svg"><circle/></svg>"#;
    let storage = storage_returning("foo.svg", sample_image(svg_bytes, "image/svg+xml"));

    // Setup router and send request
    let router = TestRouterBuilder::new(MockDB::new())
        .with_image_storage(storage)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = request("GET", "/images/foo.svg")
        .header(REFERER, "https://example.test/images/foo.svg")
        .body(Body::empty())
        .unwrap();
    let (parts, _) = send(router, request).await;

    // Check SVGs are isolated from the application origin
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(parts.headers[CONTENT_SECURITY_POLICY], "sandbox");
    assert_eq!(parts.headers[X_CONTENT_TYPE_OPTIONS], "nosniff");
}

#[tokio::test]
async fn test_serve_returns_not_found_for_missing_image() {
    // Setup an image storage without the requested image
    let mut storage = MockImageStorage::new();
    storage
        .expect_get()
        .times(1)
        .withf(|file_name| file_name == "missing.png")
        .returning(|_| Box::pin(async { Ok(None) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(MockDB::new())
        .with_image_storage(storage)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = request("GET", "/images/missing.png")
        .header(REFERER, "https://example.test/images/missing.png")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_upload_accepts_exact_open_graph_dimensions() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let png_bytes = sample_png(
        ImageTarget::OpenGraph.width(),
        ImageTarget::OpenGraph.height(),
    );
    let expected_file_name = format!("{}.png", compute_hash(&png_bytes));

    // Setup database and image storage mocks
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    let mut storage = MockImageStorage::new();
    let (expected_bytes, file_name) = (png_bytes.clone(), expected_file_name.clone());
    storage
        .expect_save()
        .times(1)
        .withf(move |image| {
            image.file_name == file_name
                && image.content_type == "image/png"
                && image.bytes == expected_bytes
                && image.user_id == ids.user_id
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_image_storage(storage)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = upload_request(
        ids.session_id,
        multipart_body(Some("open_graph"), &png_bytes),
        Some("https://example.test/dashboard"),
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::CREATED);
    let body: Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(
        body,
        json!({ "url": format!("/images/{expected_file_name}") })
    );
}

#[tokio::test]
async fn test_upload_rejects_missing_file() {
    // Setup a signed-in uploader and an image storage that must not be written
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    let mut storage = MockImageStorage::new();
    storage.expect_save().never();

    // Setup router and send a payload with only the target field
    let router = TestRouterBuilder::new(db)
        .with_image_storage(storage)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let body = format!(
        "--{UPLOAD_BOUNDARY}\r\nContent-Disposition: form-data; name=\"target\"\r\n\r\nlogo\r\n--{UPLOAD_BOUNDARY}--\r\n"
    );
    let request = upload_request(
        ids.session_id,
        body.into_bytes(),
        Some("https://example.test/dashboard"),
    );
    let (parts, bytes) = send(router, request).await;

    // Check the upload is rejected with the missing file message
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "missing file in upload payload"
    );
}

#[tokio::test]
async fn test_upload_rejects_missing_referer_when_hotlinking_allowed() {
    // Setup a signed-in uploader and an image storage that must not be written
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    let mut storage = MockImageStorage::new();
    storage.expect_save().never();

    // Setup router with image hotlinking allowed
    let router = TestRouterBuilder::new(db)
        .with_image_storage(storage)
        .with_server_cfg(HttpServerConfig {
            allow_image_hotlinking: true,
            ..sample_server_cfg("https://example.test")
        })
        .build()
        .await;

    // Send request without referer
    let request = upload_request(ids.session_id, multipart_body(None, PNG_BYTES), None);
    let (parts, bytes) = send(router, request).await;

    // Check hotlinking does not relax upload origin enforcement
    assert_empty_response(&parts, &bytes, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_upload_rejects_missing_referer_when_hotlinking_disabled() {
    // Setup a signed-in uploader and an image storage that must not be written
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    let mut storage = MockImageStorage::new();
    storage.expect_save().never();

    // Setup router with image hotlinking disabled
    let router = TestRouterBuilder::new(db)
        .with_image_storage(storage)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;

    // Send request without referer
    let request = upload_request(ids.session_id, multipart_body(None, PNG_BYTES), None);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_upload_rejects_wrong_ad_banner_dimensions() {
    // Setup a signed-in uploader and an image storage that must not be written
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    let mut storage = MockImageStorage::new();
    storage.expect_save().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_image_storage(storage)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = upload_request(
        ids.session_id,
        multipart_body(Some("ad_banner"), PNG_BYTES),
        Some("https://example.test/dashboard"),
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "image dimensions 1x1 do not match required 2400x300"
    );
}

#[tokio::test]
async fn test_upload_rejects_wrong_open_graph_dimensions() {
    // Setup a signed-in uploader and an image storage that must not be written
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    let mut storage = MockImageStorage::new();
    storage.expect_save().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_image_storage(storage)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = upload_request(
        ids.session_id,
        multipart_body(Some("open_graph"), PNG_BYTES),
        Some("https://example.test/dashboard"),
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "image dimensions 1x1 do not match required 1200x630"
    );
}

#[tokio::test]
async fn test_upload_stores_image_and_returns_url() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let expected_file_name = format!("{}.png", compute_hash(PNG_BYTES));

    // Setup database and image storage mocks
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    let mut storage = MockImageStorage::new();
    let file_name = expected_file_name.clone();
    storage
        .expect_save()
        .times(1)
        .withf(move |image| {
            image.file_name == file_name
                && image.content_type == "image/png"
                && image.bytes == PNG_BYTES
                && image.user_id == ids.user_id
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_image_storage(storage)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = upload_request(
        ids.session_id,
        multipart_body(None, PNG_BYTES),
        Some("https://example.test/dashboard"),
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::CREATED);
    let body: Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(
        body,
        json!({ "url": format!("/images/{expected_file_name}") })
    );
}

// Helpers.

/// Multipart boundary of the upload requests.
const UPLOAD_BOUNDARY: &str = "X-BOUNDARY";

/// Encodes an upload multipart body with an optional target field.
fn multipart_body(target: Option<&str>, bytes: &[u8]) -> Vec<u8> {
    let mut body = Vec::new();
    if let Some(target) = target {
        body.extend_from_slice(
            format!("--{UPLOAD_BOUNDARY}\r\nContent-Disposition: form-data; name=\"target\"\r\n\r\n{target}\r\n")
                .as_bytes(),
        );
    }
    body.extend_from_slice(
        format!(
            "--{UPLOAD_BOUNDARY}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"example.png\"\r\nContent-Type: image/png\r\n\r\n"
        )
        .as_bytes(),
    );
    body.extend_from_slice(bytes);
    body.extend_from_slice(format!("\r\n--{UPLOAD_BOUNDARY}--\r\n").as_bytes());
    body
}

/// Builds a stored image with the given bytes and content type.
fn sample_image(bytes: &[u8], content_type: &str) -> Image {
    Image {
        bytes: bytes.to_vec(),
        content_type: content_type.to_string(),
    }
}

/// Builds an image storage that returns `image` once for `file_name`.
fn storage_returning(file_name: &'static str, image: Image) -> MockImageStorage {
    let mut storage = MockImageStorage::new();
    storage
        .expect_get()
        .times(1)
        .withf(move |name| name == file_name)
        .return_once(move |_| Box::pin(async move { Ok(Some(image)) }));
    storage
}

/// Builds an authenticated upload request for the test site host.
fn upload_request(session_id: session::Id, body: Vec<u8>, referer: Option<&str>) -> Request<Body> {
    let mut request = authenticated_request("POST", "/images", session_id)
        .header(HOST, "example.test")
        .header(
            CONTENT_TYPE,
            format!("multipart/form-data; boundary={UPLOAD_BOUNDARY}"),
        );
    if let Some(referer) = referer {
        request = request.header(REFERER, referer);
    }
    request.body(Body::from(body)).unwrap()
}
