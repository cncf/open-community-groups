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
    types::{
        dashboard::DASHBOARD_PAGINATION_LIMIT,
        inbox::{InboxConversationStatus, InboxConversationsOutput},
        permissions::GroupPermission,
    },
};

#[tokio::test]
async fn test_close_passes_identifiers_and_renders_thread() {
    // Setup identifiers and the reloaded thread
    let (community_id, group_id, inbox_conversation_id, session_id, user_id) = sample_ids();
    let mut db = inbox_db(session_id, user_id, community_id, group_id);
    let conversation = sample_inbox_conversation(inbox_conversation_id);
    db.expect_get_group_inbox_conversation()
        .times(1)
        .withf(move |gid, cid| *gid == group_id && *cid == inbox_conversation_id)
        .returning(move |_, _| Ok(Some(conversation.clone())));

    // Setup inbox manager mock
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_close_conversation()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == user_id
                && input.group_id == group_id
                && input.inbox_conversation_id == inbox_conversation_id
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Send the close request
    let (parts, bytes) = send_request(
        db,
        inbox_manager,
        session_id,
        "PUT",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/close"),
        None,
    )
    .await;

    // Check the refreshed thread reports the close in a focused notice
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(html.contains("id=\"inbox-conversation\""));
    assert!(html.contains("When do doors open?"));
    assert!(html.contains("data-inbox-action-notice>Conversation closed.</div>"));
    assert!(html.contains("autofocus"));
}

#[tokio::test]
async fn test_close_renders_notice_when_thread_cannot_be_reloaded() {
    // Setup identifiers and a failing thread reload
    let (community_id, group_id, inbox_conversation_id, session_id, user_id) = sample_ids();
    let mut db = inbox_db(session_id, user_id, community_id, group_id);
    db.expect_get_group_inbox_conversation()
        .times(1)
        .returning(|_, _| Err(anyhow!("db error")));

    // Setup inbox manager mock
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_close_conversation()
        .times(1)
        .returning(|_| Box::pin(async { Ok(()) }));

    // Send the close request
    let (parts, bytes) = send_request(
        db,
        inbox_manager,
        session_id,
        "PUT",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/close"),
        None,
    )
    .await;

    // Check the committed close is reported as done
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(html.contains("data-inbox-action-done"));
    assert!(html.contains("Conversation closed."));
    assert!(html.contains(&format!(
        "href=\"/dashboard/group?tab=inbox&#38;conversation_id={inbox_conversation_id}\""
    )));
}

#[tokio::test]
async fn test_close_returns_database_rejection_message() {
    // Setup identifiers and a database rejection
    let (community_id, group_id, inbox_conversation_id, session_id, user_id) = sample_ids();
    let db = inbox_db(session_id, user_id, community_id, group_id);
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager.expect_close_conversation().times(1).returning(|_| {
        Box::pin(async {
            Err(InboxError::Other(
                HandlerError::Database("conversation not found".to_string()).into(),
            ))
        })
    });

    // Send the close request
    let (parts, bytes) = send_request(
        db,
        inbox_manager,
        session_id,
        "PUT",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/close"),
        None,
    )
    .await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "conversation not found"
    );
}

#[tokio::test]
async fn test_close_returns_internal_error_without_body() {
    // Setup identifiers and an internal failure
    let (community_id, group_id, inbox_conversation_id, session_id, user_id) = sample_ids();
    let db = inbox_db(session_id, user_id, community_id, group_id);
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_close_conversation()
        .times(1)
        .returning(|_| Box::pin(async { Err(InboxError::Other(anyhow!("db error"))) }));

    // Send the close request
    let (parts, bytes) = send_request(
        db,
        inbox_manager,
        session_id,
        "PUT",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/close"),
        None,
    )
    .await;

    // Check the internal error hides the detail
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_close_returns_rejected_message() {
    // Setup identifiers and a manager rejection
    let (community_id, group_id, inbox_conversation_id, session_id, user_id) = sample_ids();
    let db = inbox_db(session_id, user_id, community_id, group_id);
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager.expect_close_conversation().times(1).returning(|_| {
        Box::pin(async { Err(InboxError::Rejected("inbox unavailable".to_string())) })
    });

    // Send the close request
    let (parts, bytes) = send_request(
        db,
        inbox_manager,
        session_id,
        "PUT",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/close"),
        None,
    )
    .await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "inbox unavailable"
    );
}

