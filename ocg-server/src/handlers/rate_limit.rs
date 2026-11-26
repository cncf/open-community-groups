//! Responses returned to requests rejected by a rate limit.

use std::time::Duration;

use askama::Template;
use axum::{
    http::{
        HeaderMap, HeaderName, StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE, RETRY_AFTER, VARY},
    },
    response::{Html, IntoResponse, Response},
};
use tracing::error;

use crate::{
    handlers::accepts_media_type,
    router::{CACHE_CONTROL_NO_STORE, header_value_is_true},
    templates::site::too_many_requests,
};

#[cfg(test)]
mod tests;

/// Largest `Retry-After` value sent, in seconds.
const MAX_RETRY_AFTER_SECS: u64 = 86_400;

/// Header marking a plain-text rejection sent by this server, whose text the frontend may show.
pub(crate) const RATE_LIMITED_HEADER: &str = "x-ocg-rate-limited";

/// Request headers that select the rejection representation.
const REJECTION_VARY: &str = "accept, hx-request, sec-fetch-mode, x-ocg-fetch";

/// Content type of the plain-text rejection body.
const TEXT_PLAIN_UTF_8: &str = "text/plain; charset=utf-8";

/// Builds the 429 response returned to a request over an IP-keyed rate limit.
///
/// A document navigation gets a standalone HTML page; htmx, fetch and any other caller get
/// the same message as plain text, with the marker header the frontend checks before showing
/// it. Neither representation reads the database, loads or writes the session, or sets a
/// cookie: the page renders from a compiled template with the default theme.
pub(crate) fn too_many_requests(headers: &HeaderMap, retry_after: Duration) -> Response {
    too_many_requests_response(headers, retry_after, "your network")
}

/// Builds the 429 response returned to a request over a per-user rate limit.
///
/// Shares the same HTML and marked plain-text representations as
/// [`too_many_requests`] without reading the database, modifying the session,
/// or adding a cookie itself; unlike IP-keyed rejections, this runs inside the
/// authentication middleware after the session has already been loaded.
pub(crate) fn too_many_requests_for_user(headers: &HeaderMap, retry_after: Duration) -> Response {
    too_many_requests_response(headers, retry_after, "your account")
}

/// Returns whether the request is a browser document navigation, not an htmx or script call.
fn is_document_navigation(headers: &HeaderMap) -> bool {
    !header_value_is_true(headers, "hx-request")
        && !header_value_is_true(headers, "x-ocg-fetch")
        && headers
            .get("sec-fetch-mode")
            .is_none_or(|mode| mode.as_bytes().eq_ignore_ascii_case(b"navigate"))
        && accepts_media_type(headers, "text/html")
}

/// Builds the 429 response with a wait message naming `subject` (network or account).
fn too_many_requests_response(
    headers: &HeaderMap,
    retry_after: Duration,
    subject: &str,
) -> Response {
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

    // Build the message shared by both representations
    let message = format!("Too many requests from {subject}. Please wait {wait} and try again.");

    // Prepare the uncacheable headers shared by both representations
    let common_headers = [
        (RETRY_AFTER, retry_after_secs.to_string()),
        (CACHE_CONTROL, CACHE_CONTROL_NO_STORE.to_string()),
        (VARY, REJECTION_VARY.to_string()),
    ];

    // Answer a document navigation with the standalone page
    if is_document_navigation(headers) {
        let page = too_many_requests::Page {
            message: message.clone(),
        };
        match page.render() {
            Ok(html) => {
                return (StatusCode::TOO_MANY_REQUESTS, common_headers, Html(html)).into_response();
            }
            Err(err) => {
                error!(error = %format_args!("{err:#}"), "error rendering the too many requests page");
            }
        }
    }

    // Answer every other caller, and a page that failed to render, with marked plain text
    (
        StatusCode::TOO_MANY_REQUESTS,
        common_headers,
        [
            (CONTENT_TYPE, TEXT_PLAIN_UTF_8),
            (HeaderName::from_static(RATE_LIMITED_HEADER), "true"),
        ],
        message,
    )
        .into_response()
}
