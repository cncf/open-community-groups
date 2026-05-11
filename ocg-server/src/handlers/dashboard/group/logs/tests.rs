use anyhow::anyhow;
use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderValue, Request, StatusCode,
        header::{CONTENT_TYPE, COOKIE},
    },
};
use axum_login::tower_sessions::session;
use chrono::NaiveDate;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB, handlers::tests::*, services::notifications::MockNotificationsManager,
    types::permissions::GroupPermission,
};

#[tokio::test]
async fn test_list_page_db_error() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
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
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id && *gid == group_id && *uid == user_id && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_list_group_audit_logs()
        .times(1)
        .withf(move |id, filters| *id == group_id && filters.limit == Some(50) && filters.offset == Some(0))
        .returning(|_, _| Err(anyhow!("db error")));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group/logs")
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
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );
    let output = sample_audit_logs_output();

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
            *cid == community_id && *gid == group_id && *uid == user_id && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_list_group_audit_logs()
        .times(1)
        .withf(move |id, filters| {
            *id == group_id
                && filters.action.as_deref() == Some("group_updated")
                && filters.actor.as_deref() == Some("test-user")
                && filters.date_from == Some(NaiveDate::from_ymd_opt(2024, 1, 1).unwrap())
                && filters.date_to == Some(NaiveDate::from_ymd_opt(2024, 1, 31).unwrap())
                && filters.limit == Some(5)
                && filters.offset == Some(10)
                && filters.sort.as_deref() == Some("created-asc")
        })
        .returning(move |_, _| Ok(output.clone()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(
            "/dashboard/group/logs?action=group_updated&actor=test-user\
             &date_from=2024-01-01&date_to=2024-01-31&limit=5&offset=10&sort=created-asc",
        )
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8"),
    );
    assert_eq!(
        parts.headers.get("hx-push-url").unwrap(),
        &HeaderValue::from_static(concat!(
            "/dashboard/group?tab=logs&action=group_updated&actor=test-user",
            "&date_from=2024-01-01&date_to=2024-01-31&limit=5&offset=10&sort=created-asc",
        )),
    );
    assert!(body.contains("id=\"audit-actor\""));
    assert!(body.contains("Community updated"));
    assert!(body.contains("Schedule updated"));
}
