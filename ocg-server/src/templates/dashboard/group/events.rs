//! Templates and types for managing events in the group dashboard.

use askama::Template;
use chrono::NaiveDateTime;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    templates::{filters, helpers::DATE_FORMAT},
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
    /// List of events in the group.
    pub events: Vec<EventSummary>,
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
#[derive(Debug, Clone, Serialize, Deserialize)]
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
    /// Meetup.com URL.
    pub meetup_url: Option<String>,
    /// Gallery of photo URLs.
    pub photos_urls: Option<Vec<String>>,
    /// Recording URL.
    pub recording_url: Option<String>,
    /// Whether registration is required.
    pub registration_required: Option<bool>,
    /// Event sessions with speakers.
    pub sessions: Option<Vec<Session>>,
    /// Event sponsors.
    pub sponsors: Option<Vec<EventSponsor>>,
    /// Event start time.
    pub starts_at: Option<NaiveDateTime>,
    /// Streaming URL.
    pub streaming_url: Option<String>,
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

/// Session details within an event.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Session {
    /// Type of session (hybrid, in-person, virtual).
    pub kind: SessionKind,
    /// Session name.
    pub name: String,
    /// Session start time.
    pub starts_at: NaiveDateTime,

    /// Session description.
    pub description: Option<String>,
    /// Session end time.
    pub ends_at: Option<NaiveDateTime>,
    /// Location for the session.
    pub location: Option<String>,
    /// Recording URL for the session.
    pub recording_url: Option<String>,
    /// User IDs of session speakers.
    pub speakers: Option<Vec<Uuid>>,
    /// Streaming URL for the session.
    pub streaming_url: Option<String>,
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
