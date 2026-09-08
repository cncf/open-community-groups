//! Meeting type definitions.

use std::time::Duration;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_with::{DefaultOnNull, DurationSecondsWithFrac, serde_as, skip_serializing_none};
use strum::{AsRefStr, Display, EnumString};
use uuid::Uuid;

/// Represents a meeting to be synced with the provider.
#[skip_serializing_none]
#[serde_as]
#[derive(Clone, Default, Deserialize, Serialize)]
pub(crate) struct Meeting {
    /// Provider used to host the meeting.
    #[serde(alias = "meeting_provider_id", default)]
    #[serde_as(deserialize_as = "DefaultOnNull")]
    pub provider: MeetingProvider,

    /// Whether the provider meeting should be deleted.
    pub delete: Option<bool>,
    /// Meeting duration.
    #[serde(alias = "duration_secs")]
    #[serde_as(deserialize_as = "Option<DurationSecondsWithFrac<f64>>")]
    pub duration: Option<Duration>,
    /// Owning event identifier for event-level meetings.
    pub event_id: Option<Uuid>,
    /// Explicit host email addresses.
    pub hosts: Option<Vec<String>>,
    /// Provider join URL.
    pub join_url: Option<String>,
    /// Local meeting identifier.
    pub meeting_id: Option<Uuid>,
    /// Provider meeting password.
    pub password: Option<String>,
    /// Provider host user assigned to the meeting.
    pub provider_host_user_id: Option<String>,
    /// Provider-assigned meeting identifier.
    pub provider_meeting_id: Option<String>,
    /// Whether automatic recording was requested.
    #[serde(alias = "meeting_recording_requested")]
    pub recording_requested: Option<bool>,
    /// Owning session identifier for session-level meetings.
    pub session_id: Option<Uuid>,
    /// Meeting start timestamp.
    pub starts_at: Option<DateTime<Utc>>,
    /// Timestamp identifying the active synchronization claim.
    #[serde(skip_serializing)]
    pub sync_claimed_at: Option<DateTime<Utc>>,
    /// Hash identifying the state covered by the synchronization claim.
    #[serde(skip_serializing)]
    pub sync_state_hash: Option<String>,
    /// IANA timezone used by the provider payload.
    pub timezone: Option<String>,
    /// Meeting topic shown by the provider.
    pub topic: Option<String>,
}

impl Meeting {
    /// Returns the end timestamp.
    pub(crate) fn ends_at(&self) -> Option<DateTime<Utc>> {
        let starts_at = self.starts_at?;
        let duration = self.duration?;
        let duration = chrono::Duration::from_std(duration).ok()?;

        starts_at.checked_add_signed(duration)
    }
}

/// Meeting provider options.
#[derive(
    AsRefStr,
    Clone,
    Copy,
    Debug,
    Default,
    Deserialize,
    Display,
    EnumString,
    Eq,
    Hash,
    PartialEq,
    Serialize,
)]
#[serde(rename_all = "lowercase")]
#[strum(serialize_all = "lowercase")]
pub(crate) enum MeetingProvider {
    /// Zoom meetings provider.
    #[default]
    Zoom,
}

/// Outcome stored after checking an overdue meeting for automatic ending.
#[derive(AsRefStr, Clone, Copy, Debug, Display, EnumString, Eq, PartialEq)]
#[strum(serialize_all = "snake_case")]
pub(crate) enum MeetingAutoEndCheckOutcome {
    /// Meeting had already stopped running.
    AlreadyNotRunning,
    /// Meeting was ended successfully.
    AutoEnded,
    /// Provider processing failed.
    Error,
    /// Provider meeting no longer exists.
    NotFound,
}
