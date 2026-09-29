//! Database operations for the group inbox.

use anyhow::Result;
use async_trait::async_trait;
use serde::Deserialize;
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::PgExecutor,
    types::inbox::{
        InboxContactContext, InboxConversation, InboxConversationsFilters, InboxConversationsOutput,
    },
};

/// Database operations for inbox conversations between users and groups.
#[async_trait]
pub(crate) trait DBInbox {
    /// Adds a reply on behalf of the group to one of its conversations.
    async fn add_inbox_group_reply(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        inbox_conversation_id: Uuid,
        body: &str,
    ) -> Result<PostedInboxMessage>;

    /// Adds a follow-up message from the user to one of their conversations.
    async fn add_inbox_user_message(
        &self,
        actor_user_id: Uuid,
        inbox_conversation_id: Uuid,
        body: &str,
    ) -> Result<PostedInboxMessage>;

    /// Closes a conversation of the group.
    async fn close_inbox_conversation(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        inbox_conversation_id: Uuid,
    ) -> Result<()>;

    /// Counts the open conversations of the group.
    async fn count_group_open_inbox_conversations(&self, group_id: Uuid) -> Result<usize>;

    /// Returns a conversation thread of the group.
    async fn get_group_inbox_conversation(
        &self,
        group_id: Uuid,
        inbox_conversation_id: Uuid,
    ) -> Result<Option<InboxConversation>>;

    /// Returns the event page contact modal context, when the event accepts contact.
    async fn get_inbox_contact_context(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Option<Uuid>,
    ) -> Result<Option<InboxContactContext>>;

    /// Returns a conversation thread of the user.
    async fn get_user_inbox_conversation(
        &self,
        user_id: Uuid,
        inbox_conversation_id: Uuid,
    ) -> Result<Option<InboxConversation>>;

    /// Lists the conversations of the group.
    async fn list_group_inbox_conversations(
        &self,
        group_id: Uuid,
        filters: &InboxConversationsFilters,
    ) -> Result<InboxConversationsOutput>;

    /// Lists the group team members emailed when a user writes to the group.
    async fn list_inbox_recipient_ids(&self, group_id: Uuid) -> Result<Vec<Uuid>>;

    /// Lists the conversations of the user.
    async fn list_user_inbox_conversations(
        &self,
        user_id: Uuid,
        filters: &InboxConversationsFilters,
    ) -> Result<InboxConversationsOutput>;

    /// Marks a conversation of the group as spam.
    async fn mark_inbox_conversation_as_spam(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        inbox_conversation_id: Uuid,
    ) -> Result<()>;

    /// Starts a conversation with the group that owns the event.
    async fn start_inbox_conversation(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        event_id: Uuid,
        body: &str,
    ) -> Result<StartInboxConversationResult>;

    /// Unmarks a conversation of the group as spam.
    async fn unmark_inbox_conversation_as_spam(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        inbox_conversation_id: Uuid,
    ) -> Result<()>;
}

