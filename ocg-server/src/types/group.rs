//! Group type definitions.

use std::collections::BTreeMap;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::types::{
    alliance::AllianceSummary,
    location::{LocationParts, build_location},
    payments::GroupPaymentRecipient,
    user::User,
};

// Group types: minimal, summary and full.

/// Minimal group information for dashboard selectors.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct GroupMinimal {
    /// Whether the group is active.
    pub active: bool,
    /// Unique identifier for the group.
    pub group_id: Uuid,
    /// Display name of the group.
    pub name: String,
    /// URL-friendly identifier for this group.
    pub slug: String,

    /// Admin-managed URL-friendly identifier for this group.
    pub slug_pretty: Option<String>,
}

impl GroupMinimal {
    /// Returns the slug to use in public URLs.
    pub fn public_slug(&self) -> &str {
        self.slug_pretty.as_deref().unwrap_or(&self.slug)
    }
}

/// Summary group information.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct GroupSummary {
    /// Whether the group is active.
    pub active: bool,
    /// Category this group belongs to.
    pub category: GroupCategory,
    /// Human-readable display name of the alliance this group belongs to.
    pub alliance_display_name: String,
    /// Name of the alliance this group belongs to (slug for URLs).
    pub alliance_name: String,
    /// UTC timestamp when the group was created.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Unique identifier for the group.
    pub group_id: Uuid,
    /// URL to the group's logo image.
    pub logo_url: String,
    /// Display name of the group.
    pub name: String,
    /// URL-friendly identifier for this group.
    pub slug: String,

    /// URL to the group's banner image optimized for mobile devices.
    pub banner_mobile_url: Option<String>,
    /// URL to the group's banner image.
    pub banner_url: Option<String>,
    /// City where the group is located.
    pub city: Option<String>,
    /// ISO country code of the group's location.
    pub country_code: Option<String>,
    /// Full country name of the group's location.
    pub country_name: Option<String>,
    /// Short group description text.
    pub description_short: Option<String>,
    /// Latitude for map display.
    pub latitude: Option<f64>,
    /// Longitude for map display.
    pub longitude: Option<f64>,
    /// URL to the group's Open Graph image used for link previews.
    pub og_image_url: Option<String>,
    /// Pre-rendered HTML for map popovers.
    pub popover_html: Option<String>,
    /// Geographic region this group belongs to.
    pub region: Option<GroupRegion>,
    /// Admin-managed URL-friendly identifier for this group.
    pub slug_pretty: Option<String>,
    /// State or province where the group is located.
    pub state: Option<String>,
}

impl GroupSummary {
    /// Builds a formatted location string for the group.
    pub fn location(&self, max_len: usize) -> Option<String> {
        let parts = LocationParts::new()
            .city(self.city.as_deref())
            .country_code(self.country_code.as_deref())
            .country_name(self.country_name.as_deref())
            .state(self.state.as_deref());

        build_location(&parts, max_len)
    }

    /// Returns the slug to use in public URLs.
    pub fn public_slug(&self) -> &str {
        self.slug_pretty.as_deref().unwrap_or(&self.slug)
    }
}

