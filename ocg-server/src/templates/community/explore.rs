//! Templates and types for the community site explore page.

use std::fmt::{self, Display, Formatter, Write as _};

use anyhow::Result;
use askama::Template;
use axum::http::HeaderMap;
use chrono::{DateTime, Datelike, Months, NaiveDate, Utc};
use chrono_tz::Tz;
use minify_html::{Cfg as MinifyCfg, minify};
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use tracing::{instrument, trace};

use crate::{
    db::BBox,
    templates::{
        filters,
        helpers::{LocationParts, build_location, color, extract_location},
    },
};

use super::{common::Community, home};
use crate::templates::common::EventKind;

/// Default pagination limit.
const DEFAULT_PAGINATION_LIMIT: usize = 10;

// Pages templates.

/// Template for the explore page.
///
/// This is the root template that renders the explore page with either events or groups
/// content based on the selected entity.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/explore/page.html")]
pub(crate) struct Page {
    /// Community information.
    pub community: Community,
    /// The type of content being explored (events or groups).
    pub entity: Entity,
    /// Current URL path.
    pub path: String,

    /// Events section data, populated when exploring events.
    pub events_section: Option<EventsSection>,
    /// Groups section data, populated when exploring groups.
    pub groups_section: Option<GroupsSection>,
}

/// Template for the events section of the explore page.
///
/// This template renders the events exploration interface, including filters panel and
/// results. It's used when `Entity::Events` is selected.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/explore/events/section.html")]
pub(crate) struct EventsSection {
    /// Active filters for events search.
    pub filters: EventsFilters,
    /// Available filter options (categories, regions, etc.).
    pub filters_options: FiltersOptions,
    /// Results section containing matching events.
    pub results_section: EventsResultsSection,
}

/// Template for displaying event search results.
///
/// This template renders the list of matching events along with pagination controls. It
/// supports different view modes and includes geographic bounds for map display.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/explore/events/results.html")]
pub(crate) struct EventsResultsSection {
    /// List of events matching the current filters.
    pub events: Vec<Event>,
    /// Pagination links for navigating results.
    pub navigation_links: NavigationLinks,
    /// Total number of matching events (for pagination).
    pub total: usize,

    /// Geographic bounds of all events (for map centering).
    pub bbox: Option<BBox>,
    /// Current pagination offset.
    pub offset: Option<usize>,
    /// Current display mode.
    pub view_mode: Option<ViewMode>,
}

impl EventsResultsSection {
    /// Return the entity to which the results belong.
    #[allow(clippy::unused_self)]
    pub(crate) fn entity(&self) -> Entity {
        Entity::Events
    }
}

/// Detailed event information for display in explore results.
///
/// This struct contains all the data needed to render an event in the explore page,
/// including location details, timing, and group information. It can also render itself
/// as a popover for map/calendar views.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Template, Serialize, Deserialize)]
#[template(path = "community/explore/events/event.html")]
pub(crate) struct Event {
    /// Whether the event has been canceled.
    pub canceled: bool,
    /// Category of the hosting group.
    pub group_category_name: String,
    /// Generated color for visual distinction.
    #[serde(default)]
    pub group_color: String,
    /// Name of the group hosting the event.
    pub group_name: String,
    /// URL slug of the hosting group.
    pub group_slug: String,
    /// Type of event (in-person, online, hybrid).
    pub kind: EventKind,
    /// Event title.
    pub name: String,
    /// URL slug of the event.
    pub slug: String,
    /// Timezone for event times.
    pub timezone: Tz,

    /// Brief event description for listings.
    pub description_short: Option<String>,
    /// Event end time in UTC.
    #[serde(with = "chrono::serde::ts_seconds_option")]
    pub ends_at: Option<DateTime<Utc>>,
    /// City where the group is based.
    pub group_city: Option<String>,
    /// ISO country code of the group.
    pub group_country_code: Option<String>,
    /// Full country name of the group.
    pub group_country_name: Option<String>,
    /// State/province where the group is based.
    pub group_state: Option<String>,
    /// Latitude for map display.
    pub latitude: Option<f64>,
    /// URL to the event or group logo.
    pub logo_url: Option<String>,
    /// Longitude for map display.
    pub longitude: Option<f64>,
    /// Pre-rendered HTML for map/calendar popovers.
    pub popover_html: Option<String>,
    /// Event start time in UTC.
    #[serde(with = "chrono::serde::ts_seconds_option")]
    pub starts_at: Option<DateTime<Utc>>,
    /// Street address of the venue.
    pub venue_address: Option<String>,
    /// City where the event takes place.
    pub venue_city: Option<String>,
    /// Name of the venue.
    pub venue_name: Option<String>,
}

