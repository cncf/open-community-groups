//! Custom extractors for handlers.

use std::sync::Arc;
#[cfg(not(test))]
use std::time::Duration;

use anyhow::Result;
use axum::{
    extract::{FromRequestParts, Path},
    http::{StatusCode, header::HOST, request::Parts},
};
#[cfg(not(test))]
use cached::proc_macro::cached;
use tower_sessions::Session;
use tracing::{error, instrument};
use uuid::Uuid;

use crate::{
    auth::{AuthSession, OAuth2ProviderDetails, OidcProviderDetails},
    config::{OAuth2Provider, OidcProvider},
    db::DynDB,
    handlers::auth::SELECTED_GROUP_ID_KEY,
    router,
};

/// Extractor that resolves a community ID from the request's Host header.
///
/// This enables multi-tenant functionality where different communities are served based
/// on the domain name. The community ID is cached for 24 hours to reduce database
/// lookups.
pub(crate) struct CommunityId(pub Uuid);

impl FromRequestParts<router::State> for CommunityId {
    type Rejection = (StatusCode, &'static str);

    #[instrument(skip_all, err(Debug))]
    async fn from_request_parts(parts: &mut Parts, state: &router::State) -> Result<Self, Self::Rejection> {
        // Extract host from the request headers
        let Some(host_header) = parts.headers.get(HOST) else {
            return Err((StatusCode::BAD_REQUEST, "missing host header"));
        };
        let host = host_header
            .to_str()
            .unwrap_or_default()
            .split(':')
            .next()
            .unwrap_or_default();

        // Lookup the community id in the database
        let Some(community_id) = lookup_community_id(state.db.clone(), host).await.map_err(|err| {
            error!(?err, "error looking up community id");
            (StatusCode::INTERNAL_SERVER_ERROR, "")
        })?
        else {
            return Err((StatusCode::BAD_REQUEST, "community host not found"));
        };

        Ok(CommunityId(community_id))
    }
}

/// Lookup function for resolving community IDs from hostnames.
///
/// In non-test builds, results are cached for 24 hours (86400 seconds) to minimize
/// database queries. During tests the cache is disabled to avoid cross-test
/// contamination when multiple tests reuse the same host value.
#[cfg_attr(
    not(test),
    cached(
        time = 86400,
        key = "String",
        convert = r#"{ String::from(host) }"#,
        sync_writes = "by_key",
        result = true
    )
)]
#[instrument(skip(db), err)]
async fn lookup_community_id(db: DynDB, host: &str) -> Result<Option<Uuid>> {
    if host.is_empty() {
        return Ok(None);
    }
    db.get_community_id(host).await
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

// Tests.

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use anyhow::anyhow;
    use axum::{
        Router,
        body::{Body, to_bytes},
        http::{Request, StatusCode, header::HOST},
        routing::get,
    };
    use axum_login::AuthManagerLayerBuilder;
    use tower::ServiceExt;
    use tower_sessions::{MemoryStore, Session, SessionManagerLayer};
    use uuid::Uuid;

    use crate::{
        auth::AuthnBackend,
        config::{HttpServerConfig, OAuth2ProviderConfig},
        db::{DynDB, mock::MockDB},
        handlers::auth::SELECTED_GROUP_ID_KEY,
        router,
        services::notifications::{DynNotificationsManager, MockNotificationsManager},
    };

    use super::*;

    #[tokio::test]
    async fn test_community_id_extractor_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        let db: DynDB = Arc::new(db);

        // Setup notifications manager mock
        let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

        // Setup request parts and state
        let request = Request::builder()
            .uri("/")
            .header(HOST, "example.test")
            .body(Body::empty())
            .unwrap();
        let (mut parts, _) = request.into_parts();
        let state = build_state(db, nm);

        // Check extraction matches expectations
        let CommunityId(extracted) = CommunityId::from_request_parts(&mut parts, &state)
            .await
            .expect("extractor should succeed");
        assert_eq!(extracted, community_id);
    }

    #[tokio::test]
    async fn test_community_id_extractor_missing_host_header() {
        // Setup database mock
        let db: DynDB = Arc::new(MockDB::new());

        // Setup notifications manager mock
        let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

        // Setup request parts and state
        let request = Request::builder().uri("/").body(Body::empty()).unwrap();
        let (mut parts, _) = request.into_parts();
        let state = build_state(db, nm);

        // Check extraction matches expectations
        let result = CommunityId::from_request_parts(&mut parts, &state).await;
        assert!(matches!(
            result,
            Err((StatusCode::BAD_REQUEST, "missing host header"))
        ));
    }

    #[tokio::test]
    async fn test_community_id_extractor_unknown_host() {
        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "unknown.test")
            .returning(|_| Ok(None));
        let db: DynDB = Arc::new(db);

        // Setup notifications manager mock
        let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

        // Setup request parts and state
        let request = Request::builder()
            .uri("/")
            .header(HOST, "unknown.test")
            .body(Body::empty())
            .unwrap();
        let (mut parts, _) = request.into_parts();
        let state = build_state(db, nm);

        // Check extraction matches expectations
        let result = CommunityId::from_request_parts(&mut parts, &state).await;
        assert!(matches!(
            result,
            Err((StatusCode::BAD_REQUEST, "community host not found"))
        ));
    }

    #[tokio::test]
    async fn test_community_id_extractor_db_error() {
        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(|_| Err(anyhow!("db error")));
        let db: DynDB = Arc::new(db);

        // Setup notifications manager mock
        let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

        // Setup request parts and state
        let request = Request::builder()
            .uri("/")
            .header(HOST, "example.test")
            .body(Body::empty())
            .unwrap();
        let (mut parts, _) = request.into_parts();
        let state = build_state(db, nm);

        // Check extraction matches expectations
        let result = CommunityId::from_request_parts(&mut parts, &state).await;
        assert!(matches!(result, Err((StatusCode::INTERNAL_SERVER_ERROR, ""))));
    }

    #[tokio::test]
    async fn test_lookup_community_id_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let host = "example.test";

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_community_id()
            .times(1)
            .withf(move |requested_host| requested_host == host)
            .returning(move |_| Ok(Some(community_id)));
        let db: DynDB = Arc::new(db);

        // Execute lookup
        let result = lookup_community_id(db, host).await.expect("lookup should succeed");

        // Check response matches expectations
        assert_eq!(result, Some(community_id));
    }

    #[tokio::test]
    async fn test_lookup_community_id_empty_host_is_noop() {
        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_community_id().times(0);
        let db: DynDB = Arc::new(db);

        // Execute lookup
        let community_id = lookup_community_id(db, "").await.expect("lookup should succeed");

        // Check response matches expectations
        assert!(community_id.is_none());
    }

    #[tokio::test]
    async fn test_oauth2_extractor_success() {
        // Setup database mock
        let db: DynDB = Arc::new(MockDB::new());

        // Setup notifications manager mock
        let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

        // Setup config
        let scopes = vec!["read:user".to_string()];
        let mut cfg = HttpServerConfig::default();
        cfg.login.github = true;
        cfg.oauth2.insert(
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
        let backend = AuthnBackend::new(db.clone(), &cfg.oauth2, &cfg.oidc)
            .await
            .expect("backend setup should succeed");
        let auth_layer = AuthManagerLayerBuilder::new(backend, session_layer).build();

        // Setup router
        let mut state = build_state(db, nm);
        state.cfg = cfg;
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

        // Setup notifications manager mock
        let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

        // Setup router
        let router = Router::new()
            .route("/log-in/oauth2", get(|_oauth2: OAuth2| async { StatusCode::OK }))
            .with_state(build_state(db, nm));

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

        // Setup notifications manager mock
        let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

        // Setup router
        let router = Router::new()
            .route(
                "/log-in/oauth2/{provider}",
                get(|_oauth2: OAuth2| async { StatusCode::OK }),
            )
            .with_state(build_state(db, nm));

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

        // Setup notifications manager mock
        let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

        // Setup auth layer with an empty set of OAuth2 providers
        let cfg = HttpServerConfig::default();
        let session_layer = SessionManagerLayer::new(MemoryStore::default());
        let backend = AuthnBackend::new(db.clone(), &cfg.oauth2, &cfg.oidc)
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
            .with_state(build_state(db, nm));

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

        // Setup notifications manager mock
        let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

        // Setup router
        let router = Router::new()
            .route("/log-in/oidc", get(|_oidc: Oidc| async { StatusCode::OK }))
            .with_state(build_state(db, nm));

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

        // Setup notifications manager mock
        let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

        // Setup router
        let router = Router::new()
            .route(
                "/log-in/oidc/{provider}",
                get(|_oidc: Oidc| async { StatusCode::OK }),
            )
            .with_state(build_state(db, nm));

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

        // Setup notifications manager mock
        let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

        // Setup auth layer with an empty set of OIDC providers
        let cfg = HttpServerConfig::default();
        let session_layer = SessionManagerLayer::new(MemoryStore::default());
        let backend = AuthnBackend::new(db.clone(), &cfg.oauth2, &cfg.oidc)
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
            .with_state(build_state(db, nm));

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

        // Setup notifications manager mock
        let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

        // Setup request parts and state
        let mut request = Request::builder().uri("/").body(Body::empty()).unwrap();
        request.extensions_mut().insert(session);
        let (mut parts, _) = request.into_parts();
        let state = build_state(db, nm);

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

        // Setup notifications manager mock
        let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

        // Setup request parts and state
        let request = Request::builder().uri("/").body(Body::empty()).unwrap();
        let (mut parts, _) = request.into_parts();
        let state = build_state(db, nm);

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

        // Setup notifications manager mock
        let nm: DynNotificationsManager = Arc::new(MockNotificationsManager::new());

        // Setup request parts and state
        let mut request = Request::builder().uri("/").body(Body::empty()).unwrap();
        request.extensions_mut().insert(session);
        let (mut parts, _) = request.into_parts();
        let state = build_state(db, nm);

        // Check extraction matches expectations
        let result = SelectedGroupId::from_request_parts(&mut parts, &state).await;
        assert!(matches!(
            result,
            Err((StatusCode::BAD_REQUEST, "missing group id"))
        ));
    }

    // Helpers.

    /// Builds router state with the provided database and notifications manager.
    fn build_state(db: DynDB, notifications_manager: DynNotificationsManager) -> router::State {
        router::State {
            cfg: HttpServerConfig::default(),
            db,
            notifications_manager,
            serde_qs_de: serde_qs::Config::new(3, false),
        }
    }
}
