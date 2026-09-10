//! Templates for managing sponsors in the group dashboard.

use askama::Template;

use crate::{
    templates::filters,
    types::{group::GroupSponsor, pagination},
};

// Pages templates.

/// Add sponsor page template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/sponsors_add.html")]
pub(crate) struct AddPage;

/// List sponsors page template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/sponsors_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can manage sponsors.
    pub can_manage_sponsors: bool,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// List of sponsors in the group.
    pub sponsors: Vec<GroupSponsor>,
    /// Total number of sponsors in the group.
    pub total: usize,

    /// Pagination offset for results.
    pub offset: Option<usize>,
}

/// Update sponsor page template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/sponsors_update.html")]
pub(crate) struct UpdatePage {
    /// Whether the current user can manage sponsors.
    pub can_manage_sponsors: bool,
    /// Sponsor information to update.
    pub sponsor: GroupSponsor,
}
