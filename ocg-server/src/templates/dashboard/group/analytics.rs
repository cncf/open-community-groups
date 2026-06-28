//! Templates and data types for the analytics page in the group dashboard.

use crate::templates::filters;
use askama::Template;
use serde::{Deserialize, Serialize};

// Pages templates.

/// Analytics page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/analytics.html")]
pub(crate) struct Page {
    /// Statistics to render.
    pub stats: GroupDashboardStats,
}

// Types.

/// Aggregated group statistics used across charts.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupDashboardStats {
    /// Attendees statistics.
    pub attendees: GroupAttendeesStats,
    /// Events statistics.
    pub events: GroupEventsStats,
    /// Members statistics.
    pub members: GroupMembersStats,
    /// Page views statistics.
    pub page_views: GroupPageViewsStats,
    /// Reporting summaries.
    #[serde(default)]
    pub reports: GroupReports,
}

/// Statistics for attendees across a single group.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupAttendeesStats {
    /// Monthly attendee counts.
    pub per_month: Vec<(String, i64)>,
    /// Running total of attendees.
    pub running_total: Vec<(i64, i64)>,
    /// Total attendees.
    pub total: i64,
}

/// Statistics for events in a single group.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupEventsStats {
    /// Monthly event counts.
    pub per_month: Vec<(String, i64)>,
    /// Running total of events.
    pub running_total: Vec<(i64, i64)>,
    /// Total events.
    pub total: i64,
}

/// Statistics for members in a single group.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupMembersStats {
    /// Monthly member counts.
    pub per_month: Vec<(String, i64)>,
    /// Running total of members.
    pub running_total: Vec<(i64, i64)>,
    /// Total members.
    pub total: i64,
}

/// Group-scoped reporting summaries.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct GroupReports {
    /// Member reporting.
    #[serde(default)]
    pub members: GroupMemberReports,
    /// Event reporting.
    #[serde(default)]
    pub events: GroupEventReports,
}

/// Group member reporting summaries.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct GroupMemberReports {
    /// Members added in the latest 90-day window.
    pub recent_growth: i64,
    /// Members added in the previous 90-day window.
    pub previous_growth: i64,
    /// Accepted leaders.
    pub leaders_total: i64,
    /// Leaders added in the latest 90-day window.
    pub leaders_recent_growth: i64,
    /// Leaders added per month.
    pub leaders_per_month: Vec<(String, i64)>,
}

/// Group event reporting summaries.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct GroupEventReports {
    /// Events that have already started.
    pub hosted_total: i64,
    /// Future events.
    pub upcoming_total: i64,
    /// Event counts by venue city.
    pub by_city: Vec<(String, i64)>,
    /// Event counts by venue country.
    pub by_country: Vec<(String, i64)>,
    /// Event counts by kind.
    pub by_kind: Vec<(String, i64)>,
    /// Event counts by category.
    pub by_category: Vec<(String, i64)>,
}

/// Statistics for group dashboard page views.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupPageViewsStats {
    /// Event page views statistics.
    pub events: PageViewsStats,
    /// Group page views statistics.
    pub group: PageViewsStats,
    /// Total page views statistics.
    pub total: PageViewsStats,
    /// Total views across all tracked pages.
    pub total_views: i64,
}

/// Statistics for page views.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct PageViewsStats {
    /// Daily page views during the last month.
    pub per_day_views: Vec<(String, i64)>,
    /// Monthly page views.
    pub per_month_views: Vec<(String, i64)>,
    /// Total page views.
    pub total_views: i64,
}
