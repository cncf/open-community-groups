//! Group dashboard event types.

use chrono::{DateTime, NaiveDateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    types::{
        dashboard,
        event::{EventCfsLabel, EventCohostStatus, EventSummary, SessionKind},
        meetings::MeetingProvider,
        pagination::{Pagination, ToRawQuery},
        payments::{
            EventDiscountType, EventTicketTypeAvailability, TicketTaxBehavior,
            TicketTaxCalculationMode, TicketVenue,
        },
        questionnaire::QuestionnaireQuestion,
    },
    validation::{
        MAX_EVENT_COHOSTS, MAX_EVENT_LABELS_PER_EVENT, MAX_LEN_COUNTRY_CODE, MAX_LEN_DESCRIPTION,
        MAX_LEN_DESCRIPTION_SHORT, MAX_LEN_ENTITY_NAME, MAX_LEN_L, MAX_LEN_S, MAX_LEN_TIMEZONE,
        MAX_PAGINATION_LIMIT, MAX_RECURRING_ADDITIONAL_OCCURRENCES, email_vec, image_url_opt,
        trimmed_non_empty, trimmed_non_empty_opt, trimmed_non_empty_tag_vec, trimmed_non_empty_vec,
        valid_latitude, valid_longitude, web_url_opt,
    },
};

#[cfg(test)]
mod tests;

/// Approved CFS submission summary for linking sessions.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct ApprovedSubmissionSummary {
    /// Submission identifier.
    pub cfs_submission_id: Uuid,
    /// Session proposal identifier.
    pub session_proposal_id: Uuid,
    /// Speaker display name.
    pub speaker_name: String,
    /// Submission title.
    pub title: String,
}

/// CFS submission status option.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct CfsSubmissionStatus {
    /// Submission status identifier.
    pub cfs_submission_status_id: String,
    /// Display name.
    pub display_name: String,
}

/// Co-hosts selection submitted by the event editor.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct CohostsUpdate {
    /// Co-hosts revision the editor loaded.
    pub expected_revision: i32,
    /// Groups that should co-host the event.
    pub group_ids: Vec<Uuid>,
}

/// Dashboard discount code payload.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct DiscountCodeInput {
    /// Whether the code is currently enabled.
    #[garde(skip)]
    pub active: bool,
    /// Discount code entered by attendees.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_S))]
    pub code: String,
    /// Type of discount to apply.
    #[garde(skip)]
    pub kind: EventDiscountType,
    /// Display title shown in the dashboard.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_ENTITY_NAME))]
    pub title: String,

    /// Number of redemptions still available.
    #[garde(range(min = 0))]
    pub available: Option<i32>,
    /// Whether Uses remaining should stay in manual override mode.
    #[garde(skip)]
    pub available_override_active: Option<bool>,
    /// Whether clearing Uses remaining should remove the manual override.
    #[garde(skip)]
    pub available_cleared: Option<bool>,
    /// Fixed amount discount in minor units.
    #[garde(skip)]
    pub amount_minor: Option<i64>,
    /// Last date and time when the code can be used.
    #[serde(default)]
    #[garde(skip)]
    pub ends_at: Option<DateTime<Utc>>,
    /// Unique identifier for the discount code.
    #[garde(skip)]
    pub event_discount_code_id: Option<Uuid>,
    /// Percentage discount to apply.
    #[garde(range(min = 1, max = 100))]
    pub percentage: Option<i32>,
    /// First date and time when the code can be used.
    #[serde(default)]
    #[garde(skip)]
    pub starts_at: Option<DateTime<Utc>>,
    /// Maximum number of redemptions allowed.
    #[garde(range(min = 0))]
    pub total_available: Option<i32>,
}

/// Event management action scope requested by the dashboard.
#[derive(Debug, Clone, Copy, Default, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum EventActionScope {
    /// Apply the action to the linked event series.
    Series,
    /// Apply the action only to the selected event.
    #[default]
    This,
}

