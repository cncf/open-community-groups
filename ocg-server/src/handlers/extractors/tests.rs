use std::sync::Arc;

use anyhow::anyhow;
use axum::{
    Router,
    body::Body,
    http::{
        StatusCode,
        header::{CONTENT_TYPE, COOKIE, SET_COOKIE},
        response::Parts as ResponseParts,
    },
    routing::{get, post},
};
use axum_login::AuthManagerLayerBuilder;
use serde::Deserialize;
use tower_sessions::{MemoryStore, SessionManagerLayer};
use uuid::Uuid;

use crate::{
    auth::AuthnBackend,
    config::{HttpServerConfig, OAuth2ProviderConfig},
    db::{DynDB, mock::MockDB},
    handlers::{
        error::INVALID_REQUEST_PAYLOAD,
        tests::{
            assert_empty_response, request, sample_auth_user, send, test_state_with_server_cfg,
        },
    },
    services::{
        blocking::BlockingExecutor, images::MockImageStorage,
        notifications::MockNotificationsManager,
    },
};

use super::*;

#[tokio::test]
async fn test_community_id_extractor_success() {
    // Setup identifiers and database mock
    let community_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));

    // Setup router with test endpoint that uses CommunityId extractor
    let router = Router::new()
        .route(
            "/{community}/test",
            get(|CommunityId(id): CommunityId| async move { id.to_string() }),
        )
        .with_state(state(db));

    // Send request with community in path
    let request = request("GET", "/test-community/test").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

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

    // Setup router with test endpoint that uses CommunityId extractor
    let router = Router::new()
        .route(
            "/{community}/test",
            get(|CommunityId(_id): CommunityId| async { StatusCode::OK }),
        )
        .with_state(state(db));

    // Send request
    let request = request("GET", "/unknown/test").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

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

    // Setup router with test endpoint that uses CommunityId extractor
    let router = Router::new()
        .route(
            "/{community}/test",
            get(|CommunityId(_id): CommunityId| async { StatusCode::OK }),
        )
        .with_state(state(db));

    // Send request
    let request = request("GET", "/test-community/test").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_current_user_extractor_missing_auth_session() {
    // Setup router without auth layer
    let router = Router::new()
        .route(
            "/test",
            get(|_current_user: CurrentUser| async { StatusCode::OK }),
        )
        .with_state(state(MockDB::new()));

    // Send request
    let request = request("GET", "/test").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNAUTHORIZED);
    assert_eq!(bytes.as_ref(), b"user not logged in");
}

#[tokio::test]
async fn test_current_user_extractor_session_without_user() {
    // Setup router with a route that initializes a session without logging in
    let endpoints = Router::new()
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
        );
    let router = with_auth_layer(endpoints, MockDB::new(), &HttpServerConfig::default()).await;

    // Initialize session without logging in
    let init_request = request("GET", "/init").body(Body::empty()).unwrap();
    let (init_parts, _) = send(router.clone(), init_request).await;

    // Send request with session cookie
    let request = request("GET", "/test")
        .header(COOKIE, session_cookie(&init_parts))
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNAUTHORIZED);
    assert_eq!(bytes.as_ref(), b"user not logged in");
}

#[tokio::test]
async fn test_current_user_extractor_success() {
    // Setup identifiers and database mock
    let auth_hash = "auth-hash";
    let user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| id == &user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, auth_hash))));

    // Setup router with a route that logs the user in
    let endpoints = Router::new()
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
        );
    let router = with_auth_layer(endpoints, db, &HttpServerConfig::default()).await;

    // Log in to create authenticated session
    let login_request = request("GET", "/log-in").body(Body::empty()).unwrap();
    let (login_parts, _) = send(router.clone(), login_request).await;

    // Send authenticated request
    let request = request("GET", "/test")
        .header(COOKIE, session_cookie(&login_parts))
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(bytes.as_ref(), b"test-user");
}

#[tokio::test]
async fn test_oauth2_extractor_success() {
    // Setup config with a GitHub provider
    let mut server_cfg = HttpServerConfig::default();
    server_cfg.login.github = true;
    server_cfg.oauth2.insert(
        OAuth2Provider::GitHub,
        OAuth2ProviderConfig {
            auth_url: "https://github.com/login/oauth/authorize".to_string(),
            client_id: "client-id".to_string(),
            client_secret: "client-secret".to_string(),
            redirect_uri: "https://example.test/oauth2/callback".to_string(),
            scopes: vec!["read:user".to_string(), "user:email".to_string()],
            token_url: "https://github.com/login/oauth/access_token".to_string(),
        },
    );

    // Setup router returning the extracted provider scopes
    let endpoints = Router::new().route(
        "/log-in/oauth2/{provider}",
        get(|OAuth2(provider_details): OAuth2| async move { provider_details.scopes.join(" ") }),
    );
    let router = with_auth_layer(endpoints, MockDB::new(), &server_cfg).await;

    // Send request for the configured provider
    let request = request("GET", "/log-in/oauth2/github").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(bytes.as_ref(), b"read:user user:email");
}

