//! Templates and types for managing events in the group dashboard.

use std::collections::HashMap;

use askama::Template;
use chrono::{DateTime, NaiveDateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    services::meetings::MeetingProvider,
    templates::{dashboard, filters, helpers::DATE_FORMAT},
    types::{
        event::{
            EventCategory, EventCfsLabel, EventFull, EventKindSummary, EventSummary, SessionKind,
            SessionKindSummary,
        },
        group::GroupSponsor,
        pagination::{self, Pagination, ToRawQuery},
        payments::EventDiscountType,
    },
    validation::{
        MAX_LEN_COUNTRY_CODE, MAX_LEN_DESCRIPTION, MAX_LEN_DESCRIPTION_SHORT, MAX_LEN_ENTITY_NAME,
        MAX_LEN_EVENT_LABELS_PER_EVENT, MAX_LEN_L, MAX_LEN_S, MAX_LEN_TIMEZONE, MAX_PAGINATION_LIMIT,
        email_vec, image_url_opt, trimmed_non_empty, trimmed_non_empty_opt, trimmed_non_empty_tag_vec,
        trimmed_non_empty_vec, valid_latitude, valid_longitude,
    },
};

// Pages templates.

/// Add event page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/events_add.html")]
#[allow(clippy::struct_excessive_bools)]
pub(crate) struct AddPage {
    /// Whether the current user can manage events.
    pub can_manage_events: bool,
    /// List of available event categories.
    pub categories: Vec<EventCategory>,
    /// List of available event kinds.
    pub event_kinds: Vec<EventKindSummary>,
    /// Group identifier.
    pub group_id: Uuid,
    /// Flag indicating if meetings functionality is enabled.
    pub meetings_enabled: bool,
    /// Maximum participants per meeting provider.
    pub meetings_max_participants: HashMap<MeetingProvider, i32>,
    /// Whether payments are globally enabled.
    pub payments_enabled: bool,
    /// Whether this group can publish paid events.
    pub payments_ready: bool,
    /// List of available session kinds.
    pub session_kinds: Vec<SessionKindSummary>,
    /// List of sponsors available for this group.
    pub sponsors: Vec<GroupSponsor>,
    /// List of available timezones.
    pub timezones: Vec<String>,
}

/// List events page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
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

    /// Number of results per page.
    pub limit: Option<usize>,
    /// Pagination offset for past events.
    pub past_offset: Option<usize>,
    /// Pagination offset for upcoming events.
    pub upcoming_offset: Option<usize>,
}

/// Update event page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
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
    /// Group identifier.
    pub group_id: Uuid,
    /// Flag indicating if meetings functionality is enabled.
    pub meetings_enabled: bool,
    /// Maximum participants per meeting provider.
    pub meetings_max_participants: HashMap<MeetingProvider, i32>,
    /// Whether payments are globally enabled.
    pub payments_enabled: bool,
    /// Whether this group can publish paid events.
    pub payments_ready: bool,
    /// List of available session kinds.
    pub session_kinds: Vec<SessionKindSummary>,
    /// List of sponsors available for this group.
    pub sponsors: Vec<GroupSponsor>,
    /// List of available timezones.
    pub timezones: Vec<String>,
}

