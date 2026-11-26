//! Rate limiting middleware for unauthenticated routes.
//!
//! The layer sits outside the session layers, so a request rejected by an IP
//! limit is stopped before any session load or write.

use std::{net::SocketAddr, sync::Arc, time::Instant};

use anyhow::Result;
use axum::{
    extract::{ConnectInfo, MatchedPath, Request, State},
    http::{Method, StatusCode},
    middleware::Next,
    response::{IntoResponse, Response},
};

use crate::{
    config::{HttpServerConfig, LoginOptions},
    handlers::{rate_limit::too_many_requests, request_headers_match_site_origin},
    services::rate_limit::{IpLimit, RateLimiter, Verdict},
};

use super::{OriginPolicy, RESET_PASSWORD_PATH_PREFIX, browser_request_allowed};

#[cfg(test)]
mod tests;

/// Routes mapped to an IP limit, by limit and then path.
///
/// Paths are the route templates registered in `router::setup`, as reported
/// by `MatchedPath`. HEAD requests map with GET. Every route not listed here
/// is exempt.
const LIMITED_ROUTES: [LimitedRoute; 22] = [
    LimitedRoute::new(IpLimit::BadgeVerify, RouteMethod::Post, "/badges/verify"),
    LimitedRoute::new(IpLimit::ExploreSearch, RouteMethod::Get, "/explore"),
    LimitedRoute::new(
        IpLimit::ExploreSearch,
        RouteMethod::Get,
        "/explore/events-results-section",
    ),
    LimitedRoute::new(
        IpLimit::ExploreSearch,
        RouteMethod::Get,
        "/explore/events-section",
    ),
    LimitedRoute::new(
        IpLimit::ExploreSearch,
        RouteMethod::Get,
        "/explore/events/search",
    ),
    LimitedRoute::new(
        IpLimit::ExploreSearch,
        RouteMethod::Get,
        "/explore/groups-results-section",
    ),
    LimitedRoute::new(
        IpLimit::ExploreSearch,
        RouteMethod::Get,
        "/explore/groups-section",
    ),
    LimitedRoute::new(
        IpLimit::ExploreSearch,
        RouteMethod::Get,
        "/explore/groups/search",
    ),
    LimitedRoute::new(
        IpLimit::ExternalAuth,
        RouteMethod::Get,
        "/log-in/oauth2/{provider}",
    )
    .with_login(LoginOption::Github),
    LimitedRoute::new(
        IpLimit::ExternalAuth,
        RouteMethod::Get,
        "/log-in/oauth2/{provider}/callback",
    )
    .with_login(LoginOption::Github),
    LimitedRoute::new(
        IpLimit::ExternalAuth,
        RouteMethod::Get,
        "/log-in/oidc/{provider}",
    )
    .with_login(LoginOption::LinuxFoundation),
    LimitedRoute::new(
        IpLimit::ExternalAuth,
        RouteMethod::Get,
        "/log-in/oidc/{provider}/callback",
    )
    .with_login(LoginOption::LinuxFoundation),
    LimitedRoute::new(IpLimit::LogIn, RouteMethod::Post, "/log-in").with_login(LoginOption::Email),
    LimitedRoute::new(
        IpLimit::PasswordReset,
        RouteMethod::Post,
        "/forgot-password",
    )
    .with_login(LoginOption::Email),
    LimitedRoute::new(
        IpLimit::PasswordReset,
        RouteMethod::Get,
        "/reset-password/{token}",
    )
    .with_login(LoginOption::Email),
    LimitedRoute::new(
        IpLimit::PasswordReset,
        RouteMethod::Post,
        "/reset-password/{token}",
    )
    .with_login(LoginOption::Email),
    LimitedRoute::new(
        IpLimit::ResendVerification,
        RouteMethod::Post,
        "/resend-verification",
    )
    .with_login(LoginOption::Email),
    LimitedRoute::new(IpLimit::SignUp, RouteMethod::Post, "/sign-up")
        .with_login(LoginOption::Email),
    LimitedRoute::new(
        IpLimit::VerifyEmail,
        RouteMethod::Get,
        "/verify-email/{code}",
    )
    .with_login(LoginOption::Email),
    LimitedRoute::new(
        IpLimit::Views,
        RouteMethod::Post,
        "/communities/{community_id}/views",
    ),
    LimitedRoute::new(
        IpLimit::Views,
        RouteMethod::Post,
        "/events/{event_id}/views",
    ),
    LimitedRoute::new(
        IpLimit::Views,
        RouteMethod::Post,
        "/groups/{group_id}/views",
    ),
];

/// State of the rate limiting middleware.
pub(super) struct RateLimitLayerState {
    /// Limiter applied to the mapped routes.
    pub rate_limiter: Arc<RateLimiter>,
    /// HTTP server configuration, for the login options and origin checks.
    pub server_cfg: HttpServerConfig,
}

/// Route mapped to an IP limit.
#[derive(Clone, Copy, Debug)]
struct LimitedRoute {
    /// Limit applied to the route.
    limit: IpLimit,
    /// Method the route is registered under.
    method: RouteMethod,
    /// Route template as registered in the router.
    path: &'static str,

    /// Login option that registers the route, when it is conditional.
    login: Option<LoginOption>,
}

