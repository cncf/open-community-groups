//! HTTP handlers for the group dashboard home page.

use std::collections::HashMap;

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Path, Query, State},
    response::{Html, IntoResponse},
};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::CommunityId},
    templates::dashboard::group::home::{Content, Page, Tab},
};

/// Handler that returns the group dashboard home page.
///
/// This handler manages the main group dashboard page, selecting the appropriate tab
/// and preparing the content for each dashboard section.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
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
            Content::Events(crate::templates::dashboard::group::EventsPage { events })
        }
    };

    // Render the page
    let page = Page {
        community,
        path: format!("/dashboard/group/{group_id}"),
        group_id,
        group_name: "Group".to_string(), // TODO: Get actual group name
        content,
    };

    let html = Html(page.render()?);
    Ok(html)
}
