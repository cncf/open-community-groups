//! This module defines some templates and types used in the explore page of
//! the community site.

use super::common::Community;
use crate::db::TotalCount;
use anyhow::Result;
use askama::Template;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::{
    borrow::Borrow,
    fmt::{self, Display, Formatter},
};

/// Explore index page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/explore/index.html")]
pub(crate) struct Index {
    pub community: Community,
    pub entity: Entity,
    pub path: String,

    pub events_section: Option<EventsSection>,
    pub groups_section: Option<GroupsSection>,
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
#[template(path = "community/explore/events/section.html")]
pub(crate) struct EventsSection {
    pub filters: EventsFilters,
    pub filters_options: FiltersOptions,
    pub events: Vec<Event>,
    pub total_count: TotalCount,
}

/// Filters used in the events section of the community explore page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventsFilters {
    #[serde(default)]
    pub distance: Vec<String>,
    #[serde(default)]
    pub kind: Vec<EventKind>,
    #[serde(default)]
    pub region: Vec<String>,

    pub date_from: Option<String>,
    pub date_to: Option<String>,
    pub limit: Option<usize>,
    pub offset: Option<usize>,
    pub ts_query: Option<String>,
}

impl EventsFilters {
    /// Create a new `EventsFilters` instance from the raw query string
    /// provided.
    pub(crate) fn try_from_raw_query(raw_query: &str) -> Result<Self> {
        let mut filters: EventsFilters = serde_html_form::from_str(raw_query)?;

        // Clean up entries that are empty strings
        filters.distance.retain(|v| !v.is_empty());
        filters.region.retain(|v| !v.is_empty());

        Ok(filters)
    }
}

/// Event kind (in-person or virtual).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum EventKind {
    InPerson,
    Virtual,
}

impl Display for EventKind {
    fn fmt(&self, f: &mut Formatter) -> fmt::Result {
        match self {
            EventKind::InPerson => write!(f, "in-person"),
            EventKind::Virtual => write!(f, "virtual"),
        }
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

    /// Try to create a vector of `Event` instances from a JSON string.
    pub(crate) fn try_new_vec_from_json(data: &str) -> Result<Vec<Self>> {
        let mut events: Vec<Self> = serde_json::from_str(data)?;

        // Convert markdown content in some fields to HTML
        for event in &mut events {
            event.description = markdown::to_html(&event.description);
        }

        Ok(events)
    }
}

/// Explore groups section template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/explore/groups/section.html")]
pub(crate) struct GroupsSection {
    pub filters: GroupsFilters,
    pub filters_options: FiltersOptions,
    pub groups: Vec<Group>,
    pub total_count: TotalCount,
}

/// Filters used in the groups section of the community explore page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupsFilters {
    #[serde(default)]
    pub distance: Vec<String>,
    #[serde(default)]
    pub region: Vec<String>,

    pub limit: Option<usize>,
    pub offset: Option<usize>,
    pub ts_query: Option<String>,
}

impl GroupsFilters {
    /// Create a new `GroupsFilters` instance from the raw query string
    /// provided.
    pub(crate) fn try_from_raw_query(raw_query: &str) -> Result<Self> {
        let mut filters: GroupsFilters = serde_html_form::from_str(raw_query)?;

        // Clean up entries that are empty strings
        filters.distance.retain(|v| !v.is_empty());
        filters.region.retain(|v| !v.is_empty());

        Ok(filters)
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

impl Group {
    /// Try to create a vector of `Group` instances from a JSON string.
    pub(crate) fn try_new_vec_from_json(data: &str) -> Result<Vec<Self>> {
        let mut groups: Vec<Self> = serde_json::from_str(data)?;

        // Convert markdown content in some fields to HTML
        for group in &mut groups {
            group.description = markdown::to_html(&group.description);
        }

        Ok(groups)
    }
}

/// Filters options available.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct FiltersOptions {
    pub distance: Vec<FilterOption>,
    pub region: Vec<FilterOption>,
}

impl FiltersOptions {
    /// Try to create a `FiltersOptions` instance from a JSON string.
    pub(crate) fn try_from_json(data: &str) -> Result<Self> {
        let filters_options: FiltersOptions = serde_json::from_str(data)?;

        Ok(filters_options)
    }
}

/// Filter option details.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct FilterOption {
    pub name: String,
    pub value: String,
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
        assert_eq!(event.location(), Some("Venue, City, State, Country".to_string()));

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
