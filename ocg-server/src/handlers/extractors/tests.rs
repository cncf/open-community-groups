use std::sync::Arc;

use anyhow::anyhow;
use axum::{
    Router,
    body::{Body, to_bytes},
    http::{
        Request, StatusCode,
        header::{COOKIE, SET_COOKIE},
    },
    routing::get,
};
use axum_login::AuthManagerLayerBuilder;
use serde::Deserialize;
use tower::ServiceExt;
use tower_sessions::{MemoryStore, SessionManagerLayer};
use uuid::Uuid;

use crate::{
    auth::AuthnBackend,
    config::{HttpServerConfig, OAuth2ProviderConfig},
    db::{DynDB, mock::MockDB},
    handlers::tests::sample_auth_user,
    router::{self, serde_qs_config},
    services::{
        images::{DynImageStorage, MockImageStorage},
        notifications::{DynNotificationsManager, MockNotificationsManager},
    },
};

use super::*;

#[tokio::test]
async fn test_community_id_extractor_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));
    let db: DynDB = Arc::new(db);

    // Setup services mocks
    let is: DynImageStorage = Arc::new(MockImageStorage::new());
    let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

    // Setup router with test endpoint that uses CommunityId extractor
    let state = build_state(db, is, nm);
    let router = Router::new()
        .route(
            "/{community}/test",
            get(|CommunityId(id): CommunityId| async move { id.to_string() }),
        )
        .with_state(state);

    // Send request with community in path
    let request = Request::builder()
        .uri("/test-community/test")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(bytes.as_ref(), community_id.to_string().as_bytes());
}

#[tokio::test]
async fn test_community_id_extractor_unknown_community() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "unknown")
        .returning(|_| Ok(None));
    let db: DynDB = Arc::new(db);

    // Setup services mocks
    let is: DynImageStorage = Arc::new(MockImageStorage::new());
    let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

    // Setup router with test endpoint that uses CommunityId extractor
    let state = build_state(db, is, nm);
    let router = Router::new()
        .route(
            "/{community}/test",
            get(|CommunityId(_id): CommunityId| async { StatusCode::OK }),
        )
        .with_state(state);

    // Send request
    let request = Request::builder().uri("/unknown/test").body(Body::empty()).unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NOT_FOUND);
    assert_eq!(bytes.as_ref(), b"community not found");
}

#[tokio::test]
async fn test_community_id_extractor_db_error() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(|_| Err(anyhow!("db error")));
    let db: DynDB = Arc::new(db);

    // Setup services mocks
    let is: DynImageStorage = Arc::new(MockImageStorage::new());
    let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

    // Setup router with test endpoint that uses CommunityId extractor
    let state = build_state(db, is, nm);
    let router = Router::new()
        .route(
            "/{community}/test",
            get(|CommunityId(_id): CommunityId| async { StatusCode::OK }),
        )
        .with_state(state);

    // Send request
    let request = Request::builder()
        .uri("/test-community/test")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();

    // Check response matches expectations
    assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_current_user_extractor_missing_auth_session() {
    // Setup database mock
    let db: DynDB = Arc::new(MockDB::new());

    // Setup services mocks
    let is: DynImageStorage = Arc::new(MockImageStorage::new());
    let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

    // Setup router without auth layer
    let router = Router::new()
        .route(
            "/test",
            get(|_current_user: CurrentUser| async { StatusCode::OK }),
        )
        .with_state(build_state(db, is, nm));

    // Send request
    let request = Request::builder().uri("/test").body(Body::empty()).unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNAUTHORIZED);
    assert_eq!(bytes.as_ref(), b"user not logged in");
}

