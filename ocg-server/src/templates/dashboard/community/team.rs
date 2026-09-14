//! Templates for managing the community team in the dashboard.

use askama::Template;

use crate::types::dashboard::community::team::CommunityTeamMember;
use crate::{
    templates::helpers::user_initials,
    types::{community::CommunityRoleSummary, pagination},
};

// Pages templates.

/// List team members page template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/community/team_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can update team membership and roles.
    pub can_manage_team: bool,
    /// List of team members in the community.
    pub members: Vec<CommunityTeamMember>,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// List of available team roles.
    pub roles: Vec<CommunityRoleSummary>,
    /// Total number of team members.
    pub total: usize,
    /// Number of accepted admins in the community team.
    pub total_admins_accepted: usize,

    /// Pagination offset for results.
    pub offset: Option<usize>,
}