/// Current co-host of an event shown in the owner's editor.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventCohostInvitation {
    /// Human-readable display name of the co-host group's community.
    pub community_display_name: String,
    /// Name of the co-host group's community (slug for URLs).
    pub community_name: String,
    /// Whether the co-host group is still active.
    pub group_active: bool,
    /// Co-host group identifier.
    pub group_id: Uuid,
    /// Current invitation identifier.
    pub invitation_id: Uuid,
    /// When the current invitation was sent.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub invited_at: DateTime<Utc>,
    /// URL to the co-host group's logo, falling back to its community logo.
    pub logo_url: String,
    /// Co-host group display name.
    pub name: String,
    /// Generated URL-friendly identifier for the co-host group.
    pub slug: String,
    /// Current co-hosting status (pending or approved).
    pub status: EventCohostStatus,

    /// Admin-managed URL-friendly identifier for the co-host group.
    pub slug_pretty: Option<String>,
}

/// Co-hosts state loaded by the owner's event editor.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct EventCohostsEditor {
    /// Current pending and approved co-hosts.
    pub cohosts: Vec<EventCohostInvitation>,
    /// Co-hosts revision used to detect concurrent changes.
    pub revision: i32,
}

impl EventCohostsEditor {
    /// Returns the number of co-hosts that have not responded yet.
    pub(crate) fn pending_count(&self) -> usize {
        self.cohosts
            .iter()
            .filter(|cohost| cohost.status == EventCohostStatus::Pending)
            .count()
    }
}

