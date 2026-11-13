use std::time::Duration;

use axum::{
    body::to_bytes,
    http::{
        StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE, RETRY_AFTER},
    },
};

use super::*;

#[test]
fn test_too_many_requests_retry_after_rounds_up_and_clamps() {
    // Setup labeled waits with the expected header value
    let cases = [
        ("zero", Duration::ZERO, "1"),
        ("below one second", Duration::from_millis(1), "1"),
        ("whole seconds", Duration::from_secs(30), "30"),
        ("fraction rounded up", Duration::from_millis(30_001), "31"),
        ("maximum", Duration::from_hours(24), "86400"),
        ("above maximum", Duration::from_secs(86_401), "86400"),
        ("saturating", Duration::MAX, "86400"),
    ];

    // Check each wait is sent in whole seconds within the bounds
    for (case, retry_after, expected) in cases {
        let response = too_many_requests(retry_after);
        assert_eq!(
            response.headers().get(RETRY_AFTER).unwrap(),
            expected,
            "{case}"
        );
    }
}

#[tokio::test]
async fn test_too_many_requests_returns_plain_text_429() {
    // Build the response
    let response = too_many_requests(Duration::from_secs(90));

    // Check the status, headers and body
    assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);
    assert_eq!(response.headers().get(RETRY_AFTER).unwrap(), "90");
    assert_eq!(
        response.headers().get(CACHE_CONTROL).unwrap(),
        CACHE_CONTROL_NO_STORE
    );
    assert_eq!(
        response.headers().get(CONTENT_TYPE).unwrap(),
        "text/plain; charset=utf-8"
    );
    let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    assert_eq!(
        body,
        "Too many requests from your network. Please wait 2 minutes and try again."
    );
}

#[tokio::test]
async fn test_too_many_requests_wording_rounds_minutes_up() {
    // Setup labeled waits with the expected wording
    let cases = [
        ("one second", Duration::from_secs(1), "1 minute"),
        ("one minute", Duration::from_secs(60), "1 minute"),
        (
            "just over one minute",
            Duration::from_millis(60_001),
            "2 minutes",
        ),
        ("several minutes", Duration::from_secs(300), "5 minutes"),
        ("clamped day", Duration::from_secs(100_000), "1440 minutes"),
    ];

    // Check each wait renders the rounded minutes with the right plural
    for (case, retry_after, wait) in cases {
        let response = too_many_requests(retry_after);
        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        assert_eq!(
            body,
            format!("Too many requests from your network. Please wait {wait} and try again."),
            "{case}"
        );
    }
}
