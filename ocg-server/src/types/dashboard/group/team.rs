//! Group dashboard team types.

use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    types::{
        dashboard,
        group::GroupRole,
        pagination::{Pagination, ToRawQuery},
    },
    validation::MAX_PAGINATION_LIMIT,
};

/// Filter parameters for group team pagination.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct GroupTeamFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(min = 1, max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(GroupTeamFilters, limit, offset);

/// Group team member summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupTeamMember {
    /// Whether the membership has been accepted.
    pub accepted: bool,
    /// Unique identifier for the user.
    pub user_id: Uuid,
    /// Username.
    pub username: String,

    /// Company the user represents.
    pub company: Option<String>,
    /// Full name.
    pub name: Option<String>,
    /// URL to user's avatar.
    pub photo_url: Option<String>,
    /// Team role.
    pub role: Option<GroupRole>,
    /// Title held by the user.
    pub title: Option<String>,
}

impl GroupTeamMember {
    /// Returns whether the member has the admin role.
    pub(crate) fn is_admin(&self) -> bool {
        matches!(self.role.as_ref(), Some(GroupRole::Admin))
    }
}

/// Paginated group team response data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupTeamOutput {
    /// List of team members in the group.
    pub members: Vec<GroupTeamMember>,
    /// Total number of team members.
    pub total: usize,
    /// Total number of accepted members.
    pub total_accepted: usize,
    /// Total number of accepted admins.
    pub total_admins_accepted: usize,
}
