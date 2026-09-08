//! Templates for user groups.

use askama::Template;

use crate::types::dashboard::user::groups::UserGroup;
use crate::types::pagination;

// Pages templates.

/// List page for the user groups section.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/user/groups_list.html")]
pub(crate) struct ListPage {
    /// Groups where the user is a member or accepted team member.
    pub groups: Vec<UserGroup>,
    /// Pagination links for the groups list.
    pub navigation_links: pagination::NavigationLinks,
    /// Total number of groups before pagination.
    pub total: usize,

    /// Pagination offset for results.
    pub offset: Option<usize>,
}
