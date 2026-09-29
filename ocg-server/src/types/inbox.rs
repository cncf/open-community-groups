//! Inbox types shared by the public site and the group and user dashboards.

use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    types::{
        dashboard,
        pagination::{Pagination, ToRawQuery},
        user::User,
    },
    validation::{MAX_LEN_INBOX_MESSAGE, MAX_PAGINATION_LIMIT, trimmed_non_empty},
};

#[cfg(test)]
mod tests;

/// Inbox conversation thread between a user and a group.
#[derive(Debug, Clone, Deserialize)]
pub(crate) struct InboxConversation {
    /// Display name of the group's community.
    pub community_display_name: String,
    /// Name of the group's community (slug for URLs).
    pub community_name: String,
    /// When the conversation was started.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Group name.
    pub group_name: String,
    /// Generated URL-friendly identifier for the group.
    pub group_slug: String,
    /// Conversation identifier.
    pub inbox_conversation_id: Uuid,
    /// When the latest message was written.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub last_message_at: DateTime<Utc>,
    /// Messages in chronological order.
    pub messages: Vec<InboxMessage>,
    /// Current conversation status.
    pub status: InboxConversationStatus,

    /// Event the conversation started from, while the event still exists.
    pub event: Option<InboxEvent>,
    /// Admin-managed URL-friendly identifier for the group.
    pub group_slug_pretty: Option<String>,
    /// User who started the conversation, absent once their account is deleted.
    pub user: Option<User>,
}

impl InboxConversation {
    /// Returns the public event URL while the event page is publicly available.
    pub(crate) fn event_url(&self) -> Option<String> {
        let event = self.event.as_ref()?;
        let slug = event.slug.as_deref()?;
        event.is_public.then(|| {
            format!(
                "/{}/group/{}/event/{slug}",
                self.community_name,
                self.group_public_slug()
            )
        })
    }

    /// Returns the group slug to use in public URLs.
    pub(crate) fn group_public_slug(&self) -> &str {
        self.group_slug_pretty.as_deref().unwrap_or(&self.group_slug)
    }

    /// Returns true when nobody can reply because the user account was deleted.
    pub(crate) fn is_read_only(&self) -> bool {
        self.user.is_none()
    }
}

/// Context shown by the event page contact modal.
#[derive(Debug, Clone, Deserialize)]
pub(crate) struct InboxContactContext {
    /// Name of the event's community (slug for URLs).
    pub community_name: String,
    /// Event identifier.
    pub event_id: Uuid,
    /// Event name.
    pub event_name: String,
    /// URL-friendly identifier for the event.
    pub event_slug: String,
    /// Name of the group that owns the event.
    pub group_name: String,
    /// Generated URL-friendly identifier for the group.
    pub group_slug: String,

    /// Admin-managed URL-friendly identifier for the group.
    pub group_slug_pretty: Option<String>,
    /// Signed-in viewer state, absent for anonymous visitors.
    pub viewer: Option<InboxContactViewer>,
}

impl InboxContactContext {
    /// Returns the public event page path.
    pub(crate) fn event_path(&self) -> String {
        format!(
            "/{}/group/{}/event/{}",
            self.community_name,
            self.group_slug_pretty.as_deref().unwrap_or(&self.group_slug),
            self.event_slug
        )
    }
}

/// Signed-in viewer state for the event page contact modal.
#[derive(Debug, Clone, Deserialize)]
pub(crate) struct InboxContactViewer {
    /// Whether the viewer is below the daily limit of new conversations.
    pub can_start_conversation: bool,
    /// Whether spam reports block the viewer from contacting the group.
    pub is_blocked: bool,
    /// Whether the viewer organizes the group that owns the event.
    pub is_group_team_member: bool,

    /// The viewer's most recently active open conversation with the group.
    pub open_inbox_conversation_id: Option<Uuid>,
}

/// Status of an inbox conversation.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, strum::Display, strum::EnumString,
)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum InboxConversationStatus {
    /// The group replied to the latest user message.
    Answered,
    /// The group closed the conversation.
    Closed,
    /// The latest message comes from the user.
    Open,
    /// The group marked the conversation as spam.
    Spam,
}

impl InboxConversationStatus {
    /// Returns the user-facing label for the status.
    pub(crate) fn label(self) -> &'static str {
        match self {
            InboxConversationStatus::Answered => "Answered",
            InboxConversationStatus::Closed => "Closed",
            InboxConversationStatus::Open => "Open",
            InboxConversationStatus::Spam => "Spam",
        }
    }
}

/// Inbox conversation projection used by conversation lists.
#[derive(Debug, Clone, Deserialize)]
pub(crate) struct InboxConversationSummary {
    /// Display name of the group's community.
    pub community_display_name: String,
    /// Group name.
    pub group_name: String,
    /// Conversation identifier.
    pub inbox_conversation_id: Uuid,
    /// When the latest message was written.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub last_message_at: DateTime<Utc>,
    /// Beginning of the latest message.
    pub last_message_excerpt: String,
    /// Kind of the latest message.
    pub last_message_kind: InboxMessageKind,
    /// Current conversation status.
    pub status: InboxConversationStatus,

    /// Event the conversation started from, while the event still exists.
    pub event: Option<InboxEvent>,
    /// User who started the conversation, absent once their account is deleted.
    pub user: Option<User>,
}

/// Filter parameters for inbox conversation lists.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct InboxConversationsFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(min = 1, max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,

    /// Status the conversations must have; every status when absent.
    #[garde(skip)]
    pub status: Option<InboxConversationStatus>,
}

crate::impl_pagination_and_raw_query!(InboxConversationsFilters, limit, offset);

/// Paginated inbox conversations.
#[derive(Debug, Clone, Default, Deserialize)]
pub(crate) struct InboxConversationsOutput {
    /// Conversations in the current page.
    pub conversations: Vec<InboxConversationSummary>,
    /// Total number of conversations matching the filters.
    pub total: usize,
}

/// Event an inbox conversation started from.
#[derive(Debug, Clone, Deserialize)]
pub(crate) struct InboxEvent {
    /// Whether the event page is publicly available.
    pub is_public: bool,
    /// Event name.
    pub name: String,

    /// URL-friendly identifier for the event, included in conversation threads.
    pub slug: Option<String>,
}

/// Plain-text message in an inbox conversation.
#[derive(Debug, Clone, Deserialize)]
pub(crate) struct InboxMessage {
    /// Message text.
    pub body: String,
    /// When the message was written.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Message identifier.
    pub inbox_message_id: Uuid,
    /// Who wrote the message.
    pub kind: InboxMessageKind,

    /// Author of the message, absent once their account is deleted.
    pub author: Option<User>,
}

/// Validated message body written to an inbox conversation.
#[derive(Debug, Clone, Deserialize, Validate)]
pub(crate) struct InboxMessageInput {
    /// Message text. Its length is counted in characters, like the database.
    #[garde(custom(trimmed_non_empty), length(chars, max = MAX_LEN_INBOX_MESSAGE))]
    pub body: String,
}

/// Kind of inbox message, telling who wrote it even after accounts are deleted.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum InboxMessageKind {
    /// Reply written on behalf of the group.
    GroupReply,
    /// First message written by the user when starting the conversation.
    Initial,
    /// Follow-up written by the user.
    UserReply,
}

impl InboxMessageKind {
    /// Returns true when the message was written on behalf of the group.
    pub(crate) fn is_from_group(self) -> bool {
        self == InboxMessageKind::GroupReply
    }
}
