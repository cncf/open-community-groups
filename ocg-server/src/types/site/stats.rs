//! Site statistics types.

use serde::{Deserialize, Serialize};

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
