use anyhow::anyhow;
use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderValue, Method, StatusCode, Uri,
        header::{COOKIE, LOCATION},
    },
};
use axum_login::tower_sessions::session;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    services::notifications::MockNotificationsManager,
    types::permissions::{CommunityPermission, GroupPermission},
};

use super::*;

/// Dashboard mutation routes that only change the session's selected scope.
///
/// They are guarded by login and read access instead of a write permission.
const SCOPE_SELECTION_ROUTES: [&str; 3] = [
    "/dashboard/community/{community_id}/select",
    "/dashboard/group/community/{community_id}/select",
    "/dashboard/group/{group_id}/select",
];

#[tokio::test]
async fn test_browser_same_origin_middleware_enforces_browser_signals() {
    // Setup a mutation route protected by the browser-origin middleware
    let server_cfg = HttpServerConfig {
        base_url: "https://example.test".to_string(),
        ..Default::default()
    };
    let router = Router::new()
        .route(
            "/",
            get(|| async { StatusCode::NO_CONTENT }).post(|| async { StatusCode::NO_CONTENT }),
        )
        .route_layer(middleware::from_fn_with_state(
            server_cfg,
            enforce_browser_same_origin,
        ));

    // Define safe methods and trusted or untrusted browser signals
    let cases = [
        (Method::POST, None, None, StatusCode::NO_CONTENT),
        (
            Method::POST,
            Some("same-origin"),
            None,
            StatusCode::NO_CONTENT,
        ),
        (
            Method::POST,
            Some("cross-site"),
            Some("https://example.test"),
            StatusCode::FORBIDDEN,
        ),
        (Method::POST, Some("same-site"), None, StatusCode::FORBIDDEN),
        (
            Method::POST,
            None,
            Some("https://attacker.test"),
            StatusCode::FORBIDDEN,
        ),
        (
            Method::POST,
            None,
            Some("https://example.test"),
            StatusCode::NO_CONTENT,
        ),
        (
            Method::GET,
            Some("cross-site"),
            None,
            StatusCode::NO_CONTENT,
        ),
    ];

    // Send each request and check the middleware decision
    for (method, fetch_site, origin, expected_status) in cases {
        let mut request = Request::builder().method(method).uri("/");
        if let Some(fetch_site) = fetch_site {
            request = request.header("Sec-Fetch-Site", fetch_site);
        }
        if let Some(origin) = origin {
            request = request.header("Origin", origin);
        }

        let response = router
            .clone()
            .oneshot(request.body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(response.status(), expected_status);
    }
}

#[tokio::test]
async fn test_browser_same_origin_route_layer_excludes_later_webhook_routes() {
    // Setup protected browser and unprotected webhook routes
    let server_cfg = HttpServerConfig {
        base_url: "https://example.test".to_string(),
        ..Default::default()
    };
    let router = Router::new()
        .route(
            "/browser-mutation",
            post(|| async { StatusCode::NO_CONTENT }),
        )
        .route_layer(middleware::from_fn_with_state(
            server_cfg,
            enforce_browser_same_origin,
        ))
        .route("/webhook", post(|| async { StatusCode::NO_CONTENT }));

    // Send cross-site requests to both route groups
    let browser_response = router
        .clone()
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/browser-mutation")
                .header("Sec-Fetch-Site", "cross-site")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let webhook_response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/webhook")
                .header("Sec-Fetch-Site", "cross-site")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // Check only the browser mutation route is protected
    assert_eq!(browser_response.status(), StatusCode::FORBIDDEN);
    assert_eq!(webhook_response.status(), StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_current_commit_htmx_request_runs_handler() {
    // Setup router with commit SHA middleware
    let router = Router::new()
        .route("/", get(|| async { "fresh fragment" }))
        .layer(middleware::from_fn(refresh_stale_clients));

    // Send request with current commit SHA
    let request = Request::builder()
        .uri("/")
        .header("HX-Request", "true")
        .header(COMMIT_SHA_HEADER, COMMIT_SHA)
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(COMMIT_SHA_HEADER).unwrap(),
        &HeaderValue::from_static(COMMIT_SHA)
    );
    assert_eq!(String::from_utf8(bytes.to_vec()).unwrap(), "fresh fragment");
}

#[tokio::test]
async fn test_current_commit_ocg_fetch_request_runs_handler() {
    // Setup router with commit SHA middleware
    let router = Router::new()
        .route("/", get(|| async { "fresh json" }))
        .layer(middleware::from_fn(refresh_stale_clients));

    // Send request with current commit SHA
    let request = Request::builder()
        .uri("/")
        .header("X-OCG-Fetch", "true")
        .header(COMMIT_SHA_HEADER, COMMIT_SHA)
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(COMMIT_SHA_HEADER).unwrap(),
        &HeaderValue::from_static(COMMIT_SHA)
    );
    assert_eq!(String::from_utf8(bytes.to_vec()).unwrap(), "fresh json");
}

#[tokio::test]
async fn test_dashboard_mutation_routes_require_write_permission() {
    // Setup an authenticated session that only holds read access everywhere
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );
    let mut db = MockDB::new();
    db.expect_get_session()
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_community_permission()
        .returning(|_, _, permission| Ok(permission == CommunityPermission::Read));
    db.expect_user_has_group_permission()
        .returning(|_, _, _, permission| Ok(permission == GroupPermission::Read));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;

    // Collect every mutation route declared by the community and group dashboards
    let mutation_routes = dashboard_mutation_routes();
    for scope_route in SCOPE_SELECTION_ROUTES {
        assert!(
            mutation_routes.iter().any(|(path, _)| path == scope_route),
            "scope selection route {scope_route} is no longer declared"
        );
    }
    let write_routes: Vec<_> = mutation_routes
        .into_iter()
        .filter(|(path, _)| !SCOPE_SELECTION_ROUTES.contains(&path.as_str()))
        .collect();
    assert!(!write_routes.is_empty());

    // Check every write route is rejected before its handler runs
    for (path, method) in write_routes {
        let uri = path
            .split('/')
            .map(|segment| {
                if segment.starts_with('{') {
                    Uuid::new_v4().to_string()
                } else {
                    segment.to_string()
                }
            })
            .collect::<Vec<_>>()
            .join("/");
        let response = router
            .clone()
            .oneshot(
                Request::builder()
                    .method(method.clone())
                    .uri(&uri)
                    .header(COOKIE, format!("id={session_id}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(
            response.status(),
            StatusCode::FORBIDDEN,
            "{method} {path} is not protected by a write permission layer"
        );
    }
}

#[tokio::test]
async fn test_default_response_cache_header_is_private_no_store() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/log-in")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();

    // Check response matches expectations
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(
        response.headers().get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_PRIVATE_NO_STORE)
    );
    assert_eq!(
        response.headers().get(COMMIT_SHA_HEADER).unwrap(),
        &HeaderValue::from_static(COMMIT_SHA)
    );
}

