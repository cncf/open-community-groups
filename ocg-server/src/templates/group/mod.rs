//! This module defines the templates for the group site.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::{
    templates::{PageId, auth::User, filters, helpers::user_initials},
    types::{
        event::{EventKind, EventSummary},
        group::GroupFull,
        site::SiteSettings,
    },
};

// Pages and sections templates.

/// Group page template.
#[allow(dead_code)]
#[derive(Debug, Clone, Template)]
#[template(path = "group/page.html")]
pub(crate) struct Page {
    /// Detailed information about the group.
    pub group: GroupFull,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// List of past events for this group.
    pub past_events: Vec<PastEventCard>,
    /// Current URL path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// List of upcoming events for this group.
    pub upcoming_events: Vec<UpcomingEventCard>,
    /// Authenticated user information.
    pub user: User,
}

// Types

/// Event card template for past events using summary information.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "group/event_card.html")]
pub(crate) struct PastEventCard {
    /// Event data
    pub event: EventSummary,
}

/// Event card template for upcoming events using detailed information.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "group/event_card.html")]
pub(crate) struct UpcomingEventCard {
    /// Event data
    pub event: EventSummary,
}
