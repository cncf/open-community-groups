use std::sync::Arc;

use anyhow::anyhow;
use axum::{
    Router,
    body::{Body, to_bytes},
    http::{
        HeaderValue, StatusCode,
        header::{CACHE_CONTROL, LOCATION},
        response::Parts,
    },
    middleware,
    routing::get,
};
use axum_login::tower_sessions::session;
use serde_json::json;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::{DynDB, mock::MockDB},
    handlers::{auth::session_context::SELECTED_GROUP_ID_KEY, tests::*},
    router::{self, CACHE_CONTROL_NO_STORE},
    services::{
        blocking::BlockingExecutor, images::MockImageStorage,
        notifications::MockNotificationsManager,
    },
};

use super::*;

// Dashboard routes.

#[tokio::test]
async fn test_dashboard_community_redirects_to_user_invitations_when_context_is_missing_and_unavailable()
 {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_list_user_communities()
        .times(1)
        .withf(move |id| *id == ids.user_id)
        .returning(|_| Ok(vec![]));
    db.expect_update_session().times(0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/community", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL)),
    );
}

#[tokio::test]
async fn test_dashboard_group_redirects_to_user_invitations_when_context_is_missing_and_unavailable()
 {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_list_user_groups()
        .times(1)
        .withf(move |id| *id == ids.user_id)
        .returning(|_| Ok(vec![]));
    db.expect_update_session().times(0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL)),
    );
}

// Community dashboard middleware.

#[tokio::test]
async fn test_user_has_community_dashboard_permission_allows_request() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::Read);
    db.expect_update_session().times(0);

    // Setup router and send request
    let router = setup_community_dashboard_router(db).await;
    let (parts, bytes) = send(router, get_request("/protected", ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_user_has_community_dashboard_permission_allows_matching_loaded_context() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::Read);
    db.expect_update_session().times(0);

    // Setup router and send request declaring the loaded community
    let router = setup_community_dashboard_router(db).await;
    let request = authenticated_request("GET", "/protected", ids.session_id)
        .header(SELECTED_COMMUNITY_ID_HEADER, ids.community_id.to_string())
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the protected handler ran
    assert_empty_response(&parts, &bytes, StatusCode::OK);
    assert!(!parts.headers.contains_key(STALE_DASHBOARD_CONTEXT_HEADER));
}

#[tokio::test]
async fn test_user_has_community_dashboard_permission_forbidden_when_not_logged_in() {
    // Setup an anonymous session with a selected community
    let ids = DashboardIds::new();
    let mut session_record = sample_empty_session_record(ids.session_id);
    session_record.data.insert(
        SELECTED_COMMUNITY_ID_KEY.to_string(),
        json!(ids.community_id),
    );
    let mut db = MockDB::new();
    expect_stored_session(&mut db, session_record);

    // Setup router and send request
    let router = setup_community_dashboard_router(db).await;
    let (parts, bytes) = send(router, get_request("/protected", ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_user_has_community_dashboard_permission_redirects_when_context_is_missing_and_unavailable()
 {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(|_| Ok(vec![]));
    db.expect_update_session().times(0);

    // Setup router and send request
    let router = setup_community_dashboard_router(db).await;
    let (parts, bytes) = send(router, get_request("/protected", ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL)),
    );
}

#[tokio::test]
async fn test_user_has_community_dashboard_permission_redirects_when_selected_context_is_stale_and_unavailable()
 {
    // Setup a stale selection with no readable replacement community
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_session(&mut db, &ids);
    expect_community_permission_result(&mut db, &ids, CommunityPermission::Read, false);
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(|_| Ok(vec![]));
    db.expect_update_session().times(0);
    db.expect_delete_session().times(0);

    // Setup router and send request
    let router = setup_community_dashboard_router(db).await;
    let (parts, bytes) = send(router, get_request("/protected", ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL)),
    );
}

#[tokio::test]
async fn test_user_has_community_dashboard_permission_refreshes_stale_loaded_context_after_repair()
{
    // Setup a stale selection and a readable replacement community
    let ids = DashboardIds::new();
    let accessible = DashboardIds {
        community_id: Uuid::new_v4(),
        ..ids
    };
    let communities = vec![sample_community_summary(accessible.community_id)];
    let mut db = MockDB::new();
    expect_community_session(&mut db, &ids);
    expect_community_permission_result(&mut db, &ids, CommunityPermission::Read, false);
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(move |_| Ok(communities.clone()));
    expect_community_permission_result(&mut db, &accessible, CommunityPermission::Read, true);
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(|_| Ok(vec![]));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id && session_selects(record, accessible.community_id, None)
        })
        .returning(|_| Ok(()));

    // Setup router and send request declaring the stale community
    let router = setup_community_dashboard_router(db).await;
    let request = authenticated_request("GET", "/protected", ids.session_id)
        .header(SELECTED_COMMUNITY_ID_HEADER, ids.community_id.to_string())
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the client is told to reload instead of reaching the handler
    assert_stale_dashboard_context_response(&parts, &bytes);
}

