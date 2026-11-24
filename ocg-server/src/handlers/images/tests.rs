use std::{
    pin::Pin,
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
    task::{Context, Poll},
};

use axum::{
    body::Body,
    http::{
        Request, StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE, HOST, REFERER},
    },
};
use axum_login::tower_sessions::session;
use serde_json::{Value, json};
use tokio::io::{AsyncRead, ReadBuf};
use tokio_util::io::ReaderStream;

use crate::{
    db::mock::MockDB,
    handlers::{
        error::{INVALID_REQUEST_PAYLOAD, REQUEST_PAYLOAD_TOO_LARGE},
        tests::{
            DEFAULT_BODY_LIMIT_BYTES, DashboardIds, TestRouterBuilder, assert_empty_response,
            authenticated_request, expect_session, request, sample_server_cfg, send,
        },
    },
    router::CACHE_CONTROL_PRIVATE_NO_STORE,
    services::images::{ImagesError, MockImagesManager},
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
    // Setup an images manager returning the stored image
    let manager = manager_returning("foo.png", sample_image(PNG_BYTES, "image/png"));

    // Setup router with hotlinking enabled and send a cross-origin request
    let router = TestRouterBuilder::new(MockDB::new())
        .with_images_manager(manager)
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
    let manager = manager_returning("badge.png", sample_image(PNG_BYTES, "image/png"));

    // Request the public badge image without a referer
    let router = TestRouterBuilder::new(db)
        .with_images_manager(manager)
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
    let mut manager = MockImagesManager::new();
    manager.expect_get().never();

    // Request the unreferenced public badge image
    let router = TestRouterBuilder::new(db)
        .with_images_manager(manager)
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
    let mut manager = MockImagesManager::new();
    manager.expect_get().never();

    // Setup router and send request without referer
    let router = TestRouterBuilder::new(db)
        .with_images_manager(manager)
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
    let manager = manager_returning("foo.png", sample_image(PNG_BYTES, "image/png"));

    // Setup router and send request without referer
    let router = TestRouterBuilder::new(db)
        .with_images_manager(manager)
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
    // Setup an images manager that must not be read
    let mut manager = MockImagesManager::new();
    manager.expect_get().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(MockDB::new())
        .with_images_manager(manager)
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
    // Setup an images manager returning the stored image
    let manager = manager_returning("foo.png", sample_image(PNG_BYTES, "image/png"));

    // Setup router and send request
    let router = TestRouterBuilder::new(MockDB::new())
        .with_images_manager(manager)
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
    // Setup an images manager returning a stored SVG
    let svg_bytes = br#"<svg xmlns="http://www.w3.org/2000/svg"><circle/></svg>"#;
    let manager = manager_returning("foo.svg", sample_image(svg_bytes, "image/svg+xml"));

    // Setup router and send request
    let router = TestRouterBuilder::new(MockDB::new())
        .with_images_manager(manager)
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
    // Setup an images manager without the requested image
    let mut manager = MockImagesManager::new();
    manager
        .expect_get()
        .times(1)
        .withf(|file_name| file_name == "missing.png")
        .returning(|_| Box::pin(async { Ok(None) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(MockDB::new())
        .with_images_manager(manager)
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
async fn test_upload_accepts_multi_chunk_exact_limit_stream() {
    // Setup identifiers and an exact-limit payload with a non-uniform byte pattern
    let ids = DashboardIds::new();
    let payload: Vec<u8> = (0..MAX_IMAGE_SIZE_BYTES)
        .map(|index| u8::try_from(index % 251).unwrap())
        .collect();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    let mut manager = MockImagesManager::new();
    let expected_payload = payload.clone();
    manager
        .expect_upload()
        .times(1)
        .withf(move |input| {
            input.bytes == expected_payload
                && input.file_name == "example.png"
                && input.target.is_none()
                && input.user_id == ids.user_id
        })
        .returning(|_| Box::pin(async { Ok("exact-limit.png".to_string()) }));

    // Stream the exact-limit multipart body in 64 KiB chunks
    let chunk_size = 64 * 1024;
    let raw_body = multipart_body(None, &payload);
    let read_bytes = Arc::new(AtomicUsize::new(0));
    let reader = CountingReader {
        bytes: raw_body,
        chunk_size,
        offset: 0,
        read_bytes,
        yield_pending: false,
    };
    let stream_body = Body::from_stream(ReaderStream::with_capacity(reader, chunk_size));

    // Setup router and send the multi-chunk upload
    let router = TestRouterBuilder::new(db)
        .with_images_manager(manager)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = upload_request_with_body(
        ids.session_id,
        stream_body,
        Some("https://example.test/dashboard"),
    );
    let (parts, bytes) = send(router, request).await;

    // Check the exact-limit payload is reassembled and accepted
    assert_eq!(parts.status, StatusCode::CREATED);
    let body: Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "url": "/images/exact-limit.png" }));
}

#[tokio::test]
async fn test_upload_forwards_target_and_returns_badge_url() {
    // Setup identifiers and mocks
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    let mut manager = MockImagesManager::new();
    manager
        .expect_upload()
        .times(1)
        .withf(move |input| {
            input.bytes == PNG_BYTES
                && input.file_name == "example.png"
                && input.target == Some(ImageTarget::Badge)
                && input.user_id == ids.user_id
        })
        .returning(|_| Box::pin(async { Ok("stored-badge.png".to_string()) }));

    // Setup router and send request with the badge target
    let router = TestRouterBuilder::new(db)
        .with_images_manager(manager)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = upload_request(
        ids.session_id,
        multipart_body(Some("badge"), PNG_BYTES),
        Some("https://example.test/dashboard"),
    );
    let (parts, bytes) = send(router, request).await;

    // Check the badge target uses the public badge image path
    assert_eq!(parts.status, StatusCode::CREATED);
    let body: Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "url": "/images/badges/stored-badge.png" }));
}

