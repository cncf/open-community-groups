//! Contract tests for the `DBInbox` functions and the inbox manager.

use anyhow::Result;
use chrono::{TimeZone, Utc};
use tokio_postgres::error::{DbError, SqlState};
use uuid::Uuid;

use crate::{
    db::{
        USER_FACING_DB_ERROR_CODE,
        inbox::{DBInbox, StartInboxConversationConflict, StartInboxConversationResult},
    },
    types::inbox::{InboxConversationStatus, InboxConversationsFilters, InboxMessageKind},
};

use super::helpers::*;

/// Inactive community holding every inbox fixture.
const INBOX_COMMUNITY_ID: Uuid = Uuid::from_u128(0xe001);
/// Group team member with the admin role in the read and write groups.
const INBOX_ADMIN_ID: Uuid = Uuid::from_u128(0xe021);
/// Group team member with the events-manager role in the read and write groups.
const INBOX_EVENTS_MANAGER_ID: Uuid = Uuid::from_u128(0xe022);
/// Group team member with the viewer role in the read and write groups.
const INBOX_VIEWER_ID: Uuid = Uuid::from_u128(0xe023);
/// Group whose conversations are only read by the contracts.
const INBOX_READ_GROUP_ID: Uuid = Uuid::from_u128(0xe011);
/// Group receiving conversations written by the contracts.
const INBOX_WRITE_GROUP_ID: Uuid = Uuid::from_u128(0xe012);
/// User owning the open and closed read conversations.
const INBOX_USER_ID: Uuid = Uuid::from_u128(0xe024);
/// User with two conversations started today.
const INBOX_START_LIMIT_USER_ID: Uuid = Uuid::from_u128(0xe026);
/// User starting two conversations with the same group at once.
const INBOX_START_RACE_USER_ID: Uuid = Uuid::from_u128(0xe027);
/// User with nine follow-ups sent today.
const INBOX_FOLLOW_UP_LIMIT_USER_ID: Uuid = Uuid::from_u128(0xe028);
/// User owning the reply-close race conversation.
const INBOX_RACE_USER_ID: Uuid = Uuid::from_u128(0xe029);
/// User whose read group conversation was marked as spam.
const INBOX_SPAM_USER_ID: Uuid = Uuid::from_u128(0xe02b);
/// Published event owned by the read group and co-hosted by the co-host group.
const INBOX_READ_EVENT_ID: Uuid = Uuid::from_u128(0xe031);
/// Published event owned by the write group.
const INBOX_WRITE_EVENT_ID: Uuid = Uuid::from_u128(0xe032);
/// Published event owned by the co-host group.
const INBOX_COHOST_EVENT_ID: Uuid = Uuid::from_u128(0xe033);
/// Open read conversation with three messages.
const INBOX_OPEN_CONVERSATION_ID: Uuid = Uuid::from_u128(0xe041);
/// Closed read conversation without event.
const INBOX_CLOSED_CONVERSATION_ID: Uuid = Uuid::from_u128(0xe042);
/// Read conversation whose user account was deleted.
const INBOX_DELETED_USER_CONVERSATION_ID: Uuid = Uuid::from_u128(0xe043);
/// Open conversation raced by a reply and a close.
const INBOX_RACE_CONVERSATION_ID: Uuid = Uuid::from_u128(0xe044);
/// Open conversation of the follow-up limit user.
const INBOX_FOLLOW_UP_CONVERSATION_ID: Uuid = Uuid::from_u128(0xe045);
/// Read conversation marked as spam by the read group.
const INBOX_SPAM_CONVERSATION_ID: Uuid = Uuid::from_u128(0xe048);
/// Open conversation of the spam user marked and unmarked by the contracts.
const INBOX_SPAM_ROUND_TRIP_CONVERSATION_ID: Uuid = Uuid::from_u128(0xe049);

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_add_inbox_user_message_serializes_daily_limit() -> Result<()> {
    // Setup two connections and a lock probe
    let pool = contract_tests_pool()?;
    let first_client = pool.get().await?;
    let second_client = pool.get().await?;
    let probe_client = pool.get().await?;
    let first_backend_pid = backend_pid(&first_client).await?;
    let second_backend_pid = backend_pid(&second_client).await?;

    // Send the tenth follow-up of the day and keep its transaction open
    first_client.batch_execute("begin").await?;
    first_client
        .query_one(
            "select add_inbox_user_message($1::uuid, $2::uuid, 'Tenth')",
            &[
                &INBOX_FOLLOW_UP_LIMIT_USER_ID,
                &INBOX_FOLLOW_UP_CONVERSATION_ID,
            ],
        )
        .await?;

    // Send another follow-up at the same time
    let second_task = tokio::spawn(async move {
        second_client
            .query_one(
                "select add_inbox_user_message($1::uuid, $2::uuid, 'Eleventh')",
                &[
                    &INBOX_FOLLOW_UP_LIMIT_USER_ID,
                    &INBOX_FOLLOW_UP_CONVERSATION_ID,
                ],
            )
            .await
    });

    // Commit the first follow-up once the second one waits for the user lock
    wait_for_backend_blocker(&probe_client, first_backend_pid, second_backend_pid).await?;
    first_client.batch_execute("commit").await?;

    // Check the second follow-up observes the committed limit
    let err = second_task
        .await?
        .expect_err("the second follow-up should reach the daily limit");
    assert_eq!(
        err.as_db_error().map(DbError::message),
        Some("daily message limit reached")
    );
    assert_eq!(
        err.code(),
        Some(&SqlState::from_code(USER_FACING_DB_ERROR_CODE))
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_close_inbox_conversation_serializes_with_reply() -> Result<()> {
    // Setup two connections and a lock probe
    let pool = contract_tests_pool()?;
    let reply_client = pool.get().await?;
    let close_client = pool.get().await?;
    let probe_client = pool.get().await?;
    let reply_backend_pid = backend_pid(&reply_client).await?;
    let close_backend_pid = backend_pid(&close_client).await?;

    // Start the close transaction before the reply one, so audit times must
    // follow the lock order rather than the transaction start order
    close_client.batch_execute("begin").await?;

    // Reply to the conversation and keep the transaction open
    reply_client.batch_execute("begin").await?;
    reply_client
        .query_one(
            "select add_inbox_group_reply($1::uuid, $2::uuid, $3::uuid, 'Yes, it will be recorded.')",
            &[
                &INBOX_ADMIN_ID,
                &INBOX_WRITE_GROUP_ID,
                &INBOX_RACE_CONVERSATION_ID,
            ],
        )
        .await?;

    // Close the conversation at the same time
    let close_task = tokio::spawn(async move {
        close_client
            .execute(
                "select close_inbox_conversation($1::uuid, $2::uuid, $3::uuid)",
                &[
                    &INBOX_EVENTS_MANAGER_ID,
                    &INBOX_WRITE_GROUP_ID,
                    &INBOX_RACE_CONVERSATION_ID,
                ],
            )
            .await?;
        close_client.batch_execute("commit").await
    });

    // Commit the reply once the close waits for the conversation lock
    wait_for_backend_blocker(&probe_client, reply_backend_pid, close_backend_pid).await?;
    reply_client.batch_execute("commit").await?;
    close_task.await??;

    // Check the close applied after the reply without moving activity or audit time backwards
    let row = probe_client
        .query_one(
            "select
                ic.inbox_conversation_status_id,
                ic.last_message_at = (
                    select max(m.created_at)
                    from inbox_message m
                    where m.inbox_conversation_id = ic.inbox_conversation_id
                ),
                (
                    select array_agg(al.action order by al.created_at, al.action)
                    from audit_log al
                    where al.resource_id = ic.inbox_conversation_id
                )
            from inbox_conversation ic
            where ic.inbox_conversation_id = $1::uuid",
            &[&INBOX_RACE_CONVERSATION_ID],
        )
        .await?;
    assert_eq!(row.get::<_, String>(0), "closed");
    assert!(row.get::<_, bool>(1));
    assert_eq!(
        row.get::<_, Vec<String>>(2),
        vec![
            "inbox_reply_sent".to_string(),
            "inbox_conversation_closed".to_string()
        ]
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_count_group_open_inbox_conversations_counts_open_only() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Count the open conversations of the read group
    let count = db.count_group_open_inbox_conversations(INBOX_READ_GROUP_ID).await?;

    // Check the open and deleted-user conversations are counted
    assert_eq!(count, 2);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_inbox_conversation_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load the open read conversation through the Rust contract
    let conversation = db
        .get_group_inbox_conversation(INBOX_READ_GROUP_ID, INBOX_OPEN_CONVERSATION_ID)
        .await?
        .expect("read conversation to exist");

    // Check required fields
    assert_eq!(
        conversation.community_display_name,
        "Contract Inbox Community"
    );
    assert_eq!(conversation.community_name, "contract-inbox-community");
    assert_eq!(
        conversation.created_at,
        Utc.with_ymd_and_hms(2024, 2, 1, 10, 0, 0).unwrap()
    );
    assert_eq!(conversation.group_name, "Contract Inbox Read Group");
    assert_eq!(conversation.group_slug, "contract-inbox-read-group");
    assert_eq!(
        conversation.inbox_conversation_id,
        INBOX_OPEN_CONVERSATION_ID
    );
    assert_eq!(
        conversation.last_message_at,
        Utc.with_ymd_and_hms(2024, 2, 1, 12, 0, 0).unwrap()
    );
    assert_eq!(conversation.status, InboxConversationStatus::Open);

    // Check the messages in chronological order with their authors
    let kinds: Vec<_> = conversation.messages.iter().map(|message| message.kind).collect();
    assert_eq!(
        kinds,
        vec![
            InboxMessageKind::Initial,
            InboxMessageKind::GroupReply,
            InboxMessageKind::UserReply
        ]
    );
    let first = &conversation.messages[0];
    assert_eq!(first.body, "When do doors open?");
    assert_eq!(
        first.created_at,
        Utc.with_ymd_and_hms(2024, 2, 1, 10, 0, 0).unwrap()
    );
    assert_eq!(first.inbox_message_id, Uuid::from_u128(0xe051));
    assert_eq!(
        first.author.as_ref().map(|author| author.username.as_str()),
        Some("contract-inbox-user")
    );
    assert_eq!(
        conversation.messages[1]
            .author
            .as_ref()
            .and_then(|author| author.name.as_deref()),
        Some("Inbox Admin")
    );

    // Check optional fields
    let event = conversation.event.as_ref().expect("event to exist");
    assert!(event.is_public);
    assert_eq!(event.name, "Contract Inbox Read Event");
    assert_eq!(event.slug.as_deref(), Some("contract-inbox-read-event"));
    assert_eq!(
        conversation.group_slug_pretty.as_deref(),
        Some("inbox-read")
    );
    let user = conversation.user.as_ref().expect("user to exist");
    assert_eq!(user.user_id, INBOX_USER_ID);
    assert_eq!(user.name.as_deref(), Some("Inbox User"));
    assert_eq!(
        conversation.event_url().as_deref(),
        Some("/contract-inbox-community/group/inbox-read/event/contract-inbox-read-event")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_inbox_conversation_deserializes_deleted_user() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load the conversation whose user account was deleted
    let conversation = db
        .get_group_inbox_conversation(INBOX_READ_GROUP_ID, INBOX_DELETED_USER_CONVERSATION_ID)
        .await?
        .expect("deleted-user conversation to exist");

    // Check JSON null user and author deserialize as absent
    assert!(conversation.user.is_none());
    assert!(conversation.is_read_only());
    assert_eq!(conversation.messages.len(), 1);
    assert!(conversation.messages[0].author.is_none());
    assert_eq!(conversation.messages[0].body, "Please remove my data.");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_inbox_contact_context_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load the contact context for anonymous, team member, read-only member and regular viewers
    let anonymous = db
        .get_inbox_contact_context(INBOX_COMMUNITY_ID, INBOX_READ_EVENT_ID, None)
        .await?
        .expect("contact context to exist");
    let team_member = db
        .get_inbox_contact_context(
            INBOX_COMMUNITY_ID,
            INBOX_READ_EVENT_ID,
            Some(INBOX_ADMIN_ID),
        )
        .await?
        .expect("contact context to exist");
    let read_only_member = db
        .get_inbox_contact_context(
            INBOX_COMMUNITY_ID,
            INBOX_READ_EVENT_ID,
            Some(INBOX_VIEWER_ID),
        )
        .await?
        .expect("contact context to exist");
    let user = db
        .get_inbox_contact_context(INBOX_COMMUNITY_ID, INBOX_READ_EVENT_ID, Some(INBOX_USER_ID))
        .await?
        .expect("contact context to exist");
    let spam_user = db
        .get_inbox_contact_context(
            INBOX_COMMUNITY_ID,
            INBOX_READ_EVENT_ID,
            Some(INBOX_SPAM_USER_ID),
        )
        .await?
        .expect("contact context to exist");

    // Check the anonymous context
    assert_eq!(anonymous.community_name, "contract-inbox-community");
    assert_eq!(anonymous.event_id, INBOX_READ_EVENT_ID);
    assert_eq!(anonymous.event_name, "Contract Inbox Read Event");
    assert_eq!(anonymous.event_slug, "contract-inbox-read-event");
    assert_eq!(anonymous.group_name, "Contract Inbox Read Group");
    assert_eq!(anonymous.group_slug, "contract-inbox-read-group");
    assert_eq!(anonymous.group_slug_pretty.as_deref(), Some("inbox-read"));
    assert!(anonymous.viewer.is_none());

    // Check the team member, read-only member, regular and blocked viewer states
    let team_member_viewer = team_member.viewer.expect("team member viewer to exist");
    assert!(team_member_viewer.can_manage_inbox);
    assert!(team_member_viewer.can_start_conversation);
    assert!(!team_member_viewer.is_blocked);
    assert!(team_member_viewer.is_group_team_member);
    assert_eq!(team_member_viewer.open_inbox_conversation_id, None);
    let read_only_member_viewer =
        read_only_member.viewer.expect("read-only member viewer to exist");
    assert!(!read_only_member_viewer.can_manage_inbox);
    assert!(read_only_member_viewer.is_group_team_member);
    let user_viewer = user.viewer.expect("user viewer to exist");
    assert!(!user_viewer.can_manage_inbox);
    assert!(user_viewer.can_start_conversation);
    assert!(!user_viewer.is_blocked);
    assert!(!user_viewer.is_group_team_member);
    assert_eq!(
        user_viewer.open_inbox_conversation_id,
        Some(INBOX_OPEN_CONVERSATION_ID)
    );
    let spam_user_viewer = spam_user.viewer.expect("spam user viewer to exist");
    assert!(spam_user_viewer.is_blocked);
    assert!(!spam_user_viewer.is_group_team_member);
    assert_eq!(spam_user_viewer.open_inbox_conversation_id, None);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_user_inbox_conversation_scopes_by_user() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load the conversation as its owner and as another user
    let owned = db
        .get_user_inbox_conversation(INBOX_USER_ID, INBOX_OPEN_CONVERSATION_ID)
        .await?;
    let foreign = db
        .get_user_inbox_conversation(INBOX_RACE_USER_ID, INBOX_OPEN_CONVERSATION_ID)
        .await?;

    // Check only the owner can read the thread
    assert_eq!(
        owned.map(|conversation| conversation.inbox_conversation_id),
        Some(INBOX_OPEN_CONVERSATION_ID)
    );
    assert!(foreign.is_none());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_inbox_rejections_use_user_facing_sqlstate() -> Result<()> {
    // Setup the contract database
    let client = contract_tests_pool()?.get().await?;

    // Reply to a conversation whose user account was deleted
    let err = client
        .query_one(
            "select add_inbox_group_reply($1::uuid, $2::uuid, $3::uuid, 'Hi')",
            &[
                &INBOX_ADMIN_ID,
                &INBOX_READ_GROUP_ID,
                &INBOX_DELETED_USER_CONVERSATION_ID,
            ],
        )
        .await
        .expect_err("read-only conversations should reject replies");

    // Check the rejection is user facing
    assert_eq!(
        err.as_db_error().map(DbError::message),
        Some("conversation is read-only")
    );
    assert_eq!(
        err.code(),
        Some(&SqlState::from_code(USER_FACING_DB_ERROR_CODE))
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_group_inbox_conversations_deserializes() -> Result<()> {
    // Setup the contract database and filters
    let db = contract_tests_db()?;
    let all = InboxConversationsFilters {
        limit: Some(10),
        offset: Some(0),

        status: None,
    };
    let closed = InboxConversationsFilters {
        status: Some(InboxConversationStatus::Closed),
        ..all.clone()
    };
    let spam = InboxConversationsFilters {
        status: Some(InboxConversationStatus::Spam),
        ..all.clone()
    };

    // List the read group conversations
    let output = db.list_group_inbox_conversations(INBOX_READ_GROUP_ID, &all).await?;
    let closed_output = db
        .list_group_inbox_conversations(INBOX_READ_GROUP_ID, &closed)
        .await?;
    let spam_output = db.list_group_inbox_conversations(INBOX_READ_GROUP_ID, &spam).await?;

    // Check ordering and totals, leaving spam out unless filtered by it
    let ids: Vec<_> = output
        .conversations
        .iter()
        .map(|conversation| conversation.inbox_conversation_id)
        .collect();
    assert_eq!(
        ids,
        vec![
            INBOX_OPEN_CONVERSATION_ID,
            INBOX_DELETED_USER_CONVERSATION_ID,
            INBOX_CLOSED_CONVERSATION_ID
        ]
    );
    assert_eq!(output.total, 3);
    assert_eq!(closed_output.total, 1);
    assert_eq!(
        closed_output.conversations[0].inbox_conversation_id,
        INBOX_CLOSED_CONVERSATION_ID
    );
    assert_eq!(spam_output.total, 1);
    assert_eq!(
        spam_output.conversations[0].inbox_conversation_id,
        INBOX_SPAM_CONVERSATION_ID
    );
    assert_eq!(
        spam_output.conversations[0].status,
        InboxConversationStatus::Spam
    );

    // Check the latest-message projection of the first row
    let first = &output.conversations[0];
    assert_eq!(first.community_display_name, "Contract Inbox Community");
    assert_eq!(first.group_name, "Contract Inbox Read Group");
    assert_eq!(first.last_message_excerpt, "Is there parking nearby?");
    assert_eq!(first.last_message_kind, InboxMessageKind::UserReply);
    assert_eq!(first.status, InboxConversationStatus::Open);
    let event = first.event.as_ref().expect("event to exist");
    assert_eq!(event.name, "Contract Inbox Read Event");
    assert!(event.slug.is_none());
    assert_eq!(
        first.user.as_ref().map(|user| user.user_id),
        Some(INBOX_USER_ID)
    );

    // Check a deleted user and a missing event deserialize as absent
    assert!(output.conversations[1].user.is_none());
    assert!(output.conversations[2].event.is_none());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_inbox_recipient_ids_returns_group_team_members() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // List the group team members emailed by the read group
    let recipients = db.list_inbox_recipient_ids(INBOX_READ_GROUP_ID).await?;

    // Check the viewer is excluded
    assert_eq!(recipients, vec![INBOX_ADMIN_ID, INBOX_EVENTS_MANAGER_ID]);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_inbox_conversations_deserializes() -> Result<()> {
    // Setup the contract database and filters
    let db = contract_tests_db()?;
    let filters = InboxConversationsFilters {
        limit: Some(10),
        offset: Some(0),

        status: None,
    };

    // List the conversations of the inbox user
    let output = db.list_user_inbox_conversations(INBOX_USER_ID, &filters).await?;

    // Check ordering and totals
    let ids: Vec<_> = output
        .conversations
        .iter()
        .map(|conversation| conversation.inbox_conversation_id)
        .collect();
    assert_eq!(
        ids,
        vec![INBOX_OPEN_CONVERSATION_ID, INBOX_CLOSED_CONVERSATION_ID]
    );
    assert_eq!(output.total, 2);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_mark_inbox_conversation_as_spam_round_trips() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;
    let client = contract_tests_pool()?.get().await?;

    // Mark the conversation as spam
    db.mark_inbox_conversation_as_spam(
        INBOX_ADMIN_ID,
        INBOX_WRITE_GROUP_ID,
        INBOX_SPAM_ROUND_TRIP_CONVERSATION_ID,
    )
    .await?;
    let marked = db
        .get_user_inbox_conversation(INBOX_SPAM_USER_ID, INBOX_SPAM_ROUND_TRIP_CONVERSATION_ID)
        .await?
        .expect("conversation to exist");

    // Check the user sees the spam status and can no longer write
    assert_eq!(marked.status, InboxConversationStatus::Spam);
    let err = client
        .query_one(
            "select add_inbox_user_message($1::uuid, $2::uuid, 'Hello?')",
            &[&INBOX_SPAM_USER_ID, &INBOX_SPAM_ROUND_TRIP_CONVERSATION_ID],
        )
        .await
        .expect_err("conversations marked as spam should reject messages");
    assert_eq!(
        err.as_db_error().map(DbError::message),
        Some("conversation no longer accepts messages")
    );
    assert_eq!(
        err.code(),
        Some(&SqlState::from_code(USER_FACING_DB_ERROR_CODE))
    );

    // Unmark the conversation as spam
    db.unmark_inbox_conversation_as_spam(
        INBOX_ADMIN_ID,
        INBOX_WRITE_GROUP_ID,
        INBOX_SPAM_ROUND_TRIP_CONVERSATION_ID,
    )
    .await?;
    let unmarked = db
        .get_group_inbox_conversation(INBOX_WRITE_GROUP_ID, INBOX_SPAM_ROUND_TRIP_CONVERSATION_ID)
        .await?
        .expect("conversation to exist");

    // Check the status the latest user message implies is restored
    assert_eq!(unmarked.status, InboxConversationStatus::Open);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_start_inbox_conversation_returns_open_conversation_conflict() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Start a second conversation with the read group
    let result = db
        .start_inbox_conversation(
            INBOX_USER_ID,
            INBOX_COMMUNITY_ID,
            INBOX_READ_EVENT_ID,
            "Another question",
        )
        .await?;

    // Check the open conversation conflict is returned
    assert_eq!(
        result,
        StartInboxConversationResult::Conflict(StartInboxConversationConflict::OpenConversation)
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_start_inbox_conversation_serializes_daily_limit() -> Result<()> {
    // Setup two connections and a lock probe
    let pool = contract_tests_pool()?;
    let first_client = pool.get().await?;
    let second_client = pool.get().await?;
    let probe_client = pool.get().await?;
    let first_backend_pid = backend_pid(&first_client).await?;
    let second_backend_pid = backend_pid(&second_client).await?;

    // Start the third conversation of the day and keep its transaction open
    first_client.batch_execute("begin").await?;
    first_client
        .query_one(
            "select start_inbox_conversation($1::uuid, $2::uuid, $3::uuid, 'First')",
            &[
                &INBOX_START_LIMIT_USER_ID,
                &INBOX_COMMUNITY_ID,
                &INBOX_WRITE_EVENT_ID,
            ],
        )
        .await?;

    // Start another conversation with a different group at the same time
    let second_task = tokio::spawn(async move {
        second_client
            .query_one(
                "select start_inbox_conversation($1::uuid, $2::uuid, $3::uuid, 'Second')",
                &[
                    &INBOX_START_LIMIT_USER_ID,
                    &INBOX_COMMUNITY_ID,
                    &INBOX_COHOST_EVENT_ID,
                ],
            )
            .await
    });

    // Commit the first start once the second one waits for the user lock
    wait_for_backend_blocker(&probe_client, first_backend_pid, second_backend_pid).await?;
    first_client.batch_execute("commit").await?;

    // Check the second start observes the committed limit
    let err = second_task
        .await?
        .expect_err("the second start should reach the daily limit");
    assert_eq!(
        err.as_db_error().map(DbError::message),
        Some("daily limit of new conversations reached")
    );
    assert_eq!(
        err.code(),
        Some(&SqlState::from_code(USER_FACING_DB_ERROR_CODE))
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_start_inbox_conversation_serializes_open_conversation() -> Result<()> {
    // Setup two connections and a lock probe
    let pool = contract_tests_pool()?;
    let first_client = pool.get().await?;
    let second_client = pool.get().await?;
    let probe_client = pool.get().await?;
    let first_backend_pid = backend_pid(&first_client).await?;
    let second_backend_pid = backend_pid(&second_client).await?;

    // Start a conversation with the write group and keep its transaction open
    first_client.batch_execute("begin").await?;
    first_client
        .query_one(
            "select start_inbox_conversation($1::uuid, $2::uuid, $3::uuid, 'First')",
            &[
                &INBOX_START_RACE_USER_ID,
                &INBOX_COMMUNITY_ID,
                &INBOX_WRITE_EVENT_ID,
            ],
        )
        .await?;

    // Start another conversation with the same group at the same time
    let second_task = tokio::spawn(async move {
        second_client
            .query_one(
                "select start_inbox_conversation($1::uuid, $2::uuid, $3::uuid, 'Second')::text",
                &[
                    &INBOX_START_RACE_USER_ID,
                    &INBOX_COMMUNITY_ID,
                    &INBOX_WRITE_EVENT_ID,
                ],
            )
            .await
            .map(|row| row.get::<_, String>(0))
    });

    // Commit the first start once the second one waits for the user lock
    wait_for_backend_blocker(&probe_client, first_backend_pid, second_backend_pid).await?;
    first_client.batch_execute("commit").await?;

    // Check the second start points to the committed conversation
    let second: serde_json::Value = serde_json::from_str(&second_task.await??)?;
    assert_eq!(
        second,
        serde_json::json!({ "conflict": "open-conversation" })
    );
    let conversations: i64 = probe_client
        .query_one(
            "select count(*) from inbox_conversation where user_id = $1::uuid",
            &[&INBOX_START_RACE_USER_ID],
        )
        .await?
        .get(0);
    assert_eq!(conversations, 1);

    Ok(())
}

// Helpers.

/// Returns the backend process identifier of a connection.
async fn backend_pid(client: &tokio_postgres::Client) -> Result<i32> {
    Ok(client
        .query_one("select pg_backend_pid()", &[])
        .await?
        .get::<_, i32>(0))
}
