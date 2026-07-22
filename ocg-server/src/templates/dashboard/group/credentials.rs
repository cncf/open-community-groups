//! Templates for the Credentials tab in the group dashboard.

use askama::Template;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    templates::helpers::user_initials,
    types::event::EventSummary,
};

use super::attendees::Attendee;

/// Credentials tab page for a group's event.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/credentials_list.html")]
pub(crate) struct ListPage {
    /// Attendees for the selected event (status filled in by JS).
    pub attendees: Vec<Attendee>,
    /// Whether the current user can manage events (issue credentials).
    pub can_manage_events: bool,
    /// Event for which credentials are managed.
    pub event: EventSummary,
    /// Selected group id (used as the localStorage key for the API key).
    pub group_id: Uuid,
    /// Total number of attendees.
    pub total: usize,
}
