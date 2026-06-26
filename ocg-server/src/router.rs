//! HTTP routing configuration for the OCG server.
//!
//! This module sets up the Axum router with all application routes, middleware layers,
//! and static file handling.

mod api;
mod dashboard;

#[cfg(test)]
mod tests;

use anyhow::Result;
use axum::{
    Router,
    extract::{FromRef, Request, State as AxumState},
    http::{
        HeaderName, HeaderValue, StatusCode, Uri,
        header::{CACHE_CONTROL, CONTENT_TYPE, HOST, VARY},
    },
    middleware::{self, Next},
    response::{IntoResponse, Redirect},
    routing::{delete, get, post, put},
};
use axum_login::login_required;
use axum_messages::MessagesManagerLayer;
use rust_embed::Embed;
use tower::ServiceBuilder;
use tower_http::{set_header::SetResponseHeaderLayer, trace::TraceLayer};
use tracing::instrument;

use crate::{
    activity_tracker::DynActivityTracker,
    auth::AuthnBackend,
    config::{HttpServerConfig, MeetingsConfig, PaymentsConfig},
    db::DynDB,
    handlers::{
        alliance,
        auth::{self, LOG_IN_URL},
        event, group, images, meetings, payments, site,
    },
    services::{
        images::DynImageStorage, notifications::DynNotificationsManager,
        payments::DynPaymentsManager,
    },
};

/// Cache-Control header value for immutable public assets.
#[cfg(any(not(debug_assertions), test))]
pub(crate) const CACHE_CONTROL_IMMUTABLE: &str = "public, max-age=31536000, immutable";

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
const CACHE_CONTROL_FAVICON_REDIRECT: &str = "no-cache";

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

/// Headers for public shared-cache responses without additional headers.
pub(crate) const PUBLIC_SHARED_CACHE_HEADERS: [(HeaderName, &str); 2] = [
    (CACHE_CONTROL, CACHE_CONTROL_PUBLIC_SHARED),
    (VARY, PUBLIC_SHARED_CACHE_VARY),
];

/// Vary header value for public shared-cache responses.
pub(crate) const PUBLIC_SHARED_CACHE_VARY: &str = "x-ocg-commit-sha, hx-request, x-ocg-fetch";

/// Static file embedder using rust-embed.
///
/// Embeds all files from the static directory into the binary.
#[derive(Embed)]
#[folder = "dist/static"]
struct StaticFile;

/// Shared state for the router.
#[derive(Clone, FromRef)]
pub(crate) struct State {
    /// Activity tracker handle.
    pub activity_tracker: DynActivityTracker,
    /// Database handle.
    pub db: DynDB,
    /// Image storage provider handle.
    pub image_storage: DynImageStorage,
    /// Meetings configuration.
    pub meetings_cfg: Option<MeetingsConfig>,
    /// Notifications manager handle.
    pub notifications_manager: DynNotificationsManager,
    /// Payments configuration.
    pub payments_cfg: Option<PaymentsConfig>,
    /// Payments manager handle.
    pub payments_manager: DynPaymentsManager,
    /// `serde_qs` config for query string parsing.
    pub serde_qs_de: serde_qs::Config,
    /// HTTP server configuration.
    pub server_cfg: HttpServerConfig,
}

