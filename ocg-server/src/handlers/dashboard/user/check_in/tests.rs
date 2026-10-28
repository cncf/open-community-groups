use axum::http::StatusCode;
use uuid::Uuid;

use crate::{db::mock::MockDB, handlers::tests::*};

#[tokio::test]
async fn test_list_page_falls_back_to_username_when_name_is_blank() {
    // Setup identifiers and a user without a display name
    let ids = DashboardIds::new();
    let user = crate::auth::User {
        name: " ".to_string(),
        ..sample_auth_user(ids.user_id, "hash")
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_session_with_user(&mut db, &ids, user);
    db.expect_list_user_check_in_events()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(|_| Ok(vec![]));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user/check-in", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the QR modal identifies the attendee by username
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains(r#"data-user-name="test-user""#));
    assert!(body.contains(r#"data-username="test-user""#));
}

#[tokio::test]
async fn test_list_page_returns_current_user_events() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_list_user_check_in_events()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(|_| Ok(vec![]));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user/check-in", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the fragment renders the attendee display identity
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains(r#"data-user-name="Test User""#));
    assert!(body.contains(r#"data-username="test-user""#));
}

#[tokio::test]
async fn test_qr_code_returns_private_uncacheable_svg() {
    // Setup identifiers and a confirmed credential owned by the current user
    let check_in_code = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_get_user_check_in_code()
        .times(1)
        .withf(move |eid, uid| *eid == event_id && *uid == ids.user_id)
        .returning(move |_, _| Ok(Some(check_in_code)));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/user/check-in/{event_id}/qr-code"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the private SVG response contract
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(parts.headers["cache-control"], "private, no-store");
    assert_eq!(parts.headers["content-type"], "image/svg+xml");
    assert!(String::from_utf8_lossy(&bytes).contains("<svg"));
}

#[tokio::test]
async fn test_qr_code_returns_unavailable_for_non_confirmed_attendance() {
    // Setup identifiers and a user without a confirmed credential
    let event_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_get_user_check_in_code()
        .times(1)
        .withf(move |eid, uid| *eid == event_id && *uid == ids.user_id)
        .returning(|_, _| Ok(None));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/user/check-in/{event_id}/qr-code"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check credential ownership is not disclosed
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}
