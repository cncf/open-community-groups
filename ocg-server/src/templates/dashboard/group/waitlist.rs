//! Templates and types for listing event waiting list entries in the group dashboard.

use askama::Template;
use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;

use crate::{
    templates::{dashboard, dashboard::group::PresenceFilter, helpers::user_initials},
    types::{
        event::EventSummary,
        pagination::{self, Pagination, ToRawQuery},
        user::User,
    },
    validation::{MAX_LEN_M, MAX_PAGINATION_LIMIT, trimmed_non_empty_opt},
};

// Pages templates.

/// List waitlist page template for a group's event.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/waitlist_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can manage events.
    pub can_manage_events: bool,
    /// Event for which waitlist entries are listed.
    pub event: EventSummary,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// URL used to refresh the waitlist with the current filters.
    pub refresh_url: String,
    /// Total number of waitlist entries for the selected event.
    pub total: usize,
    /// Waitlist entries for the selected event.
    pub waitlist: Vec<WaitlistEntry>,

    /// Number of results per page.
    pub limit: Option<usize>,
    /// Pagination offset for results.
    pub offset: Option<usize>,
    /// Sort option used to order waitlist entries.
    pub sort: Option<WaitlistSort>,
    /// User title presence filter.
    pub title: Option<PresenceFilter>,
    /// Text search query used to filter waitlist entries.
    pub ts_query: Option<String>,
}

// Types.

/// Event waiting list entry summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WaitlistEntry {
    /// Waiting list creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Public profile payload for the waitlisted user.
    pub user: User,
    /// Position in the full event waitlist.
    pub waitlist_position: usize,
}

/// Supported waitlist sort options.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, strum::Display, strum::EnumString,
)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum WaitlistSort {
    /// Sort by waitlist creation time ascending.
    CreatedAtAsc,
    /// Sort by waitlist creation time descending.
    CreatedAtDesc,
    /// Sort by waitlisted user display name ascending.
    NameAsc,
    /// Sort by waitlisted user display name descending.
    NameDesc,
}

/// Filter parameters for waitlist lists.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct WaitlistFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(min = 1, max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
    /// Sort option used to order waitlist entries.
    #[garde(skip)]
    pub sort: Option<WaitlistSort>,
    /// User title presence filter.
    #[garde(skip)]
    pub title: Option<PresenceFilter>,
    /// Text search query.
    #[serde(default, deserialize_with = "crate::validation::blank_string_as_none")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub ts_query: Option<String>,
}

crate::impl_pagination_and_raw_query!(WaitlistFilters, limit, offset);

/// Paginated waitlist response data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct WaitlistOutput {
    /// Total number of waitlist entries for the selected event.
    pub total: usize,
    /// Waitlist entries for the selected event.
    pub waitlist: Vec<WaitlistEntry>,
}
