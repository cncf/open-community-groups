//! This module defines the router used to dispatch HTTP requests to the
//! corresponding handler.

use axum::{
    extract::FromRef,
    http::{
        header::{CACHE_CONTROL, CONTENT_TYPE},
        StatusCode, Uri,
    },
    response::IntoResponse,
    routing::get,
    Router,
};
use rust_embed::Embed;
use tower::ServiceBuilder;
use tower_http::trace::TraceLayer;
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{community, event, group},
};

/// Static files cache duration.
const STATIC_CACHE_MAX_AGE: usize = 365 * 24 * 60 * 60; // 1 year

/// Embed static files in the binary.
#[derive(Embed)]
#[folder = "static"]
struct StaticFile;

/// Router's state.
#[derive(Clone, FromRef)]
pub(crate) struct State {
    pub db: DynDB,
}

/// Setup router.
#[instrument(skip_all)]
pub(crate) fn setup(db: DynDB) -> Router {
    Router::new()
        .route("/", get(community::home::index))
        .route("/explore", get(community::explore::index))
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
        .route("/group/:group_slug", get(group::index))
        .route("/group/:group_slug/event/:event_slug", get(event::index))
        .route("/static/*file", get(static_handler))
        .layer(ServiceBuilder::new().layer(TraceLayer::new_for_http()))
        .with_state(State { db })
}

/// Handler that takes care of health check requests.
#[instrument(skip_all)]
async fn health_check() -> impl IntoResponse {
    StatusCode::OK
}

/// Handler that serves static files.
#[instrument]
async fn static_handler(uri: Uri) -> impl IntoResponse {
    // Extract file path from URI
    let mut path = uri.path().trim_start_matches('/').to_string();
    if path.starts_with("static/") {
        path = path.replace("static/", "");
    }

    // Get file content and return it (if available)
    match StaticFile::get(path.as_str()) {
        Some(file) => {
            let mime = mime_guess::from_path(path).first_or_octet_stream();
            let cache = format!("max-age={STATIC_CACHE_MAX_AGE}");
            let headers = [(CONTENT_TYPE, mime.as_ref()), (CACHE_CONTROL, &cache)];
            (headers, file.data).into_response()
        }
        None => StatusCode::NOT_FOUND.into_response(),
    }
}
