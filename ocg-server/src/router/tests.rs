use std::{
    borrow::Cow,
    collections::{BTreeMap, BTreeSet, VecDeque},
    env, fs,
    path::{Path, PathBuf},
};

use anyhow::anyhow;
use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderValue, Method, StatusCode, Uri,
        header::{COOKIE, LOCATION, SET_COOKIE},
        response::Parts,
    },
};
use axum_login::tower_sessions::session;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    db::mock::{MockDB, expect_site_settings},
    handlers::tests::*,
    services::{images::MockImagesManager, payments::MockPaymentsManager},
    types::{
        images::Image,
        permissions::{CommunityPermission, GroupPermission},
        tests::sample_site_settings,
    },
};

use super::*;

/// Unsafe routes that accept requests without browser origin headers.
///
/// External webhook providers authenticate with signatures and stateless Open
/// Badges verification accepts CLI/API clients without browser headers (while
/// still rejecting explicit cross-site browser signals).
pub(super) const HEADERLESS_EXEMPT_ROUTES: [&str; 4] = [
    "/badges/verify",
    "/webhooks/payments",
    "/webhooks/payments/connected",
    "/webhooks/zoom",
];

/// Response header the matched-path test layer echoes the matched path in.
const MATCHED_PATH_TEST_HEADER: &str = "x-test-matched-path";

/// Dashboard routes posting a request body too long for a query string
/// without changing state.
///
/// Only their `POST` method is guarded by read access instead of a write
/// permission.
const READ_ONLY_POST_ROUTES: [&str; 1] = ["/dashboard/community/contact/recipients"];

/// E2E route manifest path, relative to the server crate directory.
pub(super) const ROUTE_MANIFEST_PATH: &str = "../tests/e2e/coverage/route-manifest.json";

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

/// Unsafe webhook routes registered outside all browser origin guard layers.
///
/// Providers call these webhooks server to server and authenticate with
/// signatures, so the real-router cross-site guard test exempts exactly these paths.
const WEBHOOK_ROUTES: [&str; 3] = [
    "/webhooks/payments",
    "/webhooks/payments/connected",
    "/webhooks/zoom",
];

/// Route entry of the E2E route manifest.
#[derive(Debug, Deserialize, PartialEq, Serialize)]
pub(super) struct RouteManifestEntry {
    /// HTTP method routed on the path.
    pub method: String,
    /// Route path template, as reported by the matched path.
    pub path: String,
}

impl RouteManifestEntry {
    /// Returns the `METHOD path` label used in mismatch reports.
    fn label(&self) -> String {
        format!("{} {}", self.method, self.path)
    }
}

/// Source language used when stripping comments before scanning for vendor asset references.
#[derive(Clone, Copy)]
enum AssetSourceKind {
    /// CSS stylesheet (`/* ... */` comments).
    Css,
    /// HTML or Askama template (`<!-- ... -->`, `{# ... #}`, and inline `<script>`/`<style>`).
    Html,
    /// JavaScript module (`// ...` and `/* ... */` comments).
    Js,
}

impl AssetSourceKind {
    /// Resolves the comment-stripping language for a file extension, if supported.
    fn from_extension(ext: &str) -> Option<Self> {
        match ext {
            "css" => Some(Self::Css),
            "html" => Some(Self::Html),
            "js" => Some(Self::Js),
            _ => None,
        }
    }
}

/// Source file scanned for references to vendored static assets.
struct VendorRefSource {
    /// Raw file contents.
    content: String,
    /// Source language used for comment stripping.
    kind: AssetSourceKind,

    /// Directory relative to `/static/` for resolving relative URLs, when served under `/static/`.
    static_dir: Option<String>,
}

