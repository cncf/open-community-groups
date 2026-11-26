use std::{
    net::SocketAddr,
    sync::{Arc, Mutex},
    time::Instant,
};

use anyhow::anyhow;
use axum::{
    body::{Body, to_bytes},
    extract::{ConnectInfo, Query},
    http::{
        HeaderValue, Request, StatusCode,
        header::{ACCEPT, CACHE_CONTROL, CONTENT_TYPE, COOKIE, LOCATION, RETRY_AFTER, SET_COOKIE},
    },
    response::IntoResponse,
};
use axum_login::tower_sessions::session;
use oauth2::{
    AuthUrl, ClientId, ClientSecret, PkceCodeChallenge, PkceCodeVerifier, RedirectUrl, TokenUrl,
    basic::BasicClient,
};
use openidconnect as oidc;
use serde_json::json;
use tower_sessions::{MemoryStore, Session};
use uuid::Uuid;

use crate::{
    auth::{
        AUTH_PROVIDER_KEY, EXTERNAL_AUTH_EMAIL_CONFLICT_ERROR,
        EXTERNAL_AUTH_EMAIL_NOT_VERIFIED_ERROR, EXTERNAL_AUTH_IDENTITY_CONFLICT_ERROR,
        EXTERNAL_AUTH_OIDC_EMAIL_NOT_VERIFIED_ERROR, OAuth2ProviderDetails, OidcProviderDetails,
    },
    config::{
        HttpServerConfig, LoginOptions, OAuth2Provider, RateLimitBudget, RateLimitBudgets,
        RateLimitMode,
    },
    db::{
        DynDB,
        mock::{MockDB, expect_site_settings},
    },
    handlers::{
        extractors::{OAuth2, Oidc},
        tests::*,
    },
    router::{CACHE_CONTROL_NO_STORE, CACHE_CONTROL_PRIVATE_NO_STORE},
    services::{
        notifications::MockNotificationsManager,
        rate_limit::{Limit, RateLimiter, client_ip::ClientKey},
    },
    test_util::{element_html_with, opening_tag_with},
};

use super::*;

// Pages and sections.

#[tokio::test]
async fn test_log_in_page_success() {
    // Setup database mock
    let mut db = MockDB::new();
    expect_site_settings(&mut db);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = request("GET", LOG_IN_URL).body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_log_in_page_redirects_when_authenticated() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, get_request(LOG_IN_URL, ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static("/"))
    );
}

#[tokio::test]
async fn test_sign_up_page_success() {
    // Setup database mock
    let mut db = MockDB::new();
    expect_site_settings(&mut db);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = request("GET", SIGN_UP_URL).body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_sign_up_page_redirects_when_authenticated() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, get_request(SIGN_UP_URL, ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static("/"))
    );
}

#[tokio::test]
async fn test_user_menu_section_guest_success_ignores_theme_cookie() {
    // Setup router without database expectations, since a guest loads no session
    let router = TestRouterBuilder::new(MockDB::new()).build().await;

    // Send the guest request without and with a color theme cookie
    let request_plain = request("GET", "/section/user-menu").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router.clone(), request_plain).await;
    let request_with_cookie = request("GET", "/section/user-menu")
        .header(COOKIE, "ocg_theme=dark")
        .body(Body::empty())
        .unwrap();
    let (cookie_parts, cookie_bytes) = send(router, request_with_cookie).await;

    // Check the guest response is private and renders the theme group with System checked
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL),
        Some(&HeaderValue::from_static(CACHE_CONTROL_PRIVATE_NO_STORE))
    );
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(
        opening_tag_with(&body, r#"id="user-dropdown-button""#)
            .contains(r#"data-logged-in="false""#)
    );
    assert_theme_group_checks_system(&body);

    // Check the cookie leaves the response unchanged
    assert_html_response(&cookie_parts, &cookie_bytes, StatusCode::OK);
    assert_eq!(cookie_bytes, bytes);
}

#[tokio::test]
async fn test_user_menu_section_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, get_request("/section/user-menu", ids.session_id)).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL),
        Some(&HeaderValue::from_static(CACHE_CONTROL_PRIVATE_NO_STORE))
    );

    // Check the member menu renders the theme group with System checked
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(
        opening_tag_with(&body, r#"id="user-dropdown-button""#)
            .contains(r#"data-logged-in="true""#)
    );
    assert_theme_group_checks_system(&body);
}

// Log in and log out.

#[tokio::test]
async fn test_log_in_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let user = auth::User {
        password: Some(password_auth::generate_hash("secret-password")),
        ..sample_auth_user(ids.user_id, "hash")
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_stored_session(&mut db, sample_empty_session_record(ids.session_id));
    db.expect_get_user_by_username()
        .times(1)
        .withf(move |username| username == "test-user")
        .returning(move |_| Ok(Some(user.clone())));
    db.expect_delete_session()
        .times(1)
        .withf(move |id| *id == ids.session_id)
        .returning(|_| Ok(()));
    db.expect_create_session()
        .times(1)
        .withf(move |record| {
            session_record_contains_auth_provider(record, AUTH_PROVIDER_EMAIL)
                && session_record_contains_selected_group(record, ids.group_id)
        })
        .returning(|_| Ok(()));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &ids.user_id)
        .returning(move |_| {
            Ok(sample_user_groups_by_community(
                ids.community_id,
                ids.group_id,
            ))
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_server_cfg(email_login_cfg())
        .build()
        .await;
    let request = form_request(
        "POST",
        "/log-in?next_url=%2Fdashboard",
        ids.session_id,
        "username=test-user&password=secret-password",
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert!(parts.headers.contains_key("set-cookie"));
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static("/dashboard")),
    );
}

#[tokio::test]
async fn test_log_in_invalid_credentials() {
    // Setup database mock
    let session_id = session::Id::default();
    let mut db = MockDB::new();
    expect_stored_session(&mut db, sample_empty_session_record(session_id));
    db.expect_get_user_by_username()
        .times(1)
        .withf(move |username| username == "test-user")
        .returning(|_| Ok(None));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            message_matches(
                record,
                "Invalid credentials. Please make sure you have verified your email address.",
            )
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_server_cfg(email_login_cfg())
        .build()
        .await;
    let request = form_request(
        "POST",
        "/log-in?next_url=%2Fdashboard",
        session_id,
        "username=test-user&password=wrong",
    );
    let (parts, bytes) = send(router, request).await;

    // Check the log in page is shown again keeping the next url
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static("/log-in?next_url=%2Fdashboard")),
    );
}

#[tokio::test]
async fn test_log_in_returns_unauthorized_when_authentication_fails() {
    // Setup database mock with a failing user lookup
    let session_id = session::Id::default();
    let mut db = MockDB::new();
    expect_stored_session(&mut db, sample_empty_session_record(session_id));
    db.expect_get_user_by_username()
        .times(1)
        .withf(move |username| username == "test-user")
        .returning(|_| Err(anyhow!("db error")));
    db.expect_update_session().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_server_cfg(email_login_cfg())
        .build()
        .await;
    let request = form_request(
        "POST",
        "/log-in",
        session_id,
        "username=test-user&password=secret-password",
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn test_log_in_validation_error() {
    // Setup database mock
    let session_id = session::Id::default();
    let mut db = MockDB::new();
    expect_stored_session(&mut db, sample_empty_session_record(session_id));
    db.expect_get_user_by_username().times(0);
    db.expect_update_session()
        .times(1)
        .withf(|record| {
            message_matches(
                record,
                "username: value cannot be empty or whitespace-only\n",
            )
        })
        .returning(|_| Ok(()));

    // Setup router and send request with a whitespace-only username
    let router = TestRouterBuilder::new(db)
        .with_server_cfg(email_login_cfg())
        .build()
        .await;
    let request = form_request(
        "POST",
        "/log-in?next_url=%2Fdashboard",
        session_id,
        "username=+++&password=secret",
    );
    let (parts, bytes) = send(router, request).await;

    // Check the log in page is shown again keeping the next url
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static("/log-in?next_url=%2Fdashboard")),
    );
}

#[tokio::test]
async fn test_log_in_backend_error_refunds_failure_reservation() {
    // Setup database mock with a failing user lookup
    let session_id = session::Id::default();
    let mut db = MockDB::new();
    expect_stored_session(&mut db, sample_empty_session_record(session_id));
    db.expect_get_user_by_username()
        .times(1)
        .withf(move |username| username == "test-user")
        .returning(|_| Err(anyhow!("db error")));
    db.expect_update_session().never();

    // Setup router with an enforcing limiter allowing one failure per pair
    let rate_limiter = log_in_failures_rate_limiter(RateLimitMode::Enforce);
    let router = TestRouterBuilder::new(db)
        .with_rate_limiter(rate_limiter.clone())
        .with_server_cfg(email_login_cfg())
        .build()
        .await;

    // Send a log in request that hits the backend error
    let request = log_in_request(session_id, "username=test-user&password=secret-password");
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::UNAUTHORIZED);

    // Check the next failed attempt for the pair is still allowed
    rate_limiter
        .log_in_failure_limit(LOG_IN_CLIENT)
        .reserve("test-user", Instant::now())
        .expect("failed attempt to be allowed after the refund")
        .record_failure();
    let window = rate_limiter.take_window();
    let failures = window.limit(Limit::LogInFailures);
    assert_eq!(failures.requests, 2);
    assert_eq!(failures.over_limit, 0);
}

#[tokio::test]
async fn test_log_in_backend_error_refunds_failure_reservation_in_observe_mode() {
    // Setup database mock with a failing user lookup
    let session_id = session::Id::default();
    let mut db = MockDB::new();
    expect_stored_session(&mut db, sample_empty_session_record(session_id));
    db.expect_get_user_by_username()
        .times(1)
        .withf(move |username| username == "test-user")
        .returning(|_| Err(anyhow!("db error")));
    db.expect_update_session().never();

    // Setup router with an observing limiter allowing one failure per pair
    let rate_limiter = log_in_failures_rate_limiter(RateLimitMode::Observe);
    let router = TestRouterBuilder::new(db)
        .with_rate_limiter(rate_limiter.clone())
        .with_server_cfg(email_login_cfg())
        .build()
        .await;

    // Send a log in request that hits the backend error
    let request = log_in_request(session_id, "username=test-user&password=secret-password");
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::UNAUTHORIZED);

    // Check the next failed attempt for the pair is not over the limit
    rate_limiter
        .log_in_failure_limit(LOG_IN_CLIENT)
        .reserve("test-user", Instant::now())
        .expect("observe mode to never refuse a reservation")
        .record_failure();
    let window = rate_limiter.take_window();
    let failures = window.limit(Limit::LogInFailures);
    assert_eq!(failures.requests, 2);
    assert_eq!(failures.over_limit, 0);
}

