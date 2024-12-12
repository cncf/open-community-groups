//! This module defines some templates and types used in the home page of the
//! community site.

use anyhow::Result;
use askama_axum::Template;
use chrono::{DateTime, Utc};
use chrono_tz::Tz;
use serde::{Deserialize, Serialize};
use tracing::instrument;

use crate::templates::{
    filters,
    helpers::{build_location, color, LocationParts},
};

use super::{
    common::{Community, EventKind},
    explore,
};

/// Home index page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/home/index.html")]
pub(crate) struct Index {
    pub community: Community,
    pub path: String,
    pub recently_added_groups: Vec<Group>,
    pub upcoming_in_person_events: Vec<Event>,
    pub upcoming_virtual_events: Vec<Event>,
    pub stats: Stats,
}

/// Event information used in the community home page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/home/event.html")]
pub(crate) struct Event {
    #[serde(default)]
    pub group_color: String,
    pub group_name: String,
    pub group_slug: String,
    pub kind: EventKind,
    pub name: String,
    pub slug: String,
    pub timezone: Tz,

    pub group_city: Option<String>,
    pub group_country_code: Option<String>,
    pub group_country_name: Option<String>,
    pub group_state: Option<String>,
    pub logo_url: Option<String>,
    #[serde(with = "chrono::serde::ts_seconds_option")]
    pub starts_at: Option<DateTime<Utc>>,
    pub venue_city: Option<String>,
}

impl Event {
    /// Get the location of the event.
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

/// Group information used in the community home page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/home/group.html")]
pub(crate) struct Group {
    pub category_name: String,
    #[serde(default)]
    pub color: String,
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    pub name: String,
    pub slug: String,

    pub city: Option<String>,
    pub country_code: Option<String>,
    pub country_name: Option<String>,
    pub logo_url: Option<String>,
    pub region_name: Option<String>,
    pub state: Option<String>,
}

impl Group {
    /// Get the location of the group.
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

/// Some stats used in the community home page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/home/stats.html")]
pub(crate) struct Stats {
    groups: i64,
    groups_members: i64,
    events: i64,
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
