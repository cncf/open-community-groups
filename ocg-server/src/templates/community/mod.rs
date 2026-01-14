//! Templates and data structures for the community site.
//!
//! The home page displays an overview of the community including community statistics,
//! upcoming events (both in-person and virtual), and recently added groups.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::{
    templates::{PageId, auth::User, filters, helpers::user_initials},
    types::{
        community::CommunityFull,
        event::{EventKind, EventSummary},
        group::GroupSummary,
        site::SiteSettings,
    },
};

// Pages and sections templates.

/// Template for the community page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/page.html")]
pub(crate) struct Page {
    /// Community information.
    pub community: CommunityFull,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// List of groups recently added to the community.
    pub recently_added_groups: Vec<GroupCard>,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Aggregated statistics about groups, members, events, and attendees.
    pub stats: Stats,
    /// List of upcoming in-person events across all community groups.
    pub upcoming_in_person_events: Vec<EventCard>,
    /// List of upcoming virtual events across all community groups.
    pub upcoming_virtual_events: Vec<EventCard>,
    /// Authenticated user information.
    pub user: User,
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
#[template(path = "community/group_card.html")]
pub(crate) struct GroupCard {
    /// Group data
    pub group: GroupSummary,
}

/// Community statistics for the home page.
#[derive(Debug, Clone, Default, Template, Serialize, Deserialize)]
#[template(path = "community/stats.html")]
pub(crate) struct Stats {
    /// Total number of groups in the community.
    pub groups: i64,
    /// Total number of members across all groups.
    pub groups_members: i64,
    /// Total number of events hosted by all groups.
    pub events: i64,
    /// Total number of attendees across all events.
    pub events_attendees: i64,
}
