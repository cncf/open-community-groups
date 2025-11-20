//! Templates and data types for the analytics page in the community dashboard.

use std::collections::HashMap;

use crate::templates::filters;
use askama::Template;
use serde::{Deserialize, Serialize};

// Pages templates.

/// Analytics page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/community/analytics.html")]
pub(crate) struct Page {
    /// Statistics to render.
    pub stats: CommunityStats,
}

// Types.

/// Aggregated community statistics used across charts.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct CommunityStats {
    /// Attendees statistics.
    pub attendees: AttendeesStats,
    /// Events statistics.
    pub events: EventsStats,
    /// Groups statistics.
    pub groups: GroupsStats,
    /// Members statistics.
    pub members: MembersStats,
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
