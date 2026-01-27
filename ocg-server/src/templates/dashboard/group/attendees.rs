//! Templates and types for listing event attendees in the group dashboard.

use askama::Template;
use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    templates::{
        dashboard::DASHBOARD_PAGINATION_LIMIT,
        helpers::user_initials,
        pagination::{Pagination, ToRawQuery},
    },
    types::event::EventSummary,
    validation::MAX_PAGINATION_LIMIT,
};

// Pages templates.

/// List attendees page template for a group's event.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/attendees_list.html")]
pub(crate) struct ListPage {
    /// List of attendees for the selected event.
    pub attendees: Vec<Attendee>,
    /// Event for which attendees are listed.
    pub event: EventSummary,
    /// Pagination navigation links.
    pub navigation_links: crate::templates::pagination::NavigationLinks,
    /// Total number of attendees for the selected event.
    pub total: usize,
}

// Types.

/// Event attendee summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Attendee {
    /// Whether the attendee has checked in.
    pub checked_in: bool,
    /// RSVP creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// User id.
    pub user_id: Uuid,
    /// Username.
    pub username: String,

    /// Timestamp when the attendee checked in.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub checked_in_at: Option<DateTime<Utc>>,
    /// Company the user represents.
    pub company: Option<String>,
    /// Full name.
    pub name: Option<String>,
    /// URL to user's avatar.
    pub photo_url: Option<String>,
    /// Title held by the user.
    pub title: Option<String>,
}

/// Filter parameters for attendees searches.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct AttendeesFilters {
    /// Selected event to scope attendees list.
    #[garde(skip)]
    pub event_id: Uuid,

    /// Number of results per page.
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[garde(skip)]
    pub offset: Option<usize>,
}

/// Filter parameters for attendee pagination URLs.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct AttendeesPaginationFilters {
    /// Number of results per page.
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[garde(skip)]
    pub offset: Option<usize>,
}

impl AttendeesPaginationFilters {
    /// Apply dashboard defaults to pagination filters.
    pub(crate) fn with_defaults(mut self) -> Self {
        if self.limit.is_none() {
            self.limit = Some(DASHBOARD_PAGINATION_LIMIT);
        }
        if self.offset.is_none() {
            self.offset = Some(0);
        }
        self
    }
}

crate::impl_pagination_and_raw_query!(AttendeesPaginationFilters, limit, offset);

/// Paginated attendee response data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AttendeesOutput {
    /// List of attendees for the selected event.
    pub attendees: Vec<Attendee>,
    /// Total number of attendees for the selected event.
    pub total: usize,
}
