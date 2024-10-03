//! This module defines some templates and types used in the explore page of
//! the community site.

use super::common::Community;
use crate::db::JsonString;
use anyhow::{Context, Error, Result};
use askama::Template;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Explore index page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/explore/index.html")]
pub(crate) struct Index {
    pub community: Community,
    #[serde(default)]
    pub entity: Entity,
    #[serde(default)]
    pub path: String,

    pub events: Option<Events>,
    pub groups: Option<Groups>,
}

impl TryFrom<JsonString> for Index {
    type Error = Error;

    fn try_from(json_data: JsonString) -> Result<Self> {
        let explore: Index = serde_json::from_str(&json_data)
            .context("error deserializing explore template json data")?;

        Ok(explore)
    }
}

/// Tab to display in the explore page (events or groups).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub(crate) enum Entity {
    #[default]
    Events,
    Groups,
}

impl From<Option<&String>> for Entity {
    fn from(entity: Option<&String>) -> Self {
        match entity.map(String::as_str) {
            Some("groups") => Entity::Groups,
            _ => Entity::Events,
        }
    }
}

/// Explore events section template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/explore/events.html")]
pub(crate) struct Events {
    pub events: Vec<Event>,
}

impl TryFrom<JsonString> for Events {
    type Error = Error;

    fn try_from(json_data: JsonString) -> Result<Self> {
        let mut explore_events = Events {
            events: serde_json::from_str(&json_data)
                .context("error deserializing events json data")?,
        };

        // Convert markdown content in some fields to HTML
        for event in &mut explore_events.events {
            event.description = markdown::to_html(&event.description);
        }

        Ok(explore_events)
    }
}

/// Event information used in the community explore page.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct Event {
    pub cancelled: bool,
    pub description: String,
    pub group_name: String,
    pub group_slug: String,
    pub kind_id: String,
    pub postponed: bool,
    pub slug: String,
    #[serde(with = "chrono::serde::ts_seconds")]
    pub starts_at: DateTime<Utc>,
    pub title: String,

    pub city: Option<String>,
    pub country: Option<String>,
    pub icon_url: Option<String>,
    pub state: Option<String>,
    pub venue: Option<String>,
}

impl Event {
    /// Returns the location of the event.
    pub fn location(&self) -> Option<String> {
        let mut location = String::new();

        if let Some(venue) = &self.venue {
            location.push_str(venue);
        }
        if let Some(city) = &self.city {
            if !location.is_empty() {
                location.push_str(", ");
            }
            location.push_str(city);
        }
        if let Some(state) = &self.state {
            if !location.is_empty() {
                location.push_str(", ");
            }
            location.push_str(state);
        }
        if let Some(country) = &self.country {
            if !location.is_empty() {
                location.push_str(", ");
            }
            location.push_str(country);
        }

        if !location.is_empty() {
            return Some(location);
        }
        None
    }
}

/// Explore groups section template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/explore/groups.html")]
pub(crate) struct Groups {
    pub groups: Vec<Group>,
}

impl TryFrom<JsonString> for Groups {
    type Error = Error;

    fn try_from(json_data: JsonString) -> Result<Self> {
        let mut explore_groups = Groups {
            groups: serde_json::from_str(&json_data)
                .context("error deserializing groups json data")?,
        };

        // Convert markdown content in some fields to HTML
        for group in &mut explore_groups.groups {
            group.description = markdown::to_html(&group.description);
        }

        Ok(explore_groups)
    }
}

/// Group information used in the community explore page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Group {
    pub description: String,
    pub name: String,
    pub region_name: String,
    pub slug: String,

    pub city: Option<String>,
    pub country: Option<String>,
    pub icon_url: Option<String>,
    pub state: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::Event;

    #[test]
    fn explore_event_location() {
        let event = Event {
            city: Some("City".to_string()),
            country: Some("Country".to_string()),
            state: Some("State".to_string()),
            venue: Some("Venue".to_string()),
            ..Default::default()
        };
        assert_eq!(
            event.location(),
            Some("Venue, City, State, Country".to_string())
        );

        let event = Event {
            city: Some("City".to_string()),
            country: Some("Country".to_string()),
            state: Some("State".to_string()),
            ..Default::default()
        };
        assert_eq!(event.location(), Some("City, State, Country".to_string()));

        let event = Event {
            country: Some("Country".to_string()),
            venue: Some("Venue".to_string()),
            ..Default::default()
        };
        assert_eq!(event.location(), Some("Venue, Country".to_string()));

        let event = Event {
            city: Some("City".to_string()),
            venue: Some("Venue".to_string()),
            ..Default::default()
        };
        assert_eq!(event.location(), Some("Venue, City".to_string()));

        let event = Event::default();
        assert_eq!(event.location(), None);
    }
}
