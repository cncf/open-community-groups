//! Event type definitions.

use std::collections::{BTreeMap, HashSet};

use chrono::{DateTime, Duration, NaiveDate, Utc};
use chrono_tz::Tz;
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    services::meetings::MeetingProvider,
    types::{
        community::CommunitySummary,
        group::GroupSummary,
        location::{LocationParts, build_location},
        payments::{
            EventDiscountCode, EventRefundRequestStatus, EventTicketType, format_amount_minor,
        },
        questionnaire::QuestionnaireQuestion,
        user::User,
    },
    validation::{MAX_LEN_EVENT_LABEL_NAME, trimmed_non_empty, valid_cfs_label_color},
};

#[cfg(test)]
mod tests;

/// Minutes before the scheduled start when attendee meeting access opens.
const EVENT_LIVE_LEAD_TIME_MINUTES: i64 = 15;

// Event types: summary and full.

/// Summary event information.
#[skip_serializing_none]
#[allow(clippy::struct_excessive_bools)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventSummary {
    /// Whether attendance requests require organizer approval.
    #[serde(default)]
    pub attendee_approval_required: bool,
    /// Whether the event has been canceled.
    pub canceled: bool,
    /// Human-readable display name of the community this event belongs to.
    pub community_display_name: String,
    /// Name of the community this event belongs to (slug for URLs).
    pub community_name: String,
    /// Unique identifier for the event.
    pub event_id: Uuid,
    /// Category of the hosting group.
    pub group_category_name: String,
    /// Name of the group hosting this event.
    pub group_name: String,
    /// Generated URL-friendly identifier for the group hosting this event.
    pub group_slug: String,
    /// Whether this event has registration questions configured.
    #[serde(default)]
    pub has_registration_questions: bool,
    /// Whether this event has active related events in the same series.
    #[serde(default)]
    pub has_related_events: bool,
    /// Type of event (in-person or virtual).
    pub kind: EventKind,
    /// URL to the event or group's logo image.
    pub logo_url: String,
    /// Display name of the event.
    pub name: String,
    /// Whether the event is published.
    pub published: bool,
    /// URL-friendly identifier for this event.
    pub slug: String,
    /// Whether the event was created only for testing.
    #[serde(default)]
    pub test_event: bool,
    /// Timezone in which the event times should be displayed.
    pub timezone: Tz,
    /// Current number of users on the waiting list.
    #[serde(default)]
    pub waitlist_count: i32,
    /// Whether joining the waiting list is enabled for the event.
    #[serde(default)]
    pub waitlist_enabled: bool,

    /// Maximum capacity for the event.
    pub capacity: Option<i32>,
    /// Display name for the user who created the event, in dashboard views.
    pub created_by_display_name: Option<String>,
    /// Username for the user who created the event, in dashboard views.
    pub created_by_username: Option<String>,
    /// Brief event description for listings.
    pub description_short: Option<String>,
    /// Event end time in UTC.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub ends_at: Option<DateTime<Utc>>,
    /// Linked event series identifier, when the event was created as recurring.
    pub event_series_id: Option<Uuid>,
    /// Admin-managed URL-friendly identifier for the group hosting this event.
    pub group_slug_pretty: Option<String>,
    /// Latitude of the event's location.
    pub latitude: Option<f64>,
    /// Longitude of the event's location.
    pub longitude: Option<f64>,
    /// Extra instructions attendees need to join the meeting.
    pub meeting_join_instructions: Option<String>,
    /// URL to join the meeting.
    pub meeting_join_url: Option<String>,
    /// Password required to join the meeting.
    pub meeting_password: Option<String>,
    /// Desired meeting provider for this event.
    pub meeting_provider: Option<MeetingProvider>,
    /// Event currency used for ticket purchases.
    pub payment_currency_code: Option<String>,
    /// Pre-rendered HTML for map/calendar popovers.
    pub popover_html: Option<String>,
    /// Registration end time in UTC.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub registration_ends_at: Option<DateTime<Utc>>,
    /// Registration start time in UTC.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub registration_starts_at: Option<DateTime<Utc>>,
    /// Remaining capacity after subtracting registered attendees.
    pub remaining_capacity: Option<i32>,
    /// UTC timestamp when the event starts.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub starts_at: Option<DateTime<Utc>>,
    /// Ticket types available for the event.
    pub ticket_types: Option<Vec<EventTicketType>>,
    /// Street address of the venue.
    pub venue_address: Option<String>,
    /// City where the event venue is located (for in-person events).
    pub venue_city: Option<String>,
    /// ISO country code of the venue's location.
    pub venue_country_code: Option<String>,
    /// Full country name of the venue's location.
    pub venue_country_name: Option<String>,
    /// Name of the venue.
    pub venue_name: Option<String>,
    /// State or province where the venue is located.
    pub venue_state: Option<String>,
    /// Venue zip code.
    pub zip_code: Option<String>,
}

