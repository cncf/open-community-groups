use anyhow::anyhow;
use axum::{
    body::Body,
    http::{Request, StatusCode, header::CONTENT_TYPE},
};
use serde_json::{Value, json};

use crate::{
    db::mock::{MockDB, expect_site_settings},
    handlers::tests::{
        TestRouterBuilder, assert_empty_response, assert_html_response, request,
        sample_zoom_meetings_cfg, send,
    },
};

use super::*;

/// Webhook secret token configured in the handler tests.
const ZOOM_SECRET: &str = "zoom-secret";

#[test]
fn test_compute_hmac() {
    // RFC 4231 test case 2 for HMAC-SHA256
    let result = compute_hmac("what do ya want for nothing?", "Jefe");
    assert_eq!(
        result,
        "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
    );
}

#[test]
fn test_verify_signature() {
    // Setup signatures over the current, invalid, expired and future timestamps
    let body = r#"{"event":"test"}"#;
    let secret = "test_secret";
    let sign = |timestamp: &str| {
        format!(
            "v0={}",
            compute_hmac(&format!("v0:{timestamp}:{body}"), secret)
        )
    };
    let now = chrono::Utc::now().timestamp();
    let current = now.to_string();
    let expired = (now - 600).to_string();
    let future = (now + 600).to_string();
    let cases = [
        (
            "valid signature",
            Some(sign(&current)),
            Some(current.clone()),
            true,
        ),
        ("missing headers", None, None, false),
        (
            "missing signature header",
            None,
            Some(current.clone()),
            false,
        ),
        (
            "missing timestamp header",
            Some(sign(&current)),
            None,
            false,
        ),
        (
            "invalid timestamp",
            Some(sign("not-a-number")),
            Some("not-a-number".to_string()),
            false,
        ),
        (
            "expired timestamp",
            Some(sign(&expired)),
            Some(expired.clone()),
            false,
        ),
        (
            "future timestamp",
            Some(sign(&future)),
            Some(future.clone()),
            false,
        ),
        (
            "wrong signature",
            Some("v0=wrong_signature".to_string()),
            Some(current.clone()),
            false,
        ),
    ];

    // Check each case is accepted or rejected as expected
    for (case, signature, timestamp, expected) in cases {
        let mut headers = HeaderMap::new();
        if let Some(signature) = signature {
            headers.insert(HEADER_SIGNATURE, signature.parse().unwrap());
        }
        if let Some(timestamp) = timestamp {
            headers.insert(HEADER_TIMESTAMP, timestamp.parse().unwrap());
        }
        assert_eq!(verify_signature(&headers, body, secret), expected, "{case}");
    }
}

