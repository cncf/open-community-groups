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
        event::{EventCfsLabel, EventSummary, SessionKind},
        meetings::MeetingProvider,
        pagination::{Pagination, ToRawQuery},
        payments::{
            EventDiscountType, EventTicketTypeAvailability, TicketTaxBehavior,
            TicketTaxCalculationMode, TicketVenue,
        },
        questionnaire::QuestionnaireQuestion,
    },
    validation::{
        MAX_EVENT_LABELS_PER_EVENT, MAX_LEN_COUNTRY_CODE, MAX_LEN_DESCRIPTION,
        MAX_LEN_DESCRIPTION_SHORT, MAX_LEN_ENTITY_NAME, MAX_LEN_L, MAX_LEN_S, MAX_LEN_TIMEZONE,
        MAX_PAGINATION_LIMIT, MAX_RECURRING_ADDITIONAL_OCCURRENCES, email_vec, image_url_opt,
        trimmed_non_empty, trimmed_non_empty_opt, trimmed_non_empty_tag_vec, trimmed_non_empty_vec,
        valid_latitude, valid_longitude, web_url_opt,
    },
};

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

#[cfg(test)]
mod tests {
    use serde_json::Value;

    use crate::types::payments::{
        EventDiscountType, EventTicketTypeAvailability, TicketTaxBehavior, TicketTaxCalculationMode,
    };

    use super::{DiscountCodeInput, EventInput, TicketPriceWindowInput, TicketTypeInput};

    #[test]
    fn discount_code_deserialization_keeps_explicit_availability_override_signals() {
        let discount_code: DiscountCodeInput = serde_qs::from_str(
            "active=true&available=12&available_override_active=true&code=EARLY20&kind=percentage&percentage=20&title=Early%20supporter",
        )
        .unwrap();

        assert_eq!(discount_code.available, Some(12));
        assert_eq!(discount_code.available_override_active, Some(true));
    }

    #[test]
    fn event_deserialization_accepts_nested_registration_questions() {
        let event: EventInput = serde_qs::from_str(
            "\
category_id=00000000-0000-0000-0000-000000000001&\
description=Event%20description&\
kind_id=virtual&\
name=Sample%20Event&\
timezone=UTC&\
registration_questions_present=true&\
registration_questions[0][id]=00000000-0000-0000-0000-000000000101&\
registration_questions[0][kind]=single-select&\
registration_questions[0][prompt]=Meal%20preference&\
registration_questions[0][required]=true&\
registration_questions[0][options][0][id]=00000000-0000-0000-0000-000000000201&\
registration_questions[0][options][0][label]=Vegetarian",
        )
        .unwrap();

        assert!(event.registration_questions_present.is_some());
        assert_eq!(event.registration_questions.len(), 1);
        assert_eq!(event.registration_questions[0].prompt, "Meal preference");
        assert_eq!(
            event.registration_questions[0].options[0].label,
            "Vegetarian"
        );
    }

    #[test]
    fn event_deserialization_tracks_empty_manual_tax_rate_selection() {
        let event: EventInput = serde_qs::from_str(
            "\
category_id=00000000-0000-0000-0000-000000000001&\
description=Event%20description&\
kind_id=virtual&\
manual_tax_rate_ids_present=true&\
name=Sample%20Event&\
tax_calculation_mode=manual&\
timezone=UTC",
        )
        .unwrap();

        assert!(event.manual_tax_rate_ids.is_none());
        assert_eq!(event.manual_tax_rate_ids_present, Some(true));
        assert_eq!(event.tax_calculation_mode, TicketTaxCalculationMode::Manual);
    }

    #[test]
    fn to_db_payload_clears_submitted_empty_external_payment_fields() {
        let mut event = sample_event();
        event.external_payment_instructions_present = Some(true);
        event.external_payment_url_present = Some(true);
        event.external_payment_window_hours_present = Some(true);

        let payload = event.to_db_payload().unwrap();

        assert_eq!(payload["external_payment_instructions"], Value::Null);
        assert_eq!(payload["external_payment_url"], Value::Null);
        assert_eq!(payload["external_payment_window_hours"], Value::Null);
        assert!(payload.get("external_payment_instructions_present").is_none());
        assert!(payload.get("external_payment_url_present").is_none());
        assert!(payload.get("external_payment_window_hours_present").is_none());
    }

