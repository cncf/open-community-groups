//! HTTP routing configuration for the OCG redirector.

use std::{collections::HashMap, sync::Arc};

use axum::{
    Router,
    extract::State as AxumState,
    http::{HeaderMap, StatusCode, Uri, header::HOST},
    response::{IntoResponse, Redirect},
    routing::get,
};
use tokio::sync::RwLock;
use tower_http::trace::TraceLayer;
use tracing::instrument;

use crate::config::HttpServerConfig;

/// Shared state for the router.
#[derive(Clone)]
pub(crate) struct State {
    /// Base URL used for matched redirects.
    pub base_redirect_url: Arc<str>,
    /// Redirect host suffix used to extract the alliance name.
    pub redirect_host_suffix: Arc<str>,
    /// Redirects keyed by alliance name and normalized legacy path.
    pub redirects: Arc<RwLock<Redirects>>,
}

/// Redirect alliances keyed by alliance name.
pub(crate) type Redirects = HashMap<String, AllianceRedirects>;

/// Redirect settings and mappings for one alliance.
#[derive(Clone, Debug, Default)]
pub(crate) struct AllianceRedirects {
    /// Base legacy URL used for unmatched redirect requests.
    pub base_legacy_url: Option<String>,
    /// Redirects keyed by normalized legacy path.
    pub redirects: HashMap<String, String>,
}

