use anyhow::anyhow;
use axum::http::StatusCode;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    services::inbox::{InboxError, MockInboxManager},
    types::{
        dashboard::DASHBOARD_PAGINATION_LIMIT,
        inbox::{InboxConversationStatus, InboxConversationsOutput},
        permissions::GroupPermission,
    },
};

#[tokio::test]
async fn test_close_passes_identifiers_and_renders_thread() {
    // Setup identifiers and the reloaded thread
    let ids = DashboardIds::new();
    let inbox_conversation_id = Uuid::new_v4();
    let conversation = sample_inbox_conversation(inbox_conversation_id);

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::InboxWrite);
    db.expect_get_group_inbox_conversation()
        .times(1)
        .withf(move |group_id, conversation_id| {
            *group_id == ids.group_id && *conversation_id == inbox_conversation_id
        })
        .returning(move |_, _| Ok(Some(conversation.clone())));

    // Setup inbox manager mock
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_close_conversation()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == ids.user_id
                && input.group_id == ids.group_id
                && input.inbox_conversation_id == inbox_conversation_id
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_inbox_manager(inbox_manager)
        .build()
        .await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/close"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the refreshed thread reports the close in a focused notice
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = std::str::from_utf8(&bytes).unwrap();
    assert!(html.contains("id=\"inbox-conversation\""));
    assert!(html.contains("When do doors open?"));
    assert!(html.contains("data-inbox-action-notice>Conversation closed.</div>"));
    assert!(html.contains("autofocus"));
}

#[tokio::test]
async fn test_close_renders_notice_when_thread_cannot_be_reloaded() {
    // Setup identifiers
    let ids = DashboardIds::new();
    let inbox_conversation_id = Uuid::new_v4();

    // Setup database mock with a failing thread reload
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::InboxWrite);
    db.expect_get_group_inbox_conversation()
        .times(1)
        .returning(|_, _| Err(anyhow!("db error")));

    // Setup inbox manager mock
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_close_conversation()
        .times(1)
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_inbox_manager(inbox_manager)
        .build()
        .await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/close"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the committed close is reported as done
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = std::str::from_utf8(&bytes).unwrap();
    assert!(html.contains("data-inbox-action-done"));
    assert!(html.contains("Conversation closed."));
    assert!(html.contains(&format!(
        "href=\"/dashboard/group?tab=inbox&#38;conversation_id={inbox_conversation_id}\""
    )));
}

#[tokio::test]
async fn test_close_returns_rejected_message() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::InboxWrite);

    // Setup inbox manager mock with a rejection
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager.expect_close_conversation().times(1).returning(|_| {
        Box::pin(async { Err(InboxError::Rejected("inbox unavailable".to_string())) })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_inbox_manager(inbox_manager)
        .build()
        .await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/group/inbox/{}/close", Uuid::new_v4()),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(std::str::from_utf8(&bytes).unwrap(), "inbox unavailable");
}

#[tokio::test]
async fn test_conversation_page_rejects_conversations_of_other_groups() {
    // Setup identifiers
    let ids = DashboardIds::new();
    let inbox_conversation_id = Uuid::new_v4();

    // Setup database mock with a conversation outside the group
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::InboxWrite);
    db.expect_get_group_inbox_conversation()
        .times(1)
        .withf(move |group_id, conversation_id| {
            *group_id == ids.group_id && *conversation_id == inbox_conversation_id
        })
        .returning(|_, _| Ok(None));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/inbox/{inbox_conversation_id}"),
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

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::InboxWrite);
    db.expect_get_group_inbox_conversation()
        .times(1)
        .withf(move |group_id, conversation_id| {
            *group_id == ids.group_id && *conversation_id == inbox_conversation_id
        })
        .returning(move |_, _| Ok(Some(conversation.clone())));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/inbox/{inbox_conversation_id}"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the thread and the full dashboard URL
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url").unwrap(),
        &format!("/dashboard/group?tab=inbox&conversation_id={inbox_conversation_id}")
    );
    let html = std::str::from_utf8(&bytes).unwrap();
    assert!(html.contains("Inbox User"));
    assert!(html.contains("id=\"inbox-message-form\""));
    assert!(!html.contains("data-inbox-action-notice"));
}

