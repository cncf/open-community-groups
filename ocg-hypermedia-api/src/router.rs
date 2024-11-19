//! This module defines the router used to dispatch HTTP requests to the
//! corresponding handler.

use std::path::Path;

use anyhow::Result;
use axum::{
    extract::FromRef,
    http::{header::CACHE_CONTROL, HeaderValue, StatusCode},
    response::IntoResponse,
    routing::{get, get_service},
    Router,
};
use tower::ServiceBuilder;
use tower_http::{services::ServeDir, set_header::SetResponseHeader, trace::TraceLayer};

use crate::{
    db::DynDB,
    handlers::{community, event, group},
};

/// Static files cache duration.
const STATIC_CACHE_MAX_AGE: usize = 365 * 24 * 60 * 60; // 1 year

/// Router's state.
#[derive(Clone, FromRef)]
pub(crate) struct State {
    pub db: DynDB,
}

/// Setup router.
pub(crate) fn setup(static_dir: &Path, db: DynDB) -> Result<Router> {
    let router = Router::new()
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
        .route("/health-check", get(health_check))
        .route("/group/:group_slug", get(group::index))
        .route("/group/:group_slug/event/:event_slug", get(event::index))
        .nest_service(
            "/static",
            get_service(SetResponseHeader::overriding(
                ServeDir::new(static_dir),
                CACHE_CONTROL,
                HeaderValue::try_from(format!("max-age={STATIC_CACHE_MAX_AGE}"))?,
            )),
        )
        .layer(ServiceBuilder::new().layer(TraceLayer::new_for_http()))
        .with_state(State { db });

    Ok(router)
}

/// Handler that takes care of health check requests.
async fn health_check() -> impl IntoResponse {
    StatusCode::OK
}
