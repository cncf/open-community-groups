//! This module defines the templates for the event page.

use anyhow::Result;
use askama::Template;
use chrono::{DateTime, Utc};
use chrono_tz::Tz;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use tracing::instrument;
use uuid::Uuid;

use crate::templates::{common::User, community::common::EventKind, helpers::color};

/// Event page template.
#[allow(dead_code)]
#[derive(Debug, Clone, Template)]
#[template(path = "event/page.html")]
pub(crate) struct Page {
    /// Detailed information about the event.
    pub event: Event,
}

/// Detailed event information for the event page.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Event {
    /// Whether the event has been canceled.
    pub canceled: bool,
    /// Event category information.
    pub category_name: String,
    /// Generated color for visual distinction.
    #[serde(default)]
    pub color: String,
    /// When the event was created.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Full event description.
    pub description: String,
    /// Group hosting the event.
    pub group: GroupInfo,
    /// Event hosts.
    pub hosts: Vec<User>,
    /// Unique identifier for the event.
    #[serde(rename = "event_id")]
    pub id: Uuid,
    /// Type of event (in-person, online, hybrid).
    pub kind: EventKind,
    /// Event title.
    pub name: String,
    /// Event organizers (from group team).
    pub organizers: Vec<User>,
    /// Whether the event is published.
    pub published: bool,
    /// Event sessions.
    pub sessions: Vec<Session>,
    /// URL slug of the event.
    pub slug: String,
    /// Timezone for event times.
    pub timezone: Tz,

    /// URL to the event banner image.
    pub banner_url: Option<String>,
    /// Maximum capacity for the event.
    pub capacity: Option<i32>,
    /// Brief event description.
    pub description_short: Option<String>,
    /// Event end time in UTC.
    #[serde(with = "chrono::serde::ts_seconds_option")]
    pub ends_at: Option<DateTime<Utc>>,
    /// URL to the event logo.
    pub logo_url: Option<String>,
    /// Meetup.com URL for the event.
    pub meetup_url: Option<String>,
    /// URLs to event photos.
    pub photos_urls: Option<Vec<String>>,
    /// When the event was published.
    #[serde(with = "chrono::serde::ts_seconds_option")]
    pub published_at: Option<DateTime<Utc>>,
    /// URL for event recording.
    pub recording_url: Option<String>,
    /// Whether registration is required.
    pub registration_required: Option<bool>,
    /// Event start time in UTC.
    #[serde(with = "chrono::serde::ts_seconds_option")]
    pub starts_at: Option<DateTime<Utc>>,
    /// URL for live streaming.
    pub streaming_url: Option<String>,
    /// Event tags for categorization.
    pub tags: Option<Vec<String>>,
    /// Street address of the venue.
    pub venue_address: Option<String>,
    /// City where the event takes place.
    pub venue_city: Option<String>,
    /// Name of the venue.
    pub venue_name: Option<String>,
    /// Venue zip code.
    pub venue_zip_code: Option<String>,
}

impl Event {
    /// Try to create an `Event` instance from a JSON string.
    #[instrument(skip_all, err)]
    pub(crate) fn try_from_json(data: &str) -> Result<Self> {
        let mut event: Event = serde_json::from_str(data)?;
        event.color = color(&event.name).to_string();
        Ok(event)
    }
}

/// Basic group information for event context.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupInfo {
    /// Category of the hosting group.
    pub category_name: String,
    /// Group name.
    pub name: String,
    /// URL slug of the hosting group.
    pub slug: String,
}

/// Session information within an event.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Session {
    /// Full session description.
    pub description: String,
    /// Session end time in UTC.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub ends_at: DateTime<Utc>,
    /// Unique identifier for the session.
    #[serde(rename = "session_id")]
    pub id: Uuid,
    /// Type of session (in-person, virtual).
    pub kind: SessionKind,
    /// Session title.
    pub name: String,
    /// Session speakers.
    pub speakers: Vec<User>,
    /// Session start time in UTC.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub starts_at: DateTime<Utc>,

    /// Location details for the session.
    pub location: Option<String>,
    /// URL for session recording.
    pub recording_url: Option<String>,
    /// URL for session live stream.
    pub streaming_url: Option<String>,
}

/// Categorization of session attendance modes.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum SessionKind {
    #[default]
    InPerson,
    Virtual,
}

impl std::fmt::Display for SessionKind {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            SessionKind::InPerson => write!(f, "in-person"),
            SessionKind::Virtual => write!(f, "virtual"),
        }
    }
}
