//! Templates and types for listing event attendees in the group dashboard.

use askama::Template;
use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    templates::{dashboard, dashboard::group::PresenceFilter, helpers::user_initials},
    types::{
        event::{EventAdmissionOfferSource, EventAdmissionOfferStatus, EventSummary},
        pagination::{self, Pagination, ToRawQuery},
        payments::{EventRefundProgress, EventRefundRequestStatus, format_amount_minor},
        questionnaire::{QuestionnaireAnswers, QuestionnaireQuestion},
        user::User,
    },
    validation::{MAX_ITEMS, MAX_LEN_M, MAX_PAGINATION_LIMIT, trimmed_non_empty_opt},
};

// Pages templates.

/// List attendees page template for a group's event.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/attendees_list.html")]
pub(crate) struct ListPage {
    /// Number of attendees eligible for the all-attendees custom email scope.
    pub all_attendees_email_recipient_total: usize,
    /// List of attendees for the selected event.
    pub attendees: Vec<Attendee>,
    /// Whether the current user can process attendee check-ins.
    pub can_manage_check_ins: bool,
    /// Whether the current user can manage events.
    pub can_manage_events: bool,
    /// Event for which attendees are listed.
    pub event: EventSummary,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// URL used to refresh the attendee list with the current filters.
    pub refresh_url: String,
    /// Enrollment status filter.
    pub status: AttendeeEnrollmentStatusFilter,
    /// Total number of attendees for the selected event.
    pub total: usize,

    /// Checked-in status filter.
    pub checked_in: Option<bool>,
    /// Event ticket type identifiers used to filter attendees.
    pub event_ticket_type_ids: Option<Vec<Uuid>>,
    /// Number of results per page.
    pub limit: Option<usize>,
    /// Pagination offset for results.
    pub offset: Option<usize>,
    /// Registration questions configured for the event.
    #[serde(default)]
    pub registration_questions: Vec<QuestionnaireQuestion>,
    /// Sort option used to order attendees.
    pub sort: Option<AttendeesSort>,
    /// User title presence filter.
    pub title: Option<PresenceFilter>,
    /// Text search query used to filter attendees.
    pub ts_query: Option<String>,
}

// Types.

/// Event attendee summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Attendee {
    /// Whether the attendee can receive attendee emails.
    pub can_receive_attendee_email: bool,
    /// Whether the attendee has checked in.
    pub checked_in: bool,
    /// Enrollment record creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Email address for invitation placeholders and registered users.
    pub email: String,
    /// Organizer-facing enrollment status.
    pub enrollment_status: AttendeeEnrollmentStatus,
    /// Whether the attendee was manually invited by an organizer.
    pub manually_invited: bool,
    /// Public profile payload for the attendee.
    pub user: User,

    /// Latest organizer admission offer identifier.
    pub admission_offer_id: Option<Uuid>,
    /// Workflow that created the latest organizer admission offer.
    pub admission_offer_source: Option<EventAdmissionOfferSource>,
    /// Lifecycle status of the latest organizer admission offer.
    pub admission_offer_status: Option<EventAdmissionOfferStatus>,
    /// Purchase amount in minor units.
    pub amount_minor: Option<i64>,
    /// Timestamp when the attendee checked in.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub checked_in_at: Option<DateTime<Utc>>,
    /// Currency used for the purchase.
    pub currency_code: Option<String>,
    /// Discount code applied to the purchase.
    pub discount_code: Option<String>,
    /// Purchase identifier.
    pub event_purchase_id: Option<Uuid>,
    /// Ticket type assigned by an offer or purchase.
    pub event_ticket_type_id: Option<Uuid>,
    /// Latest organizer offer expiration time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub offer_expires_at: Option<DateTime<Utc>>,
    /// Durable refund progress for this attendee's purchase.
    pub refund_progress: Option<EventRefundProgress>,
    /// Refund request status for the attendee purchase.
    pub refund_request_status: Option<EventRefundRequestStatus>,
    /// Registration answers submitted by the attendee, when configured.
    pub registration_answers: Option<QuestionnaireAnswers>,
    /// Ticket title for the attendee purchase.
    pub ticket_title: Option<String>,
}

