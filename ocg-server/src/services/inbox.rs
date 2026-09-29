//! Group inbox workflows.
//!
//! The inbox manager owns every inbox write: starting a conversation from an
//! event page, user follow-ups, group replies, closing conversations, and
//! marking or unmarking them as spam. Writes that queue an email run in one
//! transaction together with it; writes without an email are a single atomic
//! database call.

use std::sync::Arc;

use async_trait::async_trait;
#[cfg(test)]
use mockall::automock;
use uuid::Uuid;

use crate::{
    db::{
        DBExt, DynDB,
        inbox::{StartInboxConversationConflict, StartInboxConversationResult},
    },
    services::notifications::enqueue::{
        enqueue_inbox_message_received_notification, enqueue_inbox_reply_received_notification,
    },
};

#[cfg(test)]
mod contract_tests;
#[cfg(test)]
mod tests;

/// Rejection returned when the user already has an open conversation with the group.
const OPEN_CONVERSATION_REJECTION: &str =
    "you already have an open conversation with this group; continue it from your Inbox";

/// Inbox write workflows used by handlers.
#[async_trait]
#[cfg_attr(test, automock)]
pub(crate) trait InboxManager {
    /// Adds a reply on behalf of the group and queues the email to the user.
    ///
    /// Returns the conversation identifier.
    async fn add_group_reply(&self, input: &GroupReplyInput) -> Result<Uuid, InboxError>;

    /// Adds a user follow-up and queues the email to the group team.
    ///
    /// Returns the conversation identifier.
    async fn add_user_message(&self, input: &UserMessageInput) -> Result<Uuid, InboxError>;

    /// Closes a conversation of the group.
    async fn close_conversation(&self, input: &GroupConversationInput) -> Result<(), InboxError>;

    /// Marks a conversation of the group as spam, which stops the user from
    /// writing to it and from contacting the group again.
    async fn mark_conversation_as_spam(
        &self,
        input: &GroupConversationInput,
    ) -> Result<(), InboxError>;

    /// Starts a conversation with the group that owns an event and queues the
    /// email to its team.
    ///
    /// Returns the conversation identifier.
    async fn start_conversation(&self, input: &StartConversationInput) -> Result<Uuid, InboxError>;

    /// Unmarks a conversation of the group as spam.
    async fn unmark_conversation_as_spam(
        &self,
        input: &GroupConversationInput,
    ) -> Result<(), InboxError>;
}

/// Shared inbox manager trait object.
pub(crate) type DynInboxManager = Arc<dyn InboxManager + Send + Sync>;

/// PostgreSQL-backed inbox manager implementation.
pub(crate) struct PgInboxManager {
    /// Database handle for inbox persistence.
    db: DynDB,
}

impl PgInboxManager {
    /// Creates a new `PgInboxManager`.
    pub(crate) fn new(db: DynDB) -> Self {
        Self { db }
    }
}

#[async_trait]
impl InboxManager for PgInboxManager {
    /// [`InboxManager::add_group_reply`].
    async fn add_group_reply(&self, input: &GroupReplyInput) -> Result<Uuid, InboxError> {
        let GroupReplyInput {
            actor_user_id,
            body,
            group_id,
            inbox_conversation_id,
        } = input.clone();

        // Store the reply and queue the email to the user atomically
        let posted = self
            .db
            .as_ref()
            .transaction(|tx| {
                Box::pin(async move {
                    let posted = tx
                        .add_inbox_group_reply(
                            actor_user_id,
                            group_id,
                            inbox_conversation_id,
                            &body,
                        )
                        .await?;
                    enqueue_inbox_reply_received_notification(tx, &posted).await?;
                    Ok(posted)
                })
            })
            .await?;

        Ok(posted.inbox_conversation_id)
    }

    /// [`InboxManager::add_user_message`].
    async fn add_user_message(&self, input: &UserMessageInput) -> Result<Uuid, InboxError> {
        let UserMessageInput {
            body,
            inbox_conversation_id,
            user_id,
        } = input.clone();

        // Store the follow-up and queue the email to the group team atomically
        let posted = self
            .db
            .as_ref()
            .transaction(|tx| {
                Box::pin(async move {
                    let posted = tx
                        .add_inbox_user_message(user_id, inbox_conversation_id, &body)
                        .await?;
                    enqueue_inbox_message_received_notification(tx, &posted).await?;
                    Ok(posted)
                })
            })
            .await?;

        Ok(posted.inbox_conversation_id)
    }

