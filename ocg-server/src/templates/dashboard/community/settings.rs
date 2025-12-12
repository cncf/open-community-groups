//! Templates for the community dashboard settings page.

use std::collections::BTreeMap;

use askama::Template;
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;

use crate::{
    types::community::Community,
    validation::{
        MAX_LEN_L, MAX_LEN_M, MAX_LEN_XL, hex_color, image_url, image_url_opt, image_url_vec,
        trimmed_non_empty, trimmed_non_empty_opt, url_map_values,
    },
};

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
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct CommunityUpdate {
    /// Brief description of the community's purpose or focus.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_XL))]
    pub description: String,
    /// Human-readable name shown in the UI (e.g., "CNCF").
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub display_name: String,
    /// URL to the logo image shown in the page header.
    #[garde(custom(image_url))]
    pub header_logo_url: String,
    /// Unique identifier used in URLs and database references.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub name: String,
    /// Primary color for the theme.
    #[garde(custom(hex_color))]
    pub primary_color: String,
    /// Title highlighted in the community site and other pages.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub title: String,

    /// Target URL when users click on the advertisement banner.
    #[garde(url, length(max = MAX_LEN_L))]
    pub ad_banner_link_url: Option<String>,
    /// URL to the advertisement banner image.
    #[garde(custom(image_url_opt))]
    pub ad_banner_url: Option<String>,
    /// Copyright text displayed in the footer.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_L))]
    pub copyright_notice: Option<String>,
    /// Additional custom links displayed in the community navigation.
    #[garde(custom(url_map_values))]
    pub extra_links: Option<BTreeMap<String, String>>,
    /// Link to the community's Facebook page.
    #[garde(url, length(max = MAX_LEN_L))]
    pub facebook_url: Option<String>,
    /// URL to the small icon displayed in browser tabs and bookmarks.
    #[garde(custom(image_url_opt))]
    pub favicon_url: Option<String>,
    /// Link to the community's Flickr photo collection.
    #[garde(url, length(max = MAX_LEN_L))]
    pub flickr_url: Option<String>,
    /// URL to the logo image shown in the page footer.
    #[garde(custom(image_url_opt))]
    pub footer_logo_url: Option<String>,
    /// Link to the community's GitHub organization or repository.
    #[garde(url, length(max = MAX_LEN_L))]
    pub github_url: Option<String>,
    /// Link to the community's Instagram profile.
    #[garde(url, length(max = MAX_LEN_L))]
    pub instagram_url: Option<String>,
    /// URL to the jumbotron background image for the community home page.
    #[garde(custom(image_url_opt))]
    pub jumbotron_image_url: Option<String>,
    /// Link to the community's `LinkedIn` page.
    #[garde(url, length(max = MAX_LEN_L))]
    pub linkedin_url: Option<String>,
    /// Instructions for creating new groups.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_XL))]
    pub new_group_details: Option<String>,
    /// URL to the Open Graph image used for link previews.
    #[garde(url, length(max = MAX_LEN_L))]
    pub og_image_url: Option<String>,
    /// Collection of photo URLs for community galleries or slideshows.
    #[garde(custom(image_url_vec))]
    pub photos_urls: Option<Vec<String>>,
    /// Link to the community's Slack workspace.
    #[garde(url, length(max = MAX_LEN_L))]
    pub slack_url: Option<String>,
    /// Link to the community's Twitter/X profile.
    #[garde(url, length(max = MAX_LEN_L))]
    pub twitter_url: Option<String>,
    /// Link to the community's main website.
    #[garde(url, length(max = MAX_LEN_L))]
    pub website_url: Option<String>,
    /// Link to the community's `WeChat` account or QR code.
    #[garde(url, length(max = MAX_LEN_L))]
    pub wechat_url: Option<String>,
    /// Link to the community's `YouTube` channel.
    #[garde(url, length(max = MAX_LEN_L))]
    pub youtube_url: Option<String>,
}