impl EventSummary {
    /// Returns dashboard tooltip text for the user who created the event.
    pub fn created_by_tooltip(&self) -> Option<String> {
        match (
            self.created_by_display_name.as_deref(),
            self.created_by_username.as_deref(),
        ) {
            (Some(display_name), Some(username)) if display_name != username => {
                Some(format!("Created by {display_name} (@{username})"))
            }
            (Some(display_name), _) => Some(format!("Created by {display_name}")),
            (None, Some(username)) => Some(format!("Created by @{username}")),
            (None, None) => None,
        }
    }

    /// Returns the cheapest attendee-facing ticket price available right now.
    pub fn formatted_ticket_price_badge(&self) -> Option<String> {
        format_ticket_price_badge(
            self.payment_currency_code.as_deref(),
            self.ticket_types.as_deref(),
        )
    }

    /// Check if the event is in the past.
    pub fn is_past(&self) -> bool {
        let reference_time = self.ends_at.or(self.starts_at);
        match reference_time {
            Some(time) => time < Utc::now(),
            None => false,
        }
    }

    /// Returns true when the event uses the ticketing flow.
    pub fn is_ticketed(&self) -> bool {
        has_ticket_types(self.ticket_types.as_deref())
    }

    /// Build a display-friendly location string from available location data.
    pub fn location(&self, max_len: usize) -> Option<String> {
        let parts = LocationParts::new()
            .address(self.venue_address.as_deref())
            .city(self.venue_city.as_deref())
            .country_code(self.venue_country_code.as_deref())
            .country_name(self.venue_country_name.as_deref())
            .name(self.venue_name.as_deref())
            .state(self.venue_state.as_deref());

        build_location(&parts, max_len)
    }

    /// Returns the group slug to use in public URLs.
    pub fn public_group_slug(&self) -> &str {
        self.group_slug_pretty.as_deref().unwrap_or(&self.group_slug)
    }

    /// Returns true when attendee registration is currently open.
    pub fn registration_window_is_open(&self) -> bool {
        registration_window_is_open(
            self.registration_starts_at,
            self.registration_ends_at,
            self.starts_at,
        )
    }

    /// Returns user-facing registration window copy.
    pub fn registration_window_message(&self) -> Option<String> {
        registration_window_message(
            self.registration_starts_at,
            self.registration_ends_at,
            self.starts_at,
            self.timezone,
        )
    }

    /// Returns disabled-control tooltip copy when registration is unavailable.
    pub fn registration_window_unavailable_title(&self) -> Option<String> {
        registration_window_unavailable_title(
            self.registration_starts_at,
            self.registration_ends_at,
            self.starts_at,
            self.timezone,
        )
    }
}

