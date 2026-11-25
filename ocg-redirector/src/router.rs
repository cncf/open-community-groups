//! HTTP routing configuration for the OCG redirector.

use std::{collections::HashMap, net::Ipv6Addr, str::FromStr, sync::Arc};

use axum::{
    Router,
    extract::{Request, State as AxumState},
    http::{HeaderMap, HeaderValue, StatusCode, Uri, header::HOST, uri::Scheme},
    response::{IntoResponse, Redirect},
    routing::get,
};
use tokio::sync::RwLock;
use tokio_util::sync::CancellationToken;
use tower::ServiceBuilder;
use tower_http::{
    request_id::{MakeRequestUuid, PropagateRequestIdLayer, SetRequestIdLayer},
    trace::TraceLayer,
};
use tracing::{Span, info_span, instrument};

use crate::config::HttpServerConfig;

/// Shared state for the router.
#[derive(Clone)]
pub(crate) struct State {
    /// Base URL used for matched redirects.
    pub base_redirect_url: Arc<str>,
    /// Redirect host suffix used to extract the community name.
    pub redirect_host_suffix: Arc<str>,
    /// Redirects keyed by community name and normalized legacy path.
    pub redirects: Arc<RwLock<Redirects>>,
    /// Token cancelled when the server starts draining traffic before shutdown.
    pub shutdown_drain: CancellationToken,
}

/// Redirect communities keyed by community name.
pub(crate) type Redirects = HashMap<String, CommunityRedirects>;

/// Redirect settings and mappings for one community.
#[derive(Clone, Debug, Default)]
pub(crate) struct CommunityRedirects {
    /// Redirects keyed by normalized legacy path.
    pub redirects: HashMap<String, String>,

    /// Base legacy URL used for unmatched redirect requests.
    pub base_legacy_url: Option<String>,
}

/// Returns whether the provided URL is an absolute HTTP(S) URL without
/// userinfo, query, fragment, malformed port, or invalid header characters.
pub(crate) fn is_valid_http_url(value: &str) -> bool {
    // Reject fragments and non-header characters because `http::Uri` ignores fragments
    if value.contains('#') || HeaderValue::from_str(value).is_err() {
        return false;
    }

    // Parse and require an HTTP(S) scheme without a query string
    let Ok(uri) = Uri::from_str(value) else {
        return false;
    };
    if !matches!(uri.scheme(), Some(scheme) if *scheme == Scheme::HTTP || *scheme == Scheme::HTTPS)
        || uri.query().is_some()
    {
        return false;
    }

    // Validate authority has a nonempty host (valid IPv6 when bracketed), no userinfo,
    // and a valid optional decimal port
    let Some(authority) = uri.authority() else {
        return false;
    };
    let authority_str = authority.as_str();
    let host = authority.host();
    if host.is_empty() || authority_str.contains('@') {
        return false;
    }
    if let Some(ipv6) = host.strip_prefix('[').and_then(|h| h.strip_suffix(']'))
        && ipv6.parse::<Ipv6Addr>().is_err()
    {
        return false;
    }
    if authority_str.len() != host.len() {
        let Some(port_str) = authority_str
            .strip_prefix(host)
            .and_then(|rest| rest.strip_prefix(':'))
        else {
            return false;
        };
        if port_str.is_empty()
            || !port_str.bytes().all(|byte| byte.is_ascii_digit())
            || authority.port_u16().is_none()
        {
            return false;
        }
    }

    true
}

/// Returns whether the provided redirect path is a safe root-relative path.
pub(crate) fn is_valid_redirect_path(path: &str) -> bool {
    path.starts_with('/')
        && !path.starts_with("//")
        && !path.contains('#')
        && HeaderValue::from_str(path).is_ok()
        && Uri::from_str(path).is_ok_and(|uri| uri.scheme().is_none() && uri.authority().is_none())
}