/// Configures and returns the application router.
///
/// Sets up all routes, middleware layers, and shared state. Optionally adds basic
/// authentication if configured.
#[allow(clippy::too_many_lines)]
#[allow(clippy::too_many_arguments)]
#[instrument(skip_all)]
pub(crate) async fn setup(
    activity_tracker: DynActivityTracker,
    db: DynDB,
    image_storage: DynImageStorage,
    meetings_cfg: Option<MeetingsConfig>,
    payments_cfg: Option<PaymentsConfig>,
    payments_manager: DynPaymentsManager,
    notifications_manager: DynNotificationsManager,
    server_cfg: &HttpServerConfig,
) -> Result<Router> {
    // Check whether the Zoom meetings provider is enabled
    let zoom_enabled = meetings_cfg
        .as_ref()
        .and_then(|cfg| cfg.zoom.as_ref())
        .is_some_and(|zoom_cfg| zoom_cfg.enabled);

    // Check whether a payments provider is configured
    let payments_enabled = payments_cfg.is_some();

    // Setup router state
    let state = State {
        db: db.clone(),
        activity_tracker,
        image_storage,
        meetings_cfg,
        notifications_manager,
        payments_cfg,
        payments_manager,
        serde_qs_de: serde_qs_config(),
        server_cfg: server_cfg.clone(),
    };

    // Setup authentication layer
    let auth_layer = crate::auth::setup_layer(server_cfg, db)?;

    // Setup sub-routers
    let api_router = api::setup_api_router();
    let alliance_dashboard_router = dashboard::setup_alliance_dashboard_router(&state);
    let group_dashboard_router = dashboard::setup_group_dashboard_router(&state);
    let user_dashboard_router = dashboard::setup_user_dashboard_router();

    // Setup router
    // Routes that require login are placed before the login_required middleware layer.
    let mut router = Router::new()
        // Alliance-prefixed protected routes
        .route(
            "/{alliance}/check-in/{event_id}",
            get(event::check_in_page).post(event::check_in),
        )
        .route(
            "/{alliance}/event/{event_id}/attend",
            post(event::attend_event),
        )
        .route(
            "/{alliance}/event/{event_id}/checkout",
            delete(event::cancel_checkout).post(event::start_checkout),
        )
        .route(
            "/{alliance}/event/{event_id}/attendance",
            get(event::attendance_status),
        )
        .route(
            "/{alliance}/event/{event_id}/leave",
            delete(event::leave_event),
        )
        .route(
            "/{alliance}/event/{event_id}/refund-request",
            post(event::request_refund),
        )
        .route(
            "/{alliance}/event/{event_id}/cfs-submissions",
            post(event::submit_cfs_submission),
        )
        .route("/{alliance}/group/{group_id}/join", post(group::join_group))
        .route(
            "/{alliance}/group/{group_id}/leave",
            delete(group::leave_group),
        )
        .route(
            "/{alliance}/group/{group_id}/membership",
            get(group::membership_status),
        )
        .route(
            "/{alliance}/group/{group_slug}/spotlights",
            get(group::spotlights_page),
        )
        .route(
            "/{alliance}/group/{group_slug}/members",
            get(group::members_page),
        )
        .route("/jobs/{job_id}/apply", post(site::jobs::apply))
        .route(
            "/profiles/{username}/mentorship-requests",
            post(site::profile::request_mentorship),
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
        .route(
            "/dashboard",
            get(|| async { Redirect::to("/dashboard/user") }),
        )
        .route(
            "/dashboard/jobs",
            get(crate::handlers::dashboard::jobs::page).post(crate::handlers::dashboard::jobs::add),
        )
        .route(
            "/dashboard/jobs/{job_id}",
            put(crate::handlers::dashboard::jobs::update)
                .delete(crate::handlers::dashboard::jobs::delete),
        )
        .route(
            "/dashboard/jobs/{job_id}/publish",
            put(crate::handlers::dashboard::jobs::publish),
        )
        .route(
            "/dashboard/jobs/{job_id}/unpublish",
            put(crate::handlers::dashboard::jobs::unpublish),
        )
        .nest("/dashboard/alliance", alliance_dashboard_router)
        .nest("/dashboard/group", group_dashboard_router)
        .nest("/dashboard/user", user_dashboard_router)
        // Protected image upload
        .route("/images", post(images::upload))
        .route_layer(login_required!(
            AuthnBackend,
            login_url = LOG_IN_URL,
            redirect_field = "next_url"
        ))
        .nest("/api/v1", api_router)
        // Global site routes (no alliance prefix)
        .route("/", get(site::home::page))
        .route(
            "/apple-touch-icon-precomposed.png",
            get(|| async { StatusCode::NOT_FOUND }),
        )
        .route(
            "/apple-touch-icon.png",
            get(|| async { StatusCode::NOT_FOUND }),
        )
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
        .route("/explore/groups/search", get(site::explore::search_groups))
        .route("/favicon.ico", get(favicon))
        .route("/health-check", get(health_check))
        .route("/images/og/{file_name}", get(images::serve_open_graph))
        .route("/images/{file_name}", get(images::serve))
        .route("/log-in", get(auth::log_in_page))
        .route("/about", get(site::about::page))
        .route("/docs", get(site::docs::index))
        .route("/docs/{*doc_path}", get(site::docs::page))
        .route("/jobs", get(site::jobs::page))
        .route("/jobs/{slug}", get(site::jobs::details))
        .route("/landscape", get(site::landscape::page))
        .route("/privacy", get(site::privacy::page))
        .route("/profiles/{username}", get(site::profile::page))
        .route("/search", get(site::search::page))
        .route(
            "/sponsor",
            get(site::sponsor::page).post(site::sponsor::submit),
        )
        .route("/stats", get(site::stats::page))
        .route("/wiki", get(site::wiki::page))
        // Alliance-prefixed public routes
        .route("/{alliance}/brand", get(alliance::brand_page))
        .route("/{alliance}/members", get(alliance::members_page))
        .route("/{alliance}", get(alliance::page))
        .route(
            "/{alliance}/group/{group_slug}/store",
            get(group::store_page),
        )
        .route("/{alliance}/group/{group_slug}", get(group::page))
        .route(
            "/{alliance}/event/{event_id}/cfs-modal",
            get(event::cfs_modal),
        )
        .route(
            "/{alliance}/group/{group_slug}/event/{event_slug}/availability",
            get(event::availability),
        )
        .route(
            "/{alliance}/group/{group_slug}/event/{event_slug}",
            get(event::page),
        )
        // Page view tracking routes
        .route("/alliances/{alliance_id}/views", post(alliance::track_view))
        .route("/events/{event_id}/views", post(event::track_view))
        .route("/groups/{group_id}/views", post(group::track_view))
        .fallback(site::not_found::page);

    // Setup some routes based on the login options enabled
    if server_cfg.login.email {
        router = router
            .route("/log-in", post(auth::log_in))
            .route("/sign-up", post(auth::sign_up))
            .route("/verify-email/{code}", get(auth::verify_email));
    }
    if server_cfg.login.github {
        router = router
            .route("/log-in/oauth2/{provider}", get(auth::oauth2_redirect))
            .route(
                "/log-in/oauth2/{provider}/callback",
                get(auth::oauth2_callback),
            );
    }
    if server_cfg.login.linkedin {
        router = router
            .route("/log-in/oidc/{provider}", get(auth::oidc_redirect))
            .route("/log-in/oidc/{provider}/callback", get(auth::oidc_callback));
    }

    router = router
        .route("/log-out", get(auth::log_out))
        .route("/section/user-menu", get(auth::user_menu_section))
        .route("/sign-up", get(auth::sign_up_page));

    // Setup Zoom webhook route if enabled in configuration
    if zoom_enabled {
        router = router.route("/webhooks/zoom", post(meetings::zoom_event));
    }

    // Setup the payments webhook route if enabled in configuration
    if payments_enabled {
        router = router.route("/webhooks/payments", post(payments::webhook));
    }

    router = router
        .layer(MessagesManagerLayer)
        .layer(auth_layer)
        .layer(ServiceBuilder::new().layer(TraceLayer::new_for_http()))
        .route("/static/{*file}", get(static_handler))
        .layer(SetResponseHeaderLayer::if_not_present(
            CACHE_CONTROL,
            HeaderValue::from_static(CACHE_CONTROL_PRIVATE_NO_STORE),
        ))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            redirect_old_hosts,
        ))
        .layer(middleware::from_fn(refresh_stale_clients));

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
/// Returns 200 OK for monitoring and load balancer health checks.
#[instrument(skip_all)]
async fn health_check() -> impl IntoResponse {
    StatusCode::OK
}

