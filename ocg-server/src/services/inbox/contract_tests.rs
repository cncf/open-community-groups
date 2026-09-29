//! Real-database contracts for the inbox manager: transactional compositions
//! that mocks cannot prove, run by `just db-contract-tests`.

use std::sync::Arc;

use anyhow::Result;
use uuid::Uuid;

use crate::{
    db::contract_tests::helpers::{contract_tests_db, contract_tests_pool},
    services::inbox::{InboxManager, PgInboxManager, StartConversationInput},
};

/// Inactive community holding every inbox contract fixture.
const INBOX_COMMUNITY_ID: Uuid = Uuid::from_u128(0xe001);
/// Group team member with the admin role in the write group.
const INBOX_ADMIN_ID: Uuid = Uuid::from_u128(0xe021);
/// Group team member with the events-manager role in the write group.
const INBOX_EVENTS_MANAGER_ID: Uuid = Uuid::from_u128(0xe022);
/// User starting a conversation through the manager.
const INBOX_MANAGER_USER_ID: Uuid = Uuid::from_u128(0xe02a);
/// Published event owned by the write group.
const INBOX_WRITE_EVENT_ID: Uuid = Uuid::from_u128(0xe032);

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_inbox_manager_commits_message_with_notification() -> Result<()> {
    // Setup the manager over the contract database
    let manager = PgInboxManager::new(Arc::new(contract_tests_db()?));

    // Start a conversation through the manager
    let inbox_conversation_id = manager
        .start_conversation(&StartConversationInput {
            body: "Can I bring a friend?".to_string(),
            community_id: INBOX_COMMUNITY_ID,
            event_id: INBOX_WRITE_EVENT_ID,
            user_id: INBOX_MANAGER_USER_ID,
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
    assert_eq!(recipients, vec![INBOX_ADMIN_ID, INBOX_EVENTS_MANAGER_ID]);

    Ok(())
}
