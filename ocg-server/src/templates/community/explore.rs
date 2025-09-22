//! Templates and types for the community site explore page.

use anyhow::Result;
use askama::Template;
use axum::http::HeaderMap;
use chrono::{Datelike, Months, NaiveDate, Utc};
use minify_html::{Cfg as MinifyCfg, minify};
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{
    db::BBox,
    templates::{
        PageId,
        auth::User,
        filters,
        helpers::{location::extract_location, user_initials},
    },
    types::{
        community::Community,
        event::{EventDetailed, EventKind, EventSummary},
        group::{GroupDetailed, GroupSummary},
    },
};

use super::{
    home::{EventCard as HomeEventCard, GroupCard as HomeGroupCard},
    pagination::{NavigationLinks, Pagination, ToRawQuery},
};

// Pages and sections templates.

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
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current URL path.
    pub path: String,
    /// Authenticated user information.
    pub user: User,

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
    pub events: Vec<EventCard>,
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

/// Event card template for explore page display.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "common/event_card_medium.html")]
pub(crate) struct EventCard {
    /// Event data
    #[serde(flatten)]
    pub event: EventDetailed,
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
    pub groups: Vec<GroupCard>,
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

/// Group card template for explore page display.
#[skip_serializing_none]
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/explore/groups/group_card.html")]
pub(crate) struct GroupCard {
    /// Group data
    #[serde(flatten)]
    pub group: GroupDetailed,
}

// Types.

/// Represents the type of content being explored.
///
/// The explore page can display either events or groups. This enum determines which
/// section is shown.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, strum::Display, strum::EnumString)]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum Entity {
    /// Explore events (default).
    #[default]
    Events,
    /// Explore groups.
    Groups,
}

impl From<Option<&String>> for Entity {
    fn from(entity: Option<&String>) -> Self {
        entity.and_then(|value| value.parse().ok()).unwrap_or_default()
    }
}

/// Filter parameters for event searches.
///
/// This struct captures all possible filtering criteria for events including
/// location-based filters (bounding box, distance), temporal filters (date range),
/// categorical filters, etc.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct EventsFilters {
    /// Selected event categories to filter by.
    #[serde(default)]
    pub event_category: Vec<String>,
    /// Selected groups to filter by.
    #[serde(default)]
    pub group: Vec<Uuid>,
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
    /// Sort direction for results ("asc" or "desc").
    pub sort_direction: Option<String>,
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
    fn to_raw_query(&self) -> Result<String> {
        // Reset some filters we don't want to include in the query string
        let mut filters = self.clone();
        if filters.date_from == Some(Utc::now().date_naive().to_string()) {
            filters.date_from = None;
        }
        if let Some(date_to) = Utc::now().date_naive().checked_add_months(Months::new(12))
            && filters.date_to == Some(date_to.to_string())
        {
            filters.date_to = None;
        }
        filters.latitude = None;
        filters.longitude = None;
        if filters.sort_by == Some("date".to_string()) {
            filters.sort_by = None;
        }
        if filters.sort_direction == Some("asc".to_string()) {
            filters.sort_direction = None;
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
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
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
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
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
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
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

// Helpers for rendering popovers.

/// Render popover HTML for map and calendar views for an event.
#[instrument(skip_all, err)]
pub(crate) fn render_event_popover(event: &EventDetailed) -> Result<String> {
    let event_summary = EventSummary::from(event.clone());
    let home_event = HomeEventCard { event: event_summary };
    let cfg = MinifyCfg::new();
    Ok(String::from_utf8(minify(home_event.render()?.as_bytes(), &cfg))?)
}

/// Render popover HTML for map views for a group.
#[instrument(skip_all, err)]
pub(crate) fn render_group_popover(group: &GroupDetailed) -> Result<String> {
    let group_summary: GroupSummary = group.clone().into();
    let home_group = HomeGroupCard { group: group_summary };
    let cfg = MinifyCfg::new();
    Ok(String::from_utf8(minify(home_group.render()?.as_bytes(), &cfg))?)
}
