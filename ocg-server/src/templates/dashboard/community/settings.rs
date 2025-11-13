//! Templates for the community dashboard settings page.

use std::collections::BTreeMap;

use askama::Template;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;

use crate::types::community::Community;

// Pages templates.

/// Update page template for community settings.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/community/settings_update.html")]
pub(crate) struct UpdatePage {
    /// Community information.
    pub community: Community,
}

// Types.

/// Community update form data.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct CommunityUpdate {
    /// Brief description of the community's purpose or focus.
    pub description: String,
    /// Human-readable name shown in the UI (e.g., "CNCF").
    pub display_name: String,
    /// URL to the logo image shown in the page header.
    pub header_logo_url: String,
    /// Unique identifier used in URLs and database references.
    pub name: String,
    /// Primary color for the theme.
    pub primary_color: String,
    /// Title highlighted in the community site and other pages.
    pub title: String,

    /// Target URL when users click on the advertisement banner.
    pub ad_banner_link_url: Option<String>,
    /// URL to the advertisement banner image.
    pub ad_banner_url: Option<String>,
    /// Copyright text displayed in the footer.
    pub copyright_notice: Option<String>,
    /// Additional custom links displayed in the community navigation.
    pub extra_links: Option<BTreeMap<String, String>>,
    /// Link to the community's Facebook page.
    pub facebook_url: Option<String>,
    /// URL to the small icon displayed in browser tabs and bookmarks.
    pub favicon_url: Option<String>,
    /// Link to the community's Flickr photo collection.
    pub flickr_url: Option<String>,
    /// URL to the logo image shown in the page footer.
    pub footer_logo_url: Option<String>,
    /// Link to the community's GitHub organization or repository.
    pub github_url: Option<String>,
    /// Link to the community's Instagram profile.
    pub instagram_url: Option<String>,
    /// URL to the jumbotron background image for the community home page.
    pub jumbotron_image_url: Option<String>,
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