#[tokio::test]
async fn test_log_in_observe_mode_never_rejects_failures() {
    // Setup database mock for two failed attempts with the same session
    let session_id = session::Id::default();
    let session_record = sample_empty_session_record(session_id);
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(2)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_username()
        .times(2)
        .withf(move |username| username == "test-user")
        .returning(|_| Ok(None));
    db.expect_update_session()
        .times(2)
        .withf(move |record| {
            message_matches(
                record,
                "Invalid credentials. Please make sure you have verified your email address.",
            )
        })
        .returning(|_| Ok(()));

    // Setup router with an observing limiter allowing one failure per pair
    let rate_limiter = log_in_failures_rate_limiter(RateLimitMode::Observe);
    let router = TestRouterBuilder::new(db)
        .with_rate_limiter(rate_limiter.clone())
        .with_server_cfg(email_login_cfg())
        .build()
        .await;

    // Send two log in requests with invalid credentials
    let first_request = log_in_request(session_id, "username=test-user&password=wrong");
    let (first_parts, first_bytes) = send(router.clone(), first_request).await;
    let second_request = log_in_request(session_id, "username=test-user&password=wrong");
    let (second_parts, second_bytes) = send(router, second_request).await;

    // Check both attempts show the log in page again
    for (parts, bytes) in [(&first_parts, &first_bytes), (&second_parts, &second_bytes)] {
        assert_empty_response(parts, bytes, StatusCode::SEE_OTHER);
        assert_eq!(
            parts.headers.get(LOCATION),
            Some(&HeaderValue::from_static(LOG_IN_URL)),
        );
    }

    // Check the second attempt was counted as over the limit
    let window = rate_limiter.take_window();
    let failures = window.limit(Limit::LogInFailures);
    assert_eq!(failures.requests, 2);
    assert_eq!(failures.over_limit, 1);
}

#[tokio::test]
async fn test_log_in_observe_mode_skips_failure_limit_over_the_log_in_limit() {
    // Setup database mock for two failed attempts with the same session
    let session_id = session::Id::default();
    let session_record = sample_empty_session_record(session_id);
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(2)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_username()
        .times(2)
        .withf(move |username| username == "test-user")
        .returning(|_| Ok(None));
    db.expect_update_session().times(2).returning(|_| Ok(()));

    // Setup router with an observing limiter allowing one log in per client
    let rate_limiter = sample_rate_limiter(
        RateLimitBudgets {
            log_in: RateLimitBudget {
                burst: 1,
                period_secs: 3600,
            },
            ..RateLimitBudgets::default()
        },
        RateLimitMode::Observe,
    );
    let router = TestRouterBuilder::new(db)
        .with_rate_limiter(rate_limiter.clone())
        .with_server_cfg(email_login_cfg())
        .build()
        .await;

    // Send two log in requests with invalid credentials
    let first_request = log_in_request(session_id, "username=test-user&password=wrong");
    let (first_parts, _) = send(router.clone(), first_request).await;
    let second_request = log_in_request(session_id, "username=test-user&password=wrong");
    let (second_parts, _) = send(router, second_request).await;

    // Check both attempts reached the handler
    assert_eq!(first_parts.status, StatusCode::SEE_OTHER);
    assert_eq!(second_parts.status, StatusCode::SEE_OTHER);

    // Check the attempt over the log in limit was not counted as a failed log in, as enforce
    // mode would have rejected it before the failed log in limit
    let window = rate_limiter.take_window();
    let log_in = window.limit(Limit::LogIn);
    assert_eq!(log_in.requests, 2);
    assert_eq!(log_in.over_limit, 1);
    let failures = window.limit(Limit::LogInFailures);
    assert_eq!(failures.requests, 1);
    assert_eq!(failures.over_limit, 0);
}

#[tokio::test]
async fn test_log_in_rejects_exhausted_failures_with_the_page_for_browser_forms() {
    // Setup database mock allowing only the session read
    let session_id = session::Id::default();
    let mut db = MockDB::new();
    expect_stored_session(&mut db, sample_empty_session_record(session_id));
    db.expect_get_user_by_username().never();
    db.expect_create_session().never();
    db.expect_delete_session().never();
    db.expect_update_session().never();

    // Setup router with an enforcing limiter allowing one failure per pair
    let rate_limiter = log_in_failures_rate_limiter(RateLimitMode::Enforce);
    let router = TestRouterBuilder::new(db)
        .with_rate_limiter(rate_limiter.clone())
        .with_server_cfg(email_login_cfg())
        .build()
        .await;

    // Spend the failed attempt budget of the pair
    rate_limiter
        .log_in_failure_limit(LOG_IN_CLIENT)
        .reserve("test-user", Instant::now())
        .expect("first failed attempt to be allowed")
        .record_failure();

    // Send a browser form submission for the exhausted pair
    let mut request = log_in_request(session_id, "username=test-user&password=secret-password");
    request.headers_mut().insert(
        ACCEPT,
        HeaderValue::from_static("text/html,application/xhtml+xml,*/*;q=0.8"),
    );
    request
        .headers_mut()
        .insert("sec-fetch-mode", HeaderValue::from_static("navigate"));
    let (parts, bytes) = send(router, request).await;

    // Check the uncacheable page is returned without writing the session
    assert_eq!(parts.status, StatusCode::TOO_MANY_REQUESTS);
    assert_eq!(parts.headers.get(RETRY_AFTER).unwrap(), "3600");
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        CACHE_CONTROL_NO_STORE
    );
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        "text/html; charset=utf-8"
    );
    assert!(!parts.headers.contains_key(SET_COOKIE));
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(
        body.contains("Too many requests from your network. Please wait 60 minutes and try again.")
    );
}

#[tokio::test]
async fn test_log_in_rejects_exhausted_failures_without_authenticating() {
    // Setup database mock allowing only the session read
    let session_id = session::Id::default();
    let mut db = MockDB::new();
    expect_stored_session(&mut db, sample_empty_session_record(session_id));
    db.expect_get_user_by_username().never();
    db.expect_create_session().never();
    db.expect_delete_session().never();
    db.expect_update_session().never();

    // Setup router with an enforcing limiter allowing one failure per pair
    let rate_limiter = log_in_failures_rate_limiter(RateLimitMode::Enforce);
    let router = TestRouterBuilder::new(db)
        .with_rate_limiter(rate_limiter.clone())
        .with_server_cfg(email_login_cfg())
        .build()
        .await;

    // Spend the failed attempt budget of the pair
    rate_limiter
        .log_in_failure_limit(LOG_IN_CLIENT)
        .reserve("test-user", Instant::now())
        .expect("first failed attempt to be allowed")
        .record_failure();

    // Send a log in request for the exhausted pair
    let request = log_in_request(session_id, "username=test-user&password=secret-password");
    let (parts, bytes) = send(router, request).await;

    // Check the plain-text rejection is returned
    assert_eq!(parts.status, StatusCode::TOO_MANY_REQUESTS);
    assert_eq!(parts.headers.get(RETRY_AFTER).unwrap(), "3600");
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        CACHE_CONTROL_NO_STORE
    );
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        "text/plain; charset=utf-8"
    );
    assert!(!parts.headers.contains_key(SET_COOKIE));
    assert_eq!(
        bytes,
        "Too many requests from your network. Please wait 60 minutes and try again."
    );
}

#[tokio::test]
async fn test_log_in_rejects_second_failure_with_burst_of_one() {
    // Setup database mock for two attempts with the same session, one authenticated
    let session_id = session::Id::default();
    let session_record = sample_empty_session_record(session_id);
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(2)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_username()
        .times(1)
        .withf(move |username| username == "test-user")
        .returning(|_| Ok(None));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            message_matches(
                record,
                "Invalid credentials. Please make sure you have verified your email address.",
            )
        })
        .returning(|_| Ok(()));

    // Setup router with an enforcing limiter allowing one failure per pair
    let rate_limiter = log_in_failures_rate_limiter(RateLimitMode::Enforce);
    let router = TestRouterBuilder::new(db)
        .with_rate_limiter(rate_limiter.clone())
        .with_server_cfg(email_login_cfg())
        .build()
        .await;

    // Send a first log in request with invalid credentials
    let first_request = log_in_request(session_id, "username=test-user&password=wrong");
    let (first_parts, first_bytes) = send(router.clone(), first_request).await;

    // Check the first failure shows the log in page again
    assert_empty_response(&first_parts, &first_bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        first_parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(LOG_IN_URL)),
    );

    // Send a second log in request with invalid credentials
    let second_request = log_in_request(session_id, "username=test-user&password=wrong");
    let (second_parts, second_bytes) = send(router, second_request).await;

    // Check the second failure is rejected
    assert_eq!(second_parts.status, StatusCode::TOO_MANY_REQUESTS);
    assert_eq!(second_parts.headers.get(RETRY_AFTER).unwrap(), "3600");
    assert_eq!(
        second_bytes,
        "Too many requests from your network. Please wait 60 minutes and try again."
    );

    // Check both attempts were counted and the second one rejected
    let window = rate_limiter.take_window();
    let failures = window.limit(Limit::LogInFailures);
    assert_eq!(failures.requests, 2);
    assert_eq!(failures.over_limit, 1);
}