/// Event details for dashboard management.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Default, Validate)]
pub(crate) struct EventInput {
    /// Category this event belongs to.
    #[garde(skip)]
    pub category_id: Uuid,
    /// Call for speakers labels.
    #[serde(default)]
    #[garde(length(max = MAX_EVENT_LABELS_PER_EVENT), dive)]
    pub cfs_labels: Vec<EventCfsLabel>,
    /// Event description.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DESCRIPTION))]
    pub description: String,
    /// Type of event (in-person, virtual, hybrid).
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_S))]
    pub kind_id: String,
    /// Event name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_ENTITY_NAME))]
    pub name: String,
    /// Registration questions shown to attendees before registration completes.
    #[serde(default)]
    #[garde(dive)]
    pub registration_questions: Vec<QuestionnaireQuestion>,
    /// Timezone for the event.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_TIMEZONE))]
    pub timezone: String,

    /// Whether attendee requests require organizer approval.
    #[garde(skip)]
    pub attendee_approval_required: Option<bool>,
    /// URL to the event banner image optimized for mobile devices.
    #[garde(custom(image_url_opt))]
    pub banner_mobile_url: Option<String>,
    /// Banner image URL.
    #[garde(custom(image_url_opt))]
    pub banner_url: Option<String>,
    /// Maximum capacity for the event.
    #[garde(range(min = 0))]
    pub capacity: Option<i32>,
    /// Call for speakers description.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION))]
    pub cfs_description: Option<String>,
    /// Whether call for speakers is enabled.
    #[garde(skip)]
    pub cfs_enabled: Option<bool>,
    /// Call for speakers end time.
    #[garde(skip)]
    pub cfs_ends_at: Option<NaiveDateTime>,
    /// Call for speakers start time.
    #[garde(skip)]
    pub cfs_starts_at: Option<NaiveDateTime>,
    /// Groups selected as co-hosts of the event.
    #[garde(length(max = MAX_EVENT_COHOSTS))]
    pub cohost_group_ids: Option<Vec<Uuid>>,
    /// Whether the co-hosts selection was changed and submitted.
    #[garde(skip)]
    pub cohost_group_ids_present: Option<bool>,
    /// Co-hosts revision loaded by the editor.
    #[garde(skip)]
    pub cohosts_revision: Option<i32>,
    /// Short description of the event.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub description_short: Option<String>,
    /// Discount codes configured for the event.
    #[garde(dive)]
    pub discount_codes: Option<Vec<DiscountCodeInput>>,
    /// Whether the discount codes section was submitted.
    #[garde(skip)]
    pub discount_codes_present: Option<bool>,
    /// Event end time.
    #[garde(skip)]
    pub ends_at: Option<NaiveDateTime>,
    /// Whether event reminder notifications are enabled.
    #[garde(skip)]
    pub event_reminder_enabled: Option<bool>,
    /// Organizer-supplied instructions for paying outside the platform.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub external_payment_instructions: Option<String>,
    /// Whether the payment instructions field was submitted.
    #[garde(skip)]
    pub external_payment_instructions_present: Option<bool>,
    /// External payment URL required for paid events in external mode.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub external_payment_url: Option<String>,
    /// Whether the external payment URL field was submitted.
    #[garde(skip)]
    pub external_payment_url_present: Option<bool>,
    /// Organizer-confirmation window in hours for external payments.
    #[garde(range(min = 1))]
    pub external_payment_window_hours: Option<i32>,
    /// Whether the payment window field was submitted.
    #[garde(skip)]
    pub external_payment_window_hours_present: Option<bool>,
    /// User IDs of event hosts.
    #[garde(skip)]
    pub hosts: Option<Vec<Uuid>>,
    /// Latitude coordinate of the event location.
    #[garde(custom(valid_latitude))]
    pub latitude: Option<f64>,
    /// Longitude coordinate of the event location.
    #[garde(custom(valid_longitude))]
    pub longitude: Option<f64>,
    /// URL to the event logo.
    #[garde(custom(image_url_opt))]
    pub logo_url: Option<String>,
    /// Luma URL.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub luma_url: Option<String>,
    /// Stripe Tax Rate identifiers selected for manual tax.
    #[serde(default)]
    #[garde(custom(trimmed_non_empty_vec))]
    pub manual_tax_rate_ids: Option<Vec<String>>,
    /// Whether the manual Tax Rate selection was submitted.
    #[garde(skip)]
    pub manual_tax_rate_ids_present: Option<bool>,
    /// Meeting hosts to synchronize with provider (email addresses).
    #[garde(custom(email_vec))]
    pub meeting_hosts: Option<Vec<String>>,
    /// Extra instructions attendees need to join the event meeting.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub meeting_join_instructions: Option<String>,
    /// URL to join the meeting.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub meeting_join_url: Option<String>,
    /// Desired meeting provider.
    #[serde(rename = "meeting_provider_id")]
    #[garde(skip)]
    pub meeting_provider: Option<MeetingProvider>,
    /// Whether the recording is publicly visible.
    #[garde(skip)]
    pub meeting_recording_published: Option<bool>,
    /// Whether automatic event meetings should be recorded.
    #[garde(skip)]
    pub meeting_recording_requested: Option<bool>,
    /// Organizer-managed final recording URL for meeting.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub meeting_recording_url: Option<String>,
    /// Whether a meeting has been requested for the event.
    #[garde(skip)]
    pub meeting_requested: Option<bool>,
    /// Meetup.com URL.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub meetup_url: Option<String>,
    /// Currency used for ticket purchases.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub payment_currency_code: Option<String>,
    /// Gallery of photo URLs.
    #[garde(custom(trimmed_non_empty_vec))]
    pub photos_urls: Option<Vec<String>>,
    /// Number of additional occurrences to create for recurring events.
    #[garde(range(min = 1, max = MAX_RECURRING_ADDITIONAL_OCCURRENCES))]
    pub recurrence_additional_occurrences: Option<i32>,
    /// Recurrence pattern selected for new event creation.
    #[garde(skip)]
    pub recurrence_pattern: Option<EventRecurrencePattern>,
    /// Registration end time.
    #[garde(skip)]
    pub registration_ends_at: Option<NaiveDateTime>,
    /// Whether the registration questions section was submitted.
    #[garde(skip)]
    pub registration_questions_present: Option<bool>,
    /// Registration start time.
    #[garde(skip)]
    pub registration_starts_at: Option<NaiveDateTime>,
    /// Event sessions.
    #[garde(dive)]
    pub sessions: Option<Vec<SessionInput>>,
    /// Event-level speakers.
    #[garde(dive)]
    pub speakers: Option<Vec<SpeakerInput>>,
    /// Event sponsors.
    #[garde(dive)]
    pub sponsors: Option<Vec<EventSponsorInput>>,
    /// Event start time.
    #[garde(skip)]
    pub starts_at: Option<NaiveDateTime>,
    /// Tags associated with the event.
    #[garde(custom(trimmed_non_empty_tag_vec))]
    pub tags: Option<Vec<String>>,
    /// Whether ticket prices include tax or have tax added at Checkout.
    #[serde(default)]
    #[garde(skip)]
    pub tax_behavior: TicketTaxBehavior,
    /// Automatic Stripe Tax, manual Stripe rates, or no tax collection.
    #[serde(default)]
    #[garde(skip)]
    pub tax_calculation_mode: TicketTaxCalculationMode,
    /// Whether this event is only for testing.
    #[garde(skip)]
    pub test_event: Option<bool>,
    /// Ticket types configured for the event.
    #[garde(dive)]
    pub ticket_types: Option<Vec<TicketTypeInput>>,
    /// Whether the ticket types section was submitted.
    #[garde(skip)]
    pub ticket_types_present: Option<bool>,
    /// Venue address.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub venue_address: Option<String>,
    /// City where the venue is located.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub venue_city: Option<String>,
    /// ISO country code of the venue's location.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_COUNTRY_CODE))]
    pub venue_country_code: Option<String>,
    /// Full country name of the venue's location.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub venue_country_name: Option<String>,
    /// Name of the venue.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_ENTITY_NAME))]
    pub venue_name: Option<String>,
    /// ISO state or province code of the venue's location.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_COUNTRY_CODE))]
    pub venue_state_code: Option<String>,
    /// Full state or province name of the venue's location.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub venue_state_name: Option<String>,
    /// Venue zip code.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub venue_zip_code: Option<String>,
    /// Whether the event waiting list is enabled.
    #[garde(skip)]
    pub waitlist_enabled: Option<bool>,
}