/// Full group information.
#[skip_serializing_none]
#[allow(clippy::struct_excessive_bools)]
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct GroupFull {
    /// Whether the group is active.
    pub active: bool,
    /// Category this group belongs to.
    pub category: GroupCategory,
    /// Alliance this group belongs to.
    pub alliance: AllianceSummary,
    /// When the group was created.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Unique identifier for the group.
    pub group_id: Uuid,
    /// URL to the group logo.
    pub logo_url: String,
    /// Total number of group members.
    pub members_count: i64,
    /// Whether new members must be approved by group admins.
    #[serde(default)]
    pub membership_approval_required: bool,
    /// Whether mentorship requests are enabled for this group.
    #[serde(default = "default_true")]
    pub mentorship_enabled: bool,
    /// Whether mock interview requests are enabled for this group.
    #[serde(default = "default_true")]
    pub mock_interviews_enabled: bool,
    /// Group name.
    pub name: String,
    /// List of group organizers.
    pub organizers: Vec<User>,
    /// URL slug of the group.
    pub slug: String,
    /// List of group sponsors.
    pub sponsors: Vec<GroupSponsor>,

    /// URL to the group's banner image optimized for mobile devices.
    pub banner_mobile_url: Option<String>,
    /// Banner image URL for the group page.
    pub banner_url: Option<String>,
    /// Bluesky profile URL.
    pub bluesky_url: Option<String>,
    /// City where the group is based.
    pub city: Option<String>,
    /// Whether `CoffeeMeet` is enabled for this group.
    #[serde(default = "default_true")]
    pub coffee_meet_enabled: bool,
    /// Whether private intentional dating introductions are enabled for this group.
    #[serde(default)]
    pub intentional_dating_enabled: bool,
    /// ISO country code of the group.
    pub country_code: Option<String>,
    /// Full country name of the group.
    pub country_name: Option<String>,
    /// Group description text.
    pub description: Option<String>,
    /// Short group description text.
    pub description_short: Option<String>,
    /// `Discord` invite or server URL.
    pub discord_url: Option<String>,
    /// Default payload applied when creating new events for this group.
    pub event_defaults: Option<Value>,
    /// Additional links as key-value pairs.
    pub extra_links: Option<BTreeMap<String, String>>,
    /// Facebook profile URL.
    pub facebook_url: Option<String>,
    /// Flickr profile URL.
    pub flickr_url: Option<String>,
    /// Google Photos album URL.
    pub google_photos_url: Option<String>,
    /// GitHub organization URL.
    pub github_url: Option<String>,
    /// Instagram profile URL.
    pub instagram_url: Option<String>,
    /// Latitude for map display.
    pub latitude: Option<f64>,
    /// `LinkedIn` profile URL.
    pub linkedin_url: Option<String>,
    /// Longitude for map display.
    pub longitude: Option<f64>,
    /// URL to the group's Open Graph image used for link previews.
    pub og_image_url: Option<String>,
    /// Payments recipient configuration for the group.
    pub payment_recipient: Option<GroupPaymentRecipient>,
    /// Gallery of photo URLs.
    pub photos_urls: Option<Vec<String>>,
    /// Geographic region this group belongs to.
    pub region: Option<GroupRegion>,
    /// Whether the group report is visible on the public group page.
    #[serde(default)]
    pub report_public_enabled: bool,
    /// Slack workspace URL.
    pub slack_url: Option<String>,
    /// Admin-managed URL slug of the group.
    pub slug_pretty: Option<String>,
    /// State/province where the group is based.
    pub state: Option<String>,
    /// `Substack` publication URL.
    pub substack_url: Option<String>,
    /// Tags associated with the group.
    pub tags: Option<Vec<String>>,
    /// Twitter profile URL.
    pub twitter_url: Option<String>,
    /// `WeChat` URL.
    pub wechat_url: Option<String>,
    /// Group website URL.
    pub website_url: Option<String>,
    /// `WhatsApp` community or chat URL.
    pub whatsapp_url: Option<String>,
    /// `YouTube` channel URL.
    pub youtube_url: Option<String>,
}

fn default_true() -> bool {
    true
}

impl GroupFull {
    /// Returns true when `CoffeeMeet` is available for this group and alliance.
    pub fn coffee_meet_available(&self) -> bool {
        self.coffee_meet_enabled && self.alliance.coffee_meet_enabled
    }

    /// Returns true when mentorship requests are available for this group and alliance.
    pub fn mentorship_available(&self) -> bool {
        self.mentorship_enabled && self.alliance.mentorship_enabled
    }

    /// Returns true when private intentional dating introductions are available.
    pub fn intentional_dating_available(&self) -> bool {
        self.intentional_dating_enabled && self.alliance.intentional_dating_enabled
    }

    /// Returns true when mock interview requests are available for this group and alliance.
    pub fn mock_interviews_available(&self) -> bool {
        self.mock_interviews_enabled && self.alliance.mock_interviews_enabled
    }

    /// Build a display-friendly location string from available location data.
    pub fn location(&self, max_len: usize) -> Option<String> {
        let parts = LocationParts::new()
            .city(self.city.as_deref())
            .country_code(self.country_code.as_deref())
            .country_name(self.country_name.as_deref())
            .state(self.state.as_deref());

        build_location(&parts, max_len)
    }

    /// Returns the slug to use in public URLs.
    pub fn public_slug(&self) -> &str {
        self.slug_pretty.as_deref().unwrap_or(&self.slug)
    }
}