#[async_trait]
impl<T> DBInbox for T
where
    T: PgExecutor + Send + Sync,
{
    /// [`DBInbox::add_inbox_group_reply`].
    #[instrument(skip(self, body), err)]
    async fn add_inbox_group_reply(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        inbox_conversation_id: Uuid,
        body: &str,
    ) -> Result<PostedInboxMessage> {
        self.fetch_json_one(
            "select add_inbox_group_reply($1::uuid, $2::uuid, $3::uuid, $4::text)",
            &[&actor_user_id, &group_id, &inbox_conversation_id, &body],
        )
        .await
    }

    /// [`DBInbox::add_inbox_user_message`].
    #[instrument(skip(self, body), err)]
    async fn add_inbox_user_message(
        &self,
        actor_user_id: Uuid,
        inbox_conversation_id: Uuid,
        body: &str,
    ) -> Result<PostedInboxMessage> {
        self.fetch_json_one(
            "select add_inbox_user_message($1::uuid, $2::uuid, $3::text)",
            &[&actor_user_id, &inbox_conversation_id, &body],
        )
        .await
    }

    /// [`DBInbox::close_inbox_conversation`].
    #[instrument(skip(self), err)]
    async fn close_inbox_conversation(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        inbox_conversation_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select close_inbox_conversation($1::uuid, $2::uuid, $3::uuid)",
            &[&actor_user_id, &group_id, &inbox_conversation_id],
        )
        .await
    }

    /// [`DBInbox::count_group_open_inbox_conversations`].
    #[instrument(skip(self), err)]
    async fn count_group_open_inbox_conversations(&self, group_id: Uuid) -> Result<usize> {
        let count: i32 = self
            .fetch_scalar_one(
                "select count_group_open_inbox_conversations($1::uuid)",
                &[&group_id],
            )
            .await?;

        Ok(usize::try_from(count)?)
    }

    /// [`DBInbox::get_group_inbox_conversation`].
    #[instrument(skip(self), err)]
    async fn get_group_inbox_conversation(
        &self,
        group_id: Uuid,
        inbox_conversation_id: Uuid,
    ) -> Result<Option<InboxConversation>> {
        self.fetch_json_opt(
            "select get_group_inbox_conversation($1::uuid, $2::uuid)",
            &[&group_id, &inbox_conversation_id],
        )
        .await
    }

    /// [`DBInbox::get_inbox_contact_context`].
    #[instrument(skip(self), err)]
    async fn get_inbox_contact_context(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Option<Uuid>,
    ) -> Result<Option<InboxContactContext>> {
        self.fetch_json_opt(
            "select get_inbox_contact_context($1::uuid, $2::uuid, $3::uuid)",
            &[&community_id, &event_id, &user_id],
        )
        .await
    }

    /// [`DBInbox::get_user_inbox_conversation`].
    #[instrument(skip(self), err)]
    async fn get_user_inbox_conversation(
        &self,
        user_id: Uuid,
        inbox_conversation_id: Uuid,
    ) -> Result<Option<InboxConversation>> {
        self.fetch_json_opt(
            "select get_user_inbox_conversation($1::uuid, $2::uuid)",
            &[&user_id, &inbox_conversation_id],
        )
        .await
    }

    /// [`DBInbox::list_group_inbox_conversations`].
    #[instrument(skip(self, filters), err)]
    async fn list_group_inbox_conversations(
        &self,
        group_id: Uuid,
        filters: &InboxConversationsFilters,
    ) -> Result<InboxConversationsOutput> {
        self.fetch_json_one(
            "select list_group_inbox_conversations($1::uuid, $2::jsonb)",
            &[&group_id, &Json(filters)],
        )
        .await
    }

    /// [`DBInbox::list_inbox_recipient_ids`].
    #[instrument(skip(self), err)]
    async fn list_inbox_recipient_ids(&self, group_id: Uuid) -> Result<Vec<Uuid>> {
        self.fetch_scalar_one("select list_inbox_recipient_ids($1::uuid)", &[&group_id])
            .await
    }

    /// [`DBInbox::list_user_inbox_conversations`].
    #[instrument(skip(self, filters), err)]
    async fn list_user_inbox_conversations(
        &self,
        user_id: Uuid,
        filters: &InboxConversationsFilters,
    ) -> Result<InboxConversationsOutput> {
        self.fetch_json_one(
            "select list_user_inbox_conversations($1::uuid, $2::jsonb)",
            &[&user_id, &Json(filters)],
        )
        .await
    }

    /// [`DBInbox::mark_inbox_conversation_as_spam`].
    #[instrument(skip(self), err)]
    async fn mark_inbox_conversation_as_spam(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        inbox_conversation_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select mark_inbox_conversation_as_spam($1::uuid, $2::uuid, $3::uuid)",
            &[&actor_user_id, &group_id, &inbox_conversation_id],
        )
        .await
    }

    /// [`DBInbox::start_inbox_conversation`].
    #[instrument(skip(self, body), err)]
    async fn start_inbox_conversation(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        event_id: Uuid,
        body: &str,
    ) -> Result<StartInboxConversationResult> {
        let output: StartInboxConversationOutput = self
            .fetch_json_one(
                "select start_inbox_conversation($1::uuid, $2::uuid, $3::uuid, $4::text)",
                &[&actor_user_id, &community_id, &event_id, &body],
            )
            .await?;

        Ok(output.into())
    }

    /// [`DBInbox::unmark_inbox_conversation_as_spam`].
    #[instrument(skip(self), err)]
    async fn unmark_inbox_conversation_as_spam(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        inbox_conversation_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select unmark_inbox_conversation_as_spam($1::uuid, $2::uuid, $3::uuid)",
            &[&actor_user_id, &group_id, &inbox_conversation_id],
        )
        .await
    }
}

/// Identifiers of a message stored in an inbox conversation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
pub(crate) struct PostedInboxMessage {
    /// Group receiving the conversation.
    pub group_id: Uuid,
    /// Conversation the message was added to.
    pub inbox_conversation_id: Uuid,
    /// Stored message.
    pub inbox_message_id: Uuid,
}

/// Reason a conversation could not be started.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum StartInboxConversationConflict {
    /// The user already has an open conversation with the group.
    OpenConversation,
}

/// Result of starting an inbox conversation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum StartInboxConversationResult {
    /// Nothing was written because of a conflict.
    Conflict(StartInboxConversationConflict),
    /// The conversation and its first message were stored.
    Started(PostedInboxMessage),
}

/// Database output returned after starting an inbox conversation.
#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum StartInboxConversationOutput {
    /// Nothing was written because of a conflict.
    Conflict {
        /// Conflict kind.
        conflict: StartInboxConversationConflict,
    },
    /// The conversation and its first message were stored.
    Started(PostedInboxMessage),
}

impl From<StartInboxConversationOutput> for StartInboxConversationResult {
    /// Converts database output into the caller-facing result.
    fn from(output: StartInboxConversationOutput) -> Self {
        match output {
            StartInboxConversationOutput::Conflict { conflict } => Self::Conflict(conflict),
            StartInboxConversationOutput::Started(posted) => Self::Started(posted),
        }
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;
    use uuid::Uuid;

    use super::{
        PostedInboxMessage, StartInboxConversationConflict, StartInboxConversationOutput,
        StartInboxConversationResult,
    };

    #[test]
    fn test_start_inbox_conversation_output_maps_conflicts() {
        let output: StartInboxConversationOutput =
            serde_json::from_value(json!({ "conflict": "open-conversation" })).unwrap();

        assert_eq!(
            StartInboxConversationResult::from(output),
            StartInboxConversationResult::Conflict(
                StartInboxConversationConflict::OpenConversation
            )
        );
    }

    #[test]
    fn test_start_inbox_conversation_output_maps_started_conversations() {
        let posted = PostedInboxMessage {
            group_id: Uuid::new_v4(),
            inbox_conversation_id: Uuid::new_v4(),
            inbox_message_id: Uuid::new_v4(),
        };
        let output: StartInboxConversationOutput = serde_json::from_value(json!({
            "group_id": posted.group_id,
            "inbox_conversation_id": posted.inbox_conversation_id,
            "inbox_message_id": posted.inbox_message_id,
        }))
        .unwrap();

        assert_eq!(
            StartInboxConversationResult::from(output),
            StartInboxConversationResult::Started(posted)
        );
    }
}
