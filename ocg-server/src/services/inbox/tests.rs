use std::sync::Arc;

use anyhow::anyhow;
use mockall::Sequence;
use serde_json::from_value;
use uuid::Uuid;

use crate::{
    db::{
        inbox::{PostedInboxMessage, StartInboxConversationConflict, StartInboxConversationResult},
        mock::MockDB,
    },
    templates::notifications::{InboxMessageReceived, InboxReplyReceived},
    types::{
        inbox::{InboxConversation, InboxMessage, InboxMessageKind},
        notifications::NotificationKind,
        tests::{sample_inbox_conversation, sample_site_settings, sample_template_user},
    },
};

use super::*;

#[tokio::test]
async fn test_add_group_reply_commits_reply_with_notification() {
    // Setup identifiers and the posted reply
    let actor_user_id = Uuid::new_v4();
    let posted = sample_posted();
    let conversation = sample_conversation_with_reply(posted);
    let user_id = conversation.user.as_ref().unwrap().user_id;

    // Setup transaction mock with the reply before the email
    let mut db = MockDB::new();
    let mut tx = MockDB::new();
    let mut sequence = Sequence::new();
    tx.expect_add_inbox_group_reply()
        .times(1)
        .withf(move |uid, gid, cid, body| {
            *uid == actor_user_id
                && *gid == posted.group_id
                && *cid == posted.inbox_conversation_id
                && body == "Doors open at 6pm."
        })
        .in_sequence(&mut sequence)
        .returning(move |_, _, _, _| Ok(posted));
    tx.expect_get_group_inbox_conversation()
        .times(1)
        .withf(move |gid, cid| *gid == posted.group_id && *cid == posted.inbox_conversation_id)
        .in_sequence(&mut sequence)
        .returning(move |_, _| Ok(Some(conversation.clone())));
    tx.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::InboxReplyReceived)
                && notification.recipients == vec![user_id]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<InboxReplyReceived>(value.clone())
                        .is_ok_and(|template| template.body == "Doors open at 6pm.")
                })
        })
        .returning(|_| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Run the workflow
    let manager = PgInboxManager::new(Arc::new(db));
    let result = manager
        .add_group_reply(&GroupReplyInput {
            actor_user_id,
            body: "Doors open at 6pm.".to_string(),
            group_id: posted.group_id,
            inbox_conversation_id: posted.inbox_conversation_id,
        })
        .await;

    // Check the conversation identifier is returned
    assert_eq!(result.unwrap(), posted.inbox_conversation_id);
}

#[tokio::test]
async fn test_add_group_reply_rolls_back_when_enqueue_fails() {
    // Setup identifiers and the posted reply
    let posted = sample_posted();
    let conversation = sample_conversation_with_reply(posted);

    // Setup transaction mock with a failing enqueue
    let mut db = MockDB::new();
    let mut tx = MockDB::new();
    tx.expect_add_inbox_group_reply()
        .times(1)
        .returning(move |_, _, _, _| Ok(posted));
    tx.expect_get_group_inbox_conversation()
        .times(1)
        .returning(move |_, _| Ok(Some(conversation.clone())));
    tx.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    tx.expect_enqueue_notification()
        .times(1)
        .returning(|_| Err(anyhow!("enqueue failed")));
    expect_rolled_back_transaction(&mut db, tx);

    // Run the workflow
    let manager = PgInboxManager::new(Arc::new(db));
    let result = manager
        .add_group_reply(&GroupReplyInput {
            actor_user_id: Uuid::new_v4(),
            body: "Doors open at 6pm.".to_string(),
            group_id: posted.group_id,
            inbox_conversation_id: posted.inbox_conversation_id,
        })
        .await;

    // Check the enqueue failure is returned unchanged
    assert!(matches!(result, Err(InboxError::Other(err)) if err.to_string() == "enqueue failed"));
}

