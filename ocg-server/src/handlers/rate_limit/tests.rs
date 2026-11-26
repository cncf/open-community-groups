use std::time::Duration;

use axum::{
    body::to_bytes,
    http::{
        HeaderMap, HeaderValue, StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE, RETRY_AFTER, SET_COOKIE, VARY},
    },
};

use super::*;

/// Account rejection message for a wait of 90 seconds.
const ACCOUNT_TWO_MINUTES_MESSAGE: &str =
    "Too many requests from your account. Please wait 2 minutes and try again.";

/// Accept header a browser sends on a document navigation.
const BROWSER_ACCEPT: &str = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8";

/// Rejection message for a wait of 90 seconds.
const TWO_MINUTES_MESSAGE: &str =
    "Too many requests from your network. Please wait 2 minutes and try again.";

#[test]
fn test_is_document_navigation_matches_browser_navigations_only() {
    // Setup labeled request headers with the expected classification
    type Case = (&'static str, &'static [(&'static str, &'static str)], bool);
    let cases: [Case; 11] = [
        ("no headers", &[], false),
        ("any type", &[("accept", "*/*")], false),
        ("json", &[("accept", "application/json")], false),
        ("browser accept", &[("accept", BROWSER_ACCEPT)], true),
        ("uppercase html", &[("accept", "TEXT/HTML")], true),
        ("zero quality html", &[("accept", "text/html;q=0")], false),
        (
            "htmx request",
            &[("accept", "text/html"), ("hx-request", "true")],
            false,
        ),
        (
            "htmx header set to false",
            &[("accept", "text/html"), ("hx-request", "false")],
            true,
        ),
        (
            "fetch request",
            &[("accept", "text/html"), ("x-ocg-fetch", "true")],
            false,
        ),
        (
            "cors fetch mode",
            &[("accept", "text/html"), ("sec-fetch-mode", "cors")],
            false,
        ),
        (
            "navigate fetch mode",
            &[("accept", "text/html"), ("sec-fetch-mode", "navigate")],
            true,
        ),
    ];

    // Check each request is classified as expected
    for (case, request_headers, expected) in cases {
        assert_eq!(
            is_document_navigation(&headers_from(request_headers)),
            expected,
            "{case}"
        );
    }
}

#[tokio::test]
async fn test_too_many_requests_for_user_returns_html_page_to_document_navigations() {
    // Build the response to a browser navigation
    let headers = headers_from(&[("accept", BROWSER_ACCEPT), ("sec-fetch-mode", "navigate")]);
    let response = too_many_requests_for_user(&headers, Duration::from_secs(90));

    // Check the status, headers, and account-scoped message
    assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);
    assert_eq!(response.headers().get(RETRY_AFTER).unwrap(), "90");
    assert_eq!(
        response.headers().get(CACHE_CONTROL).unwrap(),
        CACHE_CONTROL_NO_STORE
    );
    assert_eq!(
        response.headers().get(CONTENT_TYPE).unwrap(),
        "text/html; charset=utf-8"
    );
    assert_eq!(response.headers().get(VARY).unwrap(), REJECTION_VARY);
    assert!(response.headers().get(RATE_LIMITED_HEADER).is_none());
    assert!(response.headers().get(SET_COOKIE).is_none());
    let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    let body = String::from_utf8(body.to_vec()).unwrap();
    assert!(body.contains(ACCOUNT_TWO_MINUTES_MESSAGE));
}

#[tokio::test]
async fn test_too_many_requests_for_user_returns_plain_text_429() {
    // Build the response
    let response = too_many_requests_for_user(&HeaderMap::new(), Duration::from_secs(90));

    // Check the status, headers, and account-scoped body
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
    assert_eq!(response.headers().get(RATE_LIMITED_HEADER).unwrap(), "true");
    assert_eq!(response.headers().get(VARY).unwrap(), REJECTION_VARY);
    let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    assert_eq!(body, ACCOUNT_TWO_MINUTES_MESSAGE);
}

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
        let response = too_many_requests(&HeaderMap::new(), retry_after);
        assert_eq!(
            response.headers().get(RETRY_AFTER).unwrap(),
            expected,
            "{case}"
        );
    }
}

#[tokio::test]
async fn test_too_many_requests_returns_html_page_to_document_navigations() {
    // Build the response to a browser navigation
    let headers = headers_from(&[("accept", BROWSER_ACCEPT), ("sec-fetch-mode", "navigate")]);
    let response = too_many_requests(&headers, Duration::from_secs(90));

    // Check the status and headers
    assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);
    assert_eq!(response.headers().get(RETRY_AFTER).unwrap(), "90");
    assert_eq!(
        response.headers().get(CACHE_CONTROL).unwrap(),
        CACHE_CONTROL_NO_STORE
    );
    assert_eq!(
        response.headers().get(CONTENT_TYPE).unwrap(),
        "text/html; charset=utf-8"
    );
    assert_eq!(response.headers().get(VARY).unwrap(), REJECTION_VARY);
    assert!(response.headers().get(RATE_LIMITED_HEADER).is_none());
    assert!(response.headers().get(SET_COOKIE).is_none());

    // Check the page carries the message
    let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    let body = String::from_utf8(body.to_vec()).unwrap();
    assert!(body.contains(TWO_MINUTES_MESSAGE));
}

#[tokio::test]
async fn test_too_many_requests_returns_plain_text_429() {
    // Build the response
    let response = too_many_requests(&HeaderMap::new(), Duration::from_secs(90));

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
    assert_eq!(response.headers().get(RATE_LIMITED_HEADER).unwrap(), "true");
    assert_eq!(response.headers().get(VARY).unwrap(), REJECTION_VARY);
    let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    assert_eq!(body, TWO_MINUTES_MESSAGE);
}

#[tokio::test]
async fn test_too_many_requests_returns_plain_text_to_htmx_and_fetch_callers() {
    // Setup labeled request headers of callers that are not document navigations
    let cases: [(&str, &[(&str, &str)]); 3] = [
        (
            "htmx request",
            &[("accept", "text/html"), ("hx-request", "true")],
        ),
        (
            "fetch request",
            &[("accept", "*/*"), ("x-ocg-fetch", "true")],
        ),
        ("json request", &[("accept", "application/json")]),
    ];

    for (case, request_headers) in cases {
        // Build the response to the caller
        let response = too_many_requests(&headers_from(request_headers), Duration::from_secs(90));

        // Check the marked plain-text rejection
        assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS, "{case}");
        assert_eq!(
            response.headers().get(CONTENT_TYPE).unwrap(),
            "text/plain; charset=utf-8",
            "{case}"
        );
        assert_eq!(
            response.headers().get(RATE_LIMITED_HEADER).unwrap(),
            "true",
            "{case}"
        );
        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        assert_eq!(body, TWO_MINUTES_MESSAGE, "{case}");
    }
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
        let response = too_many_requests(&HeaderMap::new(), retry_after);
        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        assert_eq!(
            body,
            format!("Too many requests from your network. Please wait {wait} and try again."),
            "{case}"
        );
    }
}

// Helpers.

/// Builds a request header map from name and value pairs.
fn headers_from(pairs: &[(&str, &str)]) -> HeaderMap {
    let mut headers = HeaderMap::new();
    for &(name, value) in pairs {
        headers.insert(
            HeaderName::from_bytes(name.as_bytes()).unwrap(),
            HeaderValue::from_str(value).unwrap(),
        );
    }
    headers
}
