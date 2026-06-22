use anyhow::anyhow;
use axum::{
    body::{Body, to_bytes},
    http::{
        Request, StatusCode,
        header::{CONTENT_TYPE, COOKIE, HOST},
    },
};
use axum_login::tower_sessions::session;
use serde_json::json;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::{common::SearchGroupsOutput, mock::MockDB},
    handlers::{auth::SELECTED_GROUP_ID_KEY, tests::*},
    services::notifications::MockNotificationsManager,
    templates::dashboard::DASHBOARD_PAGINATION_LIMIT,
    types::permissions::AlliancePermission,
};

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record =
        sample_session_record(session_id, user_id, &auth_hash, Some(alliance_id), None);
    let ts_query = "rust".to_string();
    let groups_output = SearchGroupsOutput {
        groups: vec![sample_group_summary(group_id)],
        ..Default::default()
    };

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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id && *uid == user_id && permission == AlliancePermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id
                && *uid == user_id
                && permission == AlliancePermission::GroupsWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_get_alliance_name_by_id()
        .times(1)
        .withf(move |id| *id == alliance_id)
        .returning(|_| Ok(Some("test".to_string())));
    db.expect_search_groups()
        .times(1)
        .withf({
            let ts_query = ts_query.clone();
            move |filters| {
                filters.alliance == vec!["test".to_string()]
                    && filters.include_inactive == Some(true)
                    && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                    && filters.sort_by.as_deref() == Some("name")
                    && filters.ts_query.as_deref() == Some(ts_query.as_str())
            }
        })
        .returning(move |_| Ok(groups_output.clone()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/dashboard/alliance/groups?ts_query={ts_query}"))
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_list_page_db_error() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record =
        sample_session_record(session_id, user_id, &auth_hash, Some(alliance_id), None);

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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id && *uid == user_id && permission == AlliancePermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id
                && *uid == user_id
                && permission == AlliancePermission::GroupsWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_get_alliance_name_by_id()
        .times(1)
        .withf(move |id| *id == alliance_id)
        .returning(|_| Ok(Some("test".to_string())));
    db.expect_search_groups()
        .times(1)
        .withf(move |filters| {
            filters.alliance == vec!["test".to_string()]
                && filters.include_inactive == Some(true)
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
        })
        .returning(move |_| Err(anyhow!("db error")));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/alliance/groups")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_add_page_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record =
        sample_session_record(session_id, user_id, &auth_hash, Some(alliance_id), None);
    let categories = vec![sample_group_category()];
    let regions = vec![sample_group_region()];

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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id && *uid == user_id && permission == AlliancePermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id
                && *uid == user_id
                && permission == AlliancePermission::GroupsWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_list_group_categories()
        .times(1)
        .withf(move |cid| *cid == alliance_id)
        .returning(move |_| Ok(categories.clone()));
    db.expect_list_regions()
        .times(1)
        .withf(move |cid| *cid == alliance_id)
        .returning(move |_| Ok(regions.clone()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/alliance/groups/add")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_add_page_db_error() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record =
        sample_session_record(session_id, user_id, &auth_hash, Some(alliance_id), None);

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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id && *uid == user_id && permission == AlliancePermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id
                && *uid == user_id
                && permission == AlliancePermission::GroupsWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_list_group_categories()
        .times(1)
        .withf(move |cid| *cid == alliance_id)
        .returning(move |_| Err(anyhow!("db error")));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/alliance/groups/add")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_update_page_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record =
        sample_session_record(session_id, user_id, &auth_hash, Some(alliance_id), None);
    let categories = vec![sample_group_category()];
    let regions = vec![sample_group_region()];
    let group_full = sample_group_full(alliance_id, group_id);

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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id && *uid == user_id && permission == AlliancePermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id
                && *uid == user_id
                && permission == AlliancePermission::GroupsWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_get_group_full()
        .times(1)
        .withf(move |cid, gid| *cid == alliance_id && *gid == group_id)
        .returning(move |_, _| Ok(group_full.clone()));
    db.expect_list_group_categories()
        .times(1)
        .withf(move |cid| *cid == alliance_id)
        .returning(move |_| Ok(categories.clone()));
    db.expect_list_regions()
        .times(1)
        .withf(move |cid| *cid == alliance_id)
        .returning(move |_| Ok(regions.clone()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/dashboard/alliance/groups/{group_id}/update"))
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_update_page_db_error() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record =
        sample_session_record(session_id, user_id, &auth_hash, Some(alliance_id), None);

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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id && *uid == user_id && permission == AlliancePermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id
                && *uid == user_id
                && permission == AlliancePermission::GroupsWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_get_group_full()
        .times(1)
        .withf(move |cid, gid| *cid == alliance_id && *gid == group_id)
        .returning(move |_, _| Err(anyhow!("db error")));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/dashboard/alliance/groups/{group_id}/update"))
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_add_success_auto_selects_group() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let category_id = Uuid::new_v4();
    let new_group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record =
        sample_session_record(session_id, user_id, &auth_hash, Some(alliance_id), None);
    let body = serde_qs::to_string(&sample_group_form(category_id)).unwrap();

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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id
                && *uid == user_id
                && permission == AlliancePermission::GroupsWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_add_group()
        .times(1)
        .withf(move |uid, cid, group| {
            *uid == user_id
                && *cid == alliance_id
                && group.name == "Test Group"
                && group.category_id == category_id
                && group.description == "Group description"
        })
        .returning(move |_, _, _| Ok(new_group_id));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == session_id
                && record
                    .data
                    .get(SELECTED_GROUP_ID_KEY)
                    .is_some_and(|value| value == &json!(new_group_id))
        })
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("POST")
        .uri("/dashboard/alliance/groups/add")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::CREATED,
        "refresh-alliance-dashboard-table",
    );
}

#[tokio::test]
async fn test_add_success_keeps_existing_group_selection() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let category_id = Uuid::new_v4();
    let existing_group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(alliance_id),
        Some(existing_group_id),
    );
    let body = serde_qs::to_string(&sample_group_form(category_id)).unwrap();

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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id
                && *uid == user_id
                && permission == AlliancePermission::GroupsWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_add_group()
        .times(1)
        .withf(move |uid, cid, group| {
            *uid == user_id && *cid == alliance_id && group.category_id == category_id
        })
        .returning(|_, _, _| Ok(Uuid::new_v4()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("POST")
        .uri("/dashboard/alliance/groups/add")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::CREATED,
        "refresh-alliance-dashboard-table",
    );
}

#[tokio::test]
async fn test_add_invalid_payload() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record =
        sample_session_record(session_id, user_id, &auth_hash, Some(alliance_id), None);

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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id
                && *uid == user_id
                && permission == AlliancePermission::GroupsWrite
        })
        .returning(|_, _, _| Ok(true));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("POST")
        .uri("/dashboard/alliance/groups/add")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from("invalid-body"))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_non_empty_response(&parts, &bytes, StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_add_db_error() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let category_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record =
        sample_session_record(session_id, user_id, &auth_hash, Some(alliance_id), None);
    let body = serde_qs::to_string(&sample_group_form(category_id)).unwrap();

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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id
                && *uid == user_id
                && permission == AlliancePermission::GroupsWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_add_group()
        .times(1)
        .withf(move |uid, cid, group| {
            *uid == user_id && *cid == alliance_id && group.category_id == category_id
        })
        .returning(move |_, _, _| Err(anyhow!("db error")));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("POST")
        .uri("/dashboard/alliance/groups/add")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_update_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let category_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record =
        sample_session_record(session_id, user_id, &auth_hash, Some(alliance_id), None);
    let body = serde_qs::to_string(&sample_group_form(category_id)).unwrap();

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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id
                && *uid == user_id
                && permission == AlliancePermission::GroupsWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_update_group()
        .times(1)
        .withf(move |uid, cid, gid, group| {
            *uid == user_id
                && *cid == alliance_id
                && *gid == group_id
                && group.category_id == category_id
        })
        .returning(|_, _, _, _| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/alliance/groups/{group_id}/update"))
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-alliance-dashboard-table",
    );
}