impl LimitedRoute {
    /// Creates a route registered regardless of the login options.
    const fn new(limit: IpLimit, method: RouteMethod, path: &'static str) -> Self {
        Self {
            limit,
            method,
            path,

            login: None,
        }
    }

    /// Marks the route as registered only under a login option.
    const fn with_login(mut self, login: LoginOption) -> Self {
        self.login = Some(login);
        self
    }
}

/// Login option that registers a route.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum LoginOption {
    /// Email and password login.
    Email,
    /// GitHub login.
    Github,
    /// Linux Foundation login.
    LinuxFoundation,
}

impl LoginOption {
    /// Returns whether the option is enabled.
    fn is_enabled(self, login: &LoginOptions) -> bool {
        match self {
            LoginOption::Email => login.email,
            LoginOption::Github => login.github,
            LoginOption::LinuxFoundation => login.linuxfoundation,
        }
    }
}

/// Method a limited route is registered under.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum RouteMethod {
    /// GET, which also serves HEAD.
    Get,
    /// POST.
    Post,
}

/// Middleware that applies the IP limits to the mapped routes.
///
/// Fails open: an unmapped route, a POST failing the inner origin checks
/// (cross-origin, or headerless on browser-guarded routes), an origin check
/// error, and an unresolved client all pass through. Rejections are not logged
/// one by one; the periodic summary aggregates them.
pub(super) async fn limit_requests(
    State(state): State<Arc<RateLimitLayerState>>,
    mut request: Request,
    next: Next,
) -> Response {
    let RateLimitLayerState {
        rate_limiter,
        server_cfg,
    } = state.as_ref();

    // Map the method and matched route to a limit
    let Some(limit) = request.extensions().get::<MatchedPath>().and_then(|matched_path| {
        route_limit(request.method(), matched_path.as_str(), &server_cfg.login)
    }) else {
        return next.run(request).await;
    };

    // Pass POSTs failing the inner origin checks through uncounted so the
    // inner layer or handler rejects them
    if request.method() == Method::POST {
        let Ok(is_allowed) = post_origin_allowed(server_cfg, limit, &request) else {
            return next.run(request).await;
        };
        if !is_allowed {
            rate_limiter.record_skipped_origin_check(limit);
            return next.run(request).await;
        }
    }

    // Resolve the client, passing an unresolved one through unlimited
    let peer = request
        .extensions()
        .get::<ConnectInfo<SocketAddr>>()
        .map(|ConnectInfo(addr)| addr.ip());
    let Some(client) = rate_limiter.resolve_client(peer, request.headers()) else {
        return next.run(request).await;
    };

    // Apply the limit, answering a rejected view as if it had been tracked
    let verdict = rate_limiter.check(limit, client, Instant::now());
    if let Verdict::Reject { retry_after } = verdict {
        return match limit {
            IpLimit::Views => StatusCode::NO_CONTENT.into_response(),
            _ => too_many_requests(request.headers(), retry_after),
        };
    }

    // Hand the failed log-in limit of the client to the log-in handler, unless the request is
    // over the log-in limit: enforce mode would have stopped it before the failed log-in limit,
    // so observe mode must not count it there either
    if limit == IpLimit::LogIn && verdict == Verdict::Allow {
        request
            .extensions_mut()
            .insert(rate_limiter.log_in_failure_limit(client));
    }

    next.run(request).await
}

/// Returns whether a POST to a limited route passes the origin checks that
/// the inner origin layer and, for views, the view handler apply.
///
/// Stateless badge verification allows headerless CLI/API requests while still
/// rejecting explicit cross-site browser signals, matching its route layer.
fn post_origin_allowed(
    server_cfg: &HttpServerConfig,
    limit: IpLimit,
    request: &Request,
) -> Result<bool> {
    // Match the route's origin layer policy
    let policy = match limit {
        IpLimit::BadgeVerify => OriginPolicy::AllowHeaderless,
        IpLimit::PasswordReset if request.uri().path().starts_with(RESET_PASSWORD_PATH_PREFIX) => {
            OriginPolicy::AllowNoReferrerSameOrigin
        }
        _ => OriginPolicy::RequireEvidence,
    };
    if !browser_request_allowed(server_cfg, request.method(), request.headers(), policy)? {
        return Ok(false);
    }

    // Apply the view handler's origin check
    if limit == IpLimit::Views {
        return request_headers_match_site_origin(server_cfg, request.headers());
    }

    Ok(true)
}

/// Returns the IP limit applied to a request, if any.
///
/// HEAD maps with GET. A route registered only under a login option maps
/// only while that option is enabled.
fn route_limit(method: &Method, matched_path: &str, login: &LoginOptions) -> Option<IpLimit> {
    // Match HEAD requests against the GET routes
    let route_method = match *method {
        Method::GET | Method::HEAD => RouteMethod::Get,
        Method::POST => RouteMethod::Post,
        _ => return None,
    };

    // Find the route's limit, honouring the login option that registers it
    LIMITED_ROUTES
        .iter()
        .find(|route| route.method == route_method && route.path == matched_path)
        .filter(|route| route.login.is_none_or(|option| option.is_enabled(login)))
        .map(|route| route.limit)
}
