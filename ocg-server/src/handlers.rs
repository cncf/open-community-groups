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
/// CSV download helpers shared by handlers.
pub(crate) mod csv;
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
        config::tests::sample_server_cfg,
        router::{CACHE_CONTROL_PUBLIC_SHARED, PUBLIC_SHARED_CACHE_VARY},
    };

    use super::*;

    #[test]
    fn test_extend_public_shared_cache_headers_rejects_invalid_extra_headers() {
        // Setup labeled extra headers that cannot be encoded
        let cases = [
            ("invalid name", ("invalid header", "value")),
            ("invalid value", ("x-test", "invalid\nvalue")),
        ];

        // Check each extra header is rejected
        for (case, extra_header) in cases {
            let result = extend_public_shared_cache_headers(&[extra_header]);
            assert!(result.is_err(), "{case}");
        }
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
    fn test_request_headers_match_site_origin() {
        // Setup labeled site origins and request headers with the expected match
        type Case = (
            &'static str,
            &'static str,
            Option<&'static [u8]>,
            Option<&'static str>,
            bool,
        );
        let cases: [Case; 11] = [
            (
                "matching origin",
                "https://example.test",
                Some(b"https://example.test"),
                None,
                true,
            ),
            (
                "matching referer without origin",
                "https://example.test",
                None,
                Some("https://example.test/page"),
                true,
            ),
            (
                "referer with normalized default port",
                "https://example.test",
                None,
                Some("https://example.test:443/page"),
                true,
            ),
            (
                "host compared case-insensitively",
                "https://Example.Test",
                Some(b"https://EXAMPLE.TEST"),
                None,
                true,
            ),
            (
                "origin preferred over matching referer",
                "https://example.test",
                Some(b"https://evil.test"),
                Some("https://example.test/page"),
                false,
            ),
            (
                "mismatched referer without origin",
                "https://example.test",
                None,
                Some("https://evil.test/page"),
                false,
            ),
            (
                "mismatched port",
                "https://example.test:8443",
                Some(b"https://example.test"),
                None,
                false,
            ),
            (
                "mismatched scheme",
                "https://example.test",
                Some(b"http://example.test"),
                None,
                false,
            ),
            (
                "non-UTF-8 origin",
                "https://example.test",
                Some(&[0xFF]),
                None,
                false,
            ),
            (
                "unparsable referer",
                "https://example.test",
                None,
                Some("not a url"),
                false,
            ),
            ("missing headers", "https://example.test", None, None, false),
        ];

        // Check each case resolves the expected match
        for (case, base_url, origin, referer, expected) in cases {
            let server_cfg = sample_server_cfg(base_url);
            let mut headers = HeaderMap::new();
            if let Some(origin) = origin {
                headers.insert(ORIGIN, HeaderValue::from_bytes(origin).unwrap());
            }
            if let Some(referer) = referer {
                headers.insert(REFERER, HeaderValue::from_str(referer).unwrap());
            }
            assert_eq!(
                request_headers_match_site_origin(&server_cfg, &headers).unwrap(),
                expected,
                "{case}"
            );
        }
    }

    #[test]
    fn test_request_headers_match_site_origin_rejects_missing_host_in_base_url() {
        let server_cfg = sample_server_cfg("/relative-path");

        assert!(request_headers_match_site_origin(&server_cfg, &HeaderMap::new()).is_err());
    }

    #[test]
    fn test_trim_public_gallery_images() {
        // Setup labeled galleries with the expected public gallery
        let urls = |count: usize| (0..count).map(sample_photo_url).collect::<Vec<_>>();
        let cases = [
            ("no gallery", None, None),
            ("short gallery", Some(urls(2)), Some(urls(2))),
            (
                "long gallery",
                Some(urls(MAX_PUBLIC_GALLERY_IMAGES + 1)),
                Some(urls(MAX_PUBLIC_GALLERY_IMAGES)),
            ),
        ];

        // Check each gallery keeps at most the leading public images
        for (case, mut photos_urls, expected) in cases {
            trim_public_gallery_images(&mut photos_urls);
            assert_eq!(photos_urls, expected, "{case}");
        }
    }

    // Helpers.

    /// Builds the URL of the gallery photo at `idx`.
    fn sample_photo_url(idx: usize) -> String {
        format!("https://example.test/photo-{idx}.png")
    }
}
