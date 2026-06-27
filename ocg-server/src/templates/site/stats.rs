//! Templates for the global site stats page.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::{
    db::BBox,
    templates::site::explore::GroupCard,
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
    /// Groups shown on the embedded ecosystem map.
    pub group_map_groups: Vec<GroupCard>,
    /// Geographic bounds for all groups on the embedded ecosystem map.
    pub group_map_bbox: Option<BBox>,
    /// Authenticated user information.
    pub user: User,
}

/// Aggregated site statistics used across charts.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SiteStats {
    /// High-level summary metrics.
    pub summary: SiteStatsSummary,
    /// Engagement and quality metrics.
    pub engagement: SiteEngagementStats,
    /// Event breakdown metrics.
    pub event_breakdown: SiteEventBreakdown,
    /// Jobs overview metrics.
    pub jobs_overview: SiteJobsOverview,
    /// Mentorship request overview metrics.
    pub mentorship_overview: SiteMentorshipOverview,
    /// Landscape overview metrics.
    pub landscape_overview: SiteLandscapeOverview,
    /// Attendees statistics.
    pub attendees: SiteStatsSection,
    /// Events statistics.
    pub events: SiteStatsSection,
    /// Groups statistics.
    pub groups: SiteStatsSection,
    /// Members statistics.
    pub members: SiteStatsSection,
    /// Jobs statistics.
    pub jobs: SiteStatsSection,
    /// Startup landscape statistics.
    pub landscape_startups: SiteStatsSection,
    /// Open-source landscape statistics.
    pub landscape_open_source: SiteStatsSection,
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

/// High-level summary metrics for the public stats page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SiteStatsSummary {
    /// Members active in the last 90 days.
    pub active_members: i64,
    /// Published future events.
    pub upcoming_events: i64,
    /// Published jobs that have not expired.
    pub active_jobs: i64,
    /// Saved-interest job applications.
    pub job_interests: i64,
    /// Published landscape entries.
    pub landscape_entries: i64,
    /// Average confirmed attendees per published event.
    pub avg_attendees_per_event: f64,
}

/// Engagement and quality metrics for the public stats page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SiteEngagementStats {
    /// Confirmed attendees who joined two or more events.
    pub repeat_attendees: i64,
    /// Members with `LinkedIn` identity or profile data.
    pub linkedin_connected_members: i64,
    /// Average members per active group.
    pub members_per_group_avg: f64,
    /// Average published events per active group.
    pub events_per_group_avg: f64,
}

/// Event breakdown metrics for the public stats page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SiteEventBreakdown {
    /// Published events by event kind.
    pub by_kind: Vec<(String, i64)>,
    /// Published events by event category.
    pub by_category: Vec<(String, i64)>,
}

/// Jobs overview metrics for the public stats page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SiteJobsOverview {
    /// Active jobs that have not expired.
    pub active: i64,
    /// Published jobs that are expired.
    pub expired: i64,
    /// Saved-interest job applications.
    pub interests: i64,
    /// Average saved-interest applications per job.
    pub avg_interests_per_job: f64,
}

/// Mentorship request metrics for the public stats page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SiteMentorshipOverview {
    /// Total mentorship requests submitted.
    pub requests: i64,
    /// Average mentorship requests per active group.
    pub requests_per_group_avg: f64,
    /// Mentorship requests grouped by active group membership of the mentor.
    pub by_group: Vec<(String, i64)>,
}

/// Landscape overview metrics for the public stats page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SiteLandscapeOverview {
    /// Published landscape entries.
    pub entries: i64,
    /// Published landscape entries by category.
    pub by_category: Vec<(String, i64)>,
}
