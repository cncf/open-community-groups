//! Templates and types for listing event invitation requests in the group dashboard.

use askama::Template;
use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    templates::{dashboard, helpers::user_initials},
    types::{
        event::{EventInvitationRequestStatus, EventSummary},
        pagination::{self, Pagination, ToRawQuery},
    },
    validation::MAX_PAGINATION_LIMIT,
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
    /// Number of results per page.
    pub limit: Option<usize>,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// Pagination offset for results.
    pub offset: Option<usize>,
    /// Total number of invitation requests for the selected event.
    pub total: usize,
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
    /// Review completion time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub reviewed_at: Option<DateTime<Utc>>,
    /// Title held by the user.
    pub title: Option<String>,
}

/// Filter parameters for invitation request searches.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct InvitationRequestsFilters {
    /// Selected event to scope invitation requests.
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

/// Filter parameters for invitation request pagination URLs.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct InvitationRequestsPaginationFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(InvitationRequestsPaginationFilters, limit, offset);

/// Paginated invitation requests response data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct InvitationRequestsOutput {
    /// Invitation requests for the selected event.
    pub invitation_requests: Vec<InvitationRequest>,
    /// Total number of invitation requests for the selected event.
    pub total: usize,
}
