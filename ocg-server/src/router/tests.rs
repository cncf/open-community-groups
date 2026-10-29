use std::{collections::BTreeSet, env, fs, path::Path};

use anyhow::anyhow;
use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderValue, Method, StatusCode, Uri,
        header::{LOCATION, SET_COOKIE},
        response::Parts,
    },
};
use axum_login::tower_sessions::session;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    db::mock::{MockDB, expect_site_settings},
    handlers::tests::*,
    types::permissions::{CommunityPermission, GroupPermission},
};

use super::*;

/// Response header the matched-path test layer echoes the matched path in.
const MATCHED_PATH_TEST_HEADER: &str = "x-test-matched-path";

/// Dashboard routes posting a request body too long for a query string
/// without changing state.
///
/// Only their `POST` method is guarded by read access instead of a write
/// permission.
const READ_ONLY_POST_ROUTES: [&str; 1] = ["/dashboard/community/contact/recipients"];

/// E2E route manifest path, relative to the server crate directory.
const ROUTE_MANIFEST_PATH: &str = "../tests/e2e/coverage/route-manifest.json";

/// Dashboard mutation routes that only change the session's selected scope.
///
/// They are guarded by login and read access instead of a write permission.
const SCOPE_SELECTION_ROUTES: [&str; 3] = [
    "/dashboard/community/{community_id}/select",
    "/dashboard/group/community/{community_id}/select",
    "/dashboard/group/{group_id}/select",
];

/// Environment variable that makes the manifest test rewrite the E2E manifest.
const UPDATE_ROUTE_MANIFEST_ENV: &str = "OCG_UPDATE_ROUTE_MANIFEST";

/// Unsafe routes registered after the browser same-origin guard layer.
///
/// Providers call these webhooks server to server and authenticate with
/// signatures, so the real-router guard test exempts exactly these paths.
const WEBHOOK_ROUTES: [&str; 3] = [
    "/webhooks/payments",
    "/webhooks/payments/connected",
    "/webhooks/zoom",
];

/// Route entry of the E2E route manifest.
#[derive(Debug, Deserialize, PartialEq, Serialize)]
struct RouteManifestEntry {
    /// HTTP method routed on the path.
    method: String,
    /// Route path template, as reported by the matched path.
    path: String,
}

impl RouteManifestEntry {
    /// Returns the `METHOD path` label used in mismatch reports.
    fn label(&self) -> String {
        format!("{} {}", self.method, self.path)
    }
}

#[tokio::test]
async fn test_browser_same_origin_middleware_enforces_browser_signals() {
    // Setup a mutation route protected by the browser-origin middleware
    let router = Router::new()
        .route(
            "/",
            get(|| async { StatusCode::NO_CONTENT }).post(|| async { StatusCode::NO_CONTENT }),
        )
        .route_layer(middleware::from_fn_with_state(
            sample_server_cfg("https://example.test"),
            enforce_browser_same_origin,
        ));

    // Define safe methods and trusted or untrusted browser signals
    let cases = [
        (
            "post without browser signals",
            Method::POST,
            None,
            None,
            None,
            StatusCode::NO_CONTENT,
        ),
        (
            "post from same origin fetch",
            Method::POST,
            Some("same-origin"),
            None,
            None,
            StatusCode::NO_CONTENT,
        ),
        (
            "cross-site fetch with matching origin",
            Method::POST,
            Some("cross-site"),
            Some("https://example.test"),
            None,
            StatusCode::FORBIDDEN,
        ),
        (
            "same-site fetch without origin",
            Method::POST,
            Some("same-site"),
            None,
            None,
            StatusCode::FORBIDDEN,
        ),
        (
            "mismatched origin",
            Method::POST,
            None,
            Some("https://attacker.test"),
            None,
            StatusCode::FORBIDDEN,
        ),
        (
            "matching origin",
            Method::POST,
            None,
            Some("https://example.test"),
            None,
            StatusCode::NO_CONTENT,
        ),
        (
            "matching referer without origin",
            Method::POST,
            None,
            None,
            Some("https://example.test/page"),
            StatusCode::NO_CONTENT,
        ),
        (
            "mismatched referer without origin",
            Method::POST,
            None,
            None,
            Some("https://attacker.test/page"),
            StatusCode::FORBIDDEN,
        ),
        (
            "cross-site get",
            Method::GET,
            Some("cross-site"),
            None,
            None,
            StatusCode::NO_CONTENT,
        ),
    ];

    // Send each request and check the middleware decision
    for (case, method, fetch_site, origin, referer, expected_status) in cases {
        let mut request = request(method.as_str(), "/");
        if let Some(fetch_site) = fetch_site {
            request = request.header("Sec-Fetch-Site", fetch_site);
        }
        if let Some(origin) = origin {
            request = request.header("Origin", origin);
        }
        if let Some(referer) = referer {
            request = request.header("Referer", referer);
        }
        let (parts, _) = send(router.clone(), request.body(Body::empty()).unwrap()).await;
        assert_eq!(parts.status, expected_status, "{case}");
    }
}