#[tokio::test]
async fn test_favicon_route_returns_not_found_without_configured_url() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/favicon.ico")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NOT_FOUND);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_favicon_route_returns_redirect_with_cache_header() {
    // Setup database mock
    let favicon_url = "https://example.test/favicon.ico".to_string();
    let mut site_settings = sample_site_settings();
    site_settings.favicon_url = Some(favicon_url.clone());

    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/favicon.ico")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static("public, max-age=604800")
    );
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_str(&favicon_url).unwrap()
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_favicon_route_surfaces_db_errors_as_internal_server_error() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Err(anyhow!("db error")));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/favicon.ico")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();

    // Check response matches expectations
    assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_health_check_returns_ok() {
    // Run handler
    let response = health_check().await.into_response();
    let (parts, body) = response.into_parts();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert!(to_bytes(body, usize::MAX).await.unwrap().is_empty());
}

#[tokio::test]
async fn test_log_out_route_rejects_get() {
    // Setup the application router
    let router = TestRouterBuilder::new(MockDB::new(), MockNotificationsManager::new())
        .build()
        .await;

    // Send an unsupported GET request
    let response = router
        .oneshot(
            Request::builder()
                .method(Method::GET)
                .uri("/log-out")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // Check the router rejects the method
    assert_eq!(response.status(), StatusCode::METHOD_NOT_ALLOWED);
}

#[tokio::test]
async fn test_missing_route_returns_not_found_page() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/missing/page")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NOT_FOUND);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
    );
    assert_eq!(parts.headers.get("X-OCG-Not-Found").unwrap(), "true");
    assert_eq!(parts.headers.get("HX-Retarget").unwrap(), "body");
    assert_eq!(parts.headers.get("HX-Reswap").unwrap(), "innerHTML");
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("We could not find that page"));
    assert!(body.contains("Go to home page"));
}

