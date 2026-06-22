//! Templates and data structures for the alliance site.
//!
//! The home page displays an overview of the alliance including alliance statistics,
//! upcoming events (both in-person and virtual), and recently added groups.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::{
    templates::{
        PageId,
        auth::User,
        filters,
        helpers::{self, user_initials},
    },
    types::{
        alliance::AllianceFull,
        event::{EventKind, EventSummary},
        group::GroupSummary,
        site::SiteSettings,
    },
};

/// Link preview description for alliance pages.
pub(crate) const PREVIEW_DESCRIPTION: &str =
    "Open Alliance Groups, where Open Source alliances thrive.";

// Pages and sections templates.

/// Template for the alliance page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "alliance/page.html")]
pub(crate) struct Page {
    /// Configured public base URL.
    pub base_url: String,
    /// Alliance information.
    pub alliance: AllianceFull,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// List of groups recently added to the alliance.
    pub recently_added_groups: Vec<GroupCard>,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Aggregated statistics about groups, members, events, and attendees.
    pub stats: Stats,
    /// List of upcoming in-person events across all alliance groups.
    pub upcoming_in_person_events: Vec<EventCard>,
    /// List of upcoming virtual events across all alliance groups.
    pub upcoming_virtual_events: Vec<EventCard>,
    /// Authenticated user information.
    pub user: User,
}

impl Page {
    /// Returns the canonical public URL for the alliance page.
    pub(crate) fn canonical_url(&self) -> String {
        helpers::absolute_url(&self.base_url, &format!("/{}", self.alliance.name))
    }

    /// Returns the Open Graph image URL for the alliance page.
    pub(crate) fn open_graph_image_url(&self) -> Option<String> {
        self.alliance
            .og_image_url
            .as_deref()
            .map(|image_url| helpers::open_graph_image_url(&self.base_url, image_url))
    }

    /// Returns the preview title for the alliance page.
    pub(crate) fn preview_title(&self) -> String {
        format!("{} alliance", self.alliance.display_name)
    }
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
#[template(path = "alliance/group_card.html")]
pub(crate) struct GroupCard {
    /// Group data
    pub group: GroupSummary,
}

/// Alliance statistics for the home page.
#[derive(Debug, Clone, Default, Template, Serialize, Deserialize)]
#[template(path = "alliance/stats.html")]
pub(crate) struct Stats {
    /// Total number of groups in the alliance.
    pub groups: i64,
    /// Total number of members across all groups.
    pub groups_members: i64,
    /// Total number of events hosted by all groups.
    pub events: i64,
    /// Total number of attendees across all events.
    pub events_attendees: i64,
}
