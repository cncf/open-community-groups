use std::sync::Arc;

use anyhow::anyhow;
use axum::{
    Router,
    body::{Body, to_bytes},
    http::{
        HeaderValue, Request, StatusCode,
        header::{CACHE_CONTROL, COOKIE, LOCATION},
    },
    middleware,
    routing::get,
};
use axum_login::tower_sessions::session;
use serde_json::json;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::{DynDB, mock::MockDB},
    handlers::{auth::session_context::SELECTED_GROUP_ID_KEY, tests::*},
    router::CACHE_CONTROL_NO_STORE,
    services::{
        blocking::BlockingExecutor, images::MockImageStorage,
        notifications::MockNotificationsManager,
    },
};

use super::*;

#[tokio::test]
async fn test_dashboard_community_redirects_to_user_invitations_when_context_is_missing_and_unavailable()
 {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
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
async fn test_dashboard_group_redirects_to_user_invitations_when_context_is_missing_and_unavailable()
 {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
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
async fn test_user_has_community_dashboard_permission_allows_request() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    expect_community_permission(&mut db, community_id, user_id, CommunityPermission::Read);
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
async fn test_user_has_community_dashboard_permission_allows_matching_loaded_context() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    expect_community_permission(&mut db, community_id, user_id, CommunityPermission::Read);
    db.expect_update_session().times(0);

    // Setup router and send request declaring the loaded community
    let router = setup_community_dashboard_router(db).await;
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(SELECTED_COMMUNITY_ID_HEADER, community_id.to_string())
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the protected handler ran
    assert_eq!(parts.status, StatusCode::OK);
    assert!(!parts.headers.contains_key(STALE_DASHBOARD_CONTEXT_HEADER));
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_community_dashboard_permission_fetch_redirects_when_selected_context_is_stale()
 {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let stale_group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, stale_group_id);
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id && *uid == user_id && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(false));
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(|_| Ok(vec![]));
    db.expect_list_user_groups().times(0);
    db.expect_update_session().times(0);
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get("X-OCG-Redirect").unwrap(),
        &HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_community_dashboard_permission_hx_redirects_when_selected_context_is_stale()
{
    // Setup identifiers and data structures
    let inaccessible_community_id = Uuid::new_v4();
    let stale_group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(
        &mut db,
        session_id,
        user_id,
        inaccessible_community_id,
        stale_group_id,
    );
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == inaccessible_community_id
                && *uid == user_id
                && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(false));
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(|_| Ok(vec![]));
    db.expect_list_user_groups().times(0);
    db.expect_update_session().times(0);
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
        &HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_community_dashboard_permission_redirects_when_context_is_missing_and_unavailable()
 {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
async fn test_user_has_community_dashboard_permission_refreshes_stale_loaded_context_after_repair()
{
    // Setup identifiers and data structures
    let accessible_community_id = Uuid::new_v4();
    let inaccessible_community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let communities = vec![sample_community_summary(accessible_community_id)];

    // Setup stale selection and repair expectations
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, inaccessible_community_id);
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == inaccessible_community_id
                && *uid == user_id
                && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(false));
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(communities.clone()));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == accessible_community_id
                && *uid == user_id
                && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(|_| Ok(vec![]));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == session_id
                && record
                    .data
                    .get(SELECTED_COMMUNITY_ID_KEY)
                    .is_some_and(|value| value == &json!(accessible_community_id))
        })
        .returning(|_| Ok(()));

    // Setup router and send request declaring the stale community
    let router = setup_community_dashboard_router(db).await;
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(
            SELECTED_COMMUNITY_ID_HEADER,
            inaccessible_community_id.to_string(),
        )
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the client is told to reload instead of reaching the handler
    assert_stale_dashboard_context_response(parts.status, &parts.headers);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_community_dashboard_permission_repairs_missing_context() {
    // Setup identifiers and data structures
    let accessible_community_id = Uuid::new_v4();
    let accessible_group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let groups = sample_user_groups_by_community(accessible_community_id, accessible_group_id);

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
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
            *cid == accessible_community_id
                && *uid == user_id
                && permission == CommunityPermission::Read
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
async fn test_user_has_community_dashboard_permission_repairs_stale_context_without_groups() {
    // Setup identifiers and data structures
    let accessible_community_id = Uuid::new_v4();
    let inaccessible_community_id = Uuid::new_v4();
    let stale_group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let communities = vec![sample_community_summary(accessible_community_id)];

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(
        &mut db,
        session_id,
        user_id,
        inaccessible_community_id,
        stale_group_id,
    );
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == inaccessible_community_id
                && *uid == user_id
                && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(false));
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(communities.clone()));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == accessible_community_id
                && *uid == user_id
                && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(|_| Ok(vec![]));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == session_id
                && record
                    .data
                    .get(SELECTED_COMMUNITY_ID_KEY)
                    .is_some_and(|value| value == &json!(accessible_community_id))
                && !record.data.contains_key(SELECTED_GROUP_ID_KEY)
        })
        .returning(|_| Ok(()));
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
async fn test_user_has_path_community_permission_select_route_allows_request() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    expect_community_permission(&mut db, community_id, user_id, CommunityPermission::Read);

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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
    let router = Router::new()
        .route(
            "/{community_id}/protected",
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

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
    let router = Router::new()
        .route(
            "/{community_id}/protected",
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

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
    let router = Router::new()
        .route(
            "/{community_id}/protected",
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

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    expect_community_permission(&mut db, community_id, user_id, CommunityPermission::Read);

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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
    let router = Router::new()
        .route(
            "/{community_id}/protected",
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

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    db.expect_group_belongs_to_community()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(true));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, _permission| {
            *cid == community_id && *gid == group_id && *uid == user_id
        })
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
async fn test_user_has_path_group_permission_fetch_redirects_when_selected_community_is_missing() {
    // Setup an authenticated session without selected community context
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database expectations before the missing-context guard
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_group_belongs_to_community().times(0);
    db.expect_user_has_group_permission().times(0);

    // Setup protected path-group route
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
    let router = Router::new()
        .route("/groups/{group_id}", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), GroupPermission::Read),
            user_has_path_group_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute fetch request without selected community context
    let request = Request::builder()
        .method("GET")
        .uri(format!("/groups/{group_id}"))
        .header("X-OCG-Fetch", "true")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check fetch navigation uses redirect metadata without a response body
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get("X-OCG-Redirect").unwrap(),
        &HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_path_group_permission_forbidden_when_group_is_outside_selected_community() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    db.expect_group_belongs_to_community()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(false));
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
    db.expect_group_belongs_to_community().times(0);
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
async fn test_user_has_path_group_permission_forbidden_without_permission() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    db.expect_group_belongs_to_community()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(true));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, _permission| {
            *cid == community_id && *gid == group_id && *uid == user_id
        })
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
async fn test_user_has_path_group_permission_hx_redirects_when_selected_community_is_missing() {
    // Setup an authenticated session without selected community context
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database expectations before the missing-context guard
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_group_belongs_to_community().times(0);
    db.expect_user_has_group_permission().times(0);

    // Setup protected path-group route
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
    let router = Router::new()
        .route("/groups/{group_id}", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), GroupPermission::Read),
            user_has_path_group_permission,
        ))
        .layer(auth_layer)
        .with_state(state);

    // Execute HTMX request without selected community context
    let request = Request::builder()
        .method("GET")
        .uri(format!("/groups/{group_id}"))
        .header("HX-Request", "true")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check HTMX navigation uses redirect metadata without a response body
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get("HX-Redirect").unwrap(),
        &HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_path_group_permission_redirects_when_selected_community_is_missing() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_group_belongs_to_community().times(0);
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
async fn test_user_has_path_group_permission_returns_error_on_db_failure() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    db.expect_group_belongs_to_community()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(true));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, _permission| {
            *cid == community_id && *gid == group_id && *uid == user_id
        })
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
async fn test_user_has_selected_community_permission_allows_request() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    expect_community_permission(&mut db, community_id, user_id, CommunityPermission::Read);

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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
async fn test_user_has_selected_community_permission_forbidden_without_permission() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
async fn test_user_has_selected_community_permission_redirects_when_context_is_missing_and_unavailable()
 {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
async fn test_user_has_selected_community_permission_refreshes_stale_loaded_context_before_forbidding_write()
 {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let loaded_community_id = Uuid::new_v4();

    // Setup a readable selection without the write permission the route needs
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id && *uid == user_id && permission == CommunityPermission::TeamWrite
        })
        .returning(|_, _, _| Ok(false));
    expect_community_permission(&mut db, community_id, user_id, CommunityPermission::Read);
    db.expect_update_session().times(0);

    // Setup router and send an action from a page rendered for another community
    let router = setup_selected_community_router(db, CommunityPermission::TeamWrite).await;
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(
            SELECTED_COMMUNITY_ID_HEADER,
            loaded_community_id.to_string(),
        )
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the stale page is refreshed instead of receiving a forbidden error
    assert_stale_dashboard_context_response(parts.status, &parts.headers);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_selected_community_permission_refreshes_when_loaded_community_differs() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let loaded_community_id = Uuid::new_v4();

    // Setup a valid selection that differs from the loaded page
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    expect_community_permission(&mut db, community_id, user_id, CommunityPermission::Read);
    db.expect_update_session().times(0);

    // Setup router and send request declaring another community
    let router = setup_selected_community_router(db, CommunityPermission::Read).await;
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(
            SELECTED_COMMUNITY_ID_HEADER,
            loaded_community_id.to_string(),
        )
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the client is told to reload instead of reaching the handler
    assert_stale_dashboard_context_response(parts.status, &parts.headers);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_selected_community_permission_repairs_missing_context() {
    // Setup identifiers and data structures
    let accessible_community_id = Uuid::new_v4();
    let accessible_group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let groups = sample_user_groups_by_community(accessible_community_id, accessible_group_id);

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
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
            *cid == accessible_community_id
                && *uid == user_id
                && permission == CommunityPermission::Read
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
async fn test_user_has_selected_community_permission_repairs_stale_context_before_forbidding_write()
{
    // Setup identifiers and stale dashboard context
    let accessible_community_id = Uuid::new_v4();
    let inaccessible_community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let stale_group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    // Setup current and replacement permission expectations
    let mut db = MockDB::new();
    expect_authenticated_group_session(
        &mut db,
        session_id,
        user_id,
        inaccessible_community_id,
        stale_group_id,
    );
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == inaccessible_community_id
                && *uid == user_id
                && permission == CommunityPermission::TeamWrite
        })
        .returning(|_, _, _| Ok(false));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == inaccessible_community_id
                && *uid == user_id
                && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(false));
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(vec![sample_community_summary(accessible_community_id)]));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == accessible_community_id
                && *uid == user_id
                && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(|_| Ok(vec![]));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == accessible_community_id
                && *uid == user_id
                && permission == CommunityPermission::TeamWrite
        })
        .returning(|_, _, _| Ok(false));
    db.expect_update_session().times(1).returning(|_| Ok(()));
    db.expect_delete_session().times(0);

    // Setup router with a community write requirement
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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

    // Check repair occurs before write access is denied
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_user_has_selected_community_permission_returns_error_on_db_failure() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
async fn test_user_has_selected_group_permission_allows_request() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, _permission| {
            *cid == community_id && *gid == group_id && *uid == user_id
        })
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
async fn test_user_has_selected_group_permission_allows_matching_loaded_context() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    db.expect_update_session().times(0);

    // Setup router and send request declaring the loaded community and group
    let router = setup_selected_group_router(db, GroupPermission::Read).await;
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(SELECTED_COMMUNITY_ID_HEADER, community_id.to_string())
        .header(SELECTED_GROUP_ID_HEADER, group_id.to_string())
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the protected handler ran
    assert_eq!(parts.status, StatusCode::OK);
    assert!(!parts.headers.contains_key(STALE_DASHBOARD_CONTEXT_HEADER));
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_selected_group_permission_fetch_redirects_when_selected_group_is_stale() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let stale_group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, stale_group_id);
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == stale_group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(|_| Ok(vec![]));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == session_id
                && record
                    .data
                    .get(SELECTED_COMMUNITY_ID_KEY)
                    .is_some_and(|value| value == &json!(community_id))
                && !record.data.contains_key(SELECTED_GROUP_ID_KEY)
        })
        .returning(|_| Ok(()));
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get("X-OCG-Redirect").unwrap(),
        &HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL),
    );
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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

