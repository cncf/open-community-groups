//! Templates and types for managing events in the group dashboard.

use anyhow::Result;
use askama::Template;
use chrono::NaiveDateTime;
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
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub(crate) struct Event {
    /// Event name.
    pub name: String,
    /// URL-friendly identifier.
    pub slug: String,
    /// Event description.
    pub description: String,
    /// Timezone for the event.
    pub timezone: String,
    /// Category this event belongs to.
    pub category_id: Uuid,
    /// Type of event (in-person, virtual, hybrid).
    pub kind_id: String,

    /// Banner image URL.
    pub banner_url: Option<String>,
    /// Maximum capacity for the event.
    pub capacity: Option<i32>,
    /// Short description of the event.
    pub description_short: Option<String>,
    /// Event end time.
    pub ends_at: Option<NaiveDateTime>,
    /// User IDs of event hosts.
    pub hosts: Option<Vec<Uuid>>,
    /// URL to the event logo.
    pub logo_url: Option<String>,
    /// Meeting hosts to synchronize with provider (email addresses).
    pub meeting_hosts: Option<Vec<String>>,
    /// URL to join the meeting.
    pub meeting_join_url: Option<String>,
    /// Desired meeting provider.
    #[serde(rename = "meeting_provider_id")]
    pub meeting_provider: Option<MeetingProvider>,
    /// Recording URL for meeting.
    pub meeting_recording_url: Option<String>,
    /// Whether a meeting has been requested for the event.
    pub meeting_requested: Option<bool>,
    /// Whether the event meeting requires a password.
    pub meeting_requires_password: Option<bool>,
    /// Meetup.com URL.
    pub meetup_url: Option<String>,
    /// Gallery of photo URLs.
    pub photos_urls: Option<Vec<String>>,
    /// Whether registration is required.
    pub registration_required: Option<bool>,
    /// Event sessions.
    pub sessions: Option<Vec<Session>>,
    /// Event-level speakers.
    pub speakers: Option<Vec<Speaker>>,
    /// Event sponsors.
    pub sponsors: Option<Vec<EventSponsor>>,
    /// Event start time.
    pub starts_at: Option<NaiveDateTime>,
    /// Tags associated with the event.
    pub tags: Option<Vec<String>>,
    /// Venue address.
    pub venue_address: Option<String>,
    /// City where the venue is located.
    pub venue_city: Option<String>,
    /// Name of the venue.
    pub venue_name: Option<String>,
    /// Venue zip code.
    pub venue_zip_code: Option<String>,
}

/// Event sponsor information.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventSponsor {
    /// Group sponsor identifier.
    pub group_sponsor_id: Uuid,
    /// Sponsor level for this event.
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

/// Session details within an event.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Session {
    /// Type of session (hybrid, in-person, virtual).
    pub kind: SessionKind,
    /// Session name.
    pub name: String,
    /// Unique identifier for the session.
    pub session_id: Option<Uuid>,
    /// Session start time.
    pub starts_at: NaiveDateTime,

    /// Session description.
    pub description: Option<String>,
    /// Session end time.
    pub ends_at: Option<NaiveDateTime>,
    /// Location for the session.
    pub location: Option<String>,
    /// Meeting hosts to synchronize with provider (email addresses).
    pub meeting_hosts: Option<Vec<String>>,
    /// URL to join the meeting.
    pub meeting_join_url: Option<String>,
    /// Desired meeting provider.
    #[serde(rename = "meeting_provider_id")]
    pub meeting_provider: Option<MeetingProvider>,
    /// Recording URL for meeting.
    pub meeting_recording_url: Option<String>,
    /// Whether a meeting has been requested for the session.
    pub meeting_requested: Option<bool>,
    /// Whether the session meeting requires a password.
    pub meeting_requires_password: Option<bool>,
    /// Session speakers.
    pub speakers: Option<Vec<Speaker>>,
}

/// Speaker selection with optional featured flag.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Speaker {
    /// Whether the speaker is featured.
    #[serde(default)]
    pub featured: bool,
    /// Unique identifier for the speaker.
    pub user_id: Uuid,
}
