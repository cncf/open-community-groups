//! Templates for the alliance dashboard settings page.

use std::collections::BTreeMap;

use askama::Template;
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;

use crate::{
    types::alliance::AllianceFull,
    validation::{
        MAX_LEN_DESCRIPTION, MAX_LEN_DISPLAY_NAME, MAX_LEN_L, image_url, image_url_opt,
        image_url_vec, trimmed_non_empty, trimmed_non_empty_opt, url_map_values,
    },
};

// Pages templates.

/// Update page template for alliance settings.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/alliance/settings_update.html")]
pub(crate) struct UpdatePage {
    /// Whether the current user can manage settings.
    pub can_manage_settings: bool,
    /// Alliance information.
    pub alliance: AllianceFull,
}

// Types.

/// Alliance update form data.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct AllianceUpdate {
    /// URL to the alliance banner image optimized for mobile devices.
    #[garde(custom(image_url))]
    pub banner_mobile_url: String,
    /// URL to the alliance banner image.
    #[garde(custom(image_url))]
    pub banner_url: String,
    /// Whether group `CoffeeMeet` features are enabled across this alliance.
    #[serde(default = "default_true")]
    #[garde(skip)]
    pub coffee_meet_enabled: bool,
    /// Brief description of the alliance's purpose or focus.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DESCRIPTION))]
    pub description: String,
    /// Human-readable name shown in the UI (e.g., "Goup").
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DISPLAY_NAME))]
    pub display_name: String,
    /// Whether group team management is restricted to alliance roles.
    #[garde(skip)]
    pub group_team_management_restricted: bool,
    /// URL to the logo image.
    #[garde(custom(image_url))]
    pub logo_url: String,
    /// Whether mentorship requests are enabled across this alliance.
    #[serde(default = "default_true")]
    #[garde(skip)]
    pub mentorship_enabled: bool,

    /// Target URL when users click on the advertisement banner.
    #[garde(url, length(max = MAX_LEN_L))]
    pub ad_banner_link_url: Option<String>,
    /// URL to the advertisement banner image.
    #[garde(custom(image_url_opt))]
    pub ad_banner_url: Option<String>,
    /// Link to the alliance's Bluesky profile.
    #[garde(url, length(max = MAX_LEN_L))]
    pub bluesky_url: Option<String>,
    /// Additional custom links displayed in the alliance navigation.
    #[garde(custom(url_map_values))]
    pub extra_links: Option<BTreeMap<String, String>>,
    /// Link to the alliance's Facebook page.
    #[garde(url, length(max = MAX_LEN_L))]
    pub facebook_url: Option<String>,
    /// Link to the alliance's Flickr photo collection.
    #[garde(url, length(max = MAX_LEN_L))]
    pub flickr_url: Option<String>,
    /// Link to the alliance's GitHub organization or repository.
    #[garde(url, length(max = MAX_LEN_L))]
    pub github_url: Option<String>,
    /// Link to the alliance's Instagram profile.
    #[garde(url, length(max = MAX_LEN_L))]
    pub instagram_url: Option<String>,
    /// Link to the alliance's `LinkedIn` page.
    #[garde(url, length(max = MAX_LEN_L))]
    pub linkedin_url: Option<String>,
    /// Instructions for creating new groups.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION))]
    pub new_group_details: Option<String>,
    /// URL to the alliance's Open Graph image.
    #[garde(custom(image_url_opt))]
    pub og_image_url: Option<String>,
    /// Collection of photo URLs for alliance galleries or slideshows.
    #[garde(custom(image_url_vec))]
    pub photos_urls: Option<Vec<String>>,
    /// Link to the alliance's Slack workspace.
    #[garde(url, length(max = MAX_LEN_L))]
    pub slack_url: Option<String>,
    /// Link to the alliance's Twitter/X profile.
    #[garde(url, length(max = MAX_LEN_L))]
    pub twitter_url: Option<String>,
    /// Link to the alliance's main website.
    #[garde(url, length(max = MAX_LEN_L))]
    pub website_url: Option<String>,
    /// Link to the alliance's `WeChat` account or QR code.
    #[garde(url, length(max = MAX_LEN_L))]
    pub wechat_url: Option<String>,
    /// Link to the alliance's `YouTube` channel.
    #[garde(url, length(max = MAX_LEN_L))]
    pub youtube_url: Option<String>,
}

fn default_true() -> bool {
    true
}
