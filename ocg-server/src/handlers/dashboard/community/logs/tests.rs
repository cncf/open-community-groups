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
    db::mock::MockDB,
    handlers::tests::*,
    services::notifications::MockNotificationsManager,
    types::{dashboard::common::AuditLogSort, permissions::CommunityPermission},
};

#[tokio::test]
async fn test_list_page_rejects_unknown_sort() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    expect_community_permission(&mut db, community_id, user_id, CommunityPermission::Read);

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/community/logs?sort=resource-asc")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let output = sample_audit_logs_output();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    expect_community_permission(&mut db, community_id, user_id, CommunityPermission::Read);
    db.expect_list_community_audit_logs()
        .times(1)
        .withf(move |id, filters| {
            *id == community_id
                && filters.action.as_deref() == Some("community_updated")
                && filters.actor.as_deref() == Some("test-user")
                && filters.date_from == Some(NaiveDate::from_ymd_opt(2024, 1, 1).unwrap())
                && filters.date_to == Some(NaiveDate::from_ymd_opt(2024, 1, 31).unwrap())
                && filters.limit == Some(5)
                && filters.offset == Some(10)
                && filters.sort == Some(AuditLogSort::CreatedAsc)
        })
        .returning(move |_, _| Ok(output.clone()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(
            "/dashboard/community/logs?action=community_updated&actor=test-user\
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
            "/dashboard/community?tab=logs&action=community_updated&actor=test-user",
            "&date_from=2024-01-01&date_to=2024-01-31&limit=5&offset=10&sort=created-asc",
        )),
    );
    assert!(body.contains("id=\"audit-actor\""));
    assert!(body.contains("Community updated"));
    assert!(body.contains("Schedule updated"));
}
