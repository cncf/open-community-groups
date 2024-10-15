//! This module defines the router used to dispatch HTTP requests to the
//! corresponding handler.

use crate::{
    db::DynDB,
    handlers::{community, event, group},
};
use axum::{extract::FromRef, http::StatusCode, response::IntoResponse, routing::get, Router};
use tower::ServiceBuilder;
use tower_http::trace::TraceLayer;

/// Router's state.
#[derive(Clone, FromRef)]
pub(crate) struct State {
    pub db: DynDB,
}

/// Setup router.
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
        .route("/health-check", get(health_check))
        .route("/group/:group_slug", get(group::index))
        .route("/group/:group_slug/event/:event_slug", get(event::index))
        .layer(ServiceBuilder::new().layer(TraceLayer::new_for_http()))
        .with_state(State { db })
}

/// Handler that takes care of health check requests.
async fn health_check() -> impl IntoResponse {
    StatusCode::OK
}