/// Only routes declared with a path literal in `.route(` calls of the router
/// sources are covered; routes registered through helpers are missed.
#[tokio::test]
async fn test_browser_same_origin_protects_every_unsafe_route() {
    // Setup the application router with every login-dependent route mounted
    let mut server_cfg = sample_server_cfg("https://example.test");
    server_cfg.login.email = true;
    let router = TestRouterBuilder::new(MockDB::new())
        .with_server_cfg(server_cfg)
        .build()
        .await;

    // Collect the declared unsafe routes and split out the exempt webhook routes
    let (webhook_routes, unsafe_routes): (Vec<_>, Vec<_>) = declared_routes()
        .into_iter()
        .filter(|(_, method)| *method != Method::GET)
        .partition(|(path, _)| WEBHOOK_ROUTES.contains(&path.as_str()));
    let webhook_paths: Vec<_> = webhook_routes.iter().map(|(path, _)| path.as_str()).collect();
    assert_eq!(
        webhook_paths, WEBHOOK_ROUTES,
        "every WEBHOOK_ROUTES entry should be a declared unsafe route"
    );
    assert!(
        !unsafe_routes.is_empty(),
        "router should expose unsafe routes"
    );

    // Check every unsafe route rejects cross-site requests before its handler runs
    for (path, method) in unsafe_routes {
        let request = request(method.as_str(), &concrete_uri(&path))
            .header("Sec-Fetch-Site", "cross-site")
            .body(Body::empty())
            .unwrap();
        let (parts, _) = send(router.clone(), request).await;
        assert_eq!(
            parts.status,
            StatusCode::FORBIDDEN,
            "{method} {path} is not protected by the browser same-origin guard"
        );
    }
}

