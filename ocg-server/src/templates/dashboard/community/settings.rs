//! Templates for the community dashboard settings page.

use std::collections::BTreeMap;

use askama::Template;
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;

use crate::{
    types::community::CommunityFull,
    validation::{
        MAX_LEN_DESCRIPTION, MAX_LEN_DISPLAY_NAME, MAX_LEN_L, image_url, image_url_opt, image_url_vec,
        trimmed_non_empty, trimmed_non_empty_opt, url_map_values,
    },
};

// Pages templates.

/// Update page template for community settings.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/community/settings_update.html")]
pub(crate) struct UpdatePage {
    /// Community information.
    pub community: CommunityFull,
}

// Types.

/// Community update form data.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct CommunityUpdate {
    /// URL to the community banner image optimized for mobile devices.
    #[garde(custom(image_url))]
    pub banner_mobile_url: String,
    /// URL to the community banner image.
    #[garde(custom(image_url))]
    pub banner_url: String,
    /// Brief description of the community's purpose or focus.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DESCRIPTION))]
    pub description: String,
    /// Human-readable name shown in the UI (e.g., "CNCF").
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DISPLAY_NAME))]
    pub display_name: String,
    /// URL to the logo image.
    #[garde(custom(image_url))]
    pub logo_url: String,

    /// Target URL when users click on the advertisement banner.
    #[garde(url, length(max = MAX_LEN_L))]
    pub ad_banner_link_url: Option<String>,
    /// URL to the advertisement banner image.
    #[garde(custom(image_url_opt))]
    pub ad_banner_url: Option<String>,
    /// Additional custom links displayed in the community navigation.
    #[garde(custom(url_map_values))]
    pub extra_links: Option<BTreeMap<String, String>>,
    /// Link to the community's Facebook page.
    #[garde(url, length(max = MAX_LEN_L))]
    pub facebook_url: Option<String>,
    /// Link to the community's Flickr photo collection.
    #[garde(url, length(max = MAX_LEN_L))]
    pub flickr_url: Option<String>,
    /// Link to the community's GitHub organization or repository.
    #[garde(url, length(max = MAX_LEN_L))]
    pub github_url: Option<String>,
    /// Link to the community's Instagram profile.
    #[garde(url, length(max = MAX_LEN_L))]
    pub instagram_url: Option<String>,
    /// Link to the community's `LinkedIn` page.
    #[garde(url, length(max = MAX_LEN_L))]
    pub linkedin_url: Option<String>,
    /// Instructions for creating new groups.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION))]
    pub new_group_details: Option<String>,
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
