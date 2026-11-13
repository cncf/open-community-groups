//! Tests for the rate limiting middleware.

use std::{
    net::{IpAddr, Ipv4Addr, SocketAddr},
    sync::Arc,
    time::Instant,
};

use axum::{
    Extension, Router,
    body::Body,
    extract::ConnectInfo,
    http::{
        Method, StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE, ORIGIN, RETRY_AFTER, SET_COOKIE},
    },
    middleware,
    routing::{get, post},
};
use axum_login::tower_sessions::session;
use uuid::Uuid;

use crate::{
    activity_tracker::{Activity, MockActivityTracker},
    config::{HttpServerConfig, LoginOptions, RateLimitBudget, RateLimitBudgets, RateLimitMode},
    db::mock::MockDB,
    handlers::tests::{
        TestRouterBuilder, authenticated_request, request, sample_rate_limiter, sample_server_cfg,
        send,
    },
    router::{CACHE_CONTROL_NO_STORE, CACHE_CONTROL_PRIVATE_NO_STORE},
    services::rate_limit::{IpLimit, Limit, LogInFailureLimit, RateLimiter, client_ip::ClientKey},
};

use super::*;

/// Login options with every login method enabled.
const ALL_LOGIN_OPTIONS: LoginOptions = LoginOptions {
    email: true,
    github: true,
    linuxfoundation: true,
};

/// TCP peer address of the test client.
const CLIENT_ADDR: SocketAddr = SocketAddr::new(IpAddr::V4(Ipv4Addr::new(203, 0, 113, 7)), 40_000);

/// Limiting key of the test client.
const CLIENT_KEY: ClientKey = ClientKey::V4([203, 0, 113, 7]);

/// Body the stub handler returns when the failed log-in limit did not reach it.
const LOG_IN_FAILURE_LIMIT_ABSENT: &str = "log-in failure limit absent";

/// Body the stub handler returns when the failed log-in limit reached it.
const LOG_IN_FAILURE_LIMIT_PRESENT: &str = "log-in failure limit present";

/// Login options with every login method disabled.
const NO_LOGIN_OPTIONS: LoginOptions = LoginOptions {
    email: false,
    github: false,
    linuxfoundation: false,
};

/// Rejection body for a client that must wait one test budget period.
const PERIOD_REJECTION_BODY: &str =
    "Too many requests from your network. Please wait 60 minutes and try again.";

/// Period of the test budgets, long enough that no token refills during a test.
const PERIOD_SECS: u64 = 3_600;

/// Identifier used for every path parameter of a concrete request URI.
const SAMPLE_PATH_ID: &str = "b4c5e5c6-1f4a-4a3e-9d43-3f7e6d3c6b1a";

/// Origin of the configured test site.
const SITE_ORIGIN: &str = "https://example.test";