#[tokio::test]
async fn test_browser_same_origin_route_layer_excludes_later_webhook_routes() {
    // Setup protected browser and unprotected webhook routes
    let router = Router::new()
        .route(
            "/browser-mutation",
            post(|| async { StatusCode::NO_CONTENT }),
        )
        .route_layer(middleware::from_fn_with_state(
            sample_server_cfg("https://example.test"),
            enforce_browser_same_origin,
        ))
        .route("/webhook", post(|| async { StatusCode::NO_CONTENT }));

    // Send cross-site requests to both route groups
    let browser_request = request("POST", "/browser-mutation")
        .header("Sec-Fetch-Site", "cross-site")
        .body(Body::empty())
        .unwrap();
    let (browser_parts, _) = send(router.clone(), browser_request).await;
    let webhook_request = request("POST", "/webhook")
        .header("Sec-Fetch-Site", "cross-site")
        .body(Body::empty())
        .unwrap();
    let (webhook_parts, _) = send(router, webhook_request).await;

    // Check only the browser mutation route is protected
    assert_eq!(browser_parts.status, StatusCode::FORBIDDEN);
    assert_eq!(webhook_parts.status, StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_cohost_response_routes_require_settings_write_permission() {
    // Setup an events manager session without settings access
    let ids = DashboardIds::new();
    let db = permission_scoped_db(&ids, |permission| {
        matches!(
            permission,
            GroupPermission::EventsWrite | GroupPermission::Read
        )
    });
    let router = TestRouterBuilder::new(db).build().await;

    // Check every co-hosting response route rejects the events manager
    for action in ["approve", "cancel", "reject"] {
        let uri = format!("/dashboard/group/cohosts/{}/{action}", Uuid::new_v4());
        let (parts, _) = send(router.clone(), empty_request("PUT", &uri, ids.session_id)).await;
        assert_eq!(
            parts.status,
            StatusCode::FORBIDDEN,
            "co-hosting {action} is not protected by the settings write permission"
        );
    }
}

#[tokio::test]
async fn test_current_commit_request_runs_handler() {
    // Setup router with commit SHA middleware
    let router = Router::new()
        .route("/", get(|| async { "fresh response" }))
        .layer(middleware::from_fn(refresh_stale_clients));

    // Check each dynamic client on the current commit reaches the handler
    for client_header in ["HX-Request", "X-OCG-Fetch"] {
        let request = request("GET", "/")
            .header(client_header, "true")
            .header(COMMIT_SHA_HEADER, COMMIT_SHA)
            .body(Body::empty())
            .unwrap();
        let (parts, bytes) = send(router.clone(), request).await;
        assert_eq!(parts.status, StatusCode::OK, "{client_header}");
        assert_eq!(
            parts.headers.get(COMMIT_SHA_HEADER).unwrap(),
            &HeaderValue::from_static(COMMIT_SHA),
            "{client_header}"
        );
        assert_eq!(bytes.as_ref(), b"fresh response", "{client_header}");
    }
}

#[tokio::test]
async fn test_dashboard_mutation_routes_require_write_permission() {
    // Setup an authenticated session that only holds read access everywhere
    let ids = DashboardIds::new();
    let mut db = permission_scoped_db(&ids, |permission| permission == GroupPermission::Read);
    db.expect_user_has_community_permission()
        .returning(|_, _, permission| Ok(permission == CommunityPermission::Read));
    let router = TestRouterBuilder::new(db).build().await;

    // Collect every mutation route declared by the community and group dashboards
    let mutation_routes = dashboard_mutation_routes();
    for read_only_route in READ_ONLY_POST_ROUTES {
        assert!(
            mutation_routes
                .iter()
                .any(|(path, method)| path == read_only_route && *method == Method::POST),
            "read-only post route {read_only_route} is no longer declared"
        );
    }
    for scope_route in SCOPE_SELECTION_ROUTES {
        assert!(
            mutation_routes.iter().any(|(path, _)| path == scope_route),
            "scope selection route {scope_route} is no longer declared"
        );
    }
    let write_routes: Vec<_> = mutation_routes
        .into_iter()
        .filter(|(path, method)| {
            let is_read_only_post =
                *method == Method::POST && READ_ONLY_POST_ROUTES.contains(&path.as_str());
            let is_scope_selection = SCOPE_SELECTION_ROUTES.contains(&path.as_str());
            !is_read_only_post && !is_scope_selection
        })
        .collect();
    assert!(
        !write_routes.is_empty(),
        "router should expose write routes"
    );

    // Check every write route is rejected before its handler runs
    for (path, method) in write_routes {
        let request = empty_request(method.as_str(), &concrete_uri(&path), ids.session_id);
        let (parts, _) = send(router.clone(), request).await;
        assert_eq!(
            parts.status,
            StatusCode::FORBIDDEN,
            "{method} {path} is not protected by a write permission layer"
        );
    }
}

#[test]
fn test_dashboard_refresh_paths_are_routed_gets() {
    // Collect the declared routes and the dashboard home refresh path sources
    let routes = declared_routes();
    let homes = [
        (
            "/dashboard/group",
            include_str!("../templates/dashboard/group/home.rs"),
        ),
        (
            "/dashboard/user",
            include_str!("../templates/dashboard/user/home.rs"),
        ),
    ];

    // Check every refresh path resolves to a declared GET route
    for (prefix, source) in homes {
        let refresh_paths = refresh_path_literals(source);
        assert!(
            !refresh_paths.is_empty(),
            "{prefix} home should declare refresh paths"
        );
        for refresh_path in refresh_paths {
            let path = format!("{prefix}/{refresh_path}");
            assert!(
                routes
                    .iter()
                    .any(|(route, method)| *route == path && *method == Method::GET),
                "refresh path {path} is not a declared GET route"
            );
        }
    }
}

#[tokio::test]
async fn test_default_response_cache_header_is_private_no_store() {
    // Setup router and send request
    let router = TestRouterBuilder::new(site_settings_db()).build().await;
    let request = request("GET", "/log-in").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_PRIVATE_NO_STORE)
    );
    assert_eq!(
        parts.headers.get(COMMIT_SHA_HEADER).unwrap(),
        &HeaderValue::from_static(COMMIT_SHA)
    );
}

#[tokio::test]
async fn test_favicon_route_returns_not_found_without_configured_url() {
    // Setup router and send request
    let router = TestRouterBuilder::new(site_settings_db()).build().await;
    let request = request("GET", "/favicon.ico").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
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

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = request("GET", "/favicon.ico").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static("public, max-age=604800")
    );
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_str(&favicon_url).unwrap()
    );
}

#[tokio::test]
async fn test_favicon_route_surfaces_db_errors_as_internal_server_error() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Err(anyhow!("db error")));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = request("GET", "/favicon.ico").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_health_check_returns_ok() {
    // Run handler
    let response = health_check(AxumState(CancellationToken::new()))
        .await
        .into_response();
    let (parts, body) = response.into_parts();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert!(to_bytes(body, usize::MAX).await.unwrap().is_empty());
}

