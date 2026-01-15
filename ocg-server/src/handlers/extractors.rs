//! Custom extractors for handlers.

use std::{collections::HashMap, sync::Arc};

use axum::{
    Form,
    extract::{FromRequest, FromRequestParts, Path, Request},
    http::{StatusCode, request::Parts},
};
use garde::Validate;
use serde::de::DeserializeOwned;
use tower_sessions::Session;
use tracing::{error, instrument};
use uuid::Uuid;

use crate::{
    auth::{AuthSession, OAuth2ProviderDetails, OidcProviderDetails},
    config::{OAuth2Provider, OidcProvider},
    handlers::auth::{SELECTED_COMMUNITY_ID_KEY, SELECTED_GROUP_ID_KEY},
    router,
};

/// Extractor that resolves a community ID from the request path parameter.
pub(crate) struct CommunityId(pub Uuid);

impl FromRequestParts<router::State> for CommunityId {
    type Rejection = (StatusCode, &'static str);

    #[instrument(skip_all, err(Debug))]
    async fn from_request_parts(parts: &mut Parts, state: &router::State) -> Result<Self, Self::Rejection> {
        // Extract community name from path parameter
        let path_params: Path<HashMap<String, String>> = Path::from_request_parts(parts, state)
            .await
            .map_err(|_| (StatusCode::BAD_REQUEST, "invalid path parameters"))?;
        let Some(community_name) = path_params.get("community") else {
            return Err((StatusCode::BAD_REQUEST, "missing community parameter"));
        };

        // Lookup the community id in the database (cached at DB layer)
        if community_name.is_empty() {
            return Err((StatusCode::NOT_FOUND, "community not found"));
        }
        let Some(community_id) = state
            .db
            .get_community_id_by_name(community_name)
            .await
            .map_err(|err| {
                error!(?err, "error looking up community id");
                (StatusCode::INTERNAL_SERVER_ERROR, "")
            })?
        else {
            return Err((StatusCode::NOT_FOUND, "community not found"));
        };

        Ok(CommunityId(community_id))
    }
}

/// Extractor for `OAuth2` provider details from the authenticated session.
pub(crate) struct OAuth2(pub Arc<OAuth2ProviderDetails>);

impl FromRequestParts<router::State> for OAuth2 {
    type Rejection = (StatusCode, &'static str);

    #[instrument(skip_all, err(Debug))]
    async fn from_request_parts(parts: &mut Parts, state: &router::State) -> Result<Self, Self::Rejection> {
        let Ok(provider) = Path::<OAuth2Provider>::from_request_parts(parts, state).await else {
            return Err((StatusCode::BAD_REQUEST, "missing oauth2 provider"));
        };
        let Ok(auth_session) = AuthSession::from_request_parts(parts, state).await else {
            return Err((StatusCode::BAD_REQUEST, "missing auth session"));
        };
        let Some(provider_details) = auth_session.backend.oauth2_providers.get(&provider) else {
            return Err((StatusCode::BAD_REQUEST, "oauth2 provider not supported"));
        };
        Ok(OAuth2(provider_details.clone()))
    }
}

/// Extractor for `Oidc` provider details from the authenticated session.
pub(crate) struct Oidc(pub Arc<OidcProviderDetails>);

impl FromRequestParts<router::State> for Oidc {
    type Rejection = (StatusCode, &'static str);

    #[instrument(skip_all, err(Debug))]
    async fn from_request_parts(parts: &mut Parts, state: &router::State) -> Result<Self, Self::Rejection> {
        let Ok(provider) = Path::<OidcProvider>::from_request_parts(parts, state).await else {
            return Err((StatusCode::BAD_REQUEST, "missing oidc provider"));
        };
        let Ok(auth_session) = AuthSession::from_request_parts(parts, state).await else {
            return Err((StatusCode::BAD_REQUEST, "missing auth session"));
        };
        let Some(provider_details) = auth_session.backend.oidc_providers.get(&provider) else {
            return Err((StatusCode::BAD_REQUEST, "oidc provider not supported"));
        };
        Ok(Oidc(provider_details.clone()))
    }
}

/// Extractor for the selected community ID from the session.
/// Returns the Uuid if present, or an error if not found in the session.
pub(crate) struct SelectedCommunityId(pub Uuid);

impl FromRequestParts<router::State> for SelectedCommunityId {
    type Rejection = (StatusCode, &'static str);

    #[instrument(skip_all, err(Debug))]
    async fn from_request_parts(parts: &mut Parts, state: &router::State) -> Result<Self, Self::Rejection> {
        let Ok(session) = Session::from_request_parts(parts, state).await else {
            return Err((StatusCode::UNAUTHORIZED, "user not logged in"));
        };
        let community_id: Option<Uuid> = session.get(SELECTED_COMMUNITY_ID_KEY).await.map_err(|_| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                "error getting selected community from session",
            )
        })?;
        match community_id {
            Some(id) => Ok(SelectedCommunityId(id)),
            None => Err((StatusCode::BAD_REQUEST, "missing community id")),
        }
    }
}

/// Extractor for the selected group ID from the session.
/// Returns the Uuid if present, or an error if not found in the session.
pub(crate) struct SelectedGroupId(pub Uuid);

impl FromRequestParts<router::State> for SelectedGroupId {
    type Rejection = (StatusCode, &'static str);

    #[instrument(skip_all, err(Debug))]
    async fn from_request_parts(parts: &mut Parts, state: &router::State) -> Result<Self, Self::Rejection> {
        let Ok(session) = Session::from_request_parts(parts, state).await else {
            return Err((StatusCode::UNAUTHORIZED, "user not logged in"));
        };
        let group_id: Option<Uuid> = session.get(SELECTED_GROUP_ID_KEY).await.map_err(|_| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                "error getting selected group from session",
            )
        })?;
        match group_id {
            Some(id) => Ok(SelectedGroupId(id)),
            None => Err((StatusCode::BAD_REQUEST, "missing group id")),
        }
    }
}

/// Extractor that deserializes and validates form data using Axum's Form extractor.
///
/// Use this for simple, flat form structures. For complex nested structures
/// (arrays, maps), use `ValidatedFormQs` instead.
pub(crate) struct ValidatedForm<T>(pub T);

impl<T> FromRequest<router::State> for ValidatedForm<T>
where
    T: DeserializeOwned + Validate,
    T::Context: Default,
{
    type Rejection = (StatusCode, String);

    async fn from_request(req: Request, state: &router::State) -> Result<Self, Self::Rejection> {
        // Deserialize form data
        let Form(value) = Form::<T>::from_request(req, state)
            .await
            .map_err(|e| (StatusCode::UNPROCESSABLE_ENTITY, e.to_string()))?;

        // Validate the deserialized value
        value
            .validate()
            .map_err(|e| (StatusCode::UNPROCESSABLE_ENTITY, e.to_string()))?;

        Ok(ValidatedForm(value))
    }
}

/// Extractor that deserializes and validates form data using `serde_qs`.
///
/// Use this for complex form structures with nested arrays, maps, or deep
/// nesting that Axum's Form extractor cannot handle.
pub(crate) struct ValidatedFormQs<T>(pub T);

impl<T> FromRequest<router::State> for ValidatedFormQs<T>
where
    T: DeserializeOwned + Validate,
    T::Context: Default,
{
    type Rejection = (StatusCode, String);

    async fn from_request(req: Request, state: &router::State) -> Result<Self, Self::Rejection> {
        // Read body as string
        let body = String::from_request(req, state)
            .await
            .map_err(|e| (StatusCode::BAD_REQUEST, e.to_string()))?;

        // Deserialize using serde_qs
        let value: T = state
            .serde_qs_de
            .deserialize_str(&body)
            .map_err(|e| (StatusCode::UNPROCESSABLE_ENTITY, e.to_string()))?;

        // Validate the deserialized value
        value
            .validate()
            .map_err(|e| (StatusCode::UNPROCESSABLE_ENTITY, e.to_string()))?;

        Ok(ValidatedFormQs(value))
    }
}

// Tests.

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use anyhow::anyhow;
    use axum::{
        Router,
        body::{Body, to_bytes},
        http::{Request, StatusCode},
        routing::get,
    };
    use axum_login::AuthManagerLayerBuilder;
    use serde::Deserialize;
    use tower::ServiceExt;
    use tower_sessions::{MemoryStore, Session, SessionManagerLayer};
    use uuid::Uuid;

