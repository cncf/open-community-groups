//! This module defines the router used to dispatch HTTP requests.

use crate::db::DynDB;
use axum::{extract::FromRef, response::IntoResponse, routing::get, Router};
use tower::ServiceBuilder;
use tower_http::trace::TraceLayer;

/// Router's state.
#[derive(Clone, FromRef)]
struct RouterState {
    db: DynDB,
}

/// Setup router.
pub(crate) fn setup(db: DynDB) -> Router {
    Router::new()
        .route("/health-check", get(health_check))
        .layer(ServiceBuilder::new().layer(TraceLayer::new_for_http()))
        .with_state(RouterState { db })
}

/// Handler that takes care of health check requests.
async fn health_check() -> impl IntoResponse {
    ""
}
