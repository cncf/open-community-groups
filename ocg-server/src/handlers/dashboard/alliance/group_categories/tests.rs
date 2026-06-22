use anyhow::anyhow;
use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderValue, Request, StatusCode,
        header::{CONTENT_TYPE, COOKIE, HOST},
    },
};
use axum_login::tower_sessions::session;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB, handlers::tests::*, services::notifications::MockNotificationsManager,
    types::permissions::AlliancePermission,
};

use super::GroupCategoryInput;

#[tokio::test]
async fn test_add_db_error() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let form = GroupCategoryInput {
        name: "Cloud Native".to_string(),
    };
    let body = serde_qs::to_string(&form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_alliance_session(&mut db, session_id, user_id, alliance_id);
    expect_alliance_permission(
        &mut db,
        alliance_id,
        user_id,
        AlliancePermission::TaxonomyWrite,
    );
    db.expect_add_group_category()
        .times(1)
        .withf(move |uid, cid, category| {
            *uid == user_id && *cid == alliance_id && category.name == "Cloud Native"
        })
        .returning(|_, _, _| Err(anyhow!("db error")));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri("/dashboard/alliance/group-categories/add")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_add_invalid_payload() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_alliance_session(&mut db, session_id, user_id, alliance_id);
    expect_alliance_permission(
        &mut db,
        alliance_id,
        user_id,
        AlliancePermission::TaxonomyWrite,
    );

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri("/dashboard/alliance/group-categories/add")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from("name="))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_add_page_db_error() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_alliance_session(&mut db, session_id, user_id, alliance_id);
    expect_alliance_permission(&mut db, alliance_id, user_id, AlliancePermission::Read);
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id
                && *uid == user_id
                && permission == AlliancePermission::TaxonomyWrite
        })
        .returning(|_, _, _| Err(anyhow!("db error")));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/alliance/group-categories/add")
        .header(HOST, "example.test")
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
async fn test_add_page_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_alliance_session(&mut db, session_id, user_id, alliance_id);
    expect_alliance_permission(&mut db, alliance_id, user_id, AlliancePermission::Read);
    expect_alliance_permission(
        &mut db,
        alliance_id,
        user_id,
        AlliancePermission::TaxonomyWrite,
    );

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/alliance/group-categories/add")
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
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_add_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let form = GroupCategoryInput {
        name: "Platform Engineering".to_string(),
    };
    let expected_name = form.name.clone();
    let body = serde_qs::to_string(&form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_alliance_session(&mut db, session_id, user_id, alliance_id);
    expect_alliance_permission(
        &mut db,
        alliance_id,
        user_id,
        AlliancePermission::TaxonomyWrite,
    );
    db.expect_add_group_category()
        .times(1)
        .withf(move |uid, cid, category| {
            *uid == user_id && *cid == alliance_id && category.name == expected_name
        })
        .returning(|_, _, _| Ok(Uuid::new_v4()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("POST")
        .uri("/dashboard/alliance/group-categories/add")
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
async fn test_delete_db_error() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_category_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_alliance_session(&mut db, session_id, user_id, alliance_id);
    expect_alliance_permission(
        &mut db,
        alliance_id,
        user_id,
        AlliancePermission::TaxonomyWrite,
    );
    db.expect_delete_group_category()
        .times(1)
        .withf(move |uid, cid, gcid| {
            *uid == user_id && *cid == alliance_id && *gcid == group_category_id
        })
        .returning(|_, _, _| Err(anyhow!("db error")));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!(
            "/dashboard/alliance/group-categories/{group_category_id}/delete"
        ))
        .header(HOST, "example.test")
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
async fn test_delete_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_category_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_alliance_session(&mut db, session_id, user_id, alliance_id);
    expect_alliance_permission(
        &mut db,
        alliance_id,
        user_id,
        AlliancePermission::TaxonomyWrite,
    );
    db.expect_delete_group_category()
        .times(1)
        .withf(move |uid, cid, gcid| {
            *uid == user_id && *cid == alliance_id && *gcid == group_category_id
        })
        .returning(|_, _, _| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!(
            "/dashboard/alliance/group-categories/{group_category_id}/delete"
        ))
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
async fn test_list_page_db_error() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_alliance_session(&mut db, session_id, user_id, alliance_id);
    expect_alliance_permission(&mut db, alliance_id, user_id, AlliancePermission::Read);
    expect_alliance_permission(
        &mut db,
        alliance_id,
        user_id,
        AlliancePermission::TaxonomyWrite,
    );
    db.expect_list_group_categories()
        .times(1)
        .withf(move |cid| *cid == alliance_id)
        .returning(|_| Err(anyhow!("db error")));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/alliance/group-categories")
        .header(HOST, "example.test")
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
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let categories = vec![sample_group_category()];

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_alliance_session(&mut db, session_id, user_id, alliance_id);
    expect_alliance_permission(&mut db, alliance_id, user_id, AlliancePermission::Read);
    expect_alliance_permission(
        &mut db,
        alliance_id,
        user_id,
        AlliancePermission::TaxonomyWrite,
    );
    db.expect_list_group_categories()
        .times(1)
        .withf(move |cid| *cid == alliance_id)
        .returning(move |_| Ok(categories.clone()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/alliance/group-categories")
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
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_update_db_error() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_category_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let form = GroupCategoryInput {
        name: "Cloud Native".to_string(),
    };
    let body = serde_qs::to_string(&form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_alliance_session(&mut db, session_id, user_id, alliance_id);
    expect_alliance_permission(
        &mut db,
        alliance_id,
        user_id,
        AlliancePermission::TaxonomyWrite,
    );
    db.expect_update_group_category()
        .times(1)
        .withf(move |uid, cid, gcid, category| {
            *uid == user_id
                && *cid == alliance_id
                && *gcid == group_category_id
                && category.name == "Cloud Native"
        })
        .returning(|_, _, _, _| Err(anyhow!("db error")));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!(
            "/dashboard/alliance/group-categories/{group_category_id}/update"
        ))
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_update_invalid_payload() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_category_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_alliance_session(&mut db, session_id, user_id, alliance_id);
    expect_alliance_permission(
        &mut db,
        alliance_id,
        user_id,
        AlliancePermission::TaxonomyWrite,
    );

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!(
            "/dashboard/alliance/group-categories/{group_category_id}/update"
        ))
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from("name="))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_update_page_db_error() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_category_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_alliance_session(&mut db, session_id, user_id, alliance_id);
    expect_alliance_permission(&mut db, alliance_id, user_id, AlliancePermission::Read);
    expect_alliance_permission(
        &mut db,
        alliance_id,
        user_id,
        AlliancePermission::TaxonomyWrite,
    );
    db.expect_list_group_categories()
        .times(1)
        .withf(move |cid| *cid == alliance_id)
        .returning(|_| Err(anyhow!("db error")));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!(
            "/dashboard/alliance/group-categories/{group_category_id}/update"
        ))
        .header(HOST, "example.test")
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
async fn test_update_page_not_found() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_category_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let categories = vec![sample_group_category()];

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_alliance_session(&mut db, session_id, user_id, alliance_id);
    expect_alliance_permission(&mut db, alliance_id, user_id, AlliancePermission::Read);
    expect_alliance_permission(
        &mut db,
        alliance_id,
        user_id,
        AlliancePermission::TaxonomyWrite,
    );
    db.expect_list_group_categories()
        .times(1)
        .withf(move |cid| *cid == alliance_id)
        .returning(move |_| Ok(categories.clone()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(format!(
            "/dashboard/alliance/group-categories/{group_category_id}/update"
        ))
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), b"group category not found");
}

