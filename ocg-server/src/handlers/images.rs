//! Handlers for uploading and serving image assets.

use std::{borrow::Cow, str::FromStr};

use anyhow::{Context, Result, anyhow};
use axum::{
    Json,
    body::Body,
    extract::{Multipart, Path, State},
    http::{
        HeaderMap, HeaderValue, StatusCode, Uri,
        header::{CACHE_CONTROL, CONTENT_TYPE, REFERER},
    },
    response::IntoResponse,
};
use image::ImageFormat;
use quick_xml::{Reader, events::Event};
use serde_json::json;
use sha2::{Digest, Sha256};
use tracing::instrument;

use crate::{
    auth::AuthSession,
    config::HttpServerConfig,
    handlers::error::HandlerError,
    services::images::{DynImageStorage, NewImage},
};

/// Maximum payload size allowed for image uploads (2 MiB).
const MAX_IMAGE_SIZE_BYTES: usize = 2 * 1024 * 1024;

/// Cache-Control header for long-lived responses.
const CACHE_CONTROL_IMMUTABLE: &str = "public, max-age=31536000, immutable";

/// Supported image formats accepted by the upload endpoint.
enum SupportedImageFormat {
    Gif,
    Jpeg,
    Png,
    Svg,
    Tiff,
    Webp,
}

// Handlers

/// Serves previously uploaded images.
#[instrument(skip_all, err)]
pub(crate) async fn serve(
    State(cfg): State<HttpServerConfig>,
    State(image_storage): State<DynImageStorage>,
    headers: HeaderMap,
    Path(file_name): Path<String>,
) -> Result<impl IntoResponse, HandlerError> {
    // Validate referer header matches configured hostname.
    if !referer_matches_site(&cfg, &headers)? {
        return Ok(StatusCode::FORBIDDEN.into_response());
    }

    // Retrieve image from storage
    let Some(image) = image_storage.get(&file_name).await? else {
        return Ok(StatusCode::NOT_FOUND.into_response());
    };

    // Prepare headers and body
    let mut response_headers = HeaderMap::new();
    response_headers.insert(CACHE_CONTROL, HeaderValue::from_static(CACHE_CONTROL_IMMUTABLE));
    response_headers.insert(
        CONTENT_TYPE,
        HeaderValue::from_str(&image.content_type).map_err(|err| HandlerError::Other(err.into()))?,
    );
    let body = Body::from(image.bytes);

    Ok((StatusCode::OK, response_headers, body).into_response())
}

/// Handles authenticated image uploads.
#[instrument(skip_all, err)]
pub(crate) async fn upload(
    auth_session: AuthSession,
    State(cfg): State<HttpServerConfig>,
    State(image_storage): State<DynImageStorage>,
    headers: HeaderMap,
    mut multipart: Multipart,
) -> Result<impl IntoResponse, HandlerError> {
    // Validate referer header matches configured hostname.
    if !referer_matches_site(&cfg, &headers)? {
        return Ok((StatusCode::FORBIDDEN).into_response());
    }

    // Extract file name and bytes from multipart payload
    let Ok(Some(field)) = multipart.next_field().await else {
        return Ok((StatusCode::BAD_REQUEST).into_response());
    };
    let file_name = field
        .file_name()
        .map(str::to_string)
        .ok_or_else(|| HandlerError::Other(anyhow!("missing file name in upload payload")))?;
    let data = field.bytes().await.context("error reading uploaded image")?;

    // Enforce maximum file size
    if data.len() > MAX_IMAGE_SIZE_BYTES {
        return Ok((StatusCode::PAYLOAD_TOO_LARGE, "image exceeds 2MB limit").into_response());
    }

    // Detect image format and check extension matches
    let extension = image_extension(&file_name)?;
    let format = detect_image_format(data.as_ref(), extension.as_ref())?;
    if !extension_matches(&format, extension.as_ref()) {
        return Ok((
            StatusCode::UNPROCESSABLE_ENTITY,
            "file extension does not match detected image format",
        )
            .into_response());
    }

    // Compute file hash
    let hash = compute_hash(data.as_ref());

    // Store image using the configured storage provider
    let new_image = NewImage {
        bytes: data.as_ref(),
        content_type: mime_type(&format),
        file_name: &format!("{hash}.{extension}"),
        user_id: auth_session.user.as_ref().expect("user to be logged in").user_id,
    };
    image_storage.save(&new_image).await?;

    // Prepare response with image URL
    let body = Json(json!({ "url": format!("/images/{}", new_image.file_name) }));

    Ok((StatusCode::CREATED, body).into_response())
}

