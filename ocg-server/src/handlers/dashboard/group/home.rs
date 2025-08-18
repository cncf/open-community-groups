//! HTTP handlers for the group dashboard home page.

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
    handlers::{
        error::HandlerError,
        extractors::{CommunityId, SelectedGroupId},
    },
    templates::{
        PageId,
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
    CommunityId(community_id): CommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get selected tab from query
    let tab: Tab = query.get("tab").unwrap_or(&String::new()).parse().unwrap_or_default();

    // Get community information
    let community = db.get_community(community_id).await?;

    // Prepare content for the selected tab
    let content = match tab {
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
        page_id: PageId::GroupDashboard,
        path: "/dashboard/group".to_string(),
    };

    let html = Html(page.render()?);
    Ok(html)
}
