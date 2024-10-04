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

    pub events_section: Option<EventsSection>,
    pub groups_section: Option<GroupsSection>,
}

impl TryFrom<JsonString> for Index {
    type Error = Error;

    fn try_from(json_data: JsonString) -> Result<Self> {
        let explore: Index = serde_json::from_str(&json_data)
            .context("error deserializing explore template json data")?;

        Ok(explore)
    }
}

/// Entity to display in the explore page (events or groups).
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
pub(crate) struct EventsSection {
    pub events: Vec<Event>,
    pub filters: EventsFilters,
}

impl EventsSection {
    /// Create a new `EventsSection` instance.
    pub(crate) fn new(filters: EventsFilters, events_json: &JsonString) -> Result<Self> {
        let mut section = EventsSection {
            events: serde_json::from_str(events_json)?,
            filters,
        };

        // Convert markdown content in some fields to HTML
        for event in &mut section.events {
            event.description = markdown::to_html(&event.description);
        }

        Ok(section)
    }
}

/// Filters used in the events section of the community explore page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventsFilters {
    #[serde(default)]
    distance: Vec<String>,
    #[serde(default)]
    kind: Vec<EventKind>,
    #[serde(default)]
    region: Vec<String>,

    date_from: Option<String>,
    date_to: Option<String>,
}

impl EventsFilters {
    /// Create a new `EventsFilters` instance from the query string provided.
    pub(crate) fn try_from_query(query: &str) -> Result<Self> {
        let mut filters: EventsFilters = serde_html_form::from_str(query)?;

        // Use all event kinds if none are provided
        if filters.kind.is_empty() {
            filters.kind = vec![EventKind::InPerson, EventKind::Virtual];
        }

        Ok(filters)
    }
}

/// Event kind (in-person or virtual).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
enum EventKind {
    InPerson,
    Virtual,
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
pub(crate) struct GroupsSection {
    pub groups: Vec<Group>,
}

impl GroupsSection {
    /// Create a new `GroupsSection` instance.
    pub(crate) fn new(groups_json: &JsonString) -> Result<Self> {
        let mut section = GroupsSection {
            groups: serde_json::from_str(groups_json)?,
        };

        // Convert markdown content in some fields to HTML
        for group in &mut section.groups {
            group.description = markdown::to_html(&group.description);
        }

        Ok(section)
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
