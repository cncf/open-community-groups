//! Event type definitions.

use std::collections::{BTreeMap, HashSet};

use chrono::{DateTime, NaiveDate, Utc};
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
        payments::{EventDiscountCode, EventRefundRequestStatus, EventTicketType, format_amount_minor},
        user::User,
    },
    validation::{MAX_LEN_EVENT_LABEL_NAME, trimmed_non_empty, valid_cfs_label_color},
};

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
    /// URL-friendly identifier for the group hosting this event.
    pub group_slug: String,
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
    /// Brief event description for listings.
    pub description_short: Option<String>,
    /// Event end time in UTC.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub ends_at: Option<DateTime<Utc>>,
    /// Linked event series identifier, when the event was created as recurring.
    pub event_series_id: Option<Uuid>,
    /// Latitude of the event's location.
    pub latitude: Option<f64>,
    /// Longitude of the event's location.
    pub longitude: Option<f64>,
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
    /// Remaining capacity after subtracting registered attendees.
    pub remaining_capacity: Option<i32>,
    /// UTC timestamp when the event starts.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub starts_at: Option<DateTime<Utc>>,
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
    /// Ticket types available for the event.
    pub ticket_types: Option<Vec<EventTicketType>>,
    /// Venue zip code.
    pub zip_code: Option<String>,
}

impl EventSummary {
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
}

/// Full event information.
#[skip_serializing_none]
#[allow(clippy::struct_excessive_bools)]
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct EventFull {
    /// Whether attendance requests require organizer approval.
    #[serde(default)]
    pub attendee_approval_required: bool,
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
    /// Event organizers (from group team).
    pub organizers: Vec<User>,
    /// Whether the event is published.
    pub published: bool,
    /// Event sessions grouped by day.
    pub sessions: BTreeMap<NaiveDate, Vec<Session>>,
    /// URL slug of the event.
    pub slug: String,
    /// Event speakers (at the event level).
    pub speakers: Vec<Speaker>,
    /// Event sponsors.
    pub sponsors: Vec<EventSponsor>,
    /// Timezone for event times.
    pub timezone: Tz,
    /// Whether joining the waiting list is enabled for the event.
    pub waitlist_enabled: bool,
    /// Current number of users on the waiting list.
    pub waitlist_count: i32,

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
    /// Error message if meeting sync failed.
    pub meeting_error: Option<String>,
    /// Meeting hosts to synchronize with provider (email addresses).
    pub meeting_hosts: Option<Vec<String>>,
    /// Whether the event meeting is in sync.
    pub meeting_in_sync: Option<bool>,
    /// URL to join the meeting.
    pub meeting_join_url: Option<String>,
    /// Password required to join the event meeting.
    pub meeting_password: Option<String>,
    /// Desired meeting provider for this event.
    pub meeting_provider: Option<MeetingProvider>,
    /// URL for meeting recording.
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
    /// Whether registration is required.
    pub registration_required: Option<bool>,
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

    /// Check if the event is currently live.
    pub fn is_live(&self) -> bool {
        match (self.starts_at, self.ends_at) {
            (Some(starts_at), Some(ends_at)) => {
                let now = Utc::now();
                now >= starts_at && now <= ends_at
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
                    .filter(|ticket_type| ticket_type.active && ticket_type.current_amount_minor().is_some())
                    .collect()
            })
            .unwrap_or_default();

        ticket_types.sort_by_key(|ticket_type| ticket_type.current_amount_minor().unwrap_or_default());
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
            has_related_events: event.has_related_events,
            kind: event.kind.clone(),
            logo_url: event.logo_url.clone(),
            name: event.name.clone(),
            published: event.published,
            slug: event.slug.clone(),
            timezone: event.timezone,
            waitlist_count: event.waitlist_count,
            waitlist_enabled: event.waitlist_enabled,

            capacity: event.capacity,
            description_short: event.description_short.clone(),
            ends_at: event.ends_at,
            event_series_id: event.event_series_id,
            latitude: event.latitude,
            longitude: event.longitude,
            meeting_join_url: event.meeting_join_url.clone(),
            meeting_password: event.meeting_password.clone(),
            meeting_provider: event.meeting_provider,
            payment_currency_code: event.payment_currency_code.clone(),
            popover_html: None,
            remaining_capacity: event.remaining_capacity,
            starts_at: event.starts_at,
            venue_address: event.venue_address.clone(),
            venue_city: event.venue_city.clone(),
            venue_country_code: event.venue_country_code.clone(),
            venue_country_name: event.venue_country_name.clone(),
            venue_name: event.venue_name.clone(),
            venue_state: event.venue_state.clone(),
            ticket_types: event.ticket_types.clone(),
            zip_code: event.venue_zip_code.clone(),
        }
    }
}