#[tokio::test]
async fn test_update_invalid_payload() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record =
        sample_session_record(session_id, user_id, &auth_hash, Some(alliance_id), None);

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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id
                && *uid == user_id
                && permission == AlliancePermission::GroupsWrite
        })
        .returning(|_, _, _| Ok(true));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/alliance/groups/{group_id}/update"))
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from("invalid-body"))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_non_empty_response(&parts, &bytes, StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_update_db_error() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let category_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record =
        sample_session_record(session_id, user_id, &auth_hash, Some(alliance_id), None);
    let body = serde_qs::to_string(&sample_group_form(category_id)).unwrap();

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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id
                && *uid == user_id
                && permission == AlliancePermission::GroupsWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_update_group()
        .times(1)
        .withf(move |uid, cid, gid, group| {
            *uid == user_id
                && *cid == alliance_id
                && *gid == group_id
                && group.category_id == category_id
        })
        .returning(move |_, _, _, _| Err(anyhow!("db error")));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/alliance/groups/{group_id}/update"))
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_activate_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record =
        sample_session_record(session_id, user_id, &auth_hash, Some(alliance_id), None);

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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id
                && *uid == user_id
                && permission == AlliancePermission::GroupsWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_activate_group()
        .times(1)
        .withf(move |uid, cid, gid| *uid == user_id && *cid == alliance_id && *gid == group_id)
        .returning(move |_, _, _| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/alliance/groups/{group_id}/activate"))
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-alliance-dashboard-table",
    );
}