// Other related types.

/// Public membership status for the current user.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct GroupMembershipStatus {
    /// Whether the current user is already a group member.
    pub is_member: bool,
    /// Whether group admins must approve new members.
    pub approval_required: bool,
    /// Whether the current user has a pending join request.
    pub has_pending_request: bool,
}

/// Result of attempting to join a group.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, strum::EnumString)]
#[serde(rename_all = "snake_case")]
#[strum(serialize_all = "snake_case")]
pub enum GroupJoinOutcome {
    /// The user was added as a member immediately.
    Joined,
    /// The user's request is pending admin approval.
    Pending,
}

/// Group category information.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct GroupCategory {
    /// Unique identifier for the category.
    pub group_category_id: Uuid,
    /// Display name of the category.
    pub name: String,
    /// URL-friendly normalized name.
    #[serde(rename = "slug", alias = "normalized_name")]
    pub normalized_name: String,

    /// Number of groups currently using this category.
    pub groups_count: Option<usize>,
    /// Sort order for display.
    pub order: Option<i32>,
}

/// Geographic region information.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct GroupRegion {
    /// Unique identifier for the region.
    pub region_id: Uuid,
    /// Display name of the region.
    pub name: String,
    /// URL-friendly normalized name.
    pub normalized_name: String,

    /// Number of groups currently using this region.
    pub groups_count: Option<usize>,
    /// Sort order for display.
    pub order: Option<i32>,
}

/// Group team role enumeration.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, strum::Display)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum GroupRole {
    Admin,
    EventsManager,
    #[default]
    Viewer,
}

/// Group role summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupRoleSummary {
    /// Display name.
    pub display_name: String,
    /// Role identifier.
    pub group_role_id: String,
}

/// Group sponsor with identifier (used for dashboard selection lists).
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupSponsor {
    /// Whether the sponsor is highlighted on the group page.
    #[serde(default)]
    pub featured: bool,
    /// Group sponsor identifier.
    pub group_sponsor_id: Uuid,
    /// URL to sponsor logo.
    pub logo_url: String,
    /// Sponsor name.
    pub name: String,

    /// Sponsor website URL.
    pub website_url: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::GroupFull;

    #[test]
    fn coffee_meet_available_requires_group_and_alliance_enabled() {
        let mut group = GroupFull {
            coffee_meet_enabled: true,
            ..Default::default()
        };
        group.alliance.coffee_meet_enabled = true;
        assert!(group.coffee_meet_available());

        group.coffee_meet_enabled = false;
        assert!(!group.coffee_meet_available());

        group.coffee_meet_enabled = true;
        group.alliance.coffee_meet_enabled = false;
        assert!(!group.coffee_meet_available());
    }

    #[test]
    fn mentorship_available_requires_group_and_alliance_enabled() {
        let mut group = GroupFull {
            mentorship_enabled: true,
            ..Default::default()
        };
        group.alliance.mentorship_enabled = true;
        assert!(group.mentorship_available());

        group.mentorship_enabled = false;
        assert!(!group.mentorship_available());

        group.mentorship_enabled = true;
        group.alliance.mentorship_enabled = false;
        assert!(!group.mentorship_available());
    }

    #[test]
    fn mock_interviews_available_requires_group_and_alliance_enabled() {
        let mut group = GroupFull {
            mock_interviews_enabled: true,
            ..Default::default()
        };
        group.alliance.mock_interviews_enabled = true;
        assert!(group.mock_interviews_available());

        group.mock_interviews_enabled = false;
        assert!(!group.mock_interviews_available());

        group.mock_interviews_enabled = true;
        group.alliance.mock_interviews_enabled = false;
        assert!(!group.mock_interviews_available());
    }

    #[test]
    fn intentional_dating_available_requires_group_and_alliance_enabled() {
        let mut group = GroupFull {
            intentional_dating_enabled: true,
            ..Default::default()
        };
        group.alliance.intentional_dating_enabled = true;
        assert!(group.intentional_dating_available());

        group.intentional_dating_enabled = false;
        assert!(!group.intentional_dating_available());

        group.intentional_dating_enabled = true;
        group.alliance.intentional_dating_enabled = false;
        assert!(!group.intentional_dating_available());
    }
}
