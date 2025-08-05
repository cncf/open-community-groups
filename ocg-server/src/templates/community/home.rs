//! Templates and data structures for the home page of the community site.
//!
//! The home page displays an overview of the community including community statistics,
//! upcoming events (both in-person and virtual), and recently added groups.

use anyhow::Result;
use askama::Template;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use tracing::instrument;

use crate::{
    templates::{
        filters,
        helpers::{LocationParts, build_location, color},
    },
    types::event::{EventKind, EventSummary},
};

use super::{common::Community, explore};

// Pages templates.

/// Template for the community home page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/home/page.html")]
pub(crate) struct Page {
    /// Community information including name, logo, and other metadata.
    pub community: Community,
    /// Current request path.
    pub path: String,
    /// List of groups recently added to the community.
    pub recently_added_groups: Vec<Group>,
    /// List of upcoming in-person events across all community groups.
    pub upcoming_in_person_events: Vec<EventCard>,
    /// List of upcoming virtual events across all community groups.
    pub upcoming_virtual_events: Vec<EventCard>,
    /// Aggregated statistics about groups, members, events, and attendees.
    pub stats: Stats,
}

/// Event card template for home page display.
///
/// This template wraps the `EventSummary` data for rendering on the home page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/home/event_card.html")]
pub(crate) struct EventCard {
    /// Event data
    pub event: EventSummary,
}

impl From<explore::EventCard> for EventCard {
    fn from(ee: explore::EventCard) -> Self {
        Self {
            event: EventSummary {
                group_color: ee.event.group_color,
                group_name: ee.event.group_name,
                group_slug: ee.event.group_slug,
                kind: ee.event.kind,
                name: ee.event.name,
                slug: ee.event.slug,
                timezone: ee.event.timezone,

                group_city: ee.event.group_city,
                group_country_code: ee.event.group_country_code,
                group_country_name: ee.event.group_country_name,
                group_state: ee.event.group_state,
                logo_url: ee.event.logo_url,
                starts_at: ee.event.starts_at,
                venue_city: ee.event.venue_city,
            },
        }
    }
}

/// Group data structure for home page display.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/home/group.html")]
pub(crate) struct Group {
    /// Name of the category this group belongs to.
    pub category_name: String,
    /// Color associated with this group, used for visual styling.
    #[serde(default)]
    pub color: String,
    /// UTC timestamp when the group was created.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Display name of the group.
    pub name: String,
    /// URL-friendly identifier for this group.
    pub slug: String,

    /// City where the group is located.
    pub city: Option<String>,
    /// ISO country code of the group's location.
    pub country_code: Option<String>,
    /// Full country name of the group's location.
    pub country_name: Option<String>,
    /// URL to the group's logo image.
    pub logo_url: Option<String>,
    /// Geographic region name where the group is located.
    pub region_name: Option<String>,
    /// State or province where the group is located.
    pub state: Option<String>,
}

impl Group {
    /// Builds a formatted location string for the group.
    pub(crate) fn location(&self, max_len: usize) -> Option<String> {
        let parts = LocationParts::new()
            .group_city(self.city.as_ref())
            .group_country_code(self.country_code.as_ref())
            .group_country_name(self.country_name.as_ref())
            .group_state(self.state.as_ref());

        build_location(&parts, max_len)
    }

    /// Try to create a vector of `Group` instances from a JSON string.
    #[instrument(skip_all, err)]
    pub(crate) fn try_new_vec_from_json(data: &str) -> Result<Vec<Self>> {
        let mut groups: Vec<Self> = serde_json::from_str(data)?;

        for group in &mut groups {
            group.color = color(&group.name).to_string();
        }

        Ok(groups)
    }
}

impl From<explore::Group> for Group {
    fn from(eg: explore::Group) -> Self {
        Self {
            category_name: eg.category_name,
            color: eg.color,
            created_at: eg.created_at,
            name: eg.name,
            slug: eg.slug,

            city: eg.city,
            country_code: eg.country_code,
            country_name: eg.country_name,
            logo_url: eg.logo_url,
            region_name: eg.region_name,
            state: eg.state,
        }
    }
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
