//! This module defines some templates and types used in the explore page of
//! the community site.

use std::{
    borrow::Borrow,
    fmt::{self, Display, Formatter},
};

use anyhow::Result;
use askama_axum::Template;
use axum::http::HeaderMap;
use chrono::{DateTime, Utc};
use serde::{ser, Deserialize, Serialize};
use tracing::trace;

use crate::templates::helpers::extract_location;

use super::common::Community;

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

/// Filters used in the events section of the community explore page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventsFilters {
    #[serde(default)]
    pub event_category: Vec<String>,
    #[serde(default)]
    pub group_category: Vec<String>,
    #[serde(default)]
    pub kind: Vec<EventKind>,
    #[serde(default)]
    pub region: Vec<String>,

    pub date_from: Option<String>,
    pub date_to: Option<String>,
    pub distance: Option<u64>,
    pub latitude: Option<f64>,
    pub limit: Option<usize>,
    pub longitude: Option<f64>,
    pub offset: Option<usize>,
    pub sort_by: Option<String>,
    pub ts_query: Option<String>,
}

impl EventsFilters {
    /// Create a new `EventsFilters` instance from the raw query string
    /// and headers provided.
    pub(crate) fn new(headers: &HeaderMap, raw_query: &str) -> Result<Self> {
        let mut filters: EventsFilters = serde_html_form::from_str(raw_query)?;

        // Clean up entries that are empty strings
        filters.event_category.retain(|c| !c.is_empty());
        filters.group_category.retain(|c| !c.is_empty());
        filters.region.retain(|r| !r.is_empty());

        // Populate the latitude and longitude fields from the headers provided
        (filters.latitude, filters.longitude) = extract_location(headers);

        trace!("{:?}", filters);
        Ok(filters)
    }
}

impl ToRawQuery for EventsFilters {
    fn to_raw_query(&self) -> Result<String> {
        // Reset some filters we don't want to include in the query string
        let mut filters = self.clone();
        filters.latitude = None;
        filters.longitude = None;

        serde_html_form::to_string(&filters).map_err(anyhow::Error::from)
    }
}

impl Pagination for EventsFilters {
    fn limit(&self) -> Option<usize> {
        self.limit
    }

    fn offset(&self) -> Option<usize> {
        self.offset
    }

    fn set_offset(&mut self, offset: Option<usize>) {
        self.offset = offset;
    }
}

/// Events results section template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/explore/events/results.html")]
pub(crate) struct EventsResultsSection {
    pub events: Vec<Event>,
    pub navigation_links: NavigationLinks,
    pub offset: Option<usize>,
    pub total: usize,
}

/// Event kind (in-person or virtual).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum EventKind {
    Hybrid,
    InPerson,
    Virtual,
}

impl Display for EventKind {
    fn fmt(&self, f: &mut Formatter) -> fmt::Result {
        match self {
            EventKind::Hybrid => write!(f, "hybrid"),
            EventKind::InPerson => write!(f, "in-person"),
            EventKind::Virtual => write!(f, "virtual"),
        }
    }
}

/// Event information used in the community explore page.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct Event {
    pub canceled: bool,
    pub description: String,
    pub group_name: String,
    pub group_slug: String,
    pub kind_id: String,
    pub name: String,
    pub slug: String,

    pub group_city: Option<String>,
    pub group_country_code: Option<String>,
    pub group_country_name: Option<String>,
    pub group_state: Option<String>,
    pub logo_url: Option<String>,
    #[serde(with = "chrono::serde::ts_seconds_option")]
    pub starts_at: Option<DateTime<Utc>>,
    pub venue_address: Option<String>,
    pub venue_city: Option<String>,
    pub venue_name: Option<String>,
}

impl Event {
    /// Returns the location of the event.
    pub fn location(&self) -> Option<String> {
        let mut location = String::new();
        let mut location_push = |value: &Option<String>| {
            if let Some(value) = value {
                if !location.is_empty() {
                    location.push_str(", ");
                }
                location.push_str(value);
            }
        };

        location_push(&self.venue_name);
        location_push(&self.venue_address);
        if self.venue_city.is_some() {
            location_push(&self.venue_city);
        } else if self.group_city.is_some() {
            location_push(&self.group_city);
        }
        location_push(&self.group_state);
        location_push(&self.group_country_name);

        if !location.is_empty() {
            return Some(location);
        }
        None
    }