#[tokio::test]
async fn test_payments_webhook_route_is_not_mounted_without_payments_config() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("POST")
        .uri("/webhooks/payments")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NOT_FOUND);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8")
    );
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("We could not find that page"));
}

#[tokio::test]
async fn test_redirect_old_hosts_redirects_matching_host() {
    // Setup router with redirect host configuration
    let server_cfg = HttpServerConfig {
        base_url: "https://example.com".to_string(),
        redirect_hosts: Some(vec!["old.example.com".to_string()]),
        ..Default::default()
    };
    let router: Router<()> = Router::new()
        .route("/", get(|| async { "ok" }))
        .layer(middleware::from_fn_with_state(
            server_cfg.clone(),
            redirect_old_hosts,
        ))
        .with_state(server_cfg);

    // Send request from old host
    let request = Request::builder()
        .uri("/some/path?query=value")
        .header(HOST, "old.example.com:8080")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();

    // Check response matches expectations
    assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
    assert_eq!(
        response.headers().get(LOCATION).unwrap(),
        &HeaderValue::from_static("https://example.com")
    );
}

#[tokio::test]
async fn test_stale_hx_request_refreshes_without_running_handler() {
    // Setup router with commit SHA middleware
    let router = Router::new()
        .route("/", get(|| async { "stale fragment" }))
        .layer(middleware::from_fn(refresh_stale_clients));

    // Send stale HTMX request
    let request = Request::builder()
        .uri("/")
        .header("HX-Request", "true")
        .header(COMMIT_SHA_HEADER, "older-commit")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_NO_STORE)
    );
    assert_eq!(parts.headers.get("HX-Refresh").unwrap(), "true");
    assert_eq!(
        parts.headers.get(COMMIT_SHA_HEADER).unwrap(),
        &HeaderValue::from_static(COMMIT_SHA)
    );
    assert!(to_bytes(body, usize::MAX).await.unwrap().is_empty());
}

#[tokio::test]
async fn test_stale_ocg_fetch_request_refreshes_without_running_handler() {
    // Setup router with commit SHA middleware
    let router = Router::new()
        .route("/", get(|| async { "stale json" }))
        .layer(middleware::from_fn(refresh_stale_clients));

    // Send stale OCG fetch request
    let request = Request::builder()
        .uri("/")
        .header("X-OCG-Fetch", "true")
        .header(COMMIT_SHA_HEADER, "older-commit")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert_eq!(parts.headers.get("X-OCG-Refresh").unwrap(), "true");
    assert!(parts.headers.get("HX-Refresh").is_none());
    assert!(to_bytes(body, usize::MAX).await.unwrap().is_empty());
}

#[tokio::test]
async fn test_static_handler_missing_asset_returns_not_found() {
    // Run handler
    let uri = Uri::from_static("/static/does/not/exist.txt");
    let response = static_handler(uri).await.into_response();
    let (parts, body) = response.into_parts();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NOT_FOUND);
    assert!(to_bytes(body, usize::MAX).await.unwrap().is_empty());
}