#[tokio::test]
async fn test_health_check_returns_service_unavailable_while_draining() {
    // Setup a drain token that has already been cancelled
    let shutdown_drain = CancellationToken::new();
    shutdown_drain.cancel();

    // Run handler
    let response = health_check(AxumState(shutdown_drain)).await.into_response();

    // Check response matches expectations
    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
}

#[tokio::test]
async fn test_inbox_routes_require_inbox_write_permission() {
    // Setup a session with read and events access but without inbox access
    let ids = DashboardIds::new();
    let db = permission_scoped_db(&ids, |permission| {
        matches!(
            permission,
            GroupPermission::EventsWrite | GroupPermission::Read
        )
    });
    let router = TestRouterBuilder::new(db).build().await;

    // Check both inbox read routes reject the session
    for uri in [
        "/dashboard/group/inbox".to_string(),
        format!("/dashboard/group/inbox/{}", Uuid::new_v4()),
    ] {
        let (parts, _) = send(router.clone(), get_request(&uri, ids.session_id)).await;
        assert_eq!(
            parts.status,
            StatusCode::FORBIDDEN,
            "{uri} is not protected by the inbox write permission"
        );
    }
}

#[tokio::test]
async fn test_log_out_route_rejects_get() {
    // Setup the application router and send an unsupported GET request
    let router = TestRouterBuilder::new(MockDB::new()).build().await;
    let request = request("GET", "/log-out").body(Body::empty()).unwrap();
    let (parts, _) = send(router, request).await;

    // Check the router rejects the method
    assert_eq!(parts.status, StatusCode::METHOD_NOT_ALLOWED);
}

#[tokio::test]
async fn test_missing_route_returns_not_found_page() {
    // Setup router and send request
    let router = TestRouterBuilder::new(site_settings_db()).build().await;
    let request = request("GET", "/missing/page").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::NOT_FOUND);
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
    // Setup router and send request
    let router = TestRouterBuilder::new(site_settings_db()).build().await;
    let request = request("POST", "/webhooks/payments").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::NOT_FOUND);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("We could not find that page"));
}

#[tokio::test]
async fn test_public_shared_cache_page_omits_set_cookie_with_stale_session() {
    // Setup database mock without the stored session
    let session_id = session::Id::default();
    let mut db = site_settings_db();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(|_| Ok(None));
    db.expect_get_user_by_id().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, get_request("/docs", session_id)).await;

    // Check the public response does not remove the stale cookie
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_public_response_without_set_cookie(&parts);
}

#[tokio::test]
async fn test_public_shared_cache_page_omits_set_cookie_with_valid_session() {
    // Setup database mock with an authenticated session
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    expect_site_settings(&mut db);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, get_request("/docs", ids.session_id)).await;

    // Check the public response does not carry the session cookie
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_public_response_without_set_cookie(&parts);
}

#[tokio::test]
async fn test_public_shared_cache_page_omits_set_cookie_without_session() {
    // Setup router and send request
    let router = TestRouterBuilder::new(site_settings_db()).build().await;
    let request = request("GET", "/docs").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the public response does not set a cookie
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_public_response_without_set_cookie(&parts);
}

#[tokio::test]
async fn test_redirect_old_hosts_passes_other_hosts_through() {
    // Setup router with redirect host configuration
    let router = redirect_old_hosts_router();

    // Send request from the current host
    let request = request("GET", "/")
        .header(HOST, "example.com")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the request reaches the handler
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(bytes.as_ref(), b"ok");
}

#[tokio::test]
async fn test_redirect_old_hosts_redirects_matching_host() {
    // Setup router with redirect host configuration
    let router = redirect_old_hosts_router();

    // Send request from old host
    let request = request("GET", "/some/path?query=value")
        .header(HOST, "old.example.com:8080")
        .body(Body::empty())
        .unwrap();
    let (parts, _) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::PERMANENT_REDIRECT);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static("https://example.com")
    );
}