#[tokio::test]
async fn test_add_group_reply_rolls_back_when_reply_fails() {
    // Setup transaction mock with a rejected reply
    let mut db = MockDB::new();
    let mut tx = MockDB::new();
    tx.expect_add_inbox_group_reply()
        .times(1)
        .returning(|_, _, _, _| Err(anyhow!("conversation is read-only")));
    tx.expect_get_group_inbox_conversation().never();
    tx.expect_enqueue_notification().never();
    expect_rolled_back_transaction(&mut db, tx);

    // Run the workflow
    let manager = PgInboxManager::new(Arc::new(db));
    let result = manager
        .add_group_reply(&GroupReplyInput {
            actor_user_id: Uuid::new_v4(),
            body: "Hi".to_string(),
            group_id: Uuid::new_v4(),
            inbox_conversation_id: Uuid::new_v4(),
        })
        .await;

    // Check the database error is preserved for the handler to classify
    assert!(
        matches!(result, Err(InboxError::Other(err)) if err.to_string() == "conversation is read-only")
    );
}

#[tokio::test]
async fn test_add_user_message_commits_message_with_notification() {
    // Setup identifiers and the posted follow-up
    let recipient_id = Uuid::new_v4();
    let posted = sample_posted();
    let mut conversation = sample_inbox_conversation(posted.inbox_conversation_id);
    conversation.messages[0].inbox_message_id = posted.inbox_message_id;
    let user_id = conversation.user.as_ref().unwrap().user_id;

    // Setup transaction mock with the message before the email
    let mut db = MockDB::new();
    let mut tx = MockDB::new();
    let mut sequence = Sequence::new();
    tx.expect_add_inbox_user_message()
        .times(1)
        .withf(move |uid, cid, body| {
            *uid == user_id && *cid == posted.inbox_conversation_id && body == "Any update?"
        })
        .in_sequence(&mut sequence)
        .returning(move |_, _, _| Ok(posted));
    tx.expect_get_group_inbox_conversation()
        .times(1)
        .in_sequence(&mut sequence)
        .returning(move |_, _| Ok(Some(conversation.clone())));
    tx.expect_list_inbox_recipient_ids()
        .times(1)
        .withf(move |gid| *gid == posted.group_id)
        .returning(move |_| Ok(vec![recipient_id]));
    tx.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::InboxMessageReceived)
                && notification.recipients == vec![recipient_id]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<InboxMessageReceived>(value.clone())
                        .is_ok_and(|template| template.group_name == "Test Group")
                })
        })
        .returning(|_| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Run the workflow
    let manager = PgInboxManager::new(Arc::new(db));
    let result = manager
        .add_user_message(&UserMessageInput {
            body: "Any update?".to_string(),
            inbox_conversation_id: posted.inbox_conversation_id,
            user_id,
        })
        .await;

    // Check the conversation identifier is returned
    assert_eq!(result.unwrap(), posted.inbox_conversation_id);
}

#[tokio::test]
async fn test_add_user_message_rolls_back_when_enqueue_fails() {
    // Setup identifiers and the posted follow-up
    let posted = sample_posted();
    let mut conversation = sample_inbox_conversation(posted.inbox_conversation_id);
    conversation.messages[0].inbox_message_id = posted.inbox_message_id;

    // Setup transaction mock with a failing enqueue
    let mut db = MockDB::new();
    let mut tx = MockDB::new();
    tx.expect_add_inbox_user_message()
        .times(1)
        .returning(move |_, _, _| Ok(posted));
    tx.expect_get_group_inbox_conversation()
        .times(1)
        .returning(move |_, _| Ok(Some(conversation.clone())));
    tx.expect_list_inbox_recipient_ids()
        .times(1)
        .returning(|_| Ok(vec![Uuid::new_v4()]));
    tx.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    tx.expect_enqueue_notification()
        .times(1)
        .returning(|_| Err(anyhow!("enqueue failed")));
    expect_rolled_back_transaction(&mut db, tx);

    // Run the workflow
    let manager = PgInboxManager::new(Arc::new(db));
    let result = manager
        .add_user_message(&UserMessageInput {
            body: "Any update?".to_string(),
            inbox_conversation_id: posted.inbox_conversation_id,
            user_id: Uuid::new_v4(),
        })
        .await;

    // Check the enqueue failure is returned unchanged
    assert!(matches!(result, Err(InboxError::Other(err)) if err.to_string() == "enqueue failed"));
}

