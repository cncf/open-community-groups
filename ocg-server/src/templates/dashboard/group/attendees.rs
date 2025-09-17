//! Templates and types for listing event attendees in the group dashboard.

use anyhow::Result;
use askama::Template;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    templates::{filters, helpers::user_initials},
    types::event::EventSummary,
};

// Pages templates.

/// List attendees page template for a group's event.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/attendees_list.html")]
pub(crate) struct ListPage {
    /// List of attendees for the selected event.
    pub attendees: Vec<Attendee>,
    /// Applied filters.
    pub filters: AttendeesFilters,
    /// Available filters options.
    pub filters_options: AttendeesFilterOptions,
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
    /// Username.
    pub username: String,

    /// Company the user represents.
    pub company: Option<String>,
    /// Full name.
    pub name: Option<String>,
    /// URL to user's avatar.
    pub photo_url: Option<String>,
    /// Title held by the user.
    pub title: Option<String>,
}

impl Attendee {
    /// Try to create a vector of `Attendee` from a JSON array string.
    #[instrument(skip_all, err)]
    pub fn try_from_json_array(data: &str) -> Result<Vec<Self>> {
        let attendees: Vec<Self> = serde_json::from_str(data)?;
        Ok(attendees)
    }
}

/// Filter parameters for attendees searches.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AttendeesFilters {
    /// Selected event to scope attendees list.
    pub event_id: Option<Uuid>,
}

/// Available options for attendees filters.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AttendeesFilterOptions {
    /// Events available for selection.
    pub events: Vec<EventSummary>,
}
