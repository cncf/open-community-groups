//! Templates and types for attendee check-in credentials.

use askama::Template;
use chrono::{DateTime, Utc};
use chrono_tz::Tz;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::types::event::EventKind;

// Pages templates.

/// User check-in event list template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/user/check_in_list.html")]
pub(crate) struct ListPage {
    /// Events carrying an attendee credential.
    pub events: Vec<UserCheckInEvent>,
    /// User's display name.
    pub name: String,
    /// User's username.
    pub username: String,

    /// User's profile photo URL.
    pub photo_url: Option<String>,
}

// Types.

/// Event carrying the user's attendee check-in credential.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct UserCheckInEvent {
    /// Whether the attendee is already checked in.
    pub checked_in: bool,
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

    /// Event logo URL.
    pub logo_url: Option<String>,
    /// Event venue summary.
    pub location: Option<String>,
    /// Ticket title snapshot shown with the credential.
    pub ticket_title: Option<String>,
}
