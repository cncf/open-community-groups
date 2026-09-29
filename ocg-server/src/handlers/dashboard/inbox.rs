//! Inbox helpers shared by the group and user dashboard handlers.

use std::collections::HashMap;

use askama::Template;
use axum::response::Html;
use tracing::warn;
use uuid::Uuid;

use crate::{
    handlers::error::HandlerError,
    templates::dashboard::inbox::{ActionDoneNotice, ConversationPage, InboxScope},
};

#[cfg(test)]
mod tests;

/// Renders an inbox thread after a committed action. When the thread cannot
/// be loaded again, the committed action is still reported as done, with a
/// link that reloads the conversation.
pub(crate) fn render_after_action(
    loaded: Result<Option<ConversationPage>, HandlerError>,
    scope: InboxScope,
    inbox_conversation_id: Uuid,
    done_message: &str,
) -> Result<Html<String>, HandlerError> {
    // Render the refreshed thread when it was loaded
    let reason = match loaded {
        Ok(Some(template)) => return Ok(Html(template.render()?)),
        Ok(None) => "conversation not found".to_string(),
        Err(err) => format!("{err:#}"),
    };

    // Report the committed action without failing the request
    warn!(
        %inbox_conversation_id,
        error = %reason,
        "inbox conversation could not be loaded after a committed action"
    );
    let notice = ActionDoneNotice {
        message: done_message.to_string(),
        reload_url: scope.conversation_dashboard_url(&inbox_conversation_id),
    };

    Ok(Html(notice.render()?))
}

/// Returns the conversation requested in a dashboard home query, ignoring
/// malformed identifiers.
pub(crate) fn requested_conversation_id(query: &HashMap<String, String>) -> Option<Uuid> {
    query.get("conversation_id").and_then(|id| id.parse().ok())
}