// Other related types.

/// Attendance status for the current user on an event.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, strum::EnumString)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum EventAttendanceStatus {
    /// The user has no attendance relationship with the event.
    None,
    /// The user became a confirmed attendee.
    Attendee,
    /// The user requested an invitation and is waiting for review.
    PendingApproval,
    /// The user started checkout but has not completed payment yet.
    PendingPayment,
    /// The user's invitation request was rejected.
    Rejected,
    /// The user joined the waiting list.
    Waitlisted,
}

/// Attendance details for a user's relationship to an event.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventAttendanceInfo {
    /// Whether the user has checked in.
    pub is_checked_in: bool,
    /// Current attendance status.
    pub status: EventAttendanceStatus,

    /// Refund request state associated with the user purchase.
    pub refund_request_status: Option<EventRefundRequestStatus>,
    /// Purchase amount associated with the user and event.
    pub purchase_amount_minor: Option<i64>,
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
    Accepted,
    Pending,
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
    Hybrid,
    #[default]
    InPerson,
    Virtual,
}

/// Event kind summary.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventKindSummary {
    /// Kind identifier.
    pub event_kind_id: String,
    /// Display name.
    pub display_name: String,
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
    /// URL to join the meeting.
    pub meeting_join_url: Option<String>,
    /// Password required to join the session meeting.
    pub meeting_password: Option<String>,
    /// Desired meeting provider for this session.
    pub meeting_provider: Option<MeetingProvider>,
    /// URL for meeting recording.
    pub meeting_recording_url: Option<String>,
    /// Whether the session requests a meeting.
    pub meeting_requested: Option<bool>,
}

impl Session {
    /// Check if the session is currently live.
    #[allow(dead_code)]
    pub fn is_live(&self) -> bool {
        match self.ends_at {
            Some(ends_at) => {
                let now = Utc::now();
                now >= self.starts_at && now <= ends_at
            }
            None => false,
        }
    }
}

/// Categorization of session attendance modes.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, strum::Display)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum SessionKind {
    Hybrid,
    #[default]
    InPerson,
    Virtual,
}

/// Session kind summary.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionKindSummary {
    /// Kind identifier.
    pub session_kind_id: String,
    /// Display name.
    pub display_name: String,
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

/// Returns true when the event uses the ticketing flow.
fn has_ticket_types(ticket_types: Option<&[EventTicketType]>) -> bool {
    ticket_types.is_some_and(|ticket_types| !ticket_types.is_empty())
}

