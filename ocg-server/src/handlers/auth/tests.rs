use std::sync::Arc;

use anyhow::anyhow;
use axum::extract::Query;
use axum::{
    Router,
    body::{Body, to_bytes},
    http::{
        HeaderValue, Request, StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE, COOKIE, HOST, LOCATION},
    },
    middleware,
    response::IntoResponse,
    routing::get,
};
use axum_login::tower_sessions::session;
use oauth2::{AuthUrl, ClientId, ClientSecret, RedirectUrl, TokenUrl, basic::BasicClient};
use openidconnect as oidc;
use serde_json::json;
use tower::ServiceExt;
use tower_sessions::{MemoryStore, Session};
use uuid::Uuid;

use crate::{
    auth::{OAuth2ProviderDetails, OidcProviderDetails},
    config::{HttpServerConfig, LoginOptions, OAuth2Provider, OAuth2ProviderConfig},
    db::{DynDB, mock::MockDB},
    handlers::{
        extractors::{OAuth2, Oidc},
        tests::*,
    },
    router::CACHE_CONTROL_NO_CACHE,
    services::{
        images::MockImageStorage,
        notifications::{MockNotificationsManager, NotificationKind},
    },
    templates::notifications::EmailVerification as EmailVerificationTemplate,
};

use super::*;