#[tokio::test]
async fn test_limit_requests_answers_exhausted_keys_before_the_session_layers() {
    for route in LIMITED_ROUTES {
        // Setup the route's request method and case label
        let method = match route.method {
            RouteMethod::Get => "GET",
            RouteMethod::Post => "POST",
        };
        let case = format!("{method} {}", route.path);

        // Setup the router with a database that expects no calls
        let rate_limiter = sample_rate_limiter(single_request_budgets(), RateLimitMode::Enforce);
        let router = TestRouterBuilder::new(MockDB::new())
            .with_rate_limiter(rate_limiter.clone())
            .with_server_cfg(site_server_cfg())
            .build()
            .await;

        // Spend the only token of the client for the route's limit
        let verdict = rate_limiter.check(route.limit, CLIENT_KEY, Instant::now());
        assert_eq!(verdict, Verdict::Allow, "{case}");

        // Run same-origin requests from the client, with and without a session cookie
        let uri = concrete_uri(route.path);
        let requests = [
            ("without a session cookie", request(method, &uri)),
            (
                "with a session cookie",
                authenticated_request(method, &uri, session::Id::default()),
            ),
        ];
        for (variant, request) in requests {
            let request = request.header(ORIGIN, SITE_ORIGIN).body(Body::empty()).unwrap();
            let (parts, bytes) = send(router.clone(), with_client(request)).await;

            // Check the rejection, answering views as if they had been tracked
            if route.limit == IpLimit::Views {
                assert_eq!(parts.status, StatusCode::NO_CONTENT, "{case} {variant}");
                assert_eq!(
                    parts.headers.get(CACHE_CONTROL).unwrap(),
                    CACHE_CONTROL_PRIVATE_NO_STORE,
                    "{case} {variant}"
                );
                assert!(parts.headers.get(RETRY_AFTER).is_none(), "{case} {variant}");
                assert!(bytes.is_empty(), "{case} {variant}");
            } else {
                assert_eq!(
                    parts.status,
                    StatusCode::TOO_MANY_REQUESTS,
                    "{case} {variant}"
                );
                assert_eq!(
                    parts.headers.get(RETRY_AFTER).unwrap(),
                    PERIOD_SECS.to_string().as_str(),
                    "{case} {variant}"
                );
                assert_eq!(
                    parts.headers.get(CACHE_CONTROL).unwrap(),
                    CACHE_CONTROL_NO_STORE,
                    "{case} {variant}"
                );
                assert_eq!(
                    parts.headers.get(CONTENT_TYPE).unwrap(),
                    "text/plain; charset=utf-8",
                    "{case} {variant}"
                );
                assert_eq!(bytes, PERIOD_REJECTION_BODY, "{case} {variant}");
            }

            // Check the rejection wrote no session
            assert!(parts.headers.get(SET_COOKIE).is_none(), "{case} {variant}");
        }
    }
}

#[tokio::test]
async fn test_limit_requests_inserts_log_in_failure_limit_only_on_log_in_posts() {
    // Setup labeled requests with whether the handler gets the failed log-in limit
    let event_views_uri = concrete_uri("/events/{event_id}/views");
    let cases = [
        ("log-in post", Method::POST, "/log-in", true, true),
        (
            "log-in post from an unresolved client",
            Method::POST,
            "/log-in",
            false,
            false,
        ),
        ("log-in page", Method::GET, "/log-in", true, false),
        ("sign-up post", Method::POST, "/sign-up", true, false),
        ("explore search", Method::GET, "/explore", true, false),
        ("view", Method::POST, event_views_uri.as_str(), true, false),
    ];

    for mode in [RateLimitMode::Enforce, RateLimitMode::Observe] {
        // Setup a stub router behind a limiter with the default budgets
        let router = stub_router(sample_rate_limiter(RateLimitBudgets::default(), mode));

        // Run each request and check whether the extension reached the handler
        for (case, method, uri, has_client, expect_limit) in cases.clone() {
            let request = request(method.as_str(), uri)
                .header(ORIGIN, SITE_ORIGIN)
                .body(Body::empty())
                .unwrap();
            let request = if has_client {
                with_client(request)
            } else {
                request
            };
            let (parts, bytes) = send(router.clone(), request).await;

            assert_eq!(parts.status, StatusCode::OK, "{mode:?} {case}");
            let expected_body = if expect_limit {
                LOG_IN_FAILURE_LIMIT_PRESENT
            } else {
                LOG_IN_FAILURE_LIMIT_ABSENT
            };
            assert_eq!(bytes, expected_body, "{mode:?} {case}");
        }
    }
}

#[tokio::test]
async fn test_limit_requests_observe_mode_passes_requests_over_the_limit() {
    // Setup a stub router behind an observing limiter with one-request budgets
    let rate_limiter = sample_rate_limiter(single_request_budgets(), RateLimitMode::Observe);
    let router = stub_router(rate_limiter.clone());

    // Setup labeled routes with the body their handler returns within the limit
    let event_views_uri = concrete_uri("/events/{event_id}/views");
    let cases = [
        (
            "log in",
            Limit::LogIn,
            Method::POST,
            "/log-in",
            LOG_IN_FAILURE_LIMIT_PRESENT,
        ),
        (
            "explore search",
            Limit::ExploreSearch,
            Method::GET,
            "/explore",
            LOG_IN_FAILURE_LIMIT_ABSENT,
        ),
        (
            "views",
            Limit::Views,
            Method::POST,
            event_views_uri.as_str(),
            LOG_IN_FAILURE_LIMIT_ABSENT,
        ),
    ];

    for (case, limit, method, uri, expected_body) in cases {
        // Run two requests from the client, the second one over the limit
        for attempt in 1..=2 {
            let request = request(method.as_str(), uri)
                .header(ORIGIN, SITE_ORIGIN)
                .body(Body::empty())
                .unwrap();
            let (parts, bytes) = send(router.clone(), with_client(request)).await;

            // Check the request reached the handler, without the failed log-in limit once it
            // is over the limit, as enforce mode would have rejected it before that limit
            let expected_body = if attempt == 1 {
                expected_body
            } else {
                LOG_IN_FAILURE_LIMIT_ABSENT
            };
            assert_eq!(parts.status, StatusCode::OK, "{case} attempt {attempt}");
            assert_eq!(bytes, expected_body, "{case} attempt {attempt}");
        }

        // Check both requests were counted and the second one recorded over the limit
        let window = rate_limiter.take_window();
        assert_eq!(window.limit(limit).requests, 2, "{case}");
        assert_eq!(window.limit(limit).over_limit, 1, "{case}");
    }
}