impl EventInput {
    /// Returns the submitted co-hosts selection, when the editor changed it.
    pub(crate) fn cohosts_update(&self) -> Option<CohostsUpdate> {
        if !self.cohost_group_ids_present.unwrap_or(false) {
            return None;
        }

        Some(CohostsUpdate {
            expected_revision: self.cohosts_revision.unwrap_or(0),
            group_ids: self.cohost_group_ids.clone().unwrap_or_default(),
        })
    }

    /// Returns whether the form selects at least one manual Tax Rate.
    pub(crate) fn has_manual_tax_selection(&self) -> bool {
        self.tax_calculation_mode == TicketTaxCalculationMode::Manual
            && self
                .manual_tax_rate_ids
                .as_ref()
                .is_some_and(|rate_ids| !rate_ids.is_empty())
    }

    /// Builds the provider venue from the submitted venue fields.
    pub(crate) fn ticket_venue(&self) -> TicketVenue {
        TicketVenue {
            address: self.venue_address.clone().unwrap_or_default(),
            city: self.venue_city.clone().unwrap_or_default(),
            country_code: self.venue_country_code.clone().unwrap_or_default(),
            name: self.venue_name.clone().unwrap_or_default(),
            zip_code: self.venue_zip_code.clone().unwrap_or_default(),

            state_code: self.venue_state_code.clone(),
            state_name: self.venue_state_name.clone(),
        }
    }

