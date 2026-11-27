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
    /// Returns the shared form state consumed by the event editor tab partials.
    pub(crate) fn form_state(&self) -> EventFormState<'_> {
        EventFormState {
            can_manage_events: self.can_manage_events,
            external_payments: &self.external_payments,
            group_id: self.group_id,
            payments_ready: self.payments_ready,

            approved_submissions: None,
            cohosts: None,
            existing_event: None,
        }
    }

    /// Returns the event editor tab groups shown on the add page.
    #[allow(clippy::unused_self)]
    pub(crate) fn form_tab_groups(&self) -> Vec<EventFormTabGroup> {
        sections::form_tab_groups(&EventFormMode::Add, EventFormTabFlags::default())
    }
}

/// Shared event editor context consumed by the add and update tab partials.
pub(crate) struct EventFormState<'a> {
    /// Whether the current user can manage events.
    pub can_manage_events: bool,
    /// Group-level external-payments eligibility and window limits.
    pub external_payments: &'a GroupExternalPaymentsContext,
    /// Group identifier owning the event.
    pub group_id: Uuid,
    /// Whether this group can publish paid events.
    pub payments_ready: bool,

    /// Approved CFS submissions for linking sessions when editing an event.
    pub approved_submissions: Option<&'a [ApprovedSubmissionSummary]>,
    /// Current co-hosts when editing an event.
    pub cohosts: Option<&'a EventCohostsEditor>,
    /// Existing event when editing an event.
    pub existing_event: Option<&'a EventFull>,
}

impl<'a> EventFormState<'a> {
    /// Returns whether organizer approval is required before attending.
    pub(crate) fn attendee_approval_required(&self) -> bool {
        self.existing_event
            .is_some_and(|event| event.attendee_approval_required)
    }

    /// Returns whether the current user can award badges on this event.
    pub(crate) fn can_award_badges(&self) -> bool {
        self.existing_event
            .is_some_and(|event| self.can_manage_events && !event.canceled)
    }

    /// Returns whether Call for Speakers is enabled.
    pub(crate) fn cfs_enabled(&self) -> bool {
        self.existing_event
            .and_then(|event| event.cfs_enabled)
            .unwrap_or(false)
    }

    /// Returns whether the co-hosts selector is disabled.
    pub(crate) fn cohosts_disabled(&self) -> bool {
        self.existing_event.map_or(!self.can_manage_events, |event| {
            event.published || self.event_read_only()
        })
    }

