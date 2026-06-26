//! Templates and types for listing alliance members in the dashboard.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::{
    templates::{alliance::AllianceMember, helpers::user_initials},
    types::pagination,
};

/// List members page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/alliance/members_list.html")]
pub(crate) struct ListPage {
    /// Members across all groups in the alliance.
    pub members: Vec<AllianceMember>,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// Total number of matching members.
    pub total: usize,

    /// Number of results per page.
    pub limit: Option<usize>,
    /// Pagination offset for results.
    pub offset: Option<usize>,
    /// Text search query.
    pub query: Option<String>,
}
