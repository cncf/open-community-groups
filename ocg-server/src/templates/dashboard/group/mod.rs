//! Templates for the group dashboard.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::types::event::EventSummary;

pub(crate) mod home;

/// Events page for the group dashboard.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/events.html")]
pub(crate) struct EventsPage {
    pub events: Vec<EventSummary>,
}