#[tokio::test]
async fn test_log_in_success_refunds_failure_reservation() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let user = auth::User {
        password: Some(password_auth::generate_hash("secret-password")),
        ..sample_auth_user(ids.user_id, "hash")
    };

    // Setup database mock for a successful log in
    let mut db = MockDB::new();
    expect_successful_log_in(&mut db, &ids, user);

    // Setup router with an enforcing limiter allowing one failure per pair
    let rate_limiter = log_in_failures_rate_limiter(RateLimitMode::Enforce);
    let router = TestRouterBuilder::new(db)
        .with_rate_limiter(rate_limiter.clone())
        .with_server_cfg(email_login_cfg())
        .build()
        .await;

    // Send a log in request with valid credentials
    let request = log_in_request(
        ids.session_id,
        "username=test-user&password=secret-password",
    );
    let (parts, bytes) = send(router, request).await;

    // Check the user is logged in
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert!(parts.headers.contains_key(SET_COOKIE));
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static("/")),
    );

    // Check the next failed attempt for the pair is still allowed
    rate_limiter
        .log_in_failure_limit(LOG_IN_CLIENT)
        .reserve("test-user", Instant::now())
        .expect("failed attempt to be allowed after the refund")
        .record_failure();
    let window = rate_limiter.take_window();
    let failures = window.limit(Limit::LogInFailures);
    assert_eq!(failures.requests, 2);
    assert_eq!(failures.over_limit, 0);
}

#[tokio::test]
async fn test_log_in_success_refunds_failure_reservation_in_observe_mode() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let user = auth::User {
        password: Some(password_auth::generate_hash("secret-password")),
        ..sample_auth_user(ids.user_id, "hash")
    };

    // Setup database mock for a successful log in
    let mut db = MockDB::new();
    expect_successful_log_in(&mut db, &ids, user);

    // Setup router with an observing limiter allowing one failure per pair
    let rate_limiter = log_in_failures_rate_limiter(RateLimitMode::Observe);
    let router = TestRouterBuilder::new(db)
        .with_rate_limiter(rate_limiter.clone())
        .with_server_cfg(email_login_cfg())
        .build()
        .await;

    // Send a log in request with valid credentials
    let request = log_in_request(
        ids.session_id,
        "username=test-user&password=secret-password",
    );
    let (parts, bytes) = send(router, request).await;

    // Check the user is logged in
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert!(parts.headers.contains_key(SET_COOKIE));
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static("/")),
    );

    // Check the next failed attempt for the pair is not over the limit
    rate_limiter
        .log_in_failure_limit(LOG_IN_CLIENT)
        .reserve("test-user", Instant::now())
        .expect("observe mode to never refuse a reservation")
        .record_failure();
    let window = rate_limiter.take_window();
    let failures = window.limit(Limit::LogInFailures);
    assert_eq!(failures.requests, 2);
    assert_eq!(failures.over_limit, 0);
}

#[tokio::test]
async fn test_log_out_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_delete_session()
        .times(1)
        .withf(move |id| *id == ids.session_id)
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, empty_request("POST", "/log-out", ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(LOG_IN_URL)),
    );
}

#[tokio::test]
async fn test_log_out_success_with_invalid_session() {
    // Setup database mock without a stored session
    let session_id = session::Id::default();
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(|_| Ok(None));
    db.expect_get_user_by_id().times(0);
    db.expect_delete_session().times(0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, empty_request("POST", "/log-out", session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(LOG_IN_URL)),
    );

    // Check the private response removes the stale session cookie
    let set_cookie = parts.headers.get(SET_COOKIE).unwrap().to_str().unwrap();
    assert!(set_cookie.starts_with("id=;"), "{set_cookie}");
    assert!(set_cookie.contains("Max-Age=0"), "{set_cookie}");
}

// OAuth2 callbacks and redirects.

#[tokio::test]
async fn test_oauth2_callback_missing_pkce_verifier() {
    // Setup database mock with csrf state and flow provider but no pkce verifier
    let session_id = session::Id::default();
    let session_record = session_record_with_values(
        session_id,
        &[
            (OAUTH2_CSRF_STATE_KEY, "state-in-session"),
            (OAUTH2_FLOW_PROVIDER_KEY, "oauth2:github"),
        ],
    );
    let mut db = MockDB::new();
    expect_stored_session(&mut db, session_record);
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            message_matches(record, "OAuth2 authorization failed")
                && !record.data.contains_key(OAUTH2_CSRF_STATE_KEY)
                && !record.data.contains_key(OAUTH2_FLOW_PROVIDER_KEY)
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_server_cfg(github_login_cfg())
        .build()
        .await;
    let uri = "/log-in/oauth2/github/callback?code=test-code&state=state-in-session";
    let (parts, bytes) = send(router, get_request(uri, session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(LOG_IN_URL)),
    );
}

#[tokio::test]
async fn test_oauth2_callback_missing_state() {
    // Setup database mock with a session without csrf state but with sibling flow keys
    let session_id = session::Id::default();
    let session_record = session_record_with_values(
        session_id,
        &[
            (OAUTH2_FLOW_PROVIDER_KEY, "oauth2:github"),
            (OAUTH2_PKCE_VERIFIER_KEY, "verifier-in-session"),
        ],
    );
    let mut db = MockDB::new();
    expect_stored_session(&mut db, session_record);
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            message_matches(record, "OAuth2 authorization failed")
                && !record.data.contains_key(OAUTH2_FLOW_PROVIDER_KEY)
                && !record.data.contains_key(OAUTH2_PKCE_VERIFIER_KEY)
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_server_cfg(github_login_cfg())
        .build()
        .await;
    let uri = "/log-in/oauth2/github/callback?code=test-code&state=test-state";
    let (parts, bytes) = send(router, get_request(uri, session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(LOG_IN_URL)),
    );
}

#[tokio::test]
async fn test_oauth2_callback_provider_mismatch() {
    // Setup in-memory session originating from OIDC instead of OAuth2 GitHub
    let session = callback_session(
        "oidc:linuxfoundation",
        Some("nonce-in-session"),
        Some("/dashboard"),
    )
    .await;
    let mut db = MockDB::new();
    db.expect_list_user_groups().times(0);
    let db: DynDB = Arc::new(db);
    let mut callback_auth = MockCallbackAuth::default();

    // Execute helper against the GitHub OAuth2 callback
    let (error_message, on_error) = capture_error();
    let redirect = oauth2_callback_with_auth(
        &mut callback_auth,
        session.clone(),
        &db,
        OAuth2Provider::GitHub,
        "test-code".to_string(),
        oauth2::CsrfToken::new("state-in-session".to_string()),
        on_error,
    )
    .await
    .unwrap();

    // Check no token exchange occurs and pending flow state is evicted
    let response = redirect.into_response();
    let csrf_state: Option<String> = session.get(OAUTH2_CSRF_STATE_KEY).await.unwrap();
    let flow_provider: Option<String> = session.get(OAUTH2_FLOW_PROVIDER_KEY).await.unwrap();
    let nonce: Option<String> = session.get(OIDC_NONCE_KEY).await.unwrap();
    let pkce_verifier: Option<String> = session.get(OAUTH2_PKCE_VERIFIER_KEY).await.unwrap();
    assert_eq!(response.status(), StatusCode::SEE_OTHER);
    assert_eq!(
        response.headers().get(LOCATION),
        Some(&HeaderValue::from_static(LOG_IN_URL)),
    );
    assert_eq!(
        *error_message.lock().unwrap(),
        Some("OAuth2 authorization failed".to_string()),
    );
    assert_eq!(callback_auth.oauth2_call, None);
    assert!(!callback_auth.login_called);
    assert_eq!(csrf_state, None);
    assert_eq!(flow_provider, None);
    assert_eq!(nonce, None);
    assert_eq!(pkce_verifier, None);
}

#[tokio::test]
async fn test_oauth2_callback_state_mismatch() {
    // Setup database mock with a session holding another csrf state, flow provider and pkce verifier
    let session_id = session::Id::default();
    let session_record = session_record_with_values(
        session_id,
        &[
            (OAUTH2_CSRF_STATE_KEY, "state-in-session"),
            (OAUTH2_FLOW_PROVIDER_KEY, "oauth2:github"),
            (OAUTH2_PKCE_VERIFIER_KEY, "verifier-in-session"),
        ],
    );
    let mut db = MockDB::new();
    expect_stored_session(&mut db, session_record);
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            message_matches(record, "OAuth2 authorization failed")
                && !record.data.contains_key(OAUTH2_CSRF_STATE_KEY)
                && !record.data.contains_key(OAUTH2_FLOW_PROVIDER_KEY)
                && !record.data.contains_key(OAUTH2_PKCE_VERIFIER_KEY)
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_server_cfg(github_login_cfg())
        .build()
        .await;
    let uri = "/log-in/oauth2/github/callback?code=test-code&state=state-in-request";
    let (parts, bytes) = send(router, get_request(uri, session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(LOG_IN_URL)),
    );
}

#[tokio::test]
async fn test_oauth2_callback_authorization_error() {
    // Setup in-memory session and mocks
    let session = callback_session("oauth2:github", None, Some("/dashboard")).await;
    let mut db = MockDB::new();
    db.expect_list_user_groups().times(0);
    let db: DynDB = Arc::new(db);
    let mut callback_auth = MockCallbackAuth {
        oauth2_result: Some(Err("oauth2 auth error".to_string())),
        ..Default::default()
    };

    // Execute helper
    let (error_message, on_error) = capture_error();
    let redirect = oauth2_callback_with_auth(
        &mut callback_auth,
        session.clone(),
        &db,
        OAuth2Provider::GitHub,
        "test-code".to_string(),
        oauth2::CsrfToken::new("state-in-session".to_string()),
        on_error,
    )
    .await
    .unwrap();

    // Check callback result and side effects
    let response = redirect.into_response();
    let auth_provider: Option<String> = session.get(AUTH_PROVIDER_KEY).await.unwrap();
    let pkce_verifier: Option<String> = session.get(OAUTH2_PKCE_VERIFIER_KEY).await.unwrap();
    assert_eq!(response.status(), StatusCode::SEE_OTHER);
    assert_eq!(
        response.headers().get(LOCATION),
        Some(&HeaderValue::from_static("/log-in?next_url=%2Fdashboard")),
    );
    assert_eq!(
        *error_message.lock().unwrap(),
        Some("OAuth2 authorization failed".to_string()),
    );
    assert_eq!(pkce_verifier, None);
    assert!(!callback_auth.login_called);
    assert_eq!(auth_provider, None);
    assert_eq!(selected_ids(&session).await, (None, None));
}

