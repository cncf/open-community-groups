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

/// Handler that returns the home page.
pub(crate) async fn home(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Query(params): Query<HashMap<String, String>>,
    request: Request,
) -> Result<impl IntoResponse, StatusCode> {
    let home = Home {
        params,
        path: request.uri().path().to_string(),
        ..db.get_community_home_data(community_id)
            .await
            .map_err(internal_error)?
    };

    Ok(home)
}

/// Handler that returns the explore page.
pub(crate) async fn explore(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Query(params): Query<HashMap<String, String>>,
    request: Request,
) -> Result<impl IntoResponse, StatusCode> {
    let explore = Explore {
        params,
        path: request.uri().path().to_string(),
        ..db.get_community_explore_data(community_id)
            .await
            .map_err(internal_error)?
    };

    Ok(explore)
}

/// Handler that returns the explore events section.
pub(crate) async fn explore_events(CommunityId(_community_id): CommunityId) -> impl IntoResponse {
    ExploreEvents {}
}

/// Handler that returns the explore groups section.
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

/// Home page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/home.html")]
#[allow(dead_code)]
pub(crate) struct Home {
    #[serde(default)]
    pub params: HashMap<String, String>,
    #[serde(default)]
    pub path: String,

    pub community: Community,
    pub recently_added_groups: Vec<HomeGroup>,
    pub upcoming_in_person_events: Vec<HomeEvent>,
    pub upcoming_online_events: Vec<HomeEvent>,
}

impl TryFrom<serde_json::Value> for Home {
    type Error = Error;

    fn try_from(json_data: serde_json::Value) -> Result<Self> {
        let mut home: Home =
            serde_json::from_value(json_data).context("error deserializing home json data")?;

        // Convert markdown content in some fields to HTML
        home.community.description = markdown::to_html(&home.community.description);
        if let Some(copyright_notice) = &home.community.copyright_notice {
            home.community.copyright_notice = Some(markdown::to_html(copyright_notice));
        }
        if let Some(new_group_details) = &home.community.new_group_details {
            home.community.new_group_details = Some(markdown::to_html(new_group_details));
        }

        Ok(home)
    }
}

/// Event information used in the community home page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct HomeEvent {
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

/// Group information used in the community home page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct HomeGroup {
    pub name: String,
    pub region_name: String,
    pub slug: String,

    pub city: Option<String>,
    pub country: Option<String>,
    pub icon_url: Option<String>,
    pub state: Option<String>,
}

/// Explore page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/explore.html")]
#[allow(dead_code)]
pub(crate) struct Explore {
    #[serde(default)]
    pub params: HashMap<String, String>,
    #[serde(default)]
    pub path: String,

    pub community: Community,
}

impl TryFrom<serde_json::Value> for Explore {
    type Error = Error;

    fn try_from(json_data: serde_json::Value) -> Result<Self> {
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

/// Community information used in some community pages.
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