#[tokio::test]
async fn test_update_page_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_category_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut category = sample_group_category();
    category.group_category_id = group_category_id;
    let categories = vec![category];

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_alliance_session(&mut db, session_id, user_id, alliance_id);
    expect_alliance_permission(&mut db, alliance_id, user_id, AlliancePermission::Read);
    expect_alliance_permission(
        &mut db,
        alliance_id,
        user_id,
        AlliancePermission::TaxonomyWrite,
    );
    db.expect_list_group_categories()
        .times(1)
        .withf(move |cid| *cid == alliance_id)
        .returning(move |_| Ok(categories.clone()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(format!(
            "/dashboard/alliance/group-categories/{group_category_id}/update"
        ))
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
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_update_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_category_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let form = GroupCategoryInput {
        name: "Cloud Native".to_string(),
    };
    let expected_name = form.name.clone();
    let body = serde_qs::to_string(&form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_alliance_session(&mut db, session_id, user_id, alliance_id);
    expect_alliance_permission(
        &mut db,
        alliance_id,
        user_id,
        AlliancePermission::TaxonomyWrite,
    );
    db.expect_update_group_category()
        .times(1)
        .withf(move |uid, cid, gcid, category| {
            *uid == user_id
                && *cid == alliance_id
                && *gcid == group_category_id
                && category.name == expected_name
        })
        .returning(|_, _, _, _| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!(
            "/dashboard/alliance/group-categories/{group_category_id}/update"
        ))
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
