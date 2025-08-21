//! HTTP handlers for the community dashboard.

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
    handlers::{error::HandlerError, extractors::CommunityId},
    templates::{
        PageId,
        auth::{self, User, UserDetails},
        dashboard::community::{
            groups,
            home::{Content, Page, Tab},
            settings,
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
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session
    let Some(user) = auth_session.user.clone() else {
        return Ok(StatusCode::FORBIDDEN.into_response());
    };

    // Get selected tab from query
    let tab: Tab = query.get("tab").unwrap_or(&String::new()).parse().unwrap_or_default();

    // Get community information
    let community = db.get_community(community_id).await?;

    // Prepare content for the selected tab
    let content = match tab {
        Tab::Account => Content::Account(Box::new(auth::UpdateUserPage {
            user: UserDetails::from(user),
        })),
        Tab::Groups => {
            let groups = db.list_community_groups(community_id).await?;
            Content::Groups(groups::ListPage { groups })
        }
        Tab::Settings => Content::Settings(Box::new(settings::UpdatePage {
            community: community.clone(),
        })),
    };

    // Render the page
    let page = Page {
        community,
        content,
        page_id: PageId::CommunityDashboard,
        path: "/dashboard/community".to_string(),
        user: User::from_session(auth_session).await?,
    };

    let html = Html(page.render()?);
    Ok(html.into_response())
}