#[tokio::test]
async fn test_current_user_extractor_session_without_user() {
    // Setup database mock
    let db: DynDB = Arc::new(MockDB::new());

    // Setup services mocks
    let is: DynImageStorage = Arc::new(MockImageStorage::new());
    let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

    // Setup auth layer
    let server_cfg = HttpServerConfig::default();
    let session_layer = SessionManagerLayer::new(MemoryStore::default());
    let backend = AuthnBackend::new(db.clone(), &server_cfg.oauth2, &server_cfg.oidc)
        .await
        .expect("backend setup should succeed");
    let auth_layer = AuthManagerLayerBuilder::new(backend, session_layer).build();

    // Setup router
    let router = Router::new()
        .route(
            "/init",
            get(|auth_session: AuthSession| async move {
                auth_session
                    .session
                    .insert("marker", "set")
                    .await
                    .expect("session insert should succeed");
                StatusCode::NO_CONTENT
            }),
        )
        .route(
            "/test",
            get(|CurrentUser(_user): CurrentUser| async move { StatusCode::OK }),
        )
        .layer(auth_layer)
        .with_state(build_state(db, is, nm));

    // Initialize session without logging in
    let init_request = Request::builder().uri("/init").body(Body::empty()).unwrap();
    let init_response = router.clone().oneshot(init_request).await.unwrap();
    let set_cookie = init_response
        .headers()
        .get(SET_COOKIE)
        .expect("set-cookie header should be present")
        .to_str()
        .expect("set-cookie should be valid utf-8");
    let cookie = set_cookie
        .split(';')
        .next()
        .expect("set-cookie should contain cookie pair")
        .to_string();

    // Send request with session cookie
    let request = Request::builder()
        .uri("/test")
        .header(COOKIE, cookie)
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNAUTHORIZED);
    assert_eq!(bytes.as_ref(), b"user not logged in");
}

#[tokio::test]
async fn test_current_user_extractor_success() {
    // Setup identifiers and data structures
    let auth_hash = "auth-hash";
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| id == &user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, auth_hash))));
    let db: DynDB = Arc::new(db);

    // Setup services mocks
    let is: DynImageStorage = Arc::new(MockImageStorage::new());
    let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

    // Setup auth layer
    let server_cfg = HttpServerConfig::default();
    let session_layer = SessionManagerLayer::new(MemoryStore::default());
    let backend = AuthnBackend::new(db.clone(), &server_cfg.oauth2, &server_cfg.oidc)
        .await
        .expect("backend setup should succeed");
    let auth_layer = AuthManagerLayerBuilder::new(backend, session_layer).build();

    // Setup router
    let router = Router::new()
        .route(
            "/log-in",
            get(move |mut auth_session: AuthSession| async move {
                let user = sample_auth_user(user_id, auth_hash);
                auth_session.login(&user).await.expect("login should succeed");
                StatusCode::NO_CONTENT
            }),
        )
        .route(
            "/test",
            get(|CurrentUser(user): CurrentUser| async move { user.username }),
        )
        .layer(auth_layer)
        .with_state(build_state(db, is, nm));

    // Log in to create authenticated session
    let login_request = Request::builder().uri("/log-in").body(Body::empty()).unwrap();
    let login_response = router.clone().oneshot(login_request).await.unwrap();
    let set_cookie = login_response
        .headers()
        .get(SET_COOKIE)
        .expect("set-cookie header should be present")
        .to_str()
        .expect("set-cookie should be valid utf-8");
    let cookie = set_cookie
        .split(';')
        .next()
        .expect("set-cookie should contain cookie pair")
        .to_string();

    // Send authenticated request
    let request = Request::builder()
        .uri("/test")
        .header(COOKIE, cookie)
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(bytes.as_ref(), b"test-user");
}

#[tokio::test]
async fn test_oauth2_extractor_success() {
    // Setup database mock
    let db: DynDB = Arc::new(MockDB::new());

    // Setup services mocks
    let is: DynImageStorage = Arc::new(MockImageStorage::new());
    let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

    // Setup config
    let scopes = vec!["read:user".to_string()];
    let mut server_cfg = HttpServerConfig::default();
    server_cfg.login.github = true;
    server_cfg.oauth2.insert(
        OAuth2Provider::GitHub,
        OAuth2ProviderConfig {
            auth_url: "https://github.com/login/oauth/authorize".to_string(),
            client_id: "client-id".to_string(),
            client_secret: "client-secret".to_string(),
            redirect_uri: "https://example.test/oauth2/callback".to_string(),
            scopes: scopes.clone(),
            token_url: "https://github.com/login/oauth/access_token".to_string(),
        },
    );

    // Setup auth layer with the configured provider
    let session_layer = SessionManagerLayer::new(MemoryStore::default());
    let backend = AuthnBackend::new(db.clone(), &server_cfg.oauth2, &server_cfg.oidc)
        .await
        .expect("backend setup should succeed");
    let auth_layer = AuthManagerLayerBuilder::new(backend, session_layer).build();

    // Setup router
    let mut state = build_state(db, is, nm);
    state.server_cfg = server_cfg;
    let router = Router::new()
        .route(
            "/log-in/oauth2/{provider}",
            get({
                move |OAuth2(provider_details): OAuth2| async move {
                    assert_eq!(provider_details.scopes, scopes.clone());
                    StatusCode::OK
                }
            }),
        )
        .layer(auth_layer)
        .with_state(state);

    // Send request for the configured provider
    let request = Request::builder()
        .uri("/log-in/oauth2/github")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();

    // Check response matches expectations
    assert_eq!(response.status(), StatusCode::OK);
}