#[tokio::test]
async fn test_oauth2_extractor_missing_oauth2_provider() {
    // Setup router
    let router = Router::new()
        .route(
            "/log-in/oauth2",
            get(|_oauth2: OAuth2| async { StatusCode::OK }),
        )
        .with_state(state(MockDB::new()));

    // Send request
    let request = request("GET", "/log-in/oauth2").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(bytes.as_ref(), b"missing oauth2 provider");
}

#[tokio::test]
async fn test_oauth2_extractor_missing_auth_session() {
    // Setup router without auth layer
    let router = Router::new()
        .route(
            "/log-in/oauth2/{provider}",
            get(|_oauth2: OAuth2| async { StatusCode::OK }),
        )
        .with_state(state(MockDB::new()));

    // Send request
    let request = request("GET", "/log-in/oauth2/github").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(bytes.as_ref(), b"missing auth session");
}

#[tokio::test]
async fn test_oauth2_extractor_unsupported_provider() {
    // Setup router with an auth layer without OAuth2 providers
    let endpoints = Router::new().route(
        "/log-in/oauth2/{provider}",
        get(|_oauth2: OAuth2| async { StatusCode::OK }),
    );
    let router = with_auth_layer(endpoints, MockDB::new(), &HttpServerConfig::default()).await;

    // Send request
    let request = request("GET", "/log-in/oauth2/github").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(bytes.as_ref(), b"oauth2 provider not supported");
}

#[tokio::test]
async fn test_oidc_extractor_missing_oidc_provider() {
    // Setup router
    let router = Router::new()
        .route("/log-in/oidc", get(|_oidc: Oidc| async { StatusCode::OK }))
        .with_state(state(MockDB::new()));

    // Send request
    let request = request("GET", "/log-in/oidc").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(bytes.as_ref(), b"missing oidc provider");
}

#[tokio::test]
async fn test_oidc_extractor_missing_auth_session() {
    // Setup router without auth layer
    let router = Router::new()
        .route(
            "/log-in/oidc/{provider}",
            get(|_oidc: Oidc| async { StatusCode::OK }),
        )
        .with_state(state(MockDB::new()));

    // Send request
    let request = request("GET", "/log-in/oidc/linuxfoundation")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(bytes.as_ref(), b"missing auth session");
}

#[tokio::test]
async fn test_oidc_extractor_unsupported_provider() {
    // Setup router with an auth layer without OIDC providers
    let endpoints = Router::new().route(
        "/log-in/oidc/{provider}",
        get(|_oidc: Oidc| async { StatusCode::OK }),
    );
    let router = with_auth_layer(endpoints, MockDB::new(), &HttpServerConfig::default()).await;

    // Send request
    let request = request("GET", "/log-in/oidc/linuxfoundation")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(bytes.as_ref(), b"oidc provider not supported");
}

#[tokio::test]
async fn test_selected_community_id_extractor_missing_context() {
    // Setup request parts
    let (mut parts, _) = request("GET", "/").body(Body::empty()).unwrap().into_parts();

    // Check extraction matches expectations
    let result = SelectedCommunityId::from_request_parts(&mut parts, &state(MockDB::new())).await;
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
    // Setup request parts carrying the selected community
    let community_id = Uuid::new_v4();
    let mut request = request("GET", "/").body(Body::empty()).unwrap();
    request.extensions_mut().insert(SelectedCommunityId(community_id));
    let (mut parts, _) = request.into_parts();

    // Check extraction matches expectations
    let SelectedCommunityId(extracted) =
        SelectedCommunityId::from_request_parts(&mut parts, &state(MockDB::new()))
            .await
            .expect("extractor should succeed");
    assert_eq!(extracted, community_id);
}

