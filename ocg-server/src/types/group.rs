//! Group type definitions.

use std::collections::BTreeMap;

use anyhow::Result;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use tracing::instrument;

use crate::templates::{
    common::User,
    helpers::{LocationParts, build_location, color},
};

/// Summary group information.
///
/// Contains essential group information in a compact format.
/// Typically used for listing groups in home pages or search results.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupSummary {
    /// Name of the category this group belongs to.
    pub category_name: String,
    /// Color associated with this group, used for visual styling.
    #[serde(default)]
    pub color: String,
    /// UTC timestamp when the group was created.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Display name of the group.
    pub name: String,
    /// URL-friendly identifier for this group.
    pub slug: String,

    /// City where the group is located.
    pub city: Option<String>,
    /// ISO country code of the group's location.
    pub country_code: Option<String>,
    /// Full country name of the group's location.
    pub country_name: Option<String>,
    /// URL to the group's logo image.
    pub logo_url: Option<String>,
    /// Geographic region name where the group is located.
    pub region_name: Option<String>,
    /// State or province where the group is located.
    pub state: Option<String>,
}

impl GroupSummary {
    /// Builds a formatted location string for the group.
    pub fn location(&self, max_len: usize) -> Option<String> {
        let parts = LocationParts::new()
            .group_city(self.city.as_ref())
            .group_country_code(self.country_code.as_ref())
            .group_country_name(self.country_name.as_ref())
            .group_state(self.state.as_ref());

        build_location(&parts, max_len)
    }

    /// Try to create a vector of `GroupSummary` instances from a JSON string.
    #[instrument(skip_all, err)]
    pub fn try_from_json_array(data: &str) -> Result<Vec<Self>> {
        let mut groups: Vec<Self> = serde_json::from_str(data)?;

        for group in &mut groups {
            group.color = color(&group.name).to_string();
        }

        Ok(groups)
    }
}

/// Detailed group information.
///
/// Contains comprehensive group data including location details
/// and additional metadata. Used in explore pages and search results.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupDetailed {
    /// Category this group belongs to.
    pub category_name: String,
    /// Generated color for visual distinction.
    #[serde(default)]
    pub color: String,
    /// When the group was created.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Group name.
    pub name: String,
    /// URL slug of the group.
    pub slug: String,

    /// City where the group is based.
    pub city: Option<String>,
    /// ISO country code of the group.
    pub country_code: Option<String>,
    /// Full country name of the group.
    pub country_name: Option<String>,
    /// Group description text.
    pub description: Option<String>,
    /// Latitude for map display.
    pub latitude: Option<f64>,
    /// URL to the group logo.
    pub logo_url: Option<String>,
    /// Longitude for map display.
    pub longitude: Option<f64>,
    /// Pre-rendered HTML for map popovers.
    pub popover_html: Option<String>,
    /// Name of the geographic region.
    pub region_name: Option<String>,
    /// State/province where the group is based.
    pub state: Option<String>,
}

impl GroupDetailed {
    /// Build a display-friendly location string from available location data.
    pub fn location(&self, max_len: usize) -> Option<String> {
        let parts = LocationParts::new()
            .group_city(self.city.as_ref())
            .group_country_code(self.country_code.as_ref())
            .group_country_name(self.country_name.as_ref())
            .group_state(self.state.as_ref());

        build_location(&parts, max_len)
    }

    /// Try to create a vector of `GroupDetailed` instances from a JSON string.
    #[instrument(skip_all, err)]
    pub fn try_from_json_array(data: &str) -> Result<Vec<Self>> {
        let mut groups: Vec<Self> = serde_json::from_str(data)?;

        for group in &mut groups {
            group.color = color(&group.name).to_string();
        }

        Ok(groups)
    }
}

impl From<GroupDetailed> for GroupSummary {
    fn from(detailed: GroupDetailed) -> Self {
        Self {
            category_name: detailed.category_name,
            color: detailed.color,
            created_at: detailed.created_at,
            name: detailed.name,
            slug: detailed.slug,
            city: detailed.city,
            country_code: detailed.country_code,
            country_name: detailed.country_name,
            logo_url: detailed.logo_url,
            region_name: detailed.region_name,
            state: detailed.state,
        }
    }
}

/// Full group information.
///
/// Contains complete group details including all metadata,
/// social links, organizers, and statistics.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupFull {
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

impl GroupFull {
    /// Build a display-friendly location string from available location data.
    #[allow(dead_code)]
    pub fn location(&self, max_len: usize) -> Option<String> {
        let parts = LocationParts::new()
            .group_city(self.city.as_ref())
            .group_country_code(self.country_code.as_ref())
            .group_country_name(self.country_name.as_ref())
            .group_state(self.state.as_ref());

        build_location(&parts, max_len)
    }

    /// Try to create a `GroupFull` instance from a JSON string.
    #[instrument(skip_all, err)]
    pub fn try_from_json(data: &str) -> Result<Self> {
        let mut group: GroupFull = serde_json::from_str(data)?;
        group.color = color(&group.name).to_string();
        Ok(group)
    }
}