/// Static file handler for embedded assets.
///
/// Serves files embedded in the binary with appropriate MIME types and cache headers.
#[instrument]
async fn static_handler(uri: Uri) -> impl IntoResponse {
    // Extract file path from URI
    let path = uri.path().trim_start_matches("/static/");

    // Set cache policy based on resource type
    #[cfg(any(not(debug_assertions), test))]
    let cache = if path.starts_with("js/") || path.starts_with("css/") {
        // These assets are hashed.
        CACHE_CONTROL_IMMUTABLE
    } else if path.starts_with("vendor/") {
        // Vendor library files include versions.
        CACHE_CONTROL_IMMUTABLE
    } else if path.starts_with("images/") {
        CACHE_CONTROL_STATIC_IMAGES
    } else {
        // Default cache duration for other static resources.
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

/// Middleware that redirects requests from old hosts to the base URL.
///
/// If the request's Host header matches any hostname in the configured `redirect_hosts`
/// list, the request is redirected with a 301 permanent redirect to the base URL.
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
async fn refresh_stale_clients(request: Request, next: Next) -> impl IntoResponse {
    let is_htmx = header_value_is_true(request.headers(), "hx-request");
    let is_ocg_fetch = header_value_is_true(request.headers(), "x-ocg-fetch");

    if (is_htmx || is_ocg_fetch) && request_has_stale_commit_sha(request.headers()) {
        return stale_client_refresh_response(is_htmx, is_ocg_fetch);
    }

    let mut response = next.run(request).await.into_response();
    insert_commit_sha_header(response.headers_mut());

    response
}

/// Returns whether a request header has the string value `true`.
fn header_value_is_true(headers: &axum::http::HeaderMap, header_name: &str) -> bool {
    headers
        .get(header_name)
        .and_then(|value| value.to_str().ok())
        .is_some_and(|value| value.eq_ignore_ascii_case("true"))
}

/// Inserts the current commit SHA response header.
fn insert_commit_sha_header(headers: &mut axum::http::HeaderMap) {
    headers.insert(
        HeaderName::from_static(COMMIT_SHA_HEADER),
        HeaderValue::from_static(COMMIT_SHA),
    );
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

// Helpers.

/// Returns the `serde_qs` configuration for query string parsing.
pub(crate) fn serde_qs_config() -> serde_qs::Config {
    serde_qs::Config::new().max_depth(6).use_form_encoding(true)
}