    #[test]
    fn to_db_payload_clears_submitted_empty_manual_tax_rate_selection() {
        let mut event = sample_event();
        event.manual_tax_rate_ids_present = Some(true);
        event.tax_calculation_mode = TicketTaxCalculationMode::Manual;

        let payload = event.to_db_payload().unwrap();

        assert_eq!(payload["manual_tax_rate_ids"], serde_json::json!([]));
        assert!(payload.get("manual_tax_rate_ids_present").is_none());
    }

    #[test]
    fn to_db_payload_keeps_optional_section_keys_omitted_when_form_omits_inputs() {
        let payload = sample_event().to_db_payload().unwrap();

        assert_eq!(payload["cfs_labels"], Value::Array(Vec::new()));
        assert_eq!(payload["description"], "Event description");
        assert_eq!(payload["kind_id"], "virtual");
        assert_eq!(payload["name"], "Sample Event");
        assert_eq!(payload["timezone"], "UTC");
        assert!(payload.get("discount_codes").is_none());
        assert!(payload.get("external_payment_instructions").is_none());
        assert!(payload.get("external_payment_url").is_none());
        assert!(payload.get("external_payment_window_hours").is_none());
        assert!(payload.get("registration_questions").is_none());
        assert!(payload.get("ticket_types").is_none());
    }

    #[test]
    fn to_db_payload_keeps_manual_tax_rate_ids() {
        let mut event = sample_event();
        event.manual_tax_rate_ids = Some(vec!["txr_state".to_string(), "txr_local".to_string()]);
        event.manual_tax_rate_ids_present = Some(true);
        event.tax_behavior = TicketTaxBehavior::Exclusive;
        event.tax_calculation_mode = TicketTaxCalculationMode::Manual;

        let payload = event.to_db_payload().unwrap();

        assert_eq!(
            payload["manual_tax_rate_ids"],
            serde_json::json!(["txr_state", "txr_local"])
        );
        assert!(payload.get("manual_tax_rate_ids_present").is_none());
        assert_eq!(payload["tax_behavior"], "exclusive");
        assert_eq!(payload["tax_calculation_mode"], "manual");
    }

    #[test]
    fn to_db_payload_keeps_omitted_manual_tax_rate_selection_absent() {
        let mut event = sample_event();
        event.tax_calculation_mode = TicketTaxCalculationMode::Manual;

        let payload = event.to_db_payload().unwrap();

        assert!(payload.get("manual_tax_rate_ids").is_none());
        assert!(payload.get("manual_tax_rate_ids_present").is_none());
    }

    #[test]
    fn to_db_payload_normalizes_external_event_tax() {
        let mut event = sample_event();
        event.external_payment_url = Some("https://pay.example.test/add".to_string());
        event.manual_tax_rate_ids = Some(vec!["txr_stale".to_string()]);
        event.tax_behavior = TicketTaxBehavior::Exclusive;
        event.tax_calculation_mode = TicketTaxCalculationMode::Automatic;

        let payload = event.to_db_payload().unwrap();

        assert_eq!(payload["manual_tax_rate_ids"], serde_json::json!([]));
        assert_eq!(payload["tax_behavior"], "inclusive");
        assert_eq!(payload["tax_calculation_mode"], "none");
    }

    #[test]
    fn to_db_payload_normalizes_no_tax_configuration() {
        let mut event = sample_event();
        event.manual_tax_rate_ids = Some(vec!["txr_stale".to_string()]);
        event.tax_behavior = TicketTaxBehavior::Exclusive;
        event.tax_calculation_mode = TicketTaxCalculationMode::None;

        let payload = event.to_db_payload().unwrap();

        assert_eq!(payload["manual_tax_rate_ids"], serde_json::json!([]));
        assert_eq!(payload["tax_behavior"], "inclusive");
        assert_eq!(payload["tax_calculation_mode"], "none");
    }

    #[test]
    fn to_db_payload_includes_empty_registration_questions_when_inputs_are_present() {
        let mut event = sample_event();
        event.registration_questions_present = Some(true);

        let payload = event.to_db_payload().unwrap();

        assert_eq!(payload["registration_questions"], Value::Array(Vec::new()));
    }