#[tokio::test]
async fn test_selected_group_id_extractor_success() {
    // Setup request parts carrying the selected group
    let group_id = Uuid::new_v4();
    let mut request = request("GET", "/").body(Body::empty()).unwrap();
    request.extensions_mut().insert(SelectedGroupId(group_id));
    let (mut parts, _) = request.into_parts();

    // Check extraction matches expectations
    let SelectedGroupId(extracted) =
        SelectedGroupId::from_request_parts(&mut parts, &state(MockDB::new()))
            .await
            .expect("extractor should succeed");
    assert_eq!(extracted, group_id);
}

#[tokio::test]
async fn test_selected_group_id_extractor_missing_context() {
    // Setup request parts
    let (mut parts, _) = request("GET", "/").body(Body::empty()).unwrap().into_parts();

    // Check extraction matches expectations
    let result = SelectedGroupId::from_request_parts(&mut parts, &state(MockDB::new())).await;
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
    // Setup router with a handler that returns the extracted form
    let router = Router::new()
        .route(
            "/test",
            post(|ValidatedForm(form): ValidatedForm<TestForm>| async move { form.name }),
        )
        .with_state(state(MockDB::new()));

    // Send valid request
    let (parts, bytes) = send(router, form_post("/test", "name=test+name")).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(bytes.as_ref(), b"test name");
}

#[tokio::test]
async fn test_validated_form_deserialization_error() {
    // Setup router with a handler that uses ValidatedForm
    let router = Router::new()
        .route(
            "/test",
            post(|ValidatedForm(_form): ValidatedForm<TestForm>| async move { StatusCode::OK }),
        )
        .with_state(state(MockDB::new()));

    // Send request without the required field (deserialization should fail)
    let (parts, bytes) = send(router, form_post("/test", "other=value")).await;

    // Check the fixed body hides the parser detail
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), INVALID_REQUEST_PAYLOAD.as_bytes());
}

#[tokio::test]
async fn test_validated_form_validation_error() {
    // Setup router with a handler that uses ValidatedForm
    let router = Router::new()
        .route(
            "/test",
            post(|ValidatedForm(_form): ValidatedForm<TestForm>| async move { StatusCode::OK }),
        )
        .with_state(state(MockDB::new()));

    // Send request with empty name (validation should fail)
    let (parts, bytes) = send(router, form_post("/test", "name=+++")).await;

    // Check the garde report is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        bytes.as_ref(),
        b"name: value cannot be empty or whitespace-only\n"
    );
}

#[tokio::test]
async fn test_validated_form_qs_deserialization_error() {
    // Setup router with a handler that uses ValidatedFormQs
    let router = Router::new()
        .route(
            "/test",
            post(
                |ValidatedFormQs(_form): ValidatedFormQs<TestFormQs>| async move { StatusCode::OK },
            ),
        )
        .with_state(state(MockDB::new()));

    // Send request without the required field (deserialization should fail)
    let (parts, bytes) = send(router, form_post("/test", "tags[0]=tag1")).await;

    // Check the fixed body hides the parser detail
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), INVALID_REQUEST_PAYLOAD.as_bytes());
}

#[tokio::test]
async fn test_validated_form_qs_success() {
    // Setup router with a handler that returns the extracted form
    let router = Router::new()
        .route(
            "/test",
            post(
                |ValidatedFormQs(form): ValidatedFormQs<TestFormQs>| async move {
                    format!("{} {:?}", form.name, form.tags)
                },
            ),
        )
        .with_state(state(MockDB::new()));

    // Send valid request with nested array
    let body = "name=test+name&tags[0]=tag1&tags[1]=tag2";
    let (parts, bytes) = send(router, form_post("/test", body)).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(bytes.as_ref(), br#"test name Some(["tag1", "tag2"])"#);
}

#[tokio::test]
async fn test_validated_form_qs_validation_error() {
    // Setup router with a handler that uses ValidatedFormQs
    let router = Router::new()
        .route(
            "/test",
            post(
                |ValidatedFormQs(_form): ValidatedFormQs<TestFormQs>| async move { StatusCode::OK },
            ),
        )
        .with_state(state(MockDB::new()));

    // Send request with whitespace-only name (validation should fail)
    let (parts, bytes) = send(router, form_post("/test", "name=+++")).await;

    // Check the garde report is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        bytes.as_ref(),
        b"name: value cannot be empty or whitespace-only\n"
    );
}