/// Full event information.
#[skip_serializing_none]
#[allow(clippy::struct_excessive_bools)]
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct EventFull {
    /// Whether attendance requests require organizer approval.
    #[serde(default)]
    pub attendee_approval_required: bool,
    /// Current number of event attendees.
    #[serde(default)]
    pub attendee_count: i32,
    /// Whether the event has been canceled.
    pub canceled: bool,
    /// Event category information.
    pub category_name: String,
    /// Call for speakers labels.
    #[serde(default)]
    pub cfs_labels: Vec<EventCfsLabel>,
    /// Community this event belongs to.
    pub community: CommunitySummary,
    /// When the event was created.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Full event description.
    pub description: String,
    /// Unique identifier for the event.
    pub event_id: Uuid,
    /// Group hosting the event.
    pub group: GroupSummary,
    /// Whether this event has registration questions configured.
    #[serde(default)]
    pub has_registration_questions: bool,
    /// Whether this event has active related events in the same series.
    #[serde(default)]
    pub has_related_events: bool,
    /// Whether any ticket purchases already exist for this event.
    pub has_ticket_purchases: bool,
    /// Event hosts.
    pub hosts: Vec<User>,
    /// Type of event (in-person, online, hybrid).
    pub kind: EventKind,
    /// URL to the event logo.
    pub logo_url: String,
    /// Event title.
    pub name: String,
    /// Event organizers snapshotted at creation time.
    pub organizers: Vec<User>,
    /// Whether the event is published.
    pub published: bool,
    /// Registration questions configured for the event.
    #[serde(default)]
    pub registration_questions: Vec<QuestionnaireQuestion>,
    /// Whether registration questions are read-only for this event.
    #[serde(default)]
    pub registration_questions_locked: bool,
    /// Event sessions grouped by day.
    pub sessions: BTreeMap<NaiveDate, Vec<Session>>,
    /// URL slug of the event.
    pub slug: String,
    /// Event speakers (at the event level).
    pub speakers: Vec<Speaker>,
    /// Event sponsors.
    pub sponsors: Vec<EventSponsor>,
    /// Whether the event was created only for testing.
    #[serde(default)]
    pub test_event: bool,
    /// Timezone for event times.
    pub timezone: Tz,
    /// Current number of users on the waiting list.
    pub waitlist_count: i32,
    /// Whether joining the waiting list is enabled for the event.
    pub waitlist_enabled: bool,

    /// URL to the event banner image optimized for mobile devices.
    pub banner_mobile_url: Option<String>,
    /// URL to the event banner image.
    pub banner_url: Option<String>,
    /// Maximum capacity for the event.
    pub capacity: Option<i32>,
    /// Call for speakers description.
    pub cfs_description: Option<String>,
    /// Whether call for speakers is enabled.
    pub cfs_enabled: Option<bool>,
    /// Call for speakers end time in UTC.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub cfs_ends_at: Option<DateTime<Utc>>,
    /// Call for speakers start time in UTC.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub cfs_starts_at: Option<DateTime<Utc>>,
    /// Brief event description.
    pub description_short: Option<String>,
    /// Discount codes configured for the event.
    pub discount_codes: Option<Vec<EventDiscountCode>>,
    /// Event end time in UTC.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub ends_at: Option<DateTime<Utc>>,
    /// Whether event reminder notifications are enabled.
    pub event_reminder_enabled: Option<bool>,
    /// Linked event series identifier, when the event was created as recurring.
    pub event_series_id: Option<Uuid>,
    /// Latitude of the event's location.
    pub latitude: Option<f64>,
    /// Legacy event hosts.
    pub legacy_hosts: Option<Vec<LegacyUser>>,
    /// Legacy event speakers.
    pub legacy_speakers: Option<Vec<LegacyUser>>,
    /// Longitude of the event's location.
    pub longitude: Option<f64>,
    /// Luma URL for the event.
    pub luma_url: Option<String>,
    /// Error message if meeting sync failed.
    pub meeting_error: Option<String>,
    /// Meeting hosts to synchronize with provider (email addresses).
    pub meeting_hosts: Option<Vec<String>>,
    /// Whether the event meeting is in sync.
    pub meeting_in_sync: Option<bool>,
    /// Extra instructions attendees need to join the event meeting.
    pub meeting_join_instructions: Option<String>,
    /// URL to join the meeting.
    pub meeting_join_url: Option<String>,
    /// Password required to join the event meeting.
    pub meeting_password: Option<String>,
    /// Desired meeting provider for this event.
    pub meeting_provider: Option<MeetingProvider>,
    /// Public URL for the meeting recording.
    pub meeting_recording_public_url: Option<String>,
    /// Whether the meeting recording is publicly visible.
    pub meeting_recording_published: Option<bool>,
    /// Read-only raw URLs for synced provider recordings.
    pub meeting_recording_raw_urls: Option<Vec<String>>,
    /// Whether automatic event meetings should be recorded.
    pub meeting_recording_requested: Option<bool>,
    /// Organizer-managed final URL for meeting recording.
    pub meeting_recording_url: Option<String>,
    /// Whether the event requests a meeting.
    pub meeting_requested: Option<bool>,
    /// Meetup.com URL for the event.
    pub meetup_url: Option<String>,
    /// Currency used for event ticket purchases.
    pub payment_currency_code: Option<String>,
    /// URLs to event photos.
    pub photos_urls: Option<Vec<String>>,
    /// When the event was published.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub published_at: Option<DateTime<Utc>>,
    /// Registration end time in UTC.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub registration_ends_at: Option<DateTime<Utc>>,
    /// Whether registration is required.
    pub registration_required: Option<bool>,
    /// Registration start time in UTC.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub registration_starts_at: Option<DateTime<Utc>>,
    /// Remaining capacity after subtracting registered attendees.
    pub remaining_capacity: Option<i32>,
    /// Event start time in UTC.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub starts_at: Option<DateTime<Utc>>,
    /// Event tags for categorization.
    pub tags: Option<Vec<String>>,
    /// Ticket types available for the event.
    pub ticket_types: Option<Vec<EventTicketType>>,
    /// Street address of the venue.
    pub venue_address: Option<String>,
    /// City where the event takes place.
    pub venue_city: Option<String>,
    /// ISO country code of the venue's location.
    pub venue_country_code: Option<String>,
    /// Full country name of the venue's location.
    pub venue_country_name: Option<String>,
    /// Name of the venue.
    pub venue_name: Option<String>,
    /// State or province where the venue is located.
    pub venue_state: Option<String>,
    /// Venue zip code.
    pub venue_zip_code: Option<String>,
}