#[tokio::test]
async fn test_add_user_message_rolls_back_when_message_fails() {
    // Setup transaction mock with a rejected follow-up
    let mut db = MockDB::new();
    let mut tx = MockDB::new();
    tx.expect_add_inbox_user_message()
        .times(1)
        .returning(|_, _, _| Err(anyhow!("daily message limit reached")));
    tx.expect_get_group_inbox_conversation().never();
    tx.expect_enqueue_notification().never();
    expect_rolled_back_transaction(&mut db, tx);

    // Run the workflow
    let manager = PgInboxManager::new(Arc::new(db));
    let result = manager
        .add_user_message(&UserMessageInput {
            body: "Any update?".to_string(),
            inbox_conversation_id: Uuid::new_v4(),
            user_id: Uuid::new_v4(),
        })
        .await;

    // Check the database error is preserved for the handler to classify
    assert!(
        matches!(result, Err(InboxError::Other(err)) if err.to_string() == "daily message limit reached")
    );
}

#[tokio::test]
async fn test_close_conversation_returns_error_when_close_fails() {
    // Setup database mock with a rejected close
    let mut db = MockDB::new();
    db.expect_begin().never();
    db.expect_close_inbox_conversation()
        .times(1)
        .returning(|_, _, _| Err(anyhow!("conversation not found")));

    // Run the workflow
    let manager = PgInboxManager::new(Arc::new(db));
    let result = manager
        .close_conversation(&GroupConversationInput {
            actor_user_id: Uuid::new_v4(),
            group_id: Uuid::new_v4(),
            inbox_conversation_id: Uuid::new_v4(),
        })
        .await;

    // Check the database error is preserved for the handler to classify
    assert!(
        matches!(result, Err(InboxError::Other(err)) if err.to_string() == "conversation not found")
    );
}

#[tokio::test]
async fn test_close_conversation_succeeds_without_transaction_or_notification() {
    // Setup identifiers
    let actor_user_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let inbox_conversation_id = Uuid::new_v4();

    // Setup database mock with a single write and no emails
    let mut db = MockDB::new();
    db.expect_begin().never();
    db.expect_close_inbox_conversation()
        .times(1)
        .withf(move |uid, gid, cid| {
            *uid == actor_user_id && *gid == group_id && *cid == inbox_conversation_id
        })
        .returning(|_, _, _| Ok(()));
    db.expect_enqueue_notification().never();

    // Run the workflow
    let manager = PgInboxManager::new(Arc::new(db));
    let result = manager
        .close_conversation(&GroupConversationInput {
            actor_user_id,
            group_id,
            inbox_conversation_id,
        })
        .await;

    // Check the workflow succeeded
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_mark_conversation_as_spam_returns_error_when_mark_fails() {
    // Setup database mock with a rejected mark
    let mut db = MockDB::new();
    db.expect_begin().never();
    db.expect_mark_inbox_conversation_as_spam()
        .times(1)
        .returning(|_, _, _| Err(anyhow!("conversation not found")));

    // Run the workflow
    let manager = PgInboxManager::new(Arc::new(db));
    let result = manager
        .mark_conversation_as_spam(&GroupConversationInput {
            actor_user_id: Uuid::new_v4(),
            group_id: Uuid::new_v4(),
            inbox_conversation_id: Uuid::new_v4(),
        })
        .await;

    // Check the database error is preserved for the handler to classify
    assert!(
        matches!(result, Err(InboxError::Other(err)) if err.to_string() == "conversation not found")
    );
}

#[tokio::test]
async fn test_mark_conversation_as_spam_succeeds_without_transaction_or_notification() {
    // Setup identifiers
    let actor_user_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let inbox_conversation_id = Uuid::new_v4();

    // Setup database mock with a single write and no emails
    let mut db = MockDB::new();
    db.expect_begin().never();
    db.expect_mark_inbox_conversation_as_spam()
        .times(1)
        .withf(move |uid, gid, cid| {
            *uid == actor_user_id && *gid == group_id && *cid == inbox_conversation_id
        })
        .returning(|_, _, _| Ok(()));
    db.expect_enqueue_notification().never();

    // Run the workflow
    let manager = PgInboxManager::new(Arc::new(db));
    let result = manager
        .mark_conversation_as_spam(&GroupConversationInput {
            actor_user_id,
            group_id,
            inbox_conversation_id,
        })
        .await;

    // Check the workflow succeeded
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_start_conversation_commits_conversation_with_notification() {
    // Setup identifiers and the posted first message
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let recipient_id = Uuid::new_v4();
    let posted = sample_posted();
    let mut conversation = sample_inbox_conversation(posted.inbox_conversation_id);
    conversation.messages[0].inbox_message_id = posted.inbox_message_id;
    let user_id = conversation.user.as_ref().unwrap().user_id;

    // Setup transaction mock with the conversation before the email
    let mut db = MockDB::new();
    let mut tx = MockDB::new();
    let mut sequence = Sequence::new();
    tx.expect_start_inbox_conversation()
        .times(1)
        .withf(move |uid, cid, eid, body| {
            *uid == user_id && *cid == community_id && *eid == event_id && body == "Hello"
        })
        .in_sequence(&mut sequence)
        .returning(move |_, _, _, _| Ok(StartInboxConversationResult::Started(posted)));
    tx.expect_get_group_inbox_conversation()
        .times(1)
        .withf(move |gid, cid| *gid == posted.group_id && *cid == posted.inbox_conversation_id)
        .in_sequence(&mut sequence)
        .returning(move |_, _| Ok(Some(conversation.clone())));
    tx.expect_list_inbox_recipient_ids()
        .times(1)
        .returning(move |_| Ok(vec![recipient_id]));
    tx.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::InboxMessageReceived)
                && notification.recipients == vec![recipient_id]
        })
        .returning(|_| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Run the workflow
    let manager = PgInboxManager::new(Arc::new(db));
    let result = manager
        .start_conversation(&StartConversationInput {
            body: "Hello".to_string(),
            community_id,
            event_id,
            user_id,
        })
        .await;

    // Check the conversation identifier is returned
    assert_eq!(result.unwrap(), posted.inbox_conversation_id);
}

