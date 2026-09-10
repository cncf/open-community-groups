//! Templates for managing groups in the community dashboard.

use askama::Template;

use crate::types::{
    group::{GroupCategory, GroupFull, GroupParentOption, GroupRegion, GroupSummary},
    pagination,
};

// Pages templates.

/// Add group page template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/community/groups_add.html")]
pub(crate) struct AddPage {
    /// List of available group categories.
    pub categories: Vec<GroupCategory>,
    /// List of groups that can be selected as parents.
    pub parent_options: Vec<GroupParentOption>,
    /// List of available regions.
    pub regions: Vec<GroupRegion>,
}

/// List groups page template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/community/groups_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can manage groups.
    pub can_manage_groups: bool,
    /// List of groups in the community.
    pub groups: Vec<GroupSummary>,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// Total number of groups in the community.
    pub total: usize,

    /// Pagination offset for results.
    pub offset: Option<usize>,
    /// Text search query used to filter results.
    pub ts_query: Option<String>,
}

/// Update group page template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/community/groups_update.html")]
pub(crate) struct UpdatePage {
    /// Whether the current user can manage groups.
    pub can_manage_groups: bool,
    /// List of available group categories.
    pub categories: Vec<GroupCategory>,
    /// Group details to update.
    pub group: GroupFull,
    /// Whether this group has non-deleted child links.
    pub has_child_links: bool,
    /// List of groups that can be selected as parents.
    pub parent_options: Vec<GroupParentOption>,
    /// List of available regions.
    pub regions: Vec<GroupRegion>,
}
