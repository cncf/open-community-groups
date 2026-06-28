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
    /// Gamification and recognition stats.
    #[serde(default)]
    pub gamification: GroupGamificationStats,
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

/// Gamification stats for member recognition.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct GroupGamificationStats {
    /// Total points earned by group members.
    pub total_points: i64,
    /// Members with any contribution points.
    pub active_contributors: i64,
    /// Total badges awarded across leaderboard members.
    pub badges_awarded: i64,
    /// Ranked top contributors.
    #[serde(default)]
    pub leaderboard: Vec<GroupGamificationLeaderboardEntry>,
    /// Point rules shown to admins and leads.
    #[serde(default)]
    pub rules: Vec<GroupGamificationRule>,
    /// Future contribution sources that are not active yet.
    #[serde(default)]
    pub future_sources: Vec<String>,
}

/// One member in the gamification leaderboard.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct GroupGamificationLeaderboardEntry {
    /// Rank within this group.
    pub rank: i64,
    /// User identifier.
    pub user_id: String,
    /// Username.
    pub username: String,
    /// Full name.
    pub name: Option<String>,
    /// Avatar URL.
    pub photo_url: Option<String>,
    /// Total points.
    pub points: i64,
    /// Count of recent contribution signals.
    pub recent_activity_count: i64,
    /// Contribution source counts.
    #[serde(default)]
    pub contributions: GroupGamificationContributions,
    /// Badges earned by this member.
    #[serde(default)]
    pub badges: Vec<String>,
}

/// Contribution counts used to compute member points.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct GroupGamificationContributions {
    /// Group join contribution.
    pub joined: i64,
    /// Confirmed event attendances.
    pub attended_events: i64,
    /// Checked-in event attendances.
    pub checked_in_events: i64,
    /// Host, organizer, or speaker roles.
    pub event_roles: i64,
    /// Accepted group lead roles.
    pub leader_roles: i64,
    /// Mentorship requests received.
    pub mentorship_requests: i64,
    /// Future chat contributions.
    pub chats: i64,
    /// Future post contributions.
    pub posts: i64,
    /// Future poll contributions.
    pub polls: i64,
}

/// A visible point rule for member contributions.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct GroupGamificationRule {
    /// Stable source key.
    pub source: String,
    /// Display label.
    pub label: String,
    /// Points awarded for the source.
    pub points: i64,
    /// Whether the source is active today.
    pub active: bool,
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
