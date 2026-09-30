//! HTTP handlers for the user dashboard.

use std::collections::HashMap;

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Query, RawQuery, State},
    response::{Html, IntoResponse},
};
use axum_messages::Messages;
use tracing::instrument;

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::{
        dashboard::inbox::requested_conversation_id, error::HandlerError, extractors::CurrentUser,
    },
    templates::{
        PageId,
        auth::{self, UserMenuState},
        dashboard::user::home::{Content, Page, Tab},
    },
    types::user::UserDetailsInput,
};

use super::{
    badges, check_in, events, groups, inbox, invitations, logs, notifications, purchases,
    session_proposals, submissions,
};

#[cfg(test)]
mod tests;

/// Warning shown when a requested conversation is not one of the user's.
const INBOX_CONVERSATION_NOT_FOUND_WARNING: &str = "This conversation isn't in your Inbox.";

/// Handler that returns the user dashboard home page.
///
/// This handler manages the main user dashboard page, selecting the appropriate tab
/// and preparing the content for each dashboard section.
#[instrument(skip_all)]
pub(crate) async fn page(
    CurrentUser(user): CurrentUser,
    auth_session: AuthSession,
    messages: Messages,
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Get selected tab from query
    let raw_query = raw_query.as_deref().unwrap_or_default();
    let tab: Tab = query
        .get("tab")
        .map_or(Tab::default(), |tab| tab.parse().unwrap_or_default());

    // Get site settings
    let site_settings = db.get_site_settings().await?;

    // Prepare content for the selected tab
    let content = match tab {
        Tab::Account => {
            let timezones = db.list_timezones().await?;
            Content::Account(Box::new(auth::UpdateUserPage {
                has_password: user.has_password.unwrap_or(false),
                timezones,
                user: UserDetailsInput::from(user),
            }))
        }
        Tab::Badges => Content::Badges(badges::prepare_list_page(&db, user.user_id).await?),
        Tab::CheckIn => Content::CheckIn(check_in::prepare_list_page(&db, &user).await?),
        Tab::Events => {
            let (_, template) = events::prepare_list_page(&db, user.user_id, raw_query).await?;
            Content::Events(template)
        }
        Tab::Groups => {
            let (_, template) = groups::prepare_list_page(&db, user.user_id, raw_query).await?;
            Content::Groups(template)
        }
        Tab::Inbox => {
            // Load the requested conversation when the user owns it
            let inbox_conversation_id = requested_conversation_id(&query);
            let conversation = match inbox_conversation_id {
                Some(id) => inbox::prepare_conversation_page(&db, user.user_id, id, false).await?,
                None => None,
            };

            // Show the conversation, or the list warning about an unavailable one
            if let Some(template) = conversation {
                Content::InboxConversation(Box::new(template))
            } else {
                let (_, mut template) =
                    inbox::prepare_list_page(&db, user.user_id, raw_query).await?;
                template.warning =
                    inbox_conversation_id.map(|_| INBOX_CONVERSATION_NOT_FOUND_WARNING.to_string());
                Content::Inbox(template)
            }
        }
        Tab::Invitations => {
            Content::Invitations(invitations::prepare_list_page(&db, user.user_id).await?)
        }
        Tab::Logs => {
            let (_, template) = logs::prepare_list_page(&db, user.user_id, raw_query).await?;
            Content::Logs(template)
        }
        Tab::Notifications => {
            Content::Notifications(Box::new(notifications::prepare_page(&db, &user).await?))
        }
        Tab::Purchases => {
            let (_, template) = purchases::prepare_list_page(&db, user.user_id, raw_query).await?;
            Content::Purchases(template)
        }
        Tab::SessionProposals => {
            let (_, template) =
                session_proposals::prepare_list_page(&db, user.user_id, raw_query).await?;
            Content::SessionProposals(template)
        }
        Tab::Submissions => {
            let (_, template) =
                submissions::prepare_list_page(&db, user.user_id, raw_query).await?;
            Content::Submissions(template)
        }
    };

    // Render the page
    let page = Page {
        content,
        messages: messages.into_iter().collect(),
        page_id: PageId::UserDashboard,
        path: "/dashboard/user".to_string(),
        site_settings,
        user: UserMenuState::from_session(auth_session).await?,
    };

    let html = Html(page.render()?);
    Ok(html)
}
