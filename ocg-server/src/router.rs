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
    middleware,
    response::IntoResponse,
    routing::{delete, get, post, put},
};
use axum_login::login_required;
use axum_messages::MessagesManagerLayer;
use rust_embed::Embed;
use tower::ServiceBuilder;
use tower_http::{set_header::SetResponseHeaderLayer, trace::TraceLayer};
use tracing::instrument;

use crate::{
    auth::AuthnBackend,
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        auth::{self, LOG_IN_URL},
        community, dashboard, event, group, images,
    },
    services::{images::DynImageStorage, notifications::DynNotificationsManager},
};

/// Cache-Control header value instructing clients not to cache responses.
pub(crate) const CACHE_CONTROL_NO_CACHE: &str = "max-age=0, private, must-revalidate";

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
    /// Image storage provider handle.
    pub image_storage: DynImageStorage,
    /// Notifications manager handle.
    pub notifications_manager: DynNotificationsManager,
    /// `serde_qs` config for query string parsing.
    pub serde_qs_de: serde_qs::Config,
}

/// Configures and returns the application router.
///
/// Sets up all routes, middleware layers, and shared state. Optionally adds basic
/// authentication if configured.
#[instrument(skip_all)]
pub(crate) async fn setup(
    cfg: &HttpServerConfig,
    db: DynDB,
    notifications_manager: DynNotificationsManager,
    image_storage: DynImageStorage,
) -> Result<Router> {
    // Setup router state
    let state = State {
        cfg: cfg.clone(),
        db: db.clone(),
        image_storage,
        notifications_manager,
        serde_qs_de: serde_qs::Config::new(3, false),
    };

    // Setup authentication layer
    let auth_layer = crate::auth::setup_layer(cfg, db).await?;

    // Setup sub-routers
    let community_dashboard_router = setup_community_dashboard_router(state.clone());
    let group_dashboard_router = setup_group_dashboard_router(state.clone());
    let user_dashboard_router = setup_user_dashboard_router();

    // Setup router
    let mut router = Router::new()
        .route(
            "/check-in/{event_id}",
            get(event::check_in_page).post(event::check_in),
        )
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
        .route("/event/{event_id}/attend", post(event::attend_event))
        .route("/event/{event_id}/attendance", get(event::attendance_status))
        .route("/event/{event_id}/leave", delete(event::leave_event))
        .route("/group/{group_id}/join", post(group::join_group))
        .route("/group/{group_id}/leave", delete(group::leave_group))
        .route("/group/{group_id}/membership", get(group::membership_status))
        .route("/images", post(images::upload))
        .route_layer(login_required!(
            AuthnBackend,
            login_url = LOG_IN_URL,
            redirect_field = "next_url"
        ))
        .route("/", get(community::home::page))
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
        .route("/images/{file_name}", get(images::serve))
        .route("/log-in", get(auth::log_in_page));

    // Setup some routes based on the login options enabled
    if cfg.login.email {
        router = router
            .route("/log-in", post(auth::log_in))
            .route("/sign-up", post(auth::sign_up))
            .route("/verify-email/{code}", get(auth::verify_email));
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
        .route("/section/user-menu", get(auth::user_menu_section))
        .route("/sign-up", get(auth::sign_up_page))
        .layer(MessagesManagerLayer)
        .layer(auth_layer)
        .layer(ServiceBuilder::new().layer(TraceLayer::new_for_http()))
        .route("/static/{*file}", get(static_handler))
        .layer(SetResponseHeaderLayer::if_not_present(
            CACHE_CONTROL,
            HeaderValue::from_static(CACHE_CONTROL_NO_CACHE),
        ));

    Ok(router.with_state(state))
}

/// Sets up the community dashboard router and its routes.
fn setup_community_dashboard_router(state: State) -> Router<State> {
    // Setup authorization middleware
    let check_user_owns_community = middleware::from_fn_with_state(state, auth::user_owns_community);

    // Setup router
    Router::new()
        .route("/", get(dashboard::community::home::page))
        .route("/analytics", get(dashboard::community::analytics::page))
        .route("/groups", get(dashboard::community::groups::list_page))
        .route(
            "/groups/add",
            get(dashboard::community::groups::add_page).post(dashboard::community::groups::add),
        )
        .route(
            "/groups/{group_id}/activate",
            put(dashboard::community::groups::activate),
        )
        .route(
            "/groups/{group_id}/deactivate",
            put(dashboard::community::groups::deactivate),
        )
        .route(
            "/groups/{group_id}/delete",
            delete(dashboard::community::groups::delete),
        )
        .route(
            "/groups/{group_id}/update",
            get(dashboard::community::groups::update_page).put(dashboard::community::groups::update),
        )
        .route(
            "/settings/update",
            get(dashboard::community::settings::update_page).put(dashboard::community::settings::update),
        )
        .route("/team", get(dashboard::community::team::list_page))
        .route("/team/add", post(dashboard::community::team::add))
        .route(
            "/team/{user_id}/delete",
            delete(dashboard::community::team::delete),
        )
        .route("/users/search", get(dashboard::common::search_user))
        .route_layer(check_user_owns_community)
}

/// Sets up the group dashboard router and its routes.
fn setup_group_dashboard_router(state: State) -> Router<State> {
    // Setup authorization middleware
    let check_user_belongs_to_any_group_team = middleware::from_fn(auth::user_belongs_to_any_group_team);
    let check_user_owns_group = middleware::from_fn_with_state(state, auth::user_owns_group);

    // Setup router
    Router::new()
        .route("/", get(dashboard::group::home::page))
        .route("/attendees", get(dashboard::group::attendees::list_page))
        .route(
            "/check-in/{event_id}/qr-code",
            get(dashboard::group::attendees::generate_check_in_qr_code),
        )
        .route("/events", get(dashboard::group::events::list_page))
        .route(
            "/events/add",
            get(dashboard::group::events::add_page).post(dashboard::group::events::add),
        )
        .route("/events/{event_id}/cancel", put(dashboard::group::events::cancel))
        .route(
            "/events/{event_id}/delete",
            delete(dashboard::group::events::delete),
        )
        .route(
            "/events/{event_id}/details",
            get(dashboard::group::events::details),
        )
        .route(
            "/events/{event_id}/publish",
            put(dashboard::group::events::publish),
        )
        .route(
            "/events/{event_id}/unpublish",
            put(dashboard::group::events::unpublish),
        )
        .route(
            "/events/{event_id}/update",
            get(dashboard::group::events::update_page).put(dashboard::group::events::update),
        )
        .route("/members", get(dashboard::group::members::list_page))
        .route(
            "/notifications",
            post(dashboard::group::members::send_group_custom_notification),
        )
        .route(
            "/notifications/{event_id}",
            post(dashboard::group::attendees::send_event_custom_notification),
        )
        .route(
            "/settings/update",
            get(dashboard::group::settings::update_page).put(dashboard::group::settings::update),
        )
        .route("/sponsors", get(dashboard::group::sponsors::list_page))
        .route(
            "/sponsors/add",
            get(dashboard::group::sponsors::add_page).post(dashboard::group::sponsors::add),
        )
        .route(
            "/sponsors/{group_sponsor_id}/delete",
            delete(dashboard::group::sponsors::delete),
        )
        .route(
            "/sponsors/{group_sponsor_id}/update",
            get(dashboard::group::sponsors::update_page).put(dashboard::group::sponsors::update),
        )
        .route("/team", get(dashboard::group::team::list_page))
        .route("/team/add", post(dashboard::group::team::add))
        .route("/team/{user_id}/delete", delete(dashboard::group::team::delete))
        .route("/team/{user_id}/role", put(dashboard::group::team::update_role))
        .route(
            "/{group_id}/select",
            put(dashboard::group::select_group).route_layer(check_user_owns_group),
        )
        .route("/users/search", get(dashboard::common::search_user))
        .route_layer(check_user_belongs_to_any_group_team)
}

/// Sets up the user dashboard router and its routes.
fn setup_user_dashboard_router() -> Router<State> {
    // Setup router
    Router::new()
        .route("/", get(dashboard::user::home::page))
        .route("/invitations", get(dashboard::user::invitations::list_page))
        .route(
            "/invitations/community/accept",
            put(dashboard::user::invitations::accept_community_team_invitation),
        )
        .route(
            "/invitations/community/reject",
            put(dashboard::user::invitations::reject_community_team_invitation),
        )
        .route(
            "/invitations/group/{group_id}/accept",
            put(dashboard::user::invitations::accept_group_team_invitation),
        )
        .route(
            "/invitations/group/{group_id}/reject",
            put(dashboard::user::invitations::reject_group_team_invitation),
        )
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

// Tests.

#[cfg(test)]
mod tests {
    use axum::{
        body::to_bytes,
        http::{HeaderValue, StatusCode, Uri},
    };

    use super::*;

    #[tokio::test]
    async fn test_health_check_returns_ok() {
        let response = health_check().await.into_response();
        let (parts, body) = response.into_parts();

        assert_eq!(parts.status, StatusCode::OK);
        assert!(to_bytes(body, usize::MAX).await.unwrap().is_empty());
    }

    #[tokio::test]
    async fn test_static_handler_serves_existing_asset() {
        let uri = Uri::from_static("/static/images/icons/arrow_left.svg");
        let response = static_handler(uri).await.into_response();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        assert_eq!(parts.status, StatusCode::OK);
        assert_eq!(
            parts.headers.get(CONTENT_TYPE).unwrap(),
            &HeaderValue::from_static("image/svg+xml")
        );
        assert_eq!(
            parts.headers.get(CACHE_CONTROL).unwrap(),
            &HeaderValue::from_static("max-age=0")
        );
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_static_handler_missing_asset_returns_not_found() {
        let uri = Uri::from_static("/static/does/not/exist.txt");
        let response = static_handler(uri).await.into_response();
        let (parts, body) = response.into_parts();

        assert_eq!(parts.status, StatusCode::NOT_FOUND);
        assert!(to_bytes(body, usize::MAX).await.unwrap().is_empty());
    }
}