#[tokio::test]
async fn test_log_in_page_success() {
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
        .uri(LOG_IN_URL)
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8"),
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_NO_CACHE),
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_log_in_page_redirects_when_authenticated() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(LOG_IN_URL)
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static("/"),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_sign_up_page_success() {
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
        .uri(SIGN_UP_URL)
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8"),
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_NO_CACHE),
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_sign_up_page_redirects_when_authenticated() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(SIGN_UP_URL)
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static("/"),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_menu_section_success() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/section/user-menu")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8"),
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_NO_CACHE),
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_dashboard_community_redirects_to_user_invitations_when_context_is_missing_and_unavailable() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_list_user_communities()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(|_| Ok(vec![]));
    db.expect_list_user_groups().times(0);
    db.expect_update_session().times(0);
    db.expect_user_has_community_permission().times(0);

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/community")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_dashboard_group_redirects_to_user_invitations_when_context_is_missing_and_unavailable() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(|_| Ok(vec![]));
    db.expect_update_session().times(0);
    db.expect_user_has_group_permission().times(0);

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_log_in_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let password_hash = password_auth::generate_hash("secret-password");
    let session_record = sample_empty_session_record(session_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_username()
        .times(1)
        .withf(move |username| username == "test-user")
        .returning(move |_| {
            let mut user = sample_auth_user(user_id, &auth_hash);
            user.password = Some(password_hash.clone());
            Ok(Some(user))
        });
    db.expect_delete_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(|_| Ok(()));
    db.expect_create_session()
        .times(1)
        .withf(move |record| session_record_contains_selected_group(record, group_id))
        .returning(|_| Ok(()));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(sample_user_groups_by_community(community_id, group_id)));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router
    let mut server_cfg = HttpServerConfig::default();
    server_cfg.login.email = true;
    let router = TestRouterBuilder::new(db, nm)
        .with_server_cfg(server_cfg)
        .build()
        .await;

    // Setup request
    let request = Request::builder()
        .method("POST")
        .uri("/log-in?next_url=%2Fdashboard")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from("username=test-user&password=secret-password"))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert!(parts.headers.contains_key("set-cookie"));
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static("/dashboard"),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_log_in_invalid_credentials() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let session_record = sample_empty_session_record(session_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
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

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router
    let mut server_cfg = HttpServerConfig::default();
    server_cfg.login.email = true;
    let router = TestRouterBuilder::new(db, nm)
        .with_server_cfg(server_cfg)
        .build()
        .await;

    // Setup request
    let request = Request::builder()
        .method("POST")
        .uri("/log-in")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from("username=test-user&password=wrong"))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static(LOG_IN_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_log_in_validation_error() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let session_record = sample_empty_session_record(session_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_username().times(0);
    db.expect_update_session()
        .times(1)
        .withf(|record| message_matches(record, "username: value cannot be empty or whitespace-only\n"))
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router
    let mut server_cfg = HttpServerConfig::default();
    server_cfg.login.email = true;
    let router = TestRouterBuilder::new(db, nm)
        .with_server_cfg(server_cfg)
        .build()
        .await;

    // Setup request (username is whitespace only - validation should fail)
    let request = Request::builder()
        .method("POST")
        .uri("/log-in")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from("username=+++&password=secret"))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static(LOG_IN_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_log_out_success() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_delete_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(LOG_OUT_URL)
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static(LOG_IN_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_log_out_invalid_session() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(|_| Ok(None));
    db.expect_get_user_by_id().times(0);
    db.expect_delete_session().times(0);

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(LOG_OUT_URL)
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static(LOG_IN_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_oauth2_callback_missing_state() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let session_record = sample_empty_session_record(session_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_update_session()
        .times(1)
        .withf(move |record| message_matches(record, "OAuth2 authorization failed"))
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().times(0);

    // Setup router
    let mut server_cfg = HttpServerConfig::default();
    server_cfg.login.github = true;
    server_cfg.oauth2.insert(
        OAuth2Provider::GitHub,
        OAuth2ProviderConfig {
            auth_url: "https://oauth.example/authorize".to_string(),
            client_id: "client-id".to_string(),
            client_secret: "client-secret".to_string(),
            redirect_uri: "https://app.example/log-in/oauth2/github/callback".to_string(),
            scopes: vec!["read:user".to_string()],
            token_url: "https://oauth.example/token".to_string(),
        },
    );
    let router = TestRouterBuilder::new(db, nm)
        .with_server_cfg(server_cfg)
        .build()
        .await;

    // Setup request
    let request = Request::builder()
        .method("GET")
        .uri("/log-in/oauth2/github/callback?code=test-code&state=test-state")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static(LOG_IN_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_oauth2_callback_state_mismatch() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let mut session_record = sample_empty_session_record(session_id);
    session_record
        .data
        .insert(OAUTH2_CSRF_STATE_KEY.to_string(), json!("state-in-session"));

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_update_session()
        .times(1)
        .withf(move |record| message_matches(record, "OAuth2 authorization failed"))
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().times(0);

    // Setup router
    let mut server_cfg = HttpServerConfig::default();
    server_cfg.login.github = true;
    server_cfg.oauth2.insert(
        OAuth2Provider::GitHub,
        OAuth2ProviderConfig {
            auth_url: "https://oauth.example/authorize".to_string(),
            client_id: "client-id".to_string(),
            client_secret: "client-secret".to_string(),
            redirect_uri: "https://app.example/log-in/oauth2/github/callback".to_string(),
            scopes: vec!["read:user".to_string()],
            token_url: "https://oauth.example/token".to_string(),
        },
    );
    let router = TestRouterBuilder::new(db, nm)
        .with_server_cfg(server_cfg)
        .build()
        .await;

    // Setup request
    let request = Request::builder()
        .method("GET")
        .uri("/log-in/oauth2/github/callback?code=test-code&state=state-in-request")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static(LOG_IN_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_oauth2_callback_authorization_error() {
    // Setup in-memory session
    let store = Arc::new(MemoryStore::default());
    let session = Session::new(None, store, None);
    session
        .insert(OAUTH2_CSRF_STATE_KEY, "state-in-session")
        .await
        .unwrap();
    session
        .insert(NEXT_URL_KEY, Some("/dashboard".to_string()))
        .await
        .unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_list_user_groups().times(0);

    // Setup callback auth mock
    let mut callback_auth = MockCallbackAuth {
        login_called: false,
        login_result: Some(Ok(())),
        oidc_result: None,
        oauth2_result: Some(Err("oauth2 auth error".to_string())),
    };
    let db: DynDB = Arc::new(db);

    // Execute helper
    let error_message = std::sync::Arc::new(std::sync::Mutex::new(None));
    let captured_error_message = error_message.clone();
    let redirect = oauth2_callback_with_auth(
        &mut callback_auth,
        session.clone(),
        &db,
        OAuth2Provider::GitHub,
        "test-code".to_string(),
        oauth2::CsrfToken::new("state-in-session".to_string()),
        move |message| {
            let mut guard = captured_error_message.lock().unwrap();
            *guard = Some(message);
        },
    )
    .await
    .unwrap();

    // Check callback result and side effects
    let response = redirect.into_response();
    let selected_community_id: Option<Uuid> = session.get(SELECTED_COMMUNITY_ID_KEY).await.unwrap();
    let selected_group_id: Option<Uuid> = session.get(SELECTED_GROUP_ID_KEY).await.unwrap();
    assert_eq!(response.status(), StatusCode::SEE_OTHER);
    assert_eq!(
        response.headers().get(LOCATION).unwrap(),
        &HeaderValue::from_static("/log-in?next_url=%2Fdashboard"),
    );
    assert_eq!(
        *error_message.lock().unwrap(),
        Some("OAuth2 authorization failed: oauth2 auth error".to_string()),
    );
    assert!(!callback_auth.login_called);
    assert_eq!(selected_community_id, None);
    assert_eq!(selected_group_id, None);
}

#[tokio::test]
async fn test_oauth2_callback_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let groups = sample_user_groups_by_community(community_id, group_id);

    // Setup in-memory session
    let store = Arc::new(MemoryStore::default());
    let session = Session::new(None, store, None);
    session
        .insert(OAUTH2_CSRF_STATE_KEY, "state-in-session")
        .await
        .unwrap();
    session
        .insert(NEXT_URL_KEY, Some("/dashboard".to_string()))
        .await
        .unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(groups.clone()));

    // Setup callback auth mock
    let mut callback_auth = MockCallbackAuth {
        login_called: false,
        login_result: Some(Ok(())),
        oidc_result: None,
        oauth2_result: Some(Ok(Some(sample_auth_user(user_id, &auth_hash)))),
    };
    let db: DynDB = Arc::new(db);

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

    // Check callback result and side effects
    let response = redirect.into_response();
    let selected_community_id: Option<Uuid> = session.get(SELECTED_COMMUNITY_ID_KEY).await.unwrap();
    let selected_group_id: Option<Uuid> = session.get(SELECTED_GROUP_ID_KEY).await.unwrap();
    assert_eq!(response.status(), StatusCode::SEE_OTHER);
    assert_eq!(
        response.headers().get(LOCATION).unwrap(),
        &HeaderValue::from_static("/dashboard"),
    );
    assert!(callback_auth.login_called);
    assert_eq!(selected_community_id, Some(community_id));
    assert_eq!(selected_group_id, Some(group_id));
}

#[tokio::test]
async fn test_oauth2_callback_returns_error_when_provider_is_not_configured() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let mut session_record = sample_empty_session_record(session_id);
    session_record
        .data
        .insert(OAUTH2_CSRF_STATE_KEY.to_string(), json!("state-in-session"));
    session_record
        .data
        .insert(NEXT_URL_KEY.to_string(), json!("/dashboard"));

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            message_matches(record, "OAuth2 authorization failed: oauth2 provider not found")
        })
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().times(0);

    // Setup router
    let mut server_cfg = HttpServerConfig::default();
    server_cfg.login.github = true;
    let router = TestRouterBuilder::new(db, nm)
        .with_server_cfg(server_cfg)
        .build()
        .await;

    // Setup request
    let request = Request::builder()
        .method("GET")
        .uri("/log-in/oauth2/github/callback?code=test-code&state=state-in-session")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static("/log-in?next_url=%2Fdashboard"),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_oauth2_redirect_success() {
    // Setup session and form input
    let store = Arc::new(MemoryStore::default());
    let session = Session::new(None, store, None);
    let query = Query(NextUrl {
        next_url: Some("/dashboard".to_string()),
    });

    // Setup oauth2 provider details
    let client = BasicClient::new(ClientId::new("client-id".to_string()))
        .set_client_secret(ClientSecret::new("client-secret".to_string()))
        .set_auth_uri(AuthUrl::new("https://oauth.example/authorize".to_string()).unwrap())
        .set_token_uri(TokenUrl::new("https://oauth.example/token".to_string()).unwrap())
        .set_redirect_uri(
            RedirectUrl::new("https://app.example/log-in/oauth2/github/callback".to_string()).unwrap(),
        );
    let provider = OAuth2ProviderDetails {
        client,
        scopes: vec!["read:user".to_string()],
    };

    // Execute handler
    let response = oauth2_redirect(session.clone(), OAuth2(Arc::new(provider)), query)
        .await
        .expect("oauth2 redirect should succeed")
        .into_response();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let location = parts.headers.get(LOCATION).unwrap().to_str().unwrap();
    let (base_url, query) = location
        .split_once('?')
        .expect("redirect url to contain query string");

    // Check response matches expectations
    let csrf_state: Option<String> = session.get(OAUTH2_CSRF_STATE_KEY).await.unwrap();
    let next_url: Option<Option<String>> = session.get(NEXT_URL_KEY).await.unwrap();
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(base_url, "https://oauth.example/authorize");
    assert_eq!(
        csrf_state.as_deref(),
        query
            .split('&')
            .find_map(|pair| pair.strip_prefix("state=").map(String::from))
            .as_deref(),
    );
    assert_eq!(next_url, Some(Some("/dashboard".to_string())));
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_oidc_callback_missing_nonce() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let mut session_record = sample_empty_session_record(session_id);
    session_record
        .data
        .insert(OAUTH2_CSRF_STATE_KEY.to_string(), json!("state-in-session"));

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_update_session()
        .times(1)
        .withf(move |record| message_matches(record, "OpenID Connect authorization failed"))
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().times(0);

    // Setup router
    let mut server_cfg = HttpServerConfig::default();
    server_cfg.login.linuxfoundation = true;
    let router = TestRouterBuilder::new(db, nm)
        .with_server_cfg(server_cfg)
        .build()
        .await;

    // Setup request
    let request = Request::builder()
        .method("GET")
        .uri("/log-in/oidc/linuxfoundation/callback?code=test-code&state=state-in-session")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static(LOG_IN_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_oidc_callback_missing_state() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let session_record = sample_empty_session_record(session_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_update_session()
        .times(1)
        .withf(move |record| message_matches(record, "OpenID Connect authorization failed"))
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().times(0);

    // Setup router
    let mut server_cfg = HttpServerConfig::default();
    server_cfg.login.linuxfoundation = true;
    let router = TestRouterBuilder::new(db, nm)
        .with_server_cfg(server_cfg)
        .build()
        .await;

    // Setup request
    let request = Request::builder()
        .method("GET")
        .uri("/log-in/oidc/linuxfoundation/callback?code=test-code&state=test-state")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static(LOG_IN_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_oidc_callback_state_mismatch() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let mut session_record = sample_empty_session_record(session_id);
    session_record
        .data
        .insert(OAUTH2_CSRF_STATE_KEY.to_string(), json!("state-in-session"));
    session_record
        .data
        .insert(OIDC_NONCE_KEY.to_string(), json!("nonce-in-session"));

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_update_session()
        .times(1)
        .withf(move |record| message_matches(record, "OpenID Connect authorization failed"))
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().times(0);

    // Setup router
    let mut server_cfg = HttpServerConfig::default();
    server_cfg.login.linuxfoundation = true;
    let router = TestRouterBuilder::new(db, nm)
        .with_server_cfg(server_cfg)
        .build()
        .await;

    // Setup request
    let request = Request::builder()
        .method("GET")
        .uri("/log-in/oidc/linuxfoundation/callback?code=test-code&state=state-in-request")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static(LOG_IN_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_oidc_callback_authorization_error() {
    // Setup in-memory session
    let store = Arc::new(MemoryStore::default());
    let session = Session::new(None, store, None);
    session
        .insert(OAUTH2_CSRF_STATE_KEY, "state-in-session")
        .await
        .unwrap();
    session.insert(OIDC_NONCE_KEY, "nonce-in-session").await.unwrap();
    session
        .insert(NEXT_URL_KEY, Some("/dashboard".to_string()))
        .await
        .unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_list_user_groups().times(0);

    // Setup callback auth mock
    let mut callback_auth = MockCallbackAuth {
        login_called: false,
        login_result: Some(Ok(())),
        oidc_result: Some(Err("oidc auth error".to_string())),
        oauth2_result: None,
    };
    let db: DynDB = Arc::new(db);

    // Execute helper
    let error_message = std::sync::Arc::new(std::sync::Mutex::new(None));
    let captured_error_message = error_message.clone();
    let redirect = oidc_callback_with_auth(
        &mut callback_auth,
        session.clone(),
        &db,
        OidcProvider::LinuxFoundation,
        "test-code".to_string(),
        oauth2::CsrfToken::new("state-in-session".to_string()),
        move |message| {
            let mut guard = captured_error_message.lock().unwrap();
            *guard = Some(message);
        },
    )
    .await
    .unwrap();

    // Check callback result and side effects
    let response = redirect.into_response();
    let auth_provider: Option<OidcProvider> = session.get(AUTH_PROVIDER_KEY).await.unwrap();
    let selected_community_id: Option<Uuid> = session.get(SELECTED_COMMUNITY_ID_KEY).await.unwrap();
    let selected_group_id: Option<Uuid> = session.get(SELECTED_GROUP_ID_KEY).await.unwrap();
    assert_eq!(response.status(), StatusCode::SEE_OTHER);
    assert_eq!(
        response.headers().get(LOCATION).unwrap(),
        &HeaderValue::from_static("/log-in?next_url=%2Fdashboard"),
    );
    assert_eq!(
        *error_message.lock().unwrap(),
        Some("OpenID Connect authorization failed: oidc auth error".to_string()),
    );
    assert!(!callback_auth.login_called);
    assert_eq!(auth_provider, None);
    assert_eq!(selected_community_id, None);
    assert_eq!(selected_group_id, None);
}

#[tokio::test]
async fn test_oidc_callback_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let groups = sample_user_groups_by_community(community_id, group_id);

    // Setup in-memory session
    let store = Arc::new(MemoryStore::default());
    let session = Session::new(None, store, None);
    session
        .insert(OAUTH2_CSRF_STATE_KEY, "state-in-session")
        .await
        .unwrap();
    session.insert(OIDC_NONCE_KEY, "nonce-in-session").await.unwrap();
    session
        .insert(NEXT_URL_KEY, Some("/dashboard".to_string()))
        .await
        .unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(groups.clone()));

    // Setup callback auth mock
    let mut callback_auth = MockCallbackAuth {
        login_called: false,
        login_result: Some(Ok(())),
        oidc_result: Some(Ok(Some(sample_auth_user(user_id, &auth_hash)))),
        oauth2_result: None,
    };
    let db: DynDB = Arc::new(db);

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

    // Check callback result and side effects
    let response = redirect.into_response();
    let auth_provider: Option<OidcProvider> = session.get(AUTH_PROVIDER_KEY).await.unwrap();
    let selected_community_id: Option<Uuid> = session.get(SELECTED_COMMUNITY_ID_KEY).await.unwrap();
    let selected_group_id: Option<Uuid> = session.get(SELECTED_GROUP_ID_KEY).await.unwrap();
    assert_eq!(response.status(), StatusCode::SEE_OTHER);
    assert_eq!(
        response.headers().get(LOCATION).unwrap(),
        &HeaderValue::from_static("/dashboard"),
    );
    assert!(callback_auth.login_called);
    assert_eq!(auth_provider, Some(OidcProvider::LinuxFoundation));
    assert_eq!(selected_community_id, Some(community_id));
    assert_eq!(selected_group_id, Some(group_id));
}

#[tokio::test]
async fn test_oidc_callback_returns_error_when_provider_is_not_configured() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let mut session_record = sample_empty_session_record(session_id);
    session_record
        .data
        .insert(OAUTH2_CSRF_STATE_KEY.to_string(), json!("state-in-session"));
    session_record
        .data
        .insert(OIDC_NONCE_KEY.to_string(), json!("nonce-in-session"));
    session_record
        .data
        .insert(NEXT_URL_KEY.to_string(), json!("/dashboard"));

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            message_matches(
                record,
                "OpenID Connect authorization failed: oidc provider not found",
            )
        })
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().times(0);

    // Setup router
    let mut server_cfg = HttpServerConfig::default();
    server_cfg.login.linuxfoundation = true;
    let router = TestRouterBuilder::new(db, nm)
        .with_server_cfg(server_cfg)
        .build()
        .await;

    // Setup request
    let request = Request::builder()
        .method("GET")
        .uri("/log-in/oidc/linuxfoundation/callback?code=test-code&state=state-in-session")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static("/log-in?next_url=%2Fdashboard"),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_oidc_redirect_success() {
    // Setup session and form input
    let store = Arc::new(MemoryStore::default());
    let session = Session::new(None, store, None);
    let query = Query(NextUrl {
        next_url: Some("/dashboard".to_string()),
    });

    // Setup oidc provider details
    let metadata = oidc::core::CoreProviderMetadata::new(
        oidc::IssuerUrl::new("https://issuer.example".to_string()).unwrap(),
        oidc::AuthUrl::new("https://issuer.example/authorize".to_string()).unwrap(),
        oidc::JsonWebKeySetUrl::new("https://issuer.example/jwks".to_string()).unwrap(),
        vec![oidc::ResponseTypes::new(vec![oidc::core::CoreResponseType::Code])],
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
        oidc::RedirectUrl::new("https://app.example/log-in/oidc/provider/callback".to_string()).unwrap(),
    );
    let provider = OidcProviderDetails {
        client,
        scopes: vec!["openid".to_string()],
    };

    // Execute handler
    let response = oidc_redirect(session.clone(), Oidc(Arc::new(provider)), query)
        .await
        .expect("oidc redirect should succeed")
        .into_response();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let location = parts.headers.get(LOCATION).unwrap().to_str().unwrap();
    let (base_url, query) = location
        .split_once('?')
        .expect("redirect url to contain query string");

    // Check response matches expectations
    let csrf_state: Option<String> = session.get(OAUTH2_CSRF_STATE_KEY).await.unwrap();
    let nonce: Option<String> = session.get(OIDC_NONCE_KEY).await.unwrap();
    let next_url: Option<Option<String>> = session.get(NEXT_URL_KEY).await.unwrap();
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(base_url, "https://issuer.example/authorize");
    assert_eq!(
        csrf_state.as_deref(),
        query
            .split('&')
            .find_map(|pair| pair.strip_prefix("state=").map(String::from))
            .as_deref(),
    );
    assert_eq!(
        nonce.as_deref(),
        query
            .split('&')
            .find_map(|pair| pair.strip_prefix("nonce=").map(String::from))
            .as_deref(),
    );
    assert_eq!(next_url, Some(Some("/dashboard".to_string())));
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_sign_up_success() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let session_record = sample_empty_session_record(session_id);
    let email_verification_code = Uuid::new_v4();
    let user = sample_auth_user(Uuid::new_v4(), "hash");
    let user_for_notifications = user.clone();
    let user_for_db = user;

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    let site_settings = sample_site_settings();
    let site_settings_for_notifications = site_settings.clone();
    db.expect_sign_up_user()
        .times(1)
        .withf(move |summary, verify| {
            !matches!(summary.password.as_deref(), Some("secret-password")) && !verify
        })
        .returning({
            let user = user_for_db;
            move |_, _| Ok((user.clone(), Some(email_verification_code)))
        });
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
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
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(&notification.kind, NotificationKind::EmailVerification)
                && notification.recipients == vec![user_for_notifications.user_id]
                && notification.template_data.as_ref().is_some_and(|value| {
                    serde_json::from_value::<EmailVerificationTemplate>(value.clone()).is_ok_and(|template| {
                        template.link == format!("https://app.example/verify-email/{email_verification_code}")
                            && template.theme.primary_color
                                == site_settings_for_notifications.theme.primary_color
                    })
                })
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router
    let server_cfg = HttpServerConfig {
        base_url: "https://app.example".to_string(),
        login: LoginOptions {
            email: true,
            ..Default::default()
        },
        ..Default::default()
    };
    let router = TestRouterBuilder::new(db, nm)
        .with_server_cfg(server_cfg)
        .build()
        .await;

    // Setup request
    let form = "email=test%40example.test&name=Test+User&username=test-user&password=secret-password";
    let request = Request::builder()
        .method("POST")
        .uri("/sign-up?next_url=%2Fwelcome")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(form))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static("/log-in?next_url=%2Fwelcome"),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_sign_up_missing_password() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let session_record = sample_empty_session_record(session_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_sign_up_user().times(0);

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().times(0);

    // Setup router
    let mut server_cfg = HttpServerConfig::default();
    server_cfg.login.email = true;
    let router = TestRouterBuilder::new(db, nm)
        .with_server_cfg(server_cfg)
        .build()
        .await;

    // Setup request (password not provided)
    let form = "email=test%40example.test&name=Test+User&username=test-user";
    let request = Request::builder()
        .method("POST")
        .uri("/sign-up")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(form))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(bytes, "password not provided");
}

#[tokio::test]
async fn test_sign_up_db_error() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let session_record = sample_empty_session_record(session_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_sign_up_user()
        .times(1)
        .returning(|_, _| Err(anyhow!("db error")));
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

    // Setup router
    let mut server_cfg = HttpServerConfig::default();
    server_cfg.login.email = true;
    let router = TestRouterBuilder::new(db, nm)
        .with_server_cfg(server_cfg)
        .build()
        .await;

    // Setup request
    let form = "email=test%40example.test&name=Test+User&username=test-user&password=secretpw";
    let request = Request::builder()
        .method("POST")
        .uri("/sign-up")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(form))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static(SIGN_UP_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_sign_up_validation_error() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let session_record = sample_empty_session_record(session_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
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

    // Setup router
    let mut server_cfg = HttpServerConfig::default();
    server_cfg.login.email = true;
    let router = TestRouterBuilder::new(db, nm)
        .with_server_cfg(server_cfg)
        .build()
        .await;

    // Setup request (invalid email - validation should fail)
    let form = "email=invalid-email&name=Test+User&username=test-user&password=secret";
    let request = Request::builder()
        .method("POST")
        .uri("/sign-up")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(form))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static(SIGN_UP_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_update_user_details_success() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_update_user_details()
        .times(1)
        .withf(move |uid, details| {
            *uid == user_id && details.mass_notifications_enabled && details.name == "Updated User"
        })
        .returning(|_, _| Ok(()));
    db.expect_update_session()
        .times(1)
        .withf(move |record| message_matches(record, "User details updated successfully."))
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri("/dashboard/account/update/details")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(
            "name=Updated+User&company=Example&mass_notifications_enabled=true",
        ))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get("HX-Trigger").unwrap(),
        &HeaderValue::from_static("refresh-body"),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_update_user_details_invalid_body() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_update_user_details().times(0);

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri("/dashboard/account/update/details")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::from("invalid"))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_update_user_details_returns_error_on_db_failure() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_update_user_details()
        .times(1)
        .withf(move |uid, details| {
            *uid == user_id && !details.mass_notifications_enabled && details.name == "Updated User"
        })
        .returning(|_, _| Err(anyhow!("db error")));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri("/dashboard/account/update/details")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(
            "name=Updated+User&company=Example&mass_notifications_enabled=false",
        ))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_update_user_password_success() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let existing_password_hash = password_auth::generate_hash("current-password");

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_get_user_password()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(existing_password_hash.clone())));
    db.expect_update_user_password()
        .times(1)
        .withf(move |uid, new_password| *uid == user_id && new_password != "new-password")
        .returning(|_, _| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let form = "old_password=current-password&new_password=new-password";
    let request = Request::builder()
        .method("PUT")
        .uri("/dashboard/account/update/password")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(form))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert!(bytes.is_empty());
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static(LOG_OUT_URL),
    );
}

