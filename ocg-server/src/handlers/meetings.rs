//! Handlers for meeting-related webhooks (e.g., Zoom).

use axum::{
    Json,
    extract::State,
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
};
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use subtle::ConstantTimeEq;
use tracing::{instrument, trace, warn};

use crate::{
    config::{MeetingsConfig, MeetingsZoomConfig},
    db::DynDB,
    services::meetings::MeetingProvider,
};

/// Zoom webhook event types we handle.
const EVENT_RECORDING_COMPLETED: &str = "recording.completed";
const EVENT_URL_VALIDATION: &str = "endpoint.url_validation";

/// Zoom signature header names.
const HEADER_SIGNATURE: &str = "x-zm-signature";
const HEADER_TIMESTAMP: &str = "x-zm-request-timestamp";

/// Maximum age of webhook timestamp (5 minutes) to prevent replay attacks.
const MAX_TIMESTAMP_AGE_SECS: i64 = 300;

// Handlers.

/// Handles incoming Zoom webhook events.
#[instrument(skip_all)]
pub(crate) async fn zoom_event(
    State(db): State<DynDB>,
    State(meetings_cfg): State<Option<MeetingsConfig>>,
    headers: HeaderMap,
    body: String,
) -> impl IntoResponse {
    // Extract Zoom config (route only registered when zoom is configured)
    let Some(zoom_cfg) = meetings_cfg.as_ref().and_then(|cfg| cfg.zoom.as_ref()) else {
        return StatusCode::NOT_FOUND.into_response();
    };

    // Verify signature
    if !verify_signature(&headers, &body, &zoom_cfg.webhook_secret_token) {
        warn!("zoom webhook signature verification failed");
        return StatusCode::UNAUTHORIZED.into_response();
    }

    // Parse payload
    let payload: ZoomWebhookPayload = match serde_json::from_str(&body) {
        Ok(p) => p,
        Err(err) => {
            warn!(?err, "failed to parse zoom webhook payload");
            return StatusCode::BAD_REQUEST.into_response();
        }
    };

    // Handle based on event type
    match payload.event.as_str() {
        EVENT_RECORDING_COMPLETED => handle_recording_completed(&db, &payload).await,
        EVENT_URL_VALIDATION => handle_url_validation(&payload, zoom_cfg),
        _ => {
            trace!(event = %payload.event, "ignoring unhandled zoom event");
            StatusCode::OK.into_response()
        }
    }
}

/// Handles recording.completed event by updating the recording URL.
async fn handle_recording_completed(db: &DynDB, payload: &ZoomWebhookPayload) -> axum::response::Response {
    // Extract recording details from payload
    let Some(object) = payload.payload.as_ref().and_then(|p| p.object.as_ref()) else {
        warn!("recording.completed missing object");
        return StatusCode::BAD_REQUEST.into_response();
    };
    let Some(ref recording_url) = object.share_url else {
        trace!("recording.completed has no share_url, skipping");
        return StatusCode::OK.into_response();
    };
    let provider_meeting_id = object.id.to_string();

    // Update recording URL in database
    if let Err(err) = db
        .update_meeting_recording_url(MeetingProvider::Zoom, &provider_meeting_id, recording_url)
        .await
    {
        warn!(?err, "failed to update meeting recording url");
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }

    trace!(provider_meeting_id, "updated recording url");
    StatusCode::OK.into_response()
}

/// Handles Zoom's URL validation challenge-response.
fn handle_url_validation(
    payload: &ZoomWebhookPayload,
    zoom_cfg: &MeetingsZoomConfig,
) -> axum::response::Response {
    // Extract plain token from payload
    let Some(plain_token) = payload.payload.as_ref().and_then(|p| p.plain_token.as_ref()) else {
        warn!("url validation missing plain_token");
        return StatusCode::BAD_REQUEST.into_response();
    };

    // Hash the token with the secret
    let encrypted_token = compute_hmac(plain_token, &zoom_cfg.webhook_secret_token);

    // Prepare response
    let response = UrlValidationResponse {
        plain_token: plain_token.clone(),
        encrypted_token,
    };

    (StatusCode::OK, Json(response)).into_response()
}