#[tokio::test]
async fn test_oauth2_callback_rejects_unauthenticated_user() {
    // Setup in-memory session and mocks
    let session = callback_session("oauth2:github", None, Some("/dashboard")).await;
    let mut db = MockDB::new();
    db.expect_list_user_groups().times(0);
    let db: DynDB = Arc::new(db);
    let mut callback_auth = MockCallbackAuth {
        oauth2_result: Some(Ok(None)),
        ..Default::default()
    };

    // Execute helper
    let (error_message, on_error) = capture_error();
    let redirect = oauth2_callback_with_auth(
        &mut callback_auth,
        session.clone(),
        &db,
        OAuth2Provider::GitHub,
        "test-code".to_string(),
        oauth2::CsrfToken::new("state-in-session".to_string()),
        on_error,
    )
    .await
    .unwrap();

    // Check the user is sent back to log in without being logged in
    let response = redirect.into_response();
    let auth_provider: Option<String> = session.get(AUTH_PROVIDER_KEY).await.unwrap();
    assert_eq!(response.status(), StatusCode::SEE_OTHER);
    assert_eq!(
        response.headers().get(LOCATION),
        Some(&HeaderValue::from_static("/log-in?next_url=%2Fdashboard")),
    );
    assert_eq!(
        *error_message.lock().unwrap(),
        Some("OAuth2 authorization failed".to_string()),
    );
    assert!(!callback_auth.login_called);
    assert_eq!(auth_provider, None);
    assert_eq!(selected_ids(&session).await, (None, None));
}

#[tokio::test]
async fn test_oauth2_callback_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let groups = sample_user_groups_by_community(ids.community_id, ids.group_id);

    // Setup in-memory session and mocks
    let session = callback_session("oauth2:github", None, Some("/dashboard")).await;
    let mut db = MockDB::new();
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &ids.user_id)
        .returning(move |_| Ok(groups.clone()));
    let db: DynDB = Arc::new(db);
    let mut callback_auth = MockCallbackAuth {
        login_result: Some(Ok(())),
        oauth2_result: Some(Ok(Some(sample_auth_user(ids.user_id, "hash")))),
        ..Default::default()
    };

    // Execute helper
    let redirect = oauth2_callback_with_auth(
        &mut callback_auth,
        session.clone(),
        &db,
        OAuth2Provider::GitHub,
        "test-code".to_string(),
        oauth2::CsrfToken::new("state-in-session".to_string()),
        |_| {
            panic!("oauth2 callback success should not emit an error message");
        },
    )
    .await
    .unwrap();

    // Check callback result and side effects, including PKCE verifier consumption
    let response = redirect.into_response();
    let auth_provider: Option<String> = session.get(AUTH_PROVIDER_KEY).await.unwrap();
    let flow_provider: Option<String> = session.get(OAUTH2_FLOW_PROVIDER_KEY).await.unwrap();
    let pkce_verifier: Option<String> = session.get(OAUTH2_PKCE_VERIFIER_KEY).await.unwrap();
    assert_eq!(response.status(), StatusCode::SEE_OTHER);
    assert_eq!(
        response.headers().get(LOCATION),
        Some(&HeaderValue::from_static("/dashboard")),
    );
    assert_eq!(
        callback_auth.oauth2_call,
        Some((
            "test-code".to_string(),
            "verifier-in-session".to_string(),
            OAuth2Provider::GitHub,
        )),
    );
    assert_eq!(flow_provider, None);
    assert_eq!(pkce_verifier, None);
    assert!(callback_auth.login_called);
    assert_eq!(
        auth_provider.as_deref(),
        Some(OAuth2Provider::GitHub.as_ref())
    );
    assert_eq!(
        selected_ids(&session).await,
        (Some(ids.community_id), Some(ids.group_id)),
    );
}

#[tokio::test]
async fn test_oauth2_callback_returns_error_when_provider_is_not_configured() {
    // Setup database mock with a valid csrf state, flow provider, pkce verifier and next url
    let session_id = session::Id::default();
    let session_record = session_record_with_values(
        session_id,
        &[
            (OAUTH2_CSRF_STATE_KEY, "state-in-session"),
            (OAUTH2_FLOW_PROVIDER_KEY, "oauth2:github"),
            (OAUTH2_PKCE_VERIFIER_KEY, "verifier-in-session"),
            (NEXT_URL_KEY, "/dashboard"),
        ],
    );
    let mut db = MockDB::new();
    expect_stored_session(&mut db, session_record);
    db.expect_update_session()
        .times(1)
        .withf(move |record| message_matches(record, "OAuth2 authorization failed"))
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_server_cfg(github_login_cfg())
        .build()
        .await;
    let uri = "/log-in/oauth2/github/callback?code=test-code&state=state-in-session";
    let (parts, bytes) = send(router, get_request(uri, session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static("/log-in?next_url=%2Fdashboard")),
    );
}

#[tokio::test]
async fn test_oauth2_redirect_rejects_unknown_provider() {
    // Setup router with GitHub login enabled
    let router = TestRouterBuilder::new(MockDB::new())
        .with_server_cfg(github_login_cfg())
        .build()
        .await;

    // Send redirect request with an unknown provider slug
    let request = request("GET", "/log-in/oauth2/gitlab").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the custom OAuth2 extractor rejection is returned instead of Axum's raw path error
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(bytes.as_ref(), b"missing oauth2 provider");
}

#[tokio::test]
async fn test_oauth2_redirect_success() {
    // Setup session and form input
    let session = Session::new(None, Arc::new(MemoryStore::default()), None);
    let query = Query(NextUrl {
        next_url: Some("/dashboard".to_string()),
    });

    // Setup oauth2 provider details
    let client = BasicClient::new(ClientId::new("client-id".to_string()))
        .set_client_secret(ClientSecret::new("client-secret".to_string()))
        .set_auth_uri(AuthUrl::new("https://oauth.example/authorize".to_string()).unwrap())
        .set_token_uri(TokenUrl::new("https://oauth.example/token".to_string()).unwrap())
        .set_redirect_uri(
            RedirectUrl::new("https://app.example/log-in/oauth2/github/callback".to_string())
                .unwrap(),
        );
    let provider = OAuth2ProviderDetails {
        client,
        scopes: vec!["read:user".to_string()],
    };

    // Execute handler
    let response = oauth2_redirect(
        session.clone(),
        OAuth2(Arc::new(provider)),
        Path(OAuth2Provider::GitHub),
        query,
    )
    .await
    .expect("oauth2 redirect should succeed")
    .into_response();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let location = parts.headers.get(LOCATION).unwrap().to_str().unwrap();
    let (base_url, query) = location
        .split_once('?')
        .expect("redirect url to contain query string");

    // Check response matches expectations, including S256 PKCE challenge and stored verifier
    let csrf_state: Option<String> = session.get(OAUTH2_CSRF_STATE_KEY).await.unwrap();
    let flow_provider: Option<String> = session.get(OAUTH2_FLOW_PROVIDER_KEY).await.unwrap();
    let pkce_verifier: Option<String> = session.get(OAUTH2_PKCE_VERIFIER_KEY).await.unwrap();
    let next_url: Option<Option<String>> = session.get(NEXT_URL_KEY).await.unwrap();
    let expected_challenge = PkceCodeChallenge::from_code_verifier_sha256(&PkceCodeVerifier::new(
        pkce_verifier.expect("pkce verifier in session"),
    ));
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(base_url, "https://oauth.example/authorize");
    assert_eq!(
        csrf_state.as_deref(),
        query_param(query, "state").as_deref()
    );
    assert_eq!(flow_provider.as_deref(), Some("oauth2:github"));
    assert_eq!(
        query_param(query, "code_challenge_method").as_deref(),
        Some("S256"),
    );
    assert_eq!(
        query_param(query, "code_challenge").as_deref(),
        Some(expected_challenge.as_str()),
    );
    assert_eq!(next_url, Some(Some("/dashboard".to_string())));
}

// OIDC callbacks and redirects.

#[tokio::test]
async fn test_oidc_callback_missing_nonce() {
    // Setup database mock with a csrf state, flow provider and pkce verifier but no nonce
    let session_id = session::Id::default();
    let session_record = session_record_with_values(
        session_id,
        &[
            (OAUTH2_CSRF_STATE_KEY, "state-in-session"),
            (OAUTH2_FLOW_PROVIDER_KEY, "oidc:linuxfoundation"),
            (OAUTH2_PKCE_VERIFIER_KEY, "verifier-in-session"),
        ],
    );
    let mut db = MockDB::new();
    expect_stored_session(&mut db, session_record);
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            message_matches(record, "OpenID Connect authorization failed")
                && !record.data.contains_key(OAUTH2_CSRF_STATE_KEY)
                && !record.data.contains_key(OAUTH2_FLOW_PROVIDER_KEY)
                && !record.data.contains_key(OAUTH2_PKCE_VERIFIER_KEY)
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_server_cfg(linuxfoundation_login_cfg())
        .build()
        .await;
    let uri = "/log-in/oidc/linuxfoundation/callback?code=test-code&state=state-in-session";
    let (parts, bytes) = send(router, get_request(uri, session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(LOG_IN_URL)),
    );
}