impl Event {
    /// Build a display-friendly location string from available location data.
    pub(crate) fn location(&self, max_len: usize) -> Option<String> {
        let parts = LocationParts::new()
            .group_city(self.group_city.as_ref())
            .group_country_code(self.group_country_code.as_ref())
            .group_country_name(self.group_country_name.as_ref())
            .group_state(self.group_state.as_ref())
            .venue_address(self.venue_address.as_ref())
            .venue_city(self.venue_city.as_ref())
            .venue_name(self.venue_name.as_ref());

        build_location(&parts, max_len)
    }

    /// Render popover HTML for map and calendar views.
    ///
    /// Converts this event into a home::Event template and renders it as minified HTML
    /// for inclusion in map/calendar popovers.
    #[instrument(skip_all, err)]
    pub(crate) fn render_popover_html(&mut self) -> Result<()> {
        let home_event: home::Event = self.clone().into();
        let cfg = MinifyCfg::new();
        self.popover_html = Some(String::from_utf8(minify(home_event.render()?.as_bytes(), &cfg))?);

        Ok(())
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

/// Template for the groups section of the explore page.
///
/// This template renders the groups exploration interface, including filters panel and
/// results. It's used when `Entity::Groups` is selected.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/explore/groups/section.html")]
pub(crate) struct GroupsSection {
    /// Active filters for groups search.
    pub filters: GroupsFilters,
    /// Available filter options (categories, regions, etc.).
    pub filters_options: FiltersOptions,
    /// Results section containing matching groups.
    pub results_section: GroupsResultsSection,
}

/// Template for displaying group search results.
///
/// This template renders the list of matching groups along with pagination controls. It
/// supports different view modes and includes geographic bounds for map display.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/explore/groups/results.html")]
pub(crate) struct GroupsResultsSection {
    /// List of groups matching the current filters.
    pub groups: Vec<Group>,
    /// Pagination links for navigating results.
    pub navigation_links: NavigationLinks,
    /// Total number of matching groups (for pagination).
    pub total: usize,

    /// Geographic bounds of all groups (for map centering).
    pub bbox: Option<BBox>,
    /// Current pagination offset.
    pub offset: Option<usize>,
    /// Current display mode.
    pub view_mode: Option<ViewMode>,
}

impl GroupsResultsSection {
    /// Return the entity to which the results belong.
    #[allow(clippy::unused_self)]
    pub(crate) fn entity(&self) -> Entity {
        Entity::Groups
    }
}

/// Detailed group information for display in explore results.
///
/// This struct contains all the data needed to render a group in the explore page,
/// including location details and metadata. It can also render itself as a popover for
/// map views.
#[skip_serializing_none]
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/explore/groups/group.html")]
pub(crate) struct Group {
    /// Category this group belongs to.
    pub category_name: String,
    /// Generated color for visual distinction.
    #[serde(default)]
    pub color: String,
    /// When the group was created.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Group name.
    pub name: String,
    /// URL slug of the group.
    pub slug: String,

    /// City where the group is based.
    pub city: Option<String>,
    /// ISO country code of the group.
    pub country_code: Option<String>,
    /// Full country name of the group.
    pub country_name: Option<String>,
    /// Group description text.
    pub description: Option<String>,
    /// Latitude for map display.
    pub latitude: Option<f64>,
    /// URL to the group logo.
    pub logo_url: Option<String>,
    /// Longitude for map display.
    pub longitude: Option<f64>,
    /// Pre-rendered HTML for map popovers.
    pub popover_html: Option<String>,
    /// Name of the geographic region.
    pub region_name: Option<String>,
    /// State/province where the group is based.
    pub state: Option<String>,
}

impl Group {
    /// Build a display-friendly location string from available location data.
    pub(crate) fn location(&self, max_len: usize) -> Option<String> {
        let parts = LocationParts::new()
            .group_city(self.city.as_ref())
            .group_country_code(self.country_code.as_ref())
            .group_country_name(self.country_name.as_ref())
            .group_state(self.state.as_ref());

        build_location(&parts, max_len)
    }

    /// Render popover HTML for map views.
    ///
    /// Converts this group into a home::Group template and renders it as minified HTML
    /// for inclusion in map popovers.
    #[instrument(skip_all, err)]
    pub(crate) fn render_popover_html(&mut self) -> Result<()> {
        let home_group: home::Group = self.clone().into();
        let cfg = MinifyCfg::new();
        self.popover_html = Some(String::from_utf8(minify(home_group.render()?.as_bytes(), &cfg))?);
        Ok(())
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

// Types.

/// Represents the type of content being explored.
///
/// The explore page can display either events or groups. This enum determines which
/// section is shown.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub(crate) enum Entity {
    /// Explore events (default).
    #[default]
    Events,
    /// Explore groups.
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

/// Filter parameters for event searches.
///
/// This struct captures all possible filtering criteria for events including
/// location-based filters (bounding box, distance), temporal filters (date range),
/// categorical filters, etc.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventsFilters {
    /// Selected event categories to filter by.
    #[serde(default)]
    pub event_category: Vec<String>,
    /// Selected group categories to filter by.
    #[serde(default)]
    pub group_category: Vec<String>,
    /// Event types to include (in-person, online, hybrid).
    #[serde(default)]
    pub kind: Vec<EventKind>,
    /// Geographic regions to filter by.
    #[serde(default)]
    pub region: Vec<String>,

    /// Northeast latitude of bounding box for map view.
    pub bbox_ne_lat: Option<f64>,
    /// Northeast longitude of bounding box for map view.
    pub bbox_ne_lon: Option<f64>,
    /// Southwest latitude of bounding box for map view.
    pub bbox_sw_lat: Option<f64>,
    /// Southwest longitude of bounding box for map view.
    pub bbox_sw_lon: Option<f64>,
    /// Start date for event filtering (YYYY-MM-DD format).
    pub date_from: Option<String>,
    /// End date for event filtering (YYYY-MM-DD format).
    pub date_to: Option<String>,
    /// Maximum distance in meters from user's location.
    pub distance: Option<u64>,
    /// Whether to include bounding box in results (for map view).
    pub include_bbox: Option<bool>,
    /// Whether to pre-render popover HTML.
    pub include_popover_html: Option<bool>,
    /// User's latitude for distance-based filtering.
    pub latitude: Option<f64>,
    /// Number of results per page.
    pub limit: Option<usize>,
    /// User's longitude for distance-based filtering.
    pub longitude: Option<f64>,
    /// Pagination offset for results.
    pub offset: Option<usize>,
    /// Sort order for results (e.g., "date", "distance").
    pub sort_by: Option<String>,
    /// Full-text search query.
    pub ts_query: Option<String>,
    /// Display mode for results (list, calendar, or map).
    pub view_mode: Option<ViewMode>,
}

impl EventsFilters {
    /// Create a new `EventsFilters` instance from the raw query string and headers.
    #[instrument(err)]
    pub(crate) fn new(headers: &HeaderMap, raw_query: &str) -> Result<Self> {
        let mut filters: EventsFilters = serde_html_form::from_str(raw_query)?;

        // Clean up entries that are empty strings
        filters.event_category.retain(|c| !c.is_empty());
        filters.group_category.retain(|c| !c.is_empty());
        filters.region.retain(|r| !r.is_empty());

        // Populate the latitude and longitude fields from the headers provided
        (filters.latitude, filters.longitude) = extract_location(headers);

        // Set default date range when not provided. We'll use the current month as the
        // date range when the view mode is calendar. Otherwise, we'll use the next 12
        // months from now.
        let now = Utc::now();
        if filters.date_from.is_none() {
            let default_date_from = if filters.view_mode == Some(ViewMode::Calendar) {
                // First day of the current month
                NaiveDate::from_ymd_opt(now.year(), now.month(), 1).expect("valid date")
            } else {
                // Today
                now.date_naive()
            };
            filters.date_from = Some(default_date_from.to_string());
        }
        if filters.date_to.is_none() {
            let default_to_date = if filters.view_mode == Some(ViewMode::Calendar) {
                // Last day of the current month
                NaiveDate::from_ymd_opt(now.year(), now.month() + 1, 1)
                    .unwrap_or(NaiveDate::from_ymd_opt(now.year() + 1, 1, 1).expect("valid date"))
                    .pred_opt()
                    .expect("valid date")
            } else {
                // 12 months from now
                now.date_naive()
                    .checked_add_months(Months::new(12))
                    .expect("valid date")
            };
            filters.date_to = Some(default_to_date.to_string());
        }

        // Set some defaults when the view mode is calendar or map
        if filters.view_mode == Some(ViewMode::Calendar) || filters.view_mode == Some(ViewMode::Map) {
            filters.limit = Some(100);
            filters.offset = Some(0);
            filters.include_popover_html = Some(true);
        }

        // Set some defaults when the view mode is map
        if filters.view_mode == Some(ViewMode::Map) {
            filters.include_bbox = Some(true);
        }

        trace!("{:?}", filters);
        Ok(filters)
    }
}

impl ToRawQuery for EventsFilters {
    #[instrument(skip_all, err)]
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

/// Filter parameters for group searches.
///
/// Similar to `EventsFilters` but without temporal filters since groups are ongoing
/// entities. Supports location-based filtering, categorical filtering, and full-text
/// search.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupsFilters {
    /// Selected group categories to filter by.
    #[serde(default)]
    pub group_category: Vec<String>,
    /// Geographic regions to filter by.
    #[serde(default)]
    pub region: Vec<String>,

    /// Northeast latitude of bounding box for map view.
    pub bbox_ne_lat: Option<f64>,
    /// Northeast longitude of bounding box for map view.
    pub bbox_ne_lon: Option<f64>,
    /// Southwest latitude of bounding box for map view.
    pub bbox_sw_lat: Option<f64>,
    /// Southwest longitude of bounding box for map view.
    pub bbox_sw_lon: Option<f64>,
    /// Maximum distance in meters from user's location.
    pub distance: Option<f64>,
    /// Whether to include bounding box in results.
    pub include_bbox: Option<bool>,
    /// Whether to pre-render popover HTML.
    pub include_popover_html: Option<bool>,
    /// User's latitude for distance-based filtering.
    pub latitude: Option<f64>,
    /// Number of results per page.
    pub limit: Option<usize>,
    /// User's longitude for distance-based filtering.
    pub longitude: Option<f64>,
    /// Pagination offset for results.
    pub offset: Option<usize>,
    /// Sort order for results.
    pub sort_by: Option<String>,
    /// Full-text search query.
    pub ts_query: Option<String>,
    /// Display mode for results (list or map).
    pub view_mode: Option<ViewMode>,
}

impl GroupsFilters {
    /// Create a new `GroupsFilters` instance from the raw query string and headers
    /// provided.
    #[instrument(err)]
    pub(crate) fn new(headers: &HeaderMap, raw_query: &str) -> Result<Self> {
        let mut filters: GroupsFilters = serde_html_form::from_str(raw_query)?;

        // Clean up entries that are empty strings
        filters.group_category.retain(|c| !c.is_empty());
        filters.region.retain(|r| !r.is_empty());

        // Populate the latitude and longitude fields from the headers provided.
        (filters.latitude, filters.longitude) = extract_location(headers);

        // Set some defaults when the view mode is calendar or map
        if filters.view_mode == Some(ViewMode::Calendar) || filters.view_mode == Some(ViewMode::Map) {
            filters.limit = Some(100);
            filters.offset = Some(0);
            filters.include_popover_html = Some(true);
        }

        // Set some defaults when the view mode is map
        if filters.view_mode == Some(ViewMode::Map) {
            filters.include_bbox = Some(true);
        }

        trace!("{:?}", filters);
        Ok(filters)
    }
}

impl ToRawQuery for GroupsFilters {
    #[instrument(skip_all, err)]
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

/// Available options for filters.
///
/// This struct provides the lists of available options for some filters.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct FiltersOptions {
    /// Available event categories.
    pub event_category: Vec<FilterOption>,
    /// Available group categories.
    pub group_category: Vec<FilterOption>,
    /// Available distance options (e.g., 5km, 10km, 25km).
    pub distance: Vec<FilterOption>,
    /// Available geographic regions.
    pub region: Vec<FilterOption>,
}

impl FiltersOptions {
    /// Try to create a `FiltersOptions` instance from a JSON string.
    #[instrument(skip_all, err)]
    pub(crate) fn try_from_json(data: &str) -> Result<Self> {
        let filters_options: FiltersOptions = serde_json::from_str(data)?;

        Ok(filters_options)
    }
}

/// Individual filter option with display name and value.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct FilterOption {
    /// Display name shown to users.
    pub name: String,
    /// Technical value used in queries.
    pub value: String,
}

/// Display mode for explore results.
///
/// Determines how results are displayed - as a traditional list, on a calendar view, or
/// as markers on a map.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum ViewMode {
    /// Calendar grid view (events only).
    Calendar,
    /// Traditional list view (default).
    #[default]
    List,
    /// Interactive map view.
    Map,
}

// Pagination.

/// Trait for types that support pagination.
///
/// Provides methods to access and modify pagination parameters, used by the navigation
/// link generation logic to create appropriate URLs for different pages.
pub(crate) trait Pagination {
    /// Get the current page size limit.
    fn limit(&self) -> Option<usize>;

