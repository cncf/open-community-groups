//! Templates for managing events in the group dashboard.

use std::collections::HashMap;

use askama::Template;
use uuid::Uuid;

use crate::types::dashboard::group::events::{
    ApprovedSubmissionSummary, CfsSubmissionStatus, EventCohostsEditor, EventsTab, GroupEvents,
};
use crate::{
    templates::{filters, helpers::DATE_FORMAT},
    types::{
        community::CommunitySummary,
        event::{EventCategory, EventFull, EventKindSummary, SessionKindSummary},
        group::GroupSponsor,
        meetings::MeetingProvider,
        pagination,
        payments::{GroupExternalPaymentsContext, TicketTaxBehavior, TicketTaxCalculationMode},
        user::User,
    },
};

use self::sections::{EventFormMode, EventFormTabFlags, EventFormTabGroup};

pub(crate) mod preview;
pub(crate) mod sections;

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
    /// Communities whose groups can be invited to co-host.
    pub communities: Vec<CommunitySummary>,
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
    /// Accepted group team members, in team order, who can be event organizers.
    pub team_members: Vec<User>,
    /// List of available timezones.
    pub timezones: Vec<String>,
}

impl AddPage {
    /// Returns the event editor tab groups shown on the add page.
    #[allow(clippy::unused_self)]
    pub(crate) fn form_tab_groups(&self) -> Vec<EventFormTabGroup> {
        sections::form_tab_groups(&EventFormMode::Add, EventFormTabFlags::default())
    }

    /// Returns true when paid tickets can be configured through Stripe or external payments.
    pub(crate) fn is_paid_ticketing_available(&self) -> bool {
        is_paid_ticketing_available(self.payments_ready, &self.external_payments)
    }

    /// Returns true when paid tickets wait only on the group's external-payments opt-in.
    pub(crate) fn requires_external_payments_opt_in(&self) -> bool {
        requires_external_payments_opt_in(self.payments_ready, &self.external_payments)
    }

    /// Returns true when paid tickets wait only on the external payee legal name.
    pub(crate) fn requires_external_payments_seller_name(&self) -> bool {
        requires_external_payments_seller_name(self.payments_ready, &self.external_payments)
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
    /// Current co-hosts of the event.
    pub cohosts: EventCohostsEditor,
    /// Communities whose groups can be invited to co-host.
    pub communities: Vec<CommunitySummary>,
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
    /// Whether the invitation requests tab is shown.
    pub show_invitation_requests_tab: bool,
    /// Whether the waitlist tab is shown.
    pub show_waitlist_tab: bool,
    /// List of sponsors available for this group.
    pub sponsors: Vec<GroupSponsor>,
    /// Accepted group team members, in team order, who can be event organizers.
    pub team_members: Vec<User>,
    /// List of available timezones.
    pub timezones: Vec<String>,
}

impl UpdatePage {
    /// Returns the event editor tab groups shown on the update page.
    pub(crate) fn form_tab_groups(&self) -> Vec<EventFormTabGroup> {
        let mode = EventFormMode::Update {
            attendee_approval_required: self.event.attendee_approval_required,
            event_id: self.event.event_id,
        };
        let flags = EventFormTabFlags {
            invitation_requests: self.show_invitation_requests_tab,
            surveys: !self.event.canceled,
            waitlist: self.show_waitlist_tab,
        };
        sections::form_tab_groups(&mode, flags)
    }

    /// Returns true when paid tickets can be configured through Stripe or external payments.
    pub(crate) fn is_paid_ticketing_available(&self) -> bool {
        is_paid_ticketing_available(self.payments_ready, &self.external_payments)
    }

    /// Returns the number of co-hosts that have not responded yet.
    pub(crate) fn pending_cohosts_count(&self) -> usize {
        self.cohosts.pending_count()
    }

    /// Returns true when the provided currency code matches the current event currency.
    pub(crate) fn is_selected_payment_currency_code(&self, payment_currency_code: &str) -> bool {
        self.event.payment_currency_code.as_deref() == Some(payment_currency_code)
    }

    /// Returns true when paid tickets wait only on the group's external-payments opt-in.
    pub(crate) fn requires_external_payments_opt_in(&self) -> bool {
        requires_external_payments_opt_in(self.payments_ready, &self.external_payments)
    }