#[tokio::test]
async fn test_oauth2_extractor_missing_oauth2_provider() {
    // Setup database mock
    let db: DynDB = Arc::new(MockDB::new());

    // Setup services mocks
    let is: DynImageStorage = Arc::new(MockImageStorage::new());
    let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

    // Setup router
    let router = Router::new()
        .route("/log-in/oauth2", get(|_oauth2: OAuth2| async { StatusCode::OK }))
        .with_state(build_state(db, is, nm));

    // Send request
    let request = Request::builder().uri("/log-in/oauth2").body(Body::empty()).unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(bytes.as_ref(), b"missing oauth2 provider");
}

#[tokio::test]
async fn test_oauth2_extractor_missing_auth_session() {
    // Setup database mock
    let db: DynDB = Arc::new(MockDB::new());

    // Setup services mocks
    let is: DynImageStorage = Arc::new(MockImageStorage::new());
    let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

    // Setup router
    let router = Router::new()
        .route(
            "/log-in/oauth2/{provider}",
            get(|_oauth2: OAuth2| async { StatusCode::OK }),
        )
        .with_state(build_state(db, is, nm));

    // Send request
    let request = Request::builder()
        .uri("/log-in/oauth2/github")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(bytes.as_ref(), b"missing auth session");
}

#[tokio::test]
async fn test_oauth2_extractor_unsupported_provider() {
    // Setup database mock
    let db: DynDB = Arc::new(MockDB::new());

    // Setup services mocks
    let is: DynImageStorage = Arc::new(MockImageStorage::new());
    let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

    // Setup auth layer with an empty set of OAuth2 providers
    let server_cfg = HttpServerConfig::default();
    let session_layer = SessionManagerLayer::new(MemoryStore::default());
    let backend = AuthnBackend::new(db.clone(), &server_cfg.oauth2, &server_cfg.oidc)
        .await
        .expect("backend setup should succeed");
    let auth_layer = AuthManagerLayerBuilder::new(backend, session_layer).build();

    // Setup router
    let router = Router::new()
        .route(
            "/log-in/oauth2/{provider}",
            get(|_oauth2: OAuth2| async { StatusCode::OK }),
        )
        .layer(auth_layer)
        .with_state(build_state(db, is, nm));

    // Send request
    let request = Request::builder()
        .uri("/log-in/oauth2/github")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(bytes.as_ref(), b"oauth2 provider not supported");
}

#[tokio::test]
async fn test_oidc_extractor_missing_oidc_provider() {
    // Setup database mock
    let db: DynDB = Arc::new(MockDB::new());

    // Setup services mocks
    let is: DynImageStorage = Arc::new(MockImageStorage::new());
    let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

    // Setup router
    let router = Router::new()
        .route("/log-in/oidc", get(|_oidc: Oidc| async { StatusCode::OK }))
        .with_state(build_state(db, is, nm));

    // Send request
    let request = Request::builder().uri("/log-in/oidc").body(Body::empty()).unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(bytes.as_ref(), b"missing oidc provider");
}

#[tokio::test]
async fn test_oidc_extractor_missing_auth_session() {
    // Setup database mock
    let db: DynDB = Arc::new(MockDB::new());

    // Setup services mocks
    let is: DynImageStorage = Arc::new(MockImageStorage::new());
    let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

    // Setup router
    let router = Router::new()
        .route(
            "/log-in/oidc/{provider}",
            get(|_oidc: Oidc| async { StatusCode::OK }),
        )
        .with_state(build_state(db, is, nm));

    // Send request
    let request = Request::builder()
        .uri("/log-in/oidc/linuxfoundation")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(bytes.as_ref(), b"missing auth session");
}