#[tokio::test]
async fn test_redirects_to_log_in_flags_only_log_in_guard_rejections() {
    // Setup the application router with a read-only authenticated session
    let ids = DashboardIds::new();
    let db = permission_scoped_db(&ids, |permission| permission == GroupPermission::Read);
    let router = TestRouterBuilder::new(db).build().await;

    // Define guard rejections and responses whose handler or permission layer ran
    let cohost_approve_uri = format!("/dashboard/group/cohosts/{}/approve", Uuid::new_v4());
    let cases = [
        (
            "anonymous page request to a guarded route",
            request("GET", "/dashboard/user").body(Body::empty()).unwrap(),
            StatusCode::TEMPORARY_REDIRECT,
            true,
        ),
        (
            "anonymous htmx request to a guarded route",
            request("GET", "/dashboard/user")
                .header("HX-Request", "true")
                .body(Body::empty())
                .unwrap(),
            StatusCode::TEMPORARY_REDIRECT,
            true,
        ),
        (
            "log out handler redirect to log in",
            request("POST", "/log-out").body(Body::empty()).unwrap(),
            StatusCode::SEE_OTHER,
            false,
        ),
        (
            "authenticated request rejected by a permission layer",
            empty_request("PUT", &cohost_approve_uri, ids.session_id),
            StatusCode::FORBIDDEN,
            false,
        ),
        (
            "anonymous request to a public route",
            request("GET", "/health-check").body(Body::empty()).unwrap(),
            StatusCode::OK,
            false,
        ),
    ];

    // Send each request and check the status and the log-in redirect flag
    for (case, request, expected_status, expected) in cases {
        let (parts, _) = send(router.clone(), request).await;
        assert_eq!(parts.status, expected_status, "{case}");
        if parts.status.is_redirection() {
            let location = parts.headers.get(LOCATION).unwrap().to_str().unwrap();
            assert!(location.starts_with(LOG_IN_URL), "{case}: {location}");
        }
        let response = axum::http::Response::from_parts(parts, ());
        assert_eq!(
            route_hits::redirects_to_log_in(&response),
            expected,
            "{case}"
        );
    }
}

#[tokio::test]
async fn test_request_matched_path_reports_route_template_or_fallback() {
    // Setup a router whose outer layer echoes the matched path, like the request span
    let group_router = Router::new().route(
        "/{group_id}/members",
        get(|| async { StatusCode::NO_CONTENT }),
    );
    let router = Router::new()
        .route(
            "/events/{event_id}",
            get(|| async { StatusCode::NO_CONTENT }),
        )
        .nest("/dashboard/group", group_router)
        .fallback(|| async { StatusCode::NOT_FOUND })
        .layer(middleware::from_fn(echo_matched_path));

    // Define matched routes, nested routes and unmatched paths
    let cases = [
        (
            "route with a path parameter",
            "/events/b4c5e5c6-1f4a-4a3e-9d43-3f7e6d3c6b1a",
            "/events/{event_id}",
        ),
        (
            "nested route",
            "/dashboard/group/b4c5e5c6-1f4a-4a3e-9d43-3f7e6d3c6b1a/members",
            "/dashboard/group/{group_id}/members",
        ),
        ("unmatched path", "/missing/page", "fallback"),
    ];

    // Send each request and check the matched path seen by the layer
    for (case, uri, expected) in cases {
        let request = request("GET", uri).body(Body::empty()).unwrap();
        let (parts, _) = send(router.clone(), request).await;
        assert_eq!(
            parts.headers.get(MATCHED_PATH_TEST_HEADER).map(HeaderValue::as_bytes),
            Some(expected.as_bytes()),
            "{case}"
        );
    }
}

#[test]
fn test_route_manifest_matches_e2e_manifest() {
    // Build the manifest from the router sources
    let manifest = route_manifest();
    let manifest_path = Path::new(env!("CARGO_MANIFEST_DIR")).join(ROUTE_MANIFEST_PATH);

    // Rewrite the E2E manifest when an update is requested
    if env::var(UPDATE_ROUTE_MANIFEST_ENV).is_ok_and(|value| value == "1") {
        let mut json = serde_json::to_string_pretty(&manifest).unwrap();
        json.push('\n');
        fs::write(&manifest_path, json).unwrap();
    }

    // Read the committed E2E manifest
    let committed: Vec<RouteManifestEntry> = fs::read_to_string(&manifest_path)
        .ok()
        .and_then(|json| serde_json::from_str(&json).ok())
        .unwrap_or_else(|| {
            panic!(
                "{ROUTE_MANIFEST_PATH} should be a route manifest; run `just e2e-route-manifest`"
            )
        });

    // Check the committed manifest lists the declared routes in order
    let declared: BTreeSet<_> = manifest.iter().map(RouteManifestEntry::label).collect();
    let listed: BTreeSet<_> = committed.iter().map(RouteManifestEntry::label).collect();
    let missing: Vec<_> = declared.difference(&listed).collect();
    let stale: Vec<_> = listed.difference(&declared).collect();
    assert!(
        missing.is_empty() && stale.is_empty(),
        "route manifest is out of date, run `just e2e-route-manifest` (missing: {missing:?}, stale: {stale:?})"
    );
    assert_eq!(
        committed, manifest,
        "route manifest order or duplicates differ, run `just e2e-route-manifest`"
    );
}

