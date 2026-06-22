//! Templates for the alliance landscape dashboard.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::types::{
    landscape::{DashboardLandscapeFilters, LandscapeEntry},
    pagination::NavigationLinks,
};

/// Alliance landscape list page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/alliance/landscape.html")]
pub(crate) struct ListPage {
    /// Whether the current user can manage landscape entries.
    pub can_manage_landscape: bool,
    /// Pagination and search filters.
    pub filters: DashboardLandscapeFilters,
    /// Landscape entries in the selected alliance.
    pub entries: Vec<LandscapeEntry>,
    /// Total entries.
    pub total: usize,
    /// Pagination links.
    pub navigation_links: NavigationLinks,
}
