//! Analytics type definitions shared across dashboards.

use serde::{Deserialize, Serialize};

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
