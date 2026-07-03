//! Templates and data types for the analytics page in the alliance dashboard.

use std::collections::HashMap;

use crate::templates::filters;
use crate::types::alliance::AllianceFull;
use askama::Template;
use serde::{Deserialize, Serialize};

// Pages templates.

/// Analytics page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/alliance/analytics.html")]
pub(crate) struct Page {
    /// Current alliance.
    pub alliance: AllianceFull,
    /// Statistics to render.
    pub stats: AllianceDashboardStats,
}

// Types.

/// Aggregated alliance statistics used across charts.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AllianceDashboardStats {
    /// Attendees statistics.
    pub attendees: AttendeesStats,
    /// Events statistics.
    pub events: EventsStats,
    /// Groups statistics.
    pub groups: GroupsStats,
    /// Members statistics.
    pub members: MembersStats,
    /// Page views statistics.
    pub page_views: AlliancePageViewsStats,
    /// Reporting summaries and rankings.
    #[serde(default)]
    pub reports: AllianceReports,
}

/// Statistics for alliance dashboard page views.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AlliancePageViewsStats {
    /// Alliance page views statistics.
    pub alliance: PageViewsStats,
    /// Event page views statistics.
    pub events: PageViewsStats,
    /// Group page views statistics.
    pub groups: PageViewsStats,
    /// Total page views statistics.
    pub total: PageViewsStats,
    /// Total views across all tracked pages.
    pub total_views: i64,
}

/// Statistics for attendees across events.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AttendeesStats {
    /// Monthly attendee counts.
    pub per_month: Vec<(String, i64)>,
    /// Monthly attendee counts by event category.
    pub per_month_by_event_category: HashMap<String, Vec<(String, i64)>>,
    /// Monthly attendee counts by group category.
    pub per_month_by_group_category: HashMap<String, Vec<(String, i64)>>,
    /// Monthly attendee counts by group region.
    pub per_month_by_group_region: HashMap<String, Vec<(String, i64)>>,
    /// Running total of attendees.
    pub running_total: Vec<(i64, i64)>,
    /// Running total of attendees by event category.
    pub running_total_by_event_category: HashMap<String, Vec<(i64, i64)>>,
    /// Running total of attendees by group category.
    pub running_total_by_group_category: HashMap<String, Vec<(i64, i64)>>,
    /// Running total of attendees by group region.
    pub running_total_by_group_region: HashMap<String, Vec<(i64, i64)>>,
    /// Total attendees.
    pub total: i64,
    /// Total attendees by event category.
    pub total_by_event_category: Vec<(String, i64)>,
    /// Total attendees by group category.
    pub total_by_group_category: Vec<(String, i64)>,
    /// Total attendees by group region.
    pub total_by_group_region: Vec<(String, i64)>,
}

/// Statistics for events.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventsStats {
    /// Monthly event counts.
    pub per_month: Vec<(String, i64)>,
    /// Monthly event counts by event category.
    pub per_month_by_event_category: HashMap<String, Vec<(String, i64)>>,
    /// Monthly event counts by group category.
    pub per_month_by_group_category: HashMap<String, Vec<(String, i64)>>,
    /// Monthly event counts by group region.
    pub per_month_by_group_region: HashMap<String, Vec<(String, i64)>>,
    /// Running total of events.
    pub running_total: Vec<(i64, i64)>,
    /// Running total of events by event category.
    pub running_total_by_event_category: HashMap<String, Vec<(i64, i64)>>,
    /// Running total of events by group category.
    pub running_total_by_group_category: HashMap<String, Vec<(i64, i64)>>,
    /// Running total of events by group region.
    pub running_total_by_group_region: HashMap<String, Vec<(i64, i64)>>,
    /// Total events.
    pub total: i64,
    /// Total events by event category.
    pub total_by_event_category: Vec<(String, i64)>,
    /// Total events by group category.
    pub total_by_group_category: Vec<(String, i64)>,
    /// Total events by group region.
    pub total_by_group_region: Vec<(String, i64)>,
}

/// Statistics for groups.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupsStats {
    /// Monthly group counts.
    pub per_month: Vec<(String, i64)>,
    /// Monthly group counts by category.
    pub per_month_by_category: HashMap<String, Vec<(String, i64)>>,
    /// Monthly group counts by region.
    pub per_month_by_region: HashMap<String, Vec<(String, i64)>>,
    /// Running total of groups.
    pub running_total: Vec<(i64, i64)>,
    /// Running total of groups by category.
    pub running_total_by_category: HashMap<String, Vec<(i64, i64)>>,
    /// Running total of groups by region.
    pub running_total_by_region: HashMap<String, Vec<(i64, i64)>>,
    /// Total groups.
    pub total: i64,
    /// Total groups by category.
    pub total_by_category: Vec<(String, i64)>,
    /// Total groups by region.
    pub total_by_region: Vec<(String, i64)>,
}

