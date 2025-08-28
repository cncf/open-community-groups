//! HTTP handlers for the group dashboard home page.

use std::collections::HashMap;

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CommunityId, SelectedGroupId},
    },
    templates::{
        PageId,
        auth::{self, User, UserDetails},
        dashboard::group::{
            events,
            home::{Content, Page, Tab},
            settings,
        },
    },
};

/// Handler that returns the group dashboard home page.
///
/// This handler manages the main group dashboard page, selecting the appropriate tab
/// and preparing the content for each dashboard section.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    auth_session: AuthSession,
    CommunityId(community_id): CommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session
    let Some(user) = auth_session.user.clone() else {
        return Ok(StatusCode::FORBIDDEN.into_response());
    };

    // Get selected tab from query
    let tab: Tab = query.get("tab").unwrap_or(&String::new()).parse().unwrap_or_default();

    // Get community and user groups information
    let (community, groups) =
        tokio::try_join!(db.get_community(community_id), db.list_user_groups(&user.user_id))?;

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
            let events = db.list_group_events(group_id).await?;
            Content::Events(events::ListPage { events })
        }
        Tab::Settings => {
            let group = db.get_group_full(group_id).await?;
            Content::Settings(Box::new(settings::UpdatePage { group }))
        }
    };

    // Render the page
    let page = Page {
        community,
        content,
        groups,
        page_id: PageId::GroupDashboard,
        path: "/dashboard/group".to_string(),
        selected_group_id: group_id,
        user: User::from_session(auth_session).await?,
    };

    let html = Html(page.render()?);
    Ok(html.into_response())
}