#[tokio::test]
async fn test_list_page_filters_by_status_and_pushes_url() {
    // Setup identifiers and the filtered list
    let ids = DashboardIds::new();
    let summary = sample_inbox_conversation_summary(Uuid::new_v4());

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::InboxWrite);
    db.expect_list_group_inbox_conversations()
        .times(1)
        .withf(move |group_id, filters| {
            *group_id == ids.group_id
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

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group/inbox?status=open", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the list and the full dashboard URL
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url").unwrap(),
        "/dashboard/group?tab=inbox&limit=50&offset=0&status=open"
    );
    let html = std::str::from_utf8(&bytes).unwrap();
    assert!(html.contains("Inbox User"));
    assert!(html.contains("When do doors open?"));
}

#[tokio::test]
async fn test_mark_spam_passes_identifiers_and_renders_thread() {
    // Setup identifiers and the reloaded thread
    let ids = DashboardIds::new();
    let inbox_conversation_id = Uuid::new_v4();
    let mut conversation = sample_inbox_conversation(inbox_conversation_id);
    conversation.status = InboxConversationStatus::Spam;

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::InboxWrite);
    db.expect_get_group_inbox_conversation()
        .times(1)
        .withf(move |group_id, conversation_id| {
            *group_id == ids.group_id && *conversation_id == inbox_conversation_id
        })
        .returning(move |_, _| Ok(Some(conversation.clone())));

    // Setup inbox manager mock
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_mark_conversation_as_spam()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == ids.user_id
                && input.group_id == ids.group_id
                && input.inbox_conversation_id == inbox_conversation_id
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_inbox_manager(inbox_manager)
        .build()
        .await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/mark-spam"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the refreshed thread reports the spam mark in a focused notice
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = std::str::from_utf8(&bytes).unwrap();
    assert!(html.contains("id=\"inbox-conversation\""));
    assert!(html.contains("data-inbox-spam-notice"));
    assert!(html.contains("data-inbox-action-notice>Conversation marked as spam.</div>"));
    assert!(html.contains("autofocus"));
}

#[tokio::test]
async fn test_mark_spam_returns_rejected_message() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::InboxWrite);

    // Setup inbox manager mock with a rejection
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_mark_conversation_as_spam()
        .times(1)
        .returning(|_| {
            Box::pin(async { Err(InboxError::Rejected("inbox unavailable".to_string())) })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_inbox_manager(inbox_manager)
        .build()
        .await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/group/inbox/{}/mark-spam", Uuid::new_v4()),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(std::str::from_utf8(&bytes).unwrap(), "inbox unavailable");
}

#[tokio::test]
async fn test_reply_passes_identifiers_and_renders_focused_thread() {
    // Setup identifiers and the reloaded thread
    let ids = DashboardIds::new();
    let inbox_conversation_id = Uuid::new_v4();
    let conversation = sample_inbox_conversation(inbox_conversation_id);

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::InboxWrite);
    db.expect_get_group_inbox_conversation()
        .times(1)
        .withf(move |group_id, conversation_id| {
            *group_id == ids.group_id && *conversation_id == inbox_conversation_id
        })
        .returning(move |_, _| Ok(Some(conversation.clone())));

    // Setup inbox manager mock
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_add_group_reply()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == ids.user_id
                && input.body == "Doors open at 6pm."
                && input.group_id == ids.group_id
                && input.inbox_conversation_id == inbox_conversation_id
        })
        .returning(move |_| Box::pin(async move { Ok(inbox_conversation_id) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_inbox_manager(inbox_manager)
        .build()
        .await;
    let request = form_request(
        "POST",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/replies"),
        ids.session_id,
        "body=Doors+open+at+6pm.",
    );
    let (parts, bytes) = send(router, request).await;

    // Check the refreshed thread focuses the reply field without a notice
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = std::str::from_utf8(&bytes).unwrap();
    assert!(html.contains("id=\"inbox-conversation\""));
    assert!(html.contains("autofocus"));
    assert!(!html.contains("data-inbox-action-notice"));
}

#[tokio::test]
async fn test_reply_rejects_whitespace_only_body() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::InboxWrite);

    // Setup inbox manager mock without manager calls
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager.expect_add_group_reply().never();

    // Setup router and send request with a whitespace-only reply
    let router = TestRouterBuilder::new(db)
        .with_inbox_manager(inbox_manager)
        .build()
        .await;
    let request = form_request(
        "POST",
        &format!("/dashboard/group/inbox/{}/replies", Uuid::new_v4()),
        ids.session_id,
        "body=+%0A+",
    );
    let (parts, bytes) = send(router, request).await;

    // Check the validation failure
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        std::str::from_utf8(&bytes).unwrap(),
        "body: value cannot be empty or whitespace-only\n"
    );
}