/// Configures and returns the application router.
#[instrument(skip_all)]
pub(crate) fn setup(
    redirects: Arc<RwLock<Redirects>>,
    server_cfg: &HttpServerConfig,
    shutdown_drain: CancellationToken,
) -> Router {
    let state = State {
        base_redirect_url: Arc::<str>::from(server_cfg.base_redirect_url.trim_end_matches('/')),
        redirect_host_suffix: Arc::<str>::from(normalize_redirect_host_suffix(
            &server_cfg.redirect_host_suffix(),
        )),
        redirects,
        shutdown_drain,
    };

    let router = Router::new()
        .route("/", get(redirect))
        .route("/health-check", get(health_check))
        .route("/{*path}", get(redirect))
        .layer(
            // Assign a request id, open the request span carrying it, and echo it in the response
            ServiceBuilder::new()
                .layer(SetRequestIdLayer::x_request_id(MakeRequestUuid))
                .layer(TraceLayer::new_for_http().make_span_with(make_request_span))
                .layer(PropagateRequestIdLayer::x_request_id()),
        );

    router.with_state(state)
}

// Handlers.

/// Returns a success response when the service is healthy, or 503 while the
/// server drains traffic before shutdown.
async fn health_check(AxumState(state): AxumState<State>) -> impl IntoResponse {
    if state.shutdown_drain.is_cancelled() {
        return StatusCode::SERVICE_UNAVAILABLE;
    }

    StatusCode::OK
}

/// Redirects the request to the canonical location or the community fallback.
#[instrument(skip_all)]
async fn redirect(
    AxumState(state): AxumState<State>,
    headers: HeaderMap,
    uri: Uri,
) -> impl IntoResponse {
    // Resolve the community from the redirector hostname
    let Some(community_name) = community_name_from_headers(&headers, &state.redirect_host_suffix)
    else {
        return StatusCode::NOT_FOUND.into_response();
    };

    // Normalize the request path for lookups
    let legacy_path = normalize_legacy_path(uri.path());

    // Resolve the target while borrowing the shared redirect map
    let redirect_target = {
        let redirects = state.redirects.read().await;
        let Some(community_redirects) = redirects.get(&community_name) else {
            return StatusCode::NOT_FOUND.into_response();
        };

        // Redirect root requests to the community page
        if legacy_path == "/" {
            community_redirect_target(&state.base_redirect_url, &community_name)
        // Redirect known legacy paths to their canonical target, re-validating as
        // defense-in-depth in case `Redirects` was built outside `db::load_redirects`
        } else if let Some(new_path) = community_redirects
            .redirects
            .get(&legacy_path)
            .filter(|path| is_valid_redirect_path(path))
        {
            format!("{}{new_path}", state.base_redirect_url)
        // Fall back to the legacy site when configured and still valid
        } else if let Some(base_legacy_url) = community_redirects
            .base_legacy_url
            .as_deref()
            .filter(|url| is_valid_http_url(url))
        {
            legacy_redirect_target(base_legacy_url, &uri)
        // Redirect unmatched paths to the community page when no legacy fallback is configured
        } else {
            community_redirect_target(&state.base_redirect_url, &community_name)
        }
    };

    Redirect::permanent(&redirect_target).into_response()
}

// Helpers.

/// Extracts the community name from the request host headers.
fn community_name_from_headers(headers: &HeaderMap, redirect_host_suffix: &str) -> Option<String> {
    let host = headers.get(HOST)?.to_str().ok()?;

    community_name_from_host(host, redirect_host_suffix)
}

/// Extracts the community name from a redirector host.
fn community_name_from_host(host: &str, redirect_host_suffix: &str) -> Option<String> {
    let host = normalize_host(host);

    host.strip_suffix(redirect_host_suffix)
        .and_then(|community_name| community_name.strip_suffix('.'))
        .filter(|community_name| !community_name.is_empty() && !community_name.contains('.'))
        .map(ToString::to_string)
}

/// Builds the fallback redirect target for a known community.
fn community_redirect_target(base_redirect_url: &str, community_name: &str) -> String {
    format!("{base_redirect_url}/{community_name}")
}

/// Builds the fallback redirect target from the original request.
fn legacy_redirect_target(base_legacy_url: &str, uri: &Uri) -> String {
    let base_legacy_url = base_legacy_url.trim_end_matches('/');
    let path_and_query = uri.path_and_query().map_or("/", |value| value.as_str());

    format!("{base_legacy_url}{path_and_query}")
}