impl EventFull {
    /// Check if call for speakers has closed.
    pub fn cfs_is_closed(&self) -> bool {
        if self.cfs_enabled.unwrap_or(false)
            && let Some(ends_at) = self.cfs_ends_at
        {
            return Utc::now() >= ends_at;
        }
        false
    }

    /// Check if call for speakers is enabled.
    pub fn cfs_is_enabled(&self) -> bool {
        self.cfs_enabled.unwrap_or(false)
    }

    /// Check if call for speakers is open.
    pub fn cfs_is_open(&self) -> bool {
        if self.cfs_enabled.unwrap_or(false)
            && let (Some(starts_at), Some(ends_at)) = (self.cfs_starts_at, self.cfs_ends_at)
        {
            let now = Utc::now();
            return now >= starts_at && now < ends_at;
        }
        false
    }

    /// Check if call for speakers has not started yet.
    pub fn cfs_is_upcoming(&self) -> bool {
        if self.cfs_enabled.unwrap_or(false)
            && let Some(starts_at) = self.cfs_starts_at
        {
            return Utc::now() < starts_at;
        }
        false
    }

    /// Check if event reminders are enabled.
    pub fn event_reminder_is_enabled(&self) -> bool {
        self.event_reminder_enabled.unwrap_or(true)
    }

    /// Returns the cheapest attendee-facing ticket price available right now.
    pub fn formatted_ticket_price_badge(&self) -> Option<String> {
        format_ticket_price_badge(
            self.payment_currency_code.as_deref(),
            self.ticket_types.as_deref(),
        )
    }

    /// Returns true when attendees can currently select a ticket.
    pub fn has_sellable_ticket_types(&self) -> bool {
        has_sellable_ticket_types(self.ticket_types.as_deref())
    }

    /// Check if the event is currently live, including attendee access lead time.
    pub fn is_live(&self) -> bool {
        match (self.starts_at, self.ends_at) {
            (Some(starts_at), Some(ends_at)) => {
                let now = Utc::now();
                let live_starts_at = starts_at - Duration::minutes(EVENT_LIVE_LEAD_TIME_MINUTES);

                now >= live_starts_at && now <= ends_at
            }
            _ => false,
        }
    }

    /// Check if the event is in the past.
    pub fn is_past(&self) -> bool {
        let reference_time = self.ends_at.or(self.starts_at);
        match reference_time {
            Some(time) => time < Utc::now(),
            None => false,
        }
    }

    /// Returns true when the event uses the ticketing flow.
    pub fn is_ticketed(&self) -> bool {
        has_ticket_types(self.ticket_types.as_deref())
    }

