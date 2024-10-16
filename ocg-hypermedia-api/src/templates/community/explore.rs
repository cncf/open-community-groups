//! This module defines some templates and types used in the explore page of
//! the community site.

use super::common::Community;
use anyhow::Result;
use askama::Template;
use chrono::{DateTime, Utc};
use serde::{ser, Deserialize, Serialize};
use std::{
    borrow::Borrow,
    fmt::{self, Display, Formatter},
};

/// Default pagination limit.
const DEFAULT_PAGINATION_LIMIT: usize = 10;

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

impl Display for Entity {
    fn fmt(&self, f: &mut Formatter) -> fmt::Result {
        match self {
            Entity::Events => write!(f, "events"),
            Entity::Groups => write!(f, "groups"),
        }
    }
}

/// Explore events section template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/explore/events/section.html")]
pub(crate) struct EventsSection {
    pub filters: EventsFilters,
    pub filters_options: FiltersOptions,
    pub results_section: EventsResultsSection,
}

/// Events results section template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/explore/events/results.html")]
pub(crate) struct EventsResultsSection {
    pub events: Vec<Event>,
    pub navigation_links: NavigationLinks,
    pub offset: Option<usize>,
    pub total: i64,
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
    pub results_section: GroupsResultsSection,
}

/// Groups results section template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/explore/groups/results.html")]
pub(crate) struct GroupsResultsSection {
    pub groups: Vec<Group>,
    pub navigation_links: NavigationLinks,
    pub offset: Option<usize>,
    pub total: i64,
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

/// Results navigation links.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct NavigationLinks {
    pub first: Option<NavigationLink>,
    pub last: Option<NavigationLink>,
    pub next: Option<NavigationLink>,
    pub prev: Option<NavigationLink>,
}

impl NavigationLinks {
    /// Create a new `NavigationLinks` instance from the events filters provided.
    pub(crate) fn from_events_filters(filters: &EventsFilters, total: usize) -> Result<Self> {
        let mut links = NavigationLinks::default();

        let offsets = NavigationLinksOffsets::new(filters.offset, filters.limit, total);
        let entity = Entity::Events;
        let mut filters = filters.clone();

        if let Some(first_offset) = offsets.first {
            filters.offset = Some(first_offset);
            links.first = Some(NavigationLink::new(&entity, &filters)?);
        }
        if let Some(last_offset) = offsets.last {
            filters.offset = Some(last_offset);
            links.last = Some(NavigationLink::new(&entity, &filters)?);
        }
        if let Some(next_offset) = offsets.next {
            filters.offset = Some(next_offset);
            links.next = Some(NavigationLink::new(&entity, &filters)?);
        }
        if let Some(prev_offset) = offsets.prev {
            filters.offset = Some(prev_offset);
            links.prev = Some(NavigationLink::new(&entity, &filters)?);
        }

        Ok(links)
    }

    /// Create a new `NavigationLinks` instance from the groups filters provided.
    pub(crate) fn from_groups_filters(filters: &GroupsFilters, total: usize) -> Result<Self> {
        let mut links = NavigationLinks::default();

        let offsets = NavigationLinksOffsets::new(filters.offset, filters.limit, total);
        let entity = Entity::Groups;
        let mut filters = filters.clone();

        if let Some(first_offset) = offsets.first {
            filters.offset = Some(first_offset);
            links.first = Some(NavigationLink::new(&entity, &filters)?);
        }
        if let Some(last_offset) = offsets.last {
            filters.offset = Some(last_offset);
            links.last = Some(NavigationLink::new(&entity, &filters)?);
        }
        if let Some(next_offset) = offsets.next {
            filters.offset = Some(next_offset);
            links.next = Some(NavigationLink::new(&entity, &filters)?);
        }
        if let Some(prev_offset) = offsets.prev {
            filters.offset = Some(prev_offset);
            links.prev = Some(NavigationLink::new(&entity, &filters)?);
        }

        Ok(links)
    }
}

/// Navigation link.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct NavigationLink {
    pub hx_url: String,
    pub url: String,
}

impl NavigationLink {
    /// Create a new `NavigationLink` instance from the filters provided.
    pub(crate) fn new<T>(entity: &Entity, filters: &T) -> Result<Self>
    where
        T: ser::Serialize + Clone,
    {
        let link = NavigationLink {
            hx_url: build_url(
                &format!("/explore/{entity}-results-section?entity={entity}"),
                &filters,
            )?,
            url: build_url(&format!("/explore?entity={entity}"), &filters)?,
        };
        Ok(link)
    }
}

/// Offsets used to build the navigation links.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
struct NavigationLinksOffsets {
    first: Option<usize>,
    last: Option<usize>,
    next: Option<usize>,
    prev: Option<usize>,
}

impl NavigationLinksOffsets {
    /// Create a new `NavigationLinksOffsets` instance.
    fn new(offset: Option<usize>, limit: Option<usize>, total: usize) -> Self {
        let mut offsets = NavigationLinksOffsets::default();

        // Use default offset and limit values if not provided
        let offset = offset.unwrap_or(0);
        let limit = limit.unwrap_or(DEFAULT_PAGINATION_LIMIT);

        // There are more results going backwards
        if offset > 0 {
            // First
            offsets.first = Some(0);

            // Previous
            offsets.prev = Some(offset - limit);
        }

        // There are more results going forward
        if total as i64 - (offset + limit) as i64 > 0 {
            // Next
            offsets.next = Some(offset + limit);

            // Last
            offsets.last = Some(total - limit + (total % limit));
        }

        offsets
    }
}

