//! Shared search filter types and helpers used across the application.

use anyhow::Result;
use chrono::{DateTime, Datelike, Months, NaiveDate, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::{NoneAsEmptyString, serde_as, skip_serializing_none};

use crate::{
    types::{
        event::{EventKind, EventSummary},
        group::GroupSummary,
        pagination::{Pagination, ToRawQuery},
    },
    validation::{
        MAX_ITEMS, MAX_LEN_M, MAX_LEN_SORT_KEY, MAX_PAGINATION_LIMIT, trimmed_non_empty_opt,
        valid_date_opt, valid_latitude, valid_longitude,
    },
};

#[cfg(test)]
mod tests;

/// Maximum number of items returned to draw the explore map and calendar.
pub(crate) const EXPLORE_WIDGET_MAX_ITEMS: usize = 1000;

// Search filters.

/// Filter parameters for event searches.
///
/// This struct captures all possible filtering criteria for events including
/// location-based filters (bounding box, distance), temporal filters (date range),
/// categorical filters, etc.
#[serde_as]
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct SearchEventsFilters {
    /// Community names to filter by.
    #[serde(default)]
    #[garde(length(max = MAX_ITEMS), inner(length(max = MAX_LEN_M)))]
    pub community: Vec<String>,
    /// Selected event categories to filter by.
    #[serde(default)]
    #[garde(length(max = MAX_ITEMS), inner(length(max = MAX_LEN_M)))]
    pub event_category: Vec<String>,
    /// Selected groups to filter by (slugs).
    #[serde(default)]
    #[garde(length(max = MAX_ITEMS), inner(length(max = MAX_LEN_M)))]
    pub group: Vec<String>,
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
    /// Start date for event filtering (YYYY-MM-DD format, blank treated as missing).
    #[serde_as(as = "NoneAsEmptyString")]
    #[serde(default)]
    #[garde(custom(valid_date_opt))]
    pub date_from: Option<NaiveDate>,
    /// End date for event filtering (YYYY-MM-DD format, blank treated as missing).
    #[serde_as(as = "NoneAsEmptyString")]
    #[serde(default)]
    #[garde(custom(valid_date_opt))]
    pub date_to: Option<NaiveDate>,
    /// Maximum distance in meters from user's location.
    #[garde(skip)]
    pub distance: Option<u64>,
    /// User's latitude for distance-based filtering.
    #[garde(custom(valid_latitude))]
    pub latitude: Option<f64>,
    /// Number of results per page.
    #[serde(default = "default_limit")]
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// User's longitude for distance-based filtering.
    #[garde(custom(valid_longitude))]
    pub longitude: Option<f64>,
    /// Pagination offset for results.
    #[serde(default = "default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
    /// Sort order for results (e.g., "date", "distance").
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_SORT_KEY))]
    pub sort_by: Option<String>,
    /// Sort direction for results ("asc" or "desc").
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_SORT_KEY))]
    pub sort_direction: Option<String>,
    /// Full-text search query.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub ts_query: Option<String>,
    /// Display mode for results (list, calendar, or map).
    #[garde(skip)]
    pub view_mode: Option<ViewMode>,
}

