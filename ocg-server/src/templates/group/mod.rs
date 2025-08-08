//! This module defines the templates for the group site.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::{
    templates::filters,
    types::{
        community::Community,
        event::{EventKind, EventSummary},
        group::GroupFull,
    },
};

// Pages and sections templates.

/// Group page template.
#[allow(dead_code)]
#[derive(Debug, Clone, Template)]
#[template(path = "group/page.html")]
pub(crate) struct Page {
    /// Community information.
    pub community: Community,
    /// Detailed information about the group.
    pub group: GroupFull,
    /// List of past events for this group.
    pub past_events: Vec<EventCard>,
    /// Current URL path.
    pub path: String,
    /// List of upcoming events for this group.
    pub upcoming_events: Vec<EventCard>,
}

/// Event card template for group page display.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "group/event_card.html")]
pub(crate) struct EventCard {
    /// Event data
    pub event: EventSummary,
}
