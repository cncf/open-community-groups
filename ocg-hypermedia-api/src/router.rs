//! This module defines the router used to dispatch HTTP requests to the
//! corresponding handler.

use crate::{
    db::DynDB,
    handlers::{community, event, group},
};
use axum::{extract::FromRef, response::IntoResponse, routing::get, Router};
use tower::ServiceBuilder;
use tower_http::trace::TraceLayer;

/// Router's state.
#[derive(Clone, FromRef)]
pub(crate) struct State {
    pub db: DynDB,
}

/// Setup router.
pub(crate) fn setup(db: DynDB) -> Router {
    // Setup event page router
    let event_router = Router::new().route("/", get(event::index));

    // Setup group site router
    let group_router = Router::new()
        .route("/", get(group::index))
        .nest("/event/:event_slug", event_router);

    // Setup main router
    Router::new()
        .route("/", get(community::index))
        .route("/explore", get(community::explore))
        .route("/health-check", get(health_check))
        .nest("/group/:group_slug", group_router)
        .layer(ServiceBuilder::new().layer(TraceLayer::new_for_http()))
        .with_state(State { db })
}

/// Handler that takes care of health check requests.
async fn health_check() -> impl IntoResponse {
    ""
}
