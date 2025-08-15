//! HTTP routing configuration for the OCG server.
//!
//! This module sets up the Axum router with all application routes, middleware layers,
//! and static file handling.

use anyhow::Result;
use axum::{
    Router,
    extract::FromRef,
    http::{
        HeaderValue, StatusCode, Uri,
        header::{CACHE_CONTROL, CONTENT_TYPE},
    },
    response::IntoResponse,
    routing::{delete, get, post, put},
};
use axum_messages::MessagesManagerLayer;
use rust_embed::Embed;
use tower::ServiceBuilder;
use tower_http::{set_header::SetResponseHeaderLayer, trace::TraceLayer};
use tracing::instrument;

use crate::{
    config::HttpServerConfig,
    db::DynDB,
    handlers::{auth, community, dashboard, event, group},
};

/// Default cache duration for HTTP responses in seconds.
#[cfg(debug_assertions)]
pub(crate) const DEFAULT_CACHE_DURATION: usize = 0; // No cache
#[cfg(not(debug_assertions))]
pub(crate) const DEFAULT_CACHE_DURATION: usize = 60 * 5; // 5 minutes

/// Static file embedder using rust-embed.
///
/// Embeds all files from the static directory into the binary.
#[derive(Embed)]
#[folder = "dist/static"]
struct StaticFile;

/// Shared state for the router.
#[derive(Clone, FromRef)]
pub(crate) struct State {
    /// HTTP server configuration.
    pub cfg: HttpServerConfig,
    /// Database handle.
    pub db: DynDB,
    /// `serde_qs` config for query string parsing.
    pub serde_qs_de: serde_qs::Config,
}

/// Configures and returns the application router.
///
/// Sets up all routes, middleware layers, and shared state. Optionally adds basic
/// authentication if configured.
#[instrument(skip_all)]
pub(crate) async fn setup(cfg: &HttpServerConfig, db: DynDB) -> Result<Router> {
    // Setup router state
    let state = State {
        cfg: cfg.clone(),
        db: db.clone(),
        serde_qs_de: serde_qs::Config::new(3, false),
    };

    // Setup authentication layer
    let auth_layer = crate::auth::setup_layer(cfg, db).await?;

    // Setup sub-routers
    let community_dashboard_router = setup_community_dashboard_router();
    let group_dashboard_router = setup_group_dashboard_router();

    // Setup router
    let mut router = Router::new()
        .route("/", get(community::home::page))
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
        .route("/explore", get(community::explore::page))
        .route("/explore/events-section", get(community::explore::events_section))
        .route(
            "/explore/events-results-section",
            get(community::explore::events_results_section),
        )
        .route("/explore/groups-section", get(community::explore::groups_section))
        .route(
            "/explore/groups-results-section",
            get(community::explore::groups_results_section),
        )
        .route("/explore/events/search", get(community::explore::search_events))
        .route("/explore/groups/search", get(community::explore::search_groups))
        .route("/health-check", get(health_check))
        .route("/group/{group_slug}", get(group::page))
        .route("/group/{group_slug}/event/{event_slug}", get(event::page))
        .route("/log-in", get(auth::log_in_page));

    // Setup some routes based on the login options enabled
    if cfg.login.email {
        router = router
            .route("/log-in", post(auth::log_in))
            .route("/sign-up", post(auth::sign_up));
    }
    if cfg.login.github {
        router = router
            .route("/log-in/oauth2/{provider}", get(auth::oauth2_redirect))
            .route("/log-in/oauth2/{provider}/callback", get(auth::oauth2_callback));
    }
    if cfg.login.linuxfoundation {
        router = router
            .route("/log-in/oidc/{provider}", get(auth::oidc_redirect))
            .route("/log-in/oidc/{provider}/callback", get(auth::oidc_callback));
    }

    router = router
        .route("/log-out", get(auth::log_out))
        .route("/sign-up", get(auth::sign_up_page))
        .layer(MessagesManagerLayer)
        .layer(auth_layer)
        .layer(ServiceBuilder::new().layer(TraceLayer::new_for_http()))
        .route("/static/{*file}", get(static_handler))
        .layer(SetResponseHeaderLayer::if_not_present(
            CACHE_CONTROL,
            HeaderValue::try_from(format!("max-age={DEFAULT_CACHE_DURATION}")).expect("valid header value"),
        ));

    Ok(router.with_state(state))
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
    #[cfg(not(debug_assertions))]
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
    #[cfg(debug_assertions)]
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

/// Sets up the community dashboard router and its routes.
fn setup_community_dashboard_router() -> Router<State> {
    Router::new()
        .route("/", get(dashboard::community::home::page))
        .route("/groups", get(dashboard::community::groups::list_page))
        .route(
            "/groups/add",
            get(dashboard::community::groups::add_page).post(dashboard::community::groups::add),
        )
        .route(
            "/groups/{group_id}/update",
            get(dashboard::community::groups::update_page).put(dashboard::community::groups::update),
        )
        .route(
            "/groups/{group_id}/delete",
            delete(dashboard::community::groups::delete),
        )
        .route(
            "/settings/update",
            get(dashboard::community::settings::update_page).put(dashboard::community::settings::update),
        )
}

/// Sets up the group dashboard router and its routes.
fn setup_group_dashboard_router() -> Router<State> {
    Router::new()
        .route("/", get(dashboard::group::home::page))
        .route("/events", get(dashboard::group::events::list_page))
        .route(
            "/events/add",
            get(dashboard::group::events::add_page).post(dashboard::group::events::add),
        )
        .route(
            "/events/{event_id}/update",
            get(dashboard::group::events::update_page).put(dashboard::group::events::update),
        )
        .route(
            "/events/{event_id}/delete",
            delete(dashboard::group::events::delete),
        )
        .route(
            "/settings/update",
            get(dashboard::group::settings::update_page).put(dashboard::group::settings::update),
        )
}
