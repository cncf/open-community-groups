//! This module defines the templates for the group site.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::{
    templates::dashboard::group::{spotlights::GroupMemberSpotlight, store::GroupStoreItem},
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
    /// Published member spotlights for homepage discovery.
    pub spotlights: Vec<GroupMemberSpotlight>,
    /// Active store items for homepage discovery.
    pub store_items: Vec<GroupStoreItem>,
    /// List of upcoming events for this group.
    pub upcoming_events: Vec<UpcomingEventCard>,
    /// Authenticated user information.
    pub user: User,
}

/// Logged-in group member spotlights page template.
#[derive(Debug, Clone, Template)]
#[template(path = "group/spotlights.html")]
pub(crate) struct SpotlightsPage {
    /// Configured public base URL.
    pub base_url: String,
    /// Detailed information about the group.
    pub group: GroupFull,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current URL path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Published member spotlights.
    pub spotlights: Vec<GroupMemberSpotlight>,
    /// Authenticated user information.
    pub user: User,
}

/// Public group store page.
#[derive(Debug, Clone, Template)]
#[template(path = "group/store.html")]
pub(crate) struct StorePage {
    /// Configured public base URL.
    pub base_url: String,
    /// Detailed information about the group.
    pub group: GroupFull,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current URL path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Active store items.
    pub store_items: Vec<GroupStoreItem>,
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
                self.group.alliance.name,
                self.group.public_slug()
            ),
        )
    }

    /// Returns the Open Graph image URL for the group page.
    pub(crate) fn open_graph_image_url(&self) -> Option<String> {
        self.group
            .og_image_url
            .as_deref()
            .or(self.group.alliance.og_image_url.as_deref())
            .map(|image_url| helpers::open_graph_image_url(&self.base_url, image_url))
    }

    /// Returns the preview description for the group page.
    pub(crate) fn preview_description(&self) -> String {
        format!(
            "{} alliance in Open Alliance Groups, where Open Source alliances thrive.",
            self.group.alliance.display_name
        )
    }

    /// Returns the preview title for the group page.
    pub(crate) fn preview_title(&self) -> String {
        self.group.name.clone()
    }
}

impl SpotlightsPage {
    /// Returns the canonical URL for the group spotlights page.
    pub(crate) fn canonical_url(&self) -> String {
        helpers::absolute_url(
            &self.base_url,
            &format!(
                "/{}/group/{}/spotlights",
                self.group.alliance.name,
                self.group.public_slug()
            ),
        )
    }

    /// Returns the preview title.
    pub(crate) fn preview_title(&self) -> String {
        format!("{} Member Spotlights", self.group.name)
    }

    /// Returns the preview description.
    pub(crate) fn preview_description(&self) -> String {
        format!("Success stories from members of {}.", self.group.name)
    }

    /// Returns the Open Graph image URL for the page.
    pub(crate) fn open_graph_image_url(&self) -> Option<String> {
        self.group
            .og_image_url
            .as_deref()
            .or(self.group.alliance.og_image_url.as_deref())
            .map(|image_url| helpers::open_graph_image_url(&self.base_url, image_url))
    }
}

impl StorePage {
    /// Returns the canonical URL for the group store page.
    pub(crate) fn canonical_url(&self) -> String {
        helpers::absolute_url(
            &self.base_url,
            &format!(
                "/{}/group/{}/store",
                self.group.alliance.name,
                self.group.public_slug()
            ),
        )
    }

    /// Returns the `OpenGraph` image URL for the group store page.
    pub(crate) fn open_graph_image_url(&self) -> Option<String> {
        self.group
            .og_image_url
            .as_deref()
            .or(self.group.alliance.og_image_url.as_deref())
            .map(|image_url| helpers::open_graph_image_url(&self.base_url, image_url))
    }

    /// Returns the preview description for the group store page.
    pub(crate) fn preview_description(&self) -> String {
        format!("Swag and items from {}.", self.group.name)
    }

    /// Returns the preview title for the group store page.
    pub(crate) fn preview_title(&self) -> String {
        format!("{} Store", self.group.name)
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
