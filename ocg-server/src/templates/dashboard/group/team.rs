//! Templates for managing the group team in the dashboard.

use askama::Template;

use crate::types::dashboard::group::team::GroupTeamMember;
use crate::{
    templates::helpers::user_initials,
    types::{group::GroupRoleSummary, pagination},
};

// Pages templates.

/// List team members page template for a group.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/team_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can award badges.
    pub can_award_badges: bool,
    /// Whether the current user can update team membership and roles.
    pub can_manage_team: bool,
    /// Tooltip shown when the current user cannot update team membership.
    pub manage_team_disabled_message: Option<String>,
    /// List of team members in the group.
    pub members: Vec<GroupTeamMember>,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// List of available team roles.
    pub roles: Vec<GroupRoleSummary>,
    /// Total number of team members.
    pub total: usize,
    /// Number of accepted admins in the group team.
    pub total_admins_accepted: usize,

    /// Pagination offset for results.
    pub offset: Option<usize>,
}

impl ListPage {
    /// Returns the tooltip text for disabled group team management controls.
    pub(crate) fn manage_team_disabled_message(&self) -> &str {
        self.manage_team_disabled_message.as_deref().unwrap_or("")
    }
}
