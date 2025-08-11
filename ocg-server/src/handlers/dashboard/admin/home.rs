//! HTTP handlers for the admin dashboard.

use std::collections::HashMap;

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Query, State},
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::CommunityId},
    templates::dashboard::admin::home::{Content, Page, Tab},
};

/// Handler that returns the admin dashboard home page.
///
/// This handler manages the main admin dashboard page, selecting the appropriate tab
/// and preparing the content for each dashboard section.
#[instrument(skip_all, err)]
pub(crate) async fn page(
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
            let groups = db.list_community_groups(community_id).await?;
            Content::Groups(crate::templates::dashboard::admin::GroupsPage { groups })
        }
    };

    // Render the page
    let page = Page {
        community,
        path: "/dashboard/admin".to_string(),
        content,
    };

    let html = Html(page.render()?);
    Ok(html)
}