#[tokio::test]
async fn test_validated_query_success() {
    // Setup router with a handler that returns the extracted query
    let router = Router::new()
        .route(
            "/test",
            get(
                |ValidatedQuery(query): ValidatedQuery<TestQuery>| async move {
                    format!("{} {:?} {:?}", query.name, query.limit, query.tags)
                },
            ),
        )
        .with_state(state(MockDB::new()));

    // Send valid request with nested array in the query string
    let uri = "/test?name=test+name&limit=10&tags[0]=tag1&tags[1]=tag2";
    let request = request("GET", uri).body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        bytes.as_ref(),
        br#"test name Some(10) Some(["tag1", "tag2"])"#
    );
}

#[tokio::test]
async fn test_validated_query_deserialization_error() {
    // Setup router with a handler that uses ValidatedQuery
    let router = Router::new()
        .route(
            "/test",
            get(|ValidatedQuery(_query): ValidatedQuery<TestQuery>| async move { StatusCode::OK }),
        )
        .with_state(state(MockDB::new()));

    // Send request without the required field (deserialization should fail)
    let request = request("GET", "/test?limit=10").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the fixed body hides the parser detail
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), INVALID_REQUEST_PAYLOAD.as_bytes());
}

#[tokio::test]
async fn test_validated_query_validation_error() {
    // Setup router with a handler that uses ValidatedQuery
    let router = Router::new()
        .route(
            "/test",
            get(|ValidatedQuery(_query): ValidatedQuery<TestQuery>| async move { StatusCode::OK }),
        )
        .with_state(state(MockDB::new()));

    // Send request with an out-of-range limit (validation should fail)
    let request = request("GET", "/test?name=test&limit=0").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the garde report is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), b"limit: lower than 1\n");
}

#[test]
fn test_validated_query_parse_success() {
    let query: TestQuery =
        ValidatedQuery::parse("name=test+name&tags[0]=tag1").expect("query to parse");

    assert_eq!(query.name, "test name");
    assert_eq!(query.limit, None);
    assert_eq!(query.tags, Some(vec!["tag1".to_string()]));
}

#[test]
fn test_validated_query_parse_deserialization_error() {
    let err = ValidatedQuery::<TestQuery>::parse("limit=10").expect_err("parse to fail");

    assert!(matches!(err, HandlerError::Deserialization(_)));
}

#[test]
fn test_validated_query_parse_validation_error() {
    let err = ValidatedQuery::<TestQuery>::parse("name=+++").expect_err("parse to fail");

    assert!(matches!(err, HandlerError::Validation(_)));
}

// Helpers.

/// Builds an unauthenticated form-encoded POST request.
fn form_post(uri: &str, body: &'static str) -> axum::http::Request<Body> {
    request("POST", uri)
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap()
}

/// Returns the session cookie pair set by the response.
fn session_cookie(parts: &ResponseParts) -> String {
    let set_cookie = parts
        .headers
        .get(SET_COOKIE)
        .expect("set-cookie header should be present")
        .to_str()
        .expect("set-cookie should be valid utf-8");
    set_cookie
        .split(';')
        .next()
        .expect("set-cookie should contain cookie pair")
        .to_string()
}

/// Builds router state around the database mock with default service mocks.
fn state(db: MockDB) -> router::State {
    test_state_with_server_cfg(
        Arc::new(db),
        Arc::new(MockImageStorage::new()),
        Arc::new(MockNotificationsManager::new()),
        &HttpServerConfig::default(),
    )
}

/// Wraps the routes with an in-memory auth layer and the test state.
async fn with_auth_layer(
    routes: Router<router::State>,
    db: MockDB,
    server_cfg: &HttpServerConfig,
) -> Router {
    let db: DynDB = Arc::new(db);
    let backend = AuthnBackend::new(
        BlockingExecutor::new(1),
        db.clone(),
        &server_cfg.http_client,
        &server_cfg.oauth2,
        &server_cfg.oidc,
    )
    .await
    .expect("backend setup should succeed");
    let session_layer = SessionManagerLayer::new(MemoryStore::default());
    let auth_layer = AuthManagerLayerBuilder::new(backend, session_layer).build();
    let state = test_state_with_server_cfg(
        db,
        Arc::new(MockImageStorage::new()),
        Arc::new(MockNotificationsManager::new()),
        server_cfg,
    );

    routes.layer(auth_layer).with_state(state)
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

/// Test query string for `ValidatedQuery` tests.
#[derive(Debug, Deserialize, garde::Validate)]
struct TestQuery {
    #[garde(range(min = 1, max = 100))]
    limit: Option<usize>,

    #[garde(custom(crate::validation::trimmed_non_empty))]
    name: String,

    #[garde(skip)]
    tags: Option<Vec<String>>,
}