#[tokio::test]
async fn test_start_conversation_rejects_open_conversation_conflict() {
    // Setup transaction mock with a conflict
    let mut db = MockDB::new();
    let mut tx = MockDB::new();
    tx.expect_start_inbox_conversation().times(1).returning(|_, _, _, _| {
        Ok(StartInboxConversationResult::Conflict(
            StartInboxConversationConflict::OpenConversation,
        ))
    });
    tx.expect_get_group_inbox_conversation().never();
    tx.expect_list_inbox_recipient_ids().never();
    tx.expect_enqueue_notification().never();
    expect_successful_transaction(&mut db, tx);

    // Run the workflow
    let manager = PgInboxManager::new(Arc::new(db));
    let result = manager
        .start_conversation(&StartConversationInput {
            body: "Hello".to_string(),
            community_id: Uuid::new_v4(),
            event_id: Uuid::new_v4(),
            user_id: Uuid::new_v4(),
        })
        .await;

    // Check the conflict becomes a user-facing rejection
    assert!(matches!(
        result,
        Err(InboxError::Rejected(message)) if message == OPEN_CONVERSATION_REJECTION
    ));
}

#[tokio::test]
async fn test_start_conversation_rolls_back_when_enqueue_fails() {
    // Setup identifiers and the posted first message
    let posted = sample_posted();
    let mut conversation = sample_inbox_conversation(posted.inbox_conversation_id);
    conversation.messages[0].inbox_message_id = posted.inbox_message_id;

    // Setup transaction mock with a failing enqueue
    let mut db = MockDB::new();
    let mut tx = MockDB::new();
    tx.expect_start_inbox_conversation()
        .times(1)
        .returning(move |_, _, _, _| Ok(StartInboxConversationResult::Started(posted)));
    tx.expect_get_group_inbox_conversation()
        .times(1)
        .returning(move |_, _| Ok(Some(conversation.clone())));
    tx.expect_list_inbox_recipient_ids()
        .times(1)
        .returning(|_| Ok(vec![Uuid::new_v4()]));
    tx.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    tx.expect_enqueue_notification()
        .times(1)
        .returning(|_| Err(anyhow!("enqueue failed")));
    expect_rolled_back_transaction(&mut db, tx);

    // Run the workflow
    let manager = PgInboxManager::new(Arc::new(db));
    let result = manager
        .start_conversation(&StartConversationInput {
            body: "Hello".to_string(),
            community_id: Uuid::new_v4(),
            event_id: Uuid::new_v4(),
            user_id: Uuid::new_v4(),
        })
        .await;

    // Check the enqueue failure is returned unchanged
    assert!(matches!(result, Err(InboxError::Other(err)) if err.to_string() == "enqueue failed"));
}

