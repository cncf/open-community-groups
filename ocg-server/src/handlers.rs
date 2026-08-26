//! HTTP request handlers for the OCG server.
//!
//! This module organizes all HTTP request handlers by domain. It also includes shared
//! utilities like error handling and request extractors for common functionality.

use anyhow::{Context, Result};
use axum::http::{
    HeaderMap, HeaderName, HeaderValue,
    header::{ORIGIN, REFERER},
};
use reqwest::Url;

use crate::{config::HttpServerConfig, router::PUBLIC_SHARED_CACHE_HEADERS};

/// Authentication handlers.
pub(crate) mod auth;
/// Public Open Badges credential handlers.
pub(crate) mod badges;
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
/// Payments handlers.
pub(crate) mod payments;
/// Global site handlers.
pub(crate) mod site;
/// Shared tests helpers for handlers modules.
#[cfg(test)]
pub(crate) mod tests;

/// Maximum number of gallery images rendered on public pages.
pub(crate) const MAX_PUBLIC_GALLERY_IMAGES: usize = 50;

/// Extends public shared-cache headers with additional dynamic headers.
pub(crate) fn extend_public_shared_cache_headers(
    extra_headers: &[(&str, &str)],
) -> Result<HeaderMap> {
    let mut headers = HeaderMap::new();

    // Add shared public cache headers first
    for (key, value) in PUBLIC_SHARED_CACHE_HEADERS {
        headers.insert(key, HeaderValue::from_static(value));
    }

    // Add dynamic headers that may be computed per request
    for (key, value) in extra_headers {
        headers.insert(HeaderName::try_from(*key)?, HeaderValue::try_from(*value)?);
    }

    Ok(headers)
}

/// Checks whether the Origin or Referer header matches the configured site origin.
pub(crate) fn request_headers_match_site_origin(
    server_cfg: &HttpServerConfig,
    headers: &HeaderMap,
) -> Result<bool> {
    // Resolve the configured site origin
    let site_url = Url::parse(&server_cfg.base_url).context("invalid base_url")?;
    if site_url.host_str().is_none() {
        anyhow::bail!("missing host in base_url");
    }
    let site_origin = site_url.origin();

    // Prefer the Origin header when present
    if let Some(origin) = headers.get(ORIGIN) {
        let matches = origin
            .to_str()
            .ok()
            .and_then(|origin| Url::parse(origin).ok())
            .is_some_and(|origin| origin.origin() == site_origin);
        return Ok(matches);
    }

    // Fall back to Referer when Origin is absent
    let Some(referer) = headers.get(REFERER) else {
        return Ok(false);
    };
    let matches = referer
        .to_str()
        .ok()
        .and_then(|referer| Url::parse(referer).ok())
        .is_some_and(|referer| referer.origin() == site_origin);

    Ok(matches)
}

/// Truncates gallery image URLs to the public display limit while preserving order.
pub(crate) fn trim_public_gallery_images(photos_urls: &mut Option<Vec<String>>) {
    if let Some(photos_urls) = photos_urls {
        photos_urls.truncate(MAX_PUBLIC_GALLERY_IMAGES);
    }
}

#[cfg(test)]
mod helpers_tests {
    use axum::http::{
        HeaderMap, HeaderValue,
        header::{CACHE_CONTROL, VARY},
    };

    use crate::{
        config::HttpServerConfig,
        router::{CACHE_CONTROL_PUBLIC_SHARED, PUBLIC_SHARED_CACHE_VARY},
    };

    use super::*;

    #[test]
    fn test_extend_public_shared_cache_headers_rejects_invalid_extra_header_name() {
        let result = extend_public_shared_cache_headers(&[("invalid header", "value")]);

        assert!(result.is_err());
    }

    #[test]
    fn test_extend_public_shared_cache_headers_rejects_invalid_extra_header_value() {
        let result = extend_public_shared_cache_headers(&[("x-test", "invalid\nvalue")]);

        assert!(result.is_err());
    }

    #[test]
    fn test_extend_public_shared_cache_headers_sets_cache_and_extra_headers() {
        let headers = extend_public_shared_cache_headers(&[("HX-Push-Url", "/explore")]).unwrap();

        assert_eq!(
            headers.get(CACHE_CONTROL).unwrap(),
            CACHE_CONTROL_PUBLIC_SHARED
        );
        assert_eq!(headers.get(VARY).unwrap(), PUBLIC_SHARED_CACHE_VARY);
        assert_eq!(headers.get("HX-Push-Url").unwrap(), "/explore");
    }

    #[test]
    fn test_request_headers_match_site_origin_accepts_normalized_default_port() {
        let server_cfg = sample_server_cfg("https://example.test");
        let mut headers = HeaderMap::new();
        headers.insert(
            REFERER,
            HeaderValue::from_static("https://example.test:443/page"),
        );

        assert!(request_headers_match_site_origin(&server_cfg, &headers).unwrap());
    }

