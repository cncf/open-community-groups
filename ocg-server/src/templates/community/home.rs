//! Templates and data structures for the home page of the community site.
//!
//! The home page displays an overview of the community including community statistics,
//! upcoming events (both in-person and virtual), and recently added groups.

use anyhow::Result;
use askama::Template;
use chrono::{DateTime, Utc};
use chrono_tz::Tz;
use serde::{Deserialize, Serialize};
use tracing::instrument;

use crate::templates::{
    filters,
    helpers::{LocationParts, build_location, color},
};

use super::{common::Community, explore};
use crate::templates::common::EventKind;

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
    pub upcoming_in_person_events: Vec<Event>,
    /// List of upcoming virtual events across all community groups.
    pub upcoming_virtual_events: Vec<Event>,
    /// Aggregated statistics about groups, members, events, and attendees.
    pub stats: Stats,
}

/// Event data structure for home page display.
///
/// Contains essential event information optimized for the compact home page layout.
/// Includes group context and location details for proper display.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/home/event.html")]
pub(crate) struct Event {
    /// Color associated with the group hosting this event, used for visual styling.
    #[serde(default)]
    pub group_color: String,
    /// Name of the group hosting this event.
    pub group_name: String,
    /// URL-friendly identifier for the group hosting this event.
    pub group_slug: String,
    /// Type of event (in-person or virtual).
    pub kind: EventKind,
    /// Display name of the event.
    pub name: String,
    /// URL-friendly identifier for this event.
    pub slug: String,
    /// Timezone in which the event times should be displayed.
    pub timezone: Tz,

    /// City where the group is located (may differ from venue city).
    pub group_city: Option<String>,
    /// ISO country code of the group's location.
    pub group_country_code: Option<String>,
    /// Full country name of the group's location.
    pub group_country_name: Option<String>,
    /// State or province where the group is located.
    pub group_state: Option<String>,
    /// URL to the event or group's logo image.
    pub logo_url: Option<String>,
    /// UTC timestamp when the event starts.
    #[serde(with = "chrono::serde::ts_seconds_option")]
    pub starts_at: Option<DateTime<Utc>>,
    /// City where the event venue is located (for in-person events).
    pub venue_city: Option<String>,
}

impl Event {
    /// Builds a formatted location string for the event.
    pub(crate) fn location(&self, max_len: usize) -> Option<String> {
        let parts = LocationParts::new()
            .group_city(self.group_city.as_ref())
            .group_country_code(self.group_country_code.as_ref())
            .group_country_name(self.group_country_name.as_ref())
            .group_state(self.group_state.as_ref())
            .venue_city(self.venue_city.as_ref());

        build_location(&parts, max_len)
    }

    /// Try to create a vector of `Event` instances from a JSON string.
    #[instrument(skip_all, err)]
    pub(crate) fn try_new_vec_from_json(data: &str) -> Result<Vec<Self>> {
        let mut events: Vec<Self> = serde_json::from_str(data)?;

        for event in &mut events {
            event.group_color = color(&event.group_name).to_string();
        }

        Ok(events)
    }
}

impl From<explore::Event> for Event {
    fn from(ee: explore::Event) -> Self {
        Self {
            group_color: ee.group_color,
            group_name: ee.group_name,
            group_slug: ee.group_slug,
            kind: ee.kind,
            name: ee.name,
            slug: ee.slug,
            timezone: ee.timezone,

            group_city: ee.group_city,
            group_country_code: ee.group_country_code,
            group_country_name: ee.group_country_name,
            group_state: ee.group_state,
            logo_url: ee.logo_url,
            starts_at: ee.starts_at,
            venue_city: ee.venue_city,
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
