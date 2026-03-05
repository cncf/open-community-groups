//! Templates and types for user upcoming events.

use askama::Template;
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;

use crate::{
    templates::{
        dashboard,
        pagination::{self, Pagination, ToRawQuery},
    },
    types::event::EventSummary,
    validation::MAX_PAGINATION_LIMIT,
};

// Pages templates.

/// List page for the user upcoming events section.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/user/events_list.html")]
pub(crate) struct ListPage {
    /// Events where the user participates.
    pub events: Vec<UserEvent>,
    /// Pagination links for the events list.
    pub navigation_links: pagination::NavigationLinks,
    /// Total number of events before pagination.
    pub total: usize,

    /// Number of results per page.
    pub limit: Option<usize>,
    /// Pagination offset for results.
    pub offset: Option<usize>,
}

// Types.

/// Summary of one user event participation.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct UserEvent {
    /// Event summary data.
    pub event: EventSummary,
    /// Roles the user has in the event.
    pub roles: Vec<String>,
}

/// Filter parameters for events pagination.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct UserEventsFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(UserEventsFilters, limit, offset);

/// Paginated events response data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct UserEventsOutput {
    /// Events where the user participates.
    pub events: Vec<UserEvent>,
    /// Total number of events before pagination.
    pub total: usize,
}
