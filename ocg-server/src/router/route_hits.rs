//! Route-hit logging for the OCG server router.
//!
//! This module emits one `ocg_route_hits` event per response, which the E2E
//! route coverage scripts (`tests/e2e/scripts/route-hits.js`) read from the
//! server logs. The target name and the event fields are part of that contract.

use std::time::Duration;

use axum::{extract::Request, http::Response, middleware::Next};
use tower_http::trace::OnResponse;
use tracing::{Span, debug};

use crate::auth::AuthSession;

/// Tracing target of the per-request route-hit event.
///
/// It is outside the default `ocg_server` filter, so the event is only emitted
/// when `RUST_LOG` enables it explicitly (for example in E2E runs).
const ROUTE_HITS_TARGET: &str = "ocg_route_hits";

/// Response extension marking a request the log-in guard rejected before its
/// handler ran.
#[derive(Clone, Copy, Debug)]
struct LogInGuardRejection;

/// Route-hit logger run when the request span's response is ready.
///
/// Emits one `ocg_route_hits` event per response inside the request span, so
/// the event carries the span's matched path and request id.
#[derive(Clone, Copy, Debug)]
pub(super) struct RouteHitLog;

impl<B> OnResponse<B> for RouteHitLog {
    fn on_response(self, response: &Response<B>, latency: Duration, _span: &Span) {
        debug!(
            target: ROUTE_HITS_TARGET,
            latency_ms = u64::try_from(latency.as_millis()).unwrap_or(u64::MAX),
            redirects_to_log_in = redirects_to_log_in(response),
            status = response.status().as_u16(),
            "route hit"
        );
    }
}

// Middleware.

/// Middleware that marks the responses of anonymous requests to log-in
/// guarded routes.
///
/// It wraps the `login_required!` layer, which rejects exactly these requests
/// with a redirect to the log-in page, so route-hit logs can tell that
/// rejection from handlers that redirect to the log-in page themselves.
pub(super) async fn mark_log_in_guard_rejections(
    auth_session: AuthSession,
    request: Request,
    next: Next,
) -> axum::response::Response {
    // Run the log-in guard and, when the user is authenticated, the handler
    let is_anonymous = auth_session.user.is_none();
    let mut response = next.run(request).await;

    // Mark the guard's rejection of an anonymous request
    if is_anonymous {
        response.extensions_mut().insert(LogInGuardRejection);
    }

    response
}

// Helpers.

/// Returns whether the log-in guard redirected the request to the log-in page
/// instead of running its handler.
///
/// Handlers that redirect to the log-in page after doing their work, such as
/// log out, are not flagged.
pub(super) fn redirects_to_log_in<B>(response: &Response<B>) -> bool {
    response.extensions().get::<LogInGuardRejection>().is_some()
}