#[tokio::test]
async fn test_limit_requests_passes_cross_origin_posts_through_uncounted() {
    // Setup an activity tracker that must never be called
    let mut activity_tracker = MockActivityTracker::new();
    activity_tracker.expect_track().never();

    // Setup the router with a database that expects no calls
    let rate_limiter = sample_rate_limiter(single_request_budgets(), RateLimitMode::Enforce);
    let router = TestRouterBuilder::new(MockDB::new())
        .with_activity_tracker(activity_tracker)
        .with_rate_limiter(rate_limiter.clone())
        .with_server_cfg(site_server_cfg())
        .build()
        .await;

    // Spend every limit of the client, then discard the recorded window
    exhaust_ip_limits(&rate_limiter);
    rate_limiter.take_window();

    // Setup labeled cross-origin requests with the limit they map to
    let event_views_uri = concrete_uri("/events/{event_id}/views");
    let group_views_uri = concrete_uri("/groups/{group_id}/views");
    let cases = [
        (
            "cross-site sign-up",
            Limit::SignUp,
            request("POST", "/sign-up").header("Sec-Fetch-Site", "cross-site"),
        ),
        (
            "log-in from another origin",
            Limit::LogIn,
            request("POST", "/log-in").header(ORIGIN, "https://attacker.test"),
        ),
        (
            "view from another origin",
            Limit::Views,
            request("POST", &event_views_uri).header(ORIGIN, "https://attacker.test"),
        ),
        (
            "view without origin evidence",
            Limit::Views,
            request("POST", &group_views_uri),
        ),
    ];

    for (case, limit, request) in cases {
        // Run the request from the client
        let request = with_client(request.body(Body::empty()).unwrap());
        let (parts, _) = send(router.clone(), request).await;

        // Check the inner layer or handler rejected it
        assert_eq!(parts.status, StatusCode::FORBIDDEN, "{case}");

        // Check it was recorded as skipped and not counted
        let window = rate_limiter.take_window();
        assert_eq!(window.limit(limit).requests, 0, "{case}");
        assert_eq!(window.limit(limit).over_limit, 0, "{case}");
        assert_eq!(window.limit(limit).skipped_cross_origin, 1, "{case}");
    }
}

#[tokio::test]
async fn test_limit_requests_passes_origin_check_errors_through_uncounted() {
    // Setup the router with an unusable base url and a database that expects no calls
    let rate_limiter = sample_rate_limiter(single_request_budgets(), RateLimitMode::Enforce);
    let router = TestRouterBuilder::new(MockDB::new())
        .with_rate_limiter(rate_limiter.clone())
        .with_server_cfg(HttpServerConfig {
            login: ALL_LOGIN_OPTIONS,
            ..sample_server_cfg("not a url")
        })
        .build()
        .await;

    // Spend every limit of the client, then discard the recorded window
    exhaust_ip_limits(&rate_limiter);
    rate_limiter.take_window();

    // Setup labeled requests whose origin check fails, with the limit they map to
    let event_views_uri = concrete_uri("/events/{event_id}/views");
    let cases = [
        (
            "sign-up with an origin header",
            Limit::SignUp,
            request("POST", "/sign-up").header(ORIGIN, SITE_ORIGIN),
        ),
        (
            "view without origin headers",
            Limit::Views,
            request("POST", &event_views_uri),
        ),
    ];

    for (case, limit, request) in cases {
        // Run the request from the client
        let request = with_client(request.body(Body::empty()).unwrap());
        let (parts, _) = send(router.clone(), request).await;

        // Check the inner layer or handler answered with its configuration error
        assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR, "{case}");

        // Check it was neither counted nor recorded as skipped
        let window = rate_limiter.take_window();
        assert_eq!(window.limit(limit).requests, 0, "{case}");
        assert_eq!(window.limit(limit).over_limit, 0, "{case}");
        assert_eq!(window.limit(limit).skipped_cross_origin, 0, "{case}");
    }
}