    #[test]
    fn test_request_headers_match_site_origin_falls_back_to_referer() {
        let server_cfg = sample_server_cfg("https://example.test");
        let mut headers = HeaderMap::new();
        headers.insert(
            REFERER,
            HeaderValue::from_static("https://example.test/page"),
        );

        assert!(request_headers_match_site_origin(&server_cfg, &headers).unwrap());
    }

    #[test]
    fn test_request_headers_match_site_origin_matches_host_case_insensitively() {
        let server_cfg = sample_server_cfg("https://Example.Test");
        let mut headers = HeaderMap::new();
        headers.insert(ORIGIN, HeaderValue::from_static("https://EXAMPLE.TEST"));

        assert!(request_headers_match_site_origin(&server_cfg, &headers).unwrap());
    }

    #[test]
    fn test_request_headers_match_site_origin_prefers_origin_over_referer() {
        let server_cfg = sample_server_cfg("https://example.test");
        let mut headers = HeaderMap::new();
        headers.insert(ORIGIN, HeaderValue::from_static("https://evil.test"));
        headers.insert(
            REFERER,
            HeaderValue::from_static("https://example.test/page"),
        );

        assert!(!request_headers_match_site_origin(&server_cfg, &headers).unwrap());
    }

    #[test]
    fn test_request_headers_match_site_origin_rejects_mismatched_port() {
        let server_cfg = sample_server_cfg("https://example.test:8443");
        let mut headers = HeaderMap::new();
        headers.insert(ORIGIN, HeaderValue::from_static("https://example.test"));

        assert!(!request_headers_match_site_origin(&server_cfg, &headers).unwrap());
    }

    #[test]
    fn test_request_headers_match_site_origin_rejects_mismatched_scheme() {
        let server_cfg = sample_server_cfg("https://example.test");
        let mut headers = HeaderMap::new();
        headers.insert(ORIGIN, HeaderValue::from_static("http://example.test"));

        assert!(!request_headers_match_site_origin(&server_cfg, &headers).unwrap());
    }

    #[test]
    fn test_request_headers_match_site_origin_rejects_missing_host_in_base_url() {
        let server_cfg = sample_server_cfg("/relative-path");

        assert!(request_headers_match_site_origin(&server_cfg, &HeaderMap::new()).is_err());
    }

    #[test]
    fn test_request_headers_match_site_origin_rejects_non_utf8_origin() {
        let server_cfg = sample_server_cfg("https://example.test");
        let mut headers = HeaderMap::new();
        headers.insert(ORIGIN, HeaderValue::from_bytes(&[0xFF]).unwrap());

        assert!(!request_headers_match_site_origin(&server_cfg, &headers).unwrap());
    }

    #[test]
    fn test_request_headers_match_site_origin_rejects_when_headers_are_missing() {
        let server_cfg = sample_server_cfg("https://example.test");

        assert!(!request_headers_match_site_origin(&server_cfg, &HeaderMap::new()).unwrap());
    }

    #[test]
    fn test_trim_public_gallery_images_keeps_none_unchanged() {
        let mut photos_urls = None;

        trim_public_gallery_images(&mut photos_urls);

        assert_eq!(photos_urls, None);
    }

    #[test]
    fn test_trim_public_gallery_images_keeps_short_vec_unchanged() {
        let mut photos_urls = Some(vec![sample_photo_url(0), sample_photo_url(1)]);

        trim_public_gallery_images(&mut photos_urls);

        assert_eq!(
            photos_urls,
            Some(vec![sample_photo_url(0), sample_photo_url(1)])
        );
    }

    #[test]
    fn test_trim_public_gallery_images_truncates_long_vec() {
        let mut photos_urls = Some((0..=MAX_PUBLIC_GALLERY_IMAGES).map(sample_photo_url).collect());

        trim_public_gallery_images(&mut photos_urls);

        assert_eq!(
            photos_urls.as_ref().map(Vec::len),
            Some(MAX_PUBLIC_GALLERY_IMAGES)
        );
        assert_eq!(
            photos_urls.as_ref().and_then(|photos_urls| photos_urls.last()),
            Some(&sample_photo_url(MAX_PUBLIC_GALLERY_IMAGES - 1))
        );
    }

    // Helpers

    fn sample_server_cfg(base_url: &str) -> HttpServerConfig {
        HttpServerConfig {
            base_url: base_url.to_string(),
            ..Default::default()
        }
    }

    fn sample_photo_url(idx: usize) -> String {
        format!("https://example.test/photo-{idx}.png")
    }
}