    /// Returns the existing short description, if any.
    pub(crate) fn description_short(&self) -> Option<&'a str> {
        self.existing_event
            .and_then(|event| event.description_short.as_deref())
    }

    /// Returns whether the event editor forms are read-only.
    pub(crate) fn event_read_only(&self) -> bool {
        self.existing_event
            .is_some_and(|event| event.canceled || !self.can_manage_events)
    }

    /// Returns whether the 24-hour event reminder email is enabled (defaults to true on add).
    pub(crate) fn event_reminder_enabled(&self) -> bool {
        self.existing_event.is_none_or(EventFull::event_reminder_is_enabled)
    }

    /// Returns the existing external payment instructions, if any.
    pub(crate) fn external_payment_instructions(&self) -> Option<&'a str> {
        self.existing_event
            .and_then(|event| event.external_payment_instructions.as_deref())
    }

    /// Returns the existing external payment URL, if any.
    pub(crate) fn external_payment_url(&self) -> Option<&'a str> {
        self.existing_event
            .and_then(|event| event.external_payment_url.as_deref())
    }

    /// Returns whether the external payment URL input is disabled.
    pub(crate) fn external_payment_url_disabled(&self) -> bool {
        self.event_read_only() || (self.ticketing_read_only() && self.uses_external_ticketing())
    }

    /// Returns the existing external payment window in hours, if any.
    pub(crate) fn external_payment_window_hours(&self) -> Option<i32> {
        self.existing_event
            .and_then(|event| event.external_payment_window_hours)
    }

    /// Returns true when paid tickets can be configured through Stripe or external payments.
    pub(crate) fn is_paid_ticketing_available(&self) -> bool {
        is_paid_ticketing_available(self.payments_ready, self.external_payments)
    }

    /// Returns true when the provided currency code matches the event currency.
    pub(crate) fn is_selected_payment_currency_code(&self, payment_currency_code: &str) -> bool {
        self.existing_event
            .and_then(|event| event.payment_currency_code.as_deref())
            == Some(payment_currency_code)
    }

    /// Returns the existing Luma URL, if any.
    pub(crate) fn luma_url(&self) -> Option<&'a str> {
        self.existing_event.and_then(|event| event.luma_url.as_deref())
    }

    /// Returns the existing meeting join instructions, if any.
    pub(crate) fn meeting_join_instructions(&self) -> Option<&'a str> {
        self.existing_event
            .and_then(|event| event.meeting_join_instructions.as_deref())
    }

    /// Returns the existing meeting join URL, if any.
    pub(crate) fn meeting_join_url(&self) -> Option<&'a str> {
        self.existing_event
            .and_then(|event| event.meeting_join_url.as_deref())
    }

    /// Returns whether the final public recording URL is published publicly.
    pub(crate) fn meeting_recording_published(&self) -> bool {
        self.existing_event
            .and_then(|event| event.meeting_recording_published)
            .unwrap_or(false)
    }

    /// Returns the existing final public recording URL, if any.
    pub(crate) fn meeting_recording_url(&self) -> Option<&'a str> {
        self.existing_event
            .and_then(|event| event.meeting_recording_url.as_deref())
    }

    /// Returns the existing Meetup.com URL, if any.
    pub(crate) fn meetup_url(&self) -> Option<&'a str> {
        self.existing_event.and_then(|event| event.meetup_url.as_deref())
    }

    /// Returns whether paid ticket settings are read-only due to missing rail setup.
    pub(crate) fn paid_ticketing_read_only(&self) -> bool {
        self.existing_event.is_some_and(|event| {
            !self.is_paid_ticketing_available()
                && event.is_paid_capable()
                && event.external_payment_url.is_none()
        })
    }

    /// Returns whether registration questions are locked because answers exist.
    pub(crate) fn registration_questions_locked(&self) -> bool {
        self.existing_event
            .is_some_and(|event| event.registration_questions_locked)
    }

    /// Returns true when paid tickets wait only on the group's external-payments opt-in.
    pub(crate) fn requires_external_payments_opt_in(&self) -> bool {
        requires_external_payments_opt_in(self.payments_ready, self.external_payments)
    }

    /// Returns true when paid tickets wait only on the external payee legal name.
    pub(crate) fn requires_external_payments_seller_name(&self) -> bool {
        requires_external_payments_seller_name(self.payments_ready, self.external_payments)
    }

    /// Returns whether external-ticketing fields should be rendered.
    pub(crate) fn show_external_ticketing(&self) -> bool {
        self.uses_external_ticketing()
            || self
                .existing_event
                .is_some_and(|event| event.external_payment_url.is_some())
    }

    /// Returns whether paid ticketing settings and discount codes should be rendered.
    pub(crate) fn show_paid_ticketing_settings(&self) -> bool {
        self.is_paid_ticketing_available()
            || self.existing_event.is_some_and(EventFull::is_paid_capable)
    }

    /// Returns whether this event is marked as a test event.
    pub(crate) fn test_event(&self) -> bool {
        self.existing_event.is_some_and(|event| event.test_event)
    }

    /// Returns whether ticket prices are restricted to free tiers only.
    pub(crate) fn ticketing_free_only(&self) -> bool {
        !self.show_paid_ticketing_settings()
    }

    /// Returns whether ticket and discount controls are read-only.
    pub(crate) fn ticketing_read_only(&self) -> bool {
        self.event_read_only() || self.paid_ticketing_read_only()
    }

    /// Returns whether tax is added to the configured ticket price.
    pub(crate) fn uses_exclusive_ticket_tax(&self) -> bool {
        self.existing_event
            .is_some_and(|event| event.tax_behavior == TicketTaxBehavior::Exclusive)
    }

    /// Returns true when the group currently collects paid tickets outside the platform.
    pub(crate) fn uses_external_ticketing(&self) -> bool {
        matches!(
            event_ticketing_mode(self.payments_ready, self.external_payments),
            EventTicketingMode::External
        )
    }

    /// Returns whether the event uses manual Stripe Tax Rates.
    pub(crate) fn uses_manual_ticket_tax(&self) -> bool {
        self.existing_event
            .is_some_and(|event| event.tax_calculation_mode == TicketTaxCalculationMode::Manual)
    }

    /// Returns whether the event does not collect ticket tax.
    pub(crate) fn uses_no_ticket_tax(&self) -> bool {
        self.existing_event
            .is_some_and(|event| event.tax_calculation_mode == TicketTaxCalculationMode::None)
    }

    /// Returns whether the event waitlist is enabled.
    pub(crate) fn waitlist_enabled(&self) -> bool {
        self.existing_event.is_some_and(|event| event.waitlist_enabled)
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
    /// Returns the shared form state consumed by the event editor tab partials.
    pub(crate) fn form_state(&self) -> EventFormState<'_> {
        EventFormState {
            can_manage_events: self.can_manage_events,
            external_payments: &self.external_payments,
            group_id: self.event.group.group_id,
            payments_ready: self.payments_ready,

            approved_submissions: Some(&self.approved_submissions),
            cohosts: Some(&self.cohosts),
            existing_event: Some(&self.event),
        }
    }

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

    /// Returns the number of co-hosts that have not responded yet.
    pub(crate) fn pending_cohosts_count(&self) -> usize {
        self.cohosts.pending_count()
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
mod tests;