    /// Build a display-friendly location string from available location data.
    pub fn location(&self, max_len: usize) -> Option<String> {
        let parts = LocationParts::new()
            .address(self.venue_address.as_deref())
            .city(self.venue_city.as_deref())
            .country_code(self.venue_country_code.as_deref())
            .country_name(self.venue_country_name.as_deref())
            .name(self.venue_name.as_deref())
            .state(self.venue_state.as_deref());

        build_location(&parts, max_len)
    }

    /// Returns true when attendee registration is currently open.
    pub fn registration_window_is_open(&self) -> bool {
        registration_window_is_open(
            self.registration_starts_at,
            self.registration_ends_at,
            self.starts_at,
        )
    }

    /// Returns user-facing registration window copy.
    pub fn registration_window_message(&self) -> Option<String> {
        registration_window_message(
            self.registration_starts_at,
            self.registration_ends_at,
            self.starts_at,
            self.timezone,
        )
    }

    /// Returns disabled-control tooltip copy when registration is unavailable.
    pub fn registration_window_unavailable_title(&self) -> Option<String> {
        registration_window_unavailable_title(
            self.registration_starts_at,
            self.registration_ends_at,
            self.starts_at,
            self.timezone,
        )
    }

    /// Returns the attendee-selectable ticket types for the event page.
    pub fn sellable_ticket_types(&self) -> Vec<&EventTicketType> {
        self.ticket_types
            .as_ref()
            .map(|ticket_types| {
                ticket_types
                    .iter()
                    .filter(|ticket_type| ticket_type.is_sellable_now())
                    .collect()
            })
            .unwrap_or_default()
    }

    /// Collect all unique speaker user IDs (event-level + session-level).
    pub fn speakers_ids(&self) -> Vec<Uuid> {
        // Event-level speakers
        let mut ids: HashSet<Uuid> = self.speakers.iter().map(|s| s.user.user_id).collect();

        // Session-level speakers
        for sessions in self.sessions.values() {
            for session in sessions {
                for speaker in &session.speakers {
                    ids.insert(speaker.user.user_id);
                }
            }
        }

        let mut ids: Vec<Uuid> = ids.into_iter().collect();
        ids.sort();
        ids
    }

    /// Returns active ticket types shown in the tickets modal, sorted by price.
    pub fn visible_ticket_types(&self) -> Vec<&EventTicketType> {
        let mut ticket_types: Vec<_> = self
            .ticket_types
            .as_ref()
            .map(|ticket_types| {
                ticket_types
                    .iter()
                    .filter(|ticket_type| {
                        ticket_type.active && ticket_type.current_amount_minor().is_some()
                    })
                    .collect()
            })
            .unwrap_or_default();

        ticket_types
            .sort_by_key(|ticket_type| ticket_type.current_amount_minor().unwrap_or_default());
        ticket_types
    }
}

impl From<&EventFull> for EventSummary {
    fn from(event: &EventFull) -> Self {
        EventSummary {
            attendee_approval_required: event.attendee_approval_required,
            canceled: event.canceled,
            community_display_name: event.community.display_name.clone(),
            community_name: event.community.name.clone(),
            event_id: event.event_id,
            group_category_name: event.group.category.name.clone(),
            group_name: event.group.name.clone(),
            group_slug: event.group.slug.clone(),
            has_registration_questions: event.has_registration_questions
                || !event.registration_questions.is_empty(),
            has_related_events: event.has_related_events,
            kind: event.kind.clone(),
            logo_url: event.logo_url.clone(),
            name: event.name.clone(),
            published: event.published,
            slug: event.slug.clone(),
            test_event: event.test_event,
            timezone: event.timezone,
            waitlist_count: event.waitlist_count,
            waitlist_enabled: event.waitlist_enabled,

            capacity: event.capacity,
            created_by_display_name: None,
            created_by_username: None,
            description_short: event.description_short.clone(),
            ends_at: event.ends_at,
            event_series_id: event.event_series_id,
            group_slug_pretty: event.group.slug_pretty.clone(),
            latitude: event.latitude,
            longitude: event.longitude,
            meeting_join_instructions: event.meeting_join_instructions.clone(),
            meeting_join_url: event.meeting_join_url.clone(),
            meeting_password: event.meeting_password.clone(),
            meeting_provider: event.meeting_provider,
            payment_currency_code: event.payment_currency_code.clone(),
            popover_html: None,
            registration_ends_at: event.registration_ends_at,
            registration_starts_at: event.registration_starts_at,
            remaining_capacity: event.remaining_capacity,
            starts_at: event.starts_at,
            ticket_types: event.ticket_types.clone(),
            venue_address: event.venue_address.clone(),
            venue_city: event.venue_city.clone(),
            venue_country_code: event.venue_country_code.clone(),
            venue_country_name: event.venue_country_name.clone(),
            venue_name: event.venue_name.clone(),
            venue_state: event.venue_state.clone(),
            zip_code: event.venue_zip_code.clone(),
        }
    }
}