#[test]
fn test_route_manifest_parses_every_route_declaration() {
    // Collect the route calls and the parsed declarations of every router section
    let route_calls: usize = router_sections()
        .iter()
        .map(|(_, section)| section.matches(".route(").count())
        .sum();
    let declarations = route_declarations();

    // Check every route call was parsed into a declaration with a method
    assert_eq!(
        declarations.len(),
        route_calls,
        "every .route( call should be parsed"
    );
    for (path, methods) in &declarations {
        assert!(
            !methods.is_empty(),
            "route {path} should declare a DELETE, GET, PATCH, POST or PUT method"
        );
    }
}

#[tokio::test]
async fn test_stale_hx_request_refreshes_without_running_handler() {
    // Setup router with commit SHA middleware
    let router = Router::new()
        .route("/", get(|| async { "stale fragment" }))
        .layer(middleware::from_fn(refresh_stale_clients));

    // Send stale HTMX request
    let request = request("GET", "/")
        .header("HX-Request", "true")
        .header(COMMIT_SHA_HEADER, "older-commit")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_NO_STORE)
    );
    assert_eq!(parts.headers.get("HX-Refresh").unwrap(), "true");
    assert_eq!(
        parts.headers.get(COMMIT_SHA_HEADER).unwrap(),
        &HeaderValue::from_static(COMMIT_SHA)
    );
}

#[tokio::test]
async fn test_stale_ocg_fetch_request_refreshes_without_running_handler() {
    // Setup router with commit SHA middleware
    let router = Router::new()
        .route("/", get(|| async { "stale json" }))
        .layer(middleware::from_fn(refresh_stale_clients));

    // Send stale OCG fetch request
    let request = request("GET", "/")
        .header("X-OCG-Fetch", "true")
        .header(COMMIT_SHA_HEADER, "older-commit")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::NO_CONTENT);
    assert_eq!(parts.headers.get("X-OCG-Refresh").unwrap(), "true");
    assert!(parts.headers.get("HX-Refresh").is_none());
}

#[tokio::test]
async fn test_stale_ocg_fetch_static_request_serves_asset_without_commit_sha() {
    // Setup the application router
    let router = TestRouterBuilder::new(MockDB::new()).build().await;

    // Send stale OCG fetch request for a static asset
    let request = request("GET", "/static/vendor/css/docsify-vue.v4.13.1.min.css")
        .header("X-OCG-Fetch", "true")
        .header(COMMIT_SHA_HEADER, "older-commit")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the asset is served without deployment version headers
    assert_non_empty_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_IMMUTABLE)
    );
    assert!(parts.headers.get(COMMIT_SHA_HEADER).is_none());
    assert!(parts.headers.get("X-OCG-Refresh").is_none());
}

#[tokio::test]
async fn test_responses_carry_a_request_id_header() {
    // Setup the application router
    let router = TestRouterBuilder::new(MockDB::new()).build().await;

    // Send a request without a request id and one with a client-supplied id
    let generated_request = request("GET", "/health-check").body(Body::empty()).unwrap();
    let (generated, _) = send(router.clone(), generated_request).await;
    let propagated_request = request("GET", "/health-check")
        .header("x-request-id", "client-supplied-id")
        .body(Body::empty())
        .unwrap();
    let (propagated, _) = send(router, propagated_request).await;

    // Check a generated id is echoed and a supplied id is preserved
    let generated_id = generated.headers.get("x-request-id").unwrap().to_str().unwrap();
    assert!(Uuid::parse_str(generated_id).is_ok(), "{generated_id}");
    assert_eq!(
        propagated.headers.get("x-request-id").unwrap(),
        &HeaderValue::from_static("client-supplied-id")
    );
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
async fn test_static_handler_serves_assets_with_cache_policy() {
    // Setup labeled embedded assets with their content type and cache policy
    let cases = [
        (
            "image",
            "/static/images/icons/arrow_left.svg".to_string(),
            "image/svg+xml",
            CACHE_CONTROL_STATIC_IMAGES,
        ),
        (
            "hashed css",
            format!(
                "/static/{}",
                static_path_with_prefix_and_suffix("css/", ".css")
            ),
            "text/css",
            CACHE_CONTROL_IMMUTABLE,
        ),
        (
            "hashed js",
            format!(
                "/static/{}",
                static_path_with_prefix_and_suffix("js/", ".js")
            ),
            "text/javascript",
            CACHE_CONTROL_IMMUTABLE,
        ),
        (
            "vendor js",
            "/static/vendor/js/htmx.v2.0.7.min.js".to_string(),
            "text/javascript",
            CACHE_CONTROL_IMMUTABLE,
        ),
    ];

    // Check each asset is served with the expected headers
    for (case, uri, content_type, cache_control) in cases {
        let response = static_handler(Uri::try_from(uri).unwrap()).await.into_response();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();
        assert_eq!(parts.status, StatusCode::OK, "{case}");
        assert_eq!(
            parts.headers.get(CONTENT_TYPE).unwrap(),
            &HeaderValue::from_static(content_type),
            "{case}"
        );
        assert_eq!(
            parts.headers.get(CACHE_CONTROL).unwrap(),
            &HeaderValue::from_static(cache_control),
            "{case}"
        );
        assert!(!bytes.is_empty(), "{case}");
    }
}

#[tokio::test]
async fn test_zoom_webhook_route_is_not_mounted_when_zoom_is_disabled() {
    // Setup disabled Zoom configuration
    let mut meetings_cfg = sample_zoom_meetings_cfg("zoom-secret");
    if let Some(zoom_cfg) = meetings_cfg.zoom.as_mut() {
        zoom_cfg.enabled = false;
    }

    // Setup router and send request
    let router = TestRouterBuilder::new(site_settings_db())
        .with_meetings_cfg(meetings_cfg)
        .build()
        .await;
    let request = request("POST", "/webhooks/zoom").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::NOT_FOUND);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("We could not find that page"));
}

