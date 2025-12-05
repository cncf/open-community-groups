//! HTTP request handlers for the OCG server.
//!
//! This module organizes all HTTP request handlers by domain. It also includes shared
//! utilities like error handling and request extractors for common functionality.

use anyhow::Result;
use axum::http::{HeaderMap, HeaderName, HeaderValue};
use chrono::Duration;
use reqwest::header::CACHE_CONTROL;

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
/// Shared tests helpers for handlers modules.
#[cfg(test)]
pub(crate) mod tests;

/// Helper function to prepare headers for HTTP responses, including cache control and
/// additional custom headers.
#[allow(unused_variables)]
pub(crate) fn prepare_headers(cache_duration: Duration, extra_headers: &[(&str, &str)]) -> Result<HeaderMap> {
    let mut headers = HeaderMap::new();

    // Set cache control header
    #[cfg(debug_assertions)]
    let duration_secs = 0; // Disable caching in debug mode
    #[cfg(not(debug_assertions))]
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