    /// Try to create a vector of `Event` instances from a JSON string.
    pub(crate) fn try_new_vec_from_json(data: &str) -> Result<Vec<Self>> {
        let events: Vec<Self> = serde_json::from_str(data)?;
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

/// Filters used in the groups section of the community explore page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupsFilters {
    #[serde(default)]
    pub group_category: Vec<String>,
    #[serde(default)]
    pub region: Vec<String>,

    pub distance: Option<f64>,
    pub latitude: Option<f64>,
    pub limit: Option<usize>,
    pub longitude: Option<f64>,
    pub offset: Option<usize>,
    pub sort_by: Option<String>,
    pub ts_query: Option<String>,
}

impl GroupsFilters {
    /// Create a new `GroupsFilters` instance from the raw query string
    /// and headers provided.
    pub(crate) fn new(headers: &HeaderMap, raw_query: &str) -> Result<Self> {
        let mut filters: GroupsFilters = serde_html_form::from_str(raw_query)?;

        // Clean up entries that are empty strings
        filters.group_category.retain(|c| !c.is_empty());
        filters.region.retain(|r| !r.is_empty());

        // Populate the latitude and longitude fields from the headers provided.
        (filters.latitude, filters.longitude) = extract_location(headers);

        trace!("{:?}", filters);
        Ok(filters)
    }
}

impl ToRawQuery for GroupsFilters {
    fn to_raw_query(&self) -> Result<String> {
        // Reset some filters we don't want to include in the query string
        let mut filters = self.clone();
        filters.latitude = None;
        filters.longitude = None;

        serde_html_form::to_string(&filters).map_err(anyhow::Error::from)
    }
}

impl Pagination for GroupsFilters {
    fn limit(&self) -> Option<usize> {
        self.limit
    }

    fn offset(&self) -> Option<usize> {
        self.offset
    }

    fn set_offset(&mut self, offset: Option<usize>) {
        self.offset = offset;
    }
}

/// Groups results section template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/explore/groups/results.html")]
pub(crate) struct GroupsResultsSection {
    pub groups: Vec<Group>,
    pub navigation_links: NavigationLinks,
    pub offset: Option<usize>,
    pub total: usize,
}

/// Group information used in the community explore page.
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
    pub description: Option<String>,
    pub logo_url: Option<String>,
    pub region_name: Option<String>,
    pub state: Option<String>,
}

impl Group {
    /// Try to create a vector of `Group` instances from a JSON string.
    pub(crate) fn try_new_vec_from_json(data: &str) -> Result<Vec<Self>> {
        let groups: Vec<Self> = serde_json::from_str(data)?;
        Ok(groups)
    }
}

/// Filters options available.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct FiltersOptions {
    pub event_category: Vec<FilterOption>,
    pub group_category: Vec<FilterOption>,
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
    /// Create a new `NavigationLinks` instance from the filters provided.
    pub(crate) fn from_filters<T>(entity: &Entity, filters: &T, total: usize) -> Result<Self>
    where
        T: ser::Serialize + Clone + ToRawQuery + Pagination,
    {
        let mut links = NavigationLinks::default();

        let offsets = NavigationLinksOffsets::new(filters.offset(), filters.limit(), total);
        let mut filters = filters.clone();

        if let Some(first_offset) = offsets.first {
            filters.set_offset(Some(first_offset));
            links.first = Some(NavigationLink::new(entity, &filters)?);
        }
        if let Some(last_offset) = offsets.last {
            filters.set_offset(Some(last_offset));
            links.last = Some(NavigationLink::new(entity, &filters)?);
        }
        if let Some(next_offset) = offsets.next {
            filters.set_offset(Some(next_offset));
            links.next = Some(NavigationLink::new(entity, &filters)?);
        }
        if let Some(prev_offset) = offsets.prev {
            filters.set_offset(Some(prev_offset));
            links.prev = Some(NavigationLink::new(entity, &filters)?);
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
        T: ser::Serialize + ToRawQuery,
    {
        let base_hx_url = format!("/explore/{entity}-results-section");
        let base_url = format!("/explore?entity={entity}");

        Ok(NavigationLink {
            hx_url: build_url(&base_hx_url, filters)?,
            url: build_url(&base_url, filters)?,
        })
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
            offsets.prev = Some(offset.saturating_sub(limit));
        }

        // There are more results going forward
        if total.saturating_sub(offset + limit) > 0 {
            // Next
            offsets.next = Some(offset + limit);

            // Last
            offsets.last = if total % limit == 0 {
                Some(total - limit)
            } else {
                Some(total - (total % limit))
            };
        }

        offsets
    }
}

