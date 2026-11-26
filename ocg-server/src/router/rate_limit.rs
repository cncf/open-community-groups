//! Rate limiting middleware for public and authenticated routes.
//!
//! The outer IP-keyed layer sits outside the session layers, so a request
//! rejected by an IP limit is stopped before any session load or write. The
//! inner user-keyed layer sits inside `login_required!`, so authenticated
//! limits are keyed by the signed-in user's ID and never run for anonymous or
//! cross-origin requests.

use std::{net::SocketAddr, sync::Arc, time::Instant};

use anyhow::Result;
use axum::{
    extract::{ConnectInfo, MatchedPath, Request, State},
    http::{Method, StatusCode},
    middleware::Next,
    response::{IntoResponse, Response},
};

use crate::{
    auth::AuthSession,
    config::{HttpServerConfig, LoginOptions},
    handlers::{
        rate_limit::{too_many_requests, too_many_requests_for_user},
        request_headers_match_site_origin,
    },
    services::rate_limit::{IpLimit, RateLimiter, UserLimit, Verdict},
};

use super::{OriginPolicy, RESET_PASSWORD_PATH_PREFIX, browser_request_allowed};

#[cfg(test)]
mod tests;

/// Authenticated routes mapped to a per-user limit, by limit and then path.
///
/// Paths are the route templates registered in `router::setup` and
/// `router::dashboard`, as reported by `MatchedPath`. Every protected route
/// not listed here is exempt from user-keyed limits.
const AUTHENTICATED_LIMITED_ROUTES: [AuthenticatedLimitedRoute; 7] = [
    AuthenticatedLimitedRoute::new(
        UserLimit::CustomNotifications,
        RouteMethod::Post,
        "/dashboard/community/notifications",
    ),
    AuthenticatedLimitedRoute::new(
        UserLimit::CustomNotifications,
        RouteMethod::Post,
        "/dashboard/group/notifications",
    ),
    AuthenticatedLimitedRoute::new(
        UserLimit::CustomNotifications,
        RouteMethod::Post,
        "/dashboard/group/notifications/{event_id}",
    ),
    AuthenticatedLimitedRoute::new(UserLimit::ImageUploads, RouteMethod::Post, "/images"),
    AuthenticatedLimitedRoute::new(
        UserLimit::InboxMessages,
        RouteMethod::Post,
        "/dashboard/group/inbox/{inbox_conversation_id}/replies",
    ),
    AuthenticatedLimitedRoute::new(
        UserLimit::InboxMessages,
        RouteMethod::Post,
        "/dashboard/user/inbox/{inbox_conversation_id}/messages",
    ),
    AuthenticatedLimitedRoute::new(
        UserLimit::InboxMessages,
        RouteMethod::Post,
        "/{community}/event/{event_id}/contact",
    ),
];

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

/// Authenticated route mapped to a per-user limit.
#[derive(Clone, Copy, Debug)]
struct AuthenticatedLimitedRoute {
    /// Limit applied to the route.
    limit: UserLimit,
    /// Method the route is registered under.
    method: RouteMethod,
    /// Route template as registered in the router.
    path: &'static str,
}

impl AuthenticatedLimitedRoute {
    /// Creates a route mapped to a per-user limit.
    const fn new(limit: UserLimit, method: RouteMethod, path: &'static str) -> Self {
        Self {
            limit,
            method,
            path,
        }
    }
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

impl RouteMethod {
    /// Returns the HTTP method name as used in route declarations and manifests.
    #[cfg(test)]
    const fn as_str(self) -> &'static str {
        match self {
            RouteMethod::Get => "GET",
            RouteMethod::Post => "POST",
        }
    }

    /// Maps an HTTP request method to its route table method, grouping HEAD with GET.
    fn from_method(method: &Method) -> Option<Self> {
        match *method {
            Method::GET | Method::HEAD => Some(RouteMethod::Get),
            Method::POST => Some(RouteMethod::Post),
            _ => None,
        }
    }
}

/// Middleware that applies per-user limits to mapped authenticated routes.
///
/// Mounted inside `login_required!`, so requests have already passed same-origin
/// CSRF validation and authentication. Borrows `AuthSession` from request
/// extensions only for mapped routes and fails open when a route is unmapped
/// or the session carries no user.
pub(super) async fn limit_authenticated_requests(
    State(rate_limiter): State<Arc<RateLimiter>>,
    request: Request,
    next: Next,
) -> Response {
    // Map the method and matched route to a per-user limit
    let Some(limit) = request.extensions().get::<MatchedPath>().and_then(|matched_path| {
        authenticated_route_limit(request.method(), matched_path.as_str())
    }) else {
        return next.run(request).await;
    };

    // Borrow the signed-in user's ID from the auth session, passing through if absent
    let Some(user_id) = request
        .extensions()
        .get::<AuthSession>()
        .and_then(|auth_session| auth_session.user.as_ref())
        .map(|user| user.user_id)
    else {
        return next.run(request).await;
    };

    // Apply the per-user limit
    if let Verdict::Reject { retry_after } = rate_limiter.check_user(limit, user_id, Instant::now())
    {
        return too_many_requests_for_user(request.headers(), retry_after);
    }

    next.run(request).await
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

/// Returns the per-user limit applied to an authenticated request, if any.
fn authenticated_route_limit(method: &Method, matched_path: &str) -> Option<UserLimit> {
    let route_method = RouteMethod::from_method(method)?;

    // Find the route's per-user limit
    AUTHENTICATED_LIMITED_ROUTES
        .iter()
        .find(|route| route.method == route_method && route.path == matched_path)
        .map(|route| route.limit)
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
    let route_method = RouteMethod::from_method(method)?;

    // Find the route's limit, honouring the login option that registers it
    LIMITED_ROUTES
        .iter()
        .find(|route| route.method == route_method && route.path == matched_path)
        .filter(|route| route.login.is_none_or(|option| option.is_enabled(login)))
        .map(|route| route.limit)
}