#[tokio::test]
async fn test_oidc_extractor_unsupported_provider() {
    // Setup database mock
    let db: DynDB = Arc::new(MockDB::new());

    // Setup services mocks
    let is: DynImageStorage = Arc::new(MockImageStorage::new());
    let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

    // Setup auth layer with an empty set of OIDC providers
    let server_cfg = HttpServerConfig::default();
    let session_layer = SessionManagerLayer::new(MemoryStore::default());
    let backend = AuthnBackend::new(db.clone(), &server_cfg.oauth2, &server_cfg.oidc)
        .await
        .expect("backend setup should succeed");
    let auth_layer = AuthManagerLayerBuilder::new(backend, session_layer).build();

    // Setup router
    let router = Router::new()
        .route(
            "/log-in/oidc/{provider}",
            get(|_oidc: Oidc| async { StatusCode::OK }),
        )
        .layer(auth_layer)
        .with_state(build_state(db, is, nm));

    // Send request
    let request = Request::builder()
        .uri("/log-in/oidc/linuxfoundation")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(bytes.as_ref(), b"oidc provider not supported");
}

#[tokio::test]
async fn test_selected_community_id_extractor_missing_context() {
    // Setup database mock
    let db: DynDB = Arc::new(MockDB::new());

    // Setup services mocks
    let is: DynImageStorage = Arc::new(MockImageStorage::new());
    let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

    // Setup request parts and state
    let request = Request::builder().uri("/").body(Body::empty()).unwrap();
    let (mut parts, _) = request.into_parts();
    let state = build_state(db, is, nm);

    // Check extraction matches expectations
    let result = SelectedCommunityId::from_request_parts(&mut parts, &state).await;
    assert!(matches!(
        result,
        Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            "missing selected community context"
        ))
    ));
}

#[tokio::test]
async fn test_selected_community_id_extractor_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();

    // Setup database mock
    let db: DynDB = Arc::new(MockDB::new());

    // Setup services mocks
    let is: DynImageStorage = Arc::new(MockImageStorage::new());
    let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

    // Setup request parts and state
    let mut request = Request::builder().uri("/").body(Body::empty()).unwrap();
    request.extensions_mut().insert(SelectedCommunityId(community_id));
    let (mut parts, _) = request.into_parts();
    let state = build_state(db, is, nm);

    // Check extraction matches expectations
    let SelectedCommunityId(extracted) = SelectedCommunityId::from_request_parts(&mut parts, &state)
        .await
        .expect("extractor should succeed");
    assert_eq!(extracted, community_id);
}

#[tokio::test]
async fn test_selected_group_id_extractor_success() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();

    // Setup database mock
    let db: DynDB = Arc::new(MockDB::new());

    // Setup services mocks
    let is: DynImageStorage = Arc::new(MockImageStorage::new());
    let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

    // Setup request parts and state
    let mut request = Request::builder().uri("/").body(Body::empty()).unwrap();
    request.extensions_mut().insert(SelectedGroupId(group_id));
    let (mut parts, _) = request.into_parts();
    let state = build_state(db, is, nm);

    // Check extraction matches expectations
    let SelectedGroupId(extracted) = SelectedGroupId::from_request_parts(&mut parts, &state)
        .await
        .expect("extractor should succeed");
    assert_eq!(extracted, group_id);
}

#[tokio::test]
async fn test_selected_group_id_extractor_missing_context() {
    // Setup database mock
    let db: DynDB = Arc::new(MockDB::new());

    // Setup services mocks
    let is: DynImageStorage = Arc::new(MockImageStorage::new());
    let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

    // Setup request parts and state
    let request = Request::builder().uri("/").body(Body::empty()).unwrap();
    let (mut parts, _) = request.into_parts();
    let state = build_state(db, is, nm);

    // Check extraction matches expectations
    let result = SelectedGroupId::from_request_parts(&mut parts, &state).await;
    assert!(matches!(
        result,
        Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            "missing selected group context"
        ))
    ));
}

