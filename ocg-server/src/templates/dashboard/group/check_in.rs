//! Templates and types for group attendee check-in.

use askama::Template;
use chrono::{DateTime, Utc};
use chrono_tz::Tz;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::types::event::EventKind;

// Pages templates.

/// Group check-in event list template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/check_in_list.html")]
pub(crate) struct ListPage {
    /// Events available to the scanner.
    pub events: Vec<GroupCheckInEvent>,
}

// Types.

/// Event available to a group's check-in scanner.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupCheckInEvent {
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
}

/// Public attendee identity returned after a scan.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct CheckInAttendee {
    /// Attendee username.
    pub username: String,

    /// Attendee full name.
    pub name: Option<String>,
    /// Attendee profile photo URL.
    pub photo_url: Option<String>,
}

/// Stable outcome returned by a credential scan.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum CheckInOutcome {
    /// The attendee was already checked in.
    AlreadyCheckedIn,
    /// The scan recorded the attendee's first check-in.
    CheckedIn,
}

/// Successful attendee credential scan response.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct CheckInScanResult {
    /// Attendee identity shown to the scanner operator.
    pub attendee: CheckInAttendee,
    /// Durable check-in timestamp.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub checked_in_at: DateTime<Utc>,
    /// Check-in transition outcome.
    pub outcome: CheckInOutcome,

    /// Ticket title snapshot shown to the scanner operator.
    pub ticket_title: Option<String>,
}
