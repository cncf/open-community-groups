//! Templates and data structures for the home page of the community site.
//!
//! The home page displays an overview of the community including community statistics,
//! upcoming events (both in-person and virtual), and recently added groups.

use anyhow::Result;
use askama::Template;
use serde::{Deserialize, Serialize};
use tracing::instrument;

use crate::{
    templates::filters,
    types::{
        community::Community,
        event::{EventKind, EventSummary},
        group::GroupSummary,
    },
};

// Pages and sections templates.

/// Template for the community home page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/home/page.html")]
pub(crate) struct Page {
    /// Community information including name, logo, and other metadata.
    pub community: Community,
    /// Current request path.
    pub path: String,
    /// List of groups recently added to the community.
    pub recently_added_groups: Vec<GroupCard>,
    /// List of upcoming in-person events across all community groups.
    pub upcoming_in_person_events: Vec<EventCard>,
    /// List of upcoming virtual events across all community groups.
    pub upcoming_virtual_events: Vec<EventCard>,
    /// Aggregated statistics about groups, members, events, and attendees.
    pub stats: Stats,
}

/// Event card template for home page display.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "common/event_card_small.html")]
pub(crate) struct EventCard {
    /// Event data
    pub event: EventSummary,
}

/// Group card template for home page display.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/home/group_card.html")]
pub(crate) struct GroupCard {
    /// Group data
    pub group: GroupSummary,
}

/// Community statistics for the home page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/home/stats.html")]
pub(crate) struct Stats {
    /// Total number of groups in the community.
    groups: i64,
    /// Total number of members across all groups.
    groups_members: i64,
    /// Total number of events hosted by all groups.
    events: i64,
    /// Total number of attendees across all events.
    events_attendees: i64,
}

impl Stats {
    /// Try to create a `Stats` instance from a JSON string.
    #[instrument(skip_all, err)]
    pub(crate) fn try_from_json(data: &str) -> Result<Self> {
        let stats: Stats = serde_json::from_str(data)?;
        Ok(stats)
    }
}
