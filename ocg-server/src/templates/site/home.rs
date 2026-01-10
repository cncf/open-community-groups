//! Templates for the global site home page.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::{
    templates::{PageId, auth::User, filters, helpers::user_initials},
    types::{
        community::CommunitySummary,
        site::{SiteHomeStats, SiteSettings},
    },
};

/// Template for rendering the global site home page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "site/home/page.html")]
pub struct Page {
    /// List of communities to display.
    pub communities: Vec<CommunitySummary>,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Site statistics.
    pub stats: SiteHomeStats,
    /// Authenticated user information.
    pub user: User,
}