#[tokio::test]
async fn test_user_has_community_dashboard_permission_returns_error_on_db_failure() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_session(&mut db, &ids);
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == ids.community_id
                && *uid == ids.user_id
                && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Err(anyhow!("db error")));
    db.expect_update_session().times(0);

    // Setup router and send request
    let router = setup_community_dashboard_router(db).await;
    let (parts, bytes) = send(router, get_request("/protected", ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

// Path community middleware.

#[tokio::test]
async fn test_user_has_path_community_permission_allows_request() {
    // Setup identifiers and a check for the configured permission
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    expect_community_permission_result(&mut db, &ids, CommunityPermission::TeamWrite, true);

    // Setup router and send request
    let router = setup_path_community_router(db, CommunityPermission::TeamWrite).await;
    let uri = format!("/{}/select", ids.community_id);
    let (parts, bytes) = send(router, get_request(&uri, ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_user_has_path_community_permission_forbidden_when_not_logged_in() {
    // Setup an anonymous session
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_stored_session(&mut db, sample_empty_session_record(ids.session_id));

    // Setup router and send request
    let router = setup_path_community_router(db, CommunityPermission::Read).await;
    let uri = format!("/{}/select", ids.community_id);
    let (parts, bytes) = send(router, get_request(&uri, ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_user_has_path_community_permission_forbidden_without_permission() {
    // Setup identifiers and a denied permission check
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    expect_community_permission_result(&mut db, &ids, CommunityPermission::Read, false);

    // Setup router and send request
    let router = setup_path_community_router(db, CommunityPermission::Read).await;
    let uri = format!("/{}/select", ids.community_id);
    let (parts, bytes) = send(router, get_request(&uri, ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_user_has_path_community_permission_returns_error_on_db_failure() {
    // Setup identifiers and a failing permission check
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == ids.community_id
                && *uid == ids.user_id
                && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Err(anyhow!("db error")));

    // Setup router and send request
    let router = setup_path_community_router(db, CommunityPermission::Read).await;
    let uri = format!("/{}/select", ids.community_id);
    let (parts, bytes) = send(router, get_request(&uri, ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

// Path group middleware.

#[tokio::test]
async fn test_user_has_path_group_permission_allows_request() {
    // Setup identifiers and a check for the configured permission
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_session(&mut db, &ids);
    db.expect_group_belongs_to_community()
        .times(1)
        .withf(move |cid, gid| *cid == ids.community_id && *gid == ids.group_id)
        .returning(|_, _| Ok(true));
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);

    // Setup router and send request
    let router = setup_path_group_router(db, GroupPermission::EventsWrite).await;
    let uri = format!("/{}/select", ids.group_id);
    let (parts, bytes) = send(router, get_request(&uri, ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_user_has_path_group_permission_forbidden_when_group_is_outside_selected_community() {
    // Setup identifiers and a group outside the selected community
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_session(&mut db, &ids);
    db.expect_group_belongs_to_community()
        .times(1)
        .withf(move |cid, gid| *cid == ids.community_id && *gid == ids.group_id)
        .returning(|_, _| Ok(false));

    // Setup router and send request
    let router = setup_path_group_router(db, GroupPermission::Read).await;
    let uri = format!("/{}/select", ids.group_id);
    let (parts, bytes) = send(router, get_request(&uri, ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_user_has_path_group_permission_forbidden_when_not_logged_in() {
    // Setup an anonymous session with a selected community
    let ids = DashboardIds::new();
    let mut session_record = sample_empty_session_record(ids.session_id);
    session_record.data.insert(
        SELECTED_COMMUNITY_ID_KEY.to_string(),
        json!(ids.community_id),
    );
    let mut db = MockDB::new();
    expect_stored_session(&mut db, session_record);

    // Setup router and send request
    let router = setup_path_group_router(db, GroupPermission::Read).await;
    let uri = format!("/{}/select", ids.group_id);
    let (parts, bytes) = send(router, get_request(&uri, ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_user_has_path_group_permission_forbidden_without_permission() {
    // Setup identifiers and a denied check for the configured permission
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_session(&mut db, &ids);
    db.expect_group_belongs_to_community()
        .times(1)
        .withf(move |cid, gid| *cid == ids.community_id && *gid == ids.group_id)
        .returning(|_, _| Ok(true));
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, false);

    // Setup router and send request
    let router = setup_path_group_router(db, GroupPermission::EventsWrite).await;
    let uri = format!("/{}/select", ids.group_id);
    let (parts, bytes) = send(router, get_request(&uri, ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_user_has_path_group_permission_redirects_when_selected_community_is_missing() {
    // Setup an authenticated session without selected community context
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);

    // Setup router and send request
    let router = setup_path_group_router(db, GroupPermission::Read).await;
    let uri = format!("/{}/select", ids.group_id);
    let (parts, bytes) = send(router, get_request(&uri, ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL)),
    );
}

#[tokio::test]
async fn test_user_has_path_group_permission_returns_error_on_db_failure() {
    // Setup identifiers and a failing permission check
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_session(&mut db, &ids);
    db.expect_group_belongs_to_community()
        .times(1)
        .withf(move |cid, gid| *cid == ids.community_id && *gid == ids.group_id)
        .returning(|_, _| Ok(true));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == ids.community_id
                && *gid == ids.group_id
                && *uid == ids.user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Err(anyhow!("db error")));

    // Setup router and send request
    let router = setup_path_group_router(db, GroupPermission::Read).await;
    let uri = format!("/{}/select", ids.group_id);
    let (parts, bytes) = send(router, get_request(&uri, ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_user_has_path_group_permission_returns_error_when_group_membership_check_fails() {
    // Setup identifiers and a failing group membership check
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_session(&mut db, &ids);
    db.expect_group_belongs_to_community()
        .times(1)
        .withf(move |cid, gid| *cid == ids.community_id && *gid == ids.group_id)
        .returning(|_, _| Err(anyhow!("db error")));

    // Setup router and send request
    let router = setup_path_group_router(db, GroupPermission::Read).await;
    let uri = format!("/{}/select", ids.group_id);
    let (parts, bytes) = send(router, get_request(&uri, ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

// Selected community middleware.

#[tokio::test]
async fn test_user_has_selected_community_permission_allows_request() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::Read);

    // Setup router and send request
    let router = setup_selected_community_router(db, CommunityPermission::Read).await;
    let (parts, bytes) = send(router, get_request("/protected", ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_user_has_selected_community_permission_forbidden_when_not_logged_in() {
    // Setup an anonymous session with a selected community
    let ids = DashboardIds::new();
    let mut session_record = sample_empty_session_record(ids.session_id);
    session_record.data.insert(
        SELECTED_COMMUNITY_ID_KEY.to_string(),
        json!(ids.community_id),
    );
    let mut db = MockDB::new();
    expect_stored_session(&mut db, session_record);

    // Setup router and send request
    let router = setup_selected_community_router(db, CommunityPermission::Read).await;
    let (parts, bytes) = send(router, get_request("/protected", ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_user_has_selected_community_permission_forbidden_without_permission() {
    // Setup a readable selection without the write permission the route needs
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_session(&mut db, &ids);
    db.expect_user_has_community_permission()
        .times(2)
        .withf(move |cid, uid, permission| {
            *cid == ids.community_id
                && *uid == ids.user_id
                && matches!(
                    permission,
                    CommunityPermission::Read | CommunityPermission::TeamWrite
                )
        })
        .returning(|_, _, permission| Ok(permission == CommunityPermission::Read));
    db.expect_delete_session().times(0);

    // Setup router and send request
    let router = setup_selected_community_router(db, CommunityPermission::TeamWrite).await;
    let (parts, bytes) = send(router, get_request("/protected", ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_user_has_selected_community_permission_redirects_when_context_is_missing_and_unavailable()
 {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(|_| Ok(vec![]));
    db.expect_update_session().times(0);

    // Setup router and send request
    let router = setup_selected_community_router(db, CommunityPermission::Read).await;
    let (parts, bytes) = send(router, get_request("/protected", ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL)),
    );
}

#[tokio::test]
async fn test_user_has_selected_community_permission_refreshes_stale_loaded_context_before_forbidding_write()
 {
    // Setup a readable selection without the write permission the route needs
    let ids = DashboardIds::new();
    let loaded_community_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_community_session(&mut db, &ids);
    expect_community_permission_result(&mut db, &ids, CommunityPermission::TeamWrite, false);
    expect_community_permission_result(&mut db, &ids, CommunityPermission::Read, true);
    db.expect_update_session().times(0);

    // Setup router and send an action from a page rendered for another community
    let router = setup_selected_community_router(db, CommunityPermission::TeamWrite).await;
    let request = authenticated_request("GET", "/protected", ids.session_id)
        .header(
            SELECTED_COMMUNITY_ID_HEADER,
            loaded_community_id.to_string(),
        )
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the stale page is refreshed instead of receiving a forbidden error
    assert_stale_dashboard_context_response(&parts, &bytes);
}

#[tokio::test]
async fn test_user_has_selected_community_permission_refreshes_when_loaded_community_differs() {
    // Setup a valid selection that differs from the loaded page
    let ids = DashboardIds::new();
    let loaded_community_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::Read);
    db.expect_update_session().times(0);

    // Setup router and send request declaring another community
    let router = setup_selected_community_router(db, CommunityPermission::Read).await;
    let request = authenticated_request("GET", "/protected", ids.session_id)
        .header(
            SELECTED_COMMUNITY_ID_HEADER,
            loaded_community_id.to_string(),
        )
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the client is told to reload instead of reaching the handler
    assert_stale_dashboard_context_response(&parts, &bytes);
}

#[tokio::test]
async fn test_user_has_selected_community_permission_repairs_missing_context() {
    // Setup a session without selection and a readable community and group
    let ids = DashboardIds::new();
    let groups = sample_user_groups_by_community(ids.community_id, ids.group_id);
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(move |_| Ok(vec![sample_community_summary(ids.community_id)]));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(move |_| Ok(groups.clone()));
    expect_community_permission_result(&mut db, &ids, CommunityPermission::Read, true);
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id
                && session_selects(record, ids.community_id, Some(ids.group_id))
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = setup_selected_community_router(db, CommunityPermission::Read).await;
    let (parts, bytes) = send(router, get_request("/protected", ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_user_has_selected_community_permission_repairs_stale_context_before_forbidding_write()
{
    // Setup a stale selection and a readable replacement without write access
    let ids = DashboardIds::new();
    let accessible = DashboardIds {
        community_id: Uuid::new_v4(),
        ..ids
    };
    let mut db = MockDB::new();
    expect_group_session(&mut db, &ids);
    expect_community_permission_result(&mut db, &ids, CommunityPermission::TeamWrite, false);
    expect_community_permission_result(&mut db, &ids, CommunityPermission::Read, false);
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(move |_| Ok(vec![sample_community_summary(accessible.community_id)]));
    expect_community_permission_result(&mut db, &accessible, CommunityPermission::Read, true);
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(|_| Ok(vec![]));
    expect_community_permission_result(&mut db, &accessible, CommunityPermission::TeamWrite, false);
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id && session_selects(record, accessible.community_id, None)
        })
        .returning(|_| Ok(()));
    db.expect_delete_session().times(0);

    // Setup router with a community write requirement and send request
    let router = setup_selected_community_router(db, CommunityPermission::TeamWrite).await;
    let (parts, bytes) = send(router, get_request("/protected", ids.session_id)).await;

    // Check repair is persisted before write access is denied
    assert_empty_response(&parts, &bytes, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_user_has_selected_community_permission_returns_error_on_db_failure() {
    // Setup identifiers and a failing permission check
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_session(&mut db, &ids);
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == ids.community_id
                && *uid == ids.user_id
                && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Err(anyhow!("db error")));

    // Setup router and send request
    let router = setup_selected_community_router(db, CommunityPermission::Read).await;
    let (parts, bytes) = send(router, get_request("/protected", ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

// Selected group middleware.

#[tokio::test]
async fn test_user_has_selected_group_permission_allows_request() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);

    // Setup router and send request
    let router = setup_selected_group_router(db, GroupPermission::Read).await;
    let (parts, bytes) = send(router, get_request("/protected", ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_user_has_selected_group_permission_allows_matching_loaded_context() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    db.expect_update_session().times(0);

    // Setup router and send request declaring the loaded community and group
    let router = setup_selected_group_router(db, GroupPermission::Read).await;
    let request = authenticated_request("GET", "/protected", ids.session_id)
        .header(SELECTED_COMMUNITY_ID_HEADER, ids.community_id.to_string())
        .header(SELECTED_GROUP_ID_HEADER, ids.group_id.to_string())
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the protected handler ran
    assert_empty_response(&parts, &bytes, StatusCode::OK);
    assert!(!parts.headers.contains_key(STALE_DASHBOARD_CONTEXT_HEADER));
}

#[tokio::test]
async fn test_user_has_selected_group_permission_forbidden_when_not_logged_in() {
    // Setup an anonymous session with a selected community and group
    let ids = DashboardIds::new();
    let mut session_record = sample_empty_session_record(ids.session_id);
    session_record.data.insert(
        SELECTED_COMMUNITY_ID_KEY.to_string(),
        json!(ids.community_id),
    );
    session_record
        .data
        .insert(SELECTED_GROUP_ID_KEY.to_string(), json!(ids.group_id));
    let mut db = MockDB::new();
    expect_stored_session(&mut db, session_record);

    // Setup router and send request
    let router = setup_selected_group_router(db, GroupPermission::Read).await;
    let (parts, bytes) = send(router, get_request("/protected", ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_user_has_selected_group_permission_forbidden_without_permission() {
    // Setup a readable selection without the write permission the route needs
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_session(&mut db, &ids);
    db.expect_user_has_group_permission()
        .times(2)
        .withf(move |cid, gid, uid, permission| {
            *cid == ids.community_id
                && *gid == ids.group_id
                && *uid == ids.user_id
                && matches!(
                    permission,
                    GroupPermission::Read | GroupPermission::TeamWrite
                )
        })
        .returning(|_, _, _, permission| Ok(permission == GroupPermission::Read));
    db.expect_delete_session().times(0);

    // Setup router and send request
    let router = setup_selected_group_router(db, GroupPermission::TeamWrite).await;
    let (parts, bytes) = send(router, get_request("/protected", ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_user_has_selected_group_permission_redirects_when_context_is_missing_and_unavailable()
{
    // Setup a selected community without groups the user can read
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_session(&mut db, &ids);
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(|_| Ok(vec![]));
    db.expect_update_session().times(0);

    // Setup router and send request
    let router = setup_selected_group_router(db, GroupPermission::Read).await;
    let (parts, bytes) = send(router, get_request("/protected", ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL)),
    );
}

#[tokio::test]
async fn test_user_has_selected_group_permission_redirects_when_selected_group_is_stale_and_unavailable()
 {
    // Setup a stale group selection with no readable replacement
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_session(&mut db, &ids);
    expect_group_permission_result(&mut db, &ids, GroupPermission::Read, false);
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(|_| Ok(vec![]));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id && session_selects(record, ids.community_id, None)
        })
        .returning(|_| Ok(()));
    db.expect_delete_session().times(0);

    // Setup router and send request
    let router = setup_selected_group_router(db, GroupPermission::Read).await;
    let (parts, bytes) = send(router, get_request("/protected", ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL)),
    );
}

#[tokio::test]
async fn test_user_has_selected_group_permission_refreshes_stale_loaded_context_after_repair() {
    // Setup a stale group selection and a readable replacement group
    let ids = DashboardIds::new();
    let replacement = DashboardIds {
        group_id: Uuid::new_v4(),
        ..ids
    };
    let groups = sample_user_groups_by_community(ids.community_id, replacement.group_id);
    let mut db = MockDB::new();
    expect_group_session(&mut db, &ids);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::Read, false);
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(move |_| Ok(groups.clone()));
    expect_group_permission_result(&mut db, &replacement, GroupPermission::Read, true);
    expect_group_permission_result(&mut db, &replacement, GroupPermission::EventsWrite, true);
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id
                && session_selects(record, ids.community_id, Some(replacement.group_id))
        })
        .returning(|_| Ok(()));

    // Setup router and send an action from the page rendered for the stale group
    let router = setup_selected_group_router(db, GroupPermission::EventsWrite).await;
    let request = authenticated_request("GET", "/protected", ids.session_id)
        .header(SELECTED_COMMUNITY_ID_HEADER, ids.community_id.to_string())
        .header(SELECTED_GROUP_ID_HEADER, ids.group_id.to_string())
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the repaired selection is persisted but the action never runs
    assert_stale_dashboard_context_response(&parts, &bytes);
}

#[tokio::test]
async fn test_user_has_selected_group_permission_refreshes_stale_loaded_context_before_forbidding_write()
 {
    // Setup a readable selection without the write permission the route needs
    let ids = DashboardIds::new();
    let loaded_group_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_session(&mut db, &ids);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::Read, true);
    db.expect_update_session().times(0);

    // Setup router and send an action from a page rendered for another group
    let router = setup_selected_group_router(db, GroupPermission::EventsWrite).await;
    let request = authenticated_request("GET", "/protected", ids.session_id)
        .header(SELECTED_COMMUNITY_ID_HEADER, ids.community_id.to_string())
        .header(SELECTED_GROUP_ID_HEADER, loaded_group_id.to_string())
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the stale page is refreshed instead of receiving a forbidden error
    assert_stale_dashboard_context_response(&parts, &bytes);
}

#[tokio::test]
async fn test_user_has_selected_group_permission_refreshes_when_loaded_group_differs() {
    // Setup a valid selection that differs from the loaded page
    let ids = DashboardIds::new();
    let loaded_group_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    db.expect_update_session().times(0);

    // Setup router and send request declaring another group
    let router = setup_selected_group_router(db, GroupPermission::Read).await;
    let request = authenticated_request("GET", "/protected", ids.session_id)
        .header(SELECTED_COMMUNITY_ID_HEADER, ids.community_id.to_string())
        .header(SELECTED_GROUP_ID_HEADER, loaded_group_id.to_string())
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the client is told to reload instead of reaching the handler
    assert_stale_dashboard_context_response(&parts, &bytes);
}

#[tokio::test]
async fn test_user_has_selected_group_permission_refreshes_when_loaded_group_is_unparsable() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    db.expect_update_session().times(0);

    // Setup router and send request with an invalid group header
    let router = setup_selected_group_router(db, GroupPermission::Read).await;
    let request = authenticated_request("GET", "/protected", ids.session_id)
        .header(SELECTED_COMMUNITY_ID_HEADER, ids.community_id.to_string())
        .header(SELECTED_GROUP_ID_HEADER, "not-a-uuid")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the client is told to reload instead of reaching the handler
    assert_stale_dashboard_context_response(&parts, &bytes);
}

#[tokio::test]
async fn test_user_has_selected_group_permission_repairs_missing_context() {
    // Setup a session without selection and a readable group
    let ids = DashboardIds::new();
    let groups = sample_user_groups_by_community(ids.community_id, ids.group_id);
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(move |_| Ok(groups.clone()));
    expect_group_permission_result(&mut db, &ids, GroupPermission::Read, true);
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id
                && session_selects(record, ids.community_id, Some(ids.group_id))
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = setup_selected_group_router(db, GroupPermission::Read).await;
    let (parts, bytes) = send(router, get_request("/protected", ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_user_has_selected_group_permission_repairs_stale_context_before_forbidding_write() {
    // Setup a stale group selection and a readable replacement without write access
    let ids = DashboardIds::new();
    let replacement = DashboardIds {
        group_id: Uuid::new_v4(),
        ..ids
    };
    let groups = sample_user_groups_by_community(ids.community_id, replacement.group_id);
    let mut db = MockDB::new();
    expect_group_session(&mut db, &ids);
    expect_group_permission_result(&mut db, &ids, GroupPermission::TeamWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::Read, false);
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(move |_| Ok(groups.clone()));
    expect_group_permission_result(&mut db, &replacement, GroupPermission::Read, true);
    expect_group_permission_result(&mut db, &replacement, GroupPermission::TeamWrite, false);
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id
                && session_selects(record, ids.community_id, Some(replacement.group_id))
        })
        .returning(|_| Ok(()));
    db.expect_delete_session().times(0);

    // Setup router with a group write requirement and send request
    let router = setup_selected_group_router(db, GroupPermission::TeamWrite).await;
    let (parts, bytes) = send(router, get_request("/protected", ids.session_id)).await;

    // Check repair is persisted before write access is denied
    assert_empty_response(&parts, &bytes, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_user_has_selected_group_permission_returns_error_on_db_failure() {
    // Setup identifiers and a failing permission check
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_session(&mut db, &ids);
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == ids.community_id
                && *gid == ids.group_id
                && *uid == ids.user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Err(anyhow!("db error")));

    // Setup router and send request
    let router = setup_selected_group_router(db, GroupPermission::Read).await;
    let (parts, bytes) = send(router, get_request("/protected", ids.session_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

// Redirect builders.

#[tokio::test]
async fn test_redirect_to_invitations_for_request_matches_request_type() {
    // Setup request types and the redirect each one expects
    let cases = [
        ("page", None, StatusCode::SEE_OTHER, LOCATION.as_str()),
        ("htmx", Some("hx-request"), StatusCode::OK, "HX-Redirect"),
        (
            "ocg fetch",
            Some("x-ocg-fetch"),
            StatusCode::OK,
            "X-OCG-Redirect",
        ),
    ];

    for (case, request_header, expected_status, redirect_header) in cases {
        // Build the redirect for the request headers
        let mut headers = HeaderMap::new();
        if let Some(name) = request_header {
            headers.insert(name, HeaderValue::from_static("true"));
        }
        let (parts, body) = redirect_to_invitations_for_request(&headers).into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, expected_status, "{case}");
        assert_eq!(
            parts.headers.get(redirect_header),
            Some(&HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL)),
            "{case}",
        );
        assert!(bytes.is_empty(), "{case}");
    }
}

#[tokio::test]
async fn test_redirect_to_log_in_for_request_matches_request_type() {
    // Setup request types and the redirect each one expects
    let cases = [
        ("page", None, StatusCode::SEE_OTHER, LOCATION.as_str()),
        ("htmx", Some("hx-request"), StatusCode::OK, "HX-Redirect"),
        (
            "ocg fetch",
            Some("x-ocg-fetch"),
            StatusCode::UNAUTHORIZED,
            "X-OCG-Redirect",
        ),
    ];

    for (case, request_header, expected_status, redirect_header) in cases {
        // Build the redirect for the request headers
        let mut headers = HeaderMap::new();
        if let Some(name) = request_header {
            headers.insert(name, HeaderValue::from_static("true"));
        }
        let (parts, body) = redirect_to_log_in_for_request(&headers).into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, expected_status, "{case}");
        assert_eq!(
            parts.headers.get(redirect_header),
            Some(&HeaderValue::from_static(LOG_IN_URL)),
            "{case}",
        );
        assert!(bytes.is_empty(), "{case}");
    }
}

// Helpers.

/// Asserts the response is the empty stale dashboard context refresh intercept.
fn assert_stale_dashboard_context_response(parts: &Parts, bytes: &[u8]) {
    assert_empty_response(parts, bytes, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL),
        Some(&HeaderValue::from_static(CACHE_CONTROL_NO_STORE)),
    );
    assert_eq!(
        parts.headers.get(STALE_DASHBOARD_CONTEXT_HEADER),
        Some(&HeaderValue::from_static("true")),
    );
}

/// Wraps the routes with the real auth layer and the test state.
async fn protected_router(db: DynDB, routes: Router<router::State>) -> Router {
    let server_cfg = HttpServerConfig::default();
    let state = test_state(
        db.clone(),
        Arc::new(MockImageStorage::new()),
        Arc::new(MockNotificationsManager::new()),
    );
    let auth_layer = crate::auth::setup_layer(&server_cfg, BlockingExecutor::new(1), db)
        .await
        .unwrap();

    routes.layer(auth_layer).with_state(state)
}

/// Returns whether the stored session selects exactly the community and group.
fn session_selects(record: &session::Record, community_id: Uuid, group_id: Option<Uuid>) -> bool {
    record.data.get(SELECTED_COMMUNITY_ID_KEY) == Some(&json!(community_id))
        && record.data.get(SELECTED_GROUP_ID_KEY) == group_id.map(|id| json!(id)).as_ref()
}

/// Builds a router protecting `/protected` with the community dashboard middleware.
async fn setup_community_dashboard_router(db: MockDB) -> Router {
    let db: DynDB = Arc::new(db);
    let routes = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            db.clone(),
            user_has_community_dashboard_permission,
        ));

    protected_router(db, routes).await
}

/// Builds a router protecting `/{community_id}/select` with the path community middleware.
async fn setup_path_community_router(db: MockDB, permission: CommunityPermission) -> Router {
    let db: DynDB = Arc::new(db);
    let routes = Router::new()
        .route("/{community_id}/select", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), permission),
            user_has_path_community_permission,
        ));

    protected_router(db, routes).await
}

/// Builds a router protecting `/{group_id}/select` with the path group middleware.
async fn setup_path_group_router(db: MockDB, permission: GroupPermission) -> Router {
    let db: DynDB = Arc::new(db);
    let routes = Router::new()
        .route("/{group_id}/select", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), permission),
            user_has_path_group_permission,
        ));

    protected_router(db, routes).await
}

/// Builds a router protecting `/protected` with the selected community middleware.
async fn setup_selected_community_router(db: MockDB, permission: CommunityPermission) -> Router {
    let db: DynDB = Arc::new(db);
    let routes = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), permission),
            user_has_selected_community_permission,
        ));

    protected_router(db, routes).await
}

/// Builds a router protecting `/protected` with the selected group middleware.
async fn setup_selected_group_router(db: MockDB, permission: GroupPermission) -> Router {
    let db: DynDB = Arc::new(db);
    let routes = Router::new()
        .route("/protected", get(|| async { StatusCode::OK }))
        .layer(middleware::from_fn_with_state(
            (db.clone(), permission),
            user_has_selected_group_permission,
        ));

    protected_router(db, routes).await
}
