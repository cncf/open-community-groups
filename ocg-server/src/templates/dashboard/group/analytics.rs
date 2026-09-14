//! Templates for the analytics page in the group dashboard.

use askama::Template;

use crate::templates::filters;
use crate::types::dashboard::group::analytics::GroupDashboardStats;

// Pages templates.

/// Analytics page template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/analytics.html")]
pub(crate) struct Page {
    /// Whether statistics include active subgroups.
    pub include_subgroups: bool,
    /// Whether the group has active subgroups.
    pub has_subgroups: bool,
    /// Statistics to render.
    pub stats: GroupDashboardStats,
}
