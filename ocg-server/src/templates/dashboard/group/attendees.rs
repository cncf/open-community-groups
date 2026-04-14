//! Templates and types for listing event attendees in the group dashboard.

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
        payments::{EventRefundRequestStatus, format_amount_minor},
    },
    validation::MAX_PAGINATION_LIMIT,
};

// Pages templates.

/// List attendees page template for a group's event.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/attendees_list.html")]
pub(crate) struct ListPage {
    /// List of attendees for the selected event.
    pub attendees: Vec<Attendee>,
    /// Whether the current user can manage events.
    pub can_manage_events: bool,
    /// Event for which attendees are listed.
    pub event: EventSummary,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// Total number of attendees for the selected event.
    pub total: usize,

    /// Number of results per page.
    pub limit: Option<usize>,
    /// Pagination offset for results.
    pub offset: Option<usize>,
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

    /// Purchase amount in minor units.
    pub amount_minor: Option<i64>,
    /// Timestamp when the attendee checked in.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub checked_in_at: Option<DateTime<Utc>>,
    /// Company the user represents.
    pub company: Option<String>,
    /// Currency used for the purchase.
    pub currency_code: Option<String>,
    /// Discount code applied to the purchase.
    pub discount_code: Option<String>,
    /// Purchase identifier.
    pub event_purchase_id: Option<Uuid>,
    /// Full name.
    pub name: Option<String>,
    /// URL to user's avatar.
    pub photo_url: Option<String>,
    /// Refund request status for the attendee purchase.
    pub refund_request_status: Option<EventRefundRequestStatus>,
    /// Ticket title for the attendee purchase.
    pub ticket_title: Option<String>,
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
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

/// Filter parameters for attendee pagination URLs.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct AttendeesPaginationFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
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

// Helpers.

/// Format an attendee payment amount for display.
#[allow(clippy::ref_option)]
pub(crate) fn format_payment_amount(
    amount_minor: &Option<i64>,
    currency_code: Option<&str>,
) -> Option<String> {
    let amount_minor = (*amount_minor)?;
    let currency_code = currency_code?;

    if amount_minor == 0 {
        return Some("Free".to_string());
    }

    Some(format_amount_minor(amount_minor, currency_code))
}
