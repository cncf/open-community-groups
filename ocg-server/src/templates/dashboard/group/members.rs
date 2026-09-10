//! Templates for listing group members in the dashboard.

use askama::Template;

use crate::types::dashboard::group::members::GroupMember;
use crate::{templates::helpers::user_initials, types::pagination};

// Pages templates.

/// List members page template for a group.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/members_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can manage members.
    pub can_manage_members: bool,
    /// Default notification subject.
    pub default_notification_subject: String,
    /// List of members in the group.
    pub members: Vec<GroupMember>,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// Total number of members in the group.
    pub total: usize,

    /// Pagination offset for results.
    pub offset: Option<usize>,
}
