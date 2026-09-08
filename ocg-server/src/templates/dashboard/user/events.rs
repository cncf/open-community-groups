//! Templates for user upcoming events.

use askama::Template;

use crate::types::dashboard::user::events::UserEvent;
use crate::types::pagination;

// Pages templates.

/// List page for the user upcoming events section.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/user/events_list.html")]
pub(crate) struct ListPage {
    /// Events where the user participates.
    pub events: Vec<UserEvent>,
    /// Pagination links for the events list.
    pub navigation_links: pagination::NavigationLinks,
    /// Total number of events before pagination.
    pub total: usize,

    /// Pagination offset for results.
    pub offset: Option<usize>,
}
