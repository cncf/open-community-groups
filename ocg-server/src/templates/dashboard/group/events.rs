//! Templates for managing events in the group dashboard.

use std::collections::HashMap;

use askama::Template;
use uuid::Uuid;

use crate::types::dashboard::group::events::{
    ApprovedSubmissionSummary, CfsSubmissionStatus, EventsTab, GroupEvents,
};
use crate::{
    templates::{filters, helpers::DATE_FORMAT},
    types::{
        event::{EventCategory, EventFull, EventKindSummary, SessionKindSummary},
        group::GroupSponsor,
        meetings::MeetingProvider,
        pagination,
        payments::{GroupExternalPaymentsContext, TicketTaxBehavior, TicketTaxCalculationMode},
    },
};

pub(crate) mod preview;

// Pages templates.

/// Add event page template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/events_add.html")]
#[allow(clippy::struct_excessive_bools)]
pub(crate) struct AddPage {
    /// Whether the current user can manage events.
    pub can_manage_events: bool,
    /// List of available event categories.
    pub categories: Vec<EventCategory>,
    /// List of available event kinds.
    pub event_kinds: Vec<EventKindSummary>,
    /// Group-level external-payments eligibility and window limits.
    pub external_payments: GroupExternalPaymentsContext,
    /// Group identifier.
    pub group_id: Uuid,
    /// Flag indicating if meetings functionality is enabled.
    pub meetings_enabled: bool,
    /// Maximum participants per meeting provider.
    pub meetings_max_participants: HashMap<MeetingProvider, i32>,
    /// Supported payment currency codes.
    pub payment_currency_codes: Vec<String>,
    /// Whether this group can publish paid events.
    pub payments_ready: bool,
    /// List of available session kinds.
    pub session_kinds: Vec<SessionKindSummary>,
    /// List of sponsors available for this group.
    pub sponsors: Vec<GroupSponsor>,
    /// List of available timezones.
    pub timezones: Vec<String>,
}

impl AddPage {
    /// Returns true when paid tickets can be configured through Stripe or external payments.
    pub(crate) fn is_paid_ticketing_available(&self) -> bool {
        !matches!(
            event_ticketing_mode(self.payments_ready, &self.external_payments),
            EventTicketingMode::Unavailable
        )
    }

    /// Returns true when the group currently collects paid tickets outside the platform.
    pub(crate) fn uses_external_ticketing(&self) -> bool {
        matches!(
            event_ticketing_mode(self.payments_ready, &self.external_payments),
            EventTicketingMode::External
        )
    }
}

/// List events page template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/events_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can manage events.
    pub can_manage_events: bool,
    /// Group events split by upcoming and past ones.
    pub events: GroupEvents,
    /// Current events tab selection.
    pub events_tab: EventsTab,
    /// Pagination links for past events.
    pub past_navigation_links: pagination::NavigationLinks,
    /// Pagination links for upcoming events.
    pub upcoming_navigation_links: pagination::NavigationLinks,

    /// Pagination offset for past events.
    pub past_offset: Option<usize>,
    /// Pagination offset for upcoming events.
    pub upcoming_offset: Option<usize>,
}

/// Update event page template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/events_update.html")]
#[allow(clippy::struct_excessive_bools)]
pub(crate) struct UpdatePage {
    /// Approved CFS submissions for linking sessions.
    pub approved_submissions: Vec<ApprovedSubmissionSummary>,
    /// Whether the current user can manage events.
    pub can_manage_events: bool,
    /// List of available event categories.
    pub categories: Vec<EventCategory>,
    /// CFS submission status options.
    pub cfs_submission_statuses: Vec<CfsSubmissionStatus>,
    /// Current authenticated user identifier.
    pub current_user_id: Uuid,
    /// Event details to update.
    pub event: EventFull,
    /// List of available event kinds.
    pub event_kinds: Vec<EventKindSummary>,
    /// Group-level external-payments eligibility and window limits.
    pub external_payments: GroupExternalPaymentsContext,
    /// Flag indicating if meetings functionality is enabled.
    pub meetings_enabled: bool,
    /// Maximum participants per meeting provider.
    pub meetings_max_participants: HashMap<MeetingProvider, i32>,
    /// Supported payment currency codes.
    pub payment_currency_codes: Vec<String>,
    /// Whether this group can publish paid events.
    pub payments_ready: bool,
    /// List of available session kinds.
    pub session_kinds: Vec<SessionKindSummary>,
    /// List of sponsors available for this group.
    pub sponsors: Vec<GroupSponsor>,
    /// List of available timezones.
    pub timezones: Vec<String>,
}