#[tokio::test]
async fn test_start_conversation_rolls_back_when_start_fails() {
    // Setup transaction mock with a rejected start
    let mut db = MockDB::new();
    let mut tx = MockDB::new();
    tx.expect_start_inbox_conversation()
        .times(1)
        .returning(|_, _, _, _| Err(anyhow!("group team members cannot contact their own group")));
    tx.expect_enqueue_notification().never();
    expect_rolled_back_transaction(&mut db, tx);

    // Run the workflow
    let manager = PgInboxManager::new(Arc::new(db));
    let result = manager
        .start_conversation(&StartConversationInput {
            body: "Hello".to_string(),
            community_id: Uuid::new_v4(),
            event_id: Uuid::new_v4(),
            user_id: Uuid::new_v4(),
        })
        .await;

    // Check the database error is preserved for the handler to classify
    assert!(matches!(
        result,
        Err(InboxError::Other(err)) if err.to_string() == "group team members cannot contact their own group"
    ));
}

#[tokio::test]
async fn test_unmark_conversation_as_spam_returns_error_when_unmark_fails() {
    // Setup database mock with a rejected unmark
    let mut db = MockDB::new();
    db.expect_begin().never();
    db.expect_unmark_inbox_conversation_as_spam()
        .times(1)
        .returning(|_, _, _| Err(anyhow!("conversation not found")));

    // Run the workflow
    let manager = PgInboxManager::new(Arc::new(db));
    let result = manager
        .unmark_conversation_as_spam(&GroupConversationInput {
            actor_user_id: Uuid::new_v4(),
            group_id: Uuid::new_v4(),
            inbox_conversation_id: Uuid::new_v4(),
        })
        .await;

    // Check the database error is preserved for the handler to classify
    assert!(
        matches!(result, Err(InboxError::Other(err)) if err.to_string() == "conversation not found")
    );
}

#[tokio::test]
async fn test_unmark_conversation_as_spam_succeeds_without_transaction_or_notification() {
    // Setup identifiers
    let actor_user_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let inbox_conversation_id = Uuid::new_v4();

    // Setup database mock with a single write and no emails
    let mut db = MockDB::new();
    db.expect_begin().never();
    db.expect_unmark_inbox_conversation_as_spam()
        .times(1)
        .withf(move |uid, gid, cid| {
            *uid == actor_user_id && *gid == group_id && *cid == inbox_conversation_id
        })
        .returning(|_, _, _| Ok(()));
    db.expect_enqueue_notification().never();

    // Run the workflow
    let manager = PgInboxManager::new(Arc::new(db));
    let result = manager
        .unmark_conversation_as_spam(&GroupConversationInput {
            actor_user_id,
            group_id,
            inbox_conversation_id,
        })
        .await;

    // Check the workflow succeeded
    assert!(result.is_ok());
}

// Helpers.

/// Expects a transaction that rolls back without committing.
fn expect_rolled_back_transaction(db: &mut MockDB, mut tx: MockDB) {
    tx.expect_commit().never();
    tx.expect_rollback().times(1).returning(|| Ok(()));
    db.expect_begin().times(1).return_once(|| Ok(Box::new(tx)));
}

/// Expects a transaction that commits without rolling back.
fn expect_successful_transaction(db: &mut MockDB, mut tx: MockDB) {
    tx.expect_commit().times(1).returning(|| Ok(()));
    tx.expect_rollback().never();
    db.expect_begin().times(1).return_once(|| Ok(Box::new(tx)));
}

/// Builds a conversation whose latest message is the posted group reply.
fn sample_conversation_with_reply(posted: PostedInboxMessage) -> InboxConversation {
    let mut conversation = sample_inbox_conversation(posted.inbox_conversation_id);
    conversation.messages.push(InboxMessage {
        body: "Doors open at 6pm.".to_string(),
        created_at: conversation.created_at,
        inbox_message_id: posted.inbox_message_id,
        kind: InboxMessageKind::GroupReply,

        author: Some(sample_template_user()),
    });
    conversation
}

/// Builds the identifiers of a posted inbox message.
fn sample_posted() -> PostedInboxMessage {
    PostedInboxMessage {
        group_id: Uuid::new_v4(),
        inbox_conversation_id: Uuid::new_v4(),
        inbox_message_id: Uuid::new_v4(),
    }
}
