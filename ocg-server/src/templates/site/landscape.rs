//! Templates and types for the public landscape page.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::{
    templates::{auth::User, filters, helpers::user_initials, PageId},
    types::{
        landscape::{LandscapeEntry, LandscapeFilters},
        pagination::NavigationLinks,
        site::SiteSettings,
    },
};

/// Public landscape listing page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "site/landscape/page.html")]
pub(crate) struct Page {
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current URL path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,
    /// Search filters.
    pub filters: LandscapeFilters,
    /// Matching landscape entries.
    pub entries: Vec<LandscapeEntry>,
    /// Total matching entries.
    pub total: usize,
    /// Pagination links.
    pub navigation_links: NavigationLinks,
}
