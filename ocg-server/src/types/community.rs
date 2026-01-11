//! Community-related types used across the application.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

// Community types.

/// Community information used in some community pages.
#[allow(clippy::struct_field_names)]
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Community {
    /// Whether the community is active.
    pub active: bool,
    /// Unique identifier for the community.
    pub community_id: Uuid,
    /// Layout identifier for the community site.
    pub community_site_layout_id: String,
    /// Creation timestamp in milliseconds since epoch.
    pub created_at: i64,
    /// Brief description of the community's purpose or focus.
    pub description: String,
    /// Human-readable name shown in the UI (e.g., "CNCF").
    pub display_name: String,
    /// URL to the logo image shown in the page header.
    pub logo_url: String,
    /// Unique identifier used in URLs and database references.
    pub name: String,

    /// Target URL when users click on the advertisement banner.
    pub ad_banner_link_url: Option<String>,
    /// URL to the advertisement banner image.
    pub ad_banner_url: Option<String>,
    /// URL to the community banner image.
    pub banner_url: Option<String>,
    /// Additional custom links displayed in the community navigation.
    pub extra_links: Option<BTreeMap<String, String>>,
    /// Link to the community's Facebook page.
    pub facebook_url: Option<String>,
    /// Link to the community's Flickr photo collection.
    pub flickr_url: Option<String>,
    /// Link to the community's GitHub organization or repository.
    pub github_url: Option<String>,
    /// Link to the community's Instagram profile.
    pub instagram_url: Option<String>,
    /// Link to the community's `LinkedIn` page.
    pub linkedin_url: Option<String>,
    /// Instructions for creating new groups.
    pub new_group_details: Option<String>,
    /// URL to the Open Graph image used for link previews.
    pub og_image_url: Option<String>,
    /// Collection of photo URLs for community galleries or slideshows.
    pub photos_urls: Option<Vec<String>>,
    /// Link to the community's Slack workspace.
    pub slack_url: Option<String>,
    /// Link to the community's Twitter/X profile.
    pub twitter_url: Option<String>,
    /// Link to the community's main website.
    pub website_url: Option<String>,
    /// Link to the community's `WeChat` account or QR code.
    pub wechat_url: Option<String>,
    /// Link to the community's `YouTube` channel.
    pub youtube_url: Option<String>,
}

/// Summary of a community used for listing communities.
#[allow(dead_code)]
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CommunitySummary {
    /// Unique identifier for the community.
    pub community_id: Uuid,
    /// Human-readable name shown in the UI (e.g., "CNCF").
    pub display_name: String,
    /// URL to the logo image.
    pub logo_url: String,
    /// Unique identifier used in URLs and database references.
    pub name: String,
}

/// Summary community information for dashboard selectors.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct UserCommunitySummary {
    /// Unique identifier for the community.
    pub community_id: Uuid,
    /// Community name used in URLs and database references.
    pub community_name: String,
    /// Human-readable name shown in the UI.
    pub display_name: String,
}
