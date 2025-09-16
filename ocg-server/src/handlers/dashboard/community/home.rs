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
    handlers::{
        dashboard::community::groups::MAX_GROUPS_LISTED, error::HandlerError, extractors::CommunityId,
    },
    templates::{
        PageId,
        auth::User,
        community::explore::GroupsFilters,
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
    // Get selected tab from query
    let tab: Tab = query.get("tab").unwrap_or(&String::new()).parse().unwrap_or_default();

    // Get community information
    let community = db.get_community(community_id).await?;

    // Prepare content for the selected tab
    let content = match tab {
        Tab::Groups => {
            let filters = GroupsFilters {
                limit: Some(MAX_GROUPS_LISTED),
                sort_by: Some("name".to_string()),
                ts_query: query.get("ts_query").cloned(),
                ..GroupsFilters::default()
            };
            let groups = db.search_community_groups(community_id, &filters).await?.groups;
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
    Ok(html)
}
