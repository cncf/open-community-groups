//! Event type definitions.

use std::collections::BTreeMap;

use anyhow::Result;
use chrono::{DateTime, NaiveDate, Utc};
use chrono_tz::Tz;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    templates::{
        common::User,
        helpers::{
            color,
            location::{LocationParts, build_location},
        },
    },
    types::group::GroupSummary,
};

/// Summary event information.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventSummary {
    /// Whether the event has been canceled.
    pub canceled: bool,
    /// Unique identifier for the event.
    pub event_id: Uuid,
    /// Color associated with the group hosting this event, used for visual styling.
    #[serde(default)]
    pub group_color: String,
    /// Name of the group hosting this event.
    pub group_name: String,
    /// URL-friendly identifier for the group hosting this event.
    pub group_slug: String,
    /// Type of event (in-person or virtual).
    pub kind: EventKind,
    /// Display name of the event.
    pub name: String,
    /// Whether the event is published.
    pub published: bool,
    /// URL-friendly identifier for this event.
    pub slug: String,
    /// Timezone in which the event times should be displayed.
    pub timezone: Tz,

    /// City where the group is located (may differ from venue city).
    pub group_city: Option<String>,
    /// ISO country code of the group's location.
    pub group_country_code: Option<String>,
    /// Full country name of the group's location.
    pub group_country_name: Option<String>,
    /// State or province where the group is located.
    pub group_state: Option<String>,
    /// URL to the event or group's logo image.
    pub logo_url: Option<String>,
    /// UTC timestamp when the event starts.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub starts_at: Option<DateTime<Utc>>,
    /// City where the event venue is located (for in-person events).
    pub venue_city: Option<String>,
}

impl From<EventDetailed> for EventSummary {
    fn from(event: EventDetailed) -> Self {
        Self {
            canceled: event.canceled,
            event_id: event.event_id,
            group_color: event.group_color,
            group_name: event.group_name,
            group_slug: event.group_slug,
            kind: event.kind,
            name: event.name,
            published: event.published,
            slug: event.slug,
            timezone: event.timezone,

            group_city: event.group_city,
            group_country_code: event.group_country_code,
            group_country_name: event.group_country_name,
            group_state: event.group_state,
            logo_url: event.logo_url,
            starts_at: event.starts_at,
            venue_city: event.venue_city,
        }
    }
}

impl EventSummary {
    /// Build a display-friendly location string from available location data.
    pub fn location(&self, max_len: usize) -> Option<String> {
        let parts = LocationParts::new()
            .group_city(self.group_city.as_ref())
            .group_country_code(self.group_country_code.as_ref())
            .group_country_name(self.group_country_name.as_ref())
            .group_state(self.group_state.as_ref())
            .venue_city(self.venue_city.as_ref());

        build_location(&parts, max_len)
    }

    /// Try to create a vector of `EventSummary` instances from a JSON string.
    #[instrument(skip_all, err)]
    pub fn try_from_json_array(data: &str) -> Result<Vec<Self>> {
        let mut events: Vec<Self> = serde_json::from_str(data)?;

        for event in &mut events {
            event.group_color = color(&event.group_name).to_string();
        }

        Ok(events)
    }

    /// Try to create an `EventSummary` instance from a JSON string.
    #[instrument(skip_all, err)]
    pub fn try_from_json(data: &str) -> Result<Self> {
        let mut event: Self = serde_json::from_str(data)?;
        event.group_color = color(&event.group_name).to_string();
        Ok(event)
    }
}

/// Detailed event information.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct EventDetailed {
    /// Whether the event has been canceled.
    pub canceled: bool,
    /// Unique identifier for the event.
    pub event_id: Uuid,
    /// Category of the hosting group.
    pub group_category_name: String,
    /// Generated color for visual distinction.
    #[serde(default)]
    pub group_color: String,
    /// Name of the group hosting the event.
    pub group_name: String,
    /// URL slug of the hosting group.
    pub group_slug: String,
    /// Type of event (in-person, online, hybrid).
    pub kind: EventKind,
    /// Event title.
    pub name: String,
    /// Whether the event is published.
    pub published: bool,
    /// URL slug of the event.
    pub slug: String,
    /// Timezone for event times.
    pub timezone: Tz,

    /// Brief event description for listings.
    pub description_short: Option<String>,
    /// Event end time in UTC.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub ends_at: Option<DateTime<Utc>>,
    /// City where the group is based.
    pub group_city: Option<String>,
    /// ISO country code of the group.
    pub group_country_code: Option<String>,
    /// Full country name of the group.
    pub group_country_name: Option<String>,
    /// State/province where the group is based.
    pub group_state: Option<String>,
    /// Latitude for map display.
    pub latitude: Option<f64>,
    /// URL to the event or group logo.
    pub logo_url: Option<String>,
    /// Longitude for map display.
    pub longitude: Option<f64>,
    /// Pre-rendered HTML for map/calendar popovers.
    pub popover_html: Option<String>,
    /// Event start time in UTC.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub starts_at: Option<DateTime<Utc>>,
    /// Street address of the venue.
    pub venue_address: Option<String>,
    /// City where the event takes place.
    pub venue_city: Option<String>,
    /// Name of the venue.
    pub venue_name: Option<String>,
}

