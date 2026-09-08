//! Group dashboard sponsor types.

use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;

use crate::{
    types::{
        dashboard,
        group::GroupSponsor,
        pagination::{Pagination, ToRawQuery},
    },
    validation::{
        MAX_LEN_ENTITY_NAME, MAX_LEN_L, MAX_PAGINATION_LIMIT, image_url, trimmed_non_empty,
        web_url_opt,
    },
};

/// Filter parameters for group sponsors pagination.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct GroupSponsorsFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(min = 1, max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(GroupSponsorsFilters, limit, offset);

/// Paginated group sponsors response data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupSponsorsOutput {
    /// List of sponsors in the group.
    pub sponsors: Vec<GroupSponsor>,
    /// Total number of sponsors in the group.
    pub total: usize,
}

/// Sponsor input for create/update operations.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct SponsorInput {
    /// Whether the sponsor is highlighted on the public group page.
    #[serde(default)]
    #[garde(skip)]
    pub featured: bool,
    /// URL to sponsor logo.
    #[garde(custom(image_url))]
    pub logo_url: String,
    /// Sponsor name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_ENTITY_NAME))]
    pub name: String,

    /// Sponsor website URL.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub website_url: Option<String>,
}
