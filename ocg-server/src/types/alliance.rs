//! Alliance-related types used across the application.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

// Alliance types.

/// Full alliance information.
#[allow(clippy::struct_excessive_bools, clippy::struct_field_names)]
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AllianceFull {
    /// Whether the alliance is active.
    pub active: bool,
    /// URL to the alliance banner image optimized for mobile devices.
    pub banner_mobile_url: String,
    /// URL to the alliance banner image.
    pub banner_url: String,
    /// Unique identifier for the alliance.
    pub alliance_id: Uuid,
    /// Layout identifier for the alliance site.
    pub alliance_site_layout_id: String,
    /// Creation timestamp in milliseconds since epoch.
    pub created_at: i64,
    /// Whether group `CoffeeMeet` features are enabled across this alliance.
    #[serde(default = "default_true")]
    pub coffee_meet_enabled: bool,
    /// Brief description of the alliance's purpose or focus.
    pub description: String,
    /// Human-readable name shown in the UI (e.g., "Goup").
    pub display_name: String,
    /// Whether group team management is restricted to alliance roles.
    pub group_team_management_restricted: bool,
    /// Whether private intentional dating introductions are enabled across this alliance.
    #[serde(default)]
    pub intentional_dating_enabled: bool,
    /// URL to the logo image shown in the page header.
    pub logo_url: String,
    /// Whether mentorship requests are enabled across this alliance.
    #[serde(default = "default_true")]
    pub mentorship_enabled: bool,
    /// Whether mock interview requests are enabled across this alliance.
    #[serde(default = "default_true")]
    pub mock_interviews_enabled: bool,
    /// Unique identifier used in URLs and database references.
    pub name: String,

    /// Target URL when users click on the advertisement banner.
    pub ad_banner_link_url: Option<String>,
    /// URL to the advertisement banner image.
    pub ad_banner_url: Option<String>,
    /// Link to the alliance's Bluesky profile.
    pub bluesky_url: Option<String>,
    /// Additional custom links displayed in the alliance navigation.
    pub extra_links: Option<BTreeMap<String, String>>,
    /// Link to the alliance's Facebook page.
    pub facebook_url: Option<String>,
    /// Link to the alliance's Flickr photo collection.
    pub flickr_url: Option<String>,
    /// Link to the alliance's GitHub organization or repository.
    pub github_url: Option<String>,
    /// Link to the alliance's Instagram profile.
    pub instagram_url: Option<String>,
    /// Link to the alliance's `LinkedIn` page.
    pub linkedin_url: Option<String>,
    /// Instructions for creating new groups.
    pub new_group_details: Option<String>,
    /// URL to the Open Graph image used for link previews.
    pub og_image_url: Option<String>,
    /// Collection of photo URLs for alliance galleries or slideshows.
    pub photos_urls: Option<Vec<String>>,
    /// Link to the alliance's Slack workspace.
    pub slack_url: Option<String>,
    /// Link to the alliance's Twitter/X profile.
    pub twitter_url: Option<String>,
    /// Link to the alliance's main website.
    pub website_url: Option<String>,
    /// Whether the alliance report is visible on the public alliance page.
    #[serde(default)]
    pub report_public_enabled: bool,
    /// Link to the alliance's `WeChat` account or QR code.
    pub wechat_url: Option<String>,
    /// Link to the alliance's `YouTube` channel.
    pub youtube_url: Option<String>,
}

fn default_true() -> bool {
    true
}

/// Alliance team role enumeration.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, strum::Display)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum AllianceRole {
    Admin,
    GroupsManager,
    #[default]
    Viewer,
}

/// Alliance role summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AllianceRoleSummary {
    /// Role identifier.
    pub alliance_role_id: String,
    /// Display name.
    pub display_name: String,
}

/// Summary of a alliance used for listing alliances.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AllianceSummary {
    /// URL to the alliance banner image optimized for mobile devices.
    pub banner_mobile_url: String,
    /// URL to the alliance banner image.
    pub banner_url: String,
    /// Unique identifier for the alliance.
    pub alliance_id: Uuid,
    /// Human-readable name shown in the UI (e.g., "Goup").
    pub display_name: String,
    /// Whether group `CoffeeMeet` features are enabled across this alliance.
    #[serde(default = "default_true")]
    pub coffee_meet_enabled: bool,
    /// Whether private intentional dating introductions are enabled across this alliance.
    #[serde(default)]
    pub intentional_dating_enabled: bool,
    /// URL to the logo image.
    pub logo_url: String,
    /// Whether mentorship requests are enabled across this alliance.
    #[serde(default = "default_true")]
    pub mentorship_enabled: bool,
    /// Whether mock interview requests are enabled across this alliance.
    #[serde(default = "default_true")]
    pub mock_interviews_enabled: bool,
    /// Unique identifier used in URLs and database references.
    pub name: String,

    /// Target URL when users click on the advertisement banner.
    pub ad_banner_link_url: Option<String>,
    /// URL to the advertisement banner image.
    pub ad_banner_url: Option<String>,
    /// URL to the Open Graph image used for link previews.
    pub og_image_url: Option<String>,
}