// Other related types.

/// Attendance details for a user's relationship to an event.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventAttendanceInfo {
    /// Whether the user has checked in.
    pub is_checked_in: bool,
    /// Whether this attendance row comes from a manual organizer invitation.
    #[serde(default)]
    pub manually_invited: bool,
    /// Current attendance status.
    pub status: EventAttendanceStatus,

    /// Purchase amount associated with the user and event.
    pub purchase_amount_minor: Option<i64>,
    /// Refund request state associated with the user purchase.
    pub refund_request_status: Option<EventRefundRequestStatus>,
    /// Provider URL for resuming a pending checkout.
    pub resume_checkout_url: Option<String>,
}

impl EventAttendanceInfo {
    /// Returns true when the attendee can submit a refund request.
    pub fn can_request_refund(&self, starts_at: Option<DateTime<Utc>>) -> bool {
        self.status == EventAttendanceStatus::Attendee
            && self
                .purchase_amount_minor
                .is_some_and(|purchase_amount_minor| purchase_amount_minor > 0)
            && self.refund_request_status.is_none()
            && starts_at.is_none_or(|starts_at| starts_at > Utc::now())
    }
}

/// Attendance status for the current user on an event.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, strum::EnumString)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum EventAttendanceStatus {
    /// The user has no attendance relationship with the event.
    None,
    /// The user became a confirmed attendee.
    Attendee,
    /// The user's invitation request was approved and can be used to attend.
    InvitationApproved,
    /// The user requested an invitation and is waiting for review.
    PendingApproval,
    /// The user started checkout but has not completed payment yet.
    PendingPayment,
    /// The user's seat is reserved until registration questions are answered.
    RegistrationQuestionsPending,
    /// The user's invitation request was rejected.
    Rejected,
    /// The user joined the waiting list.
    Waitlisted,
}

/// Event category information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventCategory {
    /// Category identifier.
    pub event_category_id: Uuid,
    /// Category name.
    pub name: String,
    /// URL-friendly identifier.
    pub slug: String,

    /// Number of events currently using this category.
    pub events_count: Option<usize>,
}

/// Event CFS label used for submissions.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub struct EventCfsLabel {
    /// Label color.
    #[garde(custom(valid_cfs_label_color))]
    pub color: String,
    /// Label name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_EVENT_LABEL_NAME))]
    pub name: String,

    /// Event CFS label identifier.
    #[serde(default)]
    #[garde(skip)]
    pub event_cfs_label_id: Option<Uuid>,
}

/// Status of an event invitation request.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, strum::Display)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum EventInvitationRequestStatus {
    /// Invitation request was accepted.
    Accepted,
    /// Invitation request awaits review.
    Pending,
    /// Invitation request was rejected.
    Rejected,
}

/// Categorization of event attendance modes.
///
/// Distinguishes between physical, online, and mixed attendance events
/// for filtering and display purposes.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, strum::Display)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum EventKind {
    /// Event supports both in-person and virtual attendance.
    Hybrid,
    /// Event requires in-person attendance.
    #[default]
    InPerson,
    /// Event is attended virtually.
    Virtual,
}

/// Event kind summary.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventKindSummary {
    /// Display name.
    pub display_name: String,
    /// Kind identifier.
    pub event_kind_id: String,
}

/// Result returned when leaving an event or waiting list.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct EventLeaveOutcome {
    /// The status the user left from.
    pub left_status: EventAttendanceStatus,
    /// Users promoted from the waiting list as part of the operation.
    pub promoted_user_ids: Vec<Uuid>,
}