#[tokio::test]
async fn test_limit_requests_passes_unmapped_requests_through() {
    // Setup a stub router behind a limiter whose every limit the client has spent
    let rate_limiter = sample_rate_limiter(single_request_budgets(), RateLimitMode::Enforce);
    let router = stub_router(rate_limiter.clone());
    exhaust_ip_limits(&rate_limiter);
    rate_limiter.take_window();

    // Setup labeled requests to routes outside the limits
    let cases = [
        ("health check", Method::GET, "/health-check"),
        ("log-in page", Method::GET, "/log-in"),
        ("sign-up page", Method::GET, "/sign-up"),
        ("webhook", Method::POST, "/webhooks/zoom"),
        ("fallback", Method::GET, "/explore/missing"),
    ];

    // Check each request reaches its handler
    for (case, method, uri) in cases {
        let request = request(method.as_str(), uri)
            .header(ORIGIN, SITE_ORIGIN)
            .body(Body::empty())
            .unwrap();
        let (parts, bytes) = send(router.clone(), with_client(request)).await;
        assert_eq!(parts.status, StatusCode::OK, "{case}");
        assert_eq!(bytes, LOG_IN_FAILURE_LIMIT_ABSENT, "{case}");
    }

    // Check no limit recorded any traffic
    let window = rate_limiter.take_window();
    for limit in Limit::ALL {
        assert!(!window.limit(limit).has_traffic(), "{}", limit.name());
    }
}

#[tokio::test]
async fn test_limit_requests_passes_unresolved_clients_through() {
    // Setup an activity tracker expecting both views
    let group_id = Uuid::new_v4();
    let mut activity_tracker = MockActivityTracker::new();
    activity_tracker
        .expect_track()
        .times(2)
        .withf(move |activity| *activity == Activity::GroupView { group_id })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup the router behind an enforcing limiter with one-request budgets
    let rate_limiter = sample_rate_limiter(single_request_budgets(), RateLimitMode::Enforce);
    let router = TestRouterBuilder::new(MockDB::new())
        .with_activity_tracker(activity_tracker)
        .with_rate_limiter(rate_limiter.clone())
        .with_server_cfg(site_server_cfg())
        .build()
        .await;

    // Run two views without connect info, so the peer is unknown
    for attempt in 1..=2 {
        let request = request("POST", &format!("/groups/{group_id}/views"))
            .header(ORIGIN, SITE_ORIGIN)
            .body(Body::empty())
            .unwrap();
        let (parts, bytes) = send(router.clone(), request).await;

        // Check the view was tracked
        assert_eq!(parts.status, StatusCode::NO_CONTENT, "attempt {attempt}");
        assert!(bytes.is_empty(), "attempt {attempt}");
    }

    // Check both requests were unresolved and never counted against the limit
    let window = rate_limiter.take_window();
    assert_eq!(window.client_ip.unresolved_no_peer_info, 2);
    assert_eq!(window.limit(Limit::Views).requests, 0);
}

