//! This module defines the templates for the group site.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::{
    templates::filters,
    types::event::{EventKind, EventSummary},
};

// Pages and sections templates.

/// Group page template.
#[allow(dead_code)]
#[derive(Debug, Clone, Template)]
#[template(path = "group/page.html")]
pub(crate) struct Page {
    /// Detailed information about the group.
    pub group: crate::types::group::GroupFull,
    /// List of past events for this group.
    pub past_events: Vec<EventCard>,
    /// List of upcoming events for this group.
    pub upcoming_events: Vec<EventCard>,
}

/// Event card template for group page display.
///
/// This template wraps the `EventSummary` data for rendering on the group page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "group/event_card.html")]
pub(crate) struct EventCard {
    /// Event data
    pub event: EventSummary,
}
