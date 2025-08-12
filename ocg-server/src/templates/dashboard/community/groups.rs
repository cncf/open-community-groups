//! Templates and types for managing groups in the community dashboard.

use std::collections::BTreeMap;

use askama::Template;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::types::group::{GroupCategory, GroupFull, GroupRegion, GroupSummary};

// Pages templates.

/// Add group page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/community/groups_add.html")]
pub(crate) struct AddPage {
    /// List of available group categories.
    pub categories: Vec<GroupCategory>,
    /// List of available regions.
    pub regions: Vec<GroupRegion>,
}

/// List groups page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/community/groups_list.html")]
pub(crate) struct ListPage {
    /// List of groups in the community.
    pub groups: Vec<GroupSummary>,
}

/// Update group page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/community/groups_update.html")]
pub(crate) struct UpdatePage {
    /// Group details to update.
    pub group: GroupFull,
    /// List of available group categories.
    pub categories: Vec<GroupCategory>,
    /// List of available regions.
    pub regions: Vec<GroupRegion>,
}

// Types.

/// Group details for dashboard management.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Group {
    /// Group name.
    pub name: String,
    /// URL-friendly identifier.
    pub slug: String,
    /// Category this group belongs to.
    pub category_id: Uuid,
    /// Group description.
    pub description: String,

    /// Banner image URL.
    pub banner_url: Option<String>,
    /// City where the group is located.
    pub city: Option<String>,
    /// ISO country code.
    pub country_code: Option<String>,
    /// Full country name.
    pub country_name: Option<String>,
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
    /// `LinkedIn` profile URL.
    pub linkedin_url: Option<String>,
    /// URL to the group logo.
    pub logo_url: Option<String>,
    /// Gallery of photo URLs.
    pub photos_urls: Option<Vec<String>>,
    /// Region this group belongs to.
    pub region_id: Option<Uuid>,
    /// Slack workspace URL.
    pub slack_url: Option<String>,
    /// State/province where the group is located.
    pub state: Option<String>,
    /// Tags associated with the group.
    pub tags: Option<Vec<String>>,
    /// Twitter profile URL.
    pub twitter_url: Option<String>,
    /// Group website URL.
    pub website_url: Option<String>,
    /// `WeChat` URL.
    pub wechat_url: Option<String>,
    /// `YouTube` channel URL.
    pub youtube_url: Option<String>,
}