#[tokio::test]
async fn test_deactivate_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record =
        sample_session_record(session_id, user_id, &auth_hash, Some(alliance_id), None);

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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id
                && *uid == user_id
                && permission == AlliancePermission::GroupsWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_deactivate_group()
        .times(1)
        .withf(move |uid, cid, gid| *uid == user_id && *cid == alliance_id && *gid == group_id)
        .returning(move |_, _, _| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/alliance/groups/{group_id}/deactivate"))
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-alliance-dashboard-table",
    );
}

#[tokio::test]
async fn test_delete_non_selected_group() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let other_group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(alliance_id),
        Some(other_group_id),
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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id
                && *uid == user_id
                && permission == AlliancePermission::GroupsWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_delete_group()
        .times(1)
        .withf(move |uid, cid, gid| *uid == user_id && *cid == alliance_id && *gid == group_id)
        .returning(move |_, _, _| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!("/dashboard/alliance/groups/{group_id}/delete"))
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-alliance-dashboard-table",
    );
}

#[tokio::test]
async fn test_delete_selected_group_updates_selection() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let next_group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(alliance_id),
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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id
                && *uid == user_id
                && permission == AlliancePermission::GroupsWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_delete_group()
        .times(1)
        .withf(move |uid, cid, gid| *uid == user_id && *cid == alliance_id && *gid == group_id)
        .returning(move |_, _, _| Ok(()));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(sample_user_groups_by_alliance(alliance_id, next_group_id)));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == session_id
                && record
                    .data
                    .get(SELECTED_GROUP_ID_KEY)
                    .is_some_and(|value| value == &json!(next_group_id))
        })
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!("/dashboard/alliance/groups/{group_id}/delete"))
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-alliance-dashboard-table",
    );
}

#[tokio::test]
async fn test_delete_selected_group_without_fallback_clears_selection() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(alliance_id),
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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id
                && *uid == user_id
                && permission == AlliancePermission::GroupsWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_delete_group()
        .times(1)
        .withf(move |uid, cid, gid| *uid == user_id && *cid == alliance_id && *gid == group_id)
        .returning(move |_, _, _| Ok(()));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(|_| Ok(vec![]));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == session_id && !record.data.contains_key(SELECTED_GROUP_ID_KEY)
        })
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!("/dashboard/alliance/groups/{group_id}/delete"))
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-alliance-dashboard-table",
    );
}