// Helpers.

/// Asserts the response is public shared-cache and carries no `Set-Cookie`.
fn assert_public_response_without_set_cookie(parts: &Parts) {
    let cache_control = parts.headers.get(CACHE_CONTROL).unwrap().to_str().unwrap();
    assert!(cache_control.starts_with("public"), "{cache_control}");
    let set_cookies: Vec<_> = parts.headers.get_all(SET_COOKIE).iter().collect();
    assert!(
        set_cookies.is_empty(),
        "unexpected Set-Cookie: {set_cookies:?}"
    );
}

/// Replaces every `{...}` segment of a route path with a random UUID.
fn concrete_uri(path: &str) -> String {
    path.split('/')
        .map(|segment| {
            if segment.starts_with('{') {
                Uuid::new_v4().to_string()
            } else {
                segment.to_string()
            }
        })
        .collect::<Vec<_>>()
        .join("/")
}

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
    declared_routes()
        .into_iter()
        .filter(|(path, method)| {
            let in_dashboard = ["/dashboard/community", "/dashboard/group"].iter().any(|prefix| {
                path.strip_prefix(prefix)
                    .is_some_and(|rest| rest.is_empty() || rest.starts_with('/'))
            });
            in_dashboard && *method != Method::GET
        })
        .collect()
}

/// Extracts the routes declared by the main and dashboard router sources,
/// deduped and sorted by path and method.
///
/// Only `.route(` calls with a path literal are seen; routes registered
/// through helpers are missed.
fn declared_routes() -> Vec<(String, Method)> {
    // Flatten every route declaration into one entry per method
    let mut routes: Vec<_> = route_declarations()
        .into_iter()
        .flat_map(|(path, methods)| methods.into_iter().map(move |method| (path.clone(), method)))
        .collect();

    // Dedupe and sort the routes by path and method
    routes.sort_by(|(a_path, a_method), (b_path, b_method)| {
        a_path
            .cmp(b_path)
            .then_with(|| a_method.as_str().cmp(b_method.as_str()))
    });
    routes.dedup();
    routes
}

/// Echoes the request's matched path in a response header.
async fn echo_matched_path(request: Request, next: Next) -> axum::response::Response {
    let matched_path = HeaderValue::from_str(request_matched_path(&request)).unwrap();
    let mut response = next.run(request).await;
    response.headers_mut().insert(MATCHED_PATH_TEST_HEADER, matched_path);
    response
}

/// Builds a database answering every session read of a user with a selected
/// community and group, granting only the group permissions `allows` accepts.
fn permission_scoped_db(ids: &DashboardIds, allows: fn(GroupPermission) -> bool) -> MockDB {
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        ids.session_id,
        ids.user_id,
        &auth_hash,
        Some(ids.community_id),
        Some(ids.group_id),
    );
    let user_id = ids.user_id;
    let mut db = MockDB::new();
    db.expect_get_session()
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_group_permission()
        .returning(move |_, _, _, permission| Ok(allows(permission)));
    db
}

/// Builds a router that redirects `old.example.com` to the base URL.
fn redirect_old_hosts_router() -> Router {
    let server_cfg = HttpServerConfig {
        redirect_hosts: Some(vec!["old.example.com".to_string()]),
        ..sample_server_cfg("https://example.com")
    };
    Router::new()
        .route("/", get(|| async { "ok" }))
        .layer(middleware::from_fn_with_state(
            server_cfg.clone(),
            redirect_old_hosts,
        ))
        .with_state(server_cfg)
}