// Helpers

/// Computes the SHA-256 hash of the provided data and returns a hexadecimal string.
fn compute_hash(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    format!("{:x}", hasher.finalize())
}

/// Detects the image format using the `image` crate with a fallback for SVGs.
fn detect_image_format(bytes: &[u8], extension: &str) -> Result<SupportedImageFormat> {
    match image::guess_format(bytes) {
        Ok(ImageFormat::Gif) => Ok(SupportedImageFormat::Gif),
        Ok(ImageFormat::Jpeg) => Ok(SupportedImageFormat::Jpeg),
        Ok(ImageFormat::Png) => Ok(SupportedImageFormat::Png),
        Ok(ImageFormat::Tiff) => Ok(SupportedImageFormat::Tiff),
        Ok(ImageFormat::WebP) => Ok(SupportedImageFormat::Webp),
        Ok(other) => Err(anyhow!("unsupported image format: {other:?}")),
        Err(_) if is_svg(bytes, extension) => Ok(SupportedImageFormat::Svg),
        Err(_) => Err(anyhow!("unsupported image format")),
    }
}

/// Returns the accepted extensions for the provided format.
fn expected_extensions(format: &SupportedImageFormat) -> &'static [&'static str] {
    match format {
        SupportedImageFormat::Gif => &["gif"],
        SupportedImageFormat::Jpeg => &["jpg", "jpeg"],
        SupportedImageFormat::Png => &["png"],
        SupportedImageFormat::Svg => &["svg"],
        SupportedImageFormat::Tiff => &["tif", "tiff"],
        SupportedImageFormat::Webp => &["webp"],
    }
}

/// Validates that the extension matches the detected image format.
fn extension_matches(format: &SupportedImageFormat, extension: &str) -> bool {
    expected_extensions(format)
        .iter()
        .any(|candidate| candidate == &extension)
}

/// Extracts the lowercase file extension from a file name.
fn image_extension(file_name: &str) -> Result<Cow<'_, str>> {
    let extension = file_name
        .rsplit('.')
        .next()
        .ok_or_else(|| anyhow!("missing file extension"))?;
    if extension.is_empty() {
        return Err(anyhow!("missing file extension"));
    }
    Ok(Cow::from(extension.to_ascii_lowercase()))
}

/// Determines whether the provided bytes and extension represent a valid SVG asset.
///
/// This performs lightweight XML parsing to verify:
/// - The extension is "svg"
/// - The file is well-formed XML
/// - The root element is <svg> with proper namespace
/// - No dangerous elements (<script>, <foreignObject>)
/// - No event handler attributes (onclick, onload, etc.)
/// - No javascript: or suspicious data: URLs
fn is_svg(bytes: &[u8], extension: &str) -> bool {
    const SVG_NAMESPACE: &[u8] = b"http://www.w3.org/2000/svg";
    const DANGEROUS_ELEMENTS: &[&[u8]] = &[b"script", b"foreignObject"];

    // Check extension first (fast path)
    if !extension.eq_ignore_ascii_case("svg") {
        return false;
    }

    let mut reader = Reader::from_reader(bytes);
    reader.config_mut().trim_text(true);

    let mut buf = Vec::new();
    let mut found_svg_root = false;
    let mut in_root = false;

    loop {
        match reader.read_event_into(&mut buf) {
            Ok(Event::Eof) => break,
            Ok(Event::Start(ref e) | Event::Empty(ref e)) => {
                let tag_name = e.name();

                // Check for root <svg> element with proper namespace
                if !in_root {
                    if tag_name.as_ref() != b"svg" {
                        return false;
                    }

                    // Verify SVG namespace is present
                    let has_svg_namespace = e.attributes().filter_map(Result::ok).any(|attr| {
                        (attr.key.as_ref() == b"xmlns" || attr.key.local_name().as_ref() == b"xmlns")
                            && attr.value.as_ref() == SVG_NAMESPACE
                    });

                    if !has_svg_namespace {
                        return false;
                    }

                    found_svg_root = true;
                    in_root = true;
                }

                // Check for dangerous elements
                for dangerous in DANGEROUS_ELEMENTS {
                    if tag_name.as_ref().eq_ignore_ascii_case(dangerous) {
                        return false;
                    }
                }

                // Check all attributes for dangerous content
                for attr in e.attributes().filter_map(Result::ok) {
                    let key = attr.key.as_ref();
                    let value = attr.value.as_ref();

                    // Block event handler attributes (onclick, onload, etc.)
                    if key.len() >= 2 && key[..2].eq_ignore_ascii_case(b"on") {
                        return false;
                    }

                    // Block javascript: URLs
                    if (key == b"href" || key == b"xlink:href")
                        && value.len() >= 11
                        && value[..11].eq_ignore_ascii_case(b"javascript:")
                    {
                        return false;
                    }

                    // Block suspicious data: URLs that might contain scripts
                    if (key == b"href" || key == b"xlink:href")
                        && value.len() >= 5
                        && value[..5].eq_ignore_ascii_case(b"data:")
                    {
                        // Allow data:image/ but block other data: URLs
                        if value.len() < 11 || !value[5..11].eq_ignore_ascii_case(b"image/") {
                            return false;
                        }
                    }
                }
            }
            Ok(_) => {}
            Err(_) => return false,
        }
        buf.clear();
    }

    if !found_svg_root {
        return false;
    }

    true
}