#[tokio::test]
async fn test_update_user_password_wrong_old_password() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let existing_password_hash = password_auth::generate_hash("current-password");

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_get_user_password()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(existing_password_hash.clone())));
    db.expect_update_user_password().times(0);

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let form = "old_password=wrong-password&new_password=new-password";
    let request = Request::builder()
        .method("PUT")
        .uri("/dashboard/account/update/password")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(form))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::FORBIDDEN);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_update_user_password_returns_bad_request_when_hash_is_missing() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_get_user_password()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(|_| Ok(None));
    db.expect_update_user_password().times(0);

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let form = "old_password=current-password&new_password=new-password";
    let request = Request::builder()
        .method("PUT")
        .uri("/dashboard/account/update/password")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(form))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_update_user_password_returns_error_on_db_failure() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let existing_password_hash = password_auth::generate_hash("current-password");

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_get_user_password()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(existing_password_hash.clone())));
    db.expect_update_user_password()
        .times(1)
        .withf(move |uid, new_password| *uid == user_id && new_password != "new-password")
        .returning(|_, _| Err(anyhow!("db error")));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let form = "old_password=current-password&new_password=new-password";
    let request = Request::builder()
        .method("PUT")
        .uri("/dashboard/account/update/password")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(form))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_verify_email_success() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let session_record = sample_empty_session_record(session_id);
    let verification_code = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
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

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let mut server_cfg = HttpServerConfig::default();
    server_cfg.login.email = true;
    let router = TestRouterBuilder::new(db, nm)
        .with_server_cfg(server_cfg)
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/verify-email/{verification_code}"))
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert!(bytes.is_empty());
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static(LOG_IN_URL),
    );
}