#[tokio::test]
async fn test_conversation_page_rejects_conversations_of_other_groups() {
    // Setup identifiers and a conversation outside the group
    let (community_id, group_id, inbox_conversation_id, session_id, user_id) = sample_ids();
    let mut db = inbox_db(session_id, user_id, community_id, group_id);
    db.expect_get_group_inbox_conversation()
        .times(1)
        .withf(move |gid, cid| *gid == group_id && *cid == inbox_conversation_id)
        .returning(|_, _| Ok(None));

    // Request the thread
    let (parts, bytes) = send_request(
        db,
        MockInboxManager::new(),
        session_id,
        "GET",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}"),
        None,
    )
    .await;

    // Check the conversation is not found
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_conversation_page_renders_thread_with_push_url() {
    // Setup identifiers and the thread
    let (community_id, group_id, inbox_conversation_id, session_id, user_id) = sample_ids();
    let mut db = inbox_db(session_id, user_id, community_id, group_id);
    let conversation = sample_inbox_conversation(inbox_conversation_id);
    db.expect_get_group_inbox_conversation()
        .times(1)
        .withf(move |gid, cid| *gid == group_id && *cid == inbox_conversation_id)
        .returning(move |_, _| Ok(Some(conversation.clone())));

    // Request the thread
    let (parts, bytes) = send_request(
        db,
        MockInboxManager::new(),
        session_id,
        "GET",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}"),
        None,
    )
    .await;

    // Check the thread and the full dashboard URL
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url").unwrap(),
        &format!("/dashboard/group?tab=inbox&conversation_id={inbox_conversation_id}")
    );
    let html = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(html.contains("Inbox User"));
    assert!(html.contains("id=\"inbox-message-form\""));
    assert!(!html.contains("data-inbox-action-notice"));
}

#[tokio::test]
async fn test_list_page_filters_by_status_and_pushes_url() {
    // Setup identifiers and the filtered list
    let (community_id, group_id, _, session_id, user_id) = sample_ids();
    let mut db = inbox_db(session_id, user_id, community_id, group_id);
    let summary = sample_inbox_conversation_summary(Uuid::new_v4());
    db.expect_list_group_inbox_conversations()
        .times(1)
        .withf(move |gid, filters| {
            *gid == group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && filters.status == Some(InboxConversationStatus::Open)
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
        "/dashboard/group/inbox?status=open",
        None,
    )
    .await;

    // Check the list and the full dashboard URL
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url").unwrap(),
        "/dashboard/group?tab=inbox&limit=50&offset=0&status=open"
    );
    let html = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(html.contains("Inbox User"));
    assert!(html.contains("When do doors open?"));
}

#[tokio::test]
async fn test_mark_spam_passes_identifiers_and_renders_thread() {
    // Setup identifiers and the reloaded thread
    let (community_id, group_id, inbox_conversation_id, session_id, user_id) = sample_ids();
    let mut db = inbox_db(session_id, user_id, community_id, group_id);
    let mut conversation = sample_inbox_conversation(inbox_conversation_id);
    conversation.status = InboxConversationStatus::Spam;
    db.expect_get_group_inbox_conversation()
        .times(1)
        .withf(move |gid, cid| *gid == group_id && *cid == inbox_conversation_id)
        .returning(move |_, _| Ok(Some(conversation.clone())));

    // Setup inbox manager mock
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_mark_conversation_as_spam()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == user_id
                && input.group_id == group_id
                && input.inbox_conversation_id == inbox_conversation_id
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Send the mark spam request
    let (parts, bytes) = send_request(
        db,
        inbox_manager,
        session_id,
        "PUT",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/mark-spam"),
        None,
    )
    .await;

    // Check the refreshed thread reports the spam mark in a focused notice
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(html.contains("id=\"inbox-conversation\""));
    assert!(html.contains("data-inbox-spam-notice"));
    assert!(html.contains("data-inbox-action-notice>Conversation marked as spam.</div>"));
    assert!(html.contains("autofocus"));
}

#[tokio::test]
async fn test_mark_spam_returns_database_rejection_message() {
    // Setup identifiers and a database rejection
    let (community_id, group_id, inbox_conversation_id, session_id, user_id) = sample_ids();
    let db = inbox_db(session_id, user_id, community_id, group_id);
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_mark_conversation_as_spam()
        .times(1)
        .returning(|_| {
            Box::pin(async {
                Err(InboxError::Other(
                    HandlerError::Database("conversation not found".to_string()).into(),
                ))
            })
        });

    // Send the mark spam request
    let (parts, bytes) = send_request(
        db,
        inbox_manager,
        session_id,
        "PUT",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/mark-spam"),
        None,
    )
    .await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "conversation not found"
    );
}

