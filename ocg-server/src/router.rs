//! HTTP routing configuration for the OCG server.
//!
//! This module sets up the Axum router with all application routes, middleware layers,
//! and static file handling.

mod dashboard;
mod rate_limit;
mod route_hits;

#[cfg(test)]
mod tests;

use std::sync::Arc;

use anyhow::Result;
use axum::{
    Router,
    extract::{FromRef, MatchedPath, Request, State as AxumState},
    http::{
        HeaderMap, HeaderName, HeaderValue, Method, StatusCode, Uri,
        header::{
            CACHE_CONTROL, CONTENT_TYPE, HOST, ORIGIN, REFERER, REFERRER_POLICY, SET_COOKIE,
            STRICT_TRANSPORT_SECURITY, VARY, X_CONTENT_TYPE_OPTIONS, X_FRAME_OPTIONS,
        },
    },
    middleware::{self, Next},
    response::{IntoResponse, Redirect},
    routing::{delete, get, post, put},
};
use axum_login::login_required;
use axum_messages::MessagesManagerLayer;
use rust_embed::Embed;
use tokio_util::sync::CancellationToken;
use tower::ServiceBuilder;
use tower_http::{
    request_id::{MakeRequestUuid, PropagateRequestIdLayer, SetRequestIdLayer},
    set_header::SetResponseHeaderLayer,
    trace::TraceLayer,
};
use tracing::{Span, debug, error, info_span, instrument};

use crate::{
    activity_tracker::DynActivityTracker,
    auth::AuthnBackend,
    config::{HttpServerConfig, MeetingsConfig, PaymentsConfig},
    db::DynDB,
    handlers::{
        auth::{self, LOG_IN_URL},
        badges, community, event, group, images, meetings, payments,
        request_headers_match_site_origin, site,
    },
    services::{
        badges::{DynBadgesManager, SsiBadgesManager},
        blocking::BlockingExecutor,
        enrollment::DynEnrollmentManager,
        events::DynEventsManager,
        images::DynImagesManager,
        inbox::DynInboxManager,
        notifications::DynNotificationsManager,
        payments::DynPaymentsManager,
        rate_limit::RateLimiter,
    },
};

use self::rate_limit::RateLimitLayerState;

/// Cache-Control header value for immutable public assets.
#[cfg(any(not(debug_assertions), test))]
const CACHE_CONTROL_IMMUTABLE: &str = "public, max-age=31536000, immutable";

/// Cache-Control header value instructing clients and proxies not to store responses.
pub(crate) const CACHE_CONTROL_NO_STORE: &str = "no-store";

/// Cache-Control header value for private responses that must not be stored.
pub(crate) const CACHE_CONTROL_PRIVATE_NO_STORE: &str = "private, no-store";

/// Cache-Control header value for shared public responses.
#[cfg(any(not(debug_assertions), test))]
pub(crate) const CACHE_CONTROL_PUBLIC_SHARED: &str =
    "public, max-age=0, s-maxage=300, stale-while-revalidate=60";

/// Cache-Control header value for shared public responses in local development.
#[cfg(all(debug_assertions, not(test)))]
pub(crate) const CACHE_CONTROL_PUBLIC_SHARED: &str = "public, max-age=0";

/// Cache-Control header value for favicon redirects.
const CACHE_CONTROL_FAVICON_REDIRECT: &str = "public, max-age=604800";

/// Cache-Control header value for default static asset responses.
#[cfg(any(not(debug_assertions), test))]
const CACHE_CONTROL_STATIC_DEFAULT: &str = "max-age=3600";

/// Cache-Control header value for local development static asset responses.
#[cfg(all(debug_assertions, not(test)))]
const CACHE_CONTROL_STATIC_DEVELOPMENT: &str = "max-age=0";

/// Cache-Control header value for static image responses.
#[cfg(any(not(debug_assertions), test))]
const CACHE_CONTROL_STATIC_IMAGES: &str = "max-age=604800";

/// Current application commit SHA embedded at build time.
pub(crate) const COMMIT_SHA: &str = env!("OCG_COMMIT_SHA");

