//! Templates for the global site stats page.

use askama::Template;

use crate::types::site::stats::SiteStats;
use crate::{
    templates::{PageId, auth::UserMenuState, filters, helpers::user_initials},
    types::site::SiteSettings,
};

/// Template for rendering the global site stats page.
#[derive(Debug, Clone, Template)]
#[template(path = "site/stats/page.html")]
pub struct Page {
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Site statistics for charts.
    pub stats: SiteStats,
    /// Authenticated user information.
    pub user: UserMenuState,
}