#[tokio::test]
async fn test_oidc_callback_missing_pkce_verifier() {
    // Setup database mock with csrf state, flow provider and nonce but no pkce verifier
    let session_id = session::Id::default();
    let session_record = session_record_with_values(
        session_id,
        &[
            (OAUTH2_CSRF_STATE_KEY, "state-in-session"),
            (OAUTH2_FLOW_PROVIDER_KEY, "oidc:linuxfoundation"),
            (OIDC_NONCE_KEY, "nonce-in-session"),
        ],
    );
    let mut db = MockDB::new();
    expect_stored_session(&mut db, session_record);
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            message_matches(record, "OpenID Connect authorization failed")
                && !record.data.contains_key(OAUTH2_CSRF_STATE_KEY)
                && !record.data.contains_key(OAUTH2_FLOW_PROVIDER_KEY)
                && !record.data.contains_key(OIDC_NONCE_KEY)
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_server_cfg(linuxfoundation_login_cfg())
        .build()
        .await;
    let uri = "/log-in/oidc/linuxfoundation/callback?code=test-code&state=state-in-session";
    let (parts, bytes) = send(router, get_request(uri, session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(LOG_IN_URL)),
    );
}

#[tokio::test]
async fn test_oidc_callback_missing_state() {
    // Setup database mock with a session without csrf state but with sibling flow keys
    let session_id = session::Id::default();
    let session_record = session_record_with_values(
        session_id,
        &[
            (OAUTH2_FLOW_PROVIDER_KEY, "oidc:linuxfoundation"),
            (OAUTH2_PKCE_VERIFIER_KEY, "verifier-in-session"),
            (OIDC_NONCE_KEY, "nonce-in-session"),
        ],
    );
    let mut db = MockDB::new();
    expect_stored_session(&mut db, session_record);
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            message_matches(record, "OpenID Connect authorization failed")
                && !record.data.contains_key(OAUTH2_FLOW_PROVIDER_KEY)
                && !record.data.contains_key(OAUTH2_PKCE_VERIFIER_KEY)
                && !record.data.contains_key(OIDC_NONCE_KEY)
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_server_cfg(linuxfoundation_login_cfg())
        .build()
        .await;
    let uri = "/log-in/oidc/linuxfoundation/callback?code=test-code&state=test-state";
    let (parts, bytes) = send(router, get_request(uri, session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(LOG_IN_URL)),
    );
}

#[tokio::test]
async fn test_oidc_callback_provider_mismatch() {
    // Setup in-memory session originating from OAuth2 GitHub instead of OIDC
    let session = callback_session(
        "oauth2:github",
        Some("nonce-in-session"),
        Some("/dashboard"),
    )
    .await;
    let mut db = MockDB::new();
    db.expect_list_user_groups().times(0);
    let db: DynDB = Arc::new(db);
    let mut callback_auth = MockCallbackAuth::default();

    // Execute helper against the Linux Foundation OIDC callback
    let (error_message, on_error) = capture_error();
    let redirect = oidc_callback_with_auth(
        &mut callback_auth,
        session.clone(),
        &db,
        OidcProvider::LinuxFoundation,
        "test-code".to_string(),
        oauth2::CsrfToken::new("state-in-session".to_string()),
        on_error,
    )
    .await
    .unwrap();

    // Check no token exchange occurs and pending flow state is evicted
    let response = redirect.into_response();
    let csrf_state: Option<String> = session.get(OAUTH2_CSRF_STATE_KEY).await.unwrap();
    let flow_provider: Option<String> = session.get(OAUTH2_FLOW_PROVIDER_KEY).await.unwrap();
    let nonce: Option<String> = session.get(OIDC_NONCE_KEY).await.unwrap();
    let pkce_verifier: Option<String> = session.get(OAUTH2_PKCE_VERIFIER_KEY).await.unwrap();
    assert_eq!(response.status(), StatusCode::SEE_OTHER);
    assert_eq!(
        response.headers().get(LOCATION),
        Some(&HeaderValue::from_static(LOG_IN_URL)),
    );
    assert_eq!(
        *error_message.lock().unwrap(),
        Some("OpenID Connect authorization failed".to_string()),
    );
    assert_eq!(callback_auth.oidc_call, None);
    assert!(!callback_auth.login_called);
    assert_eq!(csrf_state, None);
    assert_eq!(flow_provider, None);
    assert_eq!(nonce, None);
    assert_eq!(pkce_verifier, None);
}

#[tokio::test]
async fn test_oidc_callback_state_mismatch() {
    // Setup database mock with a session holding another csrf state
    let session_id = session::Id::default();
    let session_record = session_record_with_values(
        session_id,
        &[
            (OAUTH2_CSRF_STATE_KEY, "state-in-session"),
            (OAUTH2_FLOW_PROVIDER_KEY, "oidc:linuxfoundation"),
            (OAUTH2_PKCE_VERIFIER_KEY, "verifier-in-session"),
            (OIDC_NONCE_KEY, "nonce-in-session"),
        ],
    );
    let mut db = MockDB::new();
    expect_stored_session(&mut db, session_record);
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            message_matches(record, "OpenID Connect authorization failed")
                && !record.data.contains_key(OAUTH2_CSRF_STATE_KEY)
                && !record.data.contains_key(OAUTH2_FLOW_PROVIDER_KEY)
                && !record.data.contains_key(OAUTH2_PKCE_VERIFIER_KEY)
                && !record.data.contains_key(OIDC_NONCE_KEY)
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_server_cfg(linuxfoundation_login_cfg())
        .build()
        .await;
    let uri = "/log-in/oidc/linuxfoundation/callback?code=test-code&state=state-in-request";
    let (parts, bytes) = send(router, get_request(uri, session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(LOG_IN_URL)),
    );
}

#[tokio::test]
async fn test_oidc_callback_authorization_error() {
    // Setup in-memory session and mocks
    let session = callback_session(
        "oidc:linuxfoundation",
        Some("nonce-in-session"),
        Some("/dashboard"),
    )
    .await;
    let mut db = MockDB::new();
    db.expect_list_user_groups().times(0);
    let db: DynDB = Arc::new(db);
    let mut callback_auth = MockCallbackAuth {
        oidc_result: Some(Err("oidc auth error".to_string())),
        ..Default::default()
    };

    // Execute helper
    let (error_message, on_error) = capture_error();
    let redirect = oidc_callback_with_auth(
        &mut callback_auth,
        session.clone(),
        &db,
        OidcProvider::LinuxFoundation,
        "test-code".to_string(),
        oauth2::CsrfToken::new("state-in-session".to_string()),
        on_error,
    )
    .await
    .unwrap();

    // Check callback result and side effects
    let response = redirect.into_response();
    let auth_provider: Option<String> = session.get(AUTH_PROVIDER_KEY).await.unwrap();
    let pkce_verifier: Option<String> = session.get(OAUTH2_PKCE_VERIFIER_KEY).await.unwrap();
    assert_eq!(response.status(), StatusCode::SEE_OTHER);
    assert_eq!(
        response.headers().get(LOCATION),
        Some(&HeaderValue::from_static("/log-in?next_url=%2Fdashboard")),
    );
    assert_eq!(
        *error_message.lock().unwrap(),
        Some("OpenID Connect authorization failed".to_string()),
    );
    assert_eq!(pkce_verifier, None);
    assert!(!callback_auth.login_called);
    assert_eq!(auth_provider, None);
    assert_eq!(selected_ids(&session).await, (None, None));
}

#[tokio::test]
async fn test_oidc_callback_rejects_unauthenticated_user() {
    // Setup in-memory session and mocks
    let session = callback_session(
        "oidc:linuxfoundation",
        Some("nonce-in-session"),
        Some("/dashboard"),
    )
    .await;
    let mut db = MockDB::new();
    db.expect_list_user_groups().times(0);
    let db: DynDB = Arc::new(db);
    let mut callback_auth = MockCallbackAuth {
        oidc_result: Some(Ok(None)),
        ..Default::default()
    };

    // Execute helper
    let (error_message, on_error) = capture_error();
    let redirect = oidc_callback_with_auth(
        &mut callback_auth,
        session.clone(),
        &db,
        OidcProvider::LinuxFoundation,
        "test-code".to_string(),
        oauth2::CsrfToken::new("state-in-session".to_string()),
        on_error,
    )
    .await
    .unwrap();

    // Check the user is sent back to log in without being logged in
    let response = redirect.into_response();
    let auth_provider: Option<String> = session.get(AUTH_PROVIDER_KEY).await.unwrap();
    assert_eq!(response.status(), StatusCode::SEE_OTHER);
    assert_eq!(
        response.headers().get(LOCATION),
        Some(&HeaderValue::from_static("/log-in?next_url=%2Fdashboard")),
    );
    assert_eq!(
        *error_message.lock().unwrap(),
        Some("OpenID Connect authorization failed".to_string()),
    );
    assert!(!callback_auth.login_called);
    assert_eq!(auth_provider, None);
    assert_eq!(selected_ids(&session).await, (None, None));
}

#[tokio::test]
async fn test_oidc_callback_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let groups = sample_user_groups_by_community(ids.community_id, ids.group_id);

    // Setup in-memory session and mocks
    let session = callback_session(
        "oidc:linuxfoundation",
        Some("nonce-in-session"),
        Some("/dashboard"),
    )
    .await;
    let mut db = MockDB::new();
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &ids.user_id)
        .returning(move |_| Ok(groups.clone()));
    let db: DynDB = Arc::new(db);
    let mut callback_auth = MockCallbackAuth {
        login_result: Some(Ok(())),
        oidc_result: Some(Ok(Some(sample_auth_user(ids.user_id, "hash")))),
        ..Default::default()
    };

    // Execute helper
    let redirect = oidc_callback_with_auth(
        &mut callback_auth,
        session.clone(),
        &db,
        OidcProvider::LinuxFoundation,
        "test-code".to_string(),
        oauth2::CsrfToken::new("state-in-session".to_string()),
        |_| {
            panic!("oidc callback success should not emit an error message");
        },
    )
    .await
    .unwrap();

    // Check callback result and side effects, including nonce and PKCE hand-off
    let response = redirect.into_response();
    let auth_provider: Option<String> = session.get(AUTH_PROVIDER_KEY).await.unwrap();
    let flow_provider: Option<String> = session.get(OAUTH2_FLOW_PROVIDER_KEY).await.unwrap();
    let nonce: Option<String> = session.get(OIDC_NONCE_KEY).await.unwrap();
    let pkce_verifier: Option<String> = session.get(OAUTH2_PKCE_VERIFIER_KEY).await.unwrap();
    assert_eq!(response.status(), StatusCode::SEE_OTHER);
    assert_eq!(
        response.headers().get(LOCATION),
        Some(&HeaderValue::from_static("/dashboard")),
    );
    assert_eq!(
        callback_auth.oidc_call,
        Some((
            "test-code".to_string(),
            "nonce-in-session".to_string(),
            "verifier-in-session".to_string(),
            OidcProvider::LinuxFoundation,
        )),
    );
    assert_eq!(flow_provider, None);
    assert_eq!(nonce, None);
    assert_eq!(pkce_verifier, None);
    assert!(callback_auth.login_called);
    assert_eq!(
        auth_provider.as_deref(),
        Some(OidcProvider::LinuxFoundation.as_ref())
    );
    assert_eq!(
        selected_ids(&session).await,
        (Some(ids.community_id), Some(ids.group_id)),
    );
}