    /// Returns true when paid tickets wait only on the external payee legal name.
    pub(crate) fn requires_external_payments_seller_name(&self) -> bool {
        requires_external_payments_seller_name(self.payments_ready, &self.external_payments)
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

/// Resolves the event editor's paid-ticketing rail. Selection is independent
/// of readiness: an opted-in, allowlisted group stays on the external rail even
/// while it cannot collect on it yet.
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

/// Reports whether the selected rail can collect paid tickets right now.
fn is_paid_ticketing_available(
    payments_ready: bool,
    external_payments: &GroupExternalPaymentsContext,
) -> bool {
    match event_ticketing_mode(payments_ready, external_payments) {
        // External collection needs the legal name of the collecting organization
        EventTicketingMode::External => external_payments.seller_display_name.is_some(),
        // Stripe readiness already covers the fiscal sponsor
        EventTicketingMode::Stripe => true,
        // No rail is selected or ready
        EventTicketingMode::Unavailable => false,
    }
}

/// Reports whether paid ticketing is unavailable only because an allowlisted
/// group has not opted into external payments; Stripe onboarding is blocked
/// for its country, so the opt-in is the remaining path to paid tickets.
fn requires_external_payments_opt_in(
    payments_ready: bool,
    external_payments: &GroupExternalPaymentsContext,
) -> bool {
    matches!(
        event_ticketing_mode(payments_ready, external_payments),
        EventTicketingMode::Unavailable
    ) && external_payments.configured
        && external_payments.eligible
        && !external_payments.enabled
}

/// Reports whether paid ticketing waits only on the legal name of the
/// organization collecting external payments for a group on that rail.
fn requires_external_payments_seller_name(
    payments_ready: bool,
    external_payments: &GroupExternalPaymentsContext,
) -> bool {
    matches!(
        event_ticketing_mode(payments_ready, external_payments),
        EventTicketingMode::External
    ) && external_payments.seller_display_name.is_none()
}

#[cfg(test)]
mod tests {
    use crate::types::payments::GroupExternalPaymentsContext;

    use super::{
        EventTicketingMode, event_ticketing_mode, is_paid_ticketing_available,
        requires_external_payments_opt_in, requires_external_payments_seller_name,
    };

    #[test]
    #[allow(clippy::too_many_lines)]
    fn test_ticketing_rail_helpers_follow_rail_selection() {
        use EventTicketingMode::{External, Stripe, Unavailable};

        let named = Some("External Payee Co");
        // (case, payments_ready, external payments, mode, available, opt_in, seller_name)
        let cases = [
            (
                "no rail configured",
                false,
                GroupExternalPaymentsContext::default(),
                Unavailable,
                false,
                false,
                false,
            ),
            (
                "stripe ready, country not allowlisted",
                true,
                external_payments(true, false, false, named),
                Stripe,
                true,
                false,
                false,
            ),
            (
                "stripe ready, country not allowlisted, nameless",
                true,
                external_payments(true, false, false, None),
                Stripe,
                true,
                false,
                false,
            ),
            (
                "stripe not ready, country not allowlisted",
                false,
                external_payments(true, false, false, None),
                Unavailable,
                false,
                false,
                false,
            ),
            (
                "allowlisted but external payments not configured",
                false,
                external_payments(false, true, false, None),
                Unavailable,
                false,
                false,
                false,
            ),
            (
                "allowlisted and opted out, stripe ready",
                true,
                external_payments(true, true, false, named),
                Stripe,
                true,
                false,
                false,
            ),
            (
                "allowlisted and opted out, stripe not ready",
                false,
                external_payments(true, true, false, None),
                Unavailable,
                false,
                true,
                false,
            ),
            (
                "opted in and named, stripe ready",
                true,
                external_payments(true, true, true, named),
                External,
                true,
                false,
                false,
            ),
            (
                "opted in and named, stripe not ready",
                false,
                external_payments(true, true, true, named),
                External,
                true,
                false,
                false,
            ),
            // An opted-in group stays on the external rail even when Stripe is
            // ready, so paid tickets wait on the seller name
            (
                "opted in and nameless, stripe ready",
                true,
                external_payments(true, true, true, None),
                External,
                false,
                false,
                true,
            ),
            (
                "opted in and nameless, stripe not ready",
                false,
                external_payments(true, true, true, None),
                External,
                false,
                false,
                true,
            ),
        ];

        for (case, ready, ctx, mode, available, opt_in, seller_name) in cases {
            assert_eq!(event_ticketing_mode(ready, &ctx), mode, "{case}: mode");
            assert_eq!(
                is_paid_ticketing_available(ready, &ctx),
                available,
                "{case}: available"
            );
            assert_eq!(
                requires_external_payments_opt_in(ready, &ctx),
                opt_in,
                "{case}: opt-in"
            );
            assert_eq!(
                requires_external_payments_seller_name(ready, &ctx),
                seller_name,
                "{case}: seller name"
            );
        }
    }

    // Helpers.

    /// External payments context for the given flags and seller name.
    fn external_payments(
        configured: bool,
        eligible: bool,
        enabled: bool,
        seller_display_name: Option<&str>,
    ) -> GroupExternalPaymentsContext {
        GroupExternalPaymentsContext {
            configured,
            eligible,
            enabled,
            country_code: Some("KR".to_string()),
            default_payment_window_hours: Some(72),
            max_payment_window_hours: Some(336),
            seller_display_name: seller_display_name.map(str::to_string),
        }
    }
}