/// Exact enrollment status shown for an attendee table row.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, strum::Display)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum AttendeeEnrollmentStatus {
    /// Confirmed attendance was canceled.
    AttendanceCanceled,
    /// Ticket checkout is still pending.
    CheckoutPending,
    /// Attendance is confirmed.
    Confirmed,
    /// An organizer invitation was canceled.
    InvitationCanceled,
    /// An organizer invitation was declined.
    InvitationDeclined,
    /// An organizer invitation expired.
    InvitationExpired,
    /// An organizer invitation is waiting for the recipient.
    InvitationPending,
    /// Registration questions still need to be completed.
    RegistrationPending,
}

/// Enrollment status views supported by the attendee table.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize, strum::Display)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum AttendeeEnrollmentStatusFilter {
    /// Show every current and historical enrollment row.
    All,
    /// Show only canceled attendance rows.
    AttendanceCanceled,
    /// Show only pending checkout rows.
    CheckoutPending,
    /// Show only confirmed attendee rows.
    Confirmed,
    /// Show current confirmed and pending enrollment rows.
    #[default]
    Current,
    /// Show canceled attendance and terminal invitation rows.
    History,
    /// Show only canceled invitation rows.
    InvitationCanceled,
    /// Show only declined invitation rows.
    InvitationDeclined,
    /// Show only expired invitation rows.
    InvitationExpired,
    /// Show only pending invitation rows.
    InvitationPending,
    /// Show only pending registration rows.
    RegistrationPending,
}

/// Supported attendee sort options.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, strum::Display, strum::EnumString,
)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum AttendeesSort {
    /// Sort by enrollment creation time ascending.
    CreatedAtAsc,
    /// Sort by enrollment creation time descending.
    CreatedAtDesc,
    /// Sort by attendee display name ascending.
    NameAsc,
    /// Sort by attendee display name descending.
    NameDesc,
}

/// Filter parameters for attendee lists.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct AttendeesFilters {
    /// Checked-in status filter.
    #[garde(skip)]
    pub checked_in: Option<bool>,
    /// Event ticket type identifiers used to filter attendees.
    #[garde(length(max = MAX_ITEMS))]
    pub event_ticket_type_ids: Option<Vec<Uuid>>,
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(min = 1, max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
    /// Sort option used to order attendees.
    #[garde(skip)]
    pub sort: Option<AttendeesSort>,
    /// Enrollment status filter.
    #[garde(skip)]
    pub status: Option<AttendeeEnrollmentStatusFilter>,
    /// User title presence filter.
    #[garde(skip)]
    pub title: Option<PresenceFilter>,
    /// Text search query.
    #[serde(default, deserialize_with = "crate::validation::blank_string_as_none")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub ts_query: Option<String>,
}

crate::impl_pagination_and_raw_query!(AttendeesFilters, limit, offset);

/// Paginated attendee response data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AttendeesOutput {
    /// Number of attendees eligible for the all-attendees custom email scope.
    pub all_attendees_email_recipient_total: usize,
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

    if amount_minor == 0 {
        return Some("Free".to_string());
    }

    let currency_code = currency_code?;
    Some(format_amount_minor(amount_minor, currency_code))
}

/// Returns true when the attendee has a paid event purchase.
#[allow(clippy::ref_option)]
pub(crate) fn is_paid_attendee(amount_minor: &Option<i64>) -> bool {
    matches!(*amount_minor, Some(amount_minor) if amount_minor > 0)
}

#[cfg(test)]
mod tests {
    use super::format_payment_amount;

    #[test]
    fn test_format_payment_amount_formats_free_without_currency() {
        assert_eq!(
            format_payment_amount(&Some(0), None),
            Some("Free".to_string())
        );
    }

    #[test]
    fn test_format_payment_amount_requires_currency_for_paid_amounts() {
        assert_eq!(format_payment_amount(&Some(2500), None), None);
    }
}
