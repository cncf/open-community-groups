//! Templates for listing event waiting list entries in the group dashboard.

use askama::Template;

use crate::types::dashboard::group::waitlist::{WaitlistEntry, WaitlistSort};
use crate::{
    templates::helpers::user_initials,
    types::{dashboard::group::PresenceFilter, event::EventSummary, pagination},
};

// Pages templates.

/// List waitlist page template for a group's event.
#[derive(Debug, Clone, Template)]
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