#[tokio::test]
async fn test_verify_email_failure() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let session_record = sample_empty_session_record(session_id);
    let verification_code = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
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

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let mut server_cfg = HttpServerConfig::default();
    server_cfg.login.email = true;
    let router = TestRouterBuilder::new(db, nm)
        .with_server_cfg(server_cfg)
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/verify-email/{verification_code}"))
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert!(bytes.is_empty());
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static(LOG_IN_URL),
    );
}

#[tokio::test]
async fn test_select_first_community_and_group_selects_community_when_user_has_no_groups() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(|_| Ok(vec![]));
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(vec![sample_community_summary(community_id)]));

    // Setup in-memory session
    let db: DynDB = Arc::new(db);
    let store = Arc::new(MemoryStore::default());
    let session = Session::new(None, store, None);

    // Execute helper
    select_first_community_and_group(&db, &session, &user_id)
        .await
        .expect("helper should select first available community");

    // Check session data matches expectations
    let selected_community_id: Option<Uuid> = session.get(SELECTED_COMMUNITY_ID_KEY).await.unwrap();
    let selected_group_id: Option<Uuid> = session.get(SELECTED_GROUP_ID_KEY).await.unwrap();
    assert_eq!(selected_community_id, Some(community_id));
    assert_eq!(selected_group_id, None);
}