#[tokio::test]
async fn test_reply_renders_notice_when_thread_cannot_be_reloaded() {
    // Setup identifiers
    let ids = DashboardIds::new();
    let inbox_conversation_id = Uuid::new_v4();

    // Setup database mock with a failing thread reload
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::InboxWrite);
    db.expect_get_group_inbox_conversation()
        .times(1)
        .returning(|_, _| Err(anyhow!("db error")));

    // Setup inbox manager mock
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_add_group_reply()
        .times(1)
        .returning(move |_| Box::pin(async move { Ok(inbox_conversation_id) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_inbox_manager(inbox_manager)
        .build()
        .await;
    let request = form_request(
        "POST",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/replies"),
        ids.session_id,
        "body=Hi",
    );
    let (parts, bytes) = send(router, request).await;

    // Check the committed reply is reported as sent
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = std::str::from_utf8(&bytes).unwrap();
    assert!(html.contains("data-inbox-action-done"));
    assert!(html.contains("Message sent."));
}

#[tokio::test]
async fn test_reply_returns_rejected_message() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::InboxWrite);

    // Setup inbox manager mock with a rejection
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager.expect_add_group_reply().times(1).returning(|_| {
        Box::pin(async { Err(InboxError::Rejected("inbox unavailable".to_string())) })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_inbox_manager(inbox_manager)
        .build()
        .await;
    let request = form_request(
        "POST",
        &format!("/dashboard/group/inbox/{}/replies", Uuid::new_v4()),
        ids.session_id,
        "body=Hi",
    );
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(std::str::from_utf8(&bytes).unwrap(), "inbox unavailable");
}

#[tokio::test]
async fn test_unmark_spam_passes_identifiers_and_renders_thread() {
    // Setup identifiers and the reloaded thread
    let ids = DashboardIds::new();
    let inbox_conversation_id = Uuid::new_v4();
    let mut conversation = sample_inbox_conversation(inbox_conversation_id);
    conversation.status = InboxConversationStatus::Open;

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::InboxWrite);
    db.expect_get_group_inbox_conversation()
        .times(1)
        .withf(move |group_id, conversation_id| {
            *group_id == ids.group_id && *conversation_id == inbox_conversation_id
        })
        .returning(move |_, _| Ok(Some(conversation.clone())));

    // Setup inbox manager mock
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_unmark_conversation_as_spam()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == ids.user_id
                && input.group_id == ids.group_id
                && input.inbox_conversation_id == inbox_conversation_id
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_inbox_manager(inbox_manager)
        .build()
        .await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/group/inbox/{inbox_conversation_id}/unmark-spam"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the refreshed thread reports the spam unmark in a focused notice
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = std::str::from_utf8(&bytes).unwrap();
    assert!(html.contains("id=\"inbox-conversation\""));
    assert!(html.contains("id=\"inbox-message-form\""));
    assert!(html.contains("data-inbox-action-notice>Conversation unmarked as spam.</div>"));
    assert!(html.contains("autofocus"));
}

#[tokio::test]
async fn test_unmark_spam_returns_rejected_message() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::InboxWrite);

    // Setup inbox manager mock with a rejection
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_unmark_conversation_as_spam()
        .times(1)
        .returning(|_| {
            Box::pin(async { Err(InboxError::Rejected("inbox unavailable".to_string())) })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_inbox_manager(inbox_manager)
        .build()
        .await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/group/inbox/{}/unmark-spam", Uuid::new_v4()),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(std::str::from_utf8(&bytes).unwrap(), "inbox unavailable");
}