#[tokio::test]
async fn test_mark_spam_returns_internal_error_without_body() {
    // Setup identifiers and an internal failure
    let (community_id, group_id, inbox_conversation_id, session_id, user_id) = sample_ids();
    let db = inbox_db(session_id, user_id, community_id, group_id);
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_mark_conversation_as_spam()
        .times(1)
        .returning(|_| Box::pin(async { Err(InboxError::Other(anyhow!("db error"))) }));

    // Send the mark spam request
    let (parts, bytes) = send_request(
        db,
        inbox_manager,
        session_id,
        "PUT",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/mark-spam"),
        None,
    )
    .await;

    // Check the internal error hides the detail
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_mark_spam_returns_rejected_message() {
    // Setup identifiers and a manager rejection
    let (community_id, group_id, inbox_conversation_id, session_id, user_id) = sample_ids();
    let db = inbox_db(session_id, user_id, community_id, group_id);
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_mark_conversation_as_spam()
        .times(1)
        .returning(|_| {
            Box::pin(async { Err(InboxError::Rejected("inbox unavailable".to_string())) })
        });

    // Send the mark spam request
    let (parts, bytes) = send_request(
        db,
        inbox_manager,
        session_id,
        "PUT",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/mark-spam"),
        None,
    )
    .await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "inbox unavailable"
    );
}

#[tokio::test]
async fn test_reply_passes_identifiers_and_renders_focused_thread() {
    // Setup identifiers and the reloaded thread
    let (community_id, group_id, inbox_conversation_id, session_id, user_id) = sample_ids();
    let mut db = inbox_db(session_id, user_id, community_id, group_id);
    let conversation = sample_inbox_conversation(inbox_conversation_id);
    db.expect_get_group_inbox_conversation()
        .times(1)
        .withf(move |gid, cid| *gid == group_id && *cid == inbox_conversation_id)
        .returning(move |_, _| Ok(Some(conversation.clone())));

    // Setup inbox manager mock
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_add_group_reply()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == user_id
                && input.body == "Doors open at 6pm."
                && input.group_id == group_id
                && input.inbox_conversation_id == inbox_conversation_id
        })
        .returning(move |_| Box::pin(async move { Ok(inbox_conversation_id) }));

    // Send the reply
    let (parts, bytes) = send_request(
        db,
        inbox_manager,
        session_id,
        "POST",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/replies"),
        Some("body=Doors+open+at+6pm."),
    )
    .await;

    // Check the refreshed thread focuses the reply field without a notice
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(html.contains("id=\"inbox-conversation\""));
    assert!(html.contains("autofocus"));
    assert!(!html.contains("data-inbox-action-notice"));
}

#[tokio::test]
async fn test_reply_rejects_whitespace_only_body() {
    // Setup identifiers without manager calls
    let (community_id, group_id, inbox_conversation_id, session_id, user_id) = sample_ids();
    let db = inbox_db(session_id, user_id, community_id, group_id);
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager.expect_add_group_reply().never();

    // Send an empty reply
    let (parts, _) = send_request(
        db,
        inbox_manager,
        session_id,
        "POST",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/replies"),
        Some("body=+%0A+"),
    )
    .await;

    // Check the validation failure
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_reply_renders_notice_when_thread_cannot_be_reloaded() {
    // Setup identifiers and a failing thread reload
    let (community_id, group_id, inbox_conversation_id, session_id, user_id) = sample_ids();
    let mut db = inbox_db(session_id, user_id, community_id, group_id);
    db.expect_get_group_inbox_conversation()
        .times(1)
        .returning(|_, _| Err(anyhow!("db error")));

    // Setup inbox manager mock
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_add_group_reply()
        .times(1)
        .returning(move |_| Box::pin(async move { Ok(inbox_conversation_id) }));

    // Send the reply
    let (parts, bytes) = send_request(
        db,
        inbox_manager,
        session_id,
        "POST",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/replies"),
        Some("body=Hi"),
    )
    .await;

    // Check the committed reply is reported as sent
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(html.contains("data-inbox-action-done"));
    assert!(html.contains("Message sent."));
}

#[tokio::test]
async fn test_reply_returns_database_rejection_message() {
    // Setup identifiers and a database rejection
    let (community_id, group_id, inbox_conversation_id, session_id, user_id) = sample_ids();
    let db = inbox_db(session_id, user_id, community_id, group_id);
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager.expect_add_group_reply().times(1).returning(|_| {
        Box::pin(async {
            Err(InboxError::Other(
                HandlerError::Database("conversation is read-only".to_string()).into(),
            ))
        })
    });

    // Send the reply
    let (parts, bytes) = send_request(
        db,
        inbox_manager,
        session_id,
        "POST",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/replies"),
        Some("body=Hi"),
    )
    .await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "conversation is read-only"
    );
}

