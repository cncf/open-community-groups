//! Templates and types for managing groups in the community dashboard.

use std::collections::BTreeMap;

use askama::Template;
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    templates::pagination::{self, DASHBOARD_PAGINATION_LIMIT, Pagination, ToRawQuery},
    types::group::{GroupCategory, GroupFull, GroupRegion, GroupSummary},
    validation::{
        MAX_LEN_COUNTRY_CODE, MAX_LEN_DESCRIPTION, MAX_LEN_ENTITY_NAME, MAX_LEN_L, MAX_LEN_M, MAX_LEN_S,
        MAX_PAGINATION_LIMIT, image_url_opt, image_url_vec, trimmed_non_empty, trimmed_non_empty_opt,
        trimmed_non_empty_tag_vec, url_map_values, valid_latitude, valid_longitude,
    },
};

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
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// Total number of groups in the community.
    pub total: usize,

    /// Text search query used to filter results.
    pub ts_query: Option<String>,
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

/// Filter parameters for community groups pagination.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct CommunityGroupsFilters {
    /// Number of results per page.
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[garde(skip)]
    pub offset: Option<usize>,
    /// Text search query.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub ts_query: Option<String>,
}

impl CommunityGroupsFilters {
    /// Apply dashboard defaults to pagination filters.
    pub(crate) fn with_defaults(mut self) -> Self {
        if self.limit.is_none() {
            self.limit = Some(DASHBOARD_PAGINATION_LIMIT);
        }
        if self.offset.is_none() {
            self.offset = Some(0);
        }
        self
    }
}

crate::impl_pagination_and_raw_query!(CommunityGroupsFilters, limit, offset);

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
    /// Gallery of photo URLs.
    #[garde(custom(image_url_vec))]
    pub photos_urls: Option<Vec<String>>,
    /// Region this group belongs to.
    #[garde(skip)]
    pub region_id: Option<Uuid>,
    /// Slack workspace URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub slack_url: Option<String>,
    /// State/province where the group is located.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub state: Option<String>,
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