/// Returns true when attendees can currently select a ticket.
fn has_sellable_ticket_types(ticket_types: Option<&[EventTicketType]>) -> bool {
    ticket_types.is_some_and(|ticket_types| ticket_types.iter().any(EventTicketType::is_sellable_now))
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use chrono::{Duration, TimeZone, Utc};

    use crate::types::payments::{EventTicketCurrentPrice, EventTicketType};

    use super::*;

    #[test]
    fn event_attendance_info_can_request_refund_allows_tbd_events() {
        let attendance = EventAttendanceInfo {
            is_checked_in: false,
            status: EventAttendanceStatus::Attendee,

            purchase_amount_minor: Some(2_500),
            refund_request_status: None,
            resume_checkout_url: None,
        };

        assert!(attendance.can_request_refund(Some(Utc::now() + Duration::hours(1))));
        assert!(attendance.can_request_refund(None));
        assert!(!attendance.can_request_refund(Some(Utc::now() - Duration::hours(1))));
    }

    #[test]
    fn event_full_to_summary_maps_event_fields() {
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let event_series_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let starts_at = Utc.with_ymd_and_hms(2030, 1, 2, 3, 4, 5).unwrap();
        let ends_at = starts_at + Duration::hours(2);
        let event = EventFull {
            canceled: true,
            community: CommunitySummary {
                community_id,
                display_name: "Community Display".to_string(),
                name: "community".to_string(),
                ..Default::default()
            },
            description_short: Some("Short description".to_string()),
            ends_at: Some(ends_at),
            event_id,
            event_series_id: Some(event_series_id),
            group: GroupSummary {
                category: crate::types::group::GroupCategory {
                    name: "Technology".to_string(),
                    ..Default::default()
                },
                group_id,
                name: "Group Name".to_string(),
                slug: "group-slug".to_string(),
                ..Default::default()
            },
            has_related_events: true,
            kind: EventKind::Hybrid,
            logo_url: "https://example.com/logo.png".to_string(),
            name: "Event Name".to_string(),
            payment_currency_code: Some("USD".to_string()),
            published: true,
            remaining_capacity: Some(7),
            slug: "event-slug".to_string(),
            starts_at: Some(starts_at),
            timezone: chrono_tz::Europe::Madrid,
            venue_city: Some("Madrid".to_string()),
            waitlist_count: 3,
            waitlist_enabled: true,
            ..Default::default()
        };
        let summary = EventSummary::from(&event);

        assert!(summary.canceled);
        assert_eq!(summary.community_display_name, "Community Display");
        assert_eq!(summary.community_name, "community");
        assert_eq!(summary.description_short.as_deref(), Some("Short description"));
        assert_eq!(summary.ends_at, Some(ends_at));
        assert_eq!(summary.event_id, event_id);
        assert_eq!(summary.event_series_id, Some(event_series_id));
        assert_eq!(summary.group_category_name, "Technology");
        assert_eq!(summary.group_name, "Group Name");
        assert_eq!(summary.group_slug, "group-slug");
        assert!(summary.has_related_events);
        assert_eq!(summary.kind, EventKind::Hybrid);
        assert_eq!(summary.logo_url, "https://example.com/logo.png");
        assert_eq!(summary.name, "Event Name");
        assert_eq!(summary.payment_currency_code.as_deref(), Some("USD"));
        assert_eq!(summary.popover_html, None);
        assert!(summary.published);
        assert_eq!(summary.remaining_capacity, Some(7));
        assert_eq!(summary.slug, "event-slug");
        assert_eq!(summary.starts_at, Some(starts_at));
        assert_eq!(summary.timezone, chrono_tz::Europe::Madrid);
        assert_eq!(summary.venue_city.as_deref(), Some("Madrid"));
        assert_eq!(summary.waitlist_count, 3);
        assert!(summary.waitlist_enabled);
    }

    #[test]
    fn event_full_cfs_is_enabled_returns_false_when_flag_missing() {
        let event = EventFull {
            cfs_enabled: None,
            ..Default::default()
        };
        assert!(!event.cfs_is_enabled());
    }

    #[test]
    fn event_full_cfs_is_enabled_returns_true_when_flag_set() {
        let event = EventFull {
            cfs_enabled: Some(true),
            ..Default::default()
        };
        assert!(event.cfs_is_enabled());
    }

    #[test]
    fn event_full_cfs_is_open_returns_false_when_disabled() {
        let now = Utc::now();
        let event = EventFull {
            cfs_enabled: Some(false),
            cfs_starts_at: Some(now - Duration::hours(1)),
            cfs_ends_at: Some(now + Duration::hours(1)),
            ..Default::default()
        };
        assert!(!event.cfs_is_open());
    }

    #[test]
    fn event_full_cfs_is_open_returns_true_when_within_window() {
        let now = Utc::now();
        let event = EventFull {
            cfs_enabled: Some(true),
            cfs_starts_at: Some(now - Duration::hours(1)),
            cfs_ends_at: Some(now + Duration::hours(1)),
            ..Default::default()
        };
        assert!(event.cfs_is_open());
    }

    #[test]
    fn event_full_cfs_is_closed_returns_true_when_window_ended() {
        let event = EventFull {
            cfs_enabled: Some(true),
            cfs_ends_at: Some(Utc::now() - Duration::hours(1)),
            ..Default::default()
        };
        assert!(event.cfs_is_closed());
    }

    #[test]
    fn event_full_cfs_is_upcoming_returns_false_when_started() {
        let event = EventFull {
            cfs_enabled: Some(true),
            cfs_starts_at: Some(Utc::now() - Duration::hours(1)),
            ..Default::default()
        };
        assert!(!event.cfs_is_upcoming());
    }

    #[test]
    fn event_full_cfs_is_upcoming_returns_true_when_start_in_future() {
        let event = EventFull {
            cfs_enabled: Some(true),
            cfs_starts_at: Some(Utc::now() + Duration::hours(1)),
            ..Default::default()
        };
        assert!(event.cfs_is_upcoming());
    }

    #[test]
    fn event_full_has_sellable_ticket_types_returns_false_when_no_tier_is_purchasable() {
        let event = EventFull {
            ticket_types: Some(vec![
                sample_ticket_type(false, Some(0), false, "Hidden free"),
                sample_ticket_type(true, None, false, "No current price"),
                sample_ticket_type(true, Some(1500), true, "Sold out"),
            ]),
            ..Default::default()
        };

        assert!(!event.has_sellable_ticket_types());
        assert!(event.is_ticketed());
    }

    #[test]
    fn event_full_is_live_returns_false_when_ends_at_is_none() {
        let event = EventFull {
            starts_at: Some(Utc::now() - Duration::hours(1)),
            ends_at: None,
            ..Default::default()
        };
        assert!(!event.is_live());
    }

    #[test]
    fn event_full_is_live_returns_false_when_event_ended() {
        let event = EventFull {
            starts_at: Some(Utc::now() - Duration::hours(2)),
            ends_at: Some(Utc::now() - Duration::hours(1)),
            ..Default::default()
        };
        assert!(!event.is_live());
    }

    #[test]
    fn event_full_is_live_returns_false_when_event_not_started() {
        let event = EventFull {
            starts_at: Some(Utc::now() + Duration::hours(1)),
            ends_at: Some(Utc::now() + Duration::hours(2)),
            ..Default::default()
        };
        assert!(!event.is_live());
    }

    #[test]
    fn event_full_is_live_returns_false_when_starts_at_is_none() {
        let event = EventFull {
            starts_at: None,
            ends_at: Some(Utc::now() + Duration::hours(1)),
            ..Default::default()
        };
        assert!(!event.is_live());
    }

    #[test]
    fn event_full_is_live_returns_true_when_event_is_live() {
        let event = EventFull {
            starts_at: Some(Utc::now() - Duration::hours(1)),
            ends_at: Some(Utc::now() + Duration::hours(1)),
            ..Default::default()
        };
        assert!(event.is_live());
    }

    #[test]
    fn event_full_is_past_returns_false_when_both_times_are_none() {
        let event = EventFull {
            ends_at: None,
            starts_at: None,
            ..Default::default()
        };
        assert!(!event.is_past());
    }

    #[test]
    fn event_full_is_past_returns_false_when_ends_at_is_in_future() {
        let event = EventFull {
            ends_at: Some(Utc::now() + Duration::hours(1)),
            starts_at: Some(Utc::now() - Duration::hours(1)),
            ..Default::default()
        };
        assert!(!event.is_past());
    }

    #[test]
    fn event_full_is_past_returns_false_when_starts_at_is_in_future() {
        let event = EventFull {
            ends_at: None,
            starts_at: Some(Utc::now() + Duration::hours(1)),
            ..Default::default()
        };
        assert!(!event.is_past());
    }

    #[test]
    fn event_full_is_past_returns_true_when_ends_at_is_in_past() {
        let event = EventFull {
            ends_at: Some(Utc::now() - Duration::hours(1)),
            starts_at: Some(Utc::now() - Duration::hours(2)),
            ..Default::default()
        };
        assert!(event.is_past());
    }

    #[test]
    fn event_full_is_past_returns_true_when_starts_at_is_in_past_and_no_ends_at() {
        let event = EventFull {
            ends_at: None,
            starts_at: Some(Utc::now() - Duration::hours(1)),
            ..Default::default()
        };
        assert!(event.is_past());
    }

    #[test]
    fn event_full_speakers_ids_collects_both_event_and_session_level_speakers() {
        let event_speaker_id = Uuid::from_u128(1);
        let session_speaker_id = Uuid::from_u128(2);
        let date = Utc::now().date_naive();

        let event = EventFull {
            speakers: vec![Speaker {
                featured: false,
                user: User {
                    user_id: event_speaker_id,
                    ..Default::default()
                },
            }],
            sessions: BTreeMap::from([(
                date,
                vec![Session {
                    speakers: vec![Speaker {
                        featured: false,
                        user: User {
                            user_id: session_speaker_id,
                            ..Default::default()
                        },
                    }],
                    starts_at: Utc::now(),
                    ..Default::default()
                }],
            )]),
            ..Default::default()
        };

        let ids = event.speakers_ids();
        assert_eq!(ids.len(), 2);
        assert!(ids.contains(&event_speaker_id));
        assert!(ids.contains(&session_speaker_id));
    }

    #[test]
    fn event_full_speakers_ids_deduplicates_speakers() {
        let shared_speaker_id = Uuid::from_u128(1);
        let date = Utc::now().date_naive();

        // Same speaker appears at both event and session level
        let event = EventFull {
            speakers: vec![Speaker {
                featured: false,
                user: User {
                    user_id: shared_speaker_id,
                    ..Default::default()
                },
            }],
            sessions: BTreeMap::from([(
                date,
                vec![Session {
                    speakers: vec![Speaker {
                        featured: false,
                        user: User {
                            user_id: shared_speaker_id,
                            ..Default::default()
                        },
                    }],
                    starts_at: Utc::now(),
                    ..Default::default()
                }],
            )]),
            ..Default::default()
        };

        let ids = event.speakers_ids();
        assert_eq!(ids.len(), 1);
        assert_eq!(ids[0], shared_speaker_id);
    }

    #[test]
    fn event_full_speakers_ids_returns_empty_when_no_speakers() {
        let event = EventFull::default();
        assert!(event.speakers_ids().is_empty());
    }

    #[test]
    fn event_full_speakers_ids_returns_sorted_ids() {
        let id_a = Uuid::from_u128(100);
        let id_b = Uuid::from_u128(50);
        let id_c = Uuid::from_u128(200);

        let event = EventFull {
            speakers: vec![
                Speaker {
                    featured: false,
                    user: User {
                        user_id: id_a,
                        ..Default::default()
                    },
                },
                Speaker {
                    featured: false,
                    user: User {
                        user_id: id_b,
                        ..Default::default()
                    },
                },
                Speaker {
                    featured: false,
                    user: User {
                        user_id: id_c,
                        ..Default::default()
                    },
                },
            ],
            ..Default::default()
        };

        let ids = event.speakers_ids();
        assert_eq!(ids, vec![id_b, id_a, id_c]); // Sorted by UUID value
    }

    #[test]
    fn event_full_sellable_ticket_types_filters_unsellable_tiers() {
        let event = EventFull {
            ticket_types: Some(vec![
                sample_ticket_type(false, Some(0), false, "Hidden free"),
                sample_ticket_type(true, None, false, "No current price"),
                sample_ticket_type(true, Some(1500), true, "Sold out"),
                sample_ticket_type(true, Some(2500), false, "General"),
            ]),
            ..Default::default()
        };

        let ticket_titles: Vec<_> = event
            .sellable_ticket_types()
            .into_iter()
            .map(|ticket_type| ticket_type.title.as_str())
            .collect();

        assert_eq!(ticket_titles, vec!["General"]);
    }

    #[test]
    fn event_full_visible_ticket_types_include_sold_out_tiers_sorted_by_price() {
        let event = EventFull {
            ticket_types: Some(vec![
                sample_ticket_type(false, Some(500), false, "Inactive cheap"),
                sample_ticket_type(true, None, false, "No current price"),
                sample_ticket_type(true, Some(3000), false, "General"),
                sample_ticket_type(true, Some(1500), true, "Sold out"),
                sample_ticket_type(true, Some(2000), false, "Regular"),
            ]),
            ..Default::default()
        };

        let ticket_titles: Vec<_> = event
            .visible_ticket_types()
            .into_iter()
            .map(|ticket_type| ticket_type.title.as_str())
            .collect();

        assert_eq!(ticket_titles, vec!["Sold out", "Regular", "General"]);
    }

    #[test]
    fn event_summary_formatted_ticket_price_badge_ignores_unsellable_tiers() {
        let event = sample_event_summary(vec![
            sample_ticket_type(false, Some(0), false, "Inactive free"),
            sample_ticket_type(true, Some(1000), true, "Sold out early bird"),
            sample_ticket_type(true, Some(2500), false, "General"),
        ]);

        assert_eq!(
            event.formatted_ticket_price_badge(),
            Some("From USD 25.00".to_string())
        );
    }

    #[test]
    fn event_summary_formatted_ticket_price_badge_returns_free_and_up_when_mixed() {
        let event = sample_event_summary(vec![
            sample_ticket_type(true, Some(0), false, "Free"),
            sample_ticket_type(true, Some(2500), false, "General"),
        ]);

        assert_eq!(
            event.formatted_ticket_price_badge(),
            Some("Free and up".to_string())
        );
    }

    #[test]
    fn event_summary_has_sellable_ticket_types_returns_false_when_no_tier_is_purchasable() {
        let event = sample_event_summary(vec![
            sample_ticket_type(false, Some(0), false, "Inactive free"),
            sample_ticket_type(true, Some(1000), true, "Sold out early bird"),
            sample_ticket_type(true, None, false, "No current price"),
        ]);

        assert!(!event.has_sellable_ticket_types());
        assert!(event.is_ticketed());
    }

    #[test]
    fn session_is_live_returns_false_when_ends_at_is_none() {
        let session = Session {
            starts_at: Utc::now() - Duration::hours(1),
            ..Default::default()
        };
        assert!(!session.is_live());
    }

    #[test]
    fn session_is_live_returns_false_when_session_ended() {
        let session = Session {
            ends_at: Some(Utc::now() - Duration::hours(1)),
            starts_at: Utc::now() - Duration::hours(2),
            ..Default::default()
        };
        assert!(!session.is_live());
    }

    #[test]
    fn session_is_live_returns_false_when_session_not_started() {
        let session = Session {
            ends_at: Some(Utc::now() + Duration::hours(2)),
            starts_at: Utc::now() + Duration::hours(1),
            ..Default::default()
        };
        assert!(!session.is_live());
    }

    #[test]
    fn session_is_live_returns_true_when_session_is_live() {
        let session = Session {
            ends_at: Some(Utc::now() + Duration::hours(1)),
            starts_at: Utc::now() - Duration::hours(1),
            ..Default::default()
        };
        assert!(session.is_live());
    }

    // Helpers.

    /// Build a sample ticket type with specified properties for testing.
    fn sample_ticket_type(
        active: bool,
        amount_minor: Option<i64>,
        sold_out: bool,
        title: &str,
    ) -> EventTicketType {
        EventTicketType {
            active,
            current_price: amount_minor.map(|amount_minor| EventTicketCurrentPrice {
                amount_minor,
                ..Default::default()
            }),
            event_ticket_type_id: Uuid::nil(),
            order: 1,
            price_windows: vec![],
            sold_out,
            title: title.to_string(),

            description: None,
            remaining_seats: None,
            seats_total: None,
        }
    }

    /// Build a sample event summary with specified ticket types for testing.
    fn sample_event_summary(ticket_types: Vec<EventTicketType>) -> EventSummary {
        EventSummary {
            attendee_approval_required: false,
            canceled: false,
            community_display_name: "Community".to_string(),
            community_name: "community".to_string(),
            event_id: Uuid::nil(),
            group_category_name: "Technology".to_string(),
            group_name: "Group".to_string(),
            group_slug: "group".to_string(),
            has_related_events: false,
            kind: EventKind::InPerson,
            logo_url: "https://example.com/logo.png".to_string(),
            name: "Event".to_string(),
            payment_currency_code: Some("USD".to_string()),
            published: true,
            slug: "event".to_string(),
            ticket_types: Some(ticket_types),
            timezone: chrono_tz::UTC,
            waitlist_count: 0,
            waitlist_enabled: false,

            capacity: None,
            description_short: None,
            ends_at: None,
            event_series_id: None,
            latitude: None,
            longitude: None,
            meeting_join_url: None,
            meeting_password: None,
            meeting_provider: None,
            popover_html: None,
            remaining_capacity: None,
            starts_at: None,
            venue_address: None,
            venue_city: None,
            venue_country_code: None,
            venue_country_name: None,
            venue_name: None,
            venue_state: None,
            zip_code: None,
        }
    }
}
