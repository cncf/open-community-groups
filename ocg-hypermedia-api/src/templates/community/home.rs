//! This module defines some templates and types used in the home page of the
//! community site.

use anyhow::Result;
use askama_axum::Template;
use chrono::{DateTime, Utc};
use chrono_tz::Tz;
use serde::{Deserialize, Serialize};

use crate::templates::{
    filters,
    helpers::{build_location, LocationParts},
};

use super::common::{Community, EventKind};

/// Home index page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/home/index.html")]
pub(crate) struct Index {
    pub community: Community,
    pub path: String,
    pub recently_added_groups: Vec<Group>,
    pub upcoming_in_person_events: Vec<Event>,
    pub upcoming_virtual_events: Vec<Event>,
}

/// Event information used in the community home page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Event {
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
    /// Returns the location of the event.
    pub fn location(&self, max_len: usize) -> Option<String> {
        let parts = LocationParts::new()
            .group_city(&self.group_city)
            .group_country_code(&self.group_country_code)
            .group_country_name(&self.group_country_name)
            .group_state(&self.group_state)
            .venue_city(&self.venue_city);

        build_location(max_len, &parts)
    }

    /// Try to create a vector of `Event` instances from a JSON string.
    pub(crate) fn try_new_vec_from_json(data: &str) -> Result<Vec<Self>> {
        let events: Vec<Self> = serde_json::from_str(data)?;

        Ok(events)
    }
}

/// Group information used in the community home page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Group {
    pub category_name: String,
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
    /// Returns the location of the event.
    pub fn location(&self, max_len: usize) -> Option<String> {
        let parts = LocationParts::new()
            .group_city(&self.city)
            .group_country_code(&self.country_code)
            .group_country_name(&self.country_name)
            .group_state(&self.state);

        build_location(max_len, &parts)
    }

    /// Try to create a vector of `Group` instances from a JSON string.
    pub(crate) fn try_new_vec_from_json(data: &str) -> Result<Vec<Self>> {
        let groups: Vec<Self> = serde_json::from_str(data)?;
        Ok(groups)
    }
}
