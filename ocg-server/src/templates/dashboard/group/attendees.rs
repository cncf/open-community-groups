//! Templates and types for listing event attendees in the group dashboard.

use askama::Template;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{templates::helpers::user_initials, types::event::EventSummary};

// Pages templates.

/// List attendees page template for a group's event.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/attendees_list.html")]
pub(crate) struct ListPage {
    /// List of attendees for the selected event.
    pub attendees: Vec<Attendee>,
    /// Event for which attendees are listed.
    pub event: EventSummary,
}

// Types.

/// Event attendee summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Attendee {
    /// Whether the attendee has checked in.
    pub checked_in: bool,
    /// RSVP creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// User id.
    pub user_id: Uuid,
    /// Username.
    pub username: String,

    /// Timestamp when the attendee checked in.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub checked_in_at: Option<DateTime<Utc>>,
    /// Company the user represents.
    pub company: Option<String>,
    /// Full name.
    pub name: Option<String>,
    /// URL to user's avatar.
    pub photo_url: Option<String>,
    /// Title held by the user.
    pub title: Option<String>,
}

/// Filter parameters for attendees searches.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AttendeesFilters {
    /// Selected event to scope attendees list.
    pub event_id: Uuid,
}
