use anyhow::anyhow;
use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderValue, Request, StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE},
    },
};
use serde_json::{Value, json};
use tower::ServiceExt;

use crate::{
    db::mock::MockDB,
    handlers::tests::{TestRouterBuilder, sample_site_settings, sample_zoom_meetings_cfg},
    services::notifications::MockNotificationsManager,
};

use super::*;

#[test]
fn test_compute_hmac() {
    // Test vector for HMAC-SHA256
    let result = compute_hmac("test message", "secret key");
    assert!(!result.is_empty());
    assert_eq!(result.len(), 64); // SHA256 produces 32 bytes = 64 hex chars
}

#[test]
fn test_verify_signature_missing_headers() {
    let headers = HeaderMap::new();
    assert!(!verify_signature(&headers, "body", "secret"));
}

#[test]
fn test_verify_signature_missing_signature_header() {
    let mut headers = HeaderMap::new();
    headers.insert(HEADER_TIMESTAMP, "1234567890".parse().unwrap());
    assert!(!verify_signature(&headers, "body", "secret"));
}

#[test]
fn test_verify_signature_missing_timestamp_header() {
    let mut headers = HeaderMap::new();
    headers.insert(HEADER_SIGNATURE, "v0=abc123".parse().unwrap());
    assert!(!verify_signature(&headers, "body", "secret"));
}

#[test]
fn test_verify_signature_invalid_timestamp() {
    let mut headers = HeaderMap::new();
    headers.insert(HEADER_SIGNATURE, "v0=abc123".parse().unwrap());
    headers.insert(HEADER_TIMESTAMP, "not-a-number".parse().unwrap());
    assert!(!verify_signature(&headers, "body", "secret"));
}

#[test]
fn test_verify_signature_expired_timestamp() {
    let mut headers = HeaderMap::new();
    headers.insert(HEADER_SIGNATURE, "v0=abc123".parse().unwrap());
    // Use a timestamp from 10 minutes ago
    let old_timestamp = (chrono::Utc::now().timestamp() - 600).to_string();
    headers.insert(HEADER_TIMESTAMP, old_timestamp.parse().unwrap());
    assert!(!verify_signature(&headers, "body", "secret"));
}

#[test]
fn test_verify_signature_valid() {
    let secret = "test_secret";
    let body = r#"{"event":"test"}"#;
    let timestamp = chrono::Utc::now().timestamp().to_string();

    // Compute the expected signature
    let message = format!("v0:{timestamp}:{body}");
    let expected_hash = compute_hmac(&message, secret);
    let signature = format!("v0={expected_hash}");

    let mut headers = HeaderMap::new();
    headers.insert(HEADER_SIGNATURE, signature.parse().unwrap());
    headers.insert(HEADER_TIMESTAMP, timestamp.parse().unwrap());

    assert!(verify_signature(&headers, body, secret));
}

#[test]
fn test_verify_signature_wrong_signature() {
    let secret = "test_secret";
    let body = r#"{"event":"test"}"#;
    let timestamp = chrono::Utc::now().timestamp().to_string();

    let mut headers = HeaderMap::new();
    headers.insert(HEADER_SIGNATURE, "v0=wrong_signature".parse().unwrap());
    headers.insert(HEADER_TIMESTAMP, timestamp.parse().unwrap());

    assert!(!verify_signature(&headers, body, secret));
}

