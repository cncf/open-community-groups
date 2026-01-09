//! Templates and types for the site explore page.

use anyhow::Result;
use askama::Template;
use axum::http::HeaderMap;
use chrono::{Datelike, Months, NaiveDate, Utc};
use garde::Validate;
use minify_html::{Cfg as MinifyCfg, minify};
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{
    db::BBox,
    router::serde_qs_config,
    templates::{
        PageId,
        auth::User,
        filters,
        helpers::{location::extract_location, user_initials},
    },
    types::{
        community::Community,
        event::{EventKind, EventSummary},
        group::GroupSummary,
        site::SiteSettings,
    },
    validation::{
        MAX_ITEMS, MAX_LEN_M, MAX_LEN_S, MAX_PAGINATION_LIMIT, trimmed_non_empty_opt, valid_latitude,
        valid_longitude,
    },
};

use super::pagination::{NavigationLinks, Pagination, ToRawQuery};

use crate::templates::community::{EventCard as HomeEventCard, GroupCard as HomeGroupCard};

// Pages and sections templates.

/// Template for the explore page.
///
/// This is the root template that renders the explore page with either events or groups
/// content based on the selected entity. The community is optional to support both global
/// and community-specific explore pages.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "site/explore/page.html")]
pub(crate) struct Page {
    /// The type of content being explored (events or groups).
    pub entity: Entity,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current URL path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,

    /// Community information (None for global explore page).
    pub community: Option<Community>,
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
#[template(path = "site/explore/events/section.html")]
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
#[template(path = "site/explore/events/results.html")]
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
    pub event: EventSummary,
}