    /// [`InboxManager::close_conversation`].
    async fn close_conversation(&self, input: &GroupConversationInput) -> Result<(), InboxError> {
        let GroupConversationInput {
            actor_user_id,
            group_id,
            inbox_conversation_id,
        } = *input;

        // Close the conversation; closing sends no email
        self.db
            .close_inbox_conversation(actor_user_id, group_id, inbox_conversation_id)
            .await?;

        Ok(())
    }

    /// [`InboxManager::mark_conversation_as_spam`].
    async fn mark_conversation_as_spam(
        &self,
        input: &GroupConversationInput,
    ) -> Result<(), InboxError> {
        let GroupConversationInput {
            actor_user_id,
            group_id,
            inbox_conversation_id,
        } = *input;

        // Mark the conversation as spam; marking sends no email
        self.db
            .mark_inbox_conversation_as_spam(actor_user_id, group_id, inbox_conversation_id)
            .await?;

        Ok(())
    }

    /// [`InboxManager::start_conversation`].
    async fn start_conversation(&self, input: &StartConversationInput) -> Result<Uuid, InboxError> {
        let StartConversationInput {
            body,
            community_id,
            event_id,
            user_id,
        } = input.clone();

        // Start the conversation and queue the email to the group team atomically
        let result = self
            .db
            .as_ref()
            .transaction(|tx| {
                Box::pin(async move {
                    let result = tx
                        .start_inbox_conversation(user_id, community_id, event_id, &body)
                        .await?;
                    if let StartInboxConversationResult::Started(posted) = &result {
                        enqueue_inbox_message_received_notification(tx, posted).await?;
                    }
                    Ok(result)
                })
            })
            .await?;

        // Point the user to the open conversation they already have
        match result {
            StartInboxConversationResult::Conflict(
                StartInboxConversationConflict::OpenConversation,
            ) => Err(InboxError::Rejected(
                OPEN_CONVERSATION_REJECTION.to_string(),
            )),
            StartInboxConversationResult::Started(posted) => Ok(posted.inbox_conversation_id),
        }
    }

    /// [`InboxManager::unmark_conversation_as_spam`].
    async fn unmark_conversation_as_spam(
        &self,
        input: &GroupConversationInput,
    ) -> Result<(), InboxError> {
        let GroupConversationInput {
            actor_user_id,
            group_id,
            inbox_conversation_id,
        } = *input;

        // Unmark the conversation as spam; unmarking sends no email
        self.db
            .unmark_inbox_conversation_as_spam(actor_user_id, group_id, inbox_conversation_id)
            .await?;

        Ok(())
    }
}

/// Parameters used to act on a conversation on behalf of the group: closing
/// it, or marking or unmarking it as spam.
#[derive(Clone, Copy, Debug)]
pub(crate) struct GroupConversationInput {
    /// User acting on the conversation.
    pub actor_user_id: Uuid,
    /// Selected group owning the conversation.
    pub group_id: Uuid,
    /// Conversation to act on.
    pub inbox_conversation_id: Uuid,
}

/// Parameters used to reply to a conversation on behalf of the group.
#[derive(Clone, Debug)]
pub(crate) struct GroupReplyInput {
    /// User writing the reply.
    pub actor_user_id: Uuid,
    /// Reply text.
    pub body: String,
    /// Selected group owning the conversation.
    pub group_id: Uuid,
    /// Conversation to reply to.
    pub inbox_conversation_id: Uuid,
}

/// Errors returned by inbox workflows.
#[derive(Debug, thiserror::Error)]
pub(crate) enum InboxError {
    /// Internal failure or database rejection, classified by the handler.
    #[error(transparent)]
    Other(#[from] anyhow::Error),
    /// User-facing business rejection decided by the manager.
    #[error("{0}")]
    Rejected(String),
}

/// Parameters used by a user to start a conversation from an event page.
#[derive(Clone, Debug)]
pub(crate) struct StartConversationInput {
    /// First message text.
    pub body: String,
    /// Community of the event page.
    pub community_id: Uuid,
    /// Event the conversation starts from.
    pub event_id: Uuid,
    /// User starting the conversation.
    pub user_id: Uuid,
}

/// Parameters used by a user to follow up on one of their conversations.
#[derive(Clone, Debug)]
pub(crate) struct UserMessageInput {
    /// Follow-up text.
    pub body: String,
    /// Conversation to write to.
    pub inbox_conversation_id: Uuid,
    /// User writing the follow-up.
    pub user_id: Uuid,
}
