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

use super::{events, invitations, session_proposals, submissions};

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::error::HandlerError,
    templates::{
        PageId,
        auth::{self, User, UserDetails},
        dashboard::user::home::{Content, Page, Tab},
    },
};

#[cfg(test)]
mod tests;

/// Handler that returns the user dashboard home page.
///
/// This handler manages the main user dashboard page, selecting the appropriate tab
/// and preparing the content for each dashboard section.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    auth_session: AuthSession,
    messages: Messages,
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.as_ref().expect("user to be logged in").clone();

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
                user: UserDetails::from(user),
            }))
        }
        Tab::Events => {
            let (_, template) = events::prepare_list_page(&db, user.user_id, raw_query).await?;
            Content::Events(template)
        }
        Tab::Invitations => Content::Invitations(invitations::prepare_list_page(&db, user.user_id).await?),
        Tab::SessionProposals => {
            let (_, template) = session_proposals::prepare_list_page(&db, user.user_id, raw_query).await?;
            Content::SessionProposals(template)
        }
        Tab::Submissions => {
            let (_, template) = submissions::prepare_list_page(&db, user.user_id, raw_query).await?;
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
        user: User::from_session(auth_session).await?,
    };

    let html = Html(page.render()?);
    Ok(html)
}