/// Header carrying the loaded or current application commit SHA.
pub(crate) const COMMIT_SHA_HEADER: &str = "x-ocg-commit-sha";

/// Header used to request an application-level page refresh for `ocgFetch`.
const OCG_REFRESH_HEADER: &str = "x-ocg-refresh";

/// Permissions-Policy header name.
const PERMISSIONS_POLICY: HeaderName = HeaderName::from_static("permissions-policy");

/// Permissions-Policy header value allowing camera access only on the site itself.
const PERMISSIONS_POLICY_VALUE: &str =
    "camera=(self), microphone=(), geolocation=(), payment=(), usb=()";

/// Headers for public shared-cache responses without additional headers.
pub(crate) const PUBLIC_SHARED_CACHE_HEADERS: [(HeaderName, &str); 2] = [
    (CACHE_CONTROL, CACHE_CONTROL_PUBLIC_SHARED),
    (VARY, PUBLIC_SHARED_CACHE_VARY),
];

/// Vary header value for public shared-cache responses.
pub(crate) const PUBLIC_SHARED_CACHE_VARY: &str = "x-ocg-commit-sha, hx-request, x-ocg-fetch";

/// Referrer-Policy header value applied to every response.
const REFERRER_POLICY_VALUE: &str = "strict-origin-when-cross-origin";

/// Matched path recorded for requests served by the router fallback.
const ROUTE_FALLBACK_PATH: &str = "fallback";

/// Path prefix of embedded static assets.
const STATIC_PATH_PREFIX: &str = "/static/";

/// Strict-Transport-Security header value applied when `base_url` uses HTTPS.
const STRICT_TRANSPORT_SECURITY_VALUE: &str = "max-age=31536000";

/// X-Content-Type-Options header value applied to every response.
const X_CONTENT_TYPE_OPTIONS_VALUE: &str = "nosniff";

/// X-Frame-Options header value applied to every response.
const X_FRAME_OPTIONS_VALUE: &str = "DENY";

/// Static file embedder using rust-embed.
///
/// Embeds all files from the static directory into the binary.
#[derive(Embed)]
#[folder = "dist/static"]
struct StaticFile;

/// Policy controlling how unsafe requests without browser origin headers are handled.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum OriginPolicy {
    /// Allow requests lacking `Sec-Fetch-Site`, `Origin`, and `Referer` while
    /// still rejecting explicit cross-site browser signals.
    AllowHeaderless,
    /// Fail closed unless trustworthy same-origin browser signals are present.
    RequireEvidence,
}

/// Dependencies required to build the application router.
pub(crate) struct RouterDeps {
    /// Activity tracker handle.
    pub activity_tracker: DynActivityTracker,
    /// Bounded executor for CPU-heavy work.
    pub blocking_executor: BlockingExecutor,
    /// Database handle.
    pub db: DynDB,
    /// Enrollment manager handle.
    pub enrollment_manager: DynEnrollmentManager,
    /// Events manager handle.
    pub events_manager: DynEventsManager,
    /// Images manager handle.
    pub images_manager: DynImagesManager,
    /// Inbox manager handle.
    pub inbox_manager: DynInboxManager,
    /// Notifications manager handle.
    pub notifications_manager: DynNotificationsManager,
    /// Payments manager handle.
    pub payments_manager: DynPaymentsManager,
    /// HTTP server configuration.
    pub server_cfg: HttpServerConfig,
    /// Token cancelled when the server starts draining traffic before shutdown.
    pub shutdown_drain: CancellationToken,

    /// Meetings configuration.
    pub meetings_cfg: Option<MeetingsConfig>,
    /// Payments configuration.
    pub payments_cfg: Option<PaymentsConfig>,
    /// Rate limiter for unauthenticated routes, when configured.
    pub rate_limiter: Option<Arc<RateLimiter>>,
}

