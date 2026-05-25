//! This module defines the templates for the group site.

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
        event::{EventKind, EventSummary},
        group::GroupFull,
        site::SiteSettings,
    },
};

// Pages and sections templates.

/// Group page template.
#[derive(Debug, Clone, Template)]
#[template(path = "group/page.html")]
pub(crate) struct Page {
    /// Configured public base URL.
    pub base_url: String,
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

impl Page {
    /// Returns the canonical public URL for the group page.
    pub(crate) fn canonical_url(&self) -> String {
        helpers::absolute_url(
            &self.base_url,
            &format!(
                "/{}/group/{}",
                self.group.community.name,
                self.group.public_slug()
            ),
        )
    }

    /// Returns the Open Graph image URL for the group page.
    pub(crate) fn open_graph_image_url(&self) -> Option<String> {
        self.group
            .og_image_url
            .as_deref()
            .or(self.group.community.og_image_url.as_deref())
            .map(|image_url| helpers::open_graph_image_url(&self.base_url, image_url))
    }

    /// Returns the preview title for the group page.
    pub(crate) fn preview_title(&self) -> String {
        format!("{} | {}", self.group.name, self.group.community.display_name)
    }
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
