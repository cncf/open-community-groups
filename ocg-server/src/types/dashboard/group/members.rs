//! Group dashboard member types.

use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;

use crate::{
    types::{
        dashboard,
        pagination::{Pagination, ToRawQuery},
    },
    validation::MAX_PAGINATION_LIMIT,
};

/// Group member summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupMember {
    /// Membership creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Username.
    pub username: String,

    /// Company the user represents.
    pub company: Option<String>,
    /// Full name.
    pub name: Option<String>,
    /// URL to user's avatar.
    pub photo_url: Option<String>,
    /// Title held by the user.
    pub title: Option<String>,
}

/// Filter parameters for group members pagination.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct GroupMembersFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(min = 1, max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(GroupMembersFilters, limit, offset);

/// Paginated group members response data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupMembersOutput {
    /// List of members in the group.
    pub members: Vec<GroupMember>,
    /// Total number of members in the group.
    pub total: usize,
}