#[tokio::test]
async fn test_static_handler_serves_existing_asset() {
    // Run handler
    let uri = Uri::from_static("/static/images/icons/arrow_left.svg");
    let response = static_handler(uri).await.into_response();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("image/svg+xml")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_STATIC_IMAGES)
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_static_handler_serves_hashed_css_asset_with_immutable_cache() {
    // Run handler
    let path = static_path_with_prefix_and_suffix("css/", ".css");
    let uri = Uri::try_from(format!("/static/{path}")).unwrap();
    let response = static_handler(uri).await.into_response();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/css")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_IMMUTABLE)
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_static_handler_serves_hashed_js_asset_with_immutable_cache() {
    // Run handler
    let path = static_path_with_prefix_and_suffix("js/", ".js");
    let uri = Uri::try_from(format!("/static/{path}")).unwrap();
    let response = static_handler(uri).await.into_response();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/javascript")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_IMMUTABLE)
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_static_handler_serves_vendor_asset_with_immutable_cache() {
    // Run handler
    let uri = Uri::from_static("/static/vendor/js/htmx.v2.0.7.min.js");
    let response = static_handler(uri).await.into_response();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/javascript")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_IMMUTABLE)
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_zoom_webhook_route_is_not_mounted_when_zoom_is_disabled() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup disabled Zoom configuration
    let mut meetings_cfg = sample_zoom_meetings_cfg("zoom-secret");
    if let Some(zoom_cfg) = meetings_cfg.zoom.as_mut() {
        zoom_cfg.enabled = false;
    }

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_meetings_cfg(meetings_cfg)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri("/webhooks/zoom")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NOT_FOUND);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8")
    );
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("We could not find that page"));
}

// Helpers.

/// Checks whether the route arguments call the given axum method router.
fn contains_method_call(args: &str, name: &str) -> bool {
    let needle = format!("{name}(");
    args.match_indices(&needle).any(|(index, _)| {
        args[..index]
            .chars()
            .next_back()
            .is_none_or(|c| !(c.is_alphanumeric() || c == '_' || c == ':'))
    })
}

/// Extracts the mutation routes declared by the community and group dashboard routers.
fn dashboard_mutation_routes() -> Vec<(String, Method)> {
    const SOURCE: &str = include_str!("dashboard.rs");
    const MUTATION_METHODS: [(&str, Method); 4] = [
        ("delete", Method::DELETE),
        ("patch", Method::PATCH),
        ("post", Method::POST),
        ("put", Method::PUT),
    ];
    let sections = [
        (
            "/dashboard/community",
            "fn setup_community_dashboard_router",
            "fn setup_group_dashboard_router",
        ),
        (
            "/dashboard/group",
            "fn setup_group_dashboard_router",
            "fn setup_user_dashboard_router",
        ),
    ];

    // Scan each router function for route declarations and their method chains
    let mut routes = Vec::new();
    for (prefix, start_marker, end_marker) in sections {
        let start = SOURCE.find(start_marker).expect("router function should exist");
        let end = SOURCE.find(end_marker).expect("router function should exist");
        let mut rest = &SOURCE[start..end];
        while let Some(index) = rest.find(".route(") {
            rest = &rest[index + ".route(".len()..];

            // Read the path literal and the arguments up to the matching parenthesis
            let path_start = rest.find('"').expect("route path should be a literal") + 1;
            let path_end =
                path_start + rest[path_start..].find('"').expect("route path should close");
            let path = &rest[path_start..path_end];
            let mut depth = 1;
            let mut args_end = rest.len();
            for (i, c) in rest.char_indices() {
                match c {
                    '(' => depth += 1,
                    ')' => {
                        depth -= 1;
                        if depth == 0 {
                            args_end = i;
                            break;
                        }
                    }
                    _ => {}
                }
            }
            let args = &rest[path_end..args_end];

            // Record every mutation method routed on this path
            for (name, method) in &MUTATION_METHODS {
                if contains_method_call(args, name) {
                    routes.push((format!("{prefix}{path}"), method.clone()));
                }
            }
            rest = &rest[args_end..];
        }
    }
    routes
}

/// Finds an embedded static asset path matching the given prefix and suffix.
fn static_path_with_prefix_and_suffix(prefix: &str, suffix: &str) -> String {
    StaticFile::iter()
        .find(|path| path.starts_with(prefix) && path.ends_with(suffix))
        .unwrap_or_else(|| panic!("{prefix} asset ending with {suffix} to exist"))
        .to_string()
}