/// Event sponsor information.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventSponsor {
    /// Group sponsor identifier.
    pub group_sponsor_id: Uuid,
    /// Sponsor level for this event.
    pub level: String,
    /// URL to sponsor logo.
    pub logo_url: String,
    /// Sponsor name.
    pub name: String,

    /// Sponsor website URL.
    pub website_url: Option<String>,
}

/// Legacy user information.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LegacyUser {
    /// Short biography.
    pub bio: Option<String>,
    /// Display name.
    pub name: Option<String>,
    /// URL to the profile photo.
    pub photo_url: Option<String>,
    /// Professional title.
    pub title: Option<String>,
}

/// Session information within an event.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Session {
    /// Type of session (hybrid, in-person, virtual).
    pub kind: SessionKind,
    /// Session title.
    pub name: String,
    /// Unique identifier for the session.
    pub session_id: Uuid,
    /// Session speakers.
    pub speakers: Vec<Speaker>,
    /// Session start time in UTC.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub starts_at: DateTime<Utc>,

    /// Linked CFS submission identifier.
    pub cfs_submission_id: Option<Uuid>,
    /// Full session description.
    pub description: Option<String>,
    /// Session end time in UTC.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub ends_at: Option<DateTime<Utc>>,
    /// Location details for the session.
    pub location: Option<String>,
    /// Error message if meeting sync failed.
    pub meeting_error: Option<String>,
    /// Meeting hosts to synchronize with provider (email addresses).
    pub meeting_hosts: Option<Vec<String>>,
    /// Whether the meeting data is in sync with the provider.
    pub meeting_in_sync: Option<bool>,
    /// Extra instructions attendees need to join the session meeting.
    pub meeting_join_instructions: Option<String>,
    /// URL to join the meeting.
    pub meeting_join_url: Option<String>,
    /// Password required to join the session meeting.
    pub meeting_password: Option<String>,
    /// Desired meeting provider for this session.
    pub meeting_provider: Option<MeetingProvider>,
    /// Public URL for the meeting recording.
    pub meeting_recording_public_url: Option<String>,
    /// Whether the meeting recording is publicly visible.
    pub meeting_recording_published: Option<bool>,
    /// Read-only raw URLs for synced provider recordings.
    pub meeting_recording_raw_urls: Option<Vec<String>>,
    /// Organizer-managed final URL for meeting recording.
    pub meeting_recording_url: Option<String>,
    /// Whether the session requests a meeting.
    pub meeting_requested: Option<bool>,
}

/// Categorization of session attendance modes.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, strum::Display)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum SessionKind {
    /// Session supports both in-person and virtual attendance.
    Hybrid,
    /// Session requires in-person attendance.
    #[default]
    InPerson,
    /// Session is attended virtually.
    Virtual,
}

/// Session kind summary.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionKindSummary {
    /// Display name.
    pub display_name: String,
    /// Kind identifier.
    pub session_kind_id: String,
}

/// Event/session speaker details.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Speaker {
    /// Whether the speaker is highlighted.
    #[serde(default)]
    pub featured: bool,
    /// Embedded user profile information.
    #[serde(flatten)]
    pub user: User,
}

// Helpers.

/// Returns a local datetime label for registration window copy.
fn format_registration_window_time(time: DateTime<Utc>, timezone: Tz) -> String {
    time.with_timezone(&timezone)
        .format("%b %-e, %Y at %-I:%M %p %Z")
        .to_string()
}

/// Returns the attendee-facing ticket price badge content.
fn format_ticket_price_badge(
    payment_currency_code: Option<&str>,
    ticket_types: Option<&[EventTicketType]>,
) -> Option<String> {
    let sellable_amounts: Vec<_> = ticket_types?
        .iter()
        .filter(|ticket_type| ticket_type.is_sellable_now())
        .filter_map(EventTicketType::current_amount_minor)
        .collect();

    let amount_minor = sellable_amounts.iter().min().copied()?;

    if amount_minor == 0 {
        return if sellable_amounts.iter().any(|amount| *amount > 0) {
            Some("Free and up".to_string())
        } else {
            Some("Free".to_string())
        };
    }

    let currency_code = payment_currency_code?;

    Some(format!(
        "From {}",
        format_amount_minor(amount_minor, currency_code)
    ))
}

