//! HTTP handlers for the Inbox section in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::HeaderName,
    response::{Html, IntoResponse},
};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        dashboard::inbox::render_after_action,
        error::HandlerError,
        extractors::{CurrentUser, SelectedGroupId, ValidatedForm, ValidatedQuery},
    },
    services::inbox::{DynInboxManager, GroupConversationInput, GroupReplyInput},
    templates::dashboard::inbox::{ConversationPage, InboxScope, ListPage},
    types::{
        inbox::{InboxConversationsFilters, InboxMessageInput},
        pagination::{self, NavigationLinks},
    },
};

#[cfg(test)]
mod tests;

// URLs used by the dashboard page and tab partial.
const DASHBOARD_URL: &str = "/dashboard/group?tab=inbox";
const PARTIAL_URL: &str = "/dashboard/group/inbox";

// Pages handlers.

/// Displays a conversation thread of the selected group.
#[instrument(skip_all)]
pub(crate) async fn conversation_page(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(inbox_conversation_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the thread, rejecting conversations of other groups
    let Some(template) =
        prepare_conversation_page(&db, group_id, inbox_conversation_id, false).await?
    else {
        return Err(HandlerError::NotFound);
    };

    // Keep browser navigation on the full dashboard URL
    let url = InboxScope::Group.conversation_dashboard_url(&inbox_conversation_id);
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

/// Displays the conversations of the selected group.
#[instrument(skip_all)]
pub(crate) async fn list_page(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare list page content
    let (filters, template) =
        prepare_list_page(&db, group_id, raw_query.as_deref().unwrap_or_default()).await?;

    // Keep browser navigation on the full dashboard URL
    let url = pagination::build_url(DASHBOARD_URL, &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

// Actions handlers.

/// Closes a conversation of the selected group.
#[instrument(skip_all)]
pub(crate) async fn close(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(inbox_manager): State<DynInboxManager>,
    Path(inbox_conversation_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Close the conversation
    inbox_manager
        .close_conversation(&GroupConversationInput {
            actor_user_id: user.user_id,
            group_id,
            inbox_conversation_id,
        })
        .await?;

    // Render the updated thread
    let loaded = prepare_conversation_page(&db, group_id, inbox_conversation_id, false).await;
    render_after_action(
        loaded,
        InboxScope::Group,
        inbox_conversation_id,
        "Conversation closed.",
    )
}

/// Marks a conversation of the selected group as spam.
#[instrument(skip_all)]
pub(crate) async fn mark_spam(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(inbox_manager): State<DynInboxManager>,
    Path(inbox_conversation_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Mark the conversation as spam
    inbox_manager
        .mark_conversation_as_spam(&GroupConversationInput {
            actor_user_id: user.user_id,
            group_id,
            inbox_conversation_id,
        })
        .await?;

    // Render the updated thread
    let loaded = prepare_conversation_page(&db, group_id, inbox_conversation_id, false).await;
    render_after_action(
        loaded,
        InboxScope::Group,
        inbox_conversation_id,
        "Conversation marked as spam.",
    )
}

/// Replies to a conversation of the selected group.
#[instrument(skip_all)]
pub(crate) async fn reply(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(inbox_manager): State<DynInboxManager>,
    Path(inbox_conversation_id): Path<Uuid>,
    ValidatedForm(input): ValidatedForm<InboxMessageInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Store the reply and queue the email to the user
    inbox_manager
        .add_group_reply(&GroupReplyInput {
            actor_user_id: user.user_id,
            body: input.body,
            group_id,
            inbox_conversation_id,
        })
        .await?;

    // Render the updated thread with the reply field focused
    let loaded = prepare_conversation_page(&db, group_id, inbox_conversation_id, true).await;
    render_after_action(
        loaded,
        InboxScope::Group,
        inbox_conversation_id,
        "Message sent.",
    )
}

/// Unmarks a conversation of the selected group as spam.
#[instrument(skip_all)]
pub(crate) async fn unmark_spam(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(inbox_manager): State<DynInboxManager>,
    Path(inbox_conversation_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Unmark the conversation as spam
    inbox_manager
        .unmark_conversation_as_spam(&GroupConversationInput {
            actor_user_id: user.user_id,
            group_id,
            inbox_conversation_id,
        })
        .await?;

    // Render the updated thread
    let loaded = prepare_conversation_page(&db, group_id, inbox_conversation_id, false).await;
    render_after_action(
        loaded,
        InboxScope::Group,
        inbox_conversation_id,
        "Conversation unmarked as spam.",
    )
}

// Helpers.

/// Prepares a conversation thread of the group, or `None` when the
/// conversation belongs to another group.
pub(crate) async fn prepare_conversation_page(
    db: &DynDB,
    group_id: Uuid,
    inbox_conversation_id: Uuid,
    focus_message: bool,
) -> Result<Option<ConversationPage>, HandlerError> {
    // Load the thread within the group
    let conversation = db
        .get_group_inbox_conversation(group_id, inbox_conversation_id)
        .await?;

    Ok(conversation.map(|conversation| ConversationPage {
        conversation,
        focus_message,
        scope: InboxScope::Group,
    }))
}

/// Prepares the conversations list page and filters for the group dashboard.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    group_id: Uuid,
    raw_query: &str,
) -> Result<(InboxConversationsFilters, ListPage), HandlerError> {
    // Parse and validate list filters
    let filters: InboxConversationsFilters = ValidatedQuery::parse(raw_query)?;

    // Load the conversations of the group
    let results = db.list_group_inbox_conversations(group_id, &filters).await?;

    // Build pagination links and the template
    let navigation_links =
        NavigationLinks::from_filters(&filters, results.total, DASHBOARD_URL, PARTIAL_URL)?;
    let template = ListPage {
        conversations: results.conversations,
        navigation_links,
        scope: InboxScope::Group,
        total: results.total,

        offset: filters.offset,
        status: filters.status,
        warning: None,
    };

    Ok((filters, template))
}