    /// Converts the dashboard form payload into the JSON shape used by the database.
    pub(crate) fn to_db_payload(&self) -> anyhow::Result<Value> {
        // Serialize the full event form into a mutable JSON object
        let mut payload = match serde_json::to_value(self)? {
            Value::Object(map) => map,
            _ => Map::new(),
        };

        // External payments never use provider tax
        let is_external = self
            .external_payment_url
            .as_deref()
            .is_some_and(|url| !url.trim().is_empty());
        if is_external {
            payload.insert(
                "tax_behavior".to_string(),
                serde_json::to_value(TicketTaxBehavior::Inclusive)?,
            );
            payload.insert(
                "tax_calculation_mode".to_string(),
                serde_json::to_value(TicketTaxCalculationMode::None)?,
            );
        } else if self.tax_calculation_mode == TicketTaxCalculationMode::None {
            payload.insert(
                "tax_behavior".to_string(),
                serde_json::to_value(TicketTaxBehavior::Inclusive)?,
            );
        }

        // Normalize tax fields that do not apply to the selected mode
        if is_external
            || self.tax_calculation_mode != TicketTaxCalculationMode::Manual
            || (self.manual_tax_rate_ids_present.is_some() && self.manual_tax_rate_ids.is_none())
        {
            payload.insert("manual_tax_rate_ids".to_string(), Value::Array(Vec::new()));
        }

        // Assign identifiers to discount codes that do not have one yet
        let mut discount_codes = self.discount_codes.clone();
        if let Some(discount_codes) = discount_codes.as_mut() {
            Self::normalize_discount_codes(discount_codes);
        }

        // Assign identifiers to ticket types and nested price windows
        let mut ticket_types = self.ticket_types.clone();
        if let Some(ticket_types) = ticket_types.as_mut() {
            Self::normalize_ticket_types(ticket_types);
        }

        // Remove co-host fields, which are synchronized separately
        payload.remove("cohost_group_ids");
        payload.remove("cohost_group_ids_present");
        payload.remove("cohosts_revision");

        // Remove ticketing fields so they can be reinserted from submitted inputs
        payload.remove("discount_codes");
        payload.remove("discount_codes_present");
        payload.remove("external_payment_instructions_present");
        payload.remove("external_payment_url_present");
        payload.remove("external_payment_window_hours_present");
        payload.remove("manual_tax_rate_ids_present");
        payload.remove("recurrence_additional_occurrences");
        payload.remove("recurrence_pattern");
        payload.remove("registration_questions");
        payload.remove("registration_questions_present");
        payload.remove("ticket_types");
        payload.remove("ticket_types_present");

        // Distinguish submitted-empty external fields from omitted fields
        if self.external_payment_instructions_present.is_some() {
            payload.insert(
                "external_payment_instructions".to_string(),
                serde_json::to_value(&self.external_payment_instructions)?,
            );
        }
        if self.external_payment_url_present.is_some() {
            payload.insert(
                "external_payment_url".to_string(),
                serde_json::to_value(&self.external_payment_url)?,
            );
        }
        if self.external_payment_window_hours_present.is_some() {
            payload.insert(
                "external_payment_window_hours".to_string(),
                serde_json::to_value(self.external_payment_window_hours)?,
            );
        }

        // Preserve omitted registration questions on partial form submissions,
        // but allow an explicitly submitted empty questions editor to clear them
        if self.registration_questions_present.is_some() {
            payload.insert(
                "registration_questions".to_string(),
                serde_json::to_value(&self.registration_questions)?,
            );
        }

        // Reinsert ticketing sections only when the form submitted those inputs
        Self::insert_optional_ticketing_field(
            &mut payload,
            "discount_codes",
            self.discount_codes_present.is_some(),
            discount_codes,
        )?;
        Self::insert_optional_ticketing_field(
            &mut payload,
            "ticket_types",
            self.ticket_types_present.is_some(),
            ticket_types,
        )?;

        Ok(Value::Object(payload))
    }