/// Build URL that includes the filters as query parameters.
pub(crate) fn build_url<T>(base_url: &str, filters: &T) -> Result<String>
where
    T: ser::Serialize + ToRawQuery,
{
    let mut url = base_url.to_string();
    let sep = get_url_filters_separator(&url);
    let filters_params = filters.to_raw_query()?;
    if !filters_params.is_empty() {
        url.push_str(&format!("{sep}{filters_params}"));
    }
    Ok(url)
}

/// Get the separator to use when joining the filters to the URL.
fn get_url_filters_separator(url: &str) -> &str {
    if url.contains('?') {
        if url.ends_with('?') || url.ends_with('&') {
            ""
        } else {
            "&"
        }
    } else {
        "?"
    }
}

/// Trait to convert a type to a raw query string.
pub(crate) trait ToRawQuery {
    /// Convert the type to a raw query string.
    fn to_raw_query(&self) -> Result<String>;
}

/// Trait to get and set some pagination values.
pub(crate) trait Pagination {
    /// Get the limit value.
    fn limit(&self) -> Option<usize>;

    /// Get the offset value.
    fn offset(&self) -> Option<usize>;

    /// Set the offset value.
    fn set_offset(&mut self, offset: Option<usize>);
}

#[cfg(test)]
mod tests {
    use super::{get_url_filters_separator, Event, NavigationLinksOffsets, DEFAULT_PAGINATION_LIMIT};

    macro_rules! explore_event_location_tests {
        ($(
            $name:ident: {
                event: $event:expr,
                expected_location: $expected_location:expr
            }
        ,)*) => {
        $(
            #[test]
            fn $name() {
                assert_eq!($event.location(), $expected_location);
            }
        )*
        }
    }

    explore_event_location_tests! {
        explore_event_location_1: {
            event: Event {
                group_city: Some("group city".to_string()),
                group_country_name: Some("group country".to_string()),
                group_state: Some("group state".to_string()),
                venue_address: Some("venue address".to_string()),
                venue_city: Some("venue city".to_string()),
                venue_name: Some("venue name".to_string()),
                ..Default::default()
            },
            expected_location: Some("venue name, venue address, venue city, group state, group country".to_string())
        },

        explore_event_location_2: {
            event: Event {
                group_city: Some("group city".to_string()),
                group_country_name: Some("group country".to_string()),
                group_state: Some("group state".to_string()),
                venue_address: Some("venue address".to_string()),
                venue_city: Some("venue city".to_string()),
                ..Default::default()
            },
            expected_location: Some("venue address, venue city, group state, group country".to_string())
        },

        explore_event_location_3: {
            event: Event {
                group_city: Some("group city".to_string()),
                group_country_name: Some("group country".to_string()),
                group_state: Some("group state".to_string()),
                venue_city: Some("venue city".to_string()),
                ..Default::default()
            },
            expected_location: Some("venue city, group state, group country".to_string())
        },

        explore_event_location_4: {
            event: Event {
                group_city: Some("group city".to_string()),
                group_country_name: Some("group country".to_string()),
                group_state: Some("group state".to_string()),
                ..Default::default()
            },
            expected_location: Some("group city, group state, group country".to_string())
        },

        explore_event_location_5: {
            event: Event {
                group_country_name: Some("group country".to_string()),
                group_state: Some("group state".to_string()),
                ..Default::default()
            },
            expected_location: Some("group state, group country".to_string())
        },

        explore_event_location_6: {
            event: Event {
                group_country_name: Some("group country".to_string()),
                ..Default::default()
            },
            expected_location: Some("group country".to_string())
        },

        explore_event_location_7: {
            event: Event::default(),
            expected_location: None
        },
    }

