//! Templates for listing event attendees in the group dashboard.

use askama::Template;
use uuid::Uuid;

use crate::types::dashboard::group::attendees::{
    Attendee, AttendeeEnrollmentStatus, AttendeeEnrollmentStatusFilter, AttendeesSort,
    format_payment_amount,
};
use crate::{
    templates::helpers::user_initials,
    types::{
        dashboard::group::PresenceFilter, event::EventSummary, pagination,
        questionnaire::QuestionnaireQuestion,
    },
};

// Pages templates.

/// List attendees page template for a group's event.
#[derive(Debug, Clone, Template)]
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
    pub registration_questions: Vec<QuestionnaireQuestion>,
    /// Sort option used to order attendees.
    pub sort: Option<AttendeesSort>,
    /// User title presence filter.
    pub title: Option<PresenceFilter>,
    /// Text search query used to filter attendees.
    pub ts_query: Option<String>,
}

// Helpers.

/// Returns true when the attendee has a paid event purchase.
#[allow(clippy::ref_option)]
pub(crate) fn is_paid_attendee(amount_minor: &Option<i64>) -> bool {
    matches!(*amount_minor, Some(amount_minor) if amount_minor > 0)
}
