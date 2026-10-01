use anyhow::anyhow;
use axum::{
    body::{Body, to_bytes},
    http::{
        Request, StatusCode,
        header::{CONTENT_TYPE, COOKIE},
    },
};
use axum_login::tower_sessions::session;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::{error::HandlerError, tests::*},
    services::{
        inbox::{InboxError, MockInboxManager},
        notifications::MockNotificationsManager,
    },
    types::{dashboard::DASHBOARD_PAGINATION_LIMIT, inbox::InboxConversationsOutput},
};

#[tokio::test]
async fn test_conversation_page_rejects_conversations_of_other_users() {
    // Setup identifiers and a conversation the user does not own
    let (inbox_conversation_id, session_id, user_id) = sample_ids();
    let mut db = user_db(session_id, user_id);
    db.expect_get_user_inbox_conversation()
        .times(1)
        .withf(move |uid, cid| *uid == user_id && *cid == inbox_conversation_id)
        .returning(|_, _| Ok(None));

    // Request the thread
    let (parts, bytes) = send_request(
        db,
        MockInboxManager::new(),
        session_id,
        "GET",
        &format!("/dashboard/user/inbox/{inbox_conversation_id}"),
        None,
    )
    .await;

    // Check the conversation is not found
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_conversation_page_renders_thread_with_push_url() {
    // Setup identifiers and the thread
    let (inbox_conversation_id, session_id, user_id) = sample_ids();
    let mut db = user_db(session_id, user_id);
    let conversation = sample_inbox_conversation(inbox_conversation_id);
    db.expect_get_user_inbox_conversation()
        .times(1)
        .withf(move |uid, cid| *uid == user_id && *cid == inbox_conversation_id)
        .returning(move |_, _| Ok(Some(conversation.clone())));

    // Request the thread
    let (parts, bytes) = send_request(
        db,
        MockInboxManager::new(),
        session_id,
        "GET",
        &format!("/dashboard/user/inbox/{inbox_conversation_id}"),
        None,
    )
    .await;

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
    let (_, session_id, user_id) = sample_ids();
    let mut db = user_db(session_id, user_id);
    let summary = sample_inbox_conversation_summary(Uuid::new_v4());
    db.expect_list_user_inbox_conversations()
        .times(1)
        .withf(move |uid, filters| {
            *uid == user_id
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

    // Request the list
    let (parts, bytes) = send_request(
        db,
        MockInboxManager::new(),
        session_id,
        "GET",
        "/dashboard/user/inbox",
        None,
    )
    .await;

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
    let (inbox_conversation_id, session_id, user_id) = sample_ids();
    let mut db = user_db(session_id, user_id);
    let conversation = sample_inbox_conversation(inbox_conversation_id);
    db.expect_get_user_inbox_conversation()
        .times(1)
        .withf(move |uid, cid| *uid == user_id && *cid == inbox_conversation_id)
        .returning(move |_, _| Ok(Some(conversation.clone())));

    // Setup inbox manager mock
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_add_user_message()
        .times(1)
        .withf(move |input| {
            input.body == "Any update?"
                && input.inbox_conversation_id == inbox_conversation_id
                && input.user_id == user_id
        })
        .returning(move |_| Box::pin(async move { Ok(inbox_conversation_id) }));

    // Send the follow-up
    let (parts, bytes) = send_request(
        db,
        inbox_manager,
        session_id,
        "POST",
        &format!("/dashboard/user/inbox/{inbox_conversation_id}/messages"),
        Some("body=Any+update%3F"),
    )
    .await;

    // Check the refreshed thread focuses the message field without a notice
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(html.contains("id=\"inbox-conversation\""));
    assert!(html.contains("autofocus"));
    assert!(!html.contains("data-inbox-action-notice"));
}

#[tokio::test]
async fn test_send_message_rejects_too_long_body() {
    // Setup identifiers without manager calls
    let (inbox_conversation_id, session_id, user_id) = sample_ids();
    let db = user_db(session_id, user_id);
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager.expect_add_user_message().never();

    // Send a follow-up over the character limit
    let body = format!("body={}", "a".repeat(5001));
    let (parts, _) = send_request(
        db,
        inbox_manager,
        session_id,
        "POST",
        &format!("/dashboard/user/inbox/{inbox_conversation_id}/messages"),
        Some(&body),
    )
    .await;

    // Check the validation failure
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_send_message_renders_notice_when_thread_cannot_be_reloaded() {
    // Setup identifiers and a missing thread after the commit
    let (inbox_conversation_id, session_id, user_id) = sample_ids();
    let mut db = user_db(session_id, user_id);
    db.expect_get_user_inbox_conversation()
        .times(1)
        .returning(|_, _| Ok(None));

    // Setup inbox manager mock
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_add_user_message()
        .times(1)
        .returning(move |_| Box::pin(async move { Ok(inbox_conversation_id) }));

    // Send the follow-up
    let (parts, bytes) = send_request(
        db,
        inbox_manager,
        session_id,
        "POST",
        &format!("/dashboard/user/inbox/{inbox_conversation_id}/messages"),
        Some("body=Hi"),
    )
    .await;

    // Check the committed message is reported as sent
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(html.contains("data-inbox-action-done"));
    assert!(html.contains("Message sent."));
}

#[tokio::test]
async fn test_send_message_returns_database_rejection_message() {
    // Setup identifiers and a database rejection
    let (inbox_conversation_id, session_id, user_id) = sample_ids();
    let db = user_db(session_id, user_id);
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager.expect_add_user_message().times(1).returning(|_| {
        Box::pin(async {
            Err(InboxError::Other(
                HandlerError::Database("daily message limit reached".to_string()).into(),
            ))
        })
    });

    // Send the follow-up
    let (parts, bytes) = send_request(
        db,
        inbox_manager,
        session_id,
        "POST",
        &format!("/dashboard/user/inbox/{inbox_conversation_id}/messages"),
        Some("body=Hi"),
    )
    .await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "daily message limit reached"
    );
}

#[tokio::test]
async fn test_send_message_returns_internal_error_without_body() {
    // Setup identifiers and an internal failure
    let (inbox_conversation_id, session_id, user_id) = sample_ids();
    let db = user_db(session_id, user_id);
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_add_user_message()
        .times(1)
        .returning(|_| Box::pin(async { Err(InboxError::Other(anyhow!("db error"))) }));

    // Send the follow-up
    let (parts, bytes) = send_request(
        db,
        inbox_manager,
        session_id,
        "POST",
        &format!("/dashboard/user/inbox/{inbox_conversation_id}/messages"),
        Some("body=Hi"),
    )
    .await;

    // Check the internal error hides the detail
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_send_message_returns_rejected_message() {
    // Setup identifiers and a manager rejection
    let (inbox_conversation_id, session_id, user_id) = sample_ids();
    let db = user_db(session_id, user_id);
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager.expect_add_user_message().times(1).returning(|_| {
        Box::pin(async { Err(InboxError::Rejected("inbox unavailable".to_string())) })
    });

    // Send the follow-up
    let (parts, bytes) = send_request(
        db,
        inbox_manager,
        session_id,
        "POST",
        &format!("/dashboard/user/inbox/{inbox_conversation_id}/messages"),
        Some("body=Hi"),
    )
    .await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "inbox unavailable"
    );
}

// Helpers.

/// Returns conversation, session and user identifiers.
fn sample_ids() -> (Uuid, session::Id, Uuid) {
    (Uuid::new_v4(), session::Id::default(), Uuid::new_v4())
}

/// Sends a user inbox request through the router.
async fn send_request(
    db: MockDB,
    inbox_manager: MockInboxManager,
    session_id: session::Id,
    method: &str,
    uri: &str,
    form: Option<&str>,
) -> (axum::http::response::Parts, axum::body::Bytes) {
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_inbox_manager(inbox_manager)
        .build()
        .await;
    let mut request = Request::builder()
        .method(method)
        .uri(uri)
        .header(COOKIE, format!("id={session_id}"));
    if form.is_some() {
        request = request.header(CONTENT_TYPE, "application/x-www-form-urlencoded");
    }
    let request = request
        .body(Body::from(form.unwrap_or_default().to_string()))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    (parts, bytes)
}

/// Builds a database mock for an authenticated user session.
fn user_db(session_id: session::Id, user_id: Uuid) -> MockDB {
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);

    db
}