impl UpdatePage {
    /// Returns true when paid tickets can be configured through Stripe or external payments.
    pub(crate) fn is_paid_ticketing_available(&self) -> bool {
        !matches!(
            event_ticketing_mode(self.payments_ready, &self.external_payments),
            EventTicketingMode::Unavailable
        )
    }

    /// Returns true when the provided currency code matches the current event currency.
    pub(crate) fn is_selected_payment_currency_code(&self, payment_currency_code: &str) -> bool {
        self.event.payment_currency_code.as_deref() == Some(payment_currency_code)
    }

    /// Returns true when tax is added to the configured ticket price.
    pub(crate) fn uses_exclusive_ticket_tax(&self) -> bool {
        self.event.tax_behavior == TicketTaxBehavior::Exclusive
    }

    /// Returns true when the group currently collects paid tickets outside the platform.
    pub(crate) fn uses_external_ticketing(&self) -> bool {
        matches!(
            event_ticketing_mode(self.payments_ready, &self.external_payments),
            EventTicketingMode::External
        )
    }

    /// Returns true when the event uses manual Stripe Tax Rates.
    pub(crate) fn uses_manual_ticket_tax(&self) -> bool {
        self.event.tax_calculation_mode == TicketTaxCalculationMode::Manual
    }

    /// Returns true when the event does not collect ticket tax.
    pub(crate) fn uses_no_ticket_tax(&self) -> bool {
        self.event.tax_calculation_mode == TicketTaxCalculationMode::None
    }
}

// Helpers.

/// Paid-ticketing rail available on the event editor.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum EventTicketingMode {
    /// Organizer-collected payments outside the platform.
    External,
    /// Stripe Connect payments.
    Stripe,
    /// Paid tickets cannot be configured.
    Unavailable,
}

/// Resolves the event editor's paid-ticketing rail.
fn event_ticketing_mode(
    payments_ready: bool,
    external_payments: &GroupExternalPaymentsContext,
) -> EventTicketingMode {
    // Prefer organizer-collected payments when the group is opted in and allowlisted
    if external_payments.enabled && external_payments.eligible {
        EventTicketingMode::External
    // Use Stripe when a matching fiscal sponsor is configured
    } else if payments_ready {
        EventTicketingMode::Stripe
    // Hide paid ticketing until one rail is available
    } else {
        EventTicketingMode::Unavailable
    }
}

#[cfg(test)]
mod tests {
    use crate::types::payments::GroupExternalPaymentsContext;

    use super::{EventTicketingMode, event_ticketing_mode};

    #[test]
    fn test_event_ticketing_mode_prefers_external_when_eligible() {
        let external_payments = GroupExternalPaymentsContext {
            configured: true,
            eligible: true,
            enabled: true,
            country_code: Some("KR".to_string()),
            default_payment_window_hours: Some(72),
            max_payment_window_hours: Some(336),
        };

        assert_eq!(
            event_ticketing_mode(true, &external_payments),
            EventTicketingMode::External
        );
    }

    #[test]
    fn test_event_ticketing_mode_returns_external_without_stripe_recipient() {
        let external_payments = GroupExternalPaymentsContext {
            configured: true,
            eligible: true,
            enabled: true,
            country_code: Some("KR".to_string()),
            default_payment_window_hours: Some(72),
            max_payment_window_hours: Some(336),
        };

        assert_eq!(
            event_ticketing_mode(false, &external_payments),
            EventTicketingMode::External
        );
    }

    #[test]
    fn test_event_ticketing_mode_returns_stripe_when_external_is_unavailable() {
        let external_payments = GroupExternalPaymentsContext {
            configured: true,
            eligible: false,
            enabled: false,
            country_code: Some("US".to_string()),
            default_payment_window_hours: Some(72),
            max_payment_window_hours: Some(336),
        };

        assert_eq!(
            event_ticketing_mode(true, &external_payments),
            EventTicketingMode::Stripe
        );
    }

    #[test]
    fn test_event_ticketing_mode_returns_unavailable_without_either_rail() {
        let external_payments = GroupExternalPaymentsContext::default();

        assert_eq!(
            event_ticketing_mode(false, &external_payments),
            EventTicketingMode::Unavailable
        );
    }
}