/// Shared state for the router.
#[derive(Clone, FromRef)]
pub(crate) struct State {
    /// Activity tracker handle.
    pub activity_tracker: DynActivityTracker,
    /// Open Badges credential manager.
    pub badges_manager: DynBadgesManager,
    /// Bounded executor for CPU-heavy work such as password hashing and image processing.
    pub blocking_executor: BlockingExecutor,
    /// Database handle.
    pub db: DynDB,
    /// Enrollment manager handle.
    pub enrollment_manager: DynEnrollmentManager,
    /// Events manager handle.
    pub events_manager: DynEventsManager,
    /// Images manager handle.
    pub images_manager: DynImagesManager,
    /// Inbox manager handle.
    pub inbox_manager: DynInboxManager,
    /// Notifications manager handle.
    pub notifications_manager: DynNotificationsManager,
    /// Payments manager handle.
    pub payments_manager: DynPaymentsManager,
    /// `serde_qs` config for query string parsing.
    pub serde_qs_de: serde_qs::Config,
    /// HTTP server configuration.
    pub server_cfg: HttpServerConfig,
    /// Token cancelled when the server starts draining traffic before shutdown.
    pub shutdown_drain: CancellationToken,

    /// Meetings configuration.
    pub meetings_cfg: Option<MeetingsConfig>,
    /// Payments configuration.
    pub payments_cfg: Option<PaymentsConfig>,
}

