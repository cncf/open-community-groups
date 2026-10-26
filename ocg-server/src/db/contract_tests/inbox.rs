//! Contract tests for the `DBInbox` functions.

use anyhow::Result;
use chrono::{TimeZone, Utc};
use uuid::Uuid;

use crate::{
    db::inbox::{DBInbox, StartInboxConversationConflict, StartInboxConversationResult},
    types::inbox::{InboxConversationStatus, InboxConversationsFilters, InboxMessageKind},
};

use super::helpers::*;

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_add_inbox_user_message_serializes_daily_limit() -> Result<()> {
    // Setup two racing connections and a lock probe
    let RaceClients {
        first: first_client,
        first_backend_pid,
        probe: probe_client,
        second: second_client,
        second_backend_pid,
    } = race_clients().await?;

    // Send the tenth follow-up of the day and keep its transaction open
    first_client.batch_execute("begin").await?;
    first_client
        .query_one(
            "select add_inbox_user_message($1::uuid, $2::uuid, 'Tenth')",
            &[
                &inbox_follow_up_limit_user_id(),
                &inbox_follow_up_conversation_id(),
            ],
        )
        .await?;

    // Send another follow-up at the same time
    let second_task = tokio::spawn(async move {
        second_client
            .query_one(
                "select add_inbox_user_message($1::uuid, $2::uuid, 'Eleventh')",
                &[
                    &inbox_follow_up_limit_user_id(),
                    &inbox_follow_up_conversation_id(),
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
    assert_pg_ocg01(err, "daily message limit reached");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_close_inbox_conversation_serializes_with_reply() -> Result<()> {
    // Setup two racing connections and a lock probe
    let RaceClients {
        first: reply_client,
        first_backend_pid: reply_backend_pid,
        probe: probe_client,
        second: close_client,
        second_backend_pid: close_backend_pid,
    } = race_clients().await?;

    // Start the close transaction before the reply one, so audit times must
    // follow the lock order rather than the transaction start order
    close_client.batch_execute("begin").await?;

    // Reply to the conversation and keep the transaction open
    reply_client.batch_execute("begin").await?;
    reply_client
        .query_one(
            "select add_inbox_group_reply($1::uuid, $2::uuid, $3::uuid, 'Yes, it will be recorded.')",
            &[
                &inbox_admin_id(),
                &inbox_write_group_id(),
                &inbox_race_conversation_id(),
            ],
        )
        .await?;

    // Close the conversation at the same time
    let close_task = tokio::spawn(async move {
        close_client
            .execute(
                "select close_inbox_conversation($1::uuid, $2::uuid, $3::uuid)",
                &[
                    &inbox_events_manager_id(),
                    &inbox_write_group_id(),
                    &inbox_race_conversation_id(),
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
            &[&inbox_race_conversation_id()],
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
    let count = db.count_group_open_inbox_conversations(inbox_read_group_id()).await?;

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
        .get_group_inbox_conversation(inbox_read_group_id(), inbox_open_conversation_id())
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
        inbox_open_conversation_id()
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
    assert_eq!(user.user_id, inbox_user_id());
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
        .get_group_inbox_conversation(inbox_read_group_id(), inbox_deleted_user_conversation_id())
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
        .get_inbox_contact_context(inbox_community_id(), inbox_read_event_id(), None)
        .await?
        .expect("contact context to exist");
    let team_member = db
        .get_inbox_contact_context(
            inbox_community_id(),
            inbox_read_event_id(),
            Some(inbox_admin_id()),
        )
        .await?
        .expect("contact context to exist");
    let read_only_member = db
        .get_inbox_contact_context(
            inbox_community_id(),
            inbox_read_event_id(),
            Some(inbox_viewer_id()),
        )
        .await?
        .expect("contact context to exist");
    let user = db
        .get_inbox_contact_context(
            inbox_community_id(),
            inbox_read_event_id(),
            Some(inbox_user_id()),
        )
        .await?
        .expect("contact context to exist");
    let spam_user = db
        .get_inbox_contact_context(
            inbox_community_id(),
            inbox_read_event_id(),
            Some(inbox_spam_user_id()),
        )
        .await?
        .expect("contact context to exist");

    // Check the anonymous context
    assert_eq!(anonymous.community_name, "contract-inbox-community");
    assert_eq!(anonymous.event_id, inbox_read_event_id());
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
        Some(inbox_open_conversation_id())
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
        .get_user_inbox_conversation(inbox_user_id(), inbox_open_conversation_id())
        .await?;
    let foreign = db
        .get_user_inbox_conversation(inbox_race_user_id(), inbox_open_conversation_id())
        .await?;

    // Check only the owner can read the thread
    assert_eq!(
        owned.map(|conversation| conversation.inbox_conversation_id),
        Some(inbox_open_conversation_id())
    );
    assert!(foreign.is_none());

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
    let output = db.list_group_inbox_conversations(inbox_read_group_id(), &all).await?;
    let closed_output = db
        .list_group_inbox_conversations(inbox_read_group_id(), &closed)
        .await?;
    let spam_output = db
        .list_group_inbox_conversations(inbox_read_group_id(), &spam)
        .await?;

    // Check ordering and totals, leaving spam out unless filtered by it
    let ids: Vec<_> = output
        .conversations
        .iter()
        .map(|conversation| conversation.inbox_conversation_id)
        .collect();
    assert_eq!(
        ids,
        vec![
            inbox_open_conversation_id(),
            inbox_deleted_user_conversation_id(),
            inbox_closed_conversation_id()
        ]
    );
    assert_eq!(output.total, 3);
    assert_eq!(closed_output.total, 1);
    assert_eq!(
        closed_output.conversations[0].inbox_conversation_id,
        inbox_closed_conversation_id()
    );
    assert_eq!(spam_output.total, 1);
    assert_eq!(
        spam_output.conversations[0].inbox_conversation_id,
        inbox_spam_conversation_id()
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
        Some(inbox_user_id())
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
    let recipients = db.list_inbox_recipient_ids(inbox_read_group_id()).await?;

    // Check the viewer is excluded
    assert_eq!(
        recipients,
        vec![inbox_admin_id(), inbox_events_manager_id()]
    );

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
    let output = db.list_user_inbox_conversations(inbox_user_id(), &filters).await?;

    // Check ordering and totals
    let ids: Vec<_> = output
        .conversations
        .iter()
        .map(|conversation| conversation.inbox_conversation_id)
        .collect();
    assert_eq!(
        ids,
        vec![inbox_open_conversation_id(), inbox_closed_conversation_id()]
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
        inbox_admin_id(),
        inbox_write_group_id(),
        inbox_spam_round_trip_conversation_id(),
    )
    .await?;
    let marked = db
        .get_user_inbox_conversation(
            inbox_spam_user_id(),
            inbox_spam_round_trip_conversation_id(),
        )
        .await?
        .expect("conversation to exist");

    // Check the user sees the spam status and can no longer write
    assert_eq!(marked.status, InboxConversationStatus::Spam);
    let err = client
        .query_one(
            "select add_inbox_user_message($1::uuid, $2::uuid, 'Hello?')",
            &[
                &inbox_spam_user_id(),
                &inbox_spam_round_trip_conversation_id(),
            ],
        )
        .await
        .expect_err("conversations marked as spam should reject messages");
    assert_pg_ocg01(err, "conversation no longer accepts messages");

    // Unmark the conversation as spam
    db.unmark_inbox_conversation_as_spam(
        inbox_admin_id(),
        inbox_write_group_id(),
        inbox_spam_round_trip_conversation_id(),
    )
    .await?;
    let unmarked = db
        .get_group_inbox_conversation(
            inbox_write_group_id(),
            inbox_spam_round_trip_conversation_id(),
        )
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
            inbox_user_id(),
            inbox_community_id(),
            inbox_read_event_id(),
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
    // Setup two racing connections and a lock probe
    let RaceClients {
        first: first_client,
        first_backend_pid,
        probe: probe_client,
        second: second_client,
        second_backend_pid,
    } = race_clients().await?;

    // Start the third conversation of the day and keep its transaction open
    first_client.batch_execute("begin").await?;
    first_client
        .query_one(
            "select start_inbox_conversation($1::uuid, $2::uuid, $3::uuid, 'First')",
            &[
                &inbox_start_limit_user_id(),
                &inbox_community_id(),
                &inbox_write_event_id(),
            ],
        )
        .await?;

    // Start another conversation with a different group at the same time
    let second_task = tokio::spawn(async move {
        second_client
            .query_one(
                "select start_inbox_conversation($1::uuid, $2::uuid, $3::uuid, 'Second')",
                &[
                    &inbox_start_limit_user_id(),
                    &inbox_community_id(),
                    &inbox_cohost_event_id(),
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
    assert_pg_ocg01(err, "daily limit of new conversations reached");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_start_inbox_conversation_serializes_open_conversation() -> Result<()> {
    // Setup two racing connections and a lock probe
    let RaceClients {
        first: first_client,
        first_backend_pid,
        probe: probe_client,
        second: second_client,
        second_backend_pid,
    } = race_clients().await?;

    // Start a conversation with the write group and keep its transaction open
    first_client.batch_execute("begin").await?;
    first_client
        .query_one(
            "select start_inbox_conversation($1::uuid, $2::uuid, $3::uuid, 'First')",
            &[
                &inbox_start_race_user_id(),
                &inbox_community_id(),
                &inbox_write_event_id(),
            ],
        )
        .await?;

    // Start another conversation with the same group at the same time
    let second_task = tokio::spawn(async move {
        second_client
            .query_one(
                "select start_inbox_conversation($1::uuid, $2::uuid, $3::uuid, 'Second')::text",
                &[
                    &inbox_start_race_user_id(),
                    &inbox_community_id(),
                    &inbox_write_event_id(),
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
            &[&inbox_start_race_user_id()],
        )
        .await?
        .get(0);
    assert_eq!(conversations, 1);

    Ok(())
}

// Helpers.

/// Two connections racing for an inbox lock, a probe connection observing
/// the lock graph, and the backend process IDs of the racing connections.
struct RaceClients {
    first: deadpool_postgres::Object,
    first_backend_pid: i32,
    probe: deadpool_postgres::Object,
    second: deadpool_postgres::Object,
    second_backend_pid: i32,
}

/// Opens the connections of an inbox lock race.
async fn race_clients() -> Result<RaceClients> {
    let pool = contract_tests_pool()?;
    let first = pool.get().await?;
    let second = pool.get().await?;
    let probe = pool.get().await?;
    let first_backend_pid = backend_pid(&first).await?;
    let second_backend_pid = backend_pid(&second).await?;

    Ok(RaceClients {
        first,
        first_backend_pid,
        probe,
        second,
        second_backend_pid,
    })
}
