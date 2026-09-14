//! User dashboard group types.

use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;

use crate::{
    types::{
        dashboard,
        group::GroupSummary,
        pagination::{Pagination, ToRawQuery},
    },
    validation::MAX_PAGINATION_LIMIT,
};

/// Summary of one user group relationship.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct UserGroup {
    /// Group summary data.
    pub group: GroupSummary,
    /// Whether the user has a removable group membership.
    pub is_member: bool,
    /// Whether the user has an accepted group team relationship.
    pub is_team_member: bool,
    /// Earliest date the user joined the group or its team.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub joined_at: DateTime<Utc>,
}

/// Filter parameters for groups pagination.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct UserGroupsFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(min = 1, max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(UserGroupsFilters, limit, offset);

/// Paginated groups response data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct UserGroupsOutput {
    /// Groups where the user is a member or accepted team member.
    pub groups: Vec<UserGroup>,
    /// Total number of groups before pagination.
    pub total: usize,
}
