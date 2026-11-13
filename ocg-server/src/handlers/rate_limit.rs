//! Responses returned to requests rejected by a rate limit.

use std::time::Duration;

use axum::{
    http::{
        StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE, RETRY_AFTER},
    },
    response::{IntoResponse, Response},
};

use crate::router::CACHE_CONTROL_NO_STORE;

#[cfg(test)]
mod tests;

/// Largest `Retry-After` value sent, in seconds.
const MAX_RETRY_AFTER_SECS: u64 = 86_400;

/// Content type of the plain-text rejection body.
const TEXT_PLAIN_UTF_8: &str = "text/plain; charset=utf-8";

/// Builds the 429 response returned to a request over a rate limit.
///
/// The response is plain text so a rejection renders no template, reads
/// nothing from the database and writes nothing to the session.
pub(crate) fn too_many_requests(retry_after: Duration) -> Response {
    // Round the wait up to whole seconds and minutes, within the sent bounds
    let retry_after_secs = retry_after
        .as_secs()
        .saturating_add(u64::from(retry_after.subsec_nanos() > 0))
        .clamp(1, MAX_RETRY_AFTER_SECS);
    let minutes = retry_after_secs.div_ceil(60);
    let wait = if minutes == 1 {
        "1 minute".to_string()
    } else {
        format!("{minutes} minutes")
    };

    // Prepare the uncacheable plain-text response
    let headers = [
        (RETRY_AFTER, retry_after_secs.to_string()),
        (CACHE_CONTROL, CACHE_CONTROL_NO_STORE.to_string()),
        (CONTENT_TYPE, TEXT_PLAIN_UTF_8.to_string()),
    ];
    let body = format!("Too many requests from your network. Please wait {wait} and try again.");

    (StatusCode::TOO_MANY_REQUESTS, headers, body).into_response()
}