    use crate::{
        auth::AuthnBackend,
        config::{HttpServerConfig, OAuth2ProviderConfig},
        db::{DynDB, mock::MockDB},
        handlers::auth::{SELECTED_COMMUNITY_ID_KEY, SELECTED_GROUP_ID_KEY},
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
    async fn test_selected_community_id_extractor_missing_community_id() {
        // Setup identifiers and data structures
        let store = Arc::new(MemoryStore::default());
        let session = Session::new(None, store, None);

        // Setup database mock
        let db: DynDB = Arc::new(MockDB::new());

        // Setup services mocks
        let is: DynImageStorage = Arc::new(MockImageStorage::new());
        let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

        // Setup request parts and state
        let mut request = Request::builder().uri("/").body(Body::empty()).unwrap();
        request.extensions_mut().insert(session);
        let (mut parts, _) = request.into_parts();
        let state = build_state(db, is, nm);

        // Check extraction matches expectations
        let result = SelectedCommunityId::from_request_parts(&mut parts, &state).await;
        assert!(matches!(
            result,
            Err((StatusCode::BAD_REQUEST, "missing community id"))
        ));
    }

    #[tokio::test]
    async fn test_selected_community_id_extractor_missing_session() {
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
            Err((StatusCode::UNAUTHORIZED, "user not logged in"))
        ));
    }

    #[tokio::test]
    async fn test_selected_community_id_extractor_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let store = Arc::new(MemoryStore::default());
        let session = Session::new(None, store, None);
        session
            .insert(SELECTED_COMMUNITY_ID_KEY, community_id)
            .await
            .expect("session insert should succeed");

        // Setup database mock
        let db: DynDB = Arc::new(MockDB::new());

        // Setup services mocks
        let is: DynImageStorage = Arc::new(MockImageStorage::new());
        let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

        // Setup request parts and state
        let mut request = Request::builder().uri("/").body(Body::empty()).unwrap();
        request.extensions_mut().insert(session);
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
        let store = Arc::new(MemoryStore::default());
        let session = Session::new(None, store, None);
        session
            .insert(SELECTED_GROUP_ID_KEY, group_id)
            .await
            .expect("session insert should succeed");

        // Setup database mock
        let db: DynDB = Arc::new(MockDB::new());

        // Setup services mocks
        let is: DynImageStorage = Arc::new(MockImageStorage::new());
        let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

        // Setup request parts and state
        let mut request = Request::builder().uri("/").body(Body::empty()).unwrap();
        request.extensions_mut().insert(session);
        let (mut parts, _) = request.into_parts();
        let state = build_state(db, is, nm);

        // Check extraction matches expectations
        let SelectedGroupId(extracted) = SelectedGroupId::from_request_parts(&mut parts, &state)
            .await
            .expect("extractor should succeed");
        assert_eq!(extracted, group_id);
    }

    #[tokio::test]
    async fn test_selected_group_id_extractor_missing_session() {
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
            Err((StatusCode::UNAUTHORIZED, "user not logged in"))
        ));
    }

    #[tokio::test]
    async fn test_selected_group_id_extractor_missing_group_id() {
        // Setup identifiers and data structures
        let store = Arc::new(MemoryStore::default());
        let session = Session::new(None, store, None);

        // Setup database mock
        let db: DynDB = Arc::new(MockDB::new());

        // Setup services mocks
        let is: DynImageStorage = Arc::new(MockImageStorage::new());
        let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

        // Setup request parts and state
        let mut request = Request::builder().uri("/").body(Body::empty()).unwrap();
        request.extensions_mut().insert(session);
        let (mut parts, _) = request.into_parts();
        let state = build_state(db, is, nm);

        // Check extraction matches expectations
        let result = SelectedGroupId::from_request_parts(&mut parts, &state).await;
        assert!(matches!(
            result,
            Err((StatusCode::BAD_REQUEST, "missing group id"))
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
            db,
            image_storage,
            meetings_cfg: None,
            notifications_manager: nm,
            serde_qs_de: serde_qs_config(),
            server_cfg: HttpServerConfig::default(),
        }
    }
}
