//! Shared templates for the group and user dashboard inboxes.

use askama::Template;
use uuid::Uuid;

use crate::{
    templates::filters,
    types::{
        inbox::{InboxConversation, InboxConversationStatus, InboxConversationSummary},
        pagination,
        user::User,
    },
};

#[cfg(test)]
mod tests;

/// Label shown in place of a user whose account was deleted.
const DELETED_USER_LABEL: &str = "Deleted user";

// Pages templates.

/// Notice rendered when an inbox action succeeded but the thread could not be
/// loaded again.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/inbox_action_done.html")]
pub(crate) struct ActionDoneNotice {
    /// Message describing the completed action.
    pub message: String,
    /// Full dashboard URL that reloads the conversation.
    pub reload_url: String,
}

/// Inbox conversation thread page.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/inbox_conversation.html")]
pub(crate) struct ConversationPage {
    /// Conversation thread to render.
    pub conversation: InboxConversation,
    /// Whether the message field receives focus, set after a message is sent.
    pub focus_message: bool,
    /// Dashboard rendering the conversation.
    pub scope: InboxScope,

    /// Focused notice reporting the action that refreshed the thread.
    pub action_notice: Option<String>,
}

impl ConversationPage {
    /// Returns true when the group can close the conversation.
    pub(crate) fn can_close(&self) -> bool {
        self.scope == InboxScope::Group && !self.is_closed() && !self.is_spam()
    }

    /// Returns true when the group can mark the conversation as spam.
    pub(crate) fn can_mark_spam(&self) -> bool {
        self.scope == InboxScope::Group && !self.is_spam()
    }

    /// Returns true when a new message can be written to the conversation.
    pub(crate) fn can_reply(&self) -> bool {
        !self.conversation.is_read_only() && !self.is_spam()
    }

    /// Returns true when the group can unmark the conversation as spam.
    pub(crate) fn can_unmark_spam(&self) -> bool {
        self.scope == InboxScope::Group && self.is_spam()
    }

    /// Returns true when the conversation is closed.
    pub(crate) fn is_closed(&self) -> bool {
        self.conversation.status == InboxConversationStatus::Closed
    }

    /// Returns true when the group marked the conversation as spam.
    pub(crate) fn is_spam(&self) -> bool {
        self.conversation.status == InboxConversationStatus::Spam
    }

    /// Returns the label shown for the user who started the conversation.
    pub(crate) fn user_label(&self) -> String {
        user_label(self.conversation.user.as_ref())
    }
}

/// Inbox conversations list page.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/inbox_list.html")]
pub(crate) struct ListPage {
    /// Conversations in the current page.
    pub conversations: Vec<InboxConversationSummary>,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// Dashboard rendering the list.
    pub scope: InboxScope,
    /// Total number of conversations matching the filters.
    pub total: usize,

    /// Pagination offset for results.
    pub offset: Option<usize>,
    /// Status filter applied to the list.
    pub status: Option<InboxConversationStatus>,
    /// Warning shown above the list.
    pub warning: Option<String>,
}

impl ListPage {
    /// Returns the label shown for the other party of a conversation.
    pub(crate) fn counterpart_label(&self, conversation: &InboxConversationSummary) -> String {
        match self.scope {
            InboxScope::Group => user_label(conversation.user.as_ref()),
            InboxScope::User => conversation.group_name.clone(),
        }
    }

    /// Returns true when the list is filtered by the given status value.
    pub(crate) fn is_status(&self, value: &str) -> bool {
        self.status.is_some_and(|status| status.to_string() == value)
    }

    /// Returns true when the list shows every status.
    pub(crate) fn is_unfiltered(&self) -> bool {
        self.status.is_none()
    }
}

// Types.

/// Dashboard rendering an inbox.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum InboxScope {
    /// Group dashboard inbox answered by the group team.
    Group,
    /// User dashboard inbox with the user's conversations.
    User,
}

impl InboxScope {
    /// Returns the URL that closes a conversation; only the group closes them.
    pub(crate) fn close_url(self, inbox_conversation_id: &Uuid) -> Option<String> {
        match self {
            InboxScope::Group => Some(format!(
                "/dashboard/group/inbox/{inbox_conversation_id}/close"
            )),
            InboxScope::User => None,
        }
    }

    /// Returns the full dashboard URL that opens a conversation.
    pub(crate) fn conversation_dashboard_url(self, inbox_conversation_id: &Uuid) -> String {
        format!(
            "{}&conversation_id={inbox_conversation_id}",
            self.dashboard_url()
        )
    }

    /// Returns the partial URL that renders a conversation thread.
    pub(crate) fn conversation_url(self, inbox_conversation_id: &Uuid) -> String {
        format!("{}/{inbox_conversation_id}", self.list_url())
    }

    /// Returns the full dashboard URL of the inbox.
    pub(crate) fn dashboard_url(self) -> &'static str {
        match self {
            InboxScope::Group => "/dashboard/group?tab=inbox",
            InboxScope::User => "/dashboard/user?tab=inbox",
        }
    }

    /// Returns true for the group dashboard inbox.
    pub(crate) fn is_group(self) -> bool {
        self == InboxScope::Group
    }

    /// Returns the partial URL that renders the conversations list.
    pub(crate) fn list_url(self) -> &'static str {
        match self {
            InboxScope::Group => "/dashboard/group/inbox",
            InboxScope::User => "/dashboard/user/inbox",
        }
    }

    /// Returns the URL that marks a conversation as spam; only the group marks
    /// them.
    pub(crate) fn mark_spam_url(self, inbox_conversation_id: &Uuid) -> Option<String> {
        match self {
            InboxScope::Group => Some(format!(
                "/dashboard/group/inbox/{inbox_conversation_id}/mark-spam"
            )),
            InboxScope::User => None,
        }
    }

    /// Returns the URL that stores a new message in a conversation.
    pub(crate) fn message_url(self, inbox_conversation_id: &Uuid) -> String {
        match self {
            InboxScope::Group => {
                format!("{}/replies", self.conversation_url(inbox_conversation_id))
            }
            InboxScope::User => {
                format!("{}/messages", self.conversation_url(inbox_conversation_id))
            }
        }
    }

    /// Returns the URL that unmarks a conversation as spam; only the group
    /// unmarks them.
    pub(crate) fn unmark_spam_url(self, inbox_conversation_id: &Uuid) -> Option<String> {
        match self {
            InboxScope::Group => Some(format!(
                "/dashboard/group/inbox/{inbox_conversation_id}/unmark-spam"
            )),
            InboxScope::User => None,
        }
    }
}

// Helpers.

/// Returns the label shown for a user, or the deleted-user label.
fn user_label(user: Option<&User>) -> String {
    user.map_or_else(
        || DELETED_USER_LABEL.to_string(),
        |user| user.name.clone().unwrap_or_else(|| user.username.clone()),
    )
}
