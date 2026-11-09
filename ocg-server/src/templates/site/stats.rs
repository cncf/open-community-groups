//! Templates for the global site stats page.

use askama::Template;
use chrono::{DateTime, NaiveDate};

use crate::types::site::stats::{SiteStats, SiteStatsSection};
use crate::{
    templates::{
        PageId,
        auth::UserMenuState,
        filters,
        helpers::{count_label, user_initials},
    },
    types::site::SiteSettings,
};

#[cfg(test)]
mod tests;

/// Format used for month names in chart summaries.
const SUMMARY_MONTH_FORMAT: &str = "%B %Y";

// Pages templates.

/// Template for rendering the global site stats page.
#[derive(Debug, Clone, Template)]
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
    /// Authenticated user information.
    pub user: UserMenuState,
}

impl Page {
    /// Returns the stats sections in display order.
    pub(crate) fn sections(&self) -> [StatsSectionView<'_>; 4] {
        [
            StatsSectionView {
                kind: StatsSectionKind::Groups,
                section: &self.stats.groups,
            },
            StatsSectionView {
                kind: StatsSectionKind::Members,
                section: &self.stats.members,
            },
            StatsSectionView {
                kind: StatsSectionKind::Events,
                section: &self.stats.events,
            },
            StatsSectionView {
                kind: StatsSectionKind::Attendees,
                section: &self.stats.attendees,
            },
        ]
    }
}

// Types.

/// Kind of growth series shown in a stats section.
#[derive(Debug, Clone, Copy)]
pub(crate) enum StatsSectionKind {
    /// Event attendees.
    Attendees,
    /// Events.
    Events,
    /// Groups.
    Groups,
    /// Group members.
    Members,
}

impl StatsSectionKind {
    /// Returns the key used in the section chart ids and icon.
    pub(crate) fn key(self) -> &'static str {
        match self {
            Self::Attendees => "attendees",
            Self::Events => "events",
            Self::Groups => "groups",
            Self::Members => "members",
        }
    }

    /// Returns the section title.
    pub(crate) fn title(self) -> &'static str {
        match self {
            Self::Attendees => "Attendees",
            Self::Events => "Events",
            Self::Groups => "Groups",
            Self::Members => "Members",
        }
    }

    /// Returns the noun that describes `count` items of this kind.
    fn noun(self, count: i64) -> &'static str {
        match (self, count == 1) {
            (Self::Attendees, true) => "attendee",
            (Self::Attendees, false) => "attendees",
            (Self::Events, true) => "event",
            (Self::Events, false) => "events",
            (Self::Groups, true) => "group",
            (Self::Groups, false) => "groups",
            (Self::Members, true) => "member",
            (Self::Members, false) => "members",
        }
    }
}

/// Stats section prepared for rendering.
#[derive(Debug, Clone, Copy)]
pub(crate) struct StatsSectionView<'a> {
    /// Kind of growth series.
    pub kind: StatsSectionKind,
    /// Section statistics.
    pub section: &'a SiteStatsSection,
}

impl StatsSectionView<'_> {
    /// Returns a text summary of the new items per month chart.
    pub(crate) fn monthly_summary(&self) -> String {
        let per_month = &self.section.per_month;

        // Find the busiest month, the earliest on ties, or skip the summary
        // when the chart shows the empty state
        let Some((peak_label, peak_count)) = per_month
            .iter()
            .reduce(|peak, entry| if entry.1 > peak.1 { entry } else { peak })
        else {
            return String::new();
        };

        // Describe the only month on its own
        let plural = self.kind.title().to_lowercase();
        let (first_label, first_count) = &per_month[0];
        if per_month.len() == 1 {
            return format!(
                "New {plural} per month: {} new {} in {}.",
                count_label(*first_count),
                self.kind.noun(*first_count),
                label_month(first_label)
            );
        }

        // Describe the whole range and its busiest month
        let (last_label, _) = &per_month[per_month.len() - 1];
        let total = per_month.iter().map(|(_, count)| count).sum::<i64>();
        format!(
            "New {plural} per month: {} new {} from {} to {}. The busiest month was {} with {}.",
            count_label(total),
            self.kind.noun(total),
            label_month(first_label),
            label_month(last_label),
            label_month(peak_label),
            count_label(*peak_count)
        )
    }

    /// Returns a text summary of the running total chart.
    pub(crate) fn running_summary(&self) -> String {
        let running_total = &self.section.running_total;

        // Skip the summary when the chart shows the empty state, which the
        // stats_section macro renders up to one point (min_points = 1)
        if running_total.len() <= 1 {
            return String::new();
        }

        // Describe the first and last points of the series
        let (first_timestamp, first_count) = running_total[0];
        let (last_timestamp, last_count) = running_total[running_total.len() - 1];
        format!(
            "{} over time: went from {} {} in {} to {} {} in {}.",
            self.kind.title(),
            count_label(first_count),
            self.kind.noun(first_count),
            timestamp_month(first_timestamp),
            count_label(last_count),
            self.kind.noun(last_count),
            timestamp_month(last_timestamp)
        )
    }
}

// Helpers.

/// Returns the month name of a `YYYY-MM` label, or the label when malformed.
fn label_month(label: &str) -> String {
    NaiveDate::parse_from_str(&format!("{label}-01"), "%Y-%m-%d").map_or_else(
        |_| label.to_string(),
        |date| date.format(SUMMARY_MONTH_FORMAT).to_string(),
    )
}

/// Returns the UTC month name of a millisecond timestamp, or the raw value
/// when invalid.
fn timestamp_month(timestamp: i64) -> String {
    DateTime::from_timestamp_millis(timestamp).map_or_else(
        || timestamp.to_string(),
        |date| date.format(SUMMARY_MONTH_FORMAT).to_string(),
    )
}