#[tokio::test]
async fn test_zoom_event_returns_bad_request_for_invalid_payload() {
    // Setup request body and signature
    let body = "{invalid-json";
    let secret = "zoom-secret";
    let request = signed_zoom_webhook_request(body, secret);

    // Setup database mock
    let db = MockDB::new();

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router
    let router = TestRouterBuilder::new(db, nm)
        .with_meetings_cfg(sample_zoom_meetings_cfg(secret))
        .build()
        .await;

    // Execute request
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_zoom_event_returns_internal_server_error_when_recording_update_fails() {
    // Setup request body and signature
    let body = json!({
        "event": EVENT_RECORDING_COMPLETED,
        "payload": {
            "object": {
                "id": 12345,
                "share_url": "https://zoom.example/recording",
            }
        }
    })
    .to_string();
    let secret = "zoom-secret";
    let request = signed_zoom_webhook_request(&body, secret);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_update_meeting_recording_url()
        .times(1)
        .withf(|provider, provider_meeting_id, recording_url| {
            *provider == MeetingProvider::Zoom
                && provider_meeting_id == "12345"
                && recording_url == "https://zoom.example/recording"
        })
        .returning(|_, _, _| Err(anyhow!("db error")));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router
    let router = TestRouterBuilder::new(db, nm)
        .with_meetings_cfg(sample_zoom_meetings_cfg(secret))
        .build()
        .await;

    // Execute request
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_zoom_event_returns_not_found_when_zoom_is_disabled() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router
    let router = TestRouterBuilder::new(db, nm).build().await;

    // Setup request
    let request = Request::builder()
        .method("POST")
        .uri("/webhooks/zoom")
        .header(CONTENT_TYPE, "application/json")
        .body(Body::from("{}"))
        .unwrap();

    // Execute request
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
        &HeaderValue::from_static("max-age=900")
    );
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("We could not find that page"));
}

#[tokio::test]
async fn test_zoom_event_returns_unauthorized_for_invalid_signature() {
    // Setup request body and signature
    let body = json!({
        "event": EVENT_URL_VALIDATION,
        "payload": {
            "plainToken": "challenge-token",
        }
    })
    .to_string();
    let request = signed_zoom_webhook_request(&body, "wrong-secret");

    // Setup database mock
    let db = MockDB::new();

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router
    let router = TestRouterBuilder::new(db, nm)
        .with_meetings_cfg(sample_zoom_meetings_cfg("zoom-secret"))
        .build()
        .await;

    // Execute request
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNAUTHORIZED);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_zoom_event_updates_recording_url() {
    // Setup request body and signature
    let body = json!({
        "event": EVENT_RECORDING_COMPLETED,
        "payload": {
            "object": {
                "id": 12345,
                "share_url": "https://zoom.example/recording",
            }
        }
    })
    .to_string();
    let secret = "zoom-secret";
    let request = signed_zoom_webhook_request(&body, secret);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_update_meeting_recording_url()
        .times(1)
        .withf(|provider, provider_meeting_id, recording_url| {
            *provider == MeetingProvider::Zoom
                && provider_meeting_id == "12345"
                && recording_url == "https://zoom.example/recording"
        })
        .returning(|_, _, _| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router
    let router = TestRouterBuilder::new(db, nm)
        .with_meetings_cfg(sample_zoom_meetings_cfg(secret))
        .build()
        .await;

    // Execute request
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_zoom_event_validates_url() {
    // Setup request body and signature
    let plain_token = "challenge-token";
    let body = json!({
        "event": EVENT_URL_VALIDATION,
        "payload": {
            "plainToken": plain_token,
        }
    })
    .to_string();
    let secret = "zoom-secret";
    let request = signed_zoom_webhook_request(&body, secret);

    // Setup database mock
    let db = MockDB::new();

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router
    let router = TestRouterBuilder::new(db, nm)
        .with_meetings_cfg(sample_zoom_meetings_cfg(secret))
        .build()
        .await;

    // Execute request
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    let response_json = serde_json::from_slice::<Value>(&bytes).unwrap();
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(response_json["plainToken"], plain_token);
    assert_eq!(response_json["encryptedToken"], compute_hmac(plain_token, secret));
}

// Helpers

fn signed_zoom_webhook_request(body: &str, secret: &str) -> Request<Body> {
    let timestamp = chrono::Utc::now().timestamp().to_string();
    let message = format!("v0:{timestamp}:{body}");
    let signature = format!("v0={}", compute_hmac(&message, secret));

    Request::builder()
        .method("POST")
        .uri("/webhooks/zoom")
        .header(CONTENT_TYPE, "application/json")
        .header(HEADER_SIGNATURE, signature)
        .header(HEADER_TIMESTAMP, timestamp)
        .body(Body::from(body.to_string()))
        .unwrap()
}
