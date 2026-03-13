//! HTTP routing configuration for the OCG redirector.

use std::{collections::HashMap, sync::Arc};

use axum::{
    Router,
    extract::State as AxumState,
    http::{StatusCode, Uri},
    response::{IntoResponse, Redirect},
    routing::get,
};
use tower_http::trace::TraceLayer;
use tracing::instrument;

use crate::config::HttpServerConfig;

/// Shared state for the router.
#[derive(Clone)]
pub(crate) struct State {
    /// Redirects keyed by normalized legacy path.
    pub redirects: Arc<HashMap<String, String>>,
    /// Base URL used for absolute redirects.
    pub base_redirect_url: Arc<str>,
}

/// Configures and returns the application router.
#[instrument(skip_all)]
pub(crate) fn setup(redirects: HashMap<String, String>, server_cfg: &HttpServerConfig) -> Router {
    let state = State {
        base_redirect_url: Arc::<str>::from(server_cfg.base_redirect_url.trim_end_matches('/')),
        redirects: Arc::new(redirects),
    };

    let router = Router::new()
        .route("/", get(redirect))
        .route("/health-check", get(health_check))
        .route("/{*path}", get(redirect))
        .layer(TraceLayer::new_for_http());

    router.with_state(state)
}

// Handlers.

/// Returns a success response when the service is healthy.
async fn health_check() -> impl IntoResponse {
    StatusCode::OK
}

/// Redirects the request to the canonical location or to the configured base redirect URL.
#[instrument(skip_all)]
async fn redirect(AxumState(state): AxumState<State>, uri: Uri) -> impl IntoResponse {
    // Normalize the request path for lookups
    let legacy_path = normalize_legacy_path(uri.path());

    // Redirect to the preloaded mapping when present
    if let Some(new_path) = state.redirects.get(&legacy_path) {
        return Redirect::permanent(&format!("{}{new_path}", state.base_redirect_url)).into_response();
    }

    Redirect::permanent(&state.base_redirect_url).into_response()
}

// Helpers.

/// Normalizes legacy paths for lookups.
fn normalize_legacy_path(path: &str) -> String {
    let normalized_path = path.trim_end_matches('/');

    if normalized_path.is_empty() {
        "/".to_string()
    } else {
        normalized_path.to_string()
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use axum::{
        body::Body,
        http::{HeaderValue, Request, StatusCode, header::LOCATION},
    };
    use tower::ServiceExt;

    use crate::config::HttpServerConfig;

    use super::*;

    #[tokio::test]
    async fn test_health_check_returns_ok() {
        let response = health_check().await.into_response();

        assert_eq!(response.status(), StatusCode::OK);
    }

    #[test]
    fn test_normalize_legacy_path_trims_trailing_slashes() {
        assert_eq!(normalize_legacy_path("/groups/active/"), "/groups/active");
        assert_eq!(normalize_legacy_path("/events/active/"), "/events/active");
        assert_eq!(normalize_legacy_path("/"), "/");
    }

    #[tokio::test]
    async fn test_redirect_drops_query_string_from_lookup_and_target() {
        let router = test_router(HashMap::from([(
            "/events/legacy-event".to_string(),
            "/community/group/group/event/event".to_string(),
        )]));
        let response = router
            .oneshot(test_request("/events/legacy-event?utm_source=test"))
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/community/group/group/event/event")
        );
    }

    #[tokio::test]
    async fn test_redirect_normalizes_event_trailing_slash_lookup() {
        let router = test_router(HashMap::from([(
            "/events/legacy-event".to_string(),
            "/community/group/group/event/event".to_string(),
        )]));
        let response = router.oneshot(test_request("/events/legacy-event/")).await.unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/community/group/group/event/event")
        );
    }

    #[tokio::test]
    async fn test_redirects_event_match_to_canonical_url() {
        let router = test_router(HashMap::from([(
            "/events/legacy-event".to_string(),
            "/community/group/group/event/event".to_string(),
        )]));
        let response = router.oneshot(test_request("/events/legacy-event")).await.unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/community/group/group/event/event")
        );
    }

    #[tokio::test]
    async fn test_redirects_group_match_to_canonical_url() {
        let router = test_router(HashMap::from([(
            "/legacy-group".to_string(),
            "/community/group/group".to_string(),
        )]));
        let response = router.oneshot(test_request("/legacy-group")).await.unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/community/group/group")
        );
    }

    #[tokio::test]
    async fn test_redirects_to_base_redirect_url_when_match_is_missing() {
        let router = test_router(HashMap::new());
        let response = router.oneshot(test_request("/missing")).await.unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example")
        );
    }

    #[tokio::test]
    async fn test_redirects_to_base_redirect_url_when_match_is_duplicated() {
        let router = test_router(HashMap::new());
        let response = router.oneshot(test_request("/duplicate")).await.unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example")
        );
    }

    #[tokio::test]
    async fn test_redirects_use_trimmed_base_redirect_url() {
        let server_cfg = HttpServerConfig {
            addr: "127.0.0.1:9001".to_string(),
            base_redirect_url: "https://ocg.example/".to_string(),
        };
        let router = setup(
            HashMap::from([("/legacy-group".to_string(), "/community/group/group".to_string())]),
            &server_cfg,
        );
        let response = router.oneshot(test_request("/legacy-group")).await.unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/community/group/group")
        );
    }

    // Helpers.

    /// Builds a test request for the provided path.
    fn test_request(path: &str) -> Request<Body> {
        Request::builder().uri(path).body(Body::empty()).unwrap()
    }

    /// Sets up a router with the provided redirects and default configuration for testing.
    fn test_router(redirects: HashMap<String, String>) -> Router {
        let server_cfg = HttpServerConfig {
            addr: "127.0.0.1:9001".to_string(),
            base_redirect_url: "https://ocg.example".to_string(),
        };

        setup(redirects, &server_cfg)
    }
}
