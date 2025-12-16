//! Templates and types for managing events in the group dashboard.

use std::collections::HashMap;

use anyhow::Result;
use askama::Template;
use chrono::NaiveDateTime;
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    services::meetings::MeetingProvider,
    templates::{
        filters,
        helpers::{DATE_FORMAT, color},
    },
    types::event::{
        EventCategory, EventFull, EventKindSummary, EventSummary, SessionKind, SessionKindSummary,
    },
    types::group::GroupSponsor,
    validation::{
        MAX_LEN_L, MAX_LEN_M, MAX_LEN_S, MAX_LEN_XL, email_vec, image_url_opt, trimmed_non_empty,
        trimmed_non_empty_opt, trimmed_non_empty_vec, valid_latitude, valid_longitude,
    },
};

// Pages templates.

/// Add event page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/events_add.html")]
pub(crate) struct AddPage {
    /// Group identifier.
    pub group_id: Uuid,
    /// List of available event categories.
    pub categories: Vec<EventCategory>,
    /// List of available event kinds.
    pub event_kinds: Vec<EventKindSummary>,
    /// Flag indicating if meetings functionality is enabled.
    pub meetings_enabled: bool,
    /// Maximum participants per meeting provider.
    pub meetings_max_participants: HashMap<MeetingProvider, i32>,
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
    /// Group events split by upcoming and past ones.
    pub events: GroupEvents,
}

/// Update event page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/events_update.html")]
pub(crate) struct UpdatePage {
    /// Group identifier.
    pub group_id: Uuid,
    /// Event details to update.
    pub event: EventFull,
    /// List of available event categories.
    pub categories: Vec<EventCategory>,
    /// List of available event kinds.
    pub event_kinds: Vec<EventKindSummary>,
    /// Flag indicating if meetings functionality is enabled.
    pub meetings_enabled: bool,
    /// Maximum participants per meeting provider.
    pub meetings_max_participants: HashMap<MeetingProvider, i32>,
    /// List of available session kinds.
    pub session_kinds: Vec<SessionKindSummary>,
    /// List of sponsors available for this group.
    pub sponsors: Vec<GroupSponsor>,
    /// List of available timezones.
    pub timezones: Vec<String>,
}

// Types.

/// Event details for dashboard management.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Default, Validate)]
pub(crate) struct Event {
    /// Category this event belongs to.
    #[garde(skip)]
    pub category_id: Uuid,
    /// Event description.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_XL))]
    pub description: String,
    /// Type of event (in-person, virtual, hybrid).
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_S))]
    pub kind_id: String,
    /// Event name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub name: String,
    /// Timezone for the event.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_S))]
    pub timezone: String,

    /// Banner image URL.
    #[garde(custom(image_url_opt))]
    pub banner_url: Option<String>,
    /// Maximum capacity for the event.
    #[garde(range(min = 0))]
    pub capacity: Option<i32>,
    /// Short description of the event.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_L))]
    pub description_short: Option<String>,
    /// Event end time.
    #[garde(skip)]
    pub ends_at: Option<NaiveDateTime>,
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
    #[garde(custom(trimmed_non_empty_vec))]
    pub tags: Option<Vec<String>>,
    /// Venue address.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub venue_address: Option<String>,
    /// City where the venue is located.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub venue_city: Option<String>,
    /// Name of the venue.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub venue_name: Option<String>,
    /// Venue zip code.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub venue_zip_code: Option<String>,
}

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
    pub past: Vec<EventSummary>,
    /// Events happening in the future.
    pub upcoming: Vec<EventSummary>,
}

impl GroupEvents {
    /// Try to create group events split into past and upcoming from JSON.
    #[instrument(skip_all, err)]
    pub fn try_from_json(data: &str) -> Result<Self> {
        let mut events: Self = serde_json::from_str(data)?;

        for event in events.past.iter_mut().chain(events.upcoming.iter_mut()) {
            event.group_color = color(&event.group_name).to_string();
        }

        Ok(events)
    }
}

/// Event update details for past events (limited fields).
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Default, Validate)]
pub(crate) struct PastEventUpdate {
    /// Event description.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_XL))]
    pub description: String,

    /// Banner image URL.
    #[garde(custom(image_url_opt))]
    pub banner_url: Option<String>,
    /// Short description of the event.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_L))]
    pub description_short: Option<String>,
    /// URL to the event logo.
    #[garde(custom(image_url_opt))]
    pub logo_url: Option<String>,
    /// Recording URL for meeting.
    #[garde(url, length(max = MAX_LEN_L))]
    pub meeting_recording_url: Option<String>,
    /// Gallery of photo URLs.
    #[garde(custom(trimmed_non_empty_vec))]
    pub photos_urls: Option<Vec<String>>,
    /// Tags associated with the event.
    #[garde(custom(trimmed_non_empty_vec))]
    pub tags: Option<Vec<String>>,
}

/// Session details within an event.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct Session {
    /// Type of session (hybrid, in-person, virtual).
    #[garde(skip)]
    pub kind: SessionKind,
    /// Session name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub name: String,
    /// Unique identifier for the session.
    #[garde(skip)]
    pub session_id: Option<Uuid>,
    /// Session start time.
    #[garde(skip)]
    pub starts_at: NaiveDateTime,

    /// Session description.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_XL))]
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