#[tokio::test]
async fn test_limit_requests_views_over_the_limit_return_no_content_untracked() {
    // Setup an activity tracker that must never be called
    let mut activity_tracker = MockActivityTracker::new();
    activity_tracker.expect_track().never();

    // Setup the router behind an enforcing limiter with one-request budgets
    let rate_limiter = sample_rate_limiter(single_request_budgets(), RateLimitMode::Enforce);
    let router = TestRouterBuilder::new(MockDB::new())
        .with_activity_tracker(activity_tracker)
        .with_rate_limiter(rate_limiter.clone())
        .with_server_cfg(site_server_cfg())
        .build()
        .await;

    // Spend the only views token of the client
    let verdict = rate_limiter.check(IpLimit::Views, CLIENT_KEY, Instant::now());
    assert_eq!(verdict, Verdict::Allow);

    // Run a same-origin view from the client
    let request = request("POST", &format!("/events/{}/views", Uuid::new_v4()))
        .header(ORIGIN, SITE_ORIGIN)
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, with_client(request)).await;

    // Check the response looks like a tracked view
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert!(bytes.is_empty());

    // Check the view was counted over the limit
    let window = rate_limiter.take_window();
    assert_eq!(window.limit(Limit::Views).requests, 2);
    assert_eq!(window.limit(Limit::Views).over_limit, 1);
}

#[test]
fn test_route_limit_maps_head_like_get() {
    // Setup labeled HEAD requests with the expected limit
    let cases = [
        ("explore search", "/explore", Some(IpLimit::ExploreSearch)),
        (
            "email verification",
            "/verify-email/{code}",
            Some(IpLimit::VerifyEmail),
        ),
        (
            "external auth callback",
            "/log-in/oidc/{provider}/callback",
            Some(IpLimit::ExternalAuth),
        ),
        ("badge verification post route", "/badges/verify", None),
        ("log-in post route", "/log-in", None),
        ("view post route", "/events/{event_id}/views", None),
    ];

    // Check HEAD maps exactly as GET does
    for (case, path, expected) in cases {
        assert_eq!(
            route_limit(&Method::HEAD, path, &ALL_LOGIN_OPTIONS),
            expected,
            "{case}"
        );
        assert_eq!(
            route_limit(&Method::HEAD, path, &ALL_LOGIN_OPTIONS),
            route_limit(&Method::GET, path, &ALL_LOGIN_OPTIONS),
            "{case}"
        );
    }
}