/// Opens the request span, carrying the request id so downstream log lines can be correlated.
fn make_request_span(request: &Request) -> Span {
    let request_id = request
        .headers()
        .get("x-request-id")
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default();

    info_span!(
        "request",
        method = %request.method(),
        uri = %request.uri(),
        version = ?request.version(),
        request_id,
    )
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
        let router = test_router(Redirects::new());
        let response = router.oneshot(test_request("/health-check")).await.unwrap();

        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn test_health_check_returns_service_unavailable_while_draining() {
        // Setup a router whose drain token has already been cancelled
        let shutdown_drain = CancellationToken::new();
        shutdown_drain.cancel();
        let router = setup(
            Arc::new(RwLock::new(Redirects::new())),
            &test_server_cfg(),
            shutdown_drain,
        );

        // Check health checks fail while draining
        let response = router.oneshot(test_request("/health-check")).await.unwrap();
        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    }

    #[test]
    fn test_community_name_from_host_extracts_matching_subdomain() {
        assert_eq!(
            community_name_from_host("active-community.redirects.example", "redirects.example"),
            Some("active-community".to_string())
        );
        assert_eq!(
            community_name_from_host(
                "ACTIVE-COMMUNITY.REDIRECTS.EXAMPLE:443",
                "redirects.example"
            ),
            Some("active-community".to_string())
        );
        assert_eq!(
            community_name_from_host("active-community.redirects.example.", "redirects.example"),
            Some("active-community".to_string())
        );
    }

    #[test]
    fn test_community_name_from_host_rejects_unknown_hosts() {
        assert_eq!(
            community_name_from_host("redirects.example", "redirects.example"),
            None
        );
        assert_eq!(
            community_name_from_host(
                "nested.active-community.redirects.example",
                "redirects.example"
            ),
            None
        );
        assert_eq!(
            community_name_from_host("active-community.example", "redirects.example"),
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
        let router = legacy_event_router();
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
    async fn test_redirect_ignores_invalid_new_path_and_invalid_base_legacy_url() {
        // Setup a community with unsafe new_path targets (including a fragment with control chars)
        // and an unsafe base_legacy_url
        let router = test_router(HashMap::from([(
            "active-community".to_string(),
            CommunityRedirects {
                redirects: HashMap::from([
                    (
                        "/unsafe-path".to_string(),
                        "//evil.example/phish".to_string(),
                    ),
                    (
                        "/fragment-control".to_string(),
                        "/cncf#\r\nX-Injected: 1".to_string(),
                    ),
                ]),

                base_legacy_url: Some("https://legacy.example:bad".to_string()),
            },
        )]));

        // Check both unsafe targets fall back cleanly to the community page
        for path in ["/unsafe-path", "/fragment-control"] {
            let response = router.clone().oneshot(test_request(path)).await.unwrap();
            assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT, "{path}");
            assert_eq!(
                response.headers().get(LOCATION).unwrap(),
                &HeaderValue::from_static("https://ocg.example/active-community"),
                "{path}"
            );
        }
    }

    #[tokio::test]
    async fn test_redirect_normalizes_event_trailing_slash_lookup() {
        let router = legacy_event_router();
        let response = router.oneshot(test_request("/events/legacy-event/")).await.unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/community/group/group/event/event")
        );
    }

    #[tokio::test]
    async fn test_redirects_event_match_to_canonical_url() {
        let router = legacy_event_router();
        let response = router.oneshot(test_request("/events/legacy-event")).await.unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/community/group/group/event/event")
        );
    }

    #[tokio::test]
    async fn test_redirects_group_match_to_canonical_url() {
        let router = test_router(test_community_redirects(HashMap::from([(
            "/legacy-group".to_string(),
            "/community/group/group".to_string(),
        )])));
        let response = router.oneshot(test_request("/legacy-group")).await.unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/community/group/group")
        );
    }

    #[tokio::test]
    async fn test_redirects_root_to_community_page() {
        let router = test_router(test_community_redirects_with_legacy_fallback(
            HashMap::from([(
                "/".to_string(),
                "/active-community/group/root-group".to_string(),
            )]),
        ));
        let response = router.oneshot(test_request("/")).await.unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/active-community")
        );
    }

    #[tokio::test]
    async fn test_redirects_same_path_by_request_community() {
        let router = test_router(HashMap::from([
            (
                "active-community".to_string(),
                test_redirects(HashMap::from([(
                    "/groups/active".to_string(),
                    "/active-community/group/active-group".to_string(),
                )])),
            ),
            (
                "other-community".to_string(),
                test_redirects(HashMap::from([(
                    "/groups/active".to_string(),
                    "/other-community/group/active-group".to_string(),
                )])),
            ),
        ]));
        let response = router
            .oneshot(test_host_request(
                "/groups/active",
                "other-community.redirects.ocg.example",
            ))
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/other-community/group/active-group")
        );
    }

    #[tokio::test]
    async fn test_redirects_to_base_legacy_url_when_match_is_missing_and_fallback_is_configured() {
        let router = test_router(test_community_redirects_with_legacy_fallback(HashMap::new()));
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
    async fn test_redirects_to_community_page_when_match_is_missing() {
        let router = test_router(test_community_redirects(HashMap::new()));
        let response = router.oneshot(test_request("/missing")).await.unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/active-community")
        );
    }

    #[tokio::test]
    async fn test_redirects_unknown_community_host_to_not_found() {
        let router = test_router(test_community_redirects(HashMap::new()));
        let response = router
            .oneshot(test_host_request("/missing", "unknown.example"))
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn test_redirects_unknown_mapped_community_to_not_found() {
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
        let redirects = test_community_redirects(HashMap::from([(
            "/legacy-group".to_string(),
            "/community/group/group".to_string(),
        )]));
        let router = setup(
            Arc::new(RwLock::new(redirects)),
            &server_cfg,
            CancellationToken::new(),
        );
        let response = router.oneshot(test_request("/legacy-group")).await.unwrap();

        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/community/group/group")
        );
    }

    #[tokio::test]
    async fn test_request_id_is_generated_when_missing_and_echoed_when_present() {
        // Setup the redirector router
        let router = test_router(test_community_redirects(HashMap::new()));

        // Check requests without x-request-id receive a generated header
        let generated_response =
            router.clone().oneshot(test_request("/health-check")).await.unwrap();
        let generated_id = generated_response
            .headers()
            .get("x-request-id")
            .and_then(|value| value.to_str().ok())
            .expect("x-request-id header should be generated");
        assert_ne!(generated_id, "");

        // Check requests with x-request-id echo the caller's value
        let request = Request::builder()
            .header(HOST, "active-community.redirects.ocg.example")
            .header("x-request-id", "req-custom-123")
            .uri("/missing")
            .body(Body::empty())
            .unwrap();
        let propagated_response = router.oneshot(request).await.unwrap();
        assert_eq!(
            propagated_response.headers().get("x-request-id"),
            Some(&HeaderValue::from_static("req-custom-123"))
        );
    }

    // Helpers.

    /// Sets up a router mapping the legacy event path for the active community.
    fn legacy_event_router() -> Router {
        test_router(test_community_redirects(HashMap::from([(
            "/events/legacy-event".to_string(),
            "/community/group/group/event/event".to_string(),
        )])))
    }

    /// Builds test redirects for the active community.
    fn test_community_redirects(redirects: HashMap<String, String>) -> Redirects {
        HashMap::from([("active-community".to_string(), test_redirects(redirects))])
    }

    /// Builds test redirects for the active community with a legacy fallback.
    fn test_community_redirects_with_legacy_fallback(
        redirects: HashMap<String, String>,
    ) -> Redirects {
        HashMap::from([(
            "active-community".to_string(),
            CommunityRedirects {
                redirects,

                base_legacy_url: Some("https://legacy.example/".to_string()),
            },
        )])
    }

    /// Builds test redirects without a legacy fallback.
    fn test_redirects(redirects: HashMap<String, String>) -> CommunityRedirects {
        CommunityRedirects {
            redirects,

            base_legacy_url: None,
        }
    }

    /// Builds a test request for the provided path.
    fn test_request(path: &str) -> Request<Body> {
        test_host_request(path, "active-community.redirects.ocg.example")
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
        setup(
            Arc::new(RwLock::new(redirects)),
            &test_server_cfg(),
            CancellationToken::new(),
        )
    }

    /// Returns the default server configuration used by router tests.
    fn test_server_cfg() -> HttpServerConfig {
        HttpServerConfig {
            addr: "127.0.0.1:9001".to_string(),
            base_redirect_url: "https://ocg.example".to_string(),
        }
    }
}
