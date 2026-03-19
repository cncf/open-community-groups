//! Templates and types for listing event waiting list entries in the group dashboard.

use askama::Template;
use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    templates::{dashboard, helpers::user_initials},
    types::{
        event::EventSummary,
        pagination::{self, Pagination, ToRawQuery},
    },
    validation::MAX_PAGINATION_LIMIT,
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
    /// Number of results per page.
    pub limit: Option<usize>,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// Pagination offset for results.
    pub offset: Option<usize>,
    /// Total number of waitlist entries for the selected event.
    pub total: usize,
    /// Waitlist entries for the selected event.
    pub waitlist: Vec<WaitlistEntry>,
}

// Types.

/// Event waiting list entry summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WaitlistEntry {
    /// Waiting list creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// User id.
    pub user_id: Uuid,
    /// Username.
    pub username: String,

    /// Company the user represents.
    pub company: Option<String>,
    /// Full name.
    pub name: Option<String>,
    /// URL to user's avatar.
    pub photo_url: Option<String>,
    /// Title held by the user.
    pub title: Option<String>,
}

/// Filter parameters for waitlist searches.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct WaitlistFilters {
    /// Selected event to scope waitlist entries.
    #[garde(skip)]
    pub event_id: Uuid,

    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

/// Filter parameters for waitlist pagination URLs.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct WaitlistPaginationFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(WaitlistPaginationFilters, limit, offset);

/// Paginated waitlist response data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct WaitlistOutput {
    /// Total number of waitlist entries for the selected event.
    pub total: usize,
    /// Waitlist entries for the selected event.
    pub waitlist: Vec<WaitlistEntry>,
}
