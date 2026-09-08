//! Group dashboard waitlist types.

use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    types::{
        dashboard::{self, group::PresenceFilter},
        event::EventAdmissionOfferStatus,
        pagination::{Pagination, ToRawQuery},
        user::User,
    },
    validation::{MAX_LEN_M, MAX_PAGINATION_LIMIT, trimmed_non_empty_opt},
};

/// Event waiting list entry summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WaitlistEntry {
    /// Waiting list creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Ticket type for the queue or offer history.
    pub event_ticket_type_id: Uuid,
    /// Ticket title for the queue or offer history.
    pub ticket_title: String,
    /// Public profile payload for the waitlisted user.
    pub user: User,

    /// Waitlist-generated admission offer identifier.
    pub admission_offer_id: Option<Uuid>,
    /// Waitlist-generated admission offer status.
    pub admission_offer_status: Option<EventAdmissionOfferStatus>,
    /// Offer expiration time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub offer_expires_at: Option<DateTime<Utc>>,
    /// Position within the selected ticket queue.
    pub waitlist_position: Option<usize>,
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