    /// Inserts a ticketing field only when it was submitted in the form.
    fn insert_optional_ticketing_field<T: Serialize>(
        payload: &mut Map<String, Value>,
        field_name: &str,
        field_present: bool,
        field_value: Option<T>,
    ) -> anyhow::Result<()> {
        if field_present {
            payload.insert(field_name.to_string(), serde_json::to_value(field_value)?);
        }

        Ok(())
    }

    /// Fills in missing identifiers for newly added discount codes.
    fn normalize_discount_codes(discount_codes: &mut Vec<DiscountCodeInput>) {
        for discount_code in discount_codes {
            if discount_code.event_discount_code_id.is_none() {
                discount_code.event_discount_code_id = Some(Uuid::new_v4());
            }
        }
    }

    /// Fills in missing identifiers for newly added ticketing rows.
    fn normalize_ticket_types(ticket_types: &mut Vec<TicketTypeInput>) {
        for ticket_type in ticket_types {
            if ticket_type.event_ticket_type_id.is_none() {
                ticket_type.event_ticket_type_id = Some(Uuid::new_v4());
            }

            for price_window in &mut ticket_type.price_windows {
                if price_window.event_ticket_price_window_id.is_none() {
                    price_window.event_ticket_price_window_id = Some(Uuid::new_v4());
                }
            }
        }
    }
}

/// Recurrence options supported by the add event flow.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum EventRecurrencePattern {
    /// Create only the event currently described by the form.
    #[default]
    JustOnce,
    /// Create weekly on the same weekday.
    Weekly,
    /// Create every two weeks on the same weekday.
    Biweekly,
    /// Create monthly on the same ordinal weekday.
    Monthly,
}

impl EventRecurrencePattern {
    /// Returns the database value for patterns that create an event series.
    pub(crate) fn recurrence_db_value(self) -> Option<&'static str> {
        match self {
            Self::JustOnce => None,
            Self::Biweekly => Some("biweekly"),
            Self::Monthly => Some("monthly"),
            Self::Weekly => Some("weekly"),
        }
    }
}

/// Event sponsor information.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub struct EventSponsorInput {
    /// Group sponsor identifier.
    #[garde(skip)]
    pub group_sponsor_id: Uuid,
    /// Sponsor level for this event.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_S))]
    pub level: String,
}

/// Filter parameters for events list pagination.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct EventsListFilters {
    /// Selected events tab.
    #[garde(skip)]
    pub events_tab: Option<EventsTab>,
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(min = 1, max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for past events.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub past_offset: Option<usize>,
    /// Pagination offset for upcoming events.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub upcoming_offset: Option<usize>,
}

impl EventsListFilters {
    /// Current tab or default.
    pub(crate) fn current_tab(&self) -> EventsTab {
        self.events_tab.clone().unwrap_or_default()
    }
}

impl Pagination for EventsListFilters {
    fn limit(&self) -> Option<usize> {
        self.limit
    }

    fn offset(&self) -> Option<usize> {
        match self.current_tab() {
            EventsTab::Past => self.past_offset,
            EventsTab::Upcoming => self.upcoming_offset,
        }
    }

    fn set_offset(&mut self, offset: Option<usize>) {
        match self.current_tab() {
            EventsTab::Past => {
                self.past_offset = offset;
            }
            EventsTab::Upcoming => {
                self.upcoming_offset = offset;
            }
        }
    }
}

crate::impl_to_raw_query!(EventsListFilters);

/// Tab selection for the events list.
#[derive(
    Debug, Clone, Default, PartialEq, Serialize, Deserialize, strum::Display, strum::EnumString,
)]
#[serde(rename_all = "lowercase")]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum EventsTab {
    /// Past events tab (default).
    Past,
    /// Upcoming events tab.
    #[default]
    Upcoming,
}

/// Group events separated by status.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupEvents {
    /// Events that already happened.
    pub past: PaginatedEvents,
    /// Events happening in the future.
    pub upcoming: PaginatedEvents,
}