#[test]
fn test_get_log_in_url_without_next() {
    let url = get_log_in_url(None);
    assert_eq!(url, LOG_IN_URL);
}

#[test]
fn test_get_log_in_url_with_next() {
    let url = get_log_in_url(Some("/dashboard"));
    assert_eq!(url, "/log-in?next_url=%2Fdashboard");
}

#[test]
fn test_sanitize_next_url_accepts_internal_paths() {
    assert_eq!(
        sanitize_next_url(Some("/dashboard")),
        Some("/dashboard".to_string())
    );
    assert_eq!(
        sanitize_next_url(Some("/groups?page=2#section")),
        Some("/groups?page=2#section".to_string())
    );
    assert_eq!(
        sanitize_next_url(Some("   /profile  ")),
        Some("/profile".to_string())
    );
}

#[test]
fn test_sanitize_next_url_rejects_external_paths() {
    assert_eq!(sanitize_next_url(Some("")), None);
    assert_eq!(sanitize_next_url(Some("https://evil.example")), None);
    assert_eq!(sanitize_next_url(Some("//evil.example")), None);
    assert_eq!(sanitize_next_url(Some("javascript:alert(1)")), None);
    assert_eq!(sanitize_next_url(Some("relative/path")), None);
}

#[tokio::test]
async fn test_user_has_community_dashboard_permission_allows_request() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id && *uid == user_id && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_list_user_communities().times(0);
    db.expect_list_user_groups().times(0);
    db.expect_update_session().times(0);

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            db.clone(),
            user_has_community_dashboard_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_community_dashboard_permission_returns_error_on_db_failure() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id && *uid == user_id && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Err(anyhow!("db error")));
    db.expect_list_user_communities().times(0);
    db.expect_list_user_groups().times(0);
    db.expect_update_session().times(0);

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            db.clone(),
            user_has_community_dashboard_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_community_dashboard_permission_redirects_when_context_is_missing_and_unavailable() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_community_permission().times(0);
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(|_| Ok(vec![]));
    db.expect_list_user_groups().times(0);
    db.expect_update_session().times(0);

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            db.clone(),
            user_has_community_dashboard_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_community_dashboard_permission_repairs_missing_context() {
    // Setup identifiers and data structures
    let accessible_community_id = Uuid::new_v4();
    let accessible_group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let groups = sample_user_groups_by_community(accessible_community_id, accessible_group_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(vec![sample_community_summary(accessible_community_id)]));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == accessible_community_id && *uid == user_id && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == session_id
                && record
                    .data
                    .get(SELECTED_COMMUNITY_ID_KEY)
                    .is_some_and(|value| value == &json!(accessible_community_id))
                && record
                    .data
                    .get(SELECTED_GROUP_ID_KEY)
                    .is_some_and(|value| value == &json!(accessible_group_id))
        })
        .returning(|_| Ok(()));

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            db.clone(),
            user_has_community_dashboard_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_community_dashboard_permission_logs_out_when_selected_community_is_stale() {
    // Setup identifiers and data structures
    let inaccessible_community_id = Uuid::new_v4();
    let stale_group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(inaccessible_community_id),
        Some(stale_group_id),
    );
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == inaccessible_community_id && *uid == user_id && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(false));
    db.expect_list_user_communities().times(0);
    db.expect_list_user_groups().times(0);
    db.expect_update_session().times(0);
    db.expect_delete_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(|_| Ok(()));

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            db.clone(),
            user_has_community_dashboard_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static(LOG_IN_URL)
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_community_dashboard_permission_hx_redirects_when_selected_context_is_stale() {
    // Setup identifiers and data structures
    let inaccessible_community_id = Uuid::new_v4();
    let stale_group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(inaccessible_community_id),
        Some(stale_group_id),
    );

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == inaccessible_community_id && *uid == user_id && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(false));
    db.expect_list_user_communities().times(0);
    db.expect_list_user_groups().times(0);
    db.expect_update_session().times(0);
    db.expect_delete_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(|_| Ok(()));

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            db.clone(),
            user_has_community_dashboard_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header("HX-Request", "true")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get("HX-Redirect").unwrap(),
        &HeaderValue::from_static(LOG_IN_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_community_dashboard_permission_fetch_redirects_when_selected_context_is_stale() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let stale_group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(stale_group_id),
    );

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id && *uid == user_id && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(false));
    db.expect_list_user_communities().times(0);
    db.expect_list_user_groups().times(0);
    db.expect_update_session().times(0);
    db.expect_delete_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(|_| Ok(()));

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            db.clone(),
            user_has_community_dashboard_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header("X-OCG-Fetch", "true")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNAUTHORIZED);
    assert_eq!(
        parts.headers.get("X-OCG-Redirect").unwrap(),
        &HeaderValue::from_static(LOG_IN_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_path_community_permission_select_route_allows_request() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id && *uid == user_id && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(true));

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/{community_id}/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), CommunityPermission::Read),
            user_has_path_community_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri(format!("/{community_id}/protected"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_path_community_permission_select_route_forbidden_without_permission() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id && *uid == user_id && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(false));

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/{community_id}/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), CommunityPermission::Read),
            user_has_path_community_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri(format!("/{community_id}/protected"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::FORBIDDEN);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_path_community_permission_select_route_returns_error_on_db_failure() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id && *uid == user_id && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Err(anyhow!("db error")));

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/{community_id}/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), CommunityPermission::Read),
            user_has_path_community_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri(format!("/{community_id}/protected"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_path_community_permission_allows_request() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id && *uid == user_id && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(true));

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route(
            "/community/{community_id}/select",
            get(|| async { StatusCode::OK }),
        )
        .layer(middleware::from_fn_with_state(
            (db.clone(), CommunityPermission::Read),
            user_has_path_community_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri(format!("/community/{community_id}/select"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_path_community_permission_forbidden_without_permission() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id && *uid == user_id && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(false));

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route(
            "/community/{community_id}/select",
            get(|| async { StatusCode::OK }),
        )
        .layer(middleware::from_fn_with_state(
            (db.clone(), CommunityPermission::Read),
            user_has_path_community_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri(format!("/community/{community_id}/select"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::FORBIDDEN);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_path_community_permission_returns_error_on_db_failure() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id && *uid == user_id && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Err(anyhow!("db error")));

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route(
            "/community/{community_id}/select",
            get(|| async { StatusCode::OK }),
        )
        .layer(middleware::from_fn_with_state(
            (db.clone(), CommunityPermission::Read),
            user_has_path_community_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri(format!("/community/{community_id}/select"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_path_community_permission_select_route_forbidden_when_not_logged_in() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let session_record = sample_empty_session_record(session_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id().times(0);
    db.expect_user_has_community_permission().times(0);

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route(
            "/community/{community_id}/select",
            get(|| async { StatusCode::OK }),
        )
        .layer(middleware::from_fn_with_state(
            (db.clone(), CommunityPermission::Read),
            user_has_path_community_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri(format!("/community/{community_id}/select"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::FORBIDDEN);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_path_community_permission_protected_route_forbidden_when_not_logged_in() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let session_record = sample_empty_session_record(session_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id().times(0);
    db.expect_user_has_community_permission().times(0);

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/{community_id}/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), CommunityPermission::Read),
            user_has_path_community_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri(format!("/{community_id}/protected"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::FORBIDDEN);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_path_group_permission_allows_request() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, _permission| *cid == community_id && *gid == group_id && *uid == user_id)
        .returning(|_, _, _, _| Ok(true));

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/groups/{group_id}", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), GroupPermission::Read),
            user_has_path_group_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri(format!("/groups/{group_id}"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_path_group_permission_forbidden_without_permission() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, _permission| *cid == community_id && *gid == group_id && *uid == user_id)
        .returning(|_, _, _, _| Ok(false));

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/groups/{group_id}", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), GroupPermission::Read),
            user_has_path_group_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri(format!("/groups/{group_id}"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::FORBIDDEN);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_path_group_permission_returns_error_on_db_failure() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, _permission| *cid == community_id && *gid == group_id && *uid == user_id)
        .returning(|_, _, _, _| Err(anyhow!("db error")));

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/groups/{group_id}", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), GroupPermission::Read),
            user_has_path_group_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri(format!("/groups/{group_id}"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_path_group_permission_redirects_when_selected_community_is_missing() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_group_permission().times(0);

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/groups/{group_id}", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), GroupPermission::Read),
            user_has_path_group_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri(format!("/groups/{group_id}"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_path_group_permission_forbidden_when_not_logged_in() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let mut session_record = sample_empty_session_record(session_id);
    session_record
        .data
        .insert(SELECTED_COMMUNITY_ID_KEY.to_string(), json!(community_id));

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id().times(0);
    db.expect_user_has_group_permission().times(0);

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/groups/{group_id}", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), GroupPermission::Read),
            user_has_path_group_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri(format!("/groups/{group_id}"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::FORBIDDEN);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_selected_community_permission_allows_request() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id && *uid == user_id && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(true));

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), CommunityPermission::Read),
            user_has_selected_community_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_selected_community_permission_forbidden_without_permission() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_community_permission()
        .times(2)
        .withf(move |cid, uid, permission| {
            *cid == community_id
                && *uid == user_id
                && matches!(
                    permission,
                    CommunityPermission::Read | CommunityPermission::TeamWrite
                )
        })
        .returning(|_, _, permission| Ok(permission == CommunityPermission::Read));
    db.expect_delete_session().times(0);

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), CommunityPermission::TeamWrite),
            user_has_selected_community_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::FORBIDDEN);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_selected_community_permission_returns_error_on_db_failure() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id && *uid == user_id && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Err(anyhow!("db error")));

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), CommunityPermission::Read),
            user_has_selected_community_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_selected_community_permission_redirects_when_context_is_missing_and_unavailable() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(|_| Ok(vec![]));
    db.expect_list_user_groups().times(0);
    db.expect_update_session().times(0);
    db.expect_user_has_community_permission().times(0);

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), CommunityPermission::Read),
            user_has_selected_community_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_selected_community_permission_repairs_missing_context() {
    // Setup identifiers and data structures
    let accessible_community_id = Uuid::new_v4();
    let accessible_group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let groups = sample_user_groups_by_community(accessible_community_id, accessible_group_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(vec![sample_community_summary(accessible_community_id)]));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == accessible_community_id && *uid == user_id && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == session_id
                && record
                    .data
                    .get(SELECTED_COMMUNITY_ID_KEY)
                    .is_some_and(|value| value == &json!(accessible_community_id))
                && record
                    .data
                    .get(SELECTED_GROUP_ID_KEY)
                    .is_some_and(|value| value == &json!(accessible_group_id))
        })
        .returning(|_| Ok(()));

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), CommunityPermission::Read),
            user_has_selected_community_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_selected_community_permission_forbidden_when_not_logged_in() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let mut session_record = sample_empty_session_record(session_id);
    session_record
        .data
        .insert(SELECTED_COMMUNITY_ID_KEY.to_string(), json!(community_id));

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id().times(0);
    db.expect_user_has_community_permission().times(0);

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), CommunityPermission::Read),
            user_has_selected_community_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::FORBIDDEN);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_selected_group_permission_allows_request() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, _permission| *cid == community_id && *gid == group_id && *uid == user_id)
        .returning(|_, _, _, _| Ok(true));

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), GroupPermission::Read),
            user_has_selected_group_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_selected_group_permission_forbidden_without_permission() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_group_permission()
        .times(2)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && matches!(permission, GroupPermission::Read | GroupPermission::TeamWrite)
        })
        .returning(|_, _, _, permission| Ok(permission == GroupPermission::Read));
    db.expect_delete_session().times(0);

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), GroupPermission::TeamWrite),
            user_has_selected_group_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::FORBIDDEN);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_selected_group_permission_logs_out_when_selected_group_is_stale() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let stale_group_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(stale_group_id),
    );

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == stale_group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_list_user_groups().times(0);
    db.expect_update_session().times(0);
    db.expect_delete_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(|_| Ok(()));

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), GroupPermission::Read),
            user_has_selected_group_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static(LOG_IN_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_selected_group_permission_hx_redirects_when_selected_group_is_stale() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let stale_group_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(stale_group_id),
    );

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == stale_group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_list_user_groups().times(0);
    db.expect_update_session().times(0);
    db.expect_delete_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(|_| Ok(()));

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), GroupPermission::Read),
            user_has_selected_group_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header("HX-Request", "true")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get("HX-Redirect").unwrap(),
        &HeaderValue::from_static(LOG_IN_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_selected_group_permission_fetch_redirects_when_selected_group_is_stale() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let stale_group_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(stale_group_id),
    );

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == stale_group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_list_user_groups().times(0);
    db.expect_update_session().times(0);
    db.expect_delete_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(|_| Ok(()));

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), GroupPermission::Read),
            user_has_selected_group_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header("X-OCG-Fetch", "true")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNAUTHORIZED);
    assert_eq!(
        parts.headers.get("X-OCG-Redirect").unwrap(),
        &HeaderValue::from_static(LOG_IN_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_selected_group_permission_returns_error_on_db_failure() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, _permission| *cid == community_id && *gid == group_id && *uid == user_id)
        .returning(|_, _, _, _| Err(anyhow!("db error")));

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), GroupPermission::Read),
            user_has_selected_group_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_selected_group_permission_redirects_when_context_is_missing_and_unavailable() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(|_| Ok(vec![]));
    db.expect_update_session().times(0);
    db.expect_user_has_group_permission().times(0);

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), GroupPermission::Read),
            user_has_selected_group_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_selected_group_permission_repairs_missing_context() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let groups = sample_user_groups_by_community(community_id, group_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id && *gid == group_id && *uid == user_id && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == session_id
                && record
                    .data
                    .get(SELECTED_COMMUNITY_ID_KEY)
                    .is_some_and(|value| value == &json!(community_id))
                && record
                    .data
                    .get(SELECTED_GROUP_ID_KEY)
                    .is_some_and(|value| value == &json!(group_id))
        })
        .returning(|_| Ok(()));

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), GroupPermission::Read),
            user_has_selected_group_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_selected_group_permission_forbidden_when_not_logged_in() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let mut session_record = sample_empty_session_record(session_id);
    session_record
        .data
        .insert(SELECTED_COMMUNITY_ID_KEY.to_string(), json!(community_id));
    session_record
        .data
        .insert(SELECTED_GROUP_ID_KEY.to_string(), json!(group_id));

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id().times(0);
    db.expect_user_has_group_permission().times(0);

    // Setup router
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
    let router = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), GroupPermission::Read),
            user_has_selected_group_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute request
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::FORBIDDEN);
    assert!(bytes.is_empty());
}

// Helpers.

struct MockCallbackAuth {
    login_called: bool,
    login_result: Option<Result<(), HandlerError>>,
    oidc_result: Option<Result<Option<auth::User>, String>>,
    oauth2_result: Option<Result<Option<auth::User>, String>>,
}

#[async_trait]
impl CallbackAuth for MockCallbackAuth {
    async fn authenticate_oauth2(
        &mut self,
        _code: String,
        _provider: OAuth2Provider,
    ) -> Result<Option<auth::User>, String> {
        self.oauth2_result
            .take()
            .expect("oauth2 callback auth result should be configured in tests")
    }

    async fn authenticate_oidc(
        &mut self,
        _code: String,
        _nonce: oidc::Nonce,
        _provider: OidcProvider,
    ) -> Result<Option<auth::User>, String> {
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
