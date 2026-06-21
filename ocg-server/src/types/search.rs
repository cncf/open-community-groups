//! Shared search filter types and helpers used across the application.

use anyhow::Result;
use axum::http::HeaderMap;
use chrono::{Datelike, Months, NaiveDate, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use tracing::{instrument, trace};

use crate::{
    router::serde_qs_config,
    types::{
        event::EventKind,
        pagination::{Pagination, ToRawQuery},
    },
    validation::{
        MAX_ITEMS, MAX_LEN_DATE, MAX_LEN_M, MAX_LEN_SORT_KEY, MAX_PAGINATION_LIMIT,
        trimmed_non_empty_opt, valid_latitude, valid_longitude,
    },
};

#[cfg(test)]
mod tests;

/// Filter parameters for event searches.
///
/// This struct captures all possible filtering criteria for events including
/// location-based filters (bounding box, distance), temporal filters (date range),
/// categorical filters, etc.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct SearchEventsFilters {
    /// Alliance names to filter by.
    #[serde(default)]
    #[garde(length(max = MAX_ITEMS), inner(length(max = MAX_LEN_M)))]
    pub alliance: Vec<String>,
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
    /// Start date for event filtering (YYYY-MM-DD format).
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DATE))]
    pub date_from: Option<String>,
    /// End date for event filtering (YYYY-MM-DD format).
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DATE))]
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
    /// Create a new `SearchEventsFilters` instance from the raw query string and headers.
    #[instrument(err)]
    pub(crate) fn new(headers: &HeaderMap, raw_query: &str) -> Result<Self, FilterError> {
        let mut filters: SearchEventsFilters = serde_qs_config().deserialize_str(raw_query)?;
        filters.validate()?;

        // Clean up entries that are empty strings
        filters.event_category.retain(|c| !c.is_empty());
        filters.group.retain(|g| !g.is_empty());
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
        if filters.view_mode == Some(ViewMode::Calendar) || filters.view_mode == Some(ViewMode::Map)
        {
            filters.limit = Some(100);
            filters.offset = Some(0);
        }

        // Set some defaults when the view mode is map
        if filters.view_mode == Some(ViewMode::Map) {
            filters.include_bbox = Some(true);
        }

        trace!(?filters);
        Ok(filters)
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
    /// Alliance names to filter by.
    #[serde(default)]
    #[garde(length(max = MAX_ITEMS), inner(length(max = MAX_LEN_M)))]
    pub alliance: Vec<String>,
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
    /// Create a new `SearchGroupsFilters` instance from the raw query string and headers
    /// provided.
    #[instrument(err)]
    pub(crate) fn new(headers: &HeaderMap, raw_query: &str) -> Result<Self, FilterError> {
        let mut filters: SearchGroupsFilters = serde_qs_config().deserialize_str(raw_query)?;
        filters.validate()?;

        // Clean up entries that are empty strings
        filters.group_category.retain(|c| !c.is_empty());
        filters.region.retain(|r| !r.is_empty());

        // Populate the latitude and longitude fields from the headers provided
        (filters.latitude, filters.longitude) = extract_location(headers);

        // Set some defaults when the view mode is calendar or map
        if filters.view_mode == Some(ViewMode::Calendar) || filters.view_mode == Some(ViewMode::Map)
        {
            filters.limit = Some(100);
            filters.offset = Some(0);
        }

        // Set some defaults when the view mode is map
        if filters.view_mode == Some(ViewMode::Map) {
            filters.include_bbox = Some(true);
        }

        trace!(?filters);
        Ok(filters)
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

// Helpers.

/// Extract geolocation coordinates from request headers.
fn extract_location(headers: &HeaderMap) -> (Option<f64>, Option<f64>) {
    let try_from =
        |latitude_header: &str, longitude_header: &str| -> Option<(Option<f64>, Option<f64>)> {
            let latitude = headers.get(latitude_header)?.to_str().ok()?.parse().ok()?;
            let longitude = headers.get(longitude_header)?.to_str().ok()?.parse().ok()?;
            Some((Some(latitude), Some(longitude)))
        };

    if let Some(coordinates) = try_from("CloudFront-Viewer-Latitude", "CloudFront-Viewer-Longitude")
    {
        return coordinates;
    }

    (None, None)
}