#[tokio::test]
async fn test_reply_returns_internal_error_without_body() {
    // Setup identifiers and an internal failure
    let (community_id, group_id, inbox_conversation_id, session_id, user_id) = sample_ids();
    let db = inbox_db(session_id, user_id, community_id, group_id);
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_add_group_reply()
        .times(1)
        .returning(|_| Box::pin(async { Err(InboxError::Other(anyhow!("db error"))) }));

    // Send the reply
    let (parts, bytes) = send_request(
        db,
        inbox_manager,
        session_id,
        "POST",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/replies"),
        Some("body=Hi"),
    )
    .await;

    // Check the internal error hides the detail
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_reply_returns_rejected_message() {
    // Setup identifiers and a manager rejection
    let (community_id, group_id, inbox_conversation_id, session_id, user_id) = sample_ids();
    let db = inbox_db(session_id, user_id, community_id, group_id);
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager.expect_add_group_reply().times(1).returning(|_| {
        Box::pin(async { Err(InboxError::Rejected("inbox unavailable".to_string())) })
    });

    // Send the reply
    let (parts, bytes) = send_request(
        db,
        inbox_manager,
        session_id,
        "POST",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/replies"),
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

#[tokio::test]
async fn test_unmark_spam_passes_identifiers_and_renders_thread() {
    // Setup identifiers and the reloaded thread
    let (community_id, group_id, inbox_conversation_id, session_id, user_id) = sample_ids();
    let mut db = inbox_db(session_id, user_id, community_id, group_id);
    let mut conversation = sample_inbox_conversation(inbox_conversation_id);
    conversation.status = InboxConversationStatus::Open;
    db.expect_get_group_inbox_conversation()
        .times(1)
        .withf(move |gid, cid| *gid == group_id && *cid == inbox_conversation_id)
        .returning(move |_, _| Ok(Some(conversation.clone())));

    // Setup inbox manager mock
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_unmark_conversation_as_spam()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == user_id
                && input.group_id == group_id
                && input.inbox_conversation_id == inbox_conversation_id
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Send the unmark spam request
    let (parts, bytes) = send_request(
        db,
        inbox_manager,
        session_id,
        "PUT",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/unmark-spam"),
        None,
    )
    .await;

    // Check the refreshed thread reports the spam unmark in a focused notice
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(html.contains("id=\"inbox-conversation\""));
    assert!(html.contains("id=\"inbox-message-form\""));
    assert!(html.contains("data-inbox-action-notice>Conversation unmarked as spam.</div>"));
    assert!(html.contains("autofocus"));
}

#[tokio::test]
async fn test_unmark_spam_returns_database_rejection_message() {
    // Setup identifiers and a database rejection
    let (community_id, group_id, inbox_conversation_id, session_id, user_id) = sample_ids();
    let db = inbox_db(session_id, user_id, community_id, group_id);
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_unmark_conversation_as_spam()
        .times(1)
        .returning(|_| {
            Box::pin(async {
                Err(InboxError::Other(
                    HandlerError::Database("conversation not found".to_string()).into(),
                ))
            })
        });

    // Send the unmark spam request
    let (parts, bytes) = send_request(
        db,
        inbox_manager,
        session_id,
        "PUT",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/unmark-spam"),
        None,
    )
    .await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "conversation not found"
    );
}

#[tokio::test]
async fn test_unmark_spam_returns_internal_error_without_body() {
    // Setup identifiers and an internal failure
    let (community_id, group_id, inbox_conversation_id, session_id, user_id) = sample_ids();
    let db = inbox_db(session_id, user_id, community_id, group_id);
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_unmark_conversation_as_spam()
        .times(1)
        .returning(|_| Box::pin(async { Err(InboxError::Other(anyhow!("db error"))) }));

    // Send the unmark spam request
    let (parts, bytes) = send_request(
        db,
        inbox_manager,
        session_id,
        "PUT",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/unmark-spam"),
        None,
    )
    .await;

    // Check the internal error hides the detail
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_unmark_spam_returns_rejected_message() {
    // Setup identifiers and a manager rejection
    let (community_id, group_id, inbox_conversation_id, session_id, user_id) = sample_ids();
    let db = inbox_db(session_id, user_id, community_id, group_id);
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_unmark_conversation_as_spam()
        .times(1)
        .returning(|_| {
            Box::pin(async { Err(InboxError::Rejected("inbox unavailable".to_string())) })
        });

    // Send the unmark spam request
    let (parts, bytes) = send_request(
        db,
        inbox_manager,
        session_id,
        "PUT",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/unmark-spam"),
        None,
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

/// Builds a database mock for a session allowed to use the group inbox.
fn inbox_db(session_id: session::Id, user_id: Uuid, community_id: Uuid, group_id: Uuid) -> MockDB {
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::InboxWrite,
    );

    db
}

/// Returns community, group, conversation, session and user identifiers.
fn sample_ids() -> (Uuid, Uuid, Uuid, session::Id, Uuid) {
    (
        Uuid::new_v4(),
        Uuid::new_v4(),
        Uuid::new_v4(),
        session::Id::default(),
        Uuid::new_v4(),
    )
}

/// Sends a group inbox request through the router.
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
