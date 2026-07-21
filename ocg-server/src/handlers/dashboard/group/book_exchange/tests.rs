use axum::{
    body::{Body, to_bytes},
    http::{Request, StatusCode, header::COOKIE},
};
use axum_login::tower_sessions::session;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::{dashboard::common::BookExchangeMember, mock::MockDB},
    handlers::tests::*,
    services::notifications::MockNotificationsManager,
    types::permissions::GroupPermission,
};

#[tokio::test]
async fn test_list_page_allows_read_only_group_member_without_email() {
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let member = sample_book_exchange_member(alliance_id, group_id);

    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, alliance_id, group_id);
    expect_group_permission(
        &mut db,
        alliance_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == alliance_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::SettingsWrite
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_list_book_exchange_members()
        .times(1)
        .withf(move |cid, gid| *cid == alliance_id && *gid == Some(group_id))
        .returning(move |_, _| Ok(vec![member.clone()]));

    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group/book-exchange")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let body = std::str::from_utf8(&bytes).unwrap();

    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains("The Pragmatic Programmer"));
    assert!(body.contains("@book-lover"));
    assert!(!body.contains("book-lover@example.com"));
}

fn sample_book_exchange_member(alliance_id: Uuid, group_id: Uuid) -> BookExchangeMember {
    BookExchangeMember {
        user_id: Uuid::new_v4(),
        username: "book-lover".to_string(),
        group_id,
        group_name: "GOUP Builders".to_string(),
        alliance_id,
        alliance_display_name: "GOUP".to_string(),
        book_exchange_books: Some("The Pragmatic Programmer".to_string()),
        city: Some("Phoenix".to_string()),
        company: Some("GOUP".to_string()),
        country: Some("US".to_string()),
        email: Some("book-lover@example.com".to_string()),
        name: Some("Book Lover".to_string()),
        photo_url: None,
        title: Some("Builder".to_string()),
    }
}
