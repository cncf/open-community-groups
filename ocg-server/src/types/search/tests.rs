use axum::http::HeaderValue;

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
    let filters =
        SearchEventsFilters::new(&HeaderMap::new(), &raw_query).expect("filters to be created");

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
    headers.insert(
        "CloudFront-Viewer-Latitude",
        HeaderValue::from_static("51.5"),
    );
    headers.insert(
        "CloudFront-Viewer-Longitude",
        HeaderValue::from_static("-0.12"),
    );

    // Create filters
    let filters =
        SearchEventsFilters::new(&headers, "view_mode=list").expect("filters to be created");

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
    let filters = SearchEventsFilters::new(&HeaderMap::new(), "view_mode=list")
        .expect("filters to be created");

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
    let filters = SearchEventsFilters::new(&HeaderMap::new(), "view_mode=calendar")
        .expect("filters to be created");

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
    let filters = SearchEventsFilters::new(
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
    let filters =
        SearchEventsFilters::new(&HeaderMap::new(), &raw_query).expect("filters to be created");

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
    let filters = SearchEventsFilters {
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
    let filters = SearchEventsFilters {
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
fn test_events_filters_uses_viewer_location_for_distance_searches() {
    // Prepare headers
    let mut headers = HeaderMap::new();
    headers.insert(
        "CloudFront-Viewer-Latitude",
        HeaderValue::from_static("51.5"),
    );
    headers.insert(
        "CloudFront-Viewer-Longitude",
        HeaderValue::from_static("-0.12"),
    );

    // Create filters
    let default_filters = SearchEventsFilters::new(&headers, "").expect("filters to be created");
    let distance_filter_filters =
        SearchEventsFilters::new(&headers, "distance=25000").expect("filters to be created");
    let distance_sort_filters =
        SearchEventsFilters::new(&headers, "sort_by=distance").expect("filters to be created");

    // Check filters match expected values
    assert!(!default_filters.uses_viewer_location());
    assert!(distance_filter_filters.uses_viewer_location());
    assert!(distance_sort_filters.uses_viewer_location());
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
    let filters =
        SearchGroupsFilters::new(&HeaderMap::new(), &raw_query).expect("filters to be created");

    // Check filters match expected values
    assert_eq!(filters.group_category, vec!["rust".to_string()]);
    assert_eq!(filters.region, vec!["europe".to_string()]);
    assert_eq!(filters.view_mode, Some(ViewMode::List));
}

#[test]
fn test_groups_filters_new_list_ignores_empty_scalar_vec_filters() {
    let raw_query = [
        "alliance[0]=goup",
        "group_category=",
        "region=",
        "limit=10",
        "offset=0",
    ]
    .join("&");

    let filters =
        SearchGroupsFilters::new(&HeaderMap::new(), &raw_query).expect("filters to be created");

    assert_eq!(filters.alliance, vec!["goup".to_string()]);
    assert!(filters.group_category.is_empty());
    assert!(filters.region.is_empty());
    assert_eq!(filters.limit, Some(10));
    assert_eq!(filters.offset, Some(0));
}

#[test]
fn test_groups_filters_new_list_extracts_location_from_headers() {
    // Prepare headers and raw query
    let mut headers = HeaderMap::new();
    headers.insert(
        "CloudFront-Viewer-Latitude",
        HeaderValue::from_static("51.5"),
    );
    headers.insert(
        "CloudFront-Viewer-Longitude",
        HeaderValue::from_static("-0.12"),
    );

    // Create filters
    let filters =
        SearchGroupsFilters::new(&headers, "view_mode=list").expect("filters to be created");

    // Check filters match expected values
    assert_eq!(filters.latitude, Some(51.5));
    assert_eq!(filters.longitude, Some(-0.12));
    assert_eq!(filters.view_mode, Some(ViewMode::List));
}

#[test]
fn test_groups_filters_new_calendar_sets_pagination_defaults() {
    // Create filters
    let filters = SearchGroupsFilters::new(&HeaderMap::new(), "view_mode=calendar")
        .expect("filters to be created");

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
    let filters =
        SearchGroupsFilters::new(&HeaderMap::new(), &raw_query).expect("filters to be created");

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
    let filters = SearchGroupsFilters {
        distance: Some(25.5),
        group_category: vec!["rust".to_string()],
        include_bbox: Some(false),
        latitude: Some(51.5),
        limit: Some(40),
        longitude: Some(-0.12),
        offset: Some(15),
        region: vec!["europe".to_string()],
        sort_by: Some("distance".to_string()),
        ts_query: Some("alliance".to_string()),
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
    assert!(query.contains("ts_query=alliance"));
    assert!(query.contains("view_mode=list"));
    assert!(!query.contains("latitude"));
    assert!(!query.contains("longitude"));
}

#[test]
fn test_groups_filters_to_raw_query_resets_default_values() {
    // Prepare filters
    let filters = SearchGroupsFilters {
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

#[test]
fn test_groups_filters_uses_viewer_location_for_distance_searches() {
    // Prepare headers
    let mut headers = HeaderMap::new();
    headers.insert(
        "CloudFront-Viewer-Latitude",
        HeaderValue::from_static("51.5"),
    );
    headers.insert(
        "CloudFront-Viewer-Longitude",
        HeaderValue::from_static("-0.12"),
    );

    // Create filters
    let default_filters = SearchGroupsFilters::new(&headers, "").expect("filters to be created");
    let distance_filter_filters =
        SearchGroupsFilters::new(&headers, "distance=25000").expect("filters to be created");
    let distance_sort_filters =
        SearchGroupsFilters::new(&headers, "sort_by=distance").expect("filters to be created");

    // Check filters match expected values
    assert!(!default_filters.uses_viewer_location());
    assert!(distance_filter_filters.uses_viewer_location());
    assert!(distance_sort_filters.uses_viewer_location());
}

#[test]
fn test_extract_location_valid_headers() {
    let mut headers = HeaderMap::new();
    headers.insert(
        "CloudFront-Viewer-Latitude",
        HeaderValue::from_static("10.123"),
    );
    headers.insert(
        "CloudFront-Viewer-Longitude",
        HeaderValue::from_static("-20.456"),
    );

    let (latitude, longitude) = extract_location(&headers);

    assert_eq!(latitude, Some(10.123));
    assert_eq!(longitude, Some(-20.456));
}

#[test]
fn test_extract_location_missing_headers() {
    let headers = HeaderMap::new();

    let (latitude, longitude) = extract_location(&headers);

    assert_eq!(latitude, None);
    assert_eq!(longitude, None);
}

#[test]
fn test_extract_location_invalid_values() {
    let mut headers = HeaderMap::new();
    headers.insert(
        "CloudFront-Viewer-Latitude",
        HeaderValue::from_static("invalid"),
    );
    headers.insert(
        "CloudFront-Viewer-Longitude",
        HeaderValue::from_static("10.0"),
    );

    let (latitude, longitude) = extract_location(&headers);

    assert_eq!(latitude, None);
    assert_eq!(longitude, None);
}