/// Configures and returns the application router.
#[instrument(skip_all)]
pub(crate) fn setup(redirects: Arc<RwLock<Redirects>>, server_cfg: &HttpServerConfig) -> Router {
    let state = State {
        base_redirect_url: Arc::<str>::from(server_cfg.base_redirect_url.trim_end_matches('/')),
        redirect_host_suffix: Arc::<str>::from(normalize_redirect_host_suffix(
            &server_cfg.redirect_host_suffix(),
        )),
        redirects,
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

/// Redirects the request to the canonical location or the alliance fallback.
#[instrument(skip_all)]
async fn redirect(
    AxumState(state): AxumState<State>,
    headers: HeaderMap,
    uri: Uri,
) -> impl IntoResponse {
    // Resolve the alliance from the redirector hostname
    let Some(alliance_name) = alliance_name_from_headers(&headers, &state.redirect_host_suffix)
    else {
        return StatusCode::NOT_FOUND.into_response();
    };

    // Normalize the request path for lookups
    let legacy_path = normalize_legacy_path(uri.path());

    // Resolve the target while borrowing the shared redirect map
    let redirect_target = {
        let redirects = state.redirects.read().await;
        let Some(alliance_redirects) = redirects.get(&alliance_name) else {
            return StatusCode::NOT_FOUND.into_response();
        };

        // Redirect root requests to the alliance page
        if legacy_path == "/" {
            alliance_redirect_target(&state.base_redirect_url, &alliance_name)
        // Redirect known legacy paths to their canonical target
        } else if let Some(new_path) = alliance_redirects.redirects.get(&legacy_path) {
            format!("{}{new_path}", state.base_redirect_url)
        // Fall back to the legacy site when the alliance still needs one
        } else if let Some(base_legacy_url) = &alliance_redirects.base_legacy_url {
            legacy_redirect_target(base_legacy_url, &uri)
        // Redirect unmatched paths to the alliance page when no legacy fallback is configured
        } else {
            alliance_redirect_target(&state.base_redirect_url, &alliance_name)
        }
    };

    Redirect::permanent(&redirect_target).into_response()
}

// Helpers.

/// Extracts the alliance name from the request host headers.
fn alliance_name_from_headers(headers: &HeaderMap, redirect_host_suffix: &str) -> Option<String> {
    let host = headers.get(HOST)?.to_str().ok()?;

    alliance_name_from_host(host, redirect_host_suffix)
}

/// Extracts the alliance name from a redirector host.
fn alliance_name_from_host(host: &str, redirect_host_suffix: &str) -> Option<String> {
    let host = normalize_host(host);
    let suffix = format!(".{redirect_host_suffix}");

    host.strip_suffix(&suffix)
        .filter(|alliance_name| !alliance_name.is_empty() && !alliance_name.contains('.'))
        .map(ToString::to_string)
}

/// Builds the fallback redirect target for a known alliance.
fn alliance_redirect_target(base_redirect_url: &str, alliance_name: &str) -> String {
    format!("{base_redirect_url}/{alliance_name}")
}

/// Builds the fallback redirect target from the original request.
fn legacy_redirect_target(base_legacy_url: &str, uri: &Uri) -> String {
    let base_legacy_url = base_legacy_url.trim_end_matches('/');
    let path_and_query = uri.path_and_query().map_or("/", |value| value.as_str());

    format!("{base_legacy_url}{path_and_query}")
}

/// Normalizes an incoming request host.
fn normalize_host(host: &str) -> String {
    let host = host.trim();
    let host = host.rsplit_once(':').map_or(host, |(host, _)| host);

    host.trim_end_matches('.').to_ascii_lowercase()
}

/// Normalizes legacy paths for lookups.
fn normalize_legacy_path(path: &str) -> String {
    let normalized_path = path.trim_end_matches('/');

    if normalized_path.is_empty() {
        "/".to_string()
    } else {
        normalized_path.to_string()
    }
}

/// Normalizes the configured redirect host suffix.
fn normalize_redirect_host_suffix(redirect_host_suffix: &str) -> String {
    redirect_host_suffix
        .trim()
        .trim_start_matches('.')
        .trim_end_matches('.')
        .to_ascii_lowercase()
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
    fn test_alliance_name_from_host_extracts_matching_subdomain() {
        assert_eq!(
            alliance_name_from_host("active-alliance.redirects.example", "redirects.example"),
            Some("active-alliance".to_string())
        );
        assert_eq!(
            alliance_name_from_host("ACTIVE-ALLIANCE.REDIRECTS.EXAMPLE:443", "redirects.example"),
            Some("active-alliance".to_string())
        );
        assert_eq!(
            alliance_name_from_host("active-alliance.redirects.example.", "redirects.example"),
            Some("active-alliance".to_string())
        );
    }

    #[test]
    fn test_alliance_name_from_host_rejects_unknown_hosts() {
        assert_eq!(
            alliance_name_from_host("redirects.example", "redirects.example"),
            None
        );
        assert_eq!(
            alliance_name_from_host(
                "nested.active-alliance.redirects.example",
                "redirects.example"
            ),
            None
        );
        assert_eq!(
            alliance_name_from_host("active-alliance.example", "redirects.example"),
            None
        );
    }

    #[test]
    fn test_normalize_legacy_path_trims_trailing_slashes() {
        assert_eq!(normalize_legacy_path("/groups/active/"), "/groups/active");
        assert_eq!(normalize_legacy_path("/events/active/"), "/events/active");
        assert_eq!(normalize_legacy_path("/"), "/");
    }

    #[tokio::test]
    async fn test_redirect_drops_query_string_from_lookup_and_target() {
        let router = test_router(test_alliance_redirects(HashMap::from([(
            "/events/legacy-event".to_string(),
            "/alliance/group/group/event/event".to_string(),
        )])));
        let response = router
            .oneshot(test_request("/events/legacy-event?utm_source=test"))
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/alliance/group/group/event/event")
        );
    }

    #[tokio::test]
    async fn test_redirect_normalizes_event_trailing_slash_lookup() {
        let router = test_router(test_alliance_redirects(HashMap::from([(
            "/events/legacy-event".to_string(),
            "/alliance/group/group/event/event".to_string(),
        )])));
        let response = router.oneshot(test_request("/events/legacy-event/")).await.unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/alliance/group/group/event/event")
        );
    }

    #[tokio::test]
    async fn test_redirects_event_match_to_canonical_url() {
        let router = test_router(test_alliance_redirects(HashMap::from([(
            "/events/legacy-event".to_string(),
            "/alliance/group/group/event/event".to_string(),
        )])));
        let response = router.oneshot(test_request("/events/legacy-event")).await.unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/alliance/group/group/event/event")
        );
    }

    #[tokio::test]
    async fn test_redirects_group_match_to_canonical_url() {
        let router = test_router(test_alliance_redirects(HashMap::from([(
            "/legacy-group".to_string(),
            "/alliance/group/group".to_string(),
        )])));
        let response = router.oneshot(test_request("/legacy-group")).await.unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/alliance/group/group")
        );
    }

    #[tokio::test]
    async fn test_redirects_root_to_alliance_page() {
        let router = test_router(test_alliance_redirects_with_legacy_fallback(HashMap::from(
            [(
                "/".to_string(),
                "/active-alliance/group/root-group".to_string(),
            )],
        )));
        let response = router.oneshot(test_request("/")).await.unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/active-alliance")
        );
    }

    #[tokio::test]
    async fn test_redirects_same_path_by_request_alliance() {
        let router = test_router(HashMap::from([
            (
                "active-alliance".to_string(),
                test_redirects(HashMap::from([(
                    "/groups/active".to_string(),
                    "/active-alliance/group/active-group".to_string(),
                )])),
            ),
            (
                "other-alliance".to_string(),
                test_redirects(HashMap::from([(
                    "/groups/active".to_string(),
                    "/other-alliance/group/active-group".to_string(),
                )])),
            ),
        ]));
        let response = router
            .oneshot(test_host_request(
                "/groups/active",
                "other-alliance.redirects.ocg.example",
            ))
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/other-alliance/group/active-group")
        );
    }

    #[tokio::test]
    async fn test_redirects_to_base_legacy_url_when_match_is_missing_and_fallback_is_configured() {
        let router = test_router(test_alliance_redirects_with_legacy_fallback(HashMap::new()));
        let response = router
            .oneshot(test_request("/missing/path/?utm_source=test"))
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://legacy.example/missing/path/?utm_source=test")
        );
    }

    #[tokio::test]
    async fn test_redirects_to_alliance_page_when_match_is_missing() {
        let router = test_router(test_alliance_redirects(HashMap::new()));
        let response = router.oneshot(test_request("/missing")).await.unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/active-alliance")
        );
    }

    #[tokio::test]
    async fn test_redirects_to_alliance_page_when_match_is_duplicated() {
        let router = test_router(test_alliance_redirects(HashMap::new()));
        let response = router.oneshot(test_request("/duplicate")).await.unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/active-alliance")
        );
    }

    #[tokio::test]
    async fn test_redirects_unknown_alliance_host_to_not_found() {
        let router = test_router(test_alliance_redirects(HashMap::new()));
        let response = router
            .oneshot(test_host_request("/missing", "unknown.example"))
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn test_redirects_unknown_mapped_alliance_to_not_found() {
        let router = test_router(HashMap::new());
        let response = router.oneshot(test_request("/missing")).await.unwrap();

        assert_eq!(response.status(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn test_redirects_use_trimmed_base_redirect_url() {
        let server_cfg = HttpServerConfig {
            addr: "127.0.0.1:9001".to_string(),
            base_redirect_url: "https://ocg.example/".to_string(),
        };
        let redirects = test_alliance_redirects(HashMap::from([(
            "/legacy-group".to_string(),
            "/alliance/group/group".to_string(),
        )]));
        let router = setup(Arc::new(RwLock::new(redirects)), &server_cfg);
        let response = router.oneshot(test_request("/legacy-group")).await.unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/alliance/group/group")
        );
    }

    // Helpers.

    /// Builds test redirects for the active alliance.
    fn test_alliance_redirects(redirects: HashMap<String, String>) -> Redirects {
        HashMap::from([("active-alliance".to_string(), test_redirects(redirects))])
    }

    /// Builds test redirects for the active alliance with a legacy fallback.
    fn test_alliance_redirects_with_legacy_fallback(
        redirects: HashMap<String, String>,
    ) -> Redirects {
        HashMap::from([(
            "active-alliance".to_string(),
            AllianceRedirects {
                base_legacy_url: Some("https://legacy.example/".to_string()),
                redirects,
            },
        )])
    }

    /// Builds test redirects without a legacy fallback.
    fn test_redirects(redirects: HashMap<String, String>) -> AllianceRedirects {
        AllianceRedirects {
            base_legacy_url: None,
            redirects,
        }
    }

    /// Builds a test request for the provided path.
    fn test_request(path: &str) -> Request<Body> {
        test_host_request(path, "active-alliance.redirects.ocg.example")
    }

    /// Builds a test request for the provided host and path.
    fn test_host_request(path: &str, host: &str) -> Request<Body> {
        Request::builder()
            .header(HOST, host)
            .uri(path)
            .body(Body::empty())
            .unwrap()
    }

    /// Sets up a router with the provided redirects and default configuration for testing.
    fn test_router(redirects: Redirects) -> Router {
        let server_cfg = HttpServerConfig {
            addr: "127.0.0.1:9001".to_string(),
            base_redirect_url: "https://ocg.example".to_string(),
        };

        setup(Arc::new(RwLock::new(redirects)), &server_cfg)
    }
}