#[tokio::test]
async fn test_user_has_selected_group_permission_forbidden_without_permission() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    db.expect_user_has_group_permission()
        .times(2)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && matches!(
                    permission,
                    GroupPermission::Read | GroupPermission::TeamWrite
                )
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
async fn test_user_has_selected_group_permission_hx_redirects_when_selected_group_is_stale() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let stale_group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, stale_group_id);
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == stale_group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(|_| Ok(vec![]));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == session_id
                && record
                    .data
                    .get(SELECTED_COMMUNITY_ID_KEY)
                    .is_some_and(|value| value == &json!(community_id))
                && !record.data.contains_key(SELECTED_GROUP_ID_KEY)
        })
        .returning(|_| Ok(()));
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
        &HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_selected_group_permission_redirects_when_context_is_missing_and_unavailable()
{
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
async fn test_user_has_selected_group_permission_redirects_when_selected_group_is_stale_and_unavailable()
 {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let stale_group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, stale_group_id);
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == stale_group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(|_| Ok(vec![]));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == session_id
                && record
                    .data
                    .get(SELECTED_COMMUNITY_ID_KEY)
                    .is_some_and(|value| value == &json!(community_id))
                && !record.data.contains_key(SELECTED_GROUP_ID_KEY)
        })
        .returning(|_| Ok(()));
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
async fn test_user_has_selected_group_permission_refreshes_stale_loaded_context_after_repair() {
    // Setup identifiers and stale dashboard context
    let community_id = Uuid::new_v4();
    let replacement_group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let stale_group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let groups = sample_user_groups_by_community(community_id, replacement_group_id);

    // Setup lost permission and repair expectations
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, stale_group_id);
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == stale_group_id
                && *uid == user_id
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == stale_group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(groups.clone()));
    expect_group_permission(
        &mut db,
        community_id,
        replacement_group_id,
        user_id,
        GroupPermission::Read,
    );
    expect_group_permission(
        &mut db,
        community_id,
        replacement_group_id,
        user_id,
        GroupPermission::EventsWrite,
    );
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == session_id
                && record
                    .data
                    .get(SELECTED_GROUP_ID_KEY)
                    .is_some_and(|value| value == &json!(replacement_group_id))
        })
        .returning(|_| Ok(()));

    // Setup router and send an action from the page rendered for the stale group
    let router = setup_selected_group_router(db, GroupPermission::EventsWrite).await;
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(SELECTED_COMMUNITY_ID_HEADER, community_id.to_string())
        .header(SELECTED_GROUP_ID_HEADER, stale_group_id.to_string())
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the repaired selection is persisted but the action never runs
    assert_stale_dashboard_context_response(parts.status, &parts.headers);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_selected_group_permission_refreshes_stale_loaded_context_before_forbidding_write()
 {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let loaded_group_id = Uuid::new_v4();

    // Setup a readable selection without the write permission the route needs
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(false));
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    db.expect_update_session().times(0);

    // Setup router and send an action from a page rendered for another group
    let router = setup_selected_group_router(db, GroupPermission::EventsWrite).await;
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(SELECTED_COMMUNITY_ID_HEADER, community_id.to_string())
        .header(SELECTED_GROUP_ID_HEADER, loaded_group_id.to_string())
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the stale page is refreshed instead of receiving a forbidden error
    assert_stale_dashboard_context_response(parts.status, &parts.headers);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_selected_group_permission_refreshes_when_loaded_group_differs() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let loaded_group_id = Uuid::new_v4();

    // Setup a valid selection that differs from the loaded page
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    db.expect_update_session().times(0);

    // Setup router and send request declaring another group
    let router = setup_selected_group_router(db, GroupPermission::Read).await;
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(SELECTED_COMMUNITY_ID_HEADER, community_id.to_string())
        .header(SELECTED_GROUP_ID_HEADER, loaded_group_id.to_string())
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the client is told to reload instead of reaching the handler
    assert_stale_dashboard_context_response(parts.status, &parts.headers);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_selected_group_permission_refreshes_when_loaded_group_is_unparsable() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    db.expect_update_session().times(0);

    // Setup router and send request with an invalid group header
    let router = setup_selected_group_router(db, GroupPermission::Read).await;
    let request = Request::builder()
        .method("GET")
        .uri("/protected")
        .header(SELECTED_COMMUNITY_ID_HEADER, community_id.to_string())
        .header(SELECTED_GROUP_ID_HEADER, "not-a-uuid")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the client is told to reload instead of reaching the handler
    assert_stale_dashboard_context_response(parts.status, &parts.headers);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_user_has_selected_group_permission_repairs_missing_context() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let groups = sample_user_groups_by_community(community_id, group_id);

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(groups.clone()));
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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
async fn test_user_has_selected_group_permission_repairs_stale_context_before_forbidding_write() {
    // Setup identifiers and stale dashboard context
    let community_id = Uuid::new_v4();
    let replacement_group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let stale_group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let groups = sample_user_groups_by_community(community_id, replacement_group_id);

    // Setup current and replacement permission expectations
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, stale_group_id);
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == stale_group_id
                && *uid == user_id
                && permission == GroupPermission::TeamWrite
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == stale_group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(groups.clone()));
    expect_group_permission(
        &mut db,
        community_id,
        replacement_group_id,
        user_id,
        GroupPermission::Read,
    );
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == replacement_group_id
                && *uid == user_id
                && permission == GroupPermission::TeamWrite
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_update_session().times(1).returning(|_| Ok(()));
    db.expect_delete_session().times(0);

    // Setup router with a group write requirement
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let nm = Arc::new(MockNotificationsManager::new());
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        nm.clone(),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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

    // Check repair occurs before write access is denied
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_user_has_selected_group_permission_returns_error_on_db_failure() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, _permission| {
            *cid == community_id && *gid == group_id && *uid == user_id
        })
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
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();
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