#[tokio::test]
async fn test_oidc_callback_returns_error_when_provider_is_not_configured() {
    // Setup database mock with a valid csrf state, flow provider, pkce verifier, nonce and next url
    let session_id = session::Id::default();
    let session_record = session_record_with_values(
        session_id,
        &[
            (OAUTH2_CSRF_STATE_KEY, "state-in-session"),
            (OAUTH2_FLOW_PROVIDER_KEY, "oidc:linuxfoundation"),
            (OAUTH2_PKCE_VERIFIER_KEY, "verifier-in-session"),
            (OIDC_NONCE_KEY, "nonce-in-session"),
            (NEXT_URL_KEY, "/dashboard"),
        ],
    );
    let mut db = MockDB::new();
    expect_stored_session(&mut db, session_record);
    db.expect_update_session()
        .times(1)
        .withf(move |record| message_matches(record, "OpenID Connect authorization failed"))
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_server_cfg(linuxfoundation_login_cfg())
        .build()
        .await;
    let uri = "/log-in/oidc/linuxfoundation/callback?code=test-code&state=state-in-session";
    let (parts, bytes) = send(router, get_request(uri, session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static("/log-in?next_url=%2Fdashboard")),
    );
}

#[tokio::test]
async fn test_oidc_redirect_rejects_unknown_provider() {
    // Setup router with Linux Foundation login enabled
    let router = TestRouterBuilder::new(MockDB::new())
        .with_server_cfg(linuxfoundation_login_cfg())
        .build()
        .await;

    // Send redirect request with an unknown provider slug
    let request = request("GET", "/log-in/oidc/unknown").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the custom Oidc extractor rejection is returned instead of Axum's raw path error
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(bytes.as_ref(), b"missing oidc provider");
}

#[tokio::test]
async fn test_oidc_redirect_success() {
    // Setup session and form input
    let session = Session::new(None, Arc::new(MemoryStore::default()), None);
    let query = Query(NextUrl {
        next_url: Some("/dashboard".to_string()),
    });

    // Setup oidc provider details
    let metadata = oidc::core::CoreProviderMetadata::new(
        oidc::IssuerUrl::new("https://issuer.example".to_string()).unwrap(),
        oidc::AuthUrl::new("https://issuer.example/authorize".to_string()).unwrap(),
        oidc::JsonWebKeySetUrl::new("https://issuer.example/jwks".to_string()).unwrap(),
        vec![oidc::ResponseTypes::new(vec![
            oidc::core::CoreResponseType::Code,
        ])],
        vec![oidc::core::CoreSubjectIdentifierType::Public],
        vec![oidc::core::CoreJwsSigningAlgorithm::RsaSsaPkcs1V15Sha256],
        oidc::EmptyAdditionalProviderMetadata::default(),
    )
    .set_jwks(oidc::JsonWebKeySet::new(vec![]));
    let client = oidc::core::CoreClient::from_provider_metadata(
        metadata,
        oidc::ClientId::new("client-id".to_string()),
        Some(oidc::ClientSecret::new("client-secret".to_string())),
    )
    .set_redirect_uri(
        oidc::RedirectUrl::new("https://app.example/log-in/oidc/provider/callback".to_string())
            .unwrap(),
    );
    let provider = OidcProviderDetails {
        client,
        scopes: vec!["openid".to_string()],
    };

    // Execute handler
    let response = oidc_redirect(
        session.clone(),
        Oidc(Arc::new(provider)),
        Path(OidcProvider::LinuxFoundation),
        query,
    )
    .await
    .expect("oidc redirect should succeed")
    .into_response();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let location = parts.headers.get(LOCATION).unwrap().to_str().unwrap();
    let (base_url, query) = location
        .split_once('?')
        .expect("redirect url to contain query string");

    // Check response matches expectations, including S256 PKCE challenge and stored verifier
    let csrf_state: Option<String> = session.get(OAUTH2_CSRF_STATE_KEY).await.unwrap();
    let flow_provider: Option<String> = session.get(OAUTH2_FLOW_PROVIDER_KEY).await.unwrap();
    let pkce_verifier: Option<String> = session.get(OAUTH2_PKCE_VERIFIER_KEY).await.unwrap();
    let nonce: Option<String> = session.get(OIDC_NONCE_KEY).await.unwrap();
    let next_url: Option<Option<String>> = session.get(NEXT_URL_KEY).await.unwrap();
    let expected_challenge = PkceCodeChallenge::from_code_verifier_sha256(&PkceCodeVerifier::new(
        pkce_verifier.expect("pkce verifier in session"),
    ));
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(base_url, "https://issuer.example/authorize");
    assert_eq!(
        csrf_state.as_deref(),
        query_param(query, "state").as_deref()
    );
    assert_eq!(flow_provider.as_deref(), Some("oidc:linuxfoundation"));
    assert_eq!(
        query_param(query, "code_challenge_method").as_deref(),
        Some("S256"),
    );
    assert_eq!(
        query_param(query, "code_challenge").as_deref(),
        Some(expected_challenge.as_str()),
    );
    assert_eq!(nonce.as_deref(), query_param(query, "nonce").as_deref());
    assert_eq!(next_url, Some(Some("/dashboard".to_string())));
}

// Sign up.

#[tokio::test]
async fn test_sign_up_success() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user = sample_auth_user(Uuid::new_v4(), "hash");

    // Setup database mock
    let mut db = MockDB::new();
    expect_stored_session(&mut db, sample_empty_session_record(session_id));
    expect_site_settings(&mut db);
    db.expect_activate_pre_registered_user_email_password()
        .times(1)
        .withf(move |summary, _| {
            summary.email == "test@example.test"
                && !matches!(summary.password.as_deref(), Some("secret-password"))
        })
        .returning(|_, _| Ok(None));
    db.expect_sign_up_user()
        .times(1)
        .withf(move |summary, verify, verification| {
            summary.email == "test@example.test"
                && !matches!(summary.password.as_deref(), Some("secret-password"))
                && !*verify
                && verification.is_some()
        })
        .returning(move |_, _, verification| Ok((user.clone(), verification.map(|v| v.code))));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            message_matches(
                record,
                "Please verify your email to complete the sign up process.",
            )
        })
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().times(0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_notifications_manager(nm)
        .with_server_cfg(email_login_cfg())
        .build()
        .await;
    let form =
        "email=test%40example.test&name=Test+User&username=test-user&password=secret-password";
    let request = form_request("POST", "/sign-up?next_url=%2Fwelcome", session_id, form);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static("/log-in?next_url=%2Fwelcome")),
    );
}

#[tokio::test]
async fn test_sign_up_activates_pre_registered_user() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user = sample_auth_user(Uuid::new_v4(), "hash");

    // Setup database mock
    let mut db = MockDB::new();
    expect_stored_session(&mut db, sample_empty_session_record(session_id));
    expect_site_settings(&mut db);
    db.expect_activate_pre_registered_user_email_password()
        .times(1)
        .withf(move |summary, _| {
            summary.email == "invited@example.test"
                && summary.name == "Invited User"
                && summary.username == "invited-user"
                && !matches!(summary.password.as_deref(), Some("secret-password"))
        })
        .returning(move |_, verification| Ok(Some((user.clone(), verification.code))));
    db.expect_sign_up_user().times(0);
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            message_matches(
                record,
                "Please verify your email to complete the sign up process.",
            )
        })
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().times(0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_notifications_manager(nm)
        .with_server_cfg(email_login_cfg())
        .build()
        .await;
    let form = "email=invited%40example.test&name=Invited+User&username=invited-user&password=secret-password";
    let uri = "/sign-up?next_url=%2Fdashboard%2Fuser%3Ftab%3Dinvitations";
    let (parts, bytes) = send(router, form_request("POST", uri, session_id, form)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(
            "/log-in?next_url=%2Fdashboard%2Fuser%3Ftab%3Dinvitations"
        )),
    );
}

#[tokio::test]
async fn test_sign_up_missing_password() {
    // Setup database mock
    let session_id = session::Id::default();
    let mut db = MockDB::new();
    expect_stored_session(&mut db, sample_empty_session_record(session_id));
    db.expect_activate_pre_registered_user_email_password().times(0);
    db.expect_sign_up_user().times(0);

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().times(0);

    // Setup router and send request without a password
    let router = TestRouterBuilder::new(db)
        .with_notifications_manager(nm)
        .with_server_cfg(email_login_cfg())
        .build()
        .await;
    let form = "email=test%40example.test&name=Test+User&username=test-user";
    let (parts, bytes) = send(router, form_request("POST", "/sign-up", session_id, form)).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(bytes, "password not provided");
}

#[tokio::test]
async fn test_sign_up_rejects_empty_normalized_base_url() {
    // Setup database mock
    let session_id = session::Id::default();
    let mut db = MockDB::new();
    expect_stored_session(&mut db, sample_empty_session_record(session_id));
    db.expect_get_site_settings().times(0);
    db.expect_activate_pre_registered_user_email_password().times(0);
    db.expect_sign_up_user().times(0);
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            message_matches(
                record,
                "Something went wrong while signing up. Please try again later.",
            )
        })
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().times(0);

    // Setup router with a base url that normalizes to empty and send request
    let server_cfg = HttpServerConfig {
        base_url: "/".to_string(),
        ..email_login_cfg()
    };
    let router = TestRouterBuilder::new(db)
        .with_notifications_manager(nm)
        .with_server_cfg(server_cfg)
        .build()
        .await;
    let form = "email=test%40example.test&name=Test+User&username=test-user&password=secretpw";
    let (parts, bytes) = send(router, form_request("POST", "/sign-up", session_id, form)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(SIGN_UP_URL)),
    );
}