// Helpers.

/// Computes HMAC-SHA256 and returns hex-encoded result.
fn compute_hmac(message: &str, secret: &str) -> String {
    type HmacSha256 = Hmac<Sha256>;

    let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).expect("HMAC can take key of any size");
    mac.update(message.as_bytes());
    hex::encode(mac.finalize().into_bytes())
}

/// Verifies the Zoom webhook signature using HMAC-SHA256.
fn verify_signature(headers: &HeaderMap, body: &str, secret: &str) -> bool {
    // Extract required headers
    let Some(signature) = headers.get(HEADER_SIGNATURE).and_then(|v| v.to_str().ok()) else {
        return false;
    };
    let Some(timestamp) = headers.get(HEADER_TIMESTAMP).and_then(|v| v.to_str().ok()) else {
        return false;
    };

    // Validate timestamp is not too old (replay protection)
    if let Ok(ts) = timestamp.parse::<i64>() {
        let now = chrono::Utc::now().timestamp();
        if (now - ts).abs() > MAX_TIMESTAMP_AGE_SECS {
            return false;
        }
    } else {
        return false;
    }

    // Compute expected signature: v0:timestamp:body
    let message = format!("v0:{timestamp}:{body}");
    let expected = format!("v0={}", compute_hmac(&message, secret));

    // Constant-time comparison
    signature.as_bytes().ct_eq(expected.as_bytes()).into()
}

// Types.

/// Webhook request payload from Zoom.
#[derive(Debug, Deserialize)]
pub(crate) struct ZoomWebhookPayload {
    /// Event type.
    pub event: String,

    /// Event payload data.
    #[serde(default)]
    pub payload: Option<WebhookEventPayload>,
}

/// Payload for webhook events.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct WebhookEventPayload {
    /// Plain token for URL validation.
    #[serde(default)]
    pub plain_token: Option<String>,

    /// Recording object for recording events.
    #[serde(default)]
    pub object: Option<RecordingObject>,
}

/// Recording object from recording.completed event.
#[derive(Debug, Deserialize)]
pub(crate) struct RecordingObject {
    /// Zoom meeting ID (numeric).
    pub id: i64,

    /// Share URL for the recording.
    #[serde(default)]
    pub share_url: Option<String>,
}

/// Response for URL validation challenge.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct UrlValidationResponse {
    /// Plain token echoed back.
    pub plain_token: String,

    /// HMAC-SHA256 encrypted token.
    pub encrypted_token: String,
}

// Tests.

#[cfg(test)]
mod tests {
    use anyhow::anyhow;
    use axum::{
        body::{Body, to_bytes},
        http::{Request, StatusCode, header::CONTENT_TYPE},
    };
    use serde_json::{Value, json};
    use tower::ServiceExt;

    use crate::{
        config::{MeetingsConfig, MeetingsZoomConfig},
        db::mock::MockDB,
        handlers::tests::TestRouterBuilder,
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
            .with_meetings_cfg(zoom_meetings_cfg(secret))
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
            .with_meetings_cfg(zoom_meetings_cfg(secret))
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
        let db = MockDB::new();

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
        assert!(bytes.is_empty());
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
            .with_meetings_cfg(zoom_meetings_cfg("zoom-secret"))
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
            .with_meetings_cfg(zoom_meetings_cfg(secret))
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
            .with_meetings_cfg(zoom_meetings_cfg(secret))
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

    fn zoom_meetings_cfg(secret: &str) -> MeetingsConfig {
        MeetingsConfig {
            zoom: Some(MeetingsZoomConfig {
                account_id: "account-id".to_string(),
                client_id: "client-id".to_string(),
                client_secret: "client-secret".to_string(),
                enabled: true,
                host_pool_users: vec!["host@example.com".to_string()],
                max_participants: 100,
                max_simultaneous_meetings_per_host: 1,
                webhook_secret_token: secret.to_string(),
            }),
        }
    }
}
