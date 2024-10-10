//! This module defines some templates and types used in the home page of the
//! community site.

use super::common::Community;
use anyhow::Result;
use askama::Template;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

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
    pub slug: String,
    #[serde(with = "chrono::serde::ts_seconds")]
    pub starts_at: DateTime<Utc>,
    pub title: String,

    pub city: Option<String>,
    pub icon_url: Option<String>,
    pub state: Option<String>,
}

impl Event {
    /// Try to create a vector of `Event` instances from a JSON string.
    pub(crate) fn try_new_vec_from_json(data: &str) -> Result<Vec<Self>> {
        let events: Vec<Self> = serde_json::from_str(data)?;

        Ok(events)
    }
}

/// Group information used in the community home page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Group {
    pub name: String,
    pub region_name: String,
    pub slug: String,

    pub city: Option<String>,
    pub country: Option<String>,
    pub icon_url: Option<String>,
    pub state: Option<String>,
}

impl Group {
    /// Try to create a vector of `Group` instances from a JSON string.
    pub(crate) fn try_new_vec_from_json(data: &str) -> Result<Vec<Self>> {
        let groups: Vec<Self> = serde_json::from_str(data)?;

        Ok(groups)
    }
}