#[tokio::test]
async fn test_sign_up_db_error() {
    // Setup database mock
    let session_id = session::Id::default();
    let mut db = MockDB::new();
    expect_stored_session(&mut db, sample_empty_session_record(session_id));
    expect_site_settings(&mut db);
    db.expect_activate_pre_registered_user_email_password()
        .times(1)
        .returning(|_, _| Ok(None));
    db.expect_sign_up_user()
        .times(1)
        .returning(|_, _, _| Err(anyhow!("db error")));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            message_matches(
                record,
                "Something went wrong while signing up. Please try again later.",
            )
        })
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().times(0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_notifications_manager(nm)
        .with_server_cfg(email_login_cfg())
        .build()
        .await;
    let form = "email=test%40example.test&name=Test+User&username=test-user&password=secretpw";
    let (parts, bytes) = send(router, form_request("POST", "/sign-up", session_id, form)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(SIGN_UP_URL)),
    );
}

#[tokio::test]
async fn test_sign_up_validation_error() {
    // Setup database mock
    let session_id = session::Id::default();
    let mut db = MockDB::new();
    expect_stored_session(&mut db, sample_empty_session_record(session_id));
    db.expect_activate_pre_registered_user_email_password().times(0);
    db.expect_sign_up_user().times(0);
    db.expect_update_session()
        .times(1)
        .withf(|record| {
            message_matches(
                record,
                "email: not a valid email: value is missing `@`\npassword: length is lower than 8\n",
            )
        })
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().times(0);

    // Setup router and send request with an invalid email and short password
    let router = TestRouterBuilder::new(db)
        .with_notifications_manager(nm)
        .with_server_cfg(email_login_cfg())
        .build()
        .await;
    let form = "email=invalid-email&name=Test+User&username=test-user&password=secret";
    let request = form_request("POST", "/sign-up?next_url=%2Fwelcome", session_id, form);
    let (parts, bytes) = send(router, request).await;

    // Check the sign up page is shown again keeping the next url
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static("/sign-up?next_url=%2Fwelcome")),
    );
}

// Account maintenance.

#[tokio::test]
async fn test_update_user_details_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_update_user_details()
        .times(1)
        .withf(move |uid, details| {
            *uid == ids.user_id
                && details.name == "Updated User"
                && details.company.as_deref() == Some("Example")
                && details.github_url.as_deref() == Some("https://github.com/updated-user")
        })
        .returning(|_, _| Ok(()));
    db.expect_update_session()
        .times(1)
        .withf(move |record| message_matches(record, "User details updated successfully."))
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let form =
        "name=Updated+User&company=Example&github_url=https%3A%2F%2Fgithub.com%2Fupdated-user";
    let request = form_request("PUT", UPDATE_DETAILS_URL, ids.session_id, form);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

#[tokio::test]
async fn test_update_user_details_returns_error_on_db_failure() {
    // Setup database mock with a failing write and no flash message
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_update_user_details()
        .times(1)
        .withf(move |uid, details| *uid == ids.user_id && details.name == "Updated User")
        .returning(|_, _| Err(anyhow!("db error")));
    db.expect_update_session().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let form = "name=Updated+User&company=Example";
    let request = form_request("PUT", UPDATE_DETAILS_URL, ids.session_id, form);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_update_user_details_invalid_body() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_update_user_details().times(0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request("PUT", UPDATE_DETAILS_URL, ids.session_id, "invalid");
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_non_empty_response(&parts, &bytes, StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_update_user_password_accepts_valid_change() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let existing_password_hash = password_auth::generate_hash("current-password");

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_get_user_password()
        .times(1)
        .withf(move |id| *id == ids.user_id)
        .returning(move |_| Ok(Some(existing_password_hash.clone())));
    db.expect_update_user_password()
        .times(1)
        .withf(move |uid, new_password| *uid == ids.user_id && new_password != "new-password")
        .returning(|_, _| Ok(()));
    db.expect_delete_session()
        .times(1)
        .withf(move |id| *id == ids.session_id)
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let form = "old_password=current-password&new_password=new-password";
    let request = form_request("PUT", UPDATE_PASSWORD_URL, ids.session_id, form);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(LOG_IN_URL)),
    );
}

#[tokio::test]
async fn test_update_user_password_rejects_wrong_old_password() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let existing_password_hash = password_auth::generate_hash("current-password");

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_get_user_password()
        .times(1)
        .withf(move |id| *id == ids.user_id)
        .returning(move |_| Ok(Some(existing_password_hash.clone())));
    db.expect_update_user_password().times(0);
    db.expect_delete_session().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let form = "old_password=wrong-password&new_password=new-password";
    let request = form_request("PUT", UPDATE_PASSWORD_URL, ids.session_id, form);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_update_user_password_returns_bad_request_when_hash_is_missing() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_get_user_password()
        .times(1)
        .withf(move |id| *id == ids.user_id)
        .returning(|_| Ok(None));
    db.expect_update_user_password().times(0);
    db.expect_delete_session().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let form = "old_password=current-password&new_password=new-password";
    let request = form_request("PUT", UPDATE_PASSWORD_URL, ids.session_id, form);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn test_update_user_password_returns_error_on_db_failure() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let existing_password_hash = password_auth::generate_hash("current-password");

    // Setup database mock with a failing write and no session logout
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_get_user_password()
        .times(1)
        .withf(move |id| *id == ids.user_id)
        .returning(move |_| Ok(Some(existing_password_hash.clone())));
    db.expect_update_user_password()
        .times(1)
        .withf(move |uid, new_password| *uid == ids.user_id && new_password != "new-password")
        .returning(|_, _| Err(anyhow!("db error")));
    db.expect_delete_session().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let form = "old_password=current-password&new_password=new-password";
    let request = form_request("PUT", UPDATE_PASSWORD_URL, ids.session_id, form);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_update_user_password_succeeds_when_session_delete_fails() {
    // Setup the authenticated user and current password
    let ids = DashboardIds::new();
    let existing_password_hash = password_auth::generate_hash("current-password");

    // Setup a successful password update followed by a session deletion failure
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_get_user_password()
        .times(1)
        .withf(move |id| *id == ids.user_id)
        .returning(move |_| Ok(Some(existing_password_hash.clone())));
    db.expect_update_user_password()
        .times(1)
        .withf(move |uid, new_password| *uid == ids.user_id && new_password != "new-password")
        .returning(|_, _| Ok(()));
    db.expect_delete_session()
        .times(1)
        .withf(move |id| *id == ids.session_id)
        .returning(|_| Err(anyhow!("db error")));
    db.expect_update_session()
        .times(1)
        .withf(move |record| record.id == ids.session_id && record.data.is_empty())
        .returning(|_| Ok(()));

    // Send the password update request
    let router = TestRouterBuilder::new(db).build().await;
    let form = "old_password=current-password&new_password=new-password";
    let request = form_request("PUT", UPDATE_PASSWORD_URL, ids.session_id, form);
    let (parts, bytes) = send(router, request).await;

    // Check the committed password change still reports success
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(LOG_IN_URL)),
    );
}

#[tokio::test]
async fn test_verify_email_success() {
    // Setup identifiers and database mock
    let session_id = session::Id::default();
    let verification_code = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_stored_session(&mut db, sample_empty_session_record(session_id));
    db.expect_verify_email()
        .times(1)
        .withf(move |code| *code == verification_code)
        .returning(|_| Ok(()));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            message_matches(
                record,
                "Email verified successfully. You can now log in using your credentials.",
            )
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_server_cfg(email_login_cfg())
        .build()
        .await;
    let uri = format!("/verify-email/{verification_code}");
    let (parts, bytes) = send(router, get_request(&uri, session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(LOG_IN_URL)),
    );
}

#[tokio::test]
async fn test_verify_email_failure() {
    // Setup identifiers and database mock
    let session_id = session::Id::default();
    let verification_code = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_stored_session(&mut db, sample_empty_session_record(session_id));
    db.expect_verify_email()
        .times(1)
        .withf(move |code| *code == verification_code)
        .returning(|_| Err(anyhow!("db error")));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            message_matches(
                record,
                "Error verifying email (please note that links are only valid for 24 hours).",
            )
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_server_cfg(email_login_cfg())
        .build()
        .await;
    let uri = format!("/verify-email/{verification_code}");
    let (parts, bytes) = send(router, get_request(&uri, session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(LOG_IN_URL)),
    );
}

// Pure helpers.

#[test]
fn test_get_log_in_url_appends_sanitized_next_url() {
    // Setup next url inputs and the log in url each one expects
    let cases = [
        ("no next url", None, LOG_IN_URL),
        (
            "internal next url",
            Some("/dashboard"),
            "/log-in?next_url=%2Fdashboard",
        ),
        (
            "external next url",
            Some("https://evil.example"),
            LOG_IN_URL,
        ),
        ("backslash next url", Some("/\\evil.example"), LOG_IN_URL),
    ];

    for (case, next_url, expected) in cases {
        assert_eq!(get_log_in_url(next_url), expected, "{case}");
    }
}

#[test]
fn test_oauth2_authorization_error_message_sanitizes_unknown_errors() {
    // Setup authorization errors and the flash message each one expects
    let unverified_email =
        format!("github profile error: {EXTERNAL_AUTH_EMAIL_NOT_VERIFIED_ERROR}");
    let cases = [
        (
            "unverified primary email",
            unverified_email.as_str(),
            OAUTH2_UNVERIFIED_EMAIL_MESSAGE,
        ),
        (
            "internal provider error",
            "oauth2 provider not found",
            OAUTH2_AUTHORIZATION_FAILED,
        ),
        (
            "database error",
            "error communicating with database: connection refused",
            OAUTH2_AUTHORIZATION_FAILED,
        ),
    ];

    for (case, err, expected) in cases {
        assert_eq!(oauth2_authorization_error_message(err), expected, "{case}");
    }
}

