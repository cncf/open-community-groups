//! Templates for the global site stats page.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::{
    templates::{PageId, auth::User, filters, helpers::user_initials},
    types::site::SiteSettings,
};

/// Template for rendering the global site stats page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
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
    pub user: User,
}

/// Aggregated site statistics used across charts.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SiteStats {
    /// Attendees statistics.
    pub attendees: SiteStatsSection,
    /// Events statistics.
    pub events: SiteStatsSection,
    /// Groups statistics.
    pub groups: SiteStatsSection,
    /// Members statistics.
    pub members: SiteStatsSection,
}

/// Statistics for a single site section.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SiteStatsSection {
    /// Monthly counts.
    pub per_month: Vec<(String, i64)>,
    /// Running total of counts.
    pub running_total: Vec<(i64, i64)>,
    /// Total count.
    pub total: i64,
}
