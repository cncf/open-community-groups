//! HTTP handlers for the community dashboard.

use std::collections::HashMap;

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Query, State},
    response::{Html, IntoResponse},
};
use axum_messages::Messages;
use tracing::instrument;

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::{error::HandlerError, extractors::CommunityId},
    templates::{
        PageId,
        auth::{self, User, UserDetails},
        dashboard::community::{
            groups,
            home::{Content, Page, Tab},
            settings, team,
        },
    },
};

/// Handler that returns the community dashboard home page.
///
/// This handler manages the main community dashboard page, selecting the appropriate tab
/// and preparing the content for each dashboard section.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    auth_session: AuthSession,
    messages: Messages,
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.as_ref().expect("user to be logged in").clone();

    // Get selected tab from query
    let tab: Tab = query.get("tab").unwrap_or(&String::new()).parse().unwrap_or_default();

    // Get community information
    let community = db.get_community(community_id).await?;

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
        Tab::Groups => {
            let groups = db.list_community_groups(community_id).await?;
            Content::Groups(groups::ListPage { groups })
        }
        Tab::Settings => Content::Settings(Box::new(settings::UpdatePage {
            community: community.clone(),
        })),
        Tab::Team => {
            let members = db.list_community_team_members(community_id).await?;
            let approved_members_count = members.iter().filter(|m| m.accepted).count();
            Content::Team(team::ListPage {
                approved_members_count,
                members,
            })
        }
    };

    // Render the page
    let page = Page {
        community,
        content,
        messages: messages.into_iter().collect(),
        page_id: PageId::CommunityDashboard,
        path: "/dashboard/community".to_string(),
        user: User::from_session(auth_session).await?,
    };

    let html = Html(page.render()?);
    Ok(html.into_response())
}
