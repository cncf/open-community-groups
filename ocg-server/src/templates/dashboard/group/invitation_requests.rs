//! Templates and types for listing event invitation requests in the group dashboard.

use askama::Template;
use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;

use crate::{
    templates::{dashboard, dashboard::group::PresenceFilter, helpers::user_initials},
    types::{
        event::{EventInvitationRequestStatus, EventSummary},
        pagination::{self, Pagination, ToRawQuery},
        user::User,
    },
    validation::{MAX_LEN_M, MAX_PAGINATION_LIMIT, trimmed_non_empty_opt},
};

// Pages templates.

/// List invitation requests page template for a group's event.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/invitation_requests_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can manage events.
    pub can_manage_events: bool,
    /// Event for which invitation requests are listed.
    pub event: EventSummary,
    /// Invitation requests for the selected event.
    pub invitation_requests: Vec<InvitationRequest>,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// URL used to refresh the invitation request list with the current filters.
    pub refresh_url: String,
    /// Invitation request status filter.
    pub status: InvitationRequestsStatusFilter,
    /// Total number of invitation requests for the selected event.
    pub total: usize,

    /// Number of results per page.
    pub limit: Option<usize>,
    /// Pagination offset for results.
    pub offset: Option<usize>,
    /// Sort option used to order invitation requests.
    pub sort: Option<InvitationRequestsSort>,
    /// User title presence filter.
    pub title: Option<PresenceFilter>,
    /// Text search query used to filter invitation requests.
    pub ts_query: Option<String>,
}

// Types.

/// Event invitation request summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InvitationRequest {
    /// Request creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Invitation request status.
    pub invitation_request_status: EventInvitationRequestStatus,
    /// Public profile payload for the requester.
    pub user: User,

    /// Review completion time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub reviewed_at: Option<DateTime<Utc>>,
}

/// Filter parameters for invitation request lists.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct InvitationRequestsFilters {
    /// Invitation request status filter.
    #[serde(default)]
    #[garde(skip)]
    pub status: InvitationRequestsStatusFilter,

    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(min = 1, max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
    /// Sort option used to order invitation requests.
    #[garde(skip)]
    pub sort: Option<InvitationRequestsSort>,
    /// User title presence filter.
    #[garde(skip)]
    pub title: Option<PresenceFilter>,
    /// Text search query.
    #[serde(default, deserialize_with = "crate::validation::blank_string_as_none")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub ts_query: Option<String>,
}

crate::impl_pagination_and_raw_query!(InvitationRequestsFilters, limit, offset);

/// Paginated invitation requests response data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct InvitationRequestsOutput {
    /// Invitation requests for the selected event.
    pub invitation_requests: Vec<InvitationRequest>,
    /// Total number of invitation requests for the selected event.
    pub total: usize,
}

/// Supported invitation request sort options.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, strum::Display, strum::EnumString,
)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum InvitationRequestsSort {
    /// Sort by request creation time ascending.
    CreatedAtAsc,
    /// Sort by request creation time descending.
    CreatedAtDesc,
    /// Sort by requester display name ascending.
    NameAsc,
    /// Sort by requester display name descending.
    NameDesc,
}

/// Supported invitation request status filters.
#[derive(
    Debug,
    Clone,
    Copy,
    Default,
    PartialEq,
    Eq,
    Serialize,
    Deserialize,
    strum::Display,
    strum::EnumString,
)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum InvitationRequestsStatusFilter {
    /// Filter accepted invitation requests.
    Accepted,
    /// Include invitation requests with any status.
    All,
    /// Filter pending invitation requests.
    #[default]
    Pending,
    /// Filter rejected invitation requests.
    Rejected,
}