/// Returns the MIME type associated with the provided format.
fn mime_type(format: &SupportedImageFormat) -> &'static str {
    match format {
        SupportedImageFormat::Gif => "image/gif",
        SupportedImageFormat::Jpeg => "image/jpeg",
        SupportedImageFormat::Png => "image/png",
        SupportedImageFormat::Svg => "image/svg+xml",
        SupportedImageFormat::Tiff => "image/tiff",
        SupportedImageFormat::Webp => "image/webp",
    }
}

/// Checks whether the referer header matches the configured site hostname.
fn referer_matches_site(cfg: &HttpServerConfig, headers: &HeaderMap) -> Result<bool> {
    // Check if referer checks are disabled
    if cfg.disable_referer_checks {
        return Ok(true);
    }

    // Extract referer from headers
    let Some(referer) = headers.get(REFERER) else {
        return Ok(false);
    };
    let Ok(referer) = referer.to_str() else {
        return Ok(false);
    };

    // Extract referer and site host and compare
    let referer_host = Uri::from_str(referer)
        .ok()
        .and_then(|uri| uri.host().map(str::to_ascii_lowercase));
    let site_host = Uri::from_str(&cfg.base_url)
        .expect("valid base_url in config")
        .host()
        .map(str::to_ascii_lowercase)
        .ok_or_else(|| anyhow!("missing host in base_url"))?;

    Ok(referer_host.is_some_and(|referer_host| referer_host == site_host))
}

#[cfg(test)]
mod tests {
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
        handlers::tests::{sample_auth_user, sample_session_record, setup_test_router_with_image_storage},
        router::State as RouterState,
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
        state.cfg.disable_referer_checks = true;
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
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);

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
        let cfg = HttpServerConfig {
            base_url: "https://example.test".to_string(),
            disable_referer_checks: true,
            ..HttpServerConfig::default()
        };
        let router =
            setup_test_router_with_image_storage(cfg, db, MockNotificationsManager::new(), storage).await;

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
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);

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
        let cfg = HttpServerConfig {
            base_url: "https://example.test".to_string(),
            ..HttpServerConfig::default()
        };
        let router =
            setup_test_router_with_image_storage(cfg, db, MockNotificationsManager::new(), storage).await;

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
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);

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
        let cfg = HttpServerConfig {
            base_url: "https://example.test".to_string(),
            ..HttpServerConfig::default()
        };
        let router =
            setup_test_router_with_image_storage(cfg, db, MockNotificationsManager::new(), storage).await;
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
        let db: DynDB = Arc::new(MockDB::new());
        let notifications_manager: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

        RouterState {
            cfg: HttpServerConfig {
                base_url: "https://example.test".to_string(),
                ..HttpServerConfig::default()
            },
            db,
            image_storage,
            notifications_manager,
            serde_qs_de: serde_qs::Config::new(3, false),
        }
    }
}
