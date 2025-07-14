//! This module defines the templates for the group site.

use std::collections::BTreeMap;

use anyhow::Result;
use askama::Template;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use tracing::instrument;
use uuid::Uuid;

use crate::templates::{
    community::home::Event,
    helpers::{LocationParts, build_location, color},
};

/// Group page template.
#[allow(dead_code)]
#[derive(Debug, Clone, Template)]
#[template(path = "group/page.html")]
pub(crate) struct Page {
    /// Detailed information about the group.
    pub group: Group,
    /// List of past events for this group.
    pub past_events: Vec<Event>,
    /// List of upcoming events for this group.
    pub upcoming_events: Vec<Event>,
}

/// Comprehensive group information for the group page.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Group {
    /// Category this group belongs to.
    pub category_name: String,
    /// Generated color for visual distinction.
    #[serde(default)]
    pub color: String,
    /// When the group was created.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Total number of group members.
    pub members_count: i64,
    /// Group name.
    pub name: String,
    /// List of group organizers.
    pub organizers: Vec<User>,
    /// URL slug of the group.
    pub slug: String,

    /// Banner image URL for the group page.
    pub banner_url: Option<String>,
    /// City where the group is based.
    pub city: Option<String>,
    /// ISO country code of the group.
    pub country_code: Option<String>,
    /// Full country name of the group.
    pub country_name: Option<String>,
    /// Group description text.
    pub description: Option<String>,
    /// Additional links as key-value pairs.
    pub extra_links: Option<BTreeMap<String, String>>,
    /// Facebook profile URL.
    pub facebook_url: Option<String>,
    /// Flickr profile URL.
    pub flickr_url: Option<String>,
    /// GitHub organization URL.
    pub github_url: Option<String>,
    /// Instagram profile URL.
    pub instagram_url: Option<String>,
    /// Latitude for map display.
    pub latitude: Option<f64>,
    /// `LinkedIn` profile URL.
    pub linkedin_url: Option<String>,
    /// URL to the group logo.
    pub logo_url: Option<String>,
    /// Longitude for map display.
    pub longitude: Option<f64>,
    /// Gallery of photo URLs.
    pub photos_urls: Option<Vec<String>>,
    /// Name of the geographic region.
    pub region_name: Option<String>,
    /// Slack workspace URL.
    pub slack_url: Option<String>,
    /// State/province where the group is based.
    pub state: Option<String>,
    /// Tags associated with the group.
    pub tags: Option<Vec<String>>,
    /// Twitter profile URL.
    pub twitter_url: Option<String>,
    /// `WeChat` URL.
    pub wechat_url: Option<String>,
    /// Group website URL.
    pub website_url: Option<String>,
    /// `YouTube` channel URL.
    pub youtube_url: Option<String>,
}

#[allow(dead_code)]
impl Group {
    /// Build a display-friendly location string from available location data.
    pub(crate) fn location(&self, max_len: usize) -> Option<String> {
        let parts = LocationParts::new()
            .group_city(self.city.as_ref())
            .group_country_code(self.country_code.as_ref())
            .group_country_name(self.country_name.as_ref())
            .group_state(self.state.as_ref());

        build_location(&parts, max_len)
    }

    /// Try to create a `Group` instance from a JSON string.
    #[instrument(skip_all, err)]
    pub(crate) fn try_from_json(data: &str) -> Result<Self> {
        let mut group: Group = serde_json::from_str(data)?;
        group.color = color(&group.name).to_string();
        Ok(group)
    }
}

/// User information for group organizers and members.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct User {
    /// Unique identifier for the user.
    #[serde(rename = "user_id")]
    pub id: Uuid,

    /// User's first name.
    pub first_name: Option<String>,
    /// User's last name.
    pub last_name: Option<String>,
    /// Company the user works for.
    pub company: Option<String>,
    /// User's job title.
    pub title: Option<String>,
    /// URL to the user's profile photo.
    pub photo_url: Option<String>,
    /// Facebook profile URL.
    pub facebook_url: Option<String>,
    /// `LinkedIn` profile URL.
    pub linkedin_url: Option<String>,
    /// Twitter profile URL.
    pub twitter_url: Option<String>,
    /// Personal website URL.
    pub website_url: Option<String>,
}
