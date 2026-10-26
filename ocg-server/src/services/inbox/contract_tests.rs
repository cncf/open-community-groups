//! Real-database contracts for the inbox manager: transactional compositions
//! that mocks cannot prove, run by `just db-contract-tests`.

use std::sync::Arc;

use anyhow::Result;
use uuid::Uuid;

use crate::{
    db::contract_tests::helpers::{
        contract_tests_db, contract_tests_pool, inbox_admin_id, inbox_community_id,
        inbox_events_manager_id, inbox_manager_user_id, inbox_opt_out_admin_id,
        inbox_opt_out_event_id, inbox_opt_out_events_manager_id, inbox_opt_out_group_id,
        inbox_opt_out_user_id, inbox_write_event_id,
    },
    services::inbox::{InboxManager, PgInboxManager, StartConversationInput},
};

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_inbox_manager_commits_message_with_notification() -> Result<()> {
    // Setup the manager over the contract database
    let manager = PgInboxManager::new(Arc::new(contract_tests_db()?));

    // Start a conversation through the manager
    let inbox_conversation_id = manager
        .start_conversation(&StartConversationInput {
            body: "Can I bring a friend?".to_string(),
            community_id: inbox_community_id(),
            event_id: inbox_write_event_id(),
            user_id: inbox_manager_user_id(),
        })
        .await?;

    // Load the committed message and notification rows
    let client = contract_tests_pool()?.get().await?;
    let body: String = client
        .query_one(
            "select body from inbox_message where inbox_conversation_id = $1::uuid",
            &[&inbox_conversation_id],
        )
        .await?
        .get(0);
    let recipients: Vec<Uuid> = client
        .query(
            "select n.user_id
            from notification n
            join notification_template_data d using (notification_template_data_id)
            where n.kind = 'inbox-message-received'
            and d.data->>'sender_name' = 'Inbox Manager'
            order by n.user_id",
            &[],
        )
        .await?
        .iter()
        .map(|row| row.get(0))
        .collect();

    // Check the message and its emails were committed together
    assert_eq!(body, "Can I bring a friend?");
    assert_eq!(
        recipients,
        vec![inbox_admin_id(), inbox_events_manager_id()]
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_inbox_manager_commits_conversation_when_recipients_opt_out() -> Result<()> {
    // Setup the manager over the contract database and a clean opted-out flow
    let client = contract_tests_pool()?.get().await?;
    cleanup_opted_out_inbox_flow(&client).await?;
    let manager = PgInboxManager::new(Arc::new(contract_tests_db()?));

    // Start a conversation whose group team recipients all opted out of its emails
    let inbox_conversation_id = manager
        .start_conversation(&StartConversationInput {
            body: "Will the recording be posted?".to_string(),
            community_id: inbox_community_id(),
            event_id: inbox_opt_out_event_id(),
            user_id: inbox_opt_out_user_id(),
        })
        .await?;

    // Load the stored message and any notifications for the opted-out recipients
    let body: String = client
        .query_one(
            "select body
            from inbox_message
            where inbox_conversation_id = $1::uuid",
            &[&inbox_conversation_id],
        )
        .await?
        .get(0);
    let notification_count: i64 = client
        .query_one(
            "select count(*)
            from notification
            where kind = 'inbox-message-received'
            and user_id = any($1::uuid[])",
            &[&vec![
                inbox_opt_out_admin_id(),
                inbox_opt_out_events_manager_id(),
            ]],
        )
        .await?
        .get(0);

    // Clean up the durable rows before any check can fail
    cleanup_opted_out_inbox_flow(&client).await?;

    // Check preference filtering did not roll back the inbox write
    assert_eq!(body, "Will the recording be posted?");
    assert_eq!(notification_count, 0);

    Ok(())
}

// Helpers.

/// Removes rows written by the opted-out inbox conversation contract.
async fn cleanup_opted_out_inbox_flow(client: &tokio_postgres::Client) -> Result<()> {
    // Remove any emails written by a failed prior focused run
    client
        .execute(
            "delete from notification
            where kind = 'inbox-message-received'
            and user_id = any($1::uuid[])",
            &[&vec![
                inbox_opt_out_admin_id(),
                inbox_opt_out_events_manager_id(),
            ]],
        )
        .await?;

    // Remove messages before their conversations are deleted
    client
        .execute(
            "delete from inbox_message
            where inbox_conversation_id in (
                select inbox_conversation_id
                from inbox_conversation
                where group_id = $1::uuid
                and user_id = $2::uuid
            )",
            &[&inbox_opt_out_group_id(), &inbox_opt_out_user_id()],
        )
        .await?;

    // Remove the conversation started by the contract
    client
        .execute(
            "delete from inbox_conversation
            where group_id = $1::uuid
            and user_id = $2::uuid",
            &[&inbox_opt_out_group_id(), &inbox_opt_out_user_id()],
        )
        .await?;

    Ok(())
}
