//! Templates and types for managing the group team in the dashboard.

use askama::Template;
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    templates::{
        dashboard,
        helpers::user_initials,
        pagination::{self, Pagination, ToRawQuery},
    },
    types::group::{GroupRole, GroupRoleSummary},
    validation::MAX_PAGINATION_LIMIT,
};

// Pages templates.

/// List team members page template for a group.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/team_list.html")]
pub(crate) struct ListPage {
    /// Number of members with approved status.
    pub approved_members_count: usize,
    /// List of team members in the group.
    pub members: Vec<GroupTeamMember>,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// List of available team roles.
    pub roles: Vec<GroupRoleSummary>,
    /// Total number of team members.
    pub total: usize,
}

// Types.

/// Filter parameters for group team pagination.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct GroupTeamFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
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

/// Paginated group team response data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupTeamOutput {
    /// Total number of approved members.
    pub approved_total: usize,
    /// List of team members in the group.
    pub members: Vec<GroupTeamMember>,
    /// Total number of team members.
    pub total: usize,
}