    macro_rules! navigation_links_offsets_tests {
        ($(
            $name:ident: {
                offset: $offset:expr,
                limit: $limit:expr,
                total: $total:expr,
                expected_offsets: $expected_offsets:expr
            }
        ,)*) => {
        $(
            #[test]
            fn $name() {
                let offsets = NavigationLinksOffsets::new($offset, $limit, $total);
                assert_eq!(offsets, $expected_offsets);
            }
        )*
        }
    }

    navigation_links_offsets_tests! {
        navigation_links_offsets_1: {
            offset: Some(0),
            limit: Some(10),
            total: 20,
            expected_offsets: NavigationLinksOffsets {
                first: None,
                last: Some(10),
                next: Some(10),
                prev: None,
            }
        },

        navigation_links_offsets_2: {
            offset: Some(10),
            limit: Some(10),
            total: 20,
            expected_offsets: NavigationLinksOffsets {
                first: Some(0),
                last: None,
                next: None,
                prev: Some(0),
            }
        },

        navigation_links_offsets_3: {
            offset: Some(0),
            limit: Some(10),
            total: 21,
            expected_offsets: NavigationLinksOffsets {
                first: None,
                last: Some(20),
                next: Some(10),
                prev: None,
            }
        },

        navigation_links_offsets_4: {
            offset: Some(10),
            limit: Some(10),
            total: 15,
            expected_offsets: NavigationLinksOffsets {
                first: Some(0),
                last: None,
                next: None,
                prev: Some(0),
            }
        },

        navigation_links_offsets_5: {
            offset: Some(0),
            limit: Some(10),
            total: 10,
            expected_offsets: NavigationLinksOffsets {
                first: None,
                last: None,
                next: None,
                prev: None,
            }
        },

        navigation_links_offsets_6: {
            offset: Some(0),
            limit: Some(10),
            total: 5,
            expected_offsets: NavigationLinksOffsets {
                first: None,
                last: None,
                next: None,
                prev: None,
            }
        },

        navigation_links_offsets_7: {
            offset: Some(0),
            limit: Some(10),
            total: 0,
            expected_offsets: NavigationLinksOffsets {
                first: None,
                last: None,
                next: None,
                prev: None,
            }
        },

        navigation_links_offsets_8: {
            offset: None,
            limit: Some(10),
            total: 15,
            expected_offsets: NavigationLinksOffsets {
                first: None,
                last: Some(10),
                next: Some(10),
                prev: None,
            }
        },

        navigation_links_offsets_9: {
            offset: None,
            limit: None,
            total: 15,
            expected_offsets: NavigationLinksOffsets {
                first: None,
                last: Some(DEFAULT_PAGINATION_LIMIT),
                next: Some(DEFAULT_PAGINATION_LIMIT),
                prev: None,
            }
        },

        navigation_links_offsets_10: {
            offset: Some(20),
            limit: Some(10),
            total: 50,
            expected_offsets: NavigationLinksOffsets {
                first: Some(0),
                last: Some(40),
                next: Some(30),
                prev: Some(10),
            }
        },

        navigation_links_offsets_11: {
            offset: Some(2),
            limit: Some(10),
            total: 20,
            expected_offsets: NavigationLinksOffsets {
                first: Some(0),
                last: Some(10),
                next: Some(12),
                prev: Some(0),
            }
        },

        navigation_links_offsets_12: {
            offset: Some(0),
            limit: Some(10),
            total: 5,
            expected_offsets: NavigationLinksOffsets {
                first: None,
                last: None,
                next: None,
                prev: None,
            }
        },

        navigation_links_offsets_13: {
            offset: Some(0),
            limit: Some(10),
            total: 11,
            expected_offsets: NavigationLinksOffsets {
                first: None,
                last: Some(10),
                next: Some(10),
                prev: None,
            }
        },
    }

    macro_rules! get_url_filters_separator_tests {
        ($($name:ident: $value:expr,)*) => {
        $(
            #[test]
            fn $name() {
                let (url, expected_sep) = $value;
                assert_eq!(get_url_filters_separator(url), expected_sep);
            }
        )*
        }
    }

    get_url_filters_separator_tests! {
        get_url_filters_separator_1: ("https://example.com", "?"),
        get_url_filters_separator_2: ("https://example.com?", ""),
        get_url_filters_separator_3: ("https://example.com?param1=value1", "&"),
        get_url_filters_separator_4: ("https://example.com?param1=value1&", ""),
    }
}
