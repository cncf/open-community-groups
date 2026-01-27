//! Templates and types for managing sponsors in the group dashboard.

use askama::Template;
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    templates::{
        dashboard::DASHBOARD_PAGINATION_LIMIT,
        pagination::{Pagination, ToRawQuery},
    },
    types::group::GroupSponsor,
    validation::{MAX_LEN_ENTITY_NAME, MAX_LEN_L, MAX_PAGINATION_LIMIT, image_url, trimmed_non_empty},
};

// Pages templates.

/// Add sponsor page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/sponsors_add.html")]
pub(crate) struct AddPage {
    /// Group identifier.
    pub group_id: Uuid,
}

/// List sponsors page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/sponsors_list.html")]
pub(crate) struct ListPage {
    /// List of sponsors in the group.
    pub sponsors: Vec<GroupSponsor>,
    /// Pagination navigation links.
    pub navigation_links: crate::templates::pagination::NavigationLinks,
    /// Total number of sponsors in the group.
    pub total: usize,
}

/// Update sponsor page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/sponsors_update.html")]
pub(crate) struct UpdatePage {
    /// Group identifier.
    pub group_id: Uuid,
    /// Sponsor information to update.
    pub sponsor: GroupSponsor,
}

// Types.

/// Sponsor input for create/update operations.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct Sponsor {
    /// URL to sponsor logo.
    #[garde(custom(image_url))]
    pub logo_url: String,
    /// Sponsor name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_ENTITY_NAME))]
    pub name: String,

    /// Sponsor website URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub website_url: Option<String>,
}

/// Filter parameters for group sponsors pagination.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct GroupSponsorsFilters {
    /// Number of results per page.
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[garde(skip)]
    pub offset: Option<usize>,
}

impl GroupSponsorsFilters {
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

crate::impl_pagination_and_raw_query!(GroupSponsorsFilters, limit, offset);

/// Paginated group sponsors response data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupSponsorsOutput {
    /// List of sponsors in the group.
    pub sponsors: Vec<GroupSponsor>,
    /// Total number of sponsors in the group.
    pub total: usize,
}
