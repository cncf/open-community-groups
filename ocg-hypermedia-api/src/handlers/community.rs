//! This module defines the HTTP handlers for the community site.

use super::extractor::CommunityId;
use crate::db::DynDB;
use anyhow::Error;
use askama::Template;
use askama_axum::IntoResponse;
use axum::{
    extract::{Query, State},
    http::StatusCode,
};
use serde::{Deserialize, Serialize};
use std::{collections::HashMap, fmt::Debug};
use time::OffsetDateTime;
use tracing::{debug, error};

/// Handler that returns the index document.
#[allow(clippy::unused_async)]
pub(crate) async fn index(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
) -> impl IntoResponse {
    db.get_community_index_data(community_id)
        .await
        .map_err(internal_error)
}

/// Handler that returns the explore page.
#[allow(clippy::unused_async)]
pub(crate) async fn explore(
    CommunityId(community_id): CommunityId,
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    debug!("community_id: {}, params: {:?}", community_id, params);

    Explore { params }
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
    pub community: IndexCommunity,
    pub groups: Vec<IndexGroup>,
    pub upcoming_in_person_events: Vec<IndexEvent>,
    pub upcoming_online_events: Vec<IndexEvent>,
}

/// Community information used in the community index.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct IndexCommunity {
    pub display_name: String,
    pub header_logo_url: String,
    pub title: String,
    pub description: String,
    pub banners_urls: Option<Vec<String>>,
    pub copyright_notice: Option<String>,
    pub extra_links: Option<HashMap<String, String>>,
    pub facebook_url: Option<String>,
    pub flickr_url: Option<String>,
    pub footer_logo_url: Option<String>,
    pub github_url: Option<String>,
    pub homepage_url: Option<String>,
    pub instagram_url: Option<String>,
    pub linkedin_url: Option<String>,
    pub photos_urls: Option<Vec<String>>,
    pub slack_url: Option<String>,
    pub twitter_url: Option<String>,
    pub wechat_url: Option<String>,
    pub youtube_url: Option<String>,
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
}

/// Event information used in the community index.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct IndexEvent {
    pub group_name: String,
    pub icon_url: Option<String>,
    pub slug: String,
    #[serde(with = "time::serde::iso8601")]
    pub starts_at: OffsetDateTime,
    pub title: String,
}

/// Explore page template.
#[derive(Debug, Clone, Template)]
#[template(path = "community/explore.html")]
#[allow(dead_code)]
pub(crate) struct Explore {
    pub params: HashMap<String, String>,
}

/// Explore events section template.
#[derive(Debug, Clone, Template)]
#[template(path = "community/explore_events.html")]
pub(crate) struct ExploreEvents {}

/// Explore groups section template.
#[derive(Debug, Clone, Template)]
#[template(path = "community/explore_groups.html")]
pub(crate) struct ExploreGroups {}
