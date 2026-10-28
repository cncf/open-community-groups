use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    services::inbox::{InboxError, MockInboxManager},
    types::{dashboard::DASHBOARD_PAGINATION_LIMIT, inbox::InboxConversationsOutput},
};

#[tokio::test]
async fn test_conversation_page_rejects_conversations_of_other_users() {
    // Setup identifiers and a conversation the user does not own
    let ids = DashboardIds::new();
    let inbox_conversation_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_get_user_inbox_conversation()
        .times(1)
        .withf(move |uid, cid| *uid == ids.user_id && *cid == inbox_conversation_id)
        .returning(|_, _| Ok(None));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/user/inbox/{inbox_conversation_id}"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the conversation is not found
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_conversation_page_renders_thread_with_push_url() {
    // Setup identifiers and the thread
    let ids = DashboardIds::new();
    let inbox_conversation_id = Uuid::new_v4();
    let conversation = sample_inbox_conversation(inbox_conversation_id);
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_get_user_inbox_conversation()
        .times(1)
        .withf(move |uid, cid| *uid == ids.user_id && *cid == inbox_conversation_id)
        .returning(move |_, _| Ok(Some(conversation.clone())));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/user/inbox/{inbox_conversation_id}"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the thread and the full dashboard URL
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url").unwrap(),
        &format!("/dashboard/user?tab=inbox&conversation_id={inbox_conversation_id}")
    );
    let html = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(html.contains("Test Group"));
    assert!(html.contains(&format!(
        "hx-post=\"/dashboard/user/inbox/{inbox_conversation_id}/messages\""
    )));
}

#[tokio::test]
async fn test_list_page_renders_conversations_and_pushes_url() {
    // Setup identifiers and the list
    let ids = DashboardIds::new();
    let summary = sample_inbox_conversation_summary(Uuid::new_v4());
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_list_user_inbox_conversations()
        .times(1)
        .withf(move |uid, filters| {
            *uid == ids.user_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && filters.status.is_none()
        })
        .returning(move |_, _| {
            Ok(InboxConversationsOutput {
                conversations: vec![summary.clone()],
                total: 1,
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user/inbox", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the list and the full dashboard URL
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url").unwrap(),
        "/dashboard/user?tab=inbox&limit=50&offset=0"
    );
    let html = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(html.contains("Test Group"));
    assert!(html.contains("Test Community"));
}

#[tokio::test]
async fn test_send_message_passes_identifiers_and_renders_focused_thread() {
    // Setup identifiers and the reloaded thread
    let ids = DashboardIds::new();
    let inbox_conversation_id = Uuid::new_v4();
    let conversation = sample_inbox_conversation(inbox_conversation_id);
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_get_user_inbox_conversation()
        .times(1)
        .withf(move |uid, cid| *uid == ids.user_id && *cid == inbox_conversation_id)
        .returning(move |_, _| Ok(Some(conversation.clone())));

    // Setup inbox manager mock
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_add_user_message()
        .times(1)
        .withf(move |input| {
            input.body == "Any update?"
                && input.inbox_conversation_id == inbox_conversation_id
                && input.user_id == ids.user_id
        })
        .returning(move |_| Box::pin(async move { Ok(inbox_conversation_id) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_inbox_manager(inbox_manager)
        .build()
        .await;
    let request = message_request(&ids, inbox_conversation_id, "body=Any+update%3F");
    let (parts, bytes) = send(router, request).await;

    // Check the refreshed thread focuses the message field without a notice
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(html.contains("id=\"inbox-conversation\""));
    assert!(html.contains("autofocus"));
    assert!(!html.contains("data-inbox-action-notice"));
}

#[tokio::test]
async fn test_send_message_rejects_too_long_body() {
    // Setup identifiers and an inbox manager that must not be called
    let ids = DashboardIds::new();
    let inbox_conversation_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager.expect_add_user_message().never();

    // Setup router and send a follow-up over the character limit
    let router = TestRouterBuilder::new(db)
        .with_inbox_manager(inbox_manager)
        .build()
        .await;
    let request = message_request(
        &ids,
        inbox_conversation_id,
        format!("body={}", "a".repeat(5001)),
    );
    let (parts, bytes) = send(router, request).await;

    // Check the validation failure names the field
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        std::str::from_utf8(&bytes).unwrap(),
        "body: length is greater than 5000\n"
    );
}

#[tokio::test]
async fn test_send_message_renders_notice_when_thread_cannot_be_reloaded() {
    // Setup identifiers and a missing thread after the commit
    let ids = DashboardIds::new();
    let inbox_conversation_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_get_user_inbox_conversation()
        .times(1)
        .returning(|_, _| Ok(None));

    // Setup inbox manager mock
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_add_user_message()
        .times(1)
        .returning(move |_| Box::pin(async move { Ok(inbox_conversation_id) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_inbox_manager(inbox_manager)
        .build()
        .await;
    let request = message_request(&ids, inbox_conversation_id, "body=Hi");
    let (parts, bytes) = send(router, request).await;

    // Check the committed message is reported as sent
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(html.contains("data-inbox-action-done"));
    assert!(html.contains("Message sent."));
}

#[tokio::test]
async fn test_send_message_returns_rejected_message() {
    // Setup identifiers and a manager rejection
    let ids = DashboardIds::new();
    let inbox_conversation_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager.expect_add_user_message().times(1).returning(|_| {
        Box::pin(async { Err(InboxError::Rejected("inbox unavailable".to_string())) })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_inbox_manager(inbox_manager)
        .build()
        .await;
    let request = message_request(&ids, inbox_conversation_id, "body=Hi");
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "inbox unavailable"
    );
}

// Helpers.

/// Builds the request sending a follow-up message to the conversation.
fn message_request(
    ids: &DashboardIds,
    inbox_conversation_id: Uuid,
    form: impl Into<Body>,
) -> Request<Body> {
    form_request(
        "POST",
        &format!("/dashboard/user/inbox/{inbox_conversation_id}/messages"),
        ids.session_id,
        form,
    )
}
