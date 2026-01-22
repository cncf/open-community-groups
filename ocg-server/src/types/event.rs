//! Event type definitions.

use std::collections::{BTreeMap, HashSet};

use chrono::{DateTime, NaiveDate, Utc};
use chrono_tz::Tz;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    services::meetings::MeetingProvider,
    templates::{
        common::User,
        helpers::location::{LocationParts, build_location},
    },
    types::{community::CommunitySummary, group::GroupSummary},
};

// Event types: summary and full.

/// Summary event information.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventSummary {
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

    /// Maximum capacity for the event.
    pub capacity: Option<i32>,
    /// Brief event description for listings.
    pub description_short: Option<String>,
    /// Event end time in UTC.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub ends_at: Option<DateTime<Utc>>,
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
    /// Venue zip code.
    pub zip_code: Option<String>,
}

impl EventSummary {
    /// Check if the event is in the past.
    pub fn is_past(&self) -> bool {
        let reference_time = self.ends_at.or(self.starts_at);
        match reference_time {
            Some(time) => time < Utc::now(),
            None => false,
        }
    }

    /// Build a display-friendly location string from available location data.
    pub fn location(&self, max_len: usize) -> Option<String> {
        let parts = LocationParts::new()
            .address(self.venue_address.as_ref())
            .city(self.venue_city.as_ref())
            .country_code(self.venue_country_code.as_ref())
            .country_name(self.venue_country_name.as_ref())
            .name(self.venue_name.as_ref())
            .state(self.venue_state.as_ref());

        build_location(&parts, max_len)
    }
}

/// Full event information.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct EventFull {
    /// Whether the event has been canceled.
    pub canceled: bool,
    /// Event category information.
    pub category_name: String,
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

    /// URL to the event banner image optimized for mobile devices.
    pub banner_mobile_url: Option<String>,
    /// URL to the event banner image.
    pub banner_url: Option<String>,
    /// Maximum capacity for the event.
    pub capacity: Option<i32>,
    /// Brief event description.
    pub description_short: Option<String>,
    /// Event end time in UTC.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub ends_at: Option<DateTime<Utc>>,
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
    /// Check if the event is currently live.
    #[allow(dead_code)]
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
    #[allow(dead_code)]
    pub fn is_past(&self) -> bool {
        let reference_time = self.ends_at.or(self.starts_at);
        match reference_time {
            Some(time) => time < Utc::now(),
            None => false,
        }
    }

    /// Build a display-friendly location string from available location data.
    pub fn location(&self, max_len: usize) -> Option<String> {
        let parts = LocationParts::new()
            .address(self.venue_address.as_ref())
            .city(self.venue_city.as_ref())
            .country_code(self.venue_country_code.as_ref())
            .country_name(self.venue_country_name.as_ref())
            .name(self.venue_name.as_ref())
            .state(self.venue_state.as_ref());

        build_location(&parts, max_len)
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
}

impl From<&EventFull> for EventSummary {
    fn from(event: &EventFull) -> Self {
        EventSummary {
            canceled: event.canceled,
            community_display_name: event.community.display_name.clone(),
            community_name: event.community.name.clone(),
            event_id: event.event_id,
            group_category_name: event.group.category.name.clone(),
            group_name: event.group.name.clone(),
            group_slug: event.group.slug.clone(),
            kind: event.kind.clone(),
            logo_url: event.logo_url.clone(),
            name: event.name.clone(),
            published: event.published,
            slug: event.slug.clone(),
            timezone: event.timezone,

            capacity: event.capacity,
            description_short: event.description_short.clone(),
            ends_at: event.ends_at,
            latitude: event.latitude,
            longitude: event.longitude,
            meeting_join_url: event.meeting_join_url.clone(),
            meeting_password: event.meeting_password.clone(),
            meeting_provider: event.meeting_provider,
            popover_html: None,
            remaining_capacity: event.remaining_capacity,
            starts_at: event.starts_at,
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

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use chrono::{Duration, Utc};

    use super::*;

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
}