impl EventDetailed {
    /// Build a display-friendly location string from available location data.
    pub fn location(&self, max_len: usize) -> Option<String> {
        let parts = LocationParts::new()
            .group_city(self.group_city.as_ref())
            .group_country_code(self.group_country_code.as_ref())
            .group_country_name(self.group_country_name.as_ref())
            .group_state(self.group_state.as_ref())
            .venue_address(self.venue_address.as_ref())
            .venue_city(self.venue_city.as_ref())
            .venue_name(self.venue_name.as_ref());

        build_location(&parts, max_len)
    }

    /// Try to create a vector of `EventDetailed` instances from a JSON string.
    #[instrument(skip_all, err)]
    pub fn try_from_json_array(data: &str) -> Result<Vec<Self>> {
        let mut events: Vec<Self> = serde_json::from_str(data)?;

        for event in &mut events {
            event.group_color = color(&event.group_name).to_string();
        }

        Ok(events)
    }
}

/// Full event information.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventFull {
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
    pub group: GroupSummary,
    /// Event hosts.
    pub hosts: Vec<User>,
    /// Unique identifier for the event.
    pub event_id: Uuid,
    /// Type of event (in-person, online, hybrid).
    pub kind: EventKind,
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
    /// Event sponsors.
    pub sponsors: Vec<EventSponsor>,
    /// Timezone for event times.
    pub timezone: Tz,

    /// URL to the event banner image.
    pub banner_url: Option<String>,
    /// Maximum capacity for the event.
    pub capacity: Option<i32>,
    /// Brief event description.
    pub description_short: Option<String>,
    /// Event end time in UTC.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub ends_at: Option<DateTime<Utc>>,
    /// Latitude for map display.
    pub latitude: Option<f64>,
    /// Legacy event hosts.
    pub legacy_hosts: Option<Vec<LegacyUser>>,
    /// Legacy event speakers.
    pub legacy_speakers: Option<Vec<LegacyUser>>,
    /// URL to the event logo.
    pub logo_url: Option<String>,
    /// Longitude for map display.
    pub longitude: Option<f64>,
    /// Meetup.com URL for the event.
    pub meetup_url: Option<String>,
    /// URLs to event photos.
    pub photos_urls: Option<Vec<String>>,
    /// When the event was published.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub published_at: Option<DateTime<Utc>>,
    /// URL for event recording.
    pub recording_url: Option<String>,
    /// Whether registration is required.
    pub registration_required: Option<bool>,
    /// Event start time in UTC.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
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

impl EventFull {
    /// Build a display-friendly location string from available location data.
    pub fn location(&self, max_len: usize) -> Option<String> {
        let parts = LocationParts::new()
            .group_city(self.group.city.as_ref())
            .group_country_code(self.group.country_code.as_ref())
            .group_country_name(self.group.country_name.as_ref())
            .group_state(self.group.state.as_ref())
            .venue_address(self.venue_address.as_ref())
            .venue_city(self.venue_city.as_ref())
            .venue_name(self.venue_name.as_ref());

        build_location(&parts, max_len)
    }

    /// Try to create an `EventFull` instance from a JSON string.
    #[instrument(skip_all, err)]
    pub fn try_from_json(data: &str) -> Result<Self> {
        let mut event: EventFull = serde_json::from_str(data)?;
        event.color = color(&event.name).to_string();
        Ok(event)
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
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    /// Type of session (hybrid, in-person, virtual).
    pub kind: SessionKind,
    /// Session title.
    pub name: String,
    /// Unique identifier for the session.
    pub session_id: Uuid,
    /// Session speakers.
    pub speakers: Vec<User>,
    /// Session start time in UTC.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub starts_at: DateTime<Utc>,

    /// Full session description.
    pub description: Option<String>,
    /// Session end time in UTC.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub ends_at: Option<DateTime<Utc>>,
    /// Location details for the session.
    pub location: Option<String>,
    /// URL for session recording.
    pub recording_url: Option<String>,
    /// URL for session live stream.
    pub streaming_url: Option<String>,
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