/// Configures and returns the application router.
///
/// Sets up all routes, middleware layers, and shared state. Optionally adds basic
/// authentication if configured, and rate limiting when a limiter is given.
#[allow(clippy::too_many_lines)]
#[instrument(skip_all)]
pub(crate) async fn setup(deps: RouterDeps) -> Result<Router> {
    let RouterDeps {
        activity_tracker,
        blocking_executor,
        db,
        enrollment_manager,
        events_manager,
        images_manager,
        inbox_manager,
        notifications_manager,
        payments_manager,
        server_cfg,
        shutdown_drain,

        meetings_cfg,
        payments_cfg,
        rate_limiter,
    } = deps;

    // Check whether the Zoom meetings provider is enabled
    let zoom_enabled = meetings_cfg
        .as_ref()
        .and_then(|cfg| cfg.zoom.as_ref())
        .is_some_and(|zoom_cfg| zoom_cfg.enabled);

    // Check whether a payments provider is configured
    let payments_enabled = payments_cfg.is_some();

    // Get badges configuration
    let badges_config = server_cfg
        .badges
        .as_ref()
        .expect("server badge configuration to be validated before router setup");

    // Setup authentication layer before moving server_cfg into router state
    let auth_layer = Box::pin(crate::auth::setup_layer(
        &server_cfg,
        blocking_executor.clone(),
        db.clone(),
    ))
    .await?;

    // Setup router state, sharing the caller's blocking bound with handlers and auth
    let state = State {
        activity_tracker,
        badges_manager: Arc::new(SsiBadgesManager::new(
            &server_cfg.base_url,
            blocking_executor.clone(),
            badges_config,
        )),
        blocking_executor,
        db,
        enrollment_manager,
        events_manager,
        images_manager,
        inbox_manager,
        notifications_manager,
        payments_manager,
        serde_qs_de: serde_qs_config(),
        server_cfg,
        shutdown_drain,

        meetings_cfg,
        payments_cfg,
    };

    // Setup sub-routers
    let community_dashboard_router = dashboard::setup_community_dashboard_router(&state);
    let group_dashboard_router = dashboard::setup_group_dashboard_router(&state);
    let user_dashboard_router = dashboard::setup_user_dashboard_router();

    // Setup router
    // Register protected routes before applying the login middleware layer
    let mut router = Router::new()
        // Community-prefixed protected routes
        .route(
            "/{community}/event/{event_id}/attend",
            post(event::attend_event),
        )
        .route(
            "/{community}/event/{event_id}/checkout",
            delete(event::cancel_checkout).post(event::start_checkout),
        )
        .route(
            "/{community}/event/{event_id}/enrollment",
            get(event::enrollment_state),
        )
        .route(
            "/{community}/event/{event_id}/leave",
            delete(event::leave_event),
        )
        .route(
            "/{community}/event/{event_id}/refund-request",
            post(event::request_refund),
        )
        .route(
            "/{community}/event/{event_id}/cfs-submissions",
            post(event::submit_cfs_submission),
        )
        .route(
            "/{community}/event/{event_id}/contact",
            post(event::send_contact_message),
        )
        .route(
            "/{community}/group/{group_id}/join",
            post(group::join_group),
        )
        .route(
            "/{community}/group/{group_id}/leave",
            delete(group::leave_group),
        )
        .route(
            "/{community}/group/{group_id}/membership",
            get(group::membership_status),
        )
        // Protected dashboard routes
        .route(
            "/dashboard/account/update/details",
            put(auth::update_user_details),
        )
        .route(
            "/dashboard/account/update/password",
            put(auth::update_user_password),
        )
        .nest("/dashboard/community", community_dashboard_router)
        .nest("/dashboard/group", group_dashboard_router)
        .nest("/dashboard/user", user_dashboard_router)
        // Protected image upload
        .route("/images", post(images::upload))
        .route_layer(login_required!(
            AuthnBackend,
            login_url = LOG_IN_URL,
            redirect_field = "next_url"
        ))
        .route_layer(middleware::from_fn(
            route_hits::mark_log_in_guard_rejections,
        ))
        // Global site routes (no community prefix)
        .route("/", get(site::home::page))
        .route(
            "/apple-touch-icon-precomposed.png",
            get(|| async { StatusCode::NOT_FOUND }),
        )
        .route(
            "/apple-touch-icon.png",
            get(|| async { StatusCode::NOT_FOUND }),
        )
        .route(
            "/badges/credentials/{user_badge_id}",
            get(badges::credential),
        )
        .route("/badges/issuers/{group_id}", get(badges::issuer))
        .route(
            "/badges/issuers/{group_id}/keys/{key_multibase}",
            get(badges::issuer_key),
        )
        .route(
            "/badges/status-lists/{badge_status_list_id}",
            get(badges::status_list),
        )
        .route("/docs", get(site::docs::page))
        .route("/explore", get(site::explore::page))
        .route(
            "/explore/events-section",
            get(site::explore::events_section),
        )
        .route(
            "/explore/events-results-section",
            get(site::explore::events_results_section),
        )
        .route(
            "/explore/groups-section",
            get(site::explore::groups_section),
        )
        .route(
            "/explore/groups-results-section",
            get(site::explore::groups_results_section),
        )
        .route("/explore/events/search", get(site::explore::search_events))
        .route(
            "/explore/events/{event_id}/card",
            get(site::explore::event_card),
        )
        .route("/explore/groups/search", get(site::explore::search_groups))
        .route(
            "/explore/groups/{group_id}/card",
            get(site::explore::group_card),
        )
        .route("/favicon.ico", get(favicon))
        .route("/health-check", get(health_check))
        .route("/images/badges/{file_name}", get(images::serve_badge))
        .route("/images/og/{file_name}", get(images::serve_open_graph))
        .route("/images/{file_name}", get(images::serve))
        .route("/log-in", get(auth::log_in_page))
        .route("/stats", get(site::stats::page))
        .route("/users/{username}/badges", get(badges::user_profile_badges))
        // Community-prefixed public routes
        .route("/{community}", get(community::page))
        .route("/{community}/group/{group_slug}", get(group::page))
        .route(
            "/{community}/event/{event_id}/cfs-modal",
            get(event::cfs_modal),
        )
        .route(
            "/{community}/event/{event_id}/contact-modal",
            get(event::contact_modal),
        )
        .route(
            "/{community}/group/{group_slug}/event/{event_slug}/availability",
            get(event::availability),
        )
        .route(
            "/{community}/group/{group_slug}/event/{event_slug}/calendar.ics",
            get(event::calendar),
        )
        .route(
            "/{community}/group/{group_slug}/event/{event_slug}",
            get(event::page),
        )
        // Page view tracking routes
        .route(
            "/communities/{community_id}/views",
            post(community::track_view),
        )
        .route("/events/{event_id}/views", post(event::track_view))
        .route("/groups/{group_id}/views", post(group::track_view))
        .fallback(site::not_found::page);

    // Setup some routes based on the login options enabled
    if state.server_cfg.login.email {
        router = router
            .route("/log-in", post(auth::log_in))
            .route("/sign-up", post(auth::sign_up))
            .route("/verify-email/{code}", get(auth::verify_email));
    }
    if state.server_cfg.login.github {
        router = router
            .route("/log-in/oauth2/{provider}", get(auth::oauth2_redirect))
            .route(
                "/log-in/oauth2/{provider}/callback",
                get(auth::oauth2_callback),
            );
    }
    if state.server_cfg.login.linuxfoundation {
        router = router
            .route("/log-in/oidc/{provider}", get(auth::oidc_redirect))
            .route("/log-in/oidc/{provider}/callback", get(auth::oidc_callback));
    }

    // Stateless public badge verification: allow headerless CLI/API clients
    // while still rejecting explicit cross-site browser POSTs
    let badge_verify_router = Router::new()
        .route(
            "/badges/verify",
            get(badges::verify_page).post(badges::verify),
        )
        .route_layer(middleware::from_fn_with_state(
            state.clone(),
            enforce_badge_verify_origin,
        ));

    router = router
        .route("/log-out", post(auth::log_out))
        .route("/section/user-menu", get(auth::user_menu_section))
        .route("/sign-up", get(auth::sign_up_page))
        .route_layer(middleware::from_fn_with_state(
            state.clone(),
            enforce_browser_same_origin,
        ))
        .merge(badge_verify_router);

    // Setup Zoom webhook route if enabled in configuration
    if zoom_enabled {
        router = router.route("/webhooks/zoom", post(meetings::zoom_event));
    }

    // Setup the payments webhook route if enabled in configuration
    if payments_enabled {
        router = router.route("/webhooks/payments", post(payments::webhook)).route(
            "/webhooks/payments/connected",
            post(payments::connected_webhook),
        );
    }

    // Wrap the routes in the messages and session layers
    router = router.layer(MessagesManagerLayer).layer(auth_layer);

    // Limit unauthenticated routes outside the session layers, when configured
    if let Some(rate_limiter) = rate_limiter {
        let rate_limit_state = Arc::new(RateLimitLayerState {
            rate_limiter,
            server_cfg: state.server_cfg.clone(),
        });
        router = router.layer(middleware::from_fn_with_state(
            rate_limit_state,
            rate_limit::limit_requests,
        ));
    }

    router = router
        .layer(middleware::from_fn(strip_cookies_from_public_responses))
        .layer(
            // Assign a request id, open the request span carrying it, and echo it in the response
            ServiceBuilder::new()
                .layer(SetRequestIdLayer::x_request_id(MakeRequestUuid))
                .layer(
                    TraceLayer::new_for_http()
                        .make_span_with(make_request_span)
                        .on_response(route_hits::RouteHitLog),
                )
                .layer(PropagateRequestIdLayer::x_request_id()),
        )
        .route("/static/{*file}", get(static_handler))
        .layer(SetResponseHeaderLayer::if_not_present(
            CACHE_CONTROL,
            HeaderValue::from_static(CACHE_CONTROL_PRIVATE_NO_STORE),
        ))
        .layer(middleware::from_fn(refresh_stale_clients));

    // Emit HSTS for canonical HTTPS responses (including stale-client 204s),
    // excluding legacy redirect hosts handled by the outer redirect layer
    if is_https_base_url(&state.server_cfg.base_url) {
        router = router.layer(SetResponseHeaderLayer::if_not_present(
            STRICT_TRANSPORT_SECURITY,
            HeaderValue::from_static(STRICT_TRANSPORT_SECURITY_VALUE),
        ));
    }

    router = router
        .layer(middleware::from_fn_with_state(
            state.clone(),
            redirect_old_hosts,
        ))
        // Apply global non-CSP security headers to every response
        .layer(
            ServiceBuilder::new()
                .layer(SetResponseHeaderLayer::if_not_present(
                    PERMISSIONS_POLICY,
                    HeaderValue::from_static(PERMISSIONS_POLICY_VALUE),
                ))
                .layer(SetResponseHeaderLayer::if_not_present(
                    REFERRER_POLICY,
                    HeaderValue::from_static(REFERRER_POLICY_VALUE),
                ))
                .layer(SetResponseHeaderLayer::if_not_present(
                    X_CONTENT_TYPE_OPTIONS,
                    HeaderValue::from_static(X_CONTENT_TYPE_OPTIONS_VALUE),
                ))
                .layer(SetResponseHeaderLayer::if_not_present(
                    X_FRAME_OPTIONS,
                    HeaderValue::from_static(X_FRAME_OPTIONS_VALUE),
                )),
        );

    Ok(router.with_state(state))
}