/// Collects the path literals returned by the `refresh_path` function in the
/// given dashboard home template source.
fn refresh_path_literals(source: &str) -> Vec<&str> {
    // Locate the function body up to its matching closing brace
    let start = source
        .find("fn refresh_path(")
        .expect("refresh_path function should exist");
    let body_start = start + source[start..].find('{').expect("function body should open");
    let mut depth = 0;
    let mut body_end = source.len();
    for (i, c) in source[body_start..].char_indices() {
        match c {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if depth == 0 {
                    body_end = body_start + i;
                    break;
                }
            }
            _ => {}
        }
    }
    let body = &source[body_start..body_end];

    // Read the string literal returned by each match arm, plain or in `Some`
    body.split("=>")
        .skip(1)
        .filter_map(|arm| {
            let arm = arm.trim_start();
            let literal = arm.strip_prefix("Some(").unwrap_or(arm).strip_prefix('"')?;
            Some(&literal[..literal.find('"').expect("path literal should close")])
        })
        .collect()
}

/// Extracts every `.route(` declaration of the router sections in source
/// order, with its full path and the methods it routes.
fn route_declarations() -> Vec<(String, Vec<Method>)> {
    const ROUTE_METHODS: [(&str, Method); 5] = [
        ("delete", Method::DELETE),
        ("get", Method::GET),
        ("patch", Method::PATCH),
        ("post", Method::POST),
        ("put", Method::PUT),
    ];

    // Scan each router section for route declarations and their method chains
    let mut declarations = Vec::new();
    for (prefix, section) in router_sections() {
        let mut rest = section;
        while let Some(index) = rest.find(".route(") {
            rest = &rest[index + ".route(".len()..];

            // Read the path literal and the arguments up to the matching parenthesis
            let path_start = rest.len() - rest.trim_start().len();
            assert!(
                rest[path_start..].starts_with('"'),
                "route path should be a literal: .route({}",
                &rest[..rest.len().min(80)]
            );
            let path_start = path_start + 1;
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

            // Record the methods routed on this path, mapping a nested root to the prefix
            let full_path = if path == "/" && !prefix.is_empty() {
                prefix.to_string()
            } else {
                format!("{prefix}{path}")
            };
            let methods = ROUTE_METHODS
                .iter()
                .filter(|(name, _)| contains_method_call(args, name))
                .map(|(_, method)| method.clone())
                .collect();
            declarations.push((full_path, methods));
            rest = &rest[args_end..];
        }
    }
    declarations
}

/// Lists the declared routes as E2E route manifest entries.
fn route_manifest() -> Vec<RouteManifestEntry> {
    declared_routes()
        .into_iter()
        .map(|(path, method)| RouteManifestEntry {
            method: method.to_string(),
            path,
        })
        .collect()
}

/// Returns the route prefix and source text of each router section that
/// declares application routes.
fn router_sections() -> [(&'static str, &'static str); 4] {
    const DASHBOARD_SOURCE: &str = include_str!("dashboard.rs");
    const ROUTER_SOURCE: &str = include_str!("../router.rs");
    let sections = [
        (
            ROUTER_SOURCE,
            "",
            "pub(crate) async fn setup(",
            Some("// Handlers."),
        ),
        (
            DASHBOARD_SOURCE,
            "/dashboard/community",
            "fn setup_community_dashboard_router",
            Some("fn setup_group_dashboard_router"),
        ),
        (
            DASHBOARD_SOURCE,
            "/dashboard/group",
            "fn setup_group_dashboard_router",
            Some("fn setup_user_dashboard_router"),
        ),
        (
            DASHBOARD_SOURCE,
            "/dashboard/user",
            "fn setup_user_dashboard_router",
            None,
        ),
    ];

    // Cut each section from its start marker to its end marker or the end of file
    sections.map(|(source, prefix, start_marker, end_marker)| {
        let start = source.find(start_marker).expect("router section should exist");
        let end = end_marker.map_or(source.len(), |marker| {
            source.find(marker).expect("router section end should exist")
        });
        (prefix, &source[start..end])
    })
}

/// Builds a database answering the site settings read of a rendered page.
fn site_settings_db() -> MockDB {
    let mut db = MockDB::new();
    expect_site_settings(&mut db);
    db
}

/// Finds an embedded static asset path matching the given prefix and suffix.
fn static_path_with_prefix_and_suffix(prefix: &str, suffix: &str) -> String {
    StaticFile::iter()
        .find(|path| path.starts_with(prefix) && path.ends_with(suffix))
        .unwrap_or_else(|| panic!("{prefix} asset ending with {suffix} to exist"))
        .to_string()
}