#[test]
#[allow(clippy::too_many_lines)]
fn test_route_limit_maps_routes_to_limits() {
    // Setup labeled routes and login options with the expected limit
    let cases = [
        (
            "badge verification",
            Method::POST,
            "/badges/verify",
            ALL_LOGIN_OPTIONS,
            Some(IpLimit::BadgeVerify),
        ),
        (
            "badge verification without login options",
            Method::POST,
            "/badges/verify",
            NO_LOGIN_OPTIONS,
            Some(IpLimit::BadgeVerify),
        ),
        (
            "explore page",
            Method::GET,
            "/explore",
            ALL_LOGIN_OPTIONS,
            Some(IpLimit::ExploreSearch),
        ),
        (
            "explore events results section",
            Method::GET,
            "/explore/events-results-section",
            ALL_LOGIN_OPTIONS,
            Some(IpLimit::ExploreSearch),
        ),
        (
            "explore events section",
            Method::GET,
            "/explore/events-section",
            ALL_LOGIN_OPTIONS,
            Some(IpLimit::ExploreSearch),
        ),
        (
            "explore events search",
            Method::GET,
            "/explore/events/search",
            ALL_LOGIN_OPTIONS,
            Some(IpLimit::ExploreSearch),
        ),
        (
            "explore groups results section",
            Method::GET,
            "/explore/groups-results-section",
            ALL_LOGIN_OPTIONS,
            Some(IpLimit::ExploreSearch),
        ),
        (
            "explore groups section",
            Method::GET,
            "/explore/groups-section",
            ALL_LOGIN_OPTIONS,
            Some(IpLimit::ExploreSearch),
        ),
        (
            "explore groups search",
            Method::GET,
            "/explore/groups/search",
            ALL_LOGIN_OPTIONS,
            Some(IpLimit::ExploreSearch),
        ),
        (
            "explore search without login options",
            Method::GET,
            "/explore/events/search",
            NO_LOGIN_OPTIONS,
            Some(IpLimit::ExploreSearch),
        ),
        (
            "oauth2 redirect",
            Method::GET,
            "/log-in/oauth2/{provider}",
            ALL_LOGIN_OPTIONS,
            Some(IpLimit::ExternalAuth),
        ),
        (
            "oauth2 callback",
            Method::GET,
            "/log-in/oauth2/{provider}/callback",
            ALL_LOGIN_OPTIONS,
            Some(IpLimit::ExternalAuth),
        ),
        (
            "oauth2 redirect without github login",
            Method::GET,
            "/log-in/oauth2/{provider}",
            LoginOptions {
                github: false,
                ..ALL_LOGIN_OPTIONS
            },
            None,
        ),
        (
            "oauth2 callback without github login",
            Method::GET,
            "/log-in/oauth2/{provider}/callback",
            LoginOptions {
                github: false,
                ..ALL_LOGIN_OPTIONS
            },
            None,
        ),
        (
            "oidc redirect",
            Method::GET,
            "/log-in/oidc/{provider}",
            ALL_LOGIN_OPTIONS,
            Some(IpLimit::ExternalAuth),
        ),
        (
            "oidc callback",
            Method::GET,
            "/log-in/oidc/{provider}/callback",
            ALL_LOGIN_OPTIONS,
            Some(IpLimit::ExternalAuth),
        ),
        (
            "oidc redirect without linux foundation login",
            Method::GET,
            "/log-in/oidc/{provider}",
            LoginOptions {
                linuxfoundation: false,
                ..ALL_LOGIN_OPTIONS
            },
            None,
        ),
        (
            "oidc callback without linux foundation login",
            Method::GET,
            "/log-in/oidc/{provider}/callback",
            LoginOptions {
                linuxfoundation: false,
                ..ALL_LOGIN_OPTIONS
            },
            None,
        ),
        (
            "log-in post",
            Method::POST,
            "/log-in",
            ALL_LOGIN_OPTIONS,
            Some(IpLimit::LogIn),
        ),
        (
            "log-in post without email login",
            Method::POST,
            "/log-in",
            LoginOptions {
                email: false,
                ..ALL_LOGIN_OPTIONS
            },
            None,
        ),
        (
            "sign-up post",
            Method::POST,
            "/sign-up",
            ALL_LOGIN_OPTIONS,
            Some(IpLimit::SignUp),
        ),
        (
            "sign-up post without email login",
            Method::POST,
            "/sign-up",
            LoginOptions {
                email: false,
                ..ALL_LOGIN_OPTIONS
            },
            None,
        ),
        (
            "email verification",
            Method::GET,
            "/verify-email/{code}",
            ALL_LOGIN_OPTIONS,
            Some(IpLimit::VerifyEmail),
        ),
        (
            "email verification without email login",
            Method::GET,
            "/verify-email/{code}",
            LoginOptions {
                email: false,
                ..ALL_LOGIN_OPTIONS
            },
            None,
        ),
        (
            "community view",
            Method::POST,
            "/communities/{community_id}/views",
            ALL_LOGIN_OPTIONS,
            Some(IpLimit::Views),
        ),
        (
            "event view",
            Method::POST,
            "/events/{event_id}/views",
            ALL_LOGIN_OPTIONS,
            Some(IpLimit::Views),
        ),
        (
            "group view",
            Method::POST,
            "/groups/{group_id}/views",
            ALL_LOGIN_OPTIONS,
            Some(IpLimit::Views),
        ),
        (
            "view without login options",
            Method::POST,
            "/groups/{group_id}/views",
            NO_LOGIN_OPTIONS,
            Some(IpLimit::Views),
        ),
        (
            "health check",
            Method::GET,
            "/health-check",
            ALL_LOGIN_OPTIONS,
            None,
        ),
        (
            "explore event card",
            Method::GET,
            "/explore/events/{event_id}/card",
            ALL_LOGIN_OPTIONS,
            None,
        ),
        (
            "explore group card",
            Method::GET,
            "/explore/groups/{group_id}/card",
            ALL_LOGIN_OPTIONS,
            None,
        ),
        (
            "log-in page",
            Method::GET,
            "/log-in",
            ALL_LOGIN_OPTIONS,
            None,
        ),
        (
            "sign-up page",
            Method::GET,
            "/sign-up",
            ALL_LOGIN_OPTIONS,
            None,
        ),
        (
            "payments webhook",
            Method::POST,
            "/webhooks/payments",
            ALL_LOGIN_OPTIONS,
            None,
        ),
        (
            "payments connected webhook",
            Method::POST,
            "/webhooks/payments/connected",
            ALL_LOGIN_OPTIONS,
            None,
        ),
        (
            "zoom webhook",
            Method::POST,
            "/webhooks/zoom",
            ALL_LOGIN_OPTIONS,
            None,
        ),
        (
            "unlisted route",
            Method::GET,
            "/docs",
            ALL_LOGIN_OPTIONS,
            None,
        ),
        (
            "unregistered path",
            Method::GET,
            "/explore/missing",
            ALL_LOGIN_OPTIONS,
            None,
        ),
        (
            "badge verification page",
            Method::GET,
            "/badges/verify",
            ALL_LOGIN_OPTIONS,
            None,
        ),
        (
            "explore search posted",
            Method::POST,
            "/explore/events/search",
            ALL_LOGIN_OPTIONS,
            None,
        ),
        (
            "badge verification with another method",
            Method::PUT,
            "/badges/verify",
            ALL_LOGIN_OPTIONS,
            None,
        ),
        (
            "explore search preflight",
            Method::OPTIONS,
            "/explore",
            ALL_LOGIN_OPTIONS,
            None,
        ),
    ];

    // Check each route maps to the expected limit
    for (case, method, path, login, expected) in cases {
        assert_eq!(route_limit(&method, path, &login), expected, "{case}");
    }
}