// Handlers.

/// Redirects favicon requests to the configured site favicon URL.
#[instrument(skip_all)]
async fn favicon(AxumState(db): AxumState<DynDB>) -> impl IntoResponse {
    // Load the configured site settings to resolve the favicon target
    let Ok(site_settings) = db.get_site_settings().await else {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    };

    // Return a plain 404 when no favicon has been configured
    let Some(favicon_url) = site_settings.favicon_url else {
        return StatusCode::NOT_FOUND.into_response();
    };

    // Cache the redirect so browsers avoid repeating this lookup on every visit
    let mut response = Redirect::to(&favicon_url).into_response();
    response.headers_mut().insert(
        CACHE_CONTROL,
        HeaderValue::from_static(CACHE_CONTROL_FAVICON_REDIRECT),
    );

    response
}

/// Health check endpoint handler.
///
/// Returns 200 OK for monitoring and load balancer health checks, or 503 while
/// the server drains traffic before shutdown.
#[instrument(skip_all)]
async fn health_check(
    AxumState(shutdown_drain): AxumState<CancellationToken>,
) -> impl IntoResponse {
    if shutdown_drain.is_cancelled() {
        return StatusCode::SERVICE_UNAVAILABLE;
    }

    StatusCode::OK
}

/// Static file handler for embedded assets.
///
/// Serves files embedded in the binary with appropriate MIME types and cache headers.
#[instrument]
async fn static_handler(uri: Uri) -> impl IntoResponse {
    // Extract file path from URI
    let path = uri.path().trim_start_matches(STATIC_PATH_PREFIX);

    // Set cache policy based on resource type
    #[cfg(any(not(debug_assertions), test))]
    let cache = if path.starts_with("js/") || path.starts_with("css/") {
        // Cache content-hashed assets indefinitely
        CACHE_CONTROL_IMMUTABLE
    } else if path.starts_with("vendor/") {
        // Cache versioned vendor assets indefinitely
        CACHE_CONTROL_IMMUTABLE
    } else if path.starts_with("images/") {
        CACHE_CONTROL_STATIC_IMAGES
    } else {
        // Use the default cache duration for other static resources
        CACHE_CONTROL_STATIC_DEFAULT
    };
    #[cfg(all(debug_assertions, not(test)))]
    let cache = CACHE_CONTROL_STATIC_DEVELOPMENT;

    // Get file content and return it (if available)
    match StaticFile::get(path) {
        Some(file) => {
            let mime = mime_guess::from_path(path).first_or_octet_stream();
            let headers = [(CONTENT_TYPE, mime.as_ref()), (CACHE_CONTROL, cache)];
            (headers, file.data).into_response()
        }
        None => StatusCode::NOT_FOUND.into_response(),
    }
}

