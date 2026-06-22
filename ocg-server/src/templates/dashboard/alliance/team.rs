//! Templates and types for managing the alliance team in the dashboard.

use askama::Template;
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    templates::{dashboard, helpers::user_initials},
    types::{
        alliance::{AllianceRole, AllianceRoleSummary},
        pagination::{self, Pagination, ToRawQuery},
    },
    validation::MAX_PAGINATION_LIMIT,
};

// Pages templates.

/// List team members page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/alliance/team_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can update team membership and roles.
    pub can_manage_team: bool,
    /// List of team members in the alliance.
    pub members: Vec<AllianceTeamMember>,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// List of available team roles.
    pub roles: Vec<AllianceRoleSummary>,
    /// Total number of team members.
    pub total: usize,
    /// Number of accepted members in the alliance team.
    pub total_accepted: usize,
    /// Number of accepted admins in the alliance team.
    pub total_admins_accepted: usize,

    /// Number of results per page.
    pub limit: Option<usize>,
    /// Pagination offset for results.
    pub offset: Option<usize>,
}

// Types.

/// Filter parameters for alliance team pagination.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct AllianceTeamFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(AllianceTeamFilters, limit, offset);

/// Alliance team member summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AllianceTeamMember {
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
    pub role: Option<AllianceRole>,
    /// Title held by the user.
    pub title: Option<String>,
}

/// Paginated alliance team response data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AllianceTeamOutput {
    /// List of team members in the alliance.
    pub members: Vec<AllianceTeamMember>,
    /// Total number of team members.
    pub total: usize,
    /// Total number of accepted members.
    pub total_accepted: usize,
    /// Total number of accepted admins.
    pub total_admins_accepted: usize,
}
