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
use std::{collections::HashMap, fmt::Display};
use tracing::{debug, error};

/// Index document template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/index.html")]
#[allow(dead_code)]
pub(crate) struct Index {
    pub community: IndexCommunity,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct IndexCommunity {
    pub banners_urls: Option<Vec<String>>,
    pub copyright_notice: Option<String>,
    pub description: Option<String>,
    pub display_name: String,
    pub extra_links: Option<HashMap<String, String>>,
    pub facebook_url: Option<String>,
    pub flickr_url: Option<String>,
    pub footer_logo_url: Option<String>,
    pub github_url: Option<String>,
    pub header_logo_url: Option<String>,
    pub homepage_url: Option<String>,
    pub instagram_url: Option<String>,
    pub linkedin_url: Option<String>,
    pub photos_urls: Option<Vec<String>>,
    pub slack_url: Option<String>,
    pub twitter_url: Option<String>,
    pub wechat_url: Option<String>,
    pub youtube_url: Option<String>,
}

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

/// Explore page template.
#[derive(Debug, Clone, Template)]
#[template(path = "community/explore.html")]
#[allow(dead_code)]
pub(crate) struct Explore {
    pub params: HashMap<String, String>,
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

/// Explore events section template.
#[derive(Debug, Clone, Template)]
#[template(path = "community/events.html")]
pub(crate) struct Events {}

/// Handler that returns the explore events section.
#[allow(clippy::unused_async)]
pub(crate) async fn events(CommunityId(_community_id): CommunityId) -> impl IntoResponse {
    Events {}
}

/// Explore groups section template.
#[derive(Debug, Clone, Template)]
#[template(path = "community/groups.html")]
pub(crate) struct Groups {}

/// Handler that returns the explore groups section.
#[allow(clippy::unused_async)]
pub(crate) async fn groups(CommunityId(_community): CommunityId) -> impl IntoResponse {
    Groups {}
}

/// Helper for mapping any error into a `500 Internal Server Error` response.
#[allow(clippy::needless_pass_by_value)]
fn internal_error<E>(err: E) -> StatusCode
where
    E: Into<Error> + Display,
{
    error!(%err);
    StatusCode::INTERNAL_SERVER_ERROR
}