    /// Get the current offset (starting position).
    fn offset(&self) -> Option<usize>;

    /// Update the offset for navigation.
    fn set_offset(&mut self, offset: Option<usize>);
}

/// Trait for converting filter structs to URL query strings.
///
/// Implemented by filter types to provide custom serialization logic for URL query
/// strings.
pub(crate) trait ToRawQuery {
    /// Convert the implementing type to a URL query string.
    fn to_raw_query(&self) -> Result<String>;
}

/// Pagination navigation links for result sets.
///
/// Provides first/last/next/previous links for navigating through paginated results.
/// Links are only populated when applicable based on current position in the result set.
#[derive(Debug, Clone, Default, Template, Serialize, Deserialize)]
#[template(path = "community/explore/navigation_links.html")]
pub(crate) struct NavigationLinks {
    /// Link to first page of results.
    pub first: Option<NavigationLink>,
    /// Link to last page of results.
    pub last: Option<NavigationLink>,
    /// Link to next page of results.
    pub next: Option<NavigationLink>,
    /// Link to previous page of results.
    pub prev: Option<NavigationLink>,
}

impl NavigationLinks {
    /// Generate navigation links based on current filters and result count.
    ///
    /// Calculates which navigation links should be shown based on the current offset,
    /// limit, and total number of results. Only creates links that make sense (e.g., no
    /// "previous" link on the first page).
    pub(crate) fn from_filters<T>(entity: &Entity, filters: &T, total: usize) -> Result<Self>
    where
        T: Serialize + Clone + ToRawQuery + Pagination,
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

/// Individual navigation link with URLs for both standard and HTMX requests.
///
/// Each link includes two URLs: one for standard page navigation and one for HTMX partial
/// updates to enable seamless client-side updates.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct NavigationLink {
    /// URL for HTMX partial page updates.
    pub hx_url: String,
    /// URL for standard full-page navigation.
    pub url: String,
}

impl NavigationLink {
    /// Create a navigation link with both standard and HTMX URLs.
    pub(crate) fn new<T>(entity: &Entity, filters: &T) -> Result<Self>
    where
        T: Serialize + ToRawQuery,
    {
        let base_hx_url = format!("/explore/{entity}-results-section");
        let base_url = format!("/explore?entity={entity}");

        Ok(NavigationLink {
            hx_url: build_url(&base_hx_url, filters)?,
            url: build_url(&base_url, filters)?,
        })
    }
}

/// Calculated pagination offsets for navigation links.
///
/// Internal struct used to determine which navigation links should be created based on
/// the current position in the result set.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
struct NavigationLinksOffsets {
    /// Offset for first page.
    first: Option<usize>,
    /// Offset for last page.
    last: Option<usize>,
    /// Offset for next page.
    next: Option<usize>,
    /// Offset for previous page.
    prev: Option<usize>,
}

impl NavigationLinksOffsets {
    /// Calculate appropriate offsets for pagination links.
    ///
    /// Determines which navigation links should exist based on the current offset, page
    /// size (limit), and total number of results.
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

/// Build a URL with filter parameters appended as query string.
///
/// Takes a base URL and a serializable filter object, converts the filters to URL query
/// parameters, and appends them appropriately.
pub(crate) fn build_url<T>(base_url: &str, filters: &T) -> Result<String>
where
    T: Serialize + ToRawQuery,
{
    let mut url = base_url.to_string();
    let sep = get_url_filters_separator(base_url);
    let filters_params = filters.to_raw_query()?;
    if !filters_params.is_empty() {
        write!(url, "{sep}{filters_params}").expect("write to succeed");
    }
    Ok(url)
}

/// Determine the appropriate separator for appending query parameters.
///
/// Returns "?" if the URL has no query string, "&" if it has parameters but doesn't end
/// with a separator, or "" if it already ends with one.
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

#[cfg(test)]
mod tests {
    use super::{DEFAULT_PAGINATION_LIMIT, NavigationLinksOffsets, get_url_filters_separator};

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
        test_navigation_links_offsets_1: {
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

        test_navigation_links_offsets_2: {
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

        test_navigation_links_offsets_3: {
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

        test_navigation_links_offsets_4: {
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

        test_navigation_links_offsets_5: {
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

        test_navigation_links_offsets_6: {
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

        test_navigation_links_offsets_7: {
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

        test_navigation_links_offsets_8: {
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

        test_navigation_links_offsets_9: {
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

        test_navigation_links_offsets_10: {
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

        test_navigation_links_offsets_11: {
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

        test_navigation_links_offsets_12: {
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

        test_navigation_links_offsets_13: {
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
        test_get_url_filters_separator_1: ("https://example.com", "?"),
        test_get_url_filters_separator_2: ("https://example.com?", ""),
        test_get_url_filters_separator_3: ("https://example.com?param1=value1", "&"),
        test_get_url_filters_separator_4: ("https://example.com?param1=value1&", ""),
    }
}
