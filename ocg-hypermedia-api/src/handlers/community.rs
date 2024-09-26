//! This module defines the HTTP handlers for the community site.

use super::extractor::CommunityId;
use crate::db::DynDB;
use anyhow::{Context, Error, Result};
use askama::Template;
use askama_axum::IntoResponse;
use axum::{
    extract::{Query, Request, State},
    http::StatusCode,
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, HashMap},
    fmt::Debug,
};
use tracing::error;

/// Handler that returns the index document.
#[allow(clippy::unused_async)]
pub(crate) async fn index(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Query(params): Query<HashMap<String, String>>,
    request: Request,
) -> Result<impl IntoResponse, StatusCode> {
    let mut index = db
        .get_community_index_data(community_id)
        .await
        .map_err(internal_error)?;

    index.params = params;
    index.path = request.uri().path().to_string();

    Ok(index)
}

/// Handler that returns the explore page.
#[allow(clippy::unused_async)]
pub(crate) async fn explore(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Query(params): Query<HashMap<String, String>>,
    request: Request,
) -> Result<impl IntoResponse, StatusCode> {
    let mut explore = db
        .get_community_explore_data(community_id)
        .await
        .map_err(internal_error)?;

    explore.params = params;
    explore.path = request.uri().path().to_string();

    Ok(explore)
}

/// Handler that returns the explore events section.
#[allow(clippy::unused_async)]
pub(crate) async fn explore_events(CommunityId(_community_id): CommunityId) -> impl IntoResponse {
    ExploreEvents {}
}

/// Handler that returns the explore groups section.
#[allow(clippy::unused_async)]
pub(crate) async fn explore_groups(CommunityId(_community): CommunityId) -> impl IntoResponse {
    ExploreGroups {}
}

/// Helper for mapping any error into a `500 Internal Server Error` response.
#[allow(clippy::needless_pass_by_value)]
fn internal_error<E>(err: E) -> StatusCode
where
    E: Into<Error> + Debug,
{
    error!(?err);
    StatusCode::INTERNAL_SERVER_ERROR
}

/// Index document template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/index.html")]
#[allow(dead_code)]
pub(crate) struct Index {
    pub community: Community,
    pub recently_added_groups: Vec<IndexGroup>,
    pub upcoming_in_person_events: Vec<IndexEvent>,
    pub upcoming_online_events: Vec<IndexEvent>,

    #[serde(default)]
    pub params: HashMap<String, String>,
    #[serde(default)]
    pub path: String,
}

impl TryFrom<serde_json::Value> for Index {
    type Error = Error;

    fn try_from(json_data: serde_json::Value) -> Result<Self> {
        // Deserialize JSON data
        let mut index: Index =
            serde_json::from_value(json_data).context("error deserializing index json data")?;

        // Convert markdown content in some fields to HTML
        index.community.description = markdown::to_html(&index.community.description);
        if let Some(copyright_notice) = &index.community.copyright_notice {
            index.community.copyright_notice = Some(markdown::to_html(copyright_notice));
        }
        if let Some(new_group_details) = &index.community.new_group_details {
            index.community.new_group_details = Some(markdown::to_html(new_group_details));
        }

        Ok(index)
    }
}

/// Group information used in the community index.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct IndexGroup {
    pub name: String,
    pub region_name: String,
    pub slug: String,

    pub city: Option<String>,
    pub country: Option<String>,
    pub icon_url: Option<String>,
    pub state: Option<String>,
}

/// Event information used in the community index.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct IndexEvent {
    pub group_name: String,
    pub group_slug: String,
    pub slug: String,
    #[serde(with = "chrono::serde::ts_seconds")]
    pub starts_at: DateTime<Utc>,
    pub title: String,

    pub city: Option<String>,
    pub icon_url: Option<String>,
    pub state: Option<String>,
}

/// Explore page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/explore.html")]
#[allow(dead_code)]
pub(crate) struct Explore {
    pub community: Community,

    #[serde(default)]
    pub params: HashMap<String, String>,
    #[serde(default)]
    pub path: String,
}

impl TryFrom<serde_json::Value> for Explore {
    type Error = Error;

    fn try_from(json_data: serde_json::Value) -> Result<Self> {
        // Deserialize JSON data
        let explore: Explore =
            serde_json::from_value(json_data).context("error deserializing explore json data")?;

        Ok(explore)
    }
}

/// Explore events section template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/explore_events.html")]
pub(crate) struct ExploreEvents {}

/// Explore groups section template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/explore_groups.html")]
pub(crate) struct ExploreGroups {}

/// Community information used in the community index.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Community {
    pub display_name: String,
    pub header_logo_url: String,
    pub title: String,
    pub description: String,

    pub ad_banner_link_url: Option<String>,
    pub ad_banner_url: Option<String>,
    pub copyright_notice: Option<String>,
    pub extra_links: Option<BTreeMap<String, String>>,
    pub facebook_url: Option<String>,
    pub flickr_url: Option<String>,
    pub footer_logo_url: Option<String>,
    pub github_url: Option<String>,
    pub homepage_url: Option<String>,
    pub instagram_url: Option<String>,
    pub linkedin_url: Option<String>,
    pub new_group_details: Option<String>,
    pub photos_urls: Option<Vec<String>>,
    pub slack_url: Option<String>,
    pub twitter_url: Option<String>,
    pub wechat_url: Option<String>,
    pub youtube_url: Option<String>,
}