// Types.

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
pub(crate) struct DiscountCode {
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

/// Event details for dashboard management.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Default, Validate)]
pub(crate) struct Event {
    /// Category this event belongs to.
    #[garde(skip)]
    pub category_id: Uuid,
    /// Call for speakers labels.
    #[serde(default)]
    #[garde(length(max = MAX_LEN_EVENT_LABELS_PER_EVENT), dive)]
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
    /// Timezone for the event.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_TIMEZONE))]
    pub timezone: String,

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
    /// Whether ticketing should be removed from an existing event.
    #[garde(skip)]
    pub clear_ticketing: Option<bool>,
    /// Short description of the event.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub description_short: Option<String>,
    /// Discount codes configured for the event.
    #[garde(dive)]
    pub discount_codes: Option<Vec<DiscountCode>>,
    /// Whether the discount codes section was submitted.
    #[garde(skip)]
    pub discount_codes_present: Option<bool>,
    /// Event end time.
    #[garde(skip)]
    pub ends_at: Option<NaiveDateTime>,
    /// Whether event reminder notifications are enabled.
    #[garde(skip)]
    pub event_reminder_enabled: Option<bool>,
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
    /// Meeting hosts to synchronize with provider (email addresses).
    #[garde(custom(email_vec))]
    pub meeting_hosts: Option<Vec<String>>,
    /// URL to join the meeting.
    #[garde(url, length(max = MAX_LEN_L))]
    pub meeting_join_url: Option<String>,
    /// Desired meeting provider.
    #[serde(rename = "meeting_provider_id")]
    #[garde(skip)]
    pub meeting_provider: Option<MeetingProvider>,
    /// Recording URL for meeting.
    #[garde(url, length(max = MAX_LEN_L))]
    pub meeting_recording_url: Option<String>,
    /// Whether a meeting has been requested for the event.
    #[garde(skip)]
    pub meeting_requested: Option<bool>,
    /// Meetup.com URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub meetup_url: Option<String>,
    /// Currency used for ticket purchases.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub payment_currency_code: Option<String>,
    /// Gallery of photo URLs.
    #[garde(custom(trimmed_non_empty_vec))]
    pub photos_urls: Option<Vec<String>>,
    /// Whether registration is required.
    #[garde(skip)]
    pub registration_required: Option<bool>,
    /// Event sessions.
    #[garde(dive)]
    pub sessions: Option<Vec<Session>>,
    /// Event-level speakers.
    #[garde(dive)]
    pub speakers: Option<Vec<Speaker>>,
    /// Event sponsors.
    #[garde(dive)]
    pub sponsors: Option<Vec<EventSponsor>>,
    /// Event start time.
    #[garde(skip)]
    pub starts_at: Option<NaiveDateTime>,
    /// Tags associated with the event.
    #[garde(custom(trimmed_non_empty_tag_vec))]
    pub tags: Option<Vec<String>>,
    /// Ticket types configured for the event.
    #[garde(dive)]
    pub ticket_types: Option<Vec<TicketType>>,
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
    /// State or province where the venue is located.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub venue_state: Option<String>,
    /// Venue zip code.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub venue_zip_code: Option<String>,
    /// Whether the event waiting list is enabled.
    #[garde(skip)]
    pub waitlist_enabled: Option<bool>,
}

impl Event {
    /// Converts the dashboard form payload into the JSON shape used by the database.
    pub(crate) fn to_db_payload(&self) -> anyhow::Result<Value> {
        // Serialize the full event form into a mutable JSON object
        let mut payload = match serde_json::to_value(self)? {
            Value::Object(map) => map,
            _ => Map::new(),
        };

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
        payload.remove("clear_ticketing");
        payload.remove("discount_codes");
        payload.remove("discount_codes_present");
        payload.remove("ticket_types");
        payload.remove("ticket_types_present");

        // Null out persisted ticketing fields when ticketing should be cleared
        if self.clear_ticketing.unwrap_or(false) {
            payload.insert("discount_codes".to_string(), Value::Null);
            payload.insert("payment_currency_code".to_string(), Value::Null);
            payload.insert("ticket_types".to_string(), Value::Null);
            return Ok(Value::Object(payload));
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
    fn normalize_discount_codes(discount_codes: &mut Vec<DiscountCode>) {
        for discount_code in discount_codes {
            if discount_code.event_discount_code_id.is_none() {
                discount_code.event_discount_code_id = Some(Uuid::new_v4());
            }
        }
    }

    /// Fills in missing identifiers for newly added ticketing rows.
    fn normalize_ticket_types(ticket_types: &mut Vec<TicketType>) {
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

/// Filter parameters for events list pagination.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct EventsListFilters {
    /// Selected events tab.
    #[garde(skip)]
    pub events_tab: Option<EventsTab>,
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
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

/// Event sponsor information.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub struct EventSponsor {
    /// Group sponsor identifier.
    #[garde(skip)]
    pub group_sponsor_id: Uuid,
    /// Sponsor level for this event.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_S))]
    pub level: String,
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

/// Tab selection for the events list.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, strum::Display, strum::EnumString)]
#[serde(rename_all = "lowercase")]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum EventsTab {
    /// Past events tab (default).
    Past,
    /// Upcoming events tab.
    #[default]
    Upcoming,
}

/// Session details within an event.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct Session {
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
    /// URL to join the meeting.
    #[garde(url, length(max = MAX_LEN_L))]
    pub meeting_join_url: Option<String>,
    /// Desired meeting provider.
    #[serde(rename = "meeting_provider_id")]
    #[garde(skip)]
    pub meeting_provider: Option<MeetingProvider>,
    /// Recording URL for meeting.
    #[garde(url, length(max = MAX_LEN_L))]
    pub meeting_recording_url: Option<String>,
    /// Whether a meeting has been requested for the session.
    #[garde(skip)]
    pub meeting_requested: Option<bool>,
    /// Session speakers.
    #[garde(dive)]
    pub speakers: Option<Vec<Speaker>>,
}

/// Speaker selection with optional featured flag.
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct Speaker {
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
pub(crate) struct TicketPriceWindow {
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
pub(crate) struct TicketType {
    /// Whether the ticket type can currently be selected.
    #[garde(skip)]
    pub active: bool,
    /// Display order in event pages and forms.
    #[garde(range(min = 1))]
    pub order: i32,
    /// Price windows configured for this ticket type.
    #[serde(default)]
    #[garde(dive)]
    pub price_windows: Vec<TicketPriceWindow>,
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

    use crate::types::payments::EventDiscountType;

    use super::{DiscountCode, Event, TicketPriceWindow, TicketType};

    #[test]
    fn to_db_payload_keeps_ticketing_keys_omitted_when_form_omits_inputs() {
        let payload = sample_event().to_db_payload().unwrap();

        assert_eq!(payload["cfs_labels"], Value::Array(Vec::new()));
        assert_eq!(payload["description"], "Event description");
        assert_eq!(payload["kind_id"], "virtual");
        assert_eq!(payload["name"], "Sample Event");
        assert_eq!(payload["timezone"], "UTC");
        assert!(payload.get("discount_codes").is_none());
        assert!(payload.get("ticket_types").is_none());
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
        event.discount_codes = Some(vec![DiscountCode {
            active: true,
            code: "EARLY20".to_string(),
            kind: EventDiscountType::Percentage,
            title: "Early supporter".to_string(),

            available: None,
            amount_minor: None,
            ends_at: None,
            event_discount_code_id: None,
            percentage: Some(20),
            starts_at: None,
            total_available: None,
        }]);
        event.discount_codes_present = Some(true);
        event.ticket_types = Some(vec![TicketType {
            active: true,
            order: 1,
            price_windows: vec![TicketPriceWindow {
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
        assert!(
            uuid::Uuid::parse_str(payload["ticket_types"][0]["event_ticket_type_id"].as_str().unwrap())
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
    fn to_db_payload_clears_ticketing_when_requested() {
        let mut event = sample_event();
        event.clear_ticketing = Some(true);

        let payload = event.to_db_payload().unwrap();

        assert_eq!(payload["discount_codes"], Value::Null);
        assert_eq!(payload["payment_currency_code"], Value::Null);
        assert_eq!(payload["ticket_types"], Value::Null);
    }

    // Helpers.

    /// Creates a sample event with required fields for testing.
    fn sample_event() -> Event {
        Event {
            category_id: uuid::Uuid::new_v4(),
            description: "Event description".to_string(),
            kind_id: "virtual".to_string(),
            name: "Sample Event".to_string(),
            timezone: "UTC".to_string(),
            ..Event::default()
        }
    }
}
