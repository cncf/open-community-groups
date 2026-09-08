//! Group dashboard invitation request types.

use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;

use crate::{
    types::{
        dashboard::{self, group::PresenceFilter},
        event::{EventAdmissionOfferStatus, EventInvitationRequestStatus},
        pagination::{Pagination, ToRawQuery},
        questionnaire::QuestionnaireAnswers,
        user::User,
    },
    validation::{MAX_LEN_M, MAX_PAGINATION_LIMIT, trimmed_non_empty_opt},
};

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

    /// Latest approval admission offer identifier.
    pub admission_offer_id: Option<uuid::Uuid>,
    /// Latest approval admission offer lifecycle status.
    pub admission_offer_status: Option<EventAdmissionOfferStatus>,
    /// Latest approval offer expiration time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub offer_expires_at: Option<DateTime<Utc>>,
    /// Ticket type assigned by the organizer.
    pub offered_event_ticket_type_id: Option<uuid::Uuid>,
    /// Ticket title assigned by the organizer.
    pub offered_ticket_title: Option<String>,
    /// Registration answers submitted with the request.
    pub registration_answers: Option<QuestionnaireAnswers>,
    /// Public ticket type requested by the attendee, when one was visible.
    pub requested_event_ticket_type_id: Option<uuid::Uuid>,
    /// Public ticket title requested by the attendee, when one was visible.
    pub requested_ticket_title: Option<String>,
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
