//! Templates and types for user upcoming events.

use askama::Template;
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;

use crate::{
    templates::dashboard,
    types::{
        event::{EventAttendanceStatus, EventSummary},
        pagination::{self, Pagination, ToRawQuery},
        questionnaire::{QuestionnaireAnswers, QuestionnaireQuestion},
    },
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
    /// Whether the user has a paid purchase that blocks dashboard cancellation.
    #[serde(default)]
    pub has_paid_purchase: bool,
    /// Registration questions configured for the event.
    #[serde(default)]
    pub registration_questions: Vec<QuestionnaireQuestion>,
    /// Roles the user has in the event.
    #[serde(default)]
    pub roles: Vec<UserEventRole>,

    /// Current attendee status for the user, when the user is an attendee.
    pub attendance_status: Option<EventAttendanceStatus>,
    /// Existing registration answers submitted by the user.
    pub registration_answers: Option<QuestionnaireAnswers>,
    /// Checkout URL where the user can complete payment.
    pub resume_checkout_url: Option<String>,
}

impl UserEvent {
    /// Returns the attendee status badge label, when the row needs one.
    pub(crate) fn attendance_status_label(&self) -> Option<&'static str> {
        match self.attendance_status.as_ref()? {
            EventAttendanceStatus::PendingPayment => Some("Payment pending"),
            EventAttendanceStatus::RegistrationQuestionsPending => Some("Registration pending"),
            _ => None,
        }
    }

    /// Returns true when attendance can be canceled from the user dashboard.
    pub(crate) fn can_cancel_attendance(&self) -> bool {
        // Pending registrations on ticketed events are owned by the checkout hold flow
        let cancelable_status = match self.attendance_status.as_ref() {
            Some(EventAttendanceStatus::Attendee) => true,
            Some(EventAttendanceStatus::RegistrationQuestionsPending) => !self.event.is_ticketed(),
            _ => false,
        };
        cancelable_status
            && self.roles.as_slice() == [UserEventRole::Attendee]
            && !self.has_paid_purchase
    }

    /// Returns true when registration answers can be completed or updated.
    pub(crate) fn can_complete_registration_questions(&self) -> bool {
        !self.registration_questions.is_empty()
            && matches!(
                self.attendance_status.as_ref(),
                Some(
                    EventAttendanceStatus::Attendee
                        | EventAttendanceStatus::RegistrationQuestionsPending
                )
            )
    }

    /// Returns true when registration questions are still required.
    pub(crate) fn registration_questions_pending(&self) -> bool {
        matches!(
            self.attendance_status.as_ref(),
            Some(EventAttendanceStatus::RegistrationQuestionsPending)
        )
    }
}

/// User's participation role in an event.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, strum::Display, strum::EnumString,
)]
#[serde(rename_all = "lowercase")]
#[strum(serialize_all = "lowercase")]
pub(crate) enum UserEventRole {
    /// User attends the event.
    Attendee,
    /// User hosts the event.
    Host,
    /// User speaks at the event or one of its sessions.
    Speaker,
}

impl UserEventRole {
    /// Returns the user-facing role label.
    pub(crate) fn label(self) -> &'static str {
        match self {
            Self::Attendee => "Attendee",
            Self::Host => "Host",
            Self::Speaker => "Speaker",
        }
    }
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

#[cfg(test)]
mod tests {
    use uuid::Uuid;

    use crate::{
        handlers::tests::sample_event_summary,
        types::{event::EventAttendanceStatus, payments::EventTicketType},
    };

    use super::{UserEvent, UserEventRole};

    #[test]
    fn can_cancel_attendance_allows_attendee_status() {
        let user_event = sample_user_event();

        assert!(user_event.can_cancel_attendance());
    }

    #[test]
    fn can_cancel_attendance_allows_pending_registration_on_non_ticketed_event() {
        let mut user_event = sample_user_event();
        user_event.attendance_status = Some(EventAttendanceStatus::RegistrationQuestionsPending);

        assert!(user_event.can_cancel_attendance());
    }

    #[test]
    fn can_cancel_attendance_rejects_other_statuses() {
        let mut user_event = sample_user_event();
        user_event.attendance_status = Some(EventAttendanceStatus::Waitlisted);

        assert!(!user_event.can_cancel_attendance());
    }

    #[test]
    fn can_cancel_attendance_rejects_pending_registration_on_ticketed_event() {
        let mut user_event = sample_user_event();
        user_event.attendance_status = Some(EventAttendanceStatus::RegistrationQuestionsPending);
        user_event.event.ticket_types = Some(vec![EventTicketType::default()]);

        assert!(!user_event.can_cancel_attendance());
    }

    // Helpers.

    /// Sample user event row with cancelable attendee attendance.
    fn sample_user_event() -> UserEvent {
        UserEvent {
            event: sample_event_summary(Uuid::new_v4(), Uuid::new_v4()),
            has_paid_purchase: false,
            registration_questions: vec![],
            roles: vec![UserEventRole::Attendee],
            attendance_status: Some(EventAttendanceStatus::Attendee),
            registration_answers: None,
            resume_checkout_url: None,
        }
    }
}
