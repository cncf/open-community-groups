//! HTTP routing configuration for the OCG redirector.

use std::{collections::HashMap, sync::Arc};

use anyhow::Result;
use axum::{
    Router,
    extract::State as AxumState,
    http::{StatusCode, Uri},
    response::{IntoResponse, Redirect},
    routing::get,
};
use tokio::sync::RwLock;
use tower_http::trace::TraceLayer;
use tracing::{error, instrument};

use crate::{
    config::HttpServerConfig,
    db::{DynDB, RedirectEntity, RedirectTarget},
};

/// Shared state for the router.
#[derive(Clone)]
pub(crate) struct State {
    /// Cache of resolved legacy paths to redirect locations.
    pub cache: Arc<RwLock<HashMap<String, String>>>,
    /// Database handle.
    pub db: DynDB,
    /// HTTP server configuration.
    pub server_cfg: HttpServerConfig,
}

/// Configures and returns the application router.
#[instrument(skip_all)]
pub(crate) async fn setup(db: DynDB, server_cfg: &HttpServerConfig) -> Result<Router> {
    let state = State {
        cache: Arc::new(RwLock::new(HashMap::new())),
        db,
        server_cfg: server_cfg.clone(),
    };

    let router = Router::new()
        .route("/", get(redirect))
        .route("/health-check", get(health_check))
        .route("/{*path}", get(redirect))
        .layer(TraceLayer::new_for_http());

    Ok(router.with_state(state))
}

// Handlers.

/// Returns a success response when the service is healthy.
async fn health_check() -> impl IntoResponse {
    StatusCode::OK
}