// Helpers.

/// Returns a request URI for a route template, with every path parameter
/// replaced by a sample identifier.
fn concrete_uri(path: &str) -> String {
    path.split('/')
        .map(|segment| {
            if segment.starts_with('{') {
                SAMPLE_PATH_ID
            } else {
                segment
            }
        })
        .collect::<Vec<_>>()
        .join("/")
}

/// Spends the only token of the test client in every IP limit.
fn exhaust_ip_limits(rate_limiter: &RateLimiter) {
    for limit in IpLimit::ALL {
        let verdict = rate_limiter.check(limit, CLIENT_KEY, Instant::now());
        assert_eq!(verdict, Verdict::Allow, "{limit:?}");
    }
}

/// Returns budgets that allow one request per key and refill only after
/// [`PERIOD_SECS`].
fn single_request_budgets() -> RateLimitBudgets {
    let budget = RateLimitBudget {
        burst: 1,
        period_secs: PERIOD_SECS,
    };
    RateLimitBudgets {
        badge_verify: budget,
        explore_search: budget,
        external_auth: budget,
        log_in: budget,
        log_in_failures: budget,
        sign_up: budget,
        verify_email: budget,
        views: budget,
    }
}

/// Returns the test site configuration with every login option enabled.
fn site_server_cfg() -> HttpServerConfig {
    HttpServerConfig {
        login: ALL_LOGIN_OPTIONS,
        ..sample_server_cfg(SITE_ORIGIN)
    }
}

/// Stub handler that reports whether the failed log-in limit reached it.
async fn stub_handler(log_in_failure_limit: Option<Extension<LogInFailureLimit>>) -> &'static str {
    if log_in_failure_limit.is_some() {
        LOG_IN_FAILURE_LIMIT_PRESENT
    } else {
        LOG_IN_FAILURE_LIMIT_ABSENT
    }
}

/// Builds a router of stub handlers behind the rate limiting middleware,
/// with a few mapped routes, a few exempt ones and a fallback.
fn stub_router(rate_limiter: Arc<RateLimiter>) -> Router {
    let state = Arc::new(RateLimitLayerState {
        rate_limiter,
        server_cfg: site_server_cfg(),
    });
    Router::new()
        .route("/events/{event_id}/views", post(stub_handler))
        .route("/explore", get(stub_handler))
        .route("/health-check", get(stub_handler))
        .route("/log-in", get(stub_handler).post(stub_handler))
        .route("/sign-up", get(stub_handler).post(stub_handler))
        .route("/webhooks/zoom", post(stub_handler))
        .fallback(stub_handler)
        .layer(middleware::from_fn_with_state(state, limit_requests))
}

/// Adds the test client's TCP peer address to a request, as the server's
/// connect info does.
fn with_client(mut request: Request) -> Request {
    request.extensions_mut().insert(ConnectInfo(CLIENT_ADDR));
    request
}