    #[test]
    fn to_db_payload_sets_ticketing_keys_to_null_when_inputs_are_present_but_empty() {
        let mut event = sample_event();
        event.discount_codes_present = Some(true);
        event.ticket_types_present = Some(true);

        let payload = event.to_db_payload().unwrap();

        assert_eq!(payload["discount_codes"], Value::Null);
        assert_eq!(payload["ticket_types"], Value::Null);
    }

    #[test]
    fn to_db_payload_accepts_new_ticketing_rows_without_ids() {
        let mut event = sample_event();
        event.discount_codes = Some(vec![DiscountCodeInput {
            active: true,
            code: "EARLY20".to_string(),
            kind: EventDiscountType::Percentage,
            title: "Early supporter".to_string(),

            available: None,
            available_override_active: None,
            available_cleared: None,
            amount_minor: None,
            ends_at: None,
            event_discount_code_id: None,
            percentage: Some(20),
            starts_at: None,
            total_available: None,
        }]);
        event.discount_codes_present = Some(true);
        event.ticket_types = Some(vec![TicketTypeInput {
            active: true,
            availability: EventTicketTypeAvailability::InvitationOnly,
            order: 1,
            price_windows: vec![TicketPriceWindowInput {
                amount_minor: 2500,

                ends_at: None,
                event_ticket_price_window_id: None,
                starts_at: None,
            }],
            title: "General admission".to_string(),

            description: None,
            event_ticket_type_id: None,
            seats_total: Some(100),
        }]);
        event.ticket_types_present = Some(true);

        let payload = event.to_db_payload().unwrap();

        assert_eq!(payload["discount_codes"][0]["code"], "EARLY20");
        assert!(
            uuid::Uuid::parse_str(
                payload["discount_codes"][0]["event_discount_code_id"]
                    .as_str()
                    .unwrap()
            )
            .is_ok()
        );
        assert_eq!(payload["ticket_types"][0]["title"], "General admission");
        assert_eq!(
            payload["ticket_types"][0]["availability"],
            "invitation_only"
        );
        assert!(
            uuid::Uuid::parse_str(
                payload["ticket_types"][0]["event_ticket_type_id"].as_str().unwrap()
            )
            .is_ok()
        );
        assert!(
            uuid::Uuid::parse_str(
                payload["ticket_types"][0]["price_windows"][0]["event_ticket_price_window_id"]
                    .as_str()
                    .unwrap()
            )
            .is_ok()
        );
    }

    #[test]
    fn to_db_payload_keeps_explicit_discount_availability_override_state() {
        let mut event = sample_event();
        event.discount_codes = Some(vec![DiscountCodeInput {
            active: true,
            code: "EARLY20".to_string(),
            kind: EventDiscountType::Percentage,
            title: "Early supporter".to_string(),

            available: None,
            available_override_active: Some(true),
            available_cleared: None,
            amount_minor: None,
            ends_at: None,
            event_discount_code_id: None,
            percentage: Some(20),
            starts_at: None,
            total_available: Some(50),
        }]);
        event.discount_codes_present = Some(true);

        let payload = event.to_db_payload().unwrap();

        assert!(payload["discount_codes"][0].get("available").is_none());
        assert_eq!(
            payload["discount_codes"][0]["available_override_active"],
            Value::Bool(true)
        );
    }

    #[test]
    fn to_db_payload_omits_discount_availability_override_state_when_form_omits_it() {
        let mut event = sample_event();
        event.discount_codes = Some(vec![DiscountCodeInput {
            active: true,
            code: "EARLY20".to_string(),
            kind: EventDiscountType::Percentage,
            title: "Early supporter".to_string(),

            available: None,
            available_override_active: None,
            available_cleared: None,
            amount_minor: None,
            ends_at: None,
            event_discount_code_id: None,
            percentage: Some(20),
            starts_at: None,
            total_available: Some(50),
        }]);
        event.discount_codes_present = Some(true);

        let payload = event.to_db_payload().unwrap();

        assert!(
            payload["discount_codes"][0]
                .get("available_override_active")
                .is_none()
        );
    }

    // Helpers.

    /// Creates a sample event with required fields for testing.
    fn sample_event() -> EventInput {
        EventInput {
            category_id: uuid::Uuid::new_v4(),
            description: "Event description".to_string(),
            kind_id: "virtual".to_string(),
            name: "Sample Event".to_string(),
            timezone: "UTC".to_string(),
            ..EventInput::default()
        }
    }
}