impl SearchEventsFilters {
    /// Normalizes parsed filters by dropping empty entries and applying view defaults.
    ///
    /// Missing date bounds default to the month of `now` in calendar view, and
    /// to the twelve months starting on `now` in other views.
    pub(crate) fn normalize(&mut self, now: DateTime<Utc>) {
        // Drop entries that are empty strings
        self.event_category.retain(|c| !c.is_empty());
        self.group.retain(|g| !g.is_empty());
        self.group_category.retain(|c| !c.is_empty());
        self.region.retain(|r| !r.is_empty());

        // Default the missing start date for the active view
        if self.date_from.is_none() {
            let default_date_from = if self.view_mode == Some(ViewMode::Calendar) {
                // First day of the current month
                NaiveDate::from_ymd_opt(now.year(), now.month(), 1).expect("valid date")
            } else {
                // Today
                now.date_naive()
            };
            self.date_from = Some(default_date_from);
        }

        // Default the missing end date for the active view
        if self.date_to.is_none() {
            let default_to_date = if self.view_mode == Some(ViewMode::Calendar) {
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
            self.date_to = Some(default_to_date);
        }
    }

    /// Returns whether this search depends on viewer location headers.
    pub(crate) fn uses_viewer_location(&self) -> bool {
        self.latitude.is_some()
            && self.longitude.is_some()
            && (self.distance.is_some() || self.sort_by.as_deref() == Some("distance"))
    }
}

impl ToRawQuery for SearchEventsFilters {
    fn to_raw_query(&self) -> Result<String> {
        // Reset some filters we don't want to include in the query string
        let mut filters = self.clone();
        let today = Utc::now().date_naive();
        if filters.date_from == Some(today) {
            filters.date_from = None;
        }
        if let Some(date_to) = today.checked_add_months(Months::new(12))
            && filters.date_to == Some(date_to)
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

impl Pagination for SearchEventsFilters {
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
/// Similar to `SearchEventsFilters` but without temporal filters since groups are ongoing.
/// entities. Supports location-based filtering, categorical filtering, and full-text
/// search.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct SearchGroupsFilters {
    /// Community names to filter by.
    #[serde(default)]
    #[garde(length(max = MAX_ITEMS), inner(length(max = MAX_LEN_M)))]
    pub community: Vec<String>,
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
    /// Whether to include inactive groups in results.
    #[serde(default, skip_deserializing)]
    #[garde(skip)]
    pub include_inactive: Option<bool>,
    /// User's latitude for distance-based filtering.
    #[garde(custom(valid_latitude))]
    pub latitude: Option<f64>,
    /// Number of results per page.
    #[serde(default = "default_limit")]
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// User's longitude for distance-based filtering.
    #[garde(custom(valid_longitude))]
    pub longitude: Option<f64>,
    /// Pagination offset for results.
    #[serde(default = "default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
    /// Sort order for results.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_SORT_KEY))]
    pub sort_by: Option<String>,
    /// Full-text search query.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub ts_query: Option<String>,
    /// Display mode for results (list or map).
    #[garde(skip)]
    pub view_mode: Option<ViewMode>,
}

impl SearchGroupsFilters {
    /// Normalizes parsed filters by dropping empty entries.
    pub(crate) fn normalize(&mut self) {
        // Drop entries that are empty strings
        self.group_category.retain(|c| !c.is_empty());
        self.region.retain(|r| !r.is_empty());
    }

    /// Returns whether this search depends on viewer location headers.
    pub(crate) fn uses_viewer_location(&self) -> bool {
        self.latitude.is_some()
            && self.longitude.is_some()
            && (self.distance.is_some() || self.sort_by.as_deref() == Some("distance"))
    }
}

impl ToRawQuery for SearchGroupsFilters {
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

impl Pagination for SearchGroupsFilters {
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

// Other related types.

/// Geographic bounding box coordinates.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct BBox {
    /// Northeastern latitude.
    pub ne_lat: f64,
    /// Northeastern longitude.
    pub ne_lon: f64,
    /// Southwestern latitude.
    pub sw_lat: f64,
    /// Southwestern longitude.
    pub sw_lon: f64,
}

/// Output structure for events search operations.
///
/// List searches return a page of `EventSummary` items. The explore map and
/// calendar return `EventMinimal` items, up to `EXPLORE_WIDGET_MAX_ITEMS`.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct SearchEventsOutput<T = EventSummary> {
    /// Matching events on the current result page or up to the items cap.
    pub events: Vec<T>,
    /// Total matching event count.
    pub total: usize,

    /// Geographic bounds covering every matching event in map view.
    pub bbox: Option<BBox>,
    /// Whether some matching events were left out by the items cap.
    #[serde(default)]
    pub truncated: bool,
}

/// Output structure for groups search operations.
///
/// List searches return a page of `GroupSummary` items. The explore map
/// returns located `GroupMinimal` items, up to `EXPLORE_WIDGET_MAX_ITEMS`.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct SearchGroupsOutput<T = GroupSummary> {
    /// Matching groups on the current result page or up to the items cap.
    pub groups: Vec<T>,
    /// Total matching group count.
    pub total: usize,

    /// Geographic bounds covering every matching group in map view.
    pub bbox: Option<BBox>,
    /// Whether some matching groups were left out by the items cap.
    #[serde(default)]
    pub truncated: bool,
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

// Serde defaults.

/// Default explore pagination limit for serde.
#[allow(clippy::unnecessary_wraps)]
fn default_limit() -> Option<usize> {
    Some(10)
}

/// Default explore pagination offset for serde.
#[allow(clippy::unnecessary_wraps)]
fn default_offset() -> Option<usize> {
    Some(0)
}