// Middleware.

/// Rejects explicit cross-site browser requests while allowing headerless CLI/API verifiers.
async fn enforce_badge_verify_origin(
    AxumState(server_cfg): AxumState<HttpServerConfig>,
    request: Request,
    next: Next,
) -> axum::response::Response {
    enforce_origin_policy(&server_cfg, OriginPolicy::AllowHeaderless, request, next).await
}

/// Rejects unsafe browser requests without trustworthy same-origin evidence.
async fn enforce_browser_same_origin(
    AxumState(server_cfg): AxumState<HttpServerConfig>,
    request: Request,
    next: Next,
) -> axum::response::Response {
    enforce_origin_policy(&server_cfg, OriginPolicy::RequireEvidence, request, next).await
}

/// Applies the given origin check policy to a request before invoking the next service.
async fn enforce_origin_policy(
    server_cfg: &HttpServerConfig,
    policy: OriginPolicy,
    request: Request,
    next: Next,
) -> axum::response::Response {
    // Check the request's origin evidence under the configured policy
    let allowed =
        match browser_request_allowed(server_cfg, request.method(), request.headers(), policy) {
            Ok(allowed) => allowed,
            Err(err) => {
                error!(error = %format_args!("{err:#}"), "error checking request origin");
                return StatusCode::INTERNAL_SERVER_ERROR.into_response();
            }
        };

    // Run the handler only for allowed requests
    if allowed {
        next.run(request).await
    } else {
        StatusCode::FORBIDDEN.into_response()
    }
}