#[test]
fn test_oidc_authorization_error_message_maps_known_conflicts() {
    // Setup authorization errors and the flash message each one expects
    let email_conflict = format!("db error: {EXTERNAL_AUTH_EMAIL_CONFLICT_ERROR}");
    let identity_conflict = format!("db error: {EXTERNAL_AUTH_IDENTITY_CONFLICT_ERROR}");
    let unverified_email =
        format!("oidc claims error: {EXTERNAL_AUTH_OIDC_EMAIL_NOT_VERIFIED_ERROR}");
    let cases = [
        (
            "email conflict",
            email_conflict.as_str(),
            LF_SSO_EMAIL_CONFLICT_MESSAGE,
        ),
        (
            "identity conflict",
            identity_conflict.as_str(),
            LF_SSO_IDENTITY_CONFLICT_MESSAGE,
        ),
        (
            "unverified email",
            unverified_email.as_str(),
            LF_SSO_UNVERIFIED_EMAIL_MESSAGE,
        ),
        ("other error", "oidc auth error", OIDC_AUTHORIZATION_FAILED),
    ];

    for (case, err, expected) in cases {
        assert_eq!(oidc_authorization_error_message(err), expected, "{case}");
    }
}

#[test]
fn test_sanitize_next_url() {
    // Setup next url inputs and the sanitized value each one expects
    let cases = [
        ("internal path", "/dashboard", Some("/dashboard")),
        (
            "internal path with query and fragment",
            "/groups?page=2#section",
            Some("/groups?page=2#section"),
        ),
        ("padded internal path", "   /profile  ", Some("/profile")),
        ("empty", "", None),
        ("absolute url", "https://evil.example", None),
        ("protocol-relative url", "//evil.example", None),
        ("javascript url", "javascript:alert(1)", None),
        ("relative path", "relative/path", None),
        ("leading backslash", "/\\evil.example", None),
        ("tab", "/\t/evil.example", None),
        ("newline", "/\n/evil.example", None),
        ("carriage return and newline", "/\r\n/evil.example", None),
        ("backslash traversal", "/dashboard\\..\\evil", None),
        (
            "encoded backslash",
            "/%5Cevil.example",
            Some("/%5Cevil.example"),
        ),
    ];

    for (case, next_url, expected) in cases {
        assert_eq!(
            sanitize_next_url(Some(next_url)).as_deref(),
            expected,
            "{case}"
        );
    }
}

// Helpers.

/// Client key of the peer that sends log in requests built by `log_in_request`.
const LOG_IN_CLIENT: ClientKey = ClientKey::V4([203, 0, 113, 7]);

/// Account details update route.
const UPDATE_DETAILS_URL: &str = "/dashboard/account/update/details";

/// Account password update route.
const UPDATE_PASSWORD_URL: &str = "/dashboard/account/update/password";

/// Callback authentication double that records the arguments it receives.
#[derive(Default)]
struct MockCallbackAuth {
    login_called: bool,
    login_result: Option<Result<(), HandlerError>>,
    oauth2_call: Option<(String, String, OAuth2Provider)>,
    oauth2_result: Option<Result<Option<auth::User>, String>>,
    oidc_call: Option<(String, String, String, OidcProvider)>,
    oidc_result: Option<Result<Option<auth::User>, String>>,
}

#[async_trait]
impl CallbackAuth for MockCallbackAuth {
    async fn authenticate_oauth2(
        &mut self,
        code: String,
        pkce_verifier: oauth2::PkceCodeVerifier,
        provider: OAuth2Provider,
    ) -> Result<Option<auth::User>, String> {
        self.oauth2_call = Some((code, pkce_verifier.secret().clone(), provider));
        self.oauth2_result
            .take()
            .expect("oauth2 callback auth result should be configured in tests")
    }

    async fn authenticate_oidc(
        &mut self,
        code: String,
        nonce: oidc::Nonce,
        pkce_verifier: oidc::PkceCodeVerifier,
        provider: OidcProvider,
    ) -> Result<Option<auth::User>, String> {
        self.oidc_call = Some((
            code,
            nonce.secret().clone(),
            pkce_verifier.secret().clone(),
            provider,
        ));
        self.oidc_result
            .take()
            .expect("oidc callback auth result should be configured in tests")
    }

    async fn log_in(&mut self, _user: &auth::User) -> Result<(), HandlerError> {
        self.login_called = true;
        self.login_result
            .take()
            .expect("callback login result should be configured in tests")
    }
}

/// Session record without a logged in user holding the given string values.
fn session_record_with_values(session_id: session::Id, values: &[(&str, &str)]) -> session::Record {
    let mut session_record = sample_empty_session_record(session_id);
    for (key, value) in values {
        session_record.data.insert((*key).to_string(), json!(value));
    }
    session_record
}

/// Asserts the menu renders the color theme group with only System checked.
fn assert_theme_group_checks_system(body: &str) {
    let group = element_html_with(body, r#"aria-labelledby="user-menu-theme-label""#);
    assert!(opening_tag_with(group, r#"role="group""#).contains("user-menu-theme-label"));
    assert_eq!(group.matches(r#"role="menuitemradio""#).count(), 3);
    assert_eq!(group.matches(r#"aria-checked="true""#).count(), 1);
    for (value, checked) in [("light", "false"), ("dark", "false"), ("system", "true")] {
        let choice = opening_tag_with(group, &format!(r#"data-ocg-theme-choice="{value}""#));
        assert!(
            choice.contains(&format!(r#"aria-checked="{checked}""#)),
            "{value}"
        );
    }
}

/// Builds an in-memory callback session holding the expected csrf state, flow provider and pkce verifier.
async fn callback_session(
    flow_provider: &str,
    nonce: Option<&str>,
    next_url: Option<&str>,
) -> Session {
    let session = Session::new(None, Arc::new(MemoryStore::default()), None);
    session
        .insert(OAUTH2_CSRF_STATE_KEY, "state-in-session")
        .await
        .unwrap();
    session.insert(OAUTH2_FLOW_PROVIDER_KEY, flow_provider).await.unwrap();
    session
        .insert(OAUTH2_PKCE_VERIFIER_KEY, "verifier-in-session")
        .await
        .unwrap();
    if let Some(nonce) = nonce {
        session.insert(OIDC_NONCE_KEY, nonce).await.unwrap();
    }
    if let Some(next_url) = next_url {
        session
            .insert(NEXT_URL_KEY, Some(next_url.to_string()))
            .await
            .unwrap();
    }
    session
}

/// Returns a slot and an error callback that stores the reported message in it.
fn capture_error() -> (Arc<Mutex<Option<String>>>, impl FnOnce(String)) {
    let error_message = Arc::new(Mutex::new(None));
    let captured_error_message = error_message.clone();
    let on_error = move |message: String| {
        *captured_error_message.lock().unwrap() = Some(message);
    };
    (error_message, on_error)
}

/// Server configuration with email log in enabled.
fn email_login_cfg() -> HttpServerConfig {
    HttpServerConfig {
        base_url: "https://app.example".to_string(),
        login: LoginOptions {
            email: true,
            ..Default::default()
        },
        ..Default::default()
    }
}

/// Expects the session reads and writes of a successful email log in by the user.
fn expect_successful_log_in(db: &mut MockDB, ids: &DashboardIds, user: auth::User) {
    let ids = *ids;
    expect_stored_session(db, sample_empty_session_record(ids.session_id));
    db.expect_get_user_by_username()
        .times(1)
        .withf(move |username| username == "test-user")
        .returning(move |_| Ok(Some(user.clone())));
    db.expect_delete_session()
        .times(1)
        .withf(move |id| *id == ids.session_id)
        .returning(|_| Ok(()));
    db.expect_create_session()
        .times(1)
        .withf(move |record| {
            session_record_contains_auth_provider(record, AUTH_PROVIDER_EMAIL)
                && session_record_contains_selected_group(record, ids.group_id)
        })
        .returning(|_| Ok(()));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &ids.user_id)
        .returning(move |_| {
            Ok(sample_user_groups_by_community(
                ids.community_id,
                ids.group_id,
            ))
        });
}

/// Server configuration with GitHub log in enabled.
fn github_login_cfg() -> HttpServerConfig {
    let mut server_cfg = HttpServerConfig::default();
    server_cfg.login.github = true;
    server_cfg
}

/// Server configuration with Linux Foundation log in enabled.
fn linuxfoundation_login_cfg() -> HttpServerConfig {
    let mut server_cfg = HttpServerConfig::default();
    server_cfg.login.linuxfoundation = true;
    server_cfg
}

/// Rate limiter keyed by the TCP peer that allows one failed log in per client
/// and username per hour, with the default budgets for every other limit.
fn log_in_failures_rate_limiter(mode: RateLimitMode) -> Arc<RateLimiter> {
    sample_rate_limiter(
        RateLimitBudgets {
            log_in_failures: RateLimitBudget {
                burst: 1,
                period_secs: 3600,
            },
            ..RateLimitBudgets::default()
        },
        mode,
    )
}

/// Builds a log in form request with the session cookie, sent from the peer
/// whose client key is `LOG_IN_CLIENT`.
fn log_in_request(session_id: session::Id, body: &'static str) -> Request<Body> {
    let mut request = form_request("POST", LOG_IN_URL, session_id, body);
    request
        .extensions_mut()
        .insert(ConnectInfo(SocketAddr::from(([203, 0, 113, 7], 40_000))));
    request
}

/// Returns the value of the query string parameter.
fn query_param(query: &str, name: &str) -> Option<String> {
    query.split('&').find_map(|pair| {
        pair.strip_prefix(name)
            .and_then(|rest| rest.strip_prefix('='))
            .map(String::from)
    })
}

/// Returns whether the stored session tracks the auth provider.
fn session_record_contains_auth_provider(record: &session::Record, provider: &str) -> bool {
    record.data.get(AUTH_PROVIDER_KEY).and_then(|value| value.as_str()) == Some(provider)
}
