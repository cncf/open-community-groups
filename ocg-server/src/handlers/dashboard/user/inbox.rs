//! HTTP handlers for the Inbox section in the user dashboard.

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
        dashboard::inbox::{ActionFeedback, render_after_action},
        error::HandlerError,
        extractors::{CurrentUser, ValidatedForm, ValidatedQuery},
    },
    services::inbox::{DynInboxManager, UserMessageInput},
    templates::dashboard::inbox::{ConversationPage, InboxScope, ListPage},
    types::{
        inbox::{InboxConversationsFilters, InboxMessageInput},
        pagination::{self, NavigationLinks},
    },
};

#[cfg(test)]
mod tests;

// URLs used by the dashboard page and tab partial.
const DASHBOARD_URL: &str = "/dashboard/user?tab=inbox";
const PARTIAL_URL: &str = "/dashboard/user/inbox";

// Pages handlers.

/// Displays a conversation thread of the current user.
#[instrument(skip_all)]
pub(crate) async fn conversation_page(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(inbox_conversation_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the thread, rejecting conversations of other users
    let Some(template) =
        prepare_conversation_page(&db, user.user_id, inbox_conversation_id, false).await?
    else {
        return Err(HandlerError::NotFound);
    };

    // Keep browser navigation on the full dashboard URL
    let url = InboxScope::User.conversation_dashboard_url(&inbox_conversation_id);
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

/// Displays the conversations of the current user.
#[instrument(skip_all)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare list page content
    let (filters, template) =
        prepare_list_page(&db, user.user_id, raw_query.as_deref().unwrap_or_default()).await?;

    // Keep browser navigation on the full dashboard URL
    let url = pagination::build_url(DASHBOARD_URL, &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

// Actions handlers.

/// Sends a follow-up message to a conversation of the current user.
#[instrument(skip_all)]
pub(crate) async fn send_message(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(inbox_manager): State<DynInboxManager>,
    Path(inbox_conversation_id): Path<Uuid>,
    ValidatedForm(input): ValidatedForm<InboxMessageInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Store the follow-up and queue the email to the group team
    inbox_manager
        .add_user_message(&UserMessageInput {
            body: input.body,
            inbox_conversation_id,
            user_id: user.user_id,
        })
        .await?;

    // Render the updated thread with the message field focused
    let loaded = prepare_conversation_page(&db, user.user_id, inbox_conversation_id, true).await;
    render_after_action(
        loaded,
        InboxScope::User,
        inbox_conversation_id,
        "Message sent.",
        ActionFeedback::Alert,
    )
}

// Helpers.

/// Prepares a conversation thread of the user, or `None` when the user does
/// not own the conversation.
pub(crate) async fn prepare_conversation_page(
    db: &DynDB,
    user_id: Uuid,
    inbox_conversation_id: Uuid,
    focus_message: bool,
) -> Result<Option<ConversationPage>, HandlerError> {
    // Load the thread within the user scope
    let conversation = db.get_user_inbox_conversation(user_id, inbox_conversation_id).await?;

    Ok(conversation.map(|conversation| ConversationPage {
        conversation,
        focus_message,
        scope: InboxScope::User,

        action_notice: None,
    }))
}

/// Prepares the conversations list page and filters for the user dashboard.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    user_id: Uuid,
    raw_query: &str,
) -> Result<(InboxConversationsFilters, ListPage), HandlerError> {
    // Parse and validate list filters
    let filters: InboxConversationsFilters = ValidatedQuery::parse(raw_query)?;

    // Load the conversations of the user
    let results = db.list_user_inbox_conversations(user_id, &filters).await?;

    // Build pagination links and the template
    let navigation_links =
        NavigationLinks::from_filters(&filters, results.total, DASHBOARD_URL, PARTIAL_URL)?;
    let template = ListPage {
        conversations: results.conversations,
        navigation_links,
        scope: InboxScope::User,
        total: results.total,

        offset: filters.offset,
        status: filters.status,
        warning: None,
    };

    Ok((filters, template))
}
