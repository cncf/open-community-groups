use axum::{
    body::{Body, to_bytes},
    http::{HeaderValue, Request, StatusCode, header::COOKIE},
};
use axum_login::tower_sessions::session;
use serde_json::json;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::{
        auth::{SELECTED_COMMUNITY_ID_KEY, SELECTED_GROUP_ID_KEY},
        tests::*,
    },
    services::notifications::MockNotificationsManager,
};

#[tokio::test]
async fn test_select_community_forbidden_when_user_has_no_groups_in_community() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let other_community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let groups = sample_user_groups_by_community(other_community_id, group_id);

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
    db.expect_user_has_community_permission().times(0);
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_update_session().times(0);

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/group/community/{community_id}/select"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, _) = response.into_parts();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_select_community_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let groups = sample_user_groups_by_community(community_id, group_id);

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
    db.expect_user_has_community_permission().times(0);
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(groups.clone()));
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

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/group/community/{community_id}/select"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get("HX-Trigger").unwrap(),
        &HeaderValue::from_static("refresh-body"),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_select_group_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);

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
        .withf(move |cid, gid, uid, _permission| *cid == community_id && *gid == group_id && *uid == user_id)
        .returning(|_, _, _, _| Ok(true));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == session_id
                && record
                    .data
                    .get(SELECTED_GROUP_ID_KEY)
                    .is_some_and(|value| value == &json!(group_id))
        })
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/group/{group_id}/select"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get("HX-Trigger").unwrap(),
        &HeaderValue::from_static("refresh-body"),
    );
    assert!(bytes.is_empty());
}
