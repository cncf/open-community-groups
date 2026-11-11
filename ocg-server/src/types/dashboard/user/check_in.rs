//! User dashboard check-in types.

use chrono::{DateTime, Utc};
use chrono_tz::Tz;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::types::event::{EventCohostGroup, EventKind};

/// Event carrying the user's attendee check-in credential.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct UserCheckInEvent {
    /// Whether the attendee is already checked in.
    pub checked_in: bool,
    /// Groups publicly credited as co-hosts of the event.
    #[serde(default)]
    pub cohosts: Vec<EventCohostGroup>,
    /// Event identifier.
    pub event_id: Uuid,
    /// Whether the event is currently in progress.
    pub in_progress: bool,
    /// Event delivery kind.
    pub kind: EventKind,
    /// Event display name.
    pub name: String,
    /// Event start time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub starts_at: DateTime<Utc>,
    /// Event timezone.
    pub timezone: Tz,

    /// URL to the logo image shown in dark mode in place of `logo_url`,
    /// taken from the same level (event, group or community) as `logo_url`.
    pub logo_dark_url: Option<String>,
    /// Event logo URL.
    pub logo_url: Option<String>,
    /// Event venue summary.
    pub location: Option<String>,
    /// Ticket title snapshot shown with the credential.
    pub ticket_title: Option<String>,
}