#[tokio::test]
async fn test_upload_rejects_manager_rejection() {
    // Setup a signed-in uploader and an images manager rejecting the upload
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    let mut manager = MockImagesManager::new();
    manager
        .expect_upload()
        .times(1)
        .withf(move |input| {
            input.bytes == PNG_BYTES
                && input.file_name == "example.png"
                && input.target == Some(ImageTarget::OpenGraph)
                && input.user_id == ids.user_id
        })
        .returning(|_| {
            Box::pin(async {
                Err(ImagesError::Rejected(
                    "image dimensions 1x1 do not match required 1200x630".to_string(),
                ))
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_images_manager(manager)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = upload_request(
        ids.session_id,
        multipart_body(Some("open_graph"), PNG_BYTES),
        Some("https://example.test/dashboard"),
    );
    let (parts, bytes) = send(router, request).await;

    // Check a manager rejection returns 422 with its message
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "image dimensions 1x1 do not match required 1200x630"
    );
}

#[tokio::test]
async fn test_upload_rejects_missing_file() {
    // Setup a signed-in uploader and an images manager that must not be called
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    let mut manager = MockImagesManager::new();
    manager.expect_upload().never();

    // Setup router and send a payload with only the target field
    let router = TestRouterBuilder::new(db)
        .with_images_manager(manager)
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
    // Setup a signed-in uploader and an images manager that must not be called
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    let mut manager = MockImagesManager::new();
    manager.expect_upload().never();

    // Setup router with image hotlinking allowed
    let router = TestRouterBuilder::new(db)
        .with_images_manager(manager)
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
    // Setup a signed-in uploader and an images manager that must not be called
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    let mut manager = MockImagesManager::new();
    manager.expect_upload().never();

    // Setup router with image hotlinking disabled
    let router = TestRouterBuilder::new(db)
        .with_images_manager(manager)
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
async fn test_upload_rejects_oversized_image() {
    // Setup a signed-in uploader and an images manager that must not be called
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    let mut manager = MockImagesManager::new();
    manager.expect_upload().never();

    // Setup router and send an image over the size limit
    let router = TestRouterBuilder::new(db)
        .with_images_manager(manager)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = upload_request(
        ids.session_id,
        multipart_body(None, &vec![0; MAX_IMAGE_SIZE_BYTES + 1]),
        Some("https://example.test/dashboard"),
    );
    let (parts, bytes) = send(router, request).await;

    // Check the oversized image is rejected before calling the manager
    assert_eq!(parts.status, StatusCode::PAYLOAD_TOO_LARGE);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "image exceeds 1MB limit"
    );
}

#[tokio::test]
async fn test_upload_rejects_oversized_stream_early() {
    // Setup a signed-in uploader and an images manager that must not be called
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    let mut manager = MockImagesManager::new();
    manager.expect_upload().never();

    // Setup a 3 MiB streaming multipart body read in 64 KiB chunks
    let chunk_size = 64 * 1024;
    let payload_size = 3 * 1024 * 1024;
    let raw_body = multipart_body(None, &vec![0; payload_size]);
    let read_bytes = Arc::new(AtomicUsize::new(0));
    let reader = CountingReader {
        bytes: raw_body,
        chunk_size,
        offset: 0,
        read_bytes: read_bytes.clone(),
        yield_pending: false,
    };
    let stream_body = Body::from_stream(ReaderStream::with_capacity(reader, chunk_size));

    // Setup router and send the streaming multipart request
    let router = TestRouterBuilder::new(db)
        .with_images_manager(manager)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = upload_request_with_body(
        ids.session_id,
        stream_body,
        Some("https://example.test/dashboard"),
    );
    let (parts, bytes) = send(router, request).await;

    // Check the handler aborts with 413 well before draining the remaining stream
    assert_eq!(parts.status, StatusCode::PAYLOAD_TOO_LARGE);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "image exceeds 1MB limit"
    );
    let bytes_read = read_bytes.load(Ordering::Relaxed);
    assert!(
        bytes_read > MAX_IMAGE_SIZE_BYTES,
        "expected reader to advance past 1 MiB, read {bytes_read} bytes"
    );
    assert!(
        bytes_read < DEFAULT_BODY_LIMIT_BYTES,
        "expected stream to stop early below 2 MiB body limit, read {bytes_read} bytes"
    );
}

#[tokio::test]
async fn test_upload_rejects_unreadable_multipart_body() {
    // Setup one unreadable body per multipart error class with its response
    let cases: Vec<(&str, Vec<u8>, StatusCode, &str)> = vec![
        (
            "body over the request limit",
            multipart_body(None, &vec![0; DEFAULT_BODY_LIMIT_BYTES + 1]),
            StatusCode::PAYLOAD_TOO_LARGE,
            REQUEST_PAYLOAD_TOO_LARGE,
        ),
        (
            "field without a closing boundary",
            format!(
                "--{UPLOAD_BOUNDARY}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"example.png\"\r\n\r\nincomplete"
            )
            .into_bytes(),
            StatusCode::BAD_REQUEST,
            INVALID_REQUEST_PAYLOAD,
        ),
        (
            "truncated field headers",
            format!("--{UPLOAD_BOUNDARY}\r\nContent-Disposition: form-data; name=\"file\"")
                .into_bytes(),
            StatusCode::BAD_REQUEST,
            INVALID_REQUEST_PAYLOAD,
        ),
    ];

    for (case, body, expected_status, expected_body) in cases {
        // Setup a signed-in uploader and an images manager that must not be called
        let ids = DashboardIds::new();
        let mut db = MockDB::new();
        expect_session(&mut db, &ids);
        let mut manager = MockImagesManager::new();
        manager.expect_upload().never();

        // Setup router and send the unreadable multipart body
        let router = TestRouterBuilder::new(db)
            .with_images_manager(manager)
            .with_server_cfg(sample_server_cfg("https://example.test"))
            .build()
            .await;
        let request = upload_request(ids.session_id, body, Some("https://example.test/dashboard"));
        let (parts, bytes) = send(router, request).await;

        // Check the client error is answered with axum's status and a fixed body
        assert_eq!(parts.status, expected_status, "{case}");
        assert_eq!(String::from_utf8_lossy(&bytes), expected_body, "{case}");
    }
}

#[tokio::test]
async fn test_upload_rejects_unknown_target() {
    // Setup a signed-in uploader and an images manager that must not be called
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    let mut manager = MockImagesManager::new();
    manager.expect_upload().never();

    // Setup router and send an upload with an unknown target
    let router = TestRouterBuilder::new(db)
        .with_images_manager(manager)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = upload_request(
        ids.session_id,
        multipart_body(Some("unknown"), PNG_BYTES),
        Some("https://example.test/dashboard"),
    );
    let (parts, bytes) = send(router, request).await;

    // Check the unknown target is rejected as a bad request
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "unknown image target"
    );
}

#[tokio::test]
async fn test_upload_stores_image_and_returns_url() {
    // Setup identifiers and mocks
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    let mut manager = MockImagesManager::new();
    manager
        .expect_upload()
        .times(1)
        .withf(move |input| {
            input.bytes == PNG_BYTES
                && input.file_name == "example.png"
                && input.target.is_none()
                && input.user_id == ids.user_id
        })
        .returning(|_| Box::pin(async { Ok("stored-image.png".to_string()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_images_manager(manager)
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
    assert_eq!(body, json!({ "url": "/images/stored-image.png" }));
}

// Helpers.

/// Multipart boundary of the upload requests.
const UPLOAD_BOUNDARY: &str = "X-BOUNDARY";

/// Async reader that yields one chunk per poll cycle and counts bytes read.
struct CountingReader {
    /// Complete request body bytes.
    bytes: Vec<u8>,
    /// Maximum number of bytes yielded per read poll.
    chunk_size: usize,
    /// Current read cursor inside `bytes`.
    offset: usize,
    /// Cumulative number of bytes pulled by the body consumer.
    read_bytes: Arc<AtomicUsize>,
    /// Whether the next poll should yield `Pending` so `multer` surfaces chunks incrementally.
    yield_pending: bool,
}

impl AsyncRead for CountingReader {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        if self.yield_pending {
            self.yield_pending = false;
            cx.waker().wake_by_ref();
            return Poll::Pending;
        }
        let remaining = self.bytes.len().saturating_sub(self.offset);
        let to_copy = remaining.min(self.chunk_size).min(buf.remaining());
        if to_copy > 0 {
            let end = self.offset + to_copy;
            buf.put_slice(&self.bytes[self.offset..end]);
            self.offset = end;
            self.read_bytes.fetch_add(to_copy, Ordering::Relaxed);
            self.yield_pending = true;
        }
        Poll::Ready(Ok(()))
    }
}

/// Builds an images manager that returns `image` once for `file_name`.
fn manager_returning(file_name: &'static str, image: Image) -> MockImagesManager {
    let mut manager = MockImagesManager::new();
    manager
        .expect_get()
        .times(1)
        .withf(move |name| name == file_name)
        .return_once(move |_| Box::pin(async move { Ok(Some(image)) }));
    manager
}

/// Encodes an upload multipart body for `example.png` with an optional target field.
fn multipart_body(target: Option<&str>, bytes: &[u8]) -> Vec<u8> {
    multipart_body_with_file_name(target, "example.png", bytes)
}

/// Encodes an upload multipart body with an optional target field and a file name.
fn multipart_body_with_file_name(target: Option<&str>, file_name: &str, bytes: &[u8]) -> Vec<u8> {
    let mut body = Vec::new();
    if let Some(target) = target {
        body.extend_from_slice(
            format!("--{UPLOAD_BOUNDARY}\r\nContent-Disposition: form-data; name=\"target\"\r\n\r\n{target}\r\n")
                .as_bytes(),
        );
    }
    body.extend_from_slice(
        format!(
            "--{UPLOAD_BOUNDARY}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{file_name}\"\r\nContent-Type: application/octet-stream\r\n\r\n"
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

/// Builds an authenticated upload request for the test site host.
fn upload_request(session_id: session::Id, body: Vec<u8>, referer: Option<&str>) -> Request<Body> {
    upload_request_with_body(session_id, Body::from(body), referer)
}

/// Builds an authenticated upload request with a custom body for the test site host.
fn upload_request_with_body(
    session_id: session::Id,
    body: Body,
    referer: Option<&str>,
) -> Request<Body> {
    let mut request = authenticated_request("POST", "/images", session_id)
        .header(HOST, "example.test")
        .header("Sec-Fetch-Site", "same-origin")
        .header(
            CONTENT_TYPE,
            format!("multipart/form-data; boundary={UPLOAD_BOUNDARY}"),
        );
    if let Some(referer) = referer {
        request = request.header(REFERER, referer);
    }
    request.body(body).unwrap()
}