/// Template for the groups section of the explore page.
///
/// This template renders the groups exploration interface, including filters panel and
/// results. It's used when `Entity::Groups` is selected.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "site/explore/groups/section.html")]
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
#[template(path = "site/explore/groups/results.html")]
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
#[template(path = "site/explore/groups/group_card.html")]
pub(crate) struct GroupCard {
    /// Group data
    #[serde(flatten)]
    pub group: GroupSummary,
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
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct EventsFilters {
    /// Community IDs to filter by.
    #[serde(default)]
    #[garde(length(max = MAX_ITEMS))]
    pub community: Vec<Uuid>,
    /// Selected event categories to filter by.
    #[serde(default)]
    #[garde(length(max = MAX_ITEMS), inner(length(max = MAX_LEN_M)))]
    pub event_category: Vec<String>,
    /// Selected groups to filter by.
    #[serde(default)]
    #[garde(length(max = MAX_ITEMS))]
    pub group: Vec<Uuid>,
    /// Selected group categories to filter by.
    #[serde(default)]
    #[garde(length(max = MAX_ITEMS), inner(length(max = MAX_LEN_M)))]
    pub group_category: Vec<String>,
    /// Event types to include (in-person, online, hybrid).
    #[serde(default)]
    #[garde(length(max = MAX_ITEMS))]
    pub kind: Vec<EventKind>,
    /// Geographic regions to filter by.
    #[serde(default)]
    #[garde(length(max = MAX_ITEMS), inner(length(max = MAX_LEN_M)))]
    pub region: Vec<String>,

    /// Northeast latitude of bounding box for map view.
    #[garde(custom(valid_latitude))]
    pub bbox_ne_lat: Option<f64>,
    /// Northeast longitude of bounding box for map view.
    #[garde(custom(valid_longitude))]
    pub bbox_ne_lon: Option<f64>,
    /// Southwest latitude of bounding box for map view.
    #[garde(custom(valid_latitude))]
    pub bbox_sw_lat: Option<f64>,
    /// Southwest longitude of bounding box for map view.
    #[garde(custom(valid_longitude))]
    pub bbox_sw_lon: Option<f64>,
    /// Start date for event filtering (YYYY-MM-DD format).
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub date_from: Option<String>,
    /// End date for event filtering (YYYY-MM-DD format).
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub date_to: Option<String>,
    /// Maximum distance in meters from user's location.
    #[garde(skip)]
    pub distance: Option<u64>,
    /// Whether to include bounding box in results (for map view).
    #[garde(skip)]
    pub include_bbox: Option<bool>,
    /// User's latitude for distance-based filtering.
    #[garde(custom(valid_latitude))]
    pub latitude: Option<f64>,
    /// Number of results per page.
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// User's longitude for distance-based filtering.
    #[garde(custom(valid_longitude))]
    pub longitude: Option<f64>,
    /// Pagination offset for results.
    #[garde(skip)]
    pub offset: Option<usize>,
    /// Sort order for results (e.g., "date", "distance").
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub sort_by: Option<String>,
    /// Sort direction for results ("asc" or "desc").
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub sort_direction: Option<String>,
    /// Full-text search query.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub ts_query: Option<String>,
    /// Display mode for results (list, calendar, or map).
    #[garde(skip)]
    pub view_mode: Option<ViewMode>,
}

impl EventsFilters {
    /// Create a new `EventsFilters` instance from the raw query string and headers.
    #[instrument(err)]
    pub(crate) fn new(headers: &HeaderMap, raw_query: &str) -> Result<Self, FilterError> {
        let mut filters: EventsFilters = serde_qs_config().deserialize_str(raw_query)?;
        filters.validate()?;

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

        serde_qs::to_string(&filters).map_err(anyhow::Error::from)
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
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct GroupsFilters {
    /// Community IDs to filter by.
    #[serde(default)]
    #[garde(length(max = MAX_ITEMS))]
    pub community: Vec<Uuid>,
    /// Selected group categories to filter by.
    #[serde(default)]
    #[garde(length(max = MAX_ITEMS), inner(length(max = MAX_LEN_M)))]
    pub group_category: Vec<String>,
    /// Geographic regions to filter by.
    #[serde(default)]
    #[garde(length(max = MAX_ITEMS), inner(length(max = MAX_LEN_M)))]
    pub region: Vec<String>,

    /// Northeast latitude of bounding box for map view.
    #[garde(custom(valid_latitude))]
    pub bbox_ne_lat: Option<f64>,
    /// Northeast longitude of bounding box for map view.
    #[garde(custom(valid_longitude))]
    pub bbox_ne_lon: Option<f64>,
    /// Southwest latitude of bounding box for map view.
    #[garde(custom(valid_latitude))]
    pub bbox_sw_lat: Option<f64>,
    /// Southwest longitude of bounding box for map view.
    #[garde(custom(valid_longitude))]
    pub bbox_sw_lon: Option<f64>,
    /// Maximum distance in meters from user's location.
    #[garde(skip)]
    pub distance: Option<f64>,
    /// Whether to include bounding box in results.
    #[garde(skip)]
    pub include_bbox: Option<bool>,
    /// User's latitude for distance-based filtering.
    #[garde(custom(valid_latitude))]
    pub latitude: Option<f64>,
    /// Number of results per page.
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// User's longitude for distance-based filtering.
    #[garde(custom(valid_longitude))]
    pub longitude: Option<f64>,
    /// Pagination offset for results.
    #[garde(skip)]
    pub offset: Option<usize>,
    /// Sort order for results.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub sort_by: Option<String>,
    /// Full-text search query.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub ts_query: Option<String>,
    /// Display mode for results (list or map).
    #[garde(skip)]
    pub view_mode: Option<ViewMode>,
}

impl GroupsFilters {
    /// Create a new `GroupsFilters` instance from the raw query string and headers
    /// provided.
    #[instrument(err)]
    pub(crate) fn new(headers: &HeaderMap, raw_query: &str) -> Result<Self, FilterError> {
        let mut filters: GroupsFilters = serde_qs_config().deserialize_str(raw_query)?;
        filters.validate()?;

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

        serde_qs::to_string(&filters).map_err(anyhow::Error::from)
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

/// Error that can occur when creating filter instances.
#[derive(Debug, thiserror::Error)]
pub(crate) enum FilterError {
    /// Error parsing the query string.
    #[error("parse error: {0}")]
    Parse(#[from] serde_qs::Error),

    /// Validation error.
    #[error("validation error: {0}")]
    Validation(#[from] garde::Report),
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
pub(crate) fn render_event_popover(event: &EventSummary) -> Result<String> {
    let home_event = HomeEventCard { event: event.clone() };
    let cfg = MinifyCfg::new();
    Ok(String::from_utf8(minify(home_event.render()?.as_bytes(), &cfg))?)
}

/// Render popover HTML for map views for a group.
#[instrument(skip_all, err)]
pub(crate) fn render_group_popover(group: &GroupSummary) -> Result<String> {
    let home_group = HomeGroupCard { group: group.clone() };
    let cfg = MinifyCfg::new();
    Ok(String::from_utf8(minify(home_group.render()?.as_bytes(), &cfg))?)
}

// Tests.

#[cfg(test)]
mod tests {
    use axum::http::{HeaderMap, HeaderValue};
    use chrono::{Datelike, Months, NaiveDate, Utc};

    use super::*;

    #[test]
    fn test_events_filters_new_list_cleans_empty_entries() {
        // Prepare headers and raw query (using bracket notation for arrays)
        let raw_query = [
            "event_category[0]=",
            "event_category[1]=conference",
            "group_category[0]=",
            "group_category[1]=rust",
            "region[0]=",
            "region[1]=europe",
            "view_mode=list",
        ]
        .join("&");

        // Create filters
        let filters = EventsFilters::new(&HeaderMap::new(), &raw_query).expect("filters to be created");

        // Check filters match expected values
        assert_eq!(filters.event_category, vec!["conference".to_string()]);
        assert_eq!(filters.group_category, vec!["rust".to_string()]);
        assert_eq!(filters.region, vec!["europe".to_string()]);
        assert_eq!(filters.view_mode, Some(ViewMode::List));
    }

    #[test]
    fn test_events_filters_new_list_extracts_location_from_headers() {
        // Prepare headers and raw query
        let mut headers = HeaderMap::new();
        headers.insert("CloudFront-Viewer-Latitude", HeaderValue::from_static("51.5"));
        headers.insert("CloudFront-Viewer-Longitude", HeaderValue::from_static("-0.12"));

        // Create filters
        let filters = EventsFilters::new(&headers, "view_mode=list").expect("filters to be created");

        // Check filters match expected values
        assert_eq!(filters.latitude, Some(51.5));
        assert_eq!(filters.longitude, Some(-0.12));
        assert_eq!(filters.view_mode, Some(ViewMode::List));
    }

    #[test]
    fn test_events_filters_new_list_sets_default_date_range_when_missing() {
        // Capture the time before
        let before = Utc::now().date_naive();

        // Create filters
        let filters = EventsFilters::new(&HeaderMap::new(), "view_mode=list").expect("filters to be created");

        // Capture the time after
        let after = Utc::now().date_naive();

        // Parse the dates from the filters
        let date_from = filters.date_from.as_ref().expect("date_from to exist");
        let date_to = filters.date_to.as_ref().expect("date_to to exist");
        let date_from = NaiveDate::parse_from_str(date_from, "%Y-%m-%d").expect("valid date");
        let date_to = NaiveDate::parse_from_str(date_to, "%Y-%m-%d").expect("valid date");
        let expected_date_to = date_from
            .checked_add_months(Months::new(12))
            .expect("valid future date");

        // Check filters match expected values
        assert_eq!(filters.view_mode, Some(ViewMode::List));
        assert!(
            date_from == before || date_from == after,
            "date_from should match today"
        );
        assert_eq!(date_to, expected_date_to);
    }

    #[test]
    fn test_events_filters_new_calendar_sets_month_date_range() {
        // Capture the time before
        let before = Utc::now();

        // Create filters
        let filters =
            EventsFilters::new(&HeaderMap::new(), "view_mode=calendar").expect("filters to be created");

        // Capture the time after
        let after = Utc::now();

        // Parse the dates from the filters
        let date_from = filters.date_from.as_ref().expect("date_from to exist");
        let date_from = NaiveDate::parse_from_str(date_from, "%Y-%m-%d").expect("valid date");
        let date_to = filters.date_to.as_ref().expect("date_to to exist");
        let date_to = NaiveDate::parse_from_str(date_to, "%Y-%m-%d").expect("valid date");
        let month_first_day_before =
            NaiveDate::from_ymd_opt(before.year(), before.month(), 1).expect("valid date");
        let month_first_day_after =
            NaiveDate::from_ymd_opt(after.year(), after.month(), 1).expect("valid date");
        let month_last_day = date_from
            .checked_add_months(Months::new(1))
            .expect("valid next month")
            .pred_opt()
            .expect("valid month end");

        // Check filters match expected values
        assert_eq!(filters.view_mode, Some(ViewMode::Calendar));
        assert_eq!(filters.limit, Some(100));
        assert_eq!(filters.offset, Some(0));
        assert!(
            date_from == month_first_day_before || date_from == month_first_day_after,
            "date_from should match the first day of the current month"
        );
        assert_eq!(date_to, month_last_day);
    }

    #[test]
    fn test_events_filters_new_list_uses_provided_date_range() {
        // Create filters
        let filters = EventsFilters::new(
            &HeaderMap::new(),
            "date_from=2031-01-15&date_to=2031-02-20&view_mode=list",
        )
        .expect("filters to be created");

        // Check filters match expected values
        assert_eq!(filters.date_from.as_deref(), Some("2031-01-15"));
        assert_eq!(filters.date_to.as_deref(), Some("2031-02-20"));
        assert_eq!(filters.view_mode, Some(ViewMode::List));
    }

    #[test]
    fn test_events_filters_new_map_sets_bbox_and_pagination() {
        // Prepare headers and raw query
        let raw_query = [
            "bbox_ne_lat=45.0",
            "bbox_ne_lon=10.0",
            "bbox_sw_lat=40.0",
            "bbox_sw_lon=5.0",
            "view_mode=map",
        ]
        .join("&");

        // Create filters
        let filters = EventsFilters::new(&HeaderMap::new(), &raw_query).expect("filters to be created");

        // Check filters match expected values
        assert_eq!(filters.view_mode, Some(ViewMode::Map));
        assert_eq!(filters.include_bbox, Some(true));
        assert_eq!(filters.limit, Some(100));
        assert_eq!(filters.offset, Some(0));
        assert_eq!(filters.bbox_ne_lat, Some(45.0));
        assert_eq!(filters.bbox_ne_lon, Some(10.0));
        assert_eq!(filters.bbox_sw_lat, Some(40.0));
        assert_eq!(filters.bbox_sw_lon, Some(5.0));
    }

    #[test]
    fn test_events_filters_to_raw_query_preserves_custom_values() {
        // Prepare filters
        let filters = EventsFilters {
            date_from: Some("2030-01-01".to_string()),
            date_to: Some("2030-06-01".to_string()),
            event_category: vec!["conference".to_string()],
            include_bbox: Some(false),
            kind: vec![EventKind::Hybrid],
            latitude: Some(51.5),
            limit: Some(40),
            longitude: Some(-0.12),
            offset: Some(15),
            sort_by: Some("distance".to_string()),
            ts_query: Some("rust".to_string()),
            view_mode: Some(ViewMode::List),
            ..Default::default()
        };

        // Generate raw query
        let query = filters.to_raw_query().expect("raw query to be generated");

        // Check query contains expected parameters (serde_qs uses bracket notation for arrays)
        assert!(query.contains("date_from=2030-01-01"));
        assert!(query.contains("date_to=2030-06-01"));
        assert!(query.contains("event_category[0]=conference"));
        assert!(query.contains("include_bbox=false"));
        assert!(query.contains("kind[0]=hybrid"));
        assert!(query.contains("limit=40"));
        assert!(query.contains("offset=15"));
        assert!(query.contains("sort_by=distance"));
        assert!(query.contains("ts_query=rust"));
        assert!(query.contains("view_mode=list"));
        assert!(!query.contains("latitude"));
        assert!(!query.contains("longitude"));
    }

    #[test]
    fn test_events_filters_to_raw_query_resets_default_values() {
        // Prepare filters
        let date_from = Utc::now().date_naive();
        let date_to = date_from.checked_add_months(Months::new(12)).expect("valid date");
        let filters = EventsFilters {
            date_from: Some(date_from.to_string()),
            date_to: Some(date_to.to_string()),
            event_category: vec!["meetup".to_string()],
            include_bbox: Some(true),
            kind: vec![EventKind::InPerson],
            latitude: Some(52.0),
            limit: Some(20),
            longitude: Some(13.0),
            offset: Some(5),
            sort_by: Some("date".to_string()),
            ts_query: Some("rust".to_string()),
            view_mode: Some(ViewMode::List),
            ..Default::default()
        };

        // Generate raw query
        let query = filters.to_raw_query().expect("raw query to be generated");

        // Check query contains expected parameters (serde_qs uses bracket notation for arrays)
        assert!(query.contains("event_category[0]=meetup"));
        assert!(query.contains("include_bbox=true"));
        assert!(query.contains("limit=20"));
        assert!(query.contains("offset=5"));
        assert!(query.contains("ts_query=rust"));
        assert!(query.contains("view_mode=list"));
        assert!(!query.contains("date_from"));
        assert!(!query.contains("date_to"));
        assert!(!query.contains("latitude"));
        assert!(!query.contains("longitude"));
        assert!(!query.contains("sort_by"));
    }

    #[test]
    fn test_groups_filters_new_list_cleans_empty_entries() {
        // Prepare headers and raw query (using bracket notation for arrays)
        let raw_query = [
            "group_category[0]=",
            "group_category[1]=rust",
            "region[0]=",
            "region[1]=europe",
            "view_mode=list",
        ]
        .join("&");

        // Create filters
        let filters = GroupsFilters::new(&HeaderMap::new(), &raw_query).expect("filters to be created");

        // Check filters match expected values
        assert_eq!(filters.group_category, vec!["rust".to_string()]);
        assert_eq!(filters.region, vec!["europe".to_string()]);
        assert_eq!(filters.view_mode, Some(ViewMode::List));
    }

    #[test]
    fn test_groups_filters_new_list_extracts_location_from_headers() {
        // Prepare headers and raw query
        let mut headers = HeaderMap::new();
        headers.insert("CloudFront-Viewer-Latitude", HeaderValue::from_static("51.5"));
        headers.insert("CloudFront-Viewer-Longitude", HeaderValue::from_static("-0.12"));

        // Create filters
        let filters = GroupsFilters::new(&headers, "view_mode=list").expect("filters to be created");

        // Check filters match expected values
        assert_eq!(filters.latitude, Some(51.5));
        assert_eq!(filters.longitude, Some(-0.12));
        assert_eq!(filters.view_mode, Some(ViewMode::List));
    }

    #[test]
    fn test_groups_filters_new_calendar_sets_pagination_defaults() {
        // Create filters
        let filters =
            GroupsFilters::new(&HeaderMap::new(), "view_mode=calendar").expect("filters to be created");

        // Check filters match expected values
        assert_eq!(filters.view_mode, Some(ViewMode::Calendar));
        assert_eq!(filters.limit, Some(100));
        assert_eq!(filters.offset, Some(0));
        assert_eq!(filters.include_bbox, None);
    }

    #[test]
    fn test_groups_filters_new_map_sets_bbox_and_pagination_defaults() {
        // Prepare headers and raw query
        let raw_query = [
            "bbox_ne_lat=45.0",
            "bbox_ne_lon=10.0",
            "bbox_sw_lat=40.0",
            "bbox_sw_lon=5.0",
            "view_mode=map",
        ]
        .join("&");

        // Create filters
        let filters = GroupsFilters::new(&HeaderMap::new(), &raw_query).expect("filters to be created");

        // Check filters match expected values
        assert_eq!(filters.view_mode, Some(ViewMode::Map));
        assert_eq!(filters.include_bbox, Some(true));
        assert_eq!(filters.limit, Some(100));
        assert_eq!(filters.offset, Some(0));
        assert_eq!(filters.bbox_ne_lat, Some(45.0));
        assert_eq!(filters.bbox_ne_lon, Some(10.0));
        assert_eq!(filters.bbox_sw_lat, Some(40.0));
        assert_eq!(filters.bbox_sw_lon, Some(5.0));
    }

    #[test]
    fn test_groups_filters_to_raw_query_preserves_custom_values() {
        // Prepare filters
        let filters = GroupsFilters {
            distance: Some(25.5),
            group_category: vec!["rust".to_string()],
            include_bbox: Some(false),
            latitude: Some(51.5),
            limit: Some(40),
            longitude: Some(-0.12),
            offset: Some(15),
            region: vec!["europe".to_string()],
            sort_by: Some("distance".to_string()),
            ts_query: Some("community".to_string()),
            view_mode: Some(ViewMode::List),
            ..Default::default()
        };

        // Generate raw query
        let query = filters.to_raw_query().expect("raw query to be generated");

        // Check query contains expected parameters (serde_qs uses bracket notation for arrays)
        assert!(query.contains("distance=25.5"));
        assert!(query.contains("group_category[0]=rust"));
        assert!(query.contains("include_bbox=false"));
        assert!(query.contains("limit=40"));
        assert!(query.contains("offset=15"));
        assert!(query.contains("region[0]=europe"));
        assert!(query.contains("sort_by=distance"));
        assert!(query.contains("ts_query=community"));
        assert!(query.contains("view_mode=list"));
        assert!(!query.contains("latitude"));
        assert!(!query.contains("longitude"));
    }

    #[test]
    fn test_groups_filters_to_raw_query_resets_default_values() {
        // Prepare filters
        let filters = GroupsFilters {
            group_category: vec!["dev".to_string()],
            include_bbox: Some(true),
            latitude: Some(40.0),
            limit: Some(20),
            longitude: Some(-3.7),
            offset: Some(5),
            region: vec!["emea".to_string()],
            sort_by: Some("date".to_string()),
            ts_query: Some("rust".to_string()),
            view_mode: Some(ViewMode::List),
            ..Default::default()
        };

        // Generate raw query
        let query = filters.to_raw_query().expect("raw query to be generated");

        // Check query contains expected parameters (serde_qs uses bracket notation for arrays)
        assert!(query.contains("group_category[0]=dev"));
        assert!(query.contains("include_bbox=true"));
        assert!(query.contains("limit=20"));
        assert!(query.contains("offset=5"));
        assert!(query.contains("region[0]=emea"));
        assert!(query.contains("ts_query=rust"));
        assert!(query.contains("view_mode=list"));
        assert!(!query.contains("latitude"));
        assert!(!query.contains("longitude"));
        assert!(!query.contains("sort_by"));
    }
}
