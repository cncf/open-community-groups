//! Templates for the global site home page.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::{
    templates::{PageId, auth::User, filters, helpers::user_initials},
    types::{
        community::CommunitySummary,
        event::{EventKind, EventSummary},
        group::GroupSummary,
        site::{SiteHomeStats, SiteSettings},
    },
};

// Pages and sections templates.

/// Template for rendering the global site home page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "site/home/page.html")]
pub struct Page {
    /// List of communities to display.
    pub communities: Vec<CommunitySummary>,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// List of groups recently added across all communities.
    pub recently_added_groups: Vec<GroupCard>,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Site statistics.
    pub stats: SiteHomeStats,
    /// List of upcoming in-person events across all communities.
    pub upcoming_in_person_events: Vec<EventCard>,
    /// List of upcoming virtual events across all communities.
    pub upcoming_virtual_events: Vec<EventCard>,
    /// Authenticated user information.
    pub user: User,
}

/// Event card template for home page display.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "site/home/event_card.html")]
pub struct EventCard {
    /// Event data.
    pub event: EventSummary,
}

/// Group card template for home page display.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "site/home/group_card.html")]
pub struct GroupCard {
    /// Group data.
    pub group: GroupSummary,
}
