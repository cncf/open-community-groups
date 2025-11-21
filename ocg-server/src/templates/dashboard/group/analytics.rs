//! Templates and data types for the analytics page in the group dashboard.

use askama::Template;
use serde::{Deserialize, Serialize};

// Pages templates.

/// Analytics page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/analytics.html")]
pub(crate) struct Page {
    /// Statistics to render.
    pub stats: GroupStats,
}

// Types.

/// Aggregated group statistics used across charts.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupStats {
    /// Attendees statistics.
    pub attendees: GroupAttendeesStats,
    /// Events statistics.
    pub events: GroupEventsStats,
    /// Members statistics.
    pub members: GroupMembersStats,
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