// Helpers.

/// Asserts the response is the stale dashboard context refresh intercept.
fn assert_stale_dashboard_context_response(status: StatusCode, headers: &HeaderMap) {
    assert_eq!(status, StatusCode::NO_CONTENT);
    assert_eq!(
        headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_NO_STORE),
    );
    assert_eq!(
        headers.get(STALE_DASHBOARD_CONTEXT_HEADER).unwrap(),
        &HeaderValue::from_static("true"),
    );
}

/// Builds a router protecting `/protected` with the community dashboard middleware.
async fn setup_community_dashboard_router(db: MockDB) -> Router {
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        Arc::new(MockNotificationsManager::new()),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();

    Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            db.clone(),
            user_has_community_dashboard_permission,
        ))
        .layer(auth_layer)
        .with_state(state)
}

/// Builds a router protecting `/protected` with the selected community middleware.
async fn setup_selected_community_router(db: MockDB, permission: CommunityPermission) -> Router {
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        Arc::new(MockNotificationsManager::new()),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();

    Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), permission),
            user_has_selected_community_permission,
        ))
        .layer(auth_layer)
        .with_state(state)
}

/// Builds a router protecting `/protected` with the selected group middleware.
async fn setup_selected_group_router(db: MockDB, permission: GroupPermission) -> Router {
    let server_cfg = HttpServerConfig::default();
    let db: DynDB = Arc::new(db);
    let state = test_state_with_server_cfg(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        Arc::new(MockNotificationsManager::new()),
        &server_cfg,
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db.clone())
        .await
        .unwrap();

    Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), permission),
            user_has_selected_group_permission,
        ))
        .layer(auth_layer)
        .with_state(state)
}