/// Inserts the current commit SHA response header.
fn insert_commit_sha_header(headers: &mut axum::http::HeaderMap) {
    headers.insert(
        HeaderName::from_static(COMMIT_SHA_HEADER),
        HeaderValue::from_static(COMMIT_SHA),
    );
}

/// Middleware that redirects requests from old hosts to the base URL.
///
/// If the request's Host header matches any hostname in the configured `redirect_hosts`
/// list, the request is redirected with a 308 permanent redirect to the base URL.
async fn redirect_old_hosts(
    AxumState(server_cfg): AxumState<HttpServerConfig>,
    request: Request,
    next: Next,
) -> impl IntoResponse {
    if let Some(redirect_hosts) = &server_cfg.redirect_hosts
        && let Some(host) = request.headers().get(HOST).and_then(|h| h.to_str().ok())
    {
        // Strip port from host if present
        let host = host.split(':').next().unwrap_or(host);

        // Redirect if host matches any of the redirect hosts
        if redirect_hosts.iter().any(|h| h == host) {
            return Redirect::permanent(&server_cfg.base_url).into_response();
        }
    }
    next.run(request).await.into_response()
}

/// Middleware that refreshes dynamic clients loaded from an older application commit.
///
/// Static assets are excluded: browser and shared caches keep them across
/// deployments, so a commit SHA stored with a cached copy would go stale and
/// trigger reloads that never pick up a newer version.
async fn refresh_stale_clients(request: Request, next: Next) -> impl IntoResponse {
    // Serve static assets without deployment version tracking
    if request.uri().path().starts_with(STATIC_PATH_PREFIX) {
        return next.run(request).await;
    }

    // Refresh stale dynamic clients without running the handler
    let is_htmx = header_value_is_true(request.headers(), "hx-request");
    let is_ocg_fetch = header_value_is_true(request.headers(), "x-ocg-fetch");

    if (is_htmx || is_ocg_fetch) && request_has_stale_commit_sha(request.headers()) {
        return stale_client_refresh_response(is_htmx, is_ocg_fetch);
    }

    // Run the handler and report the current commit
    let mut response = next.run(request).await.into_response();
    insert_commit_sha_header(response.headers_mut());

    response
}

/// Returns whether the request came from a page loaded with an older commit.
fn request_has_stale_commit_sha(headers: &axum::http::HeaderMap) -> bool {
    headers
        .get(COMMIT_SHA_HEADER)
        .and_then(|value| value.to_str().ok())
        .is_some_and(|value| value != COMMIT_SHA)
}

/// Builds the refresh response returned to stale dynamic clients.
fn stale_client_refresh_response(is_htmx: bool, is_ocg_fetch: bool) -> axum::response::Response {
    let mut response = StatusCode::NO_CONTENT.into_response();
    let headers = response.headers_mut();
    headers.insert(
        CACHE_CONTROL,
        HeaderValue::from_static(CACHE_CONTROL_NO_STORE),
    );
    insert_commit_sha_header(headers);

    if is_htmx {
        headers.insert(
            HeaderName::from_static("hx-refresh"),
            HeaderValue::from_static("true"),
        );
    }
    if is_ocg_fetch {
        headers.insert(
            HeaderName::from_static(OCG_REFRESH_HEADER),
            HeaderValue::from_static("true"),
        );
    }

    response
}

