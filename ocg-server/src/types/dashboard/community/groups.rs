//! Community dashboard group types.

use std::collections::BTreeMap;

use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    types::{
        dashboard,
        pagination::{Pagination, ToRawQuery},
        payments::{GroupPaymentRecipient, PaymentConfigurationValidation},
    },
    validation::{
        MAX_LEN_COUNTRY_CODE, MAX_LEN_DESCRIPTION, MAX_LEN_ENTITY_NAME, MAX_LEN_L, MAX_LEN_M,
        MAX_LEN_S, MAX_PAGINATION_LIMIT, image_url_opt, image_url_vec, trimmed_non_empty,
        trimmed_non_empty_opt, trimmed_non_empty_tag_vec, url_map_values, valid_group_pretty_slug,
        valid_latitude, valid_longitude, valid_payment_recipient, web_url_opt,
    },
};

/// Filter parameters for community groups pagination.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct CommunityGroupsFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(min = 1, max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
    /// Text search query.
    #[serde(default, deserialize_with = "crate::validation::blank_string_as_none")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub ts_query: Option<String>,
}

crate::impl_pagination_and_raw_query!(CommunityGroupsFilters, limit, offset);

/// Group details for dashboard management.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct GroupInput {
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
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
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
    /// Whether the group collects paid tickets outside the platform.
    #[serde(default)]
    #[garde(skip)]
    pub external_payments_enabled: Option<bool>,
    /// Facebook profile URL.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub facebook_url: Option<String>,
    /// Flickr profile URL.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub flickr_url: Option<String>,
    /// GitHub organization URL.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub github_url: Option<String>,
    /// Instagram profile URL.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub instagram_url: Option<String>,
    /// Latitude coordinate of the group location.
    #[garde(custom(valid_latitude))]
    pub latitude: Option<f64>,
    /// `LinkedIn` profile URL.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub linkedin_url: Option<String>,
    /// Longitude coordinate of the group location.
    #[garde(custom(valid_longitude))]
    pub longitude: Option<f64>,
    /// URL to the group logo.
    #[garde(custom(image_url_opt))]
    pub logo_url: Option<String>,
    /// URL to the group's Open Graph image.
    #[garde(custom(image_url_opt))]
    pub og_image_url: Option<String>,
    /// Optional parent group.
    #[garde(skip)]
    pub parent_group_id: Option<Uuid>,
    /// Whether the parent group field was submitted.
    #[garde(skip)]
    pub parent_group_id_present: Option<bool>,
    /// Payments recipient configuration for the group.
    #[garde(custom(valid_payment_recipient))]
    pub payment_recipient: Option<GroupPaymentRecipient>,
    /// Provider validation bound to the payment state used by this update.
    #[serde(default, rename = "_payment_validation", skip_deserializing)]
    #[garde(skip)]
    pub payment_validation: Option<PaymentConfigurationValidation>,
    /// Gallery of photo URLs.
    #[garde(custom(image_url_vec))]
    pub photos_urls: Option<Vec<String>>,
    /// Region this group belongs to.
    #[garde(skip)]
    pub region_id: Option<Uuid>,
    /// Slack workspace URL.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub slack_url: Option<String>,
    /// Admin-managed URL-friendly identifier for this group.
    #[garde(custom(valid_group_pretty_slug))]
    pub slug_pretty: Option<String>,
    /// State/province where the group is located.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub state: Option<String>,
    /// Tags associated with the group.
    #[garde(custom(trimmed_non_empty_tag_vec))]
    pub tags: Option<Vec<String>>,
    /// Twitter profile URL.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub twitter_url: Option<String>,
    /// Group website URL.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub website_url: Option<String>,
    /// `WeChat` URL.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub wechat_url: Option<String>,
    /// `YouTube` channel URL.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub youtube_url: Option<String>,
}