/// Returns true when attendees can currently select a ticket.
fn has_sellable_ticket_types(ticket_types: Option<&[EventTicketType]>) -> bool {
    ticket_types
        .is_some_and(|ticket_types| ticket_types.iter().any(EventTicketType::is_sellable_now))
}

/// Returns true when the event uses the ticketing flow.
fn has_ticket_types(ticket_types: Option<&[EventTicketType]>) -> bool {
    ticket_types.is_some_and(|ticket_types| !ticket_types.is_empty())
}

/// Returns true when a registration window has been configured.
fn registration_window_configured(
    starts_at: Option<DateTime<Utc>>,
    ends_at: Option<DateTime<Utc>>,
) -> bool {
    starts_at.is_some() || ends_at.is_some()
}

/// Returns the configured or implied registration close time.
fn registration_window_effective_ends_at(
    starts_at: Option<DateTime<Utc>>,
    ends_at: Option<DateTime<Utc>>,
    event_starts_at: Option<DateTime<Utc>>,
) -> Option<DateTime<Utc>> {
    if ends_at.is_some() {
        ends_at
    } else if starts_at.is_some() {
        event_starts_at
    } else {
        None
    }
}

/// Returns true when the registration window is currently open.
fn registration_window_is_open(
    starts_at: Option<DateTime<Utc>>,
    ends_at: Option<DateTime<Utc>>,
    event_starts_at: Option<DateTime<Utc>>,
) -> bool {
    let now = Utc::now();
    let effective_ends_at =
        registration_window_effective_ends_at(starts_at, ends_at, event_starts_at);

    starts_at.is_none_or(|starts_at| now >= starts_at)
        && effective_ends_at.is_none_or(|ends_at| now < ends_at)
}

/// Returns user-facing registration window copy.
fn registration_window_message(
    starts_at: Option<DateTime<Utc>>,
    ends_at: Option<DateTime<Utc>>,
    event_starts_at: Option<DateTime<Utc>>,
    timezone: Tz,
) -> Option<String> {
    if !registration_window_configured(starts_at, ends_at) {
        return None;
    }

    let now = Utc::now();
    let effective_ends_at =
        registration_window_effective_ends_at(starts_at, ends_at, event_starts_at);
    match (starts_at, effective_ends_at) {
        (Some(starts_at), Some(ends_at)) if now < starts_at => Some(format!(
            "Registration opens {} and closes {}.",
            format_registration_window_time(starts_at, timezone),
            format_registration_window_time(ends_at, timezone),
        )),
        (_, Some(ends_at)) if now >= ends_at => Some(format!(
            "Registration closed {}.",
            format_registration_window_time(ends_at, timezone),
        )),
        (Some(_) | None, Some(ends_at)) => Some(format!(
            "Registration is open until {}.",
            format_registration_window_time(ends_at, timezone),
        )),
        (Some(starts_at), None) if now < starts_at => Some(format!(
            "Registration opens {}.",
            format_registration_window_time(starts_at, timezone),
        )),
        (Some(starts_at), None) => Some(format!(
            "Registration opened {}.",
            format_registration_window_time(starts_at, timezone),
        )),
        (None, None) => None,
    }
}

/// Returns disabled-control tooltip copy when registration is unavailable.
fn registration_window_unavailable_title(
    starts_at: Option<DateTime<Utc>>,
    ends_at: Option<DateTime<Utc>>,
    event_starts_at: Option<DateTime<Utc>>,
    timezone: Tz,
) -> Option<String> {
    let now = Utc::now();
    let effective_ends_at =
        registration_window_effective_ends_at(starts_at, ends_at, event_starts_at);

    // Explain why controls are disabled before registration opens
    if let Some(starts_at) = starts_at
        && now < starts_at
    {
        return Some(format!(
            "Registration opens {}.",
            format_registration_window_time(starts_at, timezone)
        ));
    }

    // Explain why controls are disabled after the configured or implicit close
    if let Some(ends_at) = effective_ends_at
        && now >= ends_at
    {
        return Some(format!(
            "Registration closed {}.",
            format_registration_window_time(ends_at, timezone)
        ));
    }

    None
}
