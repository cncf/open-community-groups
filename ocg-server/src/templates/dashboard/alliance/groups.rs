//! Templates and types for managing groups in the alliance dashboard.

use std::collections::BTreeMap;

use askama::Template;
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    templates::dashboard,
    types::{
        group::{GroupCategory, GroupFull, GroupRegion, GroupSummary},
        pagination::{self, Pagination, ToRawQuery},
        payments::GroupPaymentRecipient,
    },
    validation::{
        MAX_LEN_COUNTRY_CODE, MAX_LEN_DESCRIPTION, MAX_LEN_ENTITY_NAME, MAX_LEN_L, MAX_LEN_M,
        MAX_LEN_S, MAX_PAGINATION_LIMIT, image_url_opt, image_url_vec, trimmed_non_empty,
        trimmed_non_empty_opt, trimmed_non_empty_tag_vec, url_map_values, valid_group_pretty_slug,
        valid_latitude, valid_longitude,
    },
};

// Pages templates.

/// Add group page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/alliance/groups_add.html")]
pub(crate) struct AddPage {
    /// Whether the current user can manage groups.
    pub can_manage_groups: bool,
    /// List of available group categories.
    pub categories: Vec<GroupCategory>,
    /// List of available regions.
    pub regions: Vec<GroupRegion>,
}

/// List groups page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/alliance/groups_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can manage groups.
    pub can_manage_groups: bool,
    /// List of groups in the alliance.
    pub groups: Vec<GroupSummary>,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// Total number of groups in the alliance.
    pub total: usize,

    /// Number of results per page.
    pub limit: Option<usize>,
    /// Pagination offset for results.
    pub offset: Option<usize>,
    /// Text search query used to filter results.
    pub ts_query: Option<String>,
}

/// Update group page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/alliance/groups_update.html")]
pub(crate) struct UpdatePage {
    /// Whether the current user can manage groups.
    pub can_manage_groups: bool,
    /// List of available group categories.
    pub categories: Vec<GroupCategory>,
    /// Group details to update.
    pub group: GroupFull,
    /// List of available regions.
    pub regions: Vec<GroupRegion>,
}

// Types.

/// Filter parameters for alliance groups pagination.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct AllianceGroupsFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
    /// Text search query.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub ts_query: Option<String>,
}

crate::impl_pagination_and_raw_query!(AllianceGroupsFilters, limit, offset);

/// Group details for dashboard management.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct Group {
    /// Category this group belongs to.
    #[garde(skip)]
    pub category_id: Uuid,
    /// Group description.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DESCRIPTION))]
    pub description: String,
    /// Group name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_ENTITY_NAME))]
    pub name: String,

    /// URL to the group's banner image optimized for mobile devices.
    #[garde(custom(image_url_opt))]
    pub banner_mobile_url: Option<String>,
    /// Banner image URL.
    #[garde(custom(image_url_opt))]
    pub banner_url: Option<String>,
    /// Bluesky profile URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub bluesky_url: Option<String>,
    /// City where the group is located.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub city: Option<String>,
    /// ISO country code.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_COUNTRY_CODE))]
    pub country_code: Option<String>,
    /// Full country name.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub country_name: Option<String>,
    /// Additional links as key-value pairs.
    #[garde(custom(url_map_values))]
    pub extra_links: Option<BTreeMap<String, String>>,
    /// Facebook profile URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub facebook_url: Option<String>,
    /// Flickr profile URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub flickr_url: Option<String>,
    /// Google Photos album URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub google_photos_url: Option<String>,
    /// GitHub organization URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub github_url: Option<String>,
    /// Instagram profile URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub instagram_url: Option<String>,
    /// Latitude coordinate of the group location.
    #[garde(custom(valid_latitude))]
    pub latitude: Option<f64>,
    /// `LinkedIn` profile URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub linkedin_url: Option<String>,
    /// Longitude coordinate of the group location.
    #[garde(custom(valid_longitude))]
    pub longitude: Option<f64>,
    /// URL to the group logo.
    #[garde(custom(image_url_opt))]
    pub logo_url: Option<String>,
    /// Whether new members must be approved by group admins.
    #[serde(default)]
    #[garde(skip)]
    pub membership_approval_required: bool,
    /// URL to the group's Open Graph image.
    #[garde(custom(image_url_opt))]
    pub og_image_url: Option<String>,
    /// Payments recipient configuration for the group.
    #[garde(skip)]
    pub payment_recipient: Option<GroupPaymentRecipient>,
    /// Gallery of photo URLs.
    #[garde(custom(image_url_vec))]
    pub photos_urls: Option<Vec<String>>,
    /// Region this group belongs to.
    #[garde(skip)]
    pub region_id: Option<Uuid>,
    /// Slack workspace URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub slack_url: Option<String>,
    /// Admin-managed URL-friendly identifier for this group.
    #[garde(custom(valid_group_pretty_slug))]
    pub slug_pretty: Option<String>,
    /// State/province where the group is located.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub state: Option<String>,
    /// Substack publication URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub substack_url: Option<String>,
    /// Tags associated with the group.
    #[garde(custom(trimmed_non_empty_tag_vec))]
    pub tags: Option<Vec<String>>,
    /// Twitter profile URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub twitter_url: Option<String>,
    /// Group website URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub website_url: Option<String>,
    /// `WeChat` URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub wechat_url: Option<String>,
    /// `YouTube` channel URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub youtube_url: Option<String>,
}