#[tokio::test]
async fn test_browser_same_origin_allows_exempt_routes_without_browser_headers() {
    // Setup mocks for stateless badge verification and payment webhooks
    let award = sample_user_badge();
    let badge_id = award.user_badge_id;
    let mut db = site_settings_db();
    db.expect_get_public_user_badge()
        .times(1)
        .withf(move |id| *id == badge_id)
        .return_once(move |_| Ok(Some(award)));
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_handle_webhook()
        .times(1)
        .returning(|_, _| Box::pin(async { Ok(()) }));
    payments_manager
        .expect_handle_connected_webhook()
        .times(1)
        .returning(|_, _| Box::pin(async { Ok(()) }));
    let router = TestRouterBuilder::new(db)
        .with_meetings_cfg(sample_zoom_meetings_cfg("zoom-secret"))
        .with_payments_cfg(sample_payments_cfg())
        .with_payments_manager(payments_manager)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;

    // Send a headerless POST to badge verification and check it verifies the active award
    let (badge_parts, badge_bytes) = send(router.clone(), badge_verify_request(badge_id)).await;
    assert_html_response(&badge_parts, &badge_bytes, StatusCode::OK);
    assert!(String::from_utf8_lossy(&badge_bytes).contains("Valid and active"));

    // Explicit cross-site browser POSTs to badge verification are still rejected
    for (case, header_name, header_value) in [
        ("cross-site fetch metadata", "sec-fetch-site", "cross-site"),
        ("foreign origin", "origin", "https://attacker.test"),
    ] {
        let mut cross_site_request = badge_verify_request(badge_id);
        cross_site_request.headers_mut().insert(
            HeaderName::from_static(header_name),
            HeaderValue::from_static(header_value),
        );
        let (parts, _) = send(router.clone(), cross_site_request).await;
        assert_eq!(
            parts.status,
            StatusCode::FORBIDDEN,
            "POST /badges/verify ({case})"
        );
    }

    // Send headerless webhook POSTs and check they reach their handlers
    for (path, expected_status) in [
        ("/webhooks/payments", StatusCode::OK),
        ("/webhooks/payments/connected", StatusCode::OK),
        ("/webhooks/zoom", StatusCode::UNAUTHORIZED),
    ] {
        let webhook_request = request("POST", path).body(Body::empty()).unwrap();
        let (parts, _) = send(router.clone(), webhook_request).await;
        assert_eq!(parts.status, expected_status, "POST {path}");
    }
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_browser_same_origin_middleware_enforces_browser_signals() {
    // Setup a mutation route protected by the browser-origin middleware
    let router = Router::new()
        .route(
            "/",
            delete(|| async { StatusCode::NO_CONTENT })
                .get(|| async { StatusCode::NO_CONTENT })
                .post(|| async { StatusCode::NO_CONTENT })
                .put(|| async { StatusCode::NO_CONTENT }),
        )
        .route(
            "/reset-password/{token}",
            post(|| async { StatusCode::NO_CONTENT }),
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
            StatusCode::FORBIDDEN,
        ),
        (
            "put without browser signals",
            Method::PUT,
            None,
            None,
            None,
            StatusCode::FORBIDDEN,
        ),
        (
            "delete without browser signals",
            Method::DELETE,
            None,
            None,
            None,
            StatusCode::FORBIDDEN,
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
            "null origin rejected on ordinary routes even with same-origin fetch",
            Method::POST,
            Some("same-origin"),
            Some("null"),
            None,
            StatusCode::FORBIDDEN,
        ),
        (
            "null origin without fetch metadata",
            Method::POST,
            None,
            Some("null"),
            None,
            StatusCode::FORBIDDEN,
        ),
        (
            "null origin from same-site fetch",
            Method::POST,
            Some("same-site"),
            Some("null"),
            None,
            StatusCode::FORBIDDEN,
        ),
        (
            "null origin from cross-site fetch",
            Method::POST,
            Some("cross-site"),
            Some("null"),
            None,
            StatusCode::FORBIDDEN,
        ),
        (
            "null origin with mismatched referer",
            Method::POST,
            Some("same-origin"),
            Some("null"),
            Some("https://attacker.test/page"),
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

    // Null origin with same-origin Fetch Metadata is accepted only on /reset-password/*
    let reset_null_origin = request("POST", "/reset-password/sample-token")
        .header("Sec-Fetch-Site", "same-origin")
        .header(ORIGIN, "null")
        .body(Body::empty())
        .unwrap();
    let (parts, _) = send(router.clone(), reset_null_origin).await;
    assert_eq!(parts.status, StatusCode::NO_CONTENT);

    // Null origin on /reset-password/* still fails closed without same-origin Fetch Metadata
    for (case, fetch_site) in [
        ("missing fetch metadata", None),
        ("same-site fetch", Some("same-site")),
        ("cross-site fetch", Some("cross-site")),
    ] {
        let mut req = request("POST", "/reset-password/sample-token").header(ORIGIN, "null");
        if let Some(fetch_site) = fetch_site {
            req = req.header("Sec-Fetch-Site", fetch_site);
        }
        let (parts, _) = send(router.clone(), req.body(Body::empty()).unwrap()).await;
        assert_eq!(parts.status, StatusCode::FORBIDDEN, "{case}");
    }

    // Conflicting duplicate Sec-Fetch-Site headers must also be rejected
    let duplicate_request = request("POST", "/")
        .header("Sec-Fetch-Site", "same-origin")
        .header("Sec-Fetch-Site", "cross-site")
        .body(Body::empty())
        .unwrap();
    let (parts, _) = send(router.clone(), duplicate_request).await;
    assert_eq!(parts.status, StatusCode::FORBIDDEN);

    // Duplicate Origin headers must be rejected regardless of header order
    for (case, first, second) in [
        ("site origin then null", "https://example.test", "null"),
        ("null then site origin", "null", "https://example.test"),
        (
            "site origin then foreign origin",
            "https://example.test",
            "https://attacker.test",
        ),
    ] {
        let req = request("POST", "/")
            .header("Sec-Fetch-Site", "same-origin")
            .header(ORIGIN, first)
            .header(ORIGIN, second)
            .body(Body::empty())
            .unwrap();
        let (parts, _) = send(router.clone(), req).await;
        assert_eq!(parts.status, StatusCode::FORBIDDEN, "{case}");
    }
}

#[tokio::test]
async fn test_reset_password_routes_omit_csp_report_uri() {
    for (case, report_only, expected_header) in [
        ("enforced csp", false, CONTENT_SECURITY_POLICY),
        ("report-only csp", true, CONTENT_SECURITY_POLICY_REPORT_ONLY),
    ] {
        // Setup router with email login and csp_report_uri configured
        let mut db = MockDB::new();
        db.expect_has_valid_password_reset_token()
            .times(1)
            .returning(|_| Ok(true));
        expect_site_settings(&mut db);
        let mut server_cfg = sample_server_cfg("https://example.test");
        server_cfg.login.email = true;
        server_cfg.security = SecurityConfig {
            csp_report_only: report_only,
            csp_report_uri: Some("https://csp.example.test/reports".to_string()),
        };
        let router = TestRouterBuilder::new(db).with_server_cfg(server_cfg).build().await;

        // Check ordinary routes retain report-uri while /reset-password/{token} omits it
        let (health_parts, _) = send(
            router.clone(),
            request("GET", "/health-check").body(Body::empty()).unwrap(),
        )
        .await;
        let health_csp = health_parts.headers.get(&expected_header).unwrap().to_str().unwrap();
        assert!(
            health_csp.contains("report-uri https://csp.example.test/reports"),
            "{case}"
        );

        let (reset_parts, _) = send(
            router,
            request("GET", "/reset-password/secret-token-value")
                .body(Body::empty())
                .unwrap(),
        )
        .await;
        assert_eq!(reset_parts.status, StatusCode::OK, "{case}");
        let reset_csp = reset_parts.headers.get(&expected_header).unwrap().to_str().unwrap();
        assert!(reset_csp.contains("default-src 'self'"), "{case}");
        assert!(!reset_csp.contains("report-uri"), "{case}: {reset_csp}");
        assert_eq!(
            reset_parts.headers.get(CACHE_CONTROL),
            Some(&HeaderValue::from_static(CACHE_CONTROL_NO_STORE)),
            "{case}"
        );
        assert_eq!(
            reset_parts.headers.get(REFERRER_POLICY),
            Some(&HeaderValue::from_static(REFERRER_POLICY_NO_REFERRER)),
            "{case}"
        );
    }
}

#[test]
fn test_sanitized_request_uri_redacts_auth_recovery_tokens() {
    let cases = [
        (
            "password reset route",
            "/reset-password/secret-token-abc",
            "/reset-password/{token}",
            "/reset-password/{token}",
        ),
        (
            "password reset route with query",
            "/reset-password/secret-token-abc?extra=1",
            "/reset-password/{token}",
            "/reset-password/{token}",
        ),
        (
            "unmatched password reset subpath",
            "/reset-password/secret-token-abc/extra",
            ROUTE_FALLBACK_PATH,
            "/reset-password/{token}",
        ),
        (
            "email verification route",
            "/verify-email/11111111-1111-1111-1111-111111111111",
            "/verify-email/{code}",
            "/verify-email/{code}",
        ),
        (
            "ordinary route preserved",
            "/forgot-password?ref=1",
            "/forgot-password",
            "/forgot-password?ref=1",
        ),
    ];

    for (case, uri, matched_path, expected) in cases {
        let req = Request::builder().uri(uri).body(Body::empty()).unwrap();
        let sanitized = sanitized_request_uri(&req, matched_path);
        assert_eq!(sanitized.as_ref(), expected, "{case}");
        assert!(!sanitized.contains("secret-token-abc"), "{case}");
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

    // Collect every declared unsafe route and verify the exempt lists stay in sync
    let all_unsafe_routes: Vec<_> = declared_routes()
        .into_iter()
        .filter(|(_, method)| *method != Method::GET)
        .collect();
    let webhook_paths: Vec<_> = all_unsafe_routes
        .iter()
        .filter(|(path, _)| WEBHOOK_ROUTES.contains(&path.as_str()))
        .map(|(path, _)| path.as_str())
        .collect();
    assert_eq!(
        webhook_paths, WEBHOOK_ROUTES,
        "every WEBHOOK_ROUTES entry should be a declared unsafe route"
    );
    let headerless_paths: Vec<_> = all_unsafe_routes
        .iter()
        .filter(|(path, _)| HEADERLESS_EXEMPT_ROUTES.contains(&path.as_str()))
        .map(|(path, _)| path.as_str())
        .collect();
    assert_eq!(
        headerless_paths, HEADERLESS_EXEMPT_ROUTES,
        "every HEADERLESS_EXEMPT_ROUTES entry should be a declared unsafe route"
    );
    assert!(
        !all_unsafe_routes.is_empty(),
        "router should expose unsafe routes"
    );

    // Check every non-webhook unsafe route rejects cross-site requests and every
    // non-headerless-exempt unsafe route also rejects headerless requests
    for (path, method) in all_unsafe_routes {
        if WEBHOOK_ROUTES.contains(&path.as_str()) {
            continue;
        }

        let cross_site_request = request(method.as_str(), &concrete_uri(&path))
            .header("Sec-Fetch-Site", "cross-site")
            .body(Body::empty())
            .unwrap();
        let (parts, _) = send(router.clone(), cross_site_request).await;
        assert_eq!(
            parts.status,
            StatusCode::FORBIDDEN,
            "{method} {path} (cross-site) is not protected by an origin guard"
        );

        if HEADERLESS_EXEMPT_ROUTES.contains(&path.as_str()) {
            continue;
        }

        let headerless_request = request(method.as_str(), &concrete_uri(&path))
            .body(Body::empty())
            .unwrap();
        let (parts, _) = send(router.clone(), headerless_request).await;
        assert_eq!(
            parts.status,
            StatusCode::FORBIDDEN,
            "{method} {path} (missing browser headers) is not protected by the browser same-origin guard"
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
async fn test_content_security_policy_enforced_report_only_and_svg_sandbox() {
    // Setup labeled security configurations: (case, report_only, report_uri)
    let cases = [
        ("default enforced csp", false, None),
        (
            "enforced csp with report uri",
            false,
            Some("https://reports.example.test/csp"),
        ),
        ("report-only csp", true, None),
        (
            "report-only csp with report uri",
            true,
            Some("/csp-reports"),
        ),
    ];

    for (case, csp_report_only, csp_report_uri) in cases {
        // Setup router with an SVG stored image and the case security settings
        let mut images_manager = MockImagesManager::new();
        images_manager.expect_get().times(1).returning(|_| {
            Box::pin(async {
                Ok(Some(Image {
                    bytes: b"<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>".to_vec(),
                    content_type: "image/svg+xml".to_string(),
                }))
            })
        });
        let server_cfg = HttpServerConfig {
            security: SecurityConfig {
                csp_report_only,
                csp_report_uri: csp_report_uri.map(str::to_string),
            },
            ..sample_server_cfg("https://example.test")
        };
        let router = TestRouterBuilder::new(MockDB::new())
            .with_images_manager(images_manager)
            .with_server_cfg(server_cfg)
            .build()
            .await;

        // Check regular responses carry the configured CSP header and directives
        let (parts, _) = send(
            router.clone(),
            request("GET", "/health-check").body(Body::empty()).unwrap(),
        )
        .await;
        assert_eq!(parts.status, StatusCode::OK, "{case}");

        let (expected_header, absent_header) = if csp_report_only {
            (CONTENT_SECURITY_POLICY_REPORT_ONLY, CONTENT_SECURITY_POLICY)
        } else {
            (CONTENT_SECURITY_POLICY, CONTENT_SECURITY_POLICY_REPORT_ONLY)
        };
        let csp = parts.headers.get(&expected_header).unwrap().to_str().unwrap();
        assert!(parts.headers.get(&absent_header).is_none(), "{case}");
        for directive in [
            "default-src 'self'",
            &format!("script-src 'self' {CSP_SCRIPT_HASHES}"),
            "style-src 'self' 'unsafe-inline'",
            "font-src 'self' data:",
            "img-src 'self' data: blob: https:",
            "connect-src 'self' https://tiles.openfreemap.org https://nominatim.openstreetmap.org",
            "worker-src 'self' blob:",
            "frame-ancestors 'none'",
            "object-src 'none'",
            "base-uri 'self'",
        ] {
            assert!(
                csp.contains(directive),
                "{case}: missing {directive} in {csp}"
            );
        }
        if let Some(uri) = csp_report_uri {
            assert!(
                csp.ends_with(&format!("; report-uri {uri}")),
                "{case}: {csp}"
            );
        } else {
            assert!(!csp.contains("report-uri"), "{case}: {csp}");
        }

        // Check SVG image responses keep their stricter sandbox CSP
        let svg_request = request("GET", "/images/sample.svg")
            .header(ORIGIN, "https://example.test")
            .body(Body::empty())
            .unwrap();
        let (svg_parts, _) = send(router, svg_request).await;
        assert_eq!(svg_parts.status, StatusCode::OK, "{case}");
        let svg_csp_values: Vec<_> =
            svg_parts.headers.get_all(CONTENT_SECURITY_POLICY).iter().collect();
        assert_eq!(
            svg_csp_values,
            [&HeaderValue::from_static("sandbox")],
            "{case}"
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
async fn test_public_shared_cache_not_found_page_ignores_viewer_preferences() {
    assert_public_response_ignores_viewer_preferences("/missing/page", StatusCode::NOT_FOUND).await;
}

#[tokio::test]
async fn test_public_shared_cache_page_ignores_viewer_preferences() {
    assert_public_response_ignores_viewer_preferences("/docs", StatusCode::OK).await;
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
            request("POST", "/log-out")
                .header("Sec-Fetch-Site", "same-origin")
                .body(Body::empty())
                .unwrap(),
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
#[allow(clippy::too_many_lines)]
async fn test_security_headers_are_applied_to_responses_with_conditional_hsts() {
    // Setup labeled base URLs with whether canonical responses should emit HSTS
    let cases = [
        ("http base url omits hsts", "http://localhost:9000", false),
        ("https base url emits hsts", "https://example.test", true),
        (
            "uppercase https base url emits hsts",
            "HTTPS://example.test",
            true,
        ),
    ];

    for (case, base_url, expect_hsts) in cases {
        // Setup the router with a legacy redirect host and an image response that already sets nosniff
        let mut images_manager = MockImagesManager::new();
        images_manager.expect_get().times(1).returning(|_| {
            Box::pin(async {
                Ok(Some(Image {
                    bytes: b"png".to_vec(),
                    content_type: "image/png".to_string(),
                }))
            })
        });
        let server_cfg = HttpServerConfig {
            redirect_hosts: Some(vec!["old.example.test".to_string()]),
            ..sample_server_cfg(base_url)
        };
        let router = TestRouterBuilder::new(MockDB::new())
            .with_images_manager(images_manager)
            .with_server_cfg(server_cfg)
            .build()
            .await;

        // Check canonical responses and legacy-host redirects
        let requests = [
            (
                "health check",
                request("GET", "/health-check").body(Body::empty()).unwrap(),
                StatusCode::OK,
                expect_hsts,
            ),
            (
                "static asset",
                request("GET", "/static/images/icons/arrow_left.svg")
                    .body(Body::empty())
                    .unwrap(),
                StatusCode::OK,
                expect_hsts,
            ),
            (
                "stored image",
                request("GET", "/images/sample.png")
                    .header(ORIGIN, base_url)
                    .body(Body::empty())
                    .unwrap(),
                StatusCode::OK,
                expect_hsts,
            ),
            (
                "rejected headerless post",
                request("POST", "/log-out").body(Body::empty()).unwrap(),
                StatusCode::FORBIDDEN,
                expect_hsts,
            ),
            (
                "stale client refresh",
                request("GET", "/health-check")
                    .header("HX-Request", "true")
                    .header(COMMIT_SHA_HEADER, "older-commit")
                    .body(Body::empty())
                    .unwrap(),
                StatusCode::NO_CONTENT,
                expect_hsts,
            ),
            (
                "legacy redirect host omits hsts",
                request("GET", "/health-check")
                    .header(HOST, "old.example.test")
                    .body(Body::empty())
                    .unwrap(),
                StatusCode::PERMANENT_REDIRECT,
                false,
            ),
        ];

        for (route_case, request, expected_status, expect_route_hsts) in requests {
            let (parts, _) = send(router.clone(), request).await;
            assert_eq!(parts.status, expected_status, "{case}: {route_case}");
            assert_eq!(
                parts.headers.get("permissions-policy").unwrap(),
                "camera=(self), microphone=(), geolocation=(), payment=(), usb=()",
                "{case}: {route_case}"
            );
            assert_eq!(
                parts.headers.get("referrer-policy").unwrap(),
                "strict-origin-when-cross-origin",
                "{case}: {route_case}"
            );
            let nosniff_values: Vec<_> =
                parts.headers.get_all("x-content-type-options").iter().collect();
            assert_eq!(
                nosniff_values,
                [&HeaderValue::from_static("nosniff")],
                "{case}: {route_case}"
            );
            assert_eq!(
                parts.headers.get("x-frame-options").unwrap(),
                "DENY",
                "{case}: {route_case}"
            );
            if expect_route_hsts {
                assert_eq!(
                    parts.headers.get("strict-transport-security").unwrap(),
                    "max-age=31536000",
                    "{case}: {route_case}"
                );
            } else {
                assert!(
                    parts.headers.get("strict-transport-security").is_none(),
                    "{case}: {route_case}"
                );
            }
        }
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

#[test]
fn test_static_assets_e2e_images_follow_build_profile() {
    // Check build-time e2e exclusion cfg and embedded static assets match the active Cargo profile
    let env_included = option_env!("OCG_INCLUDE_E2E_ASSETS").is_some_and(|v| v.trim() == "1");
    let expected_excluded = env!("OCG_BUILD_PROFILE") == "release" && !env_included;
    assert_eq!(cfg!(ocg_exclude_e2e_assets), expected_excluded);

    let has_e2e_images = StaticFile::iter().any(|path| path.starts_with("images/e2e/"));
    assert_eq!(has_e2e_images, !expected_excluded);
}

#[test]
fn test_static_assets_exclude_dotfiles() {
    // Check embedded static assets exclude dotfiles such as .prettierrc.yaml and .DS_Store
    let static_paths: Vec<String> = StaticFile::iter().map(Cow::into_owned).collect();
    assert_ne!(static_paths.len(), 0);
    let static_dotfiles: Vec<&str> = static_paths
        .iter()
        .map(String::as_str)
        .filter(|path| has_dot_segment(path))
        .collect();
    assert!(
        static_dotfiles.is_empty(),
        "unexpected dotfiles in dist/static: {}",
        static_dotfiles.join(", ")
    );

    // Check copied dist templates exclude dotfiles such as .djlintrc
    let dist_templates_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("dist/templates");
    let mut template_paths = Vec::new();
    collect_relative_paths(
        &dist_templates_dir,
        &dist_templates_dir,
        &mut template_paths,
    );
    assert_ne!(template_paths.len(), 0);
    let template_dotfiles: Vec<&str> = template_paths
        .iter()
        .map(String::as_str)
        .filter(|path| has_dot_segment(path))
        .collect();
    assert!(
        template_dotfiles.is_empty(),
        "unexpected dotfiles in dist/templates: {}",
        template_dotfiles.join(", ")
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
            "hashed docs css",
            format!(
                "/static/{}",
                static_path_with_prefix_and_suffix("css/docs/", ".css")
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
            "/static/vendor/js/htmx.v2.0.10.min.js".to_string(),
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
async fn test_static_handler_serves_docs_index_with_hashed_theme() {
    // Run handler
    let uri = Uri::from_static("/static/docs/index.html");
    let response = static_handler(uri).await.into_response();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the index links the content-hashed docs theme
    assert_eq!(parts.status, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    let theme_prefix = "/static/css/docs/theme.";
    let hash_start =
        body.find(theme_prefix).expect("docs theme link to exist") + theme_prefix.len();
    let hash = body.get(hash_start..hash_start + 8).unwrap_or_default();
    assert_eq!(hash.len(), 8, "{body}");
    assert!(
        hash.chars().all(|c| matches!(c, '0'..='9' | 'a'..='f')),
        "{body}"
    );
    assert!(body[hash_start + 8..].starts_with(".css\""), "{body}");
    assert!(!body.contains("assets/theme.css"), "{body}");
}

#[test]
fn test_static_vendor_comment_stripper_preserves_minified_bundles() {
    // Collect vendored JS bundles and locate each regex-heavy bundle by prefix
    let vendor_js_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("static/vendor/js");
    let mut vendor_js_files = Vec::new();
    collect_non_dotfile_paths(&vendor_js_dir, &mut vendor_js_files);

    // Check minified bundles containing slash/backtick regexes are not truncated
    for prefix in ["docsify.v", "easymde.v", "echarts.v"] {
        let bundle_path = vendor_js_files
            .iter()
            .find(|path| {
                path.file_name()
                    .and_then(|name| name.to_str())
                    .is_some_and(|name| name.starts_with(prefix) && name.ends_with(".min.js"))
            })
            .unwrap_or_else(|| panic!("expected vendored bundle matching {prefix}*.min.js"));
        let raw = fs::read_to_string(bundle_path).unwrap();
        let stripped = strip_asset_source_comments(&raw, AssetSourceKind::Js);
        assert!(
            stripped.len() * 100 >= raw.len() * 95,
            "{} lost too much content during comment stripping ({} -> {} bytes)",
            bundle_path.display(),
            raw.len(),
            stripped.len()
        );
    }
}

#[test]
fn test_static_vendor_files_are_all_referenced() {
    // Collect every non-dotfile asset under static/vendor
    let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    let vendor_dir = manifest_dir.join("static/vendor");
    let mut vendor_paths = Vec::new();
    collect_non_dotfile_paths(&vendor_dir, &mut vendor_paths);
    assert_ne!(vendor_paths.len(), 0);

    let mut vendor_files = BTreeMap::new();
    for path in vendor_paths {
        let rel = path
            .strip_prefix(&vendor_dir)
            .unwrap()
            .to_string_lossy()
            .replace('\\', "/");
        let content = fs::read_to_string(&path).ok();
        vendor_files.insert(rel, content);
    }

    // Read templates, JS modules, source CSS, and docs assets that may reference vendor files
    let generated_styles_css = manifest_dir.join("static/css/styles.css");
    let source_roots = [
        (manifest_dir.join("templates"), None, &["html", "js"][..]),
        (manifest_dir.join("static/js"), Some("js"), &["js"][..]),
        (manifest_dir.join("static/css"), Some("css"), &["css"][..]),
        (
            manifest_dir.join("../docs"),
            Some("docs"),
            &["css", "html", "js"][..],
        ),
    ];
    let mut sources = Vec::new();
    for (root, static_prefix, allowed_exts) in source_roots {
        let mut files = Vec::new();
        collect_non_dotfile_paths(&root, &mut files);
        for file in files {
            if file == generated_styles_css {
                continue;
            }
            let Some(ext) = file.extension().and_then(|ext| ext.to_str()) else {
                continue;
            };
            if !allowed_exts.contains(&ext) {
                continue;
            }
            let Some(kind) = AssetSourceKind::from_extension(ext) else {
                panic!("unexpected source extension: {ext}");
            };
            let static_dir = static_prefix.map(|prefix| {
                let rel = file.strip_prefix(&root).unwrap().to_string_lossy().replace('\\', "/");
                let (rel_dir, _) = split_rel_path(&rel);
                if rel_dir.is_empty() {
                    prefix.to_string()
                } else {
                    format!("{prefix}/{rel_dir}")
                }
            });
            sources.push(VendorRefSource {
                content: fs::read_to_string(&file).unwrap(),
                kind,
                static_dir,
            });
        }
    }
    assert_ne!(sources.len(), 0);

    // Check every vendored file is referenced directly, transitively, or as a companion license
    let unreferenced = find_unreferenced_vendor_files(&vendor_files, &sources);
    assert!(
        unreferenced.is_empty(),
        "found unreferenced files under ocg-server/static/vendor/:\n{}",
        unreferenced.join("\n")
    );
}

#[test]
fn test_static_vendor_reference_scanner_detects_unreferenced_files() {
    // Setup synthetic vendor files covering direct, relative, transitive, cyclic, and license cases
    let vendor_files = BTreeMap::from([
        ("css/icons.woff2".to_string(), None),
        (
            "css/theme.v1.min.css".to_string(),
            Some("src:url(../fonts/theme.woff2),url(icons.woff2)".to_string()),
        ),
        ("fonts/font.woff2".to_string(), None),
        ("fonts/theme.woff2".to_string(), None),
        ("js/app.LICENSE.txt".to_string(), Some("MIT".to_string())),
        ("js/app.v0.min.js".to_string(), Some("old".to_string())),
        ("js/app.v1.min.js".to_string(), Some("new".to_string())),
        ("js/app.v1.min.js.map".to_string(), Some("map".to_string())),
        ("js/exact-license.min.js".to_string(), Some("e".to_string())),
        (
            "js/exact-license.min.js.LICENSE.txt".to_string(),
            Some("MIT".to_string()),
        ),
        (
            "js/orphan-a.js".to_string(),
            Some(r#"import("./orphan-b.js");"#.to_string()),
        ),
        (
            "js/orphan-b.js".to_string(),
            Some(r#"import("./orphan-a.js");"#.to_string()),
        ),
        (
            "js/scanner-worker.min.js".to_string(),
            Some("worker".to_string()),
        ),
        (
            "js/scanner.min.js".to_string(),
            Some(r#"import("./scanner-worker.min.js");"#.to_string()),
        ),
        ("js/stale.LICENSE".to_string(), Some("BSD".to_string())),
        ("js/stale.min.js".to_string(), Some("stale".to_string())),
    ]);
    let sources = vec![
        VendorRefSource {
            content: concat!(
                r#"<link href="/static/vendor/css/theme.v1.min.css">"#,
                r#"<script src="/static/vendor/js/app.v1.min.js"></script>"#,
            )
            .to_string(),
            kind: AssetSourceKind::Html,
            static_dir: None,
        },
        VendorRefSource {
            content: concat!(
                "import S from \"../../../../vendor/js/scanner.min.js\";\n",
                "import \"/static/vendor/js/exact-license.min.js\";\n",
            )
            .to_string(),
            kind: AssetSourceKind::Js,
            static_dir: Some("js/dashboard/group/check-in".to_string()),
        },
        VendorRefSource {
            content: "src: url(/static/vendor/fonts/font.woff2) format('woff2');".to_string(),
            kind: AssetSourceKind::Css,
            static_dir: Some("css".to_string()),
        },
    ];

    // Check only genuinely unreferenced files and orphaned licenses are reported
    assert_eq!(
        find_unreferenced_vendor_files(&vendor_files, &sources),
        vec![
            "js/app.v0.min.js",
            "js/app.v1.min.js.map",
            "js/orphan-a.js",
            "js/orphan-b.js",
            "js/stale.LICENSE",
            "js/stale.min.js",
        ]
    );
}

#[test]
fn test_static_vendor_reference_scanner_ignores_comments_and_preserves_js_literals() {
    // Setup synthetic vendor files referenced inside comments, inline blocks, or after JS regexes
    let vendor_files = BTreeMap::from([
        ("fonts/commented-inline-style.woff2".to_string(), None),
        ("fonts/commented.woff2".to_string(), None),
        (
            "js/commented-after-control-regex.min.js".to_string(),
            Some("c".to_string()),
        ),
        (
            "js/commented-after-template.min.js".to_string(),
            Some("t".to_string()),
        ),
        (
            "js/commented-askama.min.js".to_string(),
            Some("a".to_string()),
        ),
        (
            "js/commented-html.min.js".to_string(),
            Some("h".to_string()),
        ),
        (
            "js/commented-inline-askama.min.js".to_string(),
            Some("ia".to_string()),
        ),
        (
            "js/commented-inline-script.min.js".to_string(),
            Some("i".to_string()),
        ),
        ("js/commented-js.min.js".to_string(), Some("j".to_string())),
        ("js/lit.min.js".to_string(), Some("lit".to_string())),
        (
            "js/minified-worker.min.js".to_string(),
            Some("worker".to_string()),
        ),
        (
            "js/minified.min.js".to_string(),
            Some(
                r#"var a=e.replace(/^\//,""),b=/WebKit\//.test(e),c=s.replace(/\`/g,"`1");import("./minified-worker.min.js");"#
                    .to_string(),
            ),
        ),
        ("js/stale.min.js".to_string(), Some("stale".to_string())),
    ]);
    let sources = vec![
        VendorRefSource {
            content: concat!(
                r#"<script type="importmap">{"imports":{"lit":"/static/vendor/js/lit.min.js"}}</script>"#,
                r#"<script type="module">// import "/static/vendor/js/commented-inline-script.min.js";</script>"#,
                r#"<script type="module">{# import "/static/vendor/js/commented-inline-askama.min.js"; #}</script>"#,
                r#"<style>/* url(/static/vendor/fonts/commented-inline-style.woff2) */</style>"#,
                r#"<!-- <script src="/static/vendor/js/commented-html.min.js"></script> -->"#,
                r#"{# <script src="/static/vendor/js/commented-askama.min.js"></script> #}"#,
            )
            .to_string(),
            kind: AssetSourceKind::Html,
            static_dir: None,
        },
        VendorRefSource {
            content: concat!(
                "const api = \"https://example.test\";\n",
                "const re = /[\"'\\n]/g;\n",
                "if (ok) /'/.test(v); // import \"/static/vendor/js/commented-after-control-regex.min.js\";\n",
                "const tpl = html`<div>${ok ? html`<span>x</span>` : \"\"}</div>`;\n",
                "// import \"/static/vendor/js/commented-after-template.min.js\";\n",
                "// import \"/static/vendor/js/commented-js.min.js\";\n",
                "/* import \"/static/vendor/js/stale.min.js\"; */\n",
                "import \"/static/vendor/js/minified.min.js\";\n",
            )
            .to_string(),
            kind: AssetSourceKind::Js,
            static_dir: Some("js/common".to_string()),
        },
        VendorRefSource {
            content: "/* url(/static/vendor/fonts/commented.woff2) */".to_string(),
            kind: AssetSourceKind::Css,
            static_dir: Some("css".to_string()),
        },
    ];

    // Check commented references are ignored while importmap and post-regex imports stay live
    assert_eq!(
        find_unreferenced_vendor_files(&vendor_files, &sources),
        vec![
            "fonts/commented-inline-style.woff2",
            "fonts/commented.woff2",
            "js/commented-after-control-regex.min.js",
            "js/commented-after-template.min.js",
            "js/commented-askama.min.js",
            "js/commented-html.min.js",
            "js/commented-inline-askama.min.js",
            "js/commented-inline-script.min.js",
            "js/commented-js.min.js",
            "js/stale.min.js",
        ]
    );
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

/// Sends the same public request without and with viewer preference cookies
/// and the color scheme client hint, then asserts both responses match.
async fn assert_public_response_ignores_viewer_preferences(path: &str, status: StatusCode) {
    // Setup database mock answering both site settings reads with one value
    let site_settings = sample_site_settings();
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(2)
        .returning(move || Ok(site_settings.clone()));

    // Send the request without and with viewer preferences
    let router = TestRouterBuilder::new(db).build().await;
    let plain_request = request("GET", path).body(Body::empty()).unwrap();
    let (plain_parts, plain_bytes) = send(router.clone(), plain_request).await;
    let preferences_request = request("GET", path)
        .header(COOKIE, "ocg_theme=dark; ocg_viewport_mode=desktop")
        .header("Sec-CH-Prefers-Color-Scheme", "dark")
        .body(Body::empty())
        .unwrap();
    let (preferences_parts, preferences_bytes) = send(router, preferences_request).await;

    // Check both responses are public shared-cache pages without cookies or client hints
    for (parts, bytes) in [
        (&plain_parts, &plain_bytes),
        (&preferences_parts, &preferences_bytes),
    ] {
        assert_html_response(parts, bytes, status);
        assert_public_response_without_set_cookie(parts);
        assert_eq!(
            parts.headers.get(CACHE_CONTROL).unwrap(),
            &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
        );
        let vary: Vec<_> = parts.headers.get_all(VARY).iter().collect();
        assert_eq!(vary, [&HeaderValue::from_static(PUBLIC_SHARED_CACHE_VARY)]);
        assert!(parts.headers.get("Accept-CH").is_none());
        assert!(parts.headers.get("Critical-CH").is_none());
    }

    // Check the viewer preferences change neither the cache headers nor the body
    for header in [CACHE_CONTROL, VARY] {
        assert_eq!(
            plain_parts.headers.get_all(&header).iter().collect::<Vec<_>>(),
            preferences_parts.headers.get_all(&header).iter().collect::<Vec<_>>(),
            "{header}"
        );
    }
    assert_eq!(plain_bytes, preferences_bytes);
}

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

/// Recursively collects regular non-dotfile paths under `dir`.
fn collect_non_dotfile_paths(dir: &Path, files: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(dir).unwrap() {
        let entry = entry.unwrap();
        if entry.file_name().as_encoded_bytes().starts_with(b".") {
            continue;
        }
        let path = entry.path();
        if path.is_dir() {
            collect_non_dotfile_paths(&path, files);
        } else if path.is_file() {
            files.push(path);
        }
    }
}

/// Recursively collects forward-slash relative paths of files and dot-entries under `dir`.
fn collect_relative_paths(root: &Path, dir: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(dir).unwrap() {
        let entry = entry.unwrap();
        let path = entry.path();
        let rel = path.strip_prefix(root).unwrap().to_string_lossy().replace('\\', "/");
        if entry.file_name().as_encoded_bytes().starts_with(b".") {
            paths.push(rel);
            continue;
        }
        if entry.file_type().unwrap().is_dir() {
            collect_relative_paths(root, &path, paths);
        } else {
            paths.push(rel);
        }
    }
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

/// Returns whether `content` references `asset_path` inside asset path delimiters.
fn contains_delimited_asset_ref(content: &str, asset_path: &str) -> bool {
    let bytes = content.as_bytes();
    content.match_indices(asset_path).any(|(start, _)| {
        let end = start + asset_path.len();
        let before_ok = start
            .checked_sub(1)
            .is_some_and(|i| matches!(bytes[i], b'"' | b'\'' | b'`' | b'('));
        let after_ok = bytes
            .get(end)
            .is_some_and(|b| matches!(b, b'"' | b'\'' | b'`' | b')' | b'?' | b'#'));
        before_ok && after_ok
    })
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

/// Returns whether `content` references `target_vendor_rel` by absolute or relative URL.
fn contains_vendor_asset_ref(
    content: &str,
    from_static_dir: Option<&str>,
    target_vendor_rel: &str,
) -> bool {
    let public_path = format!("/static/vendor/{target_vendor_rel}");
    if contains_delimited_asset_ref(content, &public_path) {
        return true;
    }

    if let Some(from_dir) = from_static_dir {
        let target_static_path = format!("vendor/{target_vendor_rel}");
        let rel_ref = relative_static_path(from_dir, &target_static_path);
        if contains_delimited_asset_ref(content, &rel_ref) {
            return true;
        }
        if let Some(bare_ref) = rel_ref.strip_prefix("./")
            && contains_delimited_asset_ref(content, bare_ref)
        {
            return true;
        }
    }

    false
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
pub(super) fn declared_routes() -> Vec<(String, Method)> {
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

/// Finds the first ASCII case-insensitive occurrence of `needle_lower` in `haystack`.
fn find_ascii_case_insensitive(haystack: &str, needle_lower: &str) -> Option<usize> {
    let hay = haystack.as_bytes();
    let needle = needle_lower.as_bytes();
    hay.windows(needle.len())
        .position(|window| window.eq_ignore_ascii_case(needle))
}

/// Returns vendor asset paths (relative to `static/vendor/`) that are not
/// referenced directly by `sources`, transitively by a referenced vendor
/// asset, or as a companion license for a referenced library.
fn find_unreferenced_vendor_files(
    vendor_files: &BTreeMap<String, Option<String>>,
    sources: &[VendorRefSource],
) -> Vec<String> {
    // Strip comments from application sources before scanning for active asset references
    let stripped_sources: Vec<(Option<&str>, String)> = sources
        .iter()
        .map(|source| {
            (
                source.static_dir.as_deref(),
                strip_asset_source_comments(&source.content, source.kind),
            )
        })
        .collect();

    // Seed reachability with vendor assets referenced directly from application sources
    let mut referenced = BTreeSet::new();
    let mut queue = VecDeque::new();
    for rel_path in vendor_files.keys() {
        if stripped_sources
            .iter()
            .any(|(static_dir, content)| contains_vendor_asset_ref(content, *static_dir, rel_path))
            && referenced.insert(rel_path.clone())
        {
            queue.push_back(rel_path.clone());
        }
    }

    // Follow absolute and relative references emitted by already-referenced vendor assets
    while let Some(referrer) = queue.pop_front() {
        let Some(Some(raw_content)) = vendor_files.get(&referrer) else {
            continue;
        };
        let content = match Path::new(&referrer)
            .extension()
            .and_then(|ext| ext.to_str())
            .and_then(AssetSourceKind::from_extension)
        {
            Some(kind) => Cow::Owned(strip_asset_source_comments(raw_content, kind)),
            None => Cow::Borrowed(raw_content.as_str()),
        };
        let (referrer_dir, _) = split_rel_path(&referrer);
        let referrer_static_dir = if referrer_dir.is_empty() {
            "vendor".to_string()
        } else {
            format!("vendor/{referrer_dir}")
        };
        for candidate in vendor_files.keys() {
            if referenced.contains(candidate) {
                continue;
            }
            if contains_vendor_asset_ref(&content, Some(&referrer_static_dir), candidate)
                && referenced.insert(candidate.clone())
            {
                queue.push_back(candidate.clone());
            }
        }
    }

    // Allow companion license files paired with a referenced library in the same directory
    let referenced_assets: Vec<String> = referenced.iter().cloned().collect();
    for rel_path in vendor_files.keys() {
        if referenced.contains(rel_path) {
            continue;
        }
        let (dir, file_name) = split_rel_path(rel_path);
        let Some(prefix) = vendor_license_prefix(file_name) else {
            continue;
        };
        let prefix_with_dot = format!("{prefix}.");
        let has_paired_asset = referenced_assets.iter().any(|asset| {
            let (asset_dir, asset_name) = split_rel_path(asset);
            asset_dir == dir
                && vendor_license_prefix(asset_name).is_none()
                && (asset_name == prefix || asset_name.starts_with(&prefix_with_dot))
        });
        if has_paired_asset {
            referenced.insert(rel_path.clone());
        }
    }

    // Return remaining unreferenced vendor paths in sorted order
    vendor_files
        .keys()
        .filter(|rel_path| !referenced.contains(*rel_path))
        .cloned()
        .collect()
}

/// Returns whether any `/`-separated path segment starts with a dot.
fn has_dot_segment(path: &str) -> bool {
    path.split('/').any(|segment| segment.starts_with('.'))
}

/// Returns whether a JS keyword introduces a parenthesized header after which `/` starts a regex.
fn is_js_control_paren_keyword(word: &str) -> bool {
    matches!(word, "for" | "if" | "while" | "with")
}

/// Returns whether a JS keyword can be immediately followed by a regex literal.
fn js_keyword_allows_regex(word: &str) -> bool {
    matches!(
        word,
        "await"
            | "case"
            | "delete"
            | "do"
            | "else"
            | "in"
            | "instanceof"
            | "new"
            | "of"
            | "return"
            | "throw"
            | "typeof"
            | "void"
            | "yield"
    )
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

/// Returns a relative path from `from_dir` to `target` within `/static/`.
fn relative_static_path(from_dir: &str, target: &str) -> String {
    let from_parts: Vec<&str> = from_dir.split('/').filter(|s| !s.is_empty()).collect();
    let target_parts: Vec<&str> = target.split('/').filter(|s| !s.is_empty()).collect();
    let common = from_parts
        .iter()
        .zip(&target_parts)
        .take_while(|(a, b)| a == b)
        .count();
    let ups = from_parts.len() - common;
    let rest = target_parts[common..].join("/");
    if ups == 0 {
        format!("./{rest}")
    } else {
        format!("{}{rest}", "../".repeat(ups))
    }
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

/// Advances past a JS regex literal starting at the opening `/` byte at `start`.
fn skip_js_regex_literal(bytes: &[u8], start: usize) -> usize {
    let mut i = start + 1;
    let mut in_char_class = false;
    while i < bytes.len() {
        if bytes[i] == b'\\' {
            i += 1;
            if i < bytes.len() && bytes[i] < 0x80 {
                i += 1;
            }
        } else if bytes[i] == b'[' {
            in_char_class = true;
            i += 1;
        } else if bytes[i] == b']' && in_char_class {
            in_char_class = false;
            i += 1;
        } else if bytes[i] == b'/' && !in_char_class {
            return i + 1;
        } else if bytes[i] == b'\n' {
            return i;
        } else {
            i += 1;
        }
    }
    bytes.len()
}

/// Advances across JS template literal text starting at `start`, returning
/// `(next_index, entered_interpolation)`.
fn skip_js_template_segment(bytes: &[u8], start: usize) -> (usize, bool) {
    let mut i = start;
    while i < bytes.len() {
        if bytes[i] == b'\\' {
            i += 1;
            if i < bytes.len() && bytes[i] < 0x80 {
                i += 1;
            }
        } else if bytes[i] == b'`' {
            return (i + 1, false);
        } else if bytes[i..].starts_with(b"${") {
            return (i + 2, true);
        } else {
            i += 1;
        }
    }
    (bytes.len(), false)
}

/// Advances past a JS identifier/keyword or numeric literal starting at `start`.
fn skip_js_word(bytes: &[u8], start: usize) -> usize {
    let mut i = start + 1;
    if bytes[start].is_ascii_digit() {
        while i < bytes.len()
            && (bytes[i].is_ascii_alphanumeric() || matches!(bytes[i], b'_' | b'.'))
        {
            i += 1;
        }
    } else {
        while i < bytes.len()
            && (bytes[i].is_ascii_alphanumeric()
                || matches!(bytes[i], b'_' | b'$')
                || bytes[i] >= 0x80)
        {
            i += 1;
        }
    }
    i
}

/// Advances past a single- or double-quoted literal starting at `start`.
fn skip_quoted_literal(bytes: &[u8], start: usize, stop_at_newline: bool) -> usize {
    let open_quote = bytes[start];
    let mut i = start + 1;
    while i < bytes.len() {
        if bytes[i] == b'\\' {
            i += 1;
            if i < bytes.len() && bytes[i] < 0x80 {
                i += 1;
            }
        } else if bytes[i] == open_quote || (stop_at_newline && bytes[i] == b'\n') {
            return i + 1;
        } else {
            i += 1;
        }
    }
    bytes.len()
}

/// Splits a forward-slash relative path into `(parent_dir, file_name)`.
fn split_rel_path(path: &str) -> (&str, &str) {
    path.rsplit_once('/').unwrap_or(("", path))
}

/// Finds an embedded static asset path matching the given prefix and suffix.
fn static_path_with_prefix_and_suffix(prefix: &str, suffix: &str) -> String {
    StaticFile::iter()
        .find(|path| path.starts_with(prefix) && path.ends_with(suffix))
        .unwrap_or_else(|| panic!("{prefix} asset ending with {suffix} to exist"))
        .to_string()
}

/// Removes Askama `{# ... #}` comments from a template before HTML/JS/CSS parsing.
fn strip_askama_comments(content: &str) -> String {
    let bytes = content.as_bytes();
    let mut output = String::with_capacity(content.len());
    let mut segment_start = 0;
    let mut i = 0;

    while i < bytes.len() {
        if bytes[i..].starts_with(b"{#") {
            output.push_str(&content[segment_start..i]);
            output.push(' ');
            i = match content[i + 2..].find("#}") {
                Some(offset) => i + 2 + offset + 2,
                None => bytes.len(),
            };
            segment_start = i;
        } else {
            i += 1;
        }
    }

    output.push_str(&content[segment_start..]);
    output
}

/// Removes comments from `content` according to `kind` while preserving string literals.
fn strip_asset_source_comments(content: &str, kind: AssetSourceKind) -> String {
    match kind {
        AssetSourceKind::Css => strip_css_comments(content),
        AssetSourceKind::Html => strip_html_comments(content),
        AssetSourceKind::Js => strip_js_comments(content),
    }
}

/// Removes CSS block comments while preserving quoted strings.
fn strip_css_comments(content: &str) -> String {
    let bytes = content.as_bytes();
    let mut output = String::with_capacity(content.len());
    let mut segment_start = 0;
    let mut i = 0;

    while i < bytes.len() {
        if matches!(bytes[i], b'"' | b'\'') {
            i = skip_quoted_literal(bytes, i, false);
        } else if bytes[i..].starts_with(b"/*") {
            output.push_str(&content[segment_start..i]);
            output.push(' ');
            i = match content[i + 2..].find("*/") {
                Some(offset) => i + 2 + offset + 2,
                None => bytes.len(),
            };
            segment_start = i;
        } else {
            i += 1;
        }
    }

    output.push_str(&content[segment_start..]);
    output
}

/// Removes HTML/Askama comments and strips comments inside inline `<script>` and `<style>` blocks.
fn strip_html_comments(content: &str) -> String {
    // Strip Askama `{# ... #}` comments first so they are also removed inside script/style blocks
    let content = strip_askama_comments(content);
    let bytes = content.as_bytes();
    let mut output = String::with_capacity(content.len());
    let mut segment_start = 0;
    let mut i = 0;

    while i < bytes.len() {
        if bytes[i..].starts_with(b"<!--") {
            output.push_str(&content[segment_start..i]);
            output.push(' ');
            i = match content[i + 4..].find("-->") {
                Some(offset) => i + 4 + offset + 3,
                None => bytes.len(),
            };
            segment_start = i;
        } else if let Some((open_len, close_tag, body_kind)) = [
            (b"<script".as_slice(), "</script", AssetSourceKind::Js),
            (b"<style".as_slice(), "</style", AssetSourceKind::Css),
        ]
        .into_iter()
        .find_map(|(open, close_tag, kind)| {
            (bytes.len() >= i + open.len()
                && bytes[i..i + open.len()].eq_ignore_ascii_case(open)
                && bytes
                    .get(i + open.len())
                    .is_none_or(|b| b.is_ascii_whitespace() || matches!(b, b'>' | b'/')))
            .then_some((open.len(), close_tag, kind))
        }) {
            // Scan to the end of the opening tag while skipping quoted attribute values
            let mut cursor = i + open_len;
            while cursor < bytes.len() {
                if matches!(bytes[cursor], b'"' | b'\'') {
                    let quote = bytes[cursor];
                    cursor += 1;
                    while cursor < bytes.len() && bytes[cursor] != quote {
                        cursor += 1;
                    }
                    if cursor < bytes.len() {
                        cursor += 1;
                    }
                } else if bytes[cursor] == b'>' {
                    cursor += 1;
                    break;
                } else {
                    cursor += 1;
                }
            }

            // Preserve the opening tag and strip comments inside the inline block body
            output.push_str(&content[segment_start..cursor]);
            let body_end = find_ascii_case_insensitive(&content[cursor..], close_tag)
                .map_or(bytes.len(), |offset| cursor + offset);
            output.push_str(&strip_asset_source_comments(
                &content[cursor..body_end],
                body_kind,
            ));
            i = body_end;
            segment_start = i;
        } else {
            i += 1;
        }
    }

    output.push_str(&content[segment_start..]);
    output
}

/// Removes JS line and block comments while preserving strings, nested templates, and regexes.
fn strip_js_comments(content: &str) -> String {
    let bytes = content.as_bytes();
    let mut output = String::with_capacity(content.len());
    let mut segment_start = 0;
    let mut i = 0;
    let mut regex_allowed = true;
    let mut pending_control_paren = false;
    let mut paren_allows_regex_on_close: Vec<bool> = Vec::new();
    let mut template_brace_depths: Vec<usize> = Vec::new();
    let mut in_template = false;

    while i < bytes.len() {
        // Scan template literal text until an unescaped backtick or `${` interpolation
        if in_template {
            let (next_i, entered_interpolation) = skip_js_template_segment(bytes, i);
            i = next_i;
            in_template = false;
            pending_control_paren = false;
            if entered_interpolation {
                template_brace_depths.push(0);
                regex_allowed = true;
            } else {
                regex_allowed = false;
            }
            continue;
        }

        let b = bytes[i];
        if b.is_ascii_whitespace() {
            i += 1;
            continue;
        }
        if bytes[i..].starts_with(b"/*") || bytes[i..].starts_with(b"//") {
            output.push_str(&content[segment_start..i]);
            output.push(' ');
            i = if bytes[i + 1] == b'*' {
                content[i + 2..].find("*/").map_or(bytes.len(), |o| i + o + 4)
            } else {
                content[i + 2..].find('\n').map_or(bytes.len(), |o| i + o + 2)
            };
            segment_start = i;
            continue;
        }

        // Consume any pending control-flow paren flag on the next non-trivia token
        let was_control_paren = std::mem::take(&mut pending_control_paren);
        if matches!(b, b'"' | b'\'') {
            i = skip_quoted_literal(bytes, i, true);
            regex_allowed = false;
        } else if b == b'`' {
            in_template = true;
            i += 1;
        } else if b == b'/' && regex_allowed {
            i = skip_js_regex_literal(bytes, i);
            regex_allowed = false;
        } else if b == b'(' {
            paren_allows_regex_on_close.push(was_control_paren);
            regex_allowed = true;
            i += 1;
        } else if b == b')' {
            regex_allowed = paren_allows_regex_on_close.pop().unwrap_or(false);
            i += 1;
        } else if b == b'{' {
            if let Some(depth) = template_brace_depths.last_mut() {
                *depth += 1;
            }
            regex_allowed = true;
            i += 1;
        } else if b == b'}' {
            if let Some(depth) = template_brace_depths.last_mut() {
                if *depth == 0 {
                    template_brace_depths.pop();
                    in_template = true;
                } else {
                    *depth -= 1;
                    regex_allowed = true;
                }
            } else {
                regex_allowed = true;
            }
            i += 1;
        } else if b.is_ascii_alphabetic() || matches!(b, b'_' | b'$') || b >= 0x80 {
            let word_start = i;
            i = skip_js_word(bytes, i);
            let word = &content[word_start..i];
            pending_control_paren = is_js_control_paren_keyword(word);
            regex_allowed = js_keyword_allows_regex(word);
        } else if b.is_ascii_digit() {
            i = skip_js_word(bytes, i);
            regex_allowed = false;
        } else if b == b']' {
            regex_allowed = false;
            i += 1;
        } else {
            regex_allowed = true;
            i += 1;
        }
    }

    output.push_str(&content[segment_start..]);
    output
}

/// Extracts the library stem from a companion license file name, if it is one.
fn vendor_license_prefix(file_name: &str) -> Option<&str> {
    file_name
        .strip_suffix(".LICENSE")
        .or_else(|| file_name.strip_suffix(".LICENSE.txt"))
        .filter(|prefix| !prefix.is_empty())
}
