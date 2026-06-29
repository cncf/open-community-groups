use axum::{
    body::Body,
    http::{Request, StatusCode, header::COOKIE},
};
use axum_login::tower_sessions::session;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB, handlers::tests::*, services::notifications::MockNotificationsManager,
};

#[tokio::test]
async fn test_unsubscribe_reads_group_id_from_delete_query() {
    // Setup identifiers and data structures.
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock.
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_unsubscribe_coffee_meet()
        .times(1)
        .withf(move |actor_user_id, requested_group_id| {
            *actor_user_id == user_id && *requested_group_id == group_id
        })
        .returning(|_, _| Ok(()));

    // Setup router and send request.
    let nm = MockNotificationsManager::new();
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!("/dashboard/user/coffee-meet?group_id={group_id}"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();

    // Execute request and verify response.
    let response = router.oneshot(request).await.unwrap();
    assert_eq!(response.status(), StatusCode::NO_CONTENT);
    assert_eq!(
        response.headers().get("HX-Trigger").unwrap(),
        "refresh-user-dashboard-content"
    );
}
