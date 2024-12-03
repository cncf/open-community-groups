//! This module defines some templates and types used in the explore page of
//! the community site.

use std::{
    borrow::Borrow,
    fmt::{self, Display, Formatter},
};

use anyhow::Result;
use askama_axum::Template;
use axum::http::HeaderMap;
use chrono::{DateTime, Months, Utc};
use chrono_tz::Tz;
use serde::{ser, Deserialize, Serialize};
use tracing::trace;

use crate::templates::{
    filters,
    helpers::{build_location, extract_location, LocationParts},
};

use super::common::{Community, EventKind};

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

    #[serde(skip_serializing_if = "Option::is_none")]
    pub bbox_ne_lat: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bbox_ne_lon: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bbox_sw_lat: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bbox_sw_lon: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub date_from: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub date_to: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub distance: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub include_bbox: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub latitude: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub longitude: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub offset: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sort_by: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ts_query: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub view_mode: Option<ViewMode>,
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

        // Add default date range if not provided (now -> 12 months from now)
        if filters.date_from.is_none() {
            filters.date_from = Some(Utc::now().date_naive().to_string());
        }
        if filters.date_to.is_none() {
            if let Some(date_to) = Utc::now().date_naive().checked_add_months(Months::new(12)) {
                filters.date_to = Some(date_to.to_string());
            }
        }

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
        if filters.date_from == Some(Utc::now().date_naive().to_string()) {
            filters.date_from = None;
        }
        if let Some(date_to) = Utc::now().date_naive().checked_add_months(Months::new(12)) {
            if filters.date_to == Some(date_to.to_string()) {
                filters.date_to = None;
            }
        }
        filters.latitude = None;
        filters.longitude = None;
        if filters.sort_by == Some("date".to_string()) {
            filters.sort_by = None;
        }

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
    pub total: usize,

    pub offset: Option<usize>,
    pub view_mode: Option<ViewMode>,
}

impl EventsResultsSection {
    /// Return the entity to which the results belong.
    #[allow(clippy::unused_self)]
    pub(crate) fn entity(&self) -> Entity {
        Entity::Events
    }
}

/// Event information used in the community explore page.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct Event {
    pub canceled: bool,
    pub group_category_name: String,
    pub group_name: String,
    pub group_slug: String,
    pub kind: EventKind,
    pub name: String,
    pub slug: String,
    pub timezone: Tz,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub description_short: Option<String>,
    #[serde(
        with = "chrono::serde::ts_seconds_option",
        skip_serializing_if = "Option::is_none"
    )]
    pub ends_at: Option<DateTime<Utc>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub group_city: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub group_country_code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub group_country_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub group_state: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub latitude: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub logo_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub longitude: Option<f64>,
    #[serde(
        with = "chrono::serde::ts_seconds_option",
        skip_serializing_if = "Option::is_none"
    )]
    pub starts_at: Option<DateTime<Utc>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub venue_address: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub venue_city: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub venue_name: Option<String>,
}

impl Event {
    /// Returns the location of the event.
    pub(crate) fn location(&self, max_len: usize) -> Option<String> {
        let parts = LocationParts::new()
            .group_city(self.group_city.as_ref())
            .group_country_code(self.group_country_code.as_ref())
            .group_country_name(self.group_country_name.as_ref())
            .group_state(self.group_state.as_ref())
            .venue_address(self.venue_address.as_ref())
            .venue_city(self.venue_city.as_ref())
            .venue_name(self.venue_name.as_ref());

        build_location(max_len, &parts)
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

    #[serde(skip_serializing_if = "Option::is_none")]
    pub bbox_ne_lat: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bbox_ne_lon: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bbox_sw_lat: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bbox_sw_lon: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub distance: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub include_bbox: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub latitude: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub longitude: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub offset: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sort_by: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ts_query: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub view_mode: Option<ViewMode>,
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
        if filters.sort_by == Some("date".to_string()) {
            filters.sort_by = None;
        }

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
    pub total: usize,

    pub offset: Option<usize>,
    pub view_mode: Option<ViewMode>,
}

impl GroupsResultsSection {
    /// Return the entity to which the results belong.
    #[allow(clippy::unused_self)]
    pub(crate) fn entity(&self) -> Entity {
        Entity::Groups
    }
}

/// Group information used in the community explore page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Group {
    pub category_name: String,
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    pub name: String,
    pub slug: String,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub city: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub country_code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub country_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub latitude: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub logo_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub longitude: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub region_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub state: Option<String>,
}

impl Group {
    /// Returns the location of the group.
    pub(crate) fn location(&self, max_len: usize) -> Option<String> {
        let parts = LocationParts::new()
            .group_city(self.city.as_ref())
            .group_country_code(self.country_code.as_ref())
            .group_country_name(self.country_name.as_ref())
            .group_state(self.state.as_ref());

        build_location(max_len, &parts)
    }

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

/// View mode.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum ViewMode {
    Calendar,
    #[default]
    List,
    Map,
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
    use super::{get_url_filters_separator, NavigationLinksOffsets, DEFAULT_PAGINATION_LIMIT};

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