/// Middleware that removes every `Set-Cookie` header from public responses.
///
/// Shared caches may store responses whose `Cache-Control` has the `public`
/// directive, so they must never carry a cookie. It wraps the session layer to
/// also drop the removal cookie written for an unknown session ID.
async fn strip_cookies_from_public_responses(
    request: Request,
    next: Next,
) -> axum::response::Response {
    // Run the inner layers and handler
    let mut response = next.run(request).await;

    // Keep cookies on responses shared caches must not store
    let is_public = response
        .headers()
        .get_all(CACHE_CONTROL)
        .iter()
        .filter_map(|value| value.to_str().ok())
        .flat_map(|value| value.split(','))
        .any(|directive| directive.trim().eq_ignore_ascii_case("public"));
    if !is_public {
        return response;
    }

    // Strip cookies from the public response
    let cookies = response.headers().get_all(SET_COOKIE).iter().count();
    if cookies > 0 {
        response.headers_mut().remove(SET_COOKIE);
        debug!(cookies, "stripped set-cookie headers from public response");
    }

    response
}

// Helpers.

/// Returns whether a request header has the string value `true`.
pub(crate) fn header_value_is_true(headers: &axum::http::HeaderMap, header_name: &str) -> bool {
    headers
        .get(header_name)
        .and_then(|value| value.to_str().ok())
        .is_some_and(|value| value.eq_ignore_ascii_case("true"))
}

/// Returns the `serde_qs` configuration for query string parsing.
pub(crate) fn serde_qs_config() -> serde_qs::Config {
    serde_qs::Config::new().max_depth(6).use_form_encoding(true)
}

/// Returns whether a request passes the origin check under `policy`.
///
/// Methods that cannot mutate application state are always allowed. Explicit
/// cross-site Fetch Metadata and foreign `Origin`/`Referer` headers are always
/// rejected. When `Sec-Fetch-Site`, `Origin`, and `Referer` are all absent,
/// [`OriginPolicy::RequireEvidence`] fails closed while
/// [`OriginPolicy::AllowHeaderless`] allows the request. Fails only when the
/// configured `base_url` cannot be used for the origin check.
fn browser_request_allowed(
    server_cfg: &HttpServerConfig,
    method: &Method,
    headers: &HeaderMap,
    policy: OriginPolicy,
) -> Result<bool> {
    // Allow methods that cannot mutate application state
    if matches!(
        *method,
        Method::GET | Method::HEAD | Method::OPTIONS | Method::TRACE
    ) {
        return Ok(true);
    }

    // Reject explicit cross-site Fetch Metadata on any header line
    let fetch_sites: Vec<_> = headers.get_all("sec-fetch-site").iter().collect();
    if fetch_sites.iter().any(|value| {
        value
            .to_str()
            .is_ok_and(|value| value.eq_ignore_ascii_case("cross-site"))
    }) {
        return Ok(false);
    }

    // Apply Fetch Metadata policy when origin headers are absent
    let has_explicit_origin = headers.contains_key(ORIGIN) || headers.contains_key(REFERER);
    if !has_explicit_origin {
        if fetch_sites.is_empty() {
            return Ok(policy == OriginPolicy::AllowHeaderless);
        }
        let all_same_origin = fetch_sites.iter().all(|value| {
            value
                .to_str()
                .is_ok_and(|value| value.eq_ignore_ascii_case("same-origin"))
        });
        return Ok(all_same_origin);
    }

    // Require explicit browser origin evidence to match the configured site
    request_headers_match_site_origin(server_cfg, headers)
}

/// Returns whether the configured base URL uses the HTTPS scheme.
fn is_https_base_url(base_url: &str) -> bool {
    base_url
        .get(..8)
        .is_some_and(|prefix| prefix.eq_ignore_ascii_case("https://"))
}

/// Opens the request span, carrying the request id so downstream log lines can be correlated.
fn make_request_span(request: &Request) -> Span {
    let request_id = request
        .headers()
        .get("x-request-id")
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default();

    info_span!(
        "request",
        method = %request.method(),
        uri = %request.uri(),
        version = ?request.version(),
        matched_path = request_matched_path(request),
        request_id,
    )
}

/// Returns the route template matched by the request, or `fallback` when no
/// route matched.
fn request_matched_path(request: &Request) -> &str {
    request
        .extensions()
        .get::<MatchedPath>()
        .map_or(ROUTE_FALLBACK_PATH, MatchedPath::as_str)
}