/// Events list with pagination metadata.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct PaginatedEvents {
    /// List of events for this section.
    pub events: Vec<EventSummary>,
    /// Total number of events for this section.
    pub total: usize,
}

/// Session details within an event.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct SessionInput {
    /// Type of session (hybrid, in-person, virtual).
    #[garde(skip)]
    pub kind: SessionKind,
    /// Session name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_ENTITY_NAME))]
    pub name: String,
    /// Unique identifier for the session.
    #[garde(skip)]
    pub session_id: Option<Uuid>,
    /// Session start time.
    #[garde(skip)]
    pub starts_at: NaiveDateTime,

    /// Linked CFS submission identifier.
    #[garde(skip)]
    pub cfs_submission_id: Option<Uuid>,
    /// Session description.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION))]
    pub description: Option<String>,
    /// Session end time.
    #[garde(skip)]
    pub ends_at: Option<NaiveDateTime>,
    /// Location for the session.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub location: Option<String>,
    /// Meeting hosts to synchronize with provider (email addresses).
    #[garde(custom(email_vec))]
    pub meeting_hosts: Option<Vec<String>>,
    /// Extra instructions attendees need to join the session meeting.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub meeting_join_instructions: Option<String>,
    /// URL to join the meeting.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub meeting_join_url: Option<String>,
    /// Desired meeting provider.
    #[serde(rename = "meeting_provider_id")]
    #[garde(skip)]
    pub meeting_provider: Option<MeetingProvider>,
    /// Whether the recording is publicly visible.
    #[garde(skip)]
    pub meeting_recording_published: Option<bool>,
    /// Organizer-managed final recording URL for meeting.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub meeting_recording_url: Option<String>,
    /// Whether a meeting has been requested for the session.
    #[garde(skip)]
    pub meeting_requested: Option<bool>,
    /// Session speakers.
    #[garde(dive)]
    pub speakers: Option<Vec<SpeakerInput>>,
}

/// Speaker selection with optional featured flag.
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct SpeakerInput {
    /// Whether the speaker is featured.
    #[serde(default)]
    #[garde(skip)]
    pub featured: bool,
    /// Unique identifier for the speaker.
    #[garde(skip)]
    pub user_id: Uuid,
}

/// Dashboard ticket price window payload.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct TicketPriceWindowInput {
    /// Price in minor units.
    #[garde(skip)]
    pub amount_minor: i64,

    /// Window end date and time.
    #[serde(default)]
    #[garde(skip)]
    pub ends_at: Option<DateTime<Utc>>,
    /// Unique identifier for the price window.
    #[garde(skip)]
    pub event_ticket_price_window_id: Option<Uuid>,
    /// Window start date and time.
    #[serde(default)]
    #[garde(skip)]
    pub starts_at: Option<DateTime<Utc>>,
}

/// Dashboard ticket type payload.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct TicketTypeInput {
    /// Whether the ticket type can currently be selected.
    #[garde(skip)]
    pub active: bool,
    /// Whether the ticket type is publicly discoverable or invitation-only.
    #[serde(default)]
    #[garde(skip)]
    pub availability: EventTicketTypeAvailability,
    /// Display order in event pages and forms.
    #[garde(range(min = 1))]
    pub order: i32,
    /// Price windows configured for this ticket type.
    #[serde(default)]
    #[garde(dive)]
    pub price_windows: Vec<TicketPriceWindowInput>,
    /// Ticket type display name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_ENTITY_NAME))]
    pub title: String,

    /// Optional subtitle shown in forms and event pages.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub description: Option<String>,
    /// Unique identifier for the ticket type.
    #[garde(skip)]
    pub event_ticket_type_id: Option<Uuid>,
    /// Total seats available for this ticket type.
    #[garde(range(min = 0))]
    pub seats_total: Option<i32>,
}
