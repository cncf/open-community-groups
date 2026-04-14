//! HTTP routing configuration for the OCG server.
//!
//! This module sets up the Axum router with all application routes, middleware layers,
//! and static file handling.

mod dashboard;

#[cfg(test)]
mod tests;

use anyhow::Result;
use axum::{
    Router,
    extract::{FromRef, Request, State as AxumState},
    http::{
        HeaderValue, StatusCode, Uri,
        header::{CACHE_CONTROL, CONTENT_TYPE, HOST},
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
        auth::{self, LOG_IN_URL},
        community, event, group, images, meetings, payments, site,
    },
    services::{
        images::DynImageStorage, notifications::DynNotificationsManager, payments::DynPaymentsManager,
    },
};

/// Cache-Control header value instructing clients not to cache responses.
pub(crate) const CACHE_CONTROL_NO_CACHE: &str = "max-age=0, private, must-revalidate";
/// Cache-Control header value for favicon redirects.
const CACHE_CONTROL_FAVICON_REDIRECT: &str = "public, max-age=604800";

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
    // Check which meetings providers are configured
    let zoom_enabled = meetings_cfg.as_ref().is_some_and(|cfg| cfg.zoom.is_some());

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
    let auth_layer = crate::auth::setup_layer(server_cfg, db).await?;

    // Setup sub-routers
    let community_dashboard_router = dashboard::setup_community_dashboard_router(&state);
    let group_dashboard_router = dashboard::setup_group_dashboard_router(&state);
    let user_dashboard_router = dashboard::setup_user_dashboard_router();

    // Setup router
    // Routes that require login are placed before the login_required middleware layer.
    let mut router = Router::new()
        // Community-prefixed protected routes
        .route(
            "/{community}/check-in/{event_id}",
            get(event::check_in_page).post(event::check_in),
        )
        .route("/{community}/event/{event_id}/attend", post(event::attend_event))
        .route(
            "/{community}/event/{event_id}/checkout",
            post(event::start_checkout),
        )
        .route(
            "/{community}/event/{event_id}/attendance",
            get(event::attendance_status),
        )
        .route("/{community}/event/{event_id}/leave", delete(event::leave_event))
        .route(
            "/{community}/event/{event_id}/refund-request",
            post(event::request_refund),
        )
        .route(
            "/{community}/event/{event_id}/cfs-submissions",
            post(event::submit_cfs_submission),
        )
        .route("/{community}/group/{group_id}/join", post(group::join_group))
        .route("/{community}/group/{group_id}/leave", delete(group::leave_group))
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
        // Global site routes (no community prefix)
        .route("/", get(site::home::page))
        .route(
            "/apple-touch-icon-precomposed.png",
            get(|| async { StatusCode::NOT_FOUND }),
        )
        .route("/apple-touch-icon.png", get(|| async { StatusCode::NOT_FOUND }))
        .route("/docs", get(site::docs::page))
        .route("/explore", get(site::explore::page))
        .route("/explore/events-section", get(site::explore::events_section))
        .route(
            "/explore/events-results-section",
            get(site::explore::events_results_section),
        )
        .route("/explore/groups-section", get(site::explore::groups_section))
        .route(
            "/explore/groups-results-section",
            get(site::explore::groups_results_section),
        )
        .route("/explore/events/search", get(site::explore::search_events))
        .route("/explore/groups/search", get(site::explore::search_groups))
        .route("/favicon.ico", get(favicon))
        .route("/health-check", get(health_check))
        .route("/images/{file_name}", get(images::serve))
        .route("/log-in", get(auth::log_in_page))
        .route("/stats", get(site::stats::page))
        // Community-prefixed public routes
        .route("/{community}", get(community::page))
        .route("/{community}/group/{group_slug}", get(group::page))
        .route("/{community}/event/{event_id}/cfs-modal", get(event::cfs_modal))
        .route(
            "/{community}/group/{group_slug}/event/{event_slug}",
            get(event::page),
        )
        // Page view tracking routes
        .route("/communities/{community_id}/views", post(community::track_view))
        .route("/events/{event_id}/views", post(event::track_view))
        .route("/groups/{group_id}/views", post(group::track_view));

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
            .route("/log-in/oauth2/{provider}/callback", get(auth::oauth2_callback));
    }
    if server_cfg.login.linuxfoundation {
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
            HeaderValue::from_static(CACHE_CONTROL_NO_CACHE),
        ))
        .layer(middleware::from_fn_with_state(state.clone(), redirect_old_hosts));

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

    // Set cache duration based on resource type
    #[cfg(any(not(debug_assertions), test))]
    let cache_max_age = if path.starts_with("js/") || path.starts_with("css/") {
        // These assets are hashed
        60 * 60 * 24 * 365 // 1 year
    } else if path.starts_with("vendor/") {
        // Vendor libraries files include versions
        60 * 60 * 24 * 365 // 1 year
    } else if path.starts_with("images/") {
        60 * 60 * 24 * 7 // 1 week
    } else {
        // Default cache duration for other static resources
        60 * 60 // 1 hour
    };
    #[cfg(all(debug_assertions, not(test)))]
    let cache_max_age = 0;

    // Get file content and return it (if available)
    match StaticFile::get(path) {
        Some(file) => {
            let mime = mime_guess::from_path(path).first_or_octet_stream();
            let cache = format!("max-age={cache_max_age}");
            let headers = [(CONTENT_TYPE, mime.as_ref()), (CACHE_CONTROL, &cache)];
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

// Helpers.

/// Returns the `serde_qs` configuration for query string parsing.
pub(crate) fn serde_qs_config() -> serde_qs::Config {
    serde_qs::Config::new().max_depth(6).use_form_encoding(true)
}