/// Redirects the request to the canonical location or to the configured base redirect URL.
#[instrument(skip_all)]
async fn redirect(AxumState(state): AxumState<State>, uri: Uri) -> impl IntoResponse {
    // Normalize the lookup path and infer which redirect table to query
    let legacy_path = normalize_legacy_path(uri.path());
    let entity = infer_entity(&legacy_path);

    // Reuse previously resolved redirect targets for stable legacy paths
    if let Some(location) = state.cache.read().await.get(&legacy_path).cloned() {
        return Redirect::permanent(&location).into_response();
    }

    // Fetch the redirect target from the database when this path is not cached
    let target = match state.db.get_redirect_target(entity, &legacy_path).await {
        Ok(target) => target,
        Err(err) => {
            error!(?err, %legacy_path, "error resolving redirect target");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    // Do not cache misses so new mappings become visible without restart
    let Some(target) = target else {
        return Redirect::permanent(&state.server_cfg.base_redirect_url).into_response();
    };

    // Build the redirect location and cache it for future requests
    let location = build_redirect_url(&state.server_cfg.base_redirect_url, &target);
    {
        let mut cache = state.cache.write().await;
        cache.insert(legacy_path, location.clone());
    }

    Redirect::permanent(&location).into_response()
}

// Helpers.

/// Builds the canonical redirect URL for the provided target.
fn build_redirect_url(base_url: &str, target: &RedirectTarget) -> String {
    let base = base_url.trim_end_matches('/');

    match target.entity {
        RedirectEntity::Event => format!(
            "{}/{}/group/{}/event/{}",
            base,
            target.community_name,
            target.group_slug,
            target
                .event_slug
                .as_deref()
                .expect("event redirects must include event_slug")
        ),
        RedirectEntity::Group => {
            format!("{}/{}/group/{}", base, target.community_name, target.group_slug)
        }
    }
}

/// Infers the redirect entity type from the request path.
/// Legacy event paths always start with `/events` and group paths never do.
fn infer_entity(path: &str) -> RedirectEntity {
    if path
        .strip_prefix("/events")
        .is_some_and(|suffix| suffix.is_empty() || suffix.starts_with('/'))
    {
        RedirectEntity::Event
    } else {
        RedirectEntity::Group
    }
}

/// Normalizes legacy paths for lookups and caching.
fn normalize_legacy_path(path: &str) -> String {
    let normalized_path = path.trim_end_matches('/');

    if normalized_path.is_empty() {
        "/".to_string()
    } else {
        normalized_path.to_string()
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use axum::{
        body::Body,
        http::{HeaderValue, Request, StatusCode, header::LOCATION},
    };
    use tower::ServiceExt;

    use crate::{
        config::HttpServerConfig,
        db::{DynDB, MockDB, RedirectEntity, RedirectTarget},
    };

    use super::*;

    #[tokio::test]
    async fn test_health_check_returns_ok() {
        let response = health_check().await.into_response();

        assert_eq!(response.status(), StatusCode::OK);
    }

    #[test]
    fn test_infer_entity_detects_event_paths() {
        assert_eq!(infer_entity("/events/legacy-event"), RedirectEntity::Event);
        assert_eq!(infer_entity("/events"), RedirectEntity::Event);
        assert_eq!(infer_entity("/foo/events/legacy-event"), RedirectEntity::Group);
        assert_eq!(infer_entity("/legacy-group"), RedirectEntity::Group);
    }

    #[test]
    fn test_normalize_legacy_path_trims_trailing_slashes() {
        assert_eq!(normalize_legacy_path("/groups/active/"), "/groups/active");
        assert_eq!(normalize_legacy_path("/events/active/"), "/events/active");
        assert_eq!(normalize_legacy_path("/"), "/");
    }

    #[tokio::test]
    async fn test_redirect_caches_resolved_location_for_normalized_paths() {
        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_redirect_target()
            .times(1)
            .withf(|entity, legacy_path| *entity == RedirectEntity::Group && legacy_path == "/legacy-group")
            .returning(|_, _| {
                Ok(Some(RedirectTarget {
                    community_name: "community".to_string(),
                    entity: RedirectEntity::Group,
                    group_slug: "group".to_string(),
                    event_slug: None,
                }))
            });

        // Setup router and send requests
        let router = test_router(Arc::new(db) as DynDB).await;
        let response = router.clone().oneshot(test_request("/legacy-group/")).await.unwrap();
        let cached_response = router.oneshot(test_request("/legacy-group")).await.unwrap();

        // Check response matches expectations
        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(cached_response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            cached_response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/community/group/group")
        );
    }

    #[tokio::test]
    async fn test_redirect_drops_query_string_from_lookup_and_target() {
        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_redirect_target()
            .once()
            .withf(|entity, legacy_path| {
                *entity == RedirectEntity::Event && legacy_path == "/events/legacy-event"
            })
            .returning(|_, _| {
                Ok(Some(RedirectTarget {
                    community_name: "community".to_string(),
                    entity: RedirectEntity::Event,
                    group_slug: "group".to_string(),

                    event_slug: Some("event".to_string()),
                }))
            });

        // Setup router and send request
        let router = test_router(Arc::new(db) as DynDB).await;
        let response = router
            .oneshot(test_request("/events/legacy-event?utm_source=test"))
            .await
            .unwrap();

        // Check response matches expectations
        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/community/group/group/event/event")
        );
    }

    #[tokio::test]
    async fn test_redirect_normalizes_event_trailing_slash_lookup() {
        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_redirect_target()
            .once()
            .withf(|entity, legacy_path| {
                *entity == RedirectEntity::Event && legacy_path == "/events/legacy-event"
            })
            .returning(|_, _| {
                Ok(Some(RedirectTarget {
                    community_name: "community".to_string(),
                    entity: RedirectEntity::Event,
                    group_slug: "group".to_string(),

                    event_slug: Some("event".to_string()),
                }))
            });

        // Setup router and send request
        let router = test_router(Arc::new(db) as DynDB).await;
        let response = router.oneshot(test_request("/events/legacy-event/")).await.unwrap();

        // Check response matches expectations
        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/community/group/group/event/event")
        );
    }

    #[tokio::test]
    async fn test_redirects_event_match_to_canonical_url() {
        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_redirect_target()
            .once()
            .withf(|entity, legacy_path| {
                *entity == RedirectEntity::Event && legacy_path == "/events/legacy-event"
            })
            .returning(|_, _| {
                Ok(Some(RedirectTarget {
                    community_name: "community".to_string(),
                    entity: RedirectEntity::Event,
                    group_slug: "group".to_string(),

                    event_slug: Some("event".to_string()),
                }))
            });

        // Setup router and send request
        let router = test_router(Arc::new(db) as DynDB).await;
        let response = router.oneshot(test_request("/events/legacy-event")).await.unwrap();

        // Check response matches expectations
        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/community/group/group/event/event")
        );
    }

    #[tokio::test]
    async fn test_redirects_group_match_to_canonical_url() {
        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_redirect_target()
            .once()
            .withf(|entity, legacy_path| *entity == RedirectEntity::Group && legacy_path == "/legacy-group")
            .returning(|_, _| {
                Ok(Some(RedirectTarget {
                    community_name: "community".to_string(),
                    entity: RedirectEntity::Group,
                    group_slug: "group".to_string(),
                    event_slug: None,
                }))
            });

        // Setup router and send request
        let router = test_router(Arc::new(db) as DynDB).await;
        let response = router.oneshot(test_request("/legacy-group")).await.unwrap();

        // Check response matches expectations
        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/community/group/group")
        );
    }

    #[tokio::test]
    async fn test_redirects_to_base_redirect_url_when_match_is_missing() {
        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_redirect_target()
            .once()
            .withf(|entity, legacy_path| *entity == RedirectEntity::Group && legacy_path == "/missing")
            .returning(|_, _| Ok(None));

        // Setup router and send request
        let router = test_router(Arc::new(db) as DynDB).await;
        let response = router.oneshot(test_request("/missing")).await.unwrap();

        // Check response matches expectations
        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example")
        );
    }

    #[tokio::test]
    async fn test_redirect_does_not_cache_default_location() {
        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_redirect_target()
            .times(2)
            .withf(|entity, legacy_path| *entity == RedirectEntity::Group && legacy_path == "/missing")
            .returning(|_, _| Ok(None));

        // Setup router and send requests
        let router = test_router(Arc::new(db) as DynDB).await;
        let response = router.clone().oneshot(test_request("/missing")).await.unwrap();
        let second_response = router.oneshot(test_request("/missing")).await.unwrap();

        // Check response matches expectations
        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(second_response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            second_response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example")
        );
    }

    #[tokio::test]
    async fn test_redirect_serves_new_match_after_initial_miss() {
        // Setup database mock
        let mut sequence = mockall::Sequence::new();
        let mut db = MockDB::new();
        db.expect_get_redirect_target()
            .once()
            .withf(|entity, legacy_path| {
                *entity == RedirectEntity::Group && legacy_path == "/new-legacy-group"
            })
            .return_once(|_, _| Ok(None))
            .in_sequence(&mut sequence);
        db.expect_get_redirect_target()
            .once()
            .withf(|entity, legacy_path| {
                *entity == RedirectEntity::Group && legacy_path == "/new-legacy-group"
            })
            .return_once(|_, _| {
                Ok(Some(RedirectTarget {
                    community_name: "community".to_string(),
                    entity: RedirectEntity::Group,
                    group_slug: "group".to_string(),
                    event_slug: None,
                }))
            })
            .in_sequence(&mut sequence);

        // Setup router and send requests
        let router = test_router(Arc::new(db) as DynDB).await;
        let fallback_response = router
            .clone()
            .oneshot(test_request("/new-legacy-group"))
            .await
            .unwrap();
        let redirect_response = router.oneshot(test_request("/new-legacy-group")).await.unwrap();

        // Check response matches expectations
        assert_eq!(fallback_response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            fallback_response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example")
        );
        assert_eq!(redirect_response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            redirect_response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example/community/group/group")
        );
    }

    #[tokio::test]
    async fn test_redirects_to_base_redirect_url_when_match_is_duplicated() {
        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_redirect_target()
            .once()
            .withf(|entity, legacy_path| *entity == RedirectEntity::Group && legacy_path == "/duplicate")
            .returning(|_, _| Ok(None));

        // Setup router and send request
        let router = test_router(Arc::new(db) as DynDB).await;
        let response = router.oneshot(test_request("/duplicate")).await.unwrap();

        // Check response matches expectations
        assert_eq!(response.status(), StatusCode::PERMANENT_REDIRECT);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("https://ocg.example")
        );
    }

    // Helpers.

    /// Builds a test request for the provided path.
    fn test_request(path: &str) -> Request<Body> {
        Request::builder().uri(path).body(Body::empty()).unwrap()
    }

    /// Sets up a router with the provided database and default configuration for testing.
    async fn test_router(db: DynDB) -> Router {
        let server_cfg = HttpServerConfig {
            addr: "127.0.0.1:9001".to_string(),
            base_redirect_url: "https://ocg.example".to_string(),
        };

        setup(db, &server_cfg).await.unwrap()
    }
}
