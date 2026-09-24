//! Templates for listing co-hosted events in the group dashboard.

use askama::Template;

use crate::{
    templates::filters,
    types::{dashboard::group::cohosts::CohostedEvent, pagination},
};

// Pages templates.

/// Co-hosted events list page template for a group.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/cohosts_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can respond to co-hosting invitations.
    pub can_manage_cohosts: bool,
    /// Co-hosted events in the current page.
    pub events: Vec<CohostedEvent>,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// Partial URL used to refresh the current list.
    pub refresh_url: String,
    /// Total number of co-hosted events.
    pub total: usize,

    /// Pagination offset for results.
    pub offset: Option<usize>,
}