#[tokio::test]
async fn test_validated_form_success() {
    // Setup database mock
    let db: DynDB = Arc::new(MockDB::new());

    // Setup services mocks
    let is: DynImageStorage = Arc::new(MockImageStorage::new());
    let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

    // Setup router with a handler that uses ValidatedForm
    let state = build_state(db, is, nm);
    let router = Router::new()
        .route(
            "/test",
            axum::routing::post(|ValidatedForm(form): ValidatedForm<TestForm>| async move {
                assert_eq!(form.name, "test name");
                StatusCode::OK
            }),
        )
        .with_state(state);

    // Send valid request
    let request = Request::builder()
        .method("POST")
        .uri("/test")
        .header("content-type", "application/x-www-form-urlencoded")
        .body(Body::from("name=test+name"))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();

    // Check response matches expectations
    assert_eq!(response.status(), StatusCode::OK);
}

#[tokio::test]
async fn test_validated_form_validation_error() {
    // Setup database mock
    let db: DynDB = Arc::new(MockDB::new());

    // Setup services mocks
    let is: DynImageStorage = Arc::new(MockImageStorage::new());
    let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

    // Setup router with a handler that uses ValidatedForm
    let state = build_state(db, is, nm);
    let router = Router::new()
        .route(
            "/test",
            axum::routing::post(
                |ValidatedForm(_form): ValidatedForm<TestForm>| async move { StatusCode::OK },
            ),
        )
        .with_state(state);

    // Send request with empty name (validation should fail)
    let request = Request::builder()
        .method("POST")
        .uri("/test")
        .header("content-type", "application/x-www-form-urlencoded")
        .body(Body::from("name=+++"))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();

    // Check response matches expectations
    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_validated_form_qs_success() {
    // Setup database mock
    let db: DynDB = Arc::new(MockDB::new());

    // Setup services mocks
    let is: DynImageStorage = Arc::new(MockImageStorage::new());
    let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

    // Setup router with a handler that uses ValidatedFormQs
    let state = build_state(db, is, nm);
    let router = Router::new()
        .route(
            "/test",
            axum::routing::post(|ValidatedFormQs(form): ValidatedFormQs<TestFormQs>| async move {
                assert_eq!(form.name, "test name");
                assert_eq!(form.tags, Some(vec!["tag1".to_string(), "tag2".to_string()]));
                StatusCode::OK
            }),
        )
        .with_state(state);

    // Send valid request with nested array
    let request = Request::builder()
        .method("POST")
        .uri("/test")
        .header("content-type", "application/x-www-form-urlencoded")
        .body(Body::from("name=test+name&tags[0]=tag1&tags[1]=tag2"))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();

    // Check response matches expectations
    assert_eq!(response.status(), StatusCode::OK);
}

#[tokio::test]
async fn test_validated_form_qs_validation_error() {
    // Setup database mock
    let db: DynDB = Arc::new(MockDB::new());

    // Setup services mocks
    let is: DynImageStorage = Arc::new(MockImageStorage::new());
    let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

    // Setup router with a handler that uses ValidatedFormQs
    let state = build_state(db, is, nm);
    let router = Router::new()
        .route(
            "/test",
            axum::routing::post(|ValidatedFormQs(_form): ValidatedFormQs<TestFormQs>| async move {
                StatusCode::OK
            }),
        )
        .with_state(state);

    // Send request with whitespace-only name (validation should fail)
    let request = Request::builder()
        .method("POST")
        .uri("/test")
        .header("content-type", "application/x-www-form-urlencoded")
        .body(Body::from("name=+++"))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();

    // Check response matches expectations
    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

// Test form structs for validation.

/// Simple test form for `ValidatedForm` tests.
#[derive(Debug, Deserialize, garde::Validate)]
struct TestForm {
    #[garde(custom(crate::validation::trimmed_non_empty))]
    name: String,
}

/// Complex test form for `ValidatedFormQs` tests.
#[derive(Debug, Deserialize, garde::Validate)]
struct TestFormQs {
    #[garde(custom(crate::validation::trimmed_non_empty))]
    name: String,

    #[garde(skip)]
    tags: Option<Vec<String>>,
}

// Helpers.

/// Builds router state with the provided database and notifications manager.
fn build_state(db: DynDB, image_storage: DynImageStorage, nm: DynNotificationsManager) -> router::State {
    router::State {
        activity_tracker: Arc::new(crate::activity_tracker::MockActivityTracker::new()),
        db,
        image_storage,
        meetings_cfg: None,
        notifications_manager: nm,
        serde_qs_de: serde_qs_config(),
        server_cfg: HttpServerConfig::default(),
    }
}