/// Statistics for members.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct MembersStats {
    /// Monthly member counts.
    pub per_month: Vec<(String, i64)>,
    /// Monthly member counts by category.
    pub per_month_by_category: HashMap<String, Vec<(String, i64)>>,
    /// Monthly member counts by region.
    pub per_month_by_region: HashMap<String, Vec<(String, i64)>>,
    /// Running total of members.
    pub running_total: Vec<(i64, i64)>,
    /// Running total of members by category.
    pub running_total_by_category: HashMap<String, Vec<(i64, i64)>>,
    /// Running total of members by region.
    pub running_total_by_region: HashMap<String, Vec<(i64, i64)>>,
    /// Total members.
    pub total: i64,
    /// Total members by category.
    pub total_by_category: Vec<(String, i64)>,
    /// Total members by region.
    pub total_by_region: Vec<(String, i64)>,
}

/// Alliance reporting summaries for chapter programs, members, and events.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct AllianceReports {
    /// Chapter reporting.
    #[serde(default)]
    pub chapters: ChapterReports,
    /// Member reporting.
    #[serde(default)]
    pub members: MemberReports,
    /// Event reporting.
    #[serde(default)]
    pub events: EventReports,
}

/// Cross-chapter reporting.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct ChapterReports {
    /// Top chapter rankings.
    pub rankings: Vec<ChapterRanking>,
    /// Chapters with strong recent growth.
    pub rapid_growth: Vec<ChapterGrowthSignal>,
    /// Chapters that may need attention.
    pub needs_revitalization: Vec<ChapterRevitalizationSignal>,
    /// Recent member growth grouped by region.
    pub growth_by_region: Vec<(String, i64)>,
}

/// Ranked chapter metrics.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct ChapterRanking {
    /// Chapter name.
    pub name: String,
    /// Chapter slug.
    pub slug: String,
    /// Chapter category.
    pub category: String,
    /// Chapter region.
    pub region: String,
    /// Total members.
    pub members_total: i64,
    /// Members added in the latest 90-day window.
    pub members_recent: i64,
    /// Members added in the previous 90-day window.
    pub members_previous: i64,
    /// Total events.
    pub events_total: i64,
    /// Hosted events.
    pub hosted_events: i64,
    /// Upcoming events.
    pub upcoming_events: i64,
    /// Confirmed attendees.
    pub attendees_total: i64,
    /// Accepted leaders.
    pub leaders_total: i64,
}

/// Recent chapter growth signal.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct ChapterGrowthSignal {
    /// Chapter name.
    pub name: String,
    /// Chapter slug.
    pub slug: String,
    /// Chapter region.
    pub region: String,
    /// Total members.
    pub members_total: i64,
    /// Members added in the latest 90-day window.
    pub members_recent: i64,
    /// Growth delta against the previous 90 days.
    pub growth_delta: i64,
}

/// Chapter signal for revitalization.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct ChapterRevitalizationSignal {
    /// Chapter name.
    pub name: String,
    /// Chapter slug.
    pub slug: String,
    /// Chapter region.
    pub region: String,
    /// Total members.
    pub members_total: i64,
    /// Members added in the latest 90-day window.
    pub members_recent: i64,
    /// Upcoming events.
    pub upcoming_events: i64,
    /// Hosted events.
    pub hosted_events: i64,
}

/// Member reporting summaries.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct MemberReports {
    /// Members added in the latest 90-day window.
    pub recent_growth: i64,
    /// Members added in the previous 90-day window.
    pub previous_growth: i64,
    /// Member distribution by group region.
    pub by_region: Vec<(String, i64)>,
    /// Accepted chapter leaders.
    pub leaders_total: i64,
    /// Leaders added in the latest 90-day window.
    pub leaders_recent_growth: i64,
    /// Leaders added per month.
    pub leaders_per_month: Vec<(String, i64)>,
}

/// Event reporting summaries.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct EventReports {
    /// Events that have already started.
    pub hosted_total: i64,
    /// Future events.
    pub upcoming_total: i64,
    /// Event counts by group region.
    pub by_region: Vec<(String, i64)>,
    /// Event counts by venue city.
    pub by_city: Vec<(String, i64)>,
    /// Event counts by venue country.
    pub by_country: Vec<(String, i64)>,
    /// Event counts by kind.
    pub by_kind: Vec<(String, i64)>,
    /// Event counts by category.
    pub by_category: Vec<(String, i64)>,
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
