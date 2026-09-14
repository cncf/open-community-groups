//! Templates for the analytics page in the community dashboard.

use crate::templates::filters;
use crate::types::dashboard::community::analytics::CommunityDashboardStats;
use askama::Template;

// Pages templates.

/// Analytics page template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/community/analytics.html")]
pub(crate) struct Page {
    /// Statistics to render.
    pub stats: CommunityDashboardStats,
}