/// Build URL that includes the filters as query parameters.
pub(crate) fn build_url<T>(base_url: &str, filters: &T) -> Result<String>
where
    T: ser::Serialize,
{
    let mut url = base_url.to_string();
    let filters_params = serde_html_form::to_string(filters)?;
    if !filters_params.is_empty() {
        url.push_str(&format!("&{filters_params}"));
    }
    Ok(url)
}

#[cfg(test)]
mod tests {
    use crate::templates::community::explore::DEFAULT_PAGINATION_LIMIT;

    use super::{Event, NavigationLinksOffsets};

    #[test]
    fn explore_event_location_case1() {
        let event = Event {
            city: Some("City".to_string()),
            country: Some("Country".to_string()),
            state: Some("State".to_string()),
            venue: Some("Venue".to_string()),
            ..Default::default()
        };
        assert_eq!(event.location(), Some("Venue, City, State, Country".to_string()));
    }

    #[test]
    fn explore_event_location_case2() {
        let event = Event {
            city: Some("City".to_string()),
            country: Some("Country".to_string()),
            state: Some("State".to_string()),
            ..Default::default()
        };
        assert_eq!(event.location(), Some("City, State, Country".to_string()));
    }

    #[test]
    fn explore_event_location_case3() {
        let event = Event {
            country: Some("Country".to_string()),
            venue: Some("Venue".to_string()),
            ..Default::default()
        };
        assert_eq!(event.location(), Some("Venue, Country".to_string()));
    }

    #[test]
    fn explore_event_location_case4() {
        let event = Event {
            city: Some("City".to_string()),
            venue: Some("Venue".to_string()),
            ..Default::default()
        };
        assert_eq!(event.location(), Some("Venue, City".to_string()));
    }

    #[test]
    fn explore_event_location_case5() {
        let event = Event::default();
        assert_eq!(event.location(), None);
    }

    #[test]
    fn navigation_links_offsets_case1() {
        let offsets = NavigationLinksOffsets::new(Some(0), Some(10), 20);
        assert_eq!(
            offsets,
            NavigationLinksOffsets {
                first: None,
                last: Some(10),
                next: Some(10),
                prev: None,
            }
        );
    }

    #[test]
    fn navigation_links_offsets_case2() {
        let offsets = NavigationLinksOffsets::new(Some(10), Some(10), 20);
        assert_eq!(
            offsets,
            NavigationLinksOffsets {
                first: Some(0),
                last: None,
                next: None,
                prev: Some(0),
            }
        );
    }

    #[test]
    fn navigation_links_offsets_case3() {
        let offsets = NavigationLinksOffsets::new(Some(0), Some(10), 20);
        assert_eq!(
            offsets,
            NavigationLinksOffsets {
                first: None,
                last: Some(10),
                next: Some(10),
                prev: None,
            }
        );
    }

    #[test]
    fn navigation_links_offsets_case4() {
        let offsets = NavigationLinksOffsets::new(Some(10), Some(10), 15);
        assert_eq!(
            offsets,
            NavigationLinksOffsets {
                first: Some(0),
                last: None,
                next: None,
                prev: Some(0),
            }
        );
    }

    #[test]
    fn navigation_links_offsets_case5() {
        let offsets = NavigationLinksOffsets::new(Some(0), Some(10), 10);
        assert_eq!(
            offsets,
            NavigationLinksOffsets {
                first: None,
                last: None,
                next: None,
                prev: None,
            }
        );
    }

    #[test]
    fn navigation_links_offsets_case6() {
        let offsets = NavigationLinksOffsets::new(Some(0), Some(10), 5);
        assert_eq!(
            offsets,
            NavigationLinksOffsets {
                first: None,
                last: None,
                next: None,
                prev: None,
            }
        );
    }

    #[test]
    fn navigation_links_offsets_case7() {
        let offsets = NavigationLinksOffsets::new(Some(0), Some(10), 0);
        assert_eq!(
            offsets,
            NavigationLinksOffsets {
                first: None,
                last: None,
                next: None,
                prev: None,
            }
        );
    }

    #[test]
    fn navigation_links_offsets_case8() {
        let offsets = NavigationLinksOffsets::new(None, Some(10), 15);
        assert_eq!(
            offsets,
            NavigationLinksOffsets {
                first: None,
                last: Some(10),
                next: Some(10),
                prev: None,
            }
        );
    }

    #[test]
    fn navigation_links_offsets_case9() {
        let offsets = NavigationLinksOffsets::new(None, None, 15);
        assert_eq!(
            offsets,
            NavigationLinksOffsets {
                first: None,
                last: Some(DEFAULT_PAGINATION_LIMIT),
                next: Some(DEFAULT_PAGINATION_LIMIT),
                prev: None,
            }
        );
    }

    #[test]
    fn navigation_links_offsets_case10() {
        let offsets = NavigationLinksOffsets::new(Some(20), Some(10), 50);
        assert_eq!(
            offsets,
            NavigationLinksOffsets {
                first: Some(0),
                last: Some(40),
                next: Some(30),
                prev: Some(10),
            }
        );
    }
}