#[tokio::test]
async fn test_zoom_event_appends_recording_url() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_append_meeting_recording_url()
        .times(1)
        .withf(|provider, provider_meeting_id, recording_url| {
            *provider == MeetingProvider::Zoom
                && provider_meeting_id == "12345"
                && recording_url == "https://zoom.example/recording"
        })
        .returning(|_, _, _| Ok(()));

    // Send the signed webhook
    let body = recording_completed_body(Some("https://zoom.example/recording"));
    let router = TestRouterBuilder::new(db)
        .with_meetings_cfg(sample_zoom_meetings_cfg(ZOOM_SECRET))
        .build()
        .await;
    let request = signed_zoom_webhook_request(&body, ZOOM_SECRET);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_zoom_event_ignores_unhandled_event() {
    // Send a signed webhook of an event type without a handler
    let body = json!({ "event": "meeting.started" }).to_string();
    let router = TestRouterBuilder::new(MockDB::new())
        .with_meetings_cfg(sample_zoom_meetings_cfg(ZOOM_SECRET))
        .build()
        .await;
    let request = signed_zoom_webhook_request(&body, ZOOM_SECRET);
    let (parts, bytes) = send(router, request).await;

    // Check the event is acknowledged without database writes
    assert_empty_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_zoom_event_returns_bad_request_for_invalid_payload() {
    // Send a signed webhook with a malformed body
    let router = TestRouterBuilder::new(MockDB::new())
        .with_meetings_cfg(sample_zoom_meetings_cfg(ZOOM_SECRET))
        .build()
        .await;
    let request = signed_zoom_webhook_request("{invalid-json", ZOOM_SECRET);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn test_zoom_event_returns_bad_request_when_plain_token_is_missing() {
    // Send a signed URL validation without the challenge token
    let body = json!({ "event": EVENT_URL_VALIDATION, "payload": {} }).to_string();
    let router = TestRouterBuilder::new(MockDB::new())
        .with_meetings_cfg(sample_zoom_meetings_cfg(ZOOM_SECRET))
        .build()
        .await;
    let request = signed_zoom_webhook_request(&body, ZOOM_SECRET);
    let (parts, bytes) = send(router, request).await;

    // Check the challenge is rejected
    assert_empty_response(&parts, &bytes, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn test_zoom_event_returns_bad_request_when_recording_object_is_missing() {
    // Send a signed recording event without the recording object
    let body = json!({ "event": EVENT_RECORDING_COMPLETED, "payload": {} }).to_string();
    let router = TestRouterBuilder::new(MockDB::new())
        .with_meetings_cfg(sample_zoom_meetings_cfg(ZOOM_SECRET))
        .build()
        .await;
    let request = signed_zoom_webhook_request(&body, ZOOM_SECRET);
    let (parts, bytes) = send(router, request).await;

    // Check the event is rejected without database writes
    assert_empty_response(&parts, &bytes, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn test_zoom_event_returns_internal_server_error_when_recording_append_fails() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_append_meeting_recording_url()
        .times(1)
        .withf(|provider, provider_meeting_id, recording_url| {
            *provider == MeetingProvider::Zoom
                && provider_meeting_id == "12345"
                && recording_url == "https://zoom.example/recording"
        })
        .returning(|_, _, _| Err(anyhow!("db error")));

    // Send the signed webhook
    let body = recording_completed_body(Some("https://zoom.example/recording"));
    let router = TestRouterBuilder::new(db)
        .with_meetings_cfg(sample_zoom_meetings_cfg(ZOOM_SECRET))
        .build()
        .await;
    let request = signed_zoom_webhook_request(&body, ZOOM_SECRET);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_zoom_event_returns_not_found_when_zoom_is_disabled() {
    // Setup database mock
    let mut db = MockDB::new();
    expect_site_settings(&mut db);

    // Setup router without meetings configuration and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = request("POST", "/webhooks/zoom")
        .header(CONTENT_TYPE, "application/json")
        .body(Body::from("{}"))
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::NOT_FOUND);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("We could not find that page"));
}

#[tokio::test]
async fn test_zoom_event_returns_unauthorized_for_invalid_signature() {
    // Send a webhook signed with a secret other than the configured one
    let body = json!({
        "event": EVENT_URL_VALIDATION,
        "payload": {
            "plainToken": "challenge-token",
        }
    })
    .to_string();
    let router = TestRouterBuilder::new(MockDB::new())
        .with_meetings_cfg(sample_zoom_meetings_cfg(ZOOM_SECRET))
        .build()
        .await;
    let request = signed_zoom_webhook_request(&body, "wrong-secret");
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn test_zoom_event_skips_recording_without_share_url() {
    // Send a signed recording event without a share URL
    let body = recording_completed_body(None);
    let router = TestRouterBuilder::new(MockDB::new())
        .with_meetings_cfg(sample_zoom_meetings_cfg(ZOOM_SECRET))
        .build()
        .await;
    let request = signed_zoom_webhook_request(&body, ZOOM_SECRET);
    let (parts, bytes) = send(router, request).await;

    // Check the event is acknowledged without database writes
    assert_empty_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_zoom_event_validates_url() {
    // Send a signed URL validation challenge
    let plain_token = "challenge-token";
    let body = json!({
        "event": EVENT_URL_VALIDATION,
        "payload": {
            "plainToken": plain_token,
        }
    })
    .to_string();
    let router = TestRouterBuilder::new(MockDB::new())
        .with_meetings_cfg(sample_zoom_meetings_cfg(ZOOM_SECRET))
        .build()
        .await;
    let request = signed_zoom_webhook_request(&body, ZOOM_SECRET);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    let response_json = serde_json::from_slice::<Value>(&bytes).unwrap();
    assert_eq!(response_json["plainToken"], plain_token);
    assert_eq!(
        response_json["encryptedToken"],
        compute_hmac(plain_token, ZOOM_SECRET)
    );
}

// Helpers.

/// Builds a recording.completed payload for meeting 12345.
fn recording_completed_body(share_url: Option<&str>) -> String {
    json!({
        "event": EVENT_RECORDING_COMPLETED,
        "payload": {
            "object": {
                "id": 12345,
                "share_url": share_url,
            }
        }
    })
    .to_string()
}

/// Builds a Zoom webhook request signed with `secret` at the current time.
fn signed_zoom_webhook_request(body: &str, secret: &str) -> Request<Body> {
    let timestamp = chrono::Utc::now().timestamp().to_string();
    let message = format!("v0:{timestamp}:{body}");
    let signature = format!("v0={}", compute_hmac(&message, secret));

    request("POST", "/webhooks/zoom")
        .header(CONTENT_TYPE, "application/json")
        .header(HEADER_SIGNATURE, signature)
        .header(HEADER_TIMESTAMP, timestamp)
        .body(Body::from(body.to_string()))
        .unwrap()
}
