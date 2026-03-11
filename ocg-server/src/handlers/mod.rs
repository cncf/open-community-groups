//! HTTP request handlers for the OCG server.
//!
//! This module organizes all HTTP request handlers by domain. It also includes shared
//! utilities like error handling and request extractors for common functionality.

use std::str::FromStr;

use anyhow::{Result, anyhow};
use axum::http::{HeaderMap, HeaderName, HeaderValue, Uri, header::ORIGIN, header::REFERER};
use chrono::Duration;
use reqwest::header::CACHE_CONTROL;

use crate::config::HttpServerConfig;

/// Authentication handlers.
pub(crate) mod auth;
/// Community site handlers.
pub(crate) mod community;
/// Dashboards handlers.
pub(crate) mod dashboard;
/// Error handling utilities for HTTP handlers.
pub(crate) mod error;
/// Event page handlers.
pub(crate) mod event;
/// Custom extractors for HTTP handlers.
pub(crate) mod extractors;
/// Group site handlers.
pub(crate) mod group;
/// Images handlers.
pub(crate) mod images;
/// Meetings handlers.
pub(crate) mod meetings;
/// Global site handlers.
pub(crate) mod site;
/// Shared tests helpers for handlers modules.
#[cfg(test)]
pub(crate) mod tests;

/// Helper function to prepare headers for HTTP responses, including cache control and
/// additional custom headers.
#[allow(unused_variables)]
pub(crate) fn prepare_headers(cache_duration: Duration, extra_headers: &[(&str, &str)]) -> Result<HeaderMap> {
    let mut headers = HeaderMap::new();

    // Set cache control header
    #[cfg(all(debug_assertions, not(test)))]
    let duration_secs = 0; // Disable caching in debug mode
    #[cfg(any(not(debug_assertions), test))]
    let duration_secs = cache_duration.num_seconds();
    headers.insert(
        CACHE_CONTROL,
        HeaderValue::try_from(format!("max-age={duration_secs}"))?,
    );

    // Set extra headers
    for (key, value) in extra_headers {
        headers.insert(HeaderName::try_from(*key)?, HeaderValue::try_from(*value)?);
    }

    Ok(headers)
}

/// Checks whether the request comes from the configured site hostname.
pub(crate) fn request_matches_site(server_cfg: &HttpServerConfig, headers: &HeaderMap) -> Result<bool> {
    // Check if referer checks are disabled
    if server_cfg.disable_referer_checks {
        return Ok(true);
    }

    // Extract the host from the base URL in the config
    let site_host = Uri::from_str(&server_cfg.base_url)
        .expect("valid base_url in config")
        .host()
        .map(str::to_ascii_lowercase)
        .ok_or_else(|| anyhow!("missing host in base_url"))?;

    // Prefer the origin header when present
    if let Some(origin) = headers.get(ORIGIN) {
        let Ok(origin) = origin.to_str() else {
            return Ok(false);
        };
        let origin_host = Uri::from_str(origin)
            .ok()
            .and_then(|uri| uri.host().map(str::to_ascii_lowercase));

        return Ok(origin_host.is_some_and(|origin_host| origin_host == site_host));
    }

    // Fall back to referer when origin is absent
    let Some(referer) = headers.get(REFERER) else {
        return Ok(false);
    };
    let Ok(referer) = referer.to_str() else {
        return Ok(false);
    };
    let referer_host = Uri::from_str(referer)
        .ok()
        .and_then(|uri| uri.host().map(str::to_ascii_lowercase));

    Ok(referer_host.is_some_and(|referer_host| referer_host == site_host))
}

#[cfg(test)]
mod helpers_tests {
    use axum::http::{HeaderMap, HeaderValue};
    use chrono::Duration;

    use crate::config::HttpServerConfig;

    use super::*;

    #[test]
    fn test_prepare_headers_rejects_invalid_extra_header_name() {
        let result = prepare_headers(Duration::minutes(5), &[("invalid header", "value")]);

        assert!(result.is_err());
    }

    #[test]
    fn test_prepare_headers_sets_cache_control_and_extra_headers() {
        let headers = prepare_headers(
            Duration::minutes(5),
            &[("content-type", "application/json"), ("x-test", "ok")],
        )
        .unwrap();

        assert_eq!(headers.get(super::CACHE_CONTROL).unwrap(), "max-age=300");
        assert_eq!(headers.get("content-type").unwrap(), "application/json");
        assert_eq!(headers.get("x-test").unwrap(), "ok");
    }

    #[test]
    fn test_request_matches_site_accepts_when_referer_checks_disabled() {
        let server_cfg = sample_server_cfg("https://example.test", true);

        assert!(request_matches_site(&server_cfg, &HeaderMap::new()).unwrap());
    }

    #[test]
    fn test_request_matches_site_falls_back_to_referer() {
        let server_cfg = sample_server_cfg("https://example.test", false);
        let mut headers = HeaderMap::new();
        headers.insert(REFERER, HeaderValue::from_static("https://example.test/page"));

        assert!(request_matches_site(&server_cfg, &headers).unwrap());
    }

    #[test]
    fn test_request_matches_site_matches_origin_host_case_insensitively() {
        let server_cfg = sample_server_cfg("https://Example.Test", false);
        let mut headers = HeaderMap::new();
        headers.insert(ORIGIN, HeaderValue::from_static("https://EXAMPLE.TEST"));

        assert!(request_matches_site(&server_cfg, &headers).unwrap());
    }

    #[test]
    fn test_request_matches_site_prefers_origin_over_referer() {
        let server_cfg = sample_server_cfg("https://example.test", false);
        let mut headers = HeaderMap::new();
        headers.insert(ORIGIN, HeaderValue::from_static("https://evil.test"));
        headers.insert(REFERER, HeaderValue::from_static("https://example.test/page"));

        assert!(!request_matches_site(&server_cfg, &headers).unwrap());
    }

    #[test]
    fn test_request_matches_site_rejects_invalid_base_url_without_host() {
        let server_cfg = sample_server_cfg("/relative-path", false);

        assert!(request_matches_site(&server_cfg, &HeaderMap::new()).is_err());
    }

    #[test]
    fn test_request_matches_site_rejects_non_utf8_origin() {
        let server_cfg = sample_server_cfg("https://example.test", false);
        let mut headers = HeaderMap::new();
        headers.insert(ORIGIN, HeaderValue::from_bytes(&[0xFF]).unwrap());

        assert!(!request_matches_site(&server_cfg, &headers).unwrap());
    }

    #[test]
    fn test_request_matches_site_rejects_when_no_origin_or_referer() {
        let server_cfg = sample_server_cfg("https://example.test", false);

        assert!(!request_matches_site(&server_cfg, &HeaderMap::new()).unwrap());
    }

    // Helpers

    fn sample_server_cfg(base_url: &str, disable_referer_checks: bool) -> HttpServerConfig {
        HttpServerConfig {
            base_url: base_url.to_string(),
            disable_referer_checks,
            ..Default::default()
        }
    }
}
