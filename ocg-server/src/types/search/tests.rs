use chrono::TimeZone;

use super::*;

#[test]
fn test_events_filters_normalize_calendar_sets_month_date_range() {
    // Setup calendar filters without date bounds
    let mut filters = SearchEventsFilters {
        view_mode: Some(ViewMode::Calendar),
        ..Default::default()
    };

    // Normalize filters in the last month of the year
    filters.normalize(sample_now(2031, 12, 15));

    // Check the range covers the whole month
    assert_eq!(filters.date_from, NaiveDate::from_ymd_opt(2031, 12, 1));
    assert_eq!(filters.date_to, NaiveDate::from_ymd_opt(2031, 12, 31));
}

#[test]
fn test_events_filters_normalize_drops_empty_entries() {
    // Setup filters with empty entries
    let mut filters = SearchEventsFilters {
        event_category: vec![String::new(), "conference".to_string()],
        group: vec![String::new(), "rust-madrid".to_string()],
        group_category: vec![String::new(), "rust".to_string()],
        region: vec![String::new(), "europe".to_string()],
        view_mode: Some(ViewMode::List),
        ..Default::default()
    };

    // Normalize filters
    filters.normalize(sample_now(2031, 1, 15));

    // Check empty entries were dropped
    assert_eq!(filters.event_category, vec!["conference".to_string()]);
    assert_eq!(filters.group, vec!["rust-madrid".to_string()]);
    assert_eq!(filters.group_category, vec!["rust".to_string()]);
    assert_eq!(filters.region, vec!["europe".to_string()]);
}

#[test]
fn test_events_filters_normalize_list_keeps_provided_date_range() {
    // Setup list filters with date bounds
    let mut filters = SearchEventsFilters {
        date_from: NaiveDate::from_ymd_opt(2031, 1, 15),
        date_to: NaiveDate::from_ymd_opt(2031, 2, 20),
        view_mode: Some(ViewMode::List),
        ..Default::default()
    };

    // Normalize filters
    filters.normalize(sample_now(2030, 6, 1));

    // Check the provided range was kept
    assert_eq!(filters.date_from, NaiveDate::from_ymd_opt(2031, 1, 15));
    assert_eq!(filters.date_to, NaiveDate::from_ymd_opt(2031, 2, 20));
}

#[test]
fn test_events_filters_normalize_list_sets_default_date_range() {
    // Setup list filters without date bounds
    let mut filters = SearchEventsFilters {
        view_mode: Some(ViewMode::List),
        ..Default::default()
    };

    // Normalize filters
    filters.normalize(sample_now(2031, 1, 31));

    // Check the range starts today and spans twelve months
    assert_eq!(filters.date_from, NaiveDate::from_ymd_opt(2031, 1, 31));
    assert_eq!(filters.date_to, NaiveDate::from_ymd_opt(2032, 1, 31));
}

#[test]
fn test_events_filters_parse_legacy_include_bbox() {
    // Parse a bookmarked query string that still carries the removed key
    let filters: SearchEventsFilters =
        serde_qs::from_str("include_bbox=true&view_mode=map").expect("filters to be parsed");

    // Check the legacy key is ignored
    assert_eq!(filters.view_mode, Some(ViewMode::Map));
}

#[test]
fn test_events_filters_to_raw_query_preserves_custom_values() {
    // Prepare filters
    let filters = SearchEventsFilters {
        date_from: NaiveDate::from_ymd_opt(2030, 1, 1),
        date_to: NaiveDate::from_ymd_opt(2030, 6, 1),
        event_category: vec!["conference".to_string()],
        kind: vec![EventKind::Hybrid],
        latitude: Some(51.5),
        limit: Some(40),
        longitude: Some(-0.12),
        offset: Some(15),
        sort_by: Some("distance".to_string()),
        sort_direction: Some("desc".to_string()),
        ts_query: Some("rust".to_string()),
        view_mode: Some(ViewMode::List),
        ..Default::default()
    };

    // Generate raw query
    let query = filters.to_raw_query().expect("raw query to be generated");

    // Check custom values are kept and the viewer location is dropped
    assert!(query.contains("date_from=2030-01-01"));
    assert!(query.contains("date_to=2030-06-01"));
    assert!(query.contains("event_category[0]=conference"));
    assert!(query.contains("kind[0]=hybrid"));
    assert!(query.contains("limit=40"));
    assert!(query.contains("offset=15"));
    assert!(query.contains("sort_by=distance"));
    assert!(query.contains("sort_direction=desc"));
    assert!(query.contains("ts_query=rust"));
    assert!(query.contains("view_mode=list"));
    assert!(!query.contains("latitude"));
    assert!(!query.contains("longitude"));
}

#[test]
fn test_events_filters_to_raw_query_resets_default_values() {
    // Generate the raw query of filters using the default dates and sorting
    let query = with_stable_today(|today| {
        let filters = SearchEventsFilters {
            date_from: Some(today),
            date_to: today.checked_add_months(Months::new(12)),
            event_category: vec!["meetup".to_string()],
            limit: Some(20),
            sort_by: Some("date".to_string()),
            sort_direction: Some("asc".to_string()),
            view_mode: Some(ViewMode::List),
            ..Default::default()
        };
        filters.to_raw_query().expect("raw query to be generated")
    });

    // Check only the non-default values remain
    assert!(query.contains("event_category[0]=meetup"));
    assert!(query.contains("limit=20"));
    assert!(query.contains("view_mode=list"));
    assert!(!query.contains("date_from"));
    assert!(!query.contains("date_to"));
    assert!(!query.contains("sort_by"));
    assert!(!query.contains("sort_direction"));
}

#[test]
fn test_events_filters_uses_viewer_location_for_distance_searches() {
    // Setup filters with a viewer location
    let default_filters = SearchEventsFilters {
        latitude: Some(51.5),
        longitude: Some(-0.12),
        ..Default::default()
    };
    let distance_filter_filters = SearchEventsFilters {
        distance: Some(25000),
        ..default_filters.clone()
    };
    let distance_sort_filters = SearchEventsFilters {
        sort_by: Some("distance".to_string()),
        ..default_filters.clone()
    };
    let no_location_filters = SearchEventsFilters {
        distance: Some(25000),
        sort_by: Some("distance".to_string()),
        ..Default::default()
    };

    // Check only location sensitive searches with a location use it
    assert!(!default_filters.uses_viewer_location());
    assert!(distance_filter_filters.uses_viewer_location());
    assert!(distance_sort_filters.uses_viewer_location());
    assert!(!no_location_filters.uses_viewer_location());
}

#[test]
fn test_groups_filters_normalize_drops_empty_entries() {
    // Setup filters with empty entries
    let mut filters = SearchGroupsFilters {
        group_category: vec![String::new(), "rust".to_string()],
        region: vec![String::new(), "europe".to_string()],
        view_mode: Some(ViewMode::List),
        ..Default::default()
    };

    // Normalize filters
    filters.normalize();

    // Check empty entries were dropped
    assert_eq!(filters.group_category, vec!["rust".to_string()]);
    assert_eq!(filters.region, vec!["europe".to_string()]);
}

#[test]
fn test_groups_filters_parse_legacy_include_bbox() {
    // Parse a bookmarked query string that still carries the removed key
    let filters: SearchGroupsFilters =
        serde_qs::from_str("include_bbox=true&view_mode=map").expect("filters to be parsed");

    // Check the legacy key is ignored
    assert_eq!(filters.view_mode, Some(ViewMode::Map));
}

#[test]
fn test_groups_filters_to_raw_query_keeps_custom_values_and_drops_defaults() {
    // Prepare filters with custom values, the viewer location and the default sorting
    let filters = SearchGroupsFilters {
        distance: Some(25.5),
        group_category: vec!["rust".to_string()],
        latitude: Some(51.5),
        limit: Some(40),
        longitude: Some(-0.12),
        offset: Some(15),
        region: vec!["europe".to_string()],
        sort_by: Some("date".to_string()),
        ts_query: Some("community".to_string()),
        view_mode: Some(ViewMode::List),
        ..Default::default()
    };
    let distance_sorted = SearchGroupsFilters {
        sort_by: Some("distance".to_string()),
        ..filters.clone()
    };

    // Generate raw queries
    let query = filters.to_raw_query().expect("raw query to be generated");
    let distance_sorted_query = distance_sorted.to_raw_query().expect("raw query to be generated");

    // Check custom values are kept (serde_qs uses bracket notation for arrays)
    assert!(query.contains("distance=25.5"));
    assert!(query.contains("group_category[0]=rust"));
    assert!(query.contains("limit=40"));
    assert!(query.contains("offset=15"));
    assert!(query.contains("region[0]=europe"));
    assert!(query.contains("ts_query=community"));
    assert!(query.contains("view_mode=list"));
    assert!(distance_sorted_query.contains("sort_by=distance"));

    // Check the viewer location and the default sorting are dropped
    assert!(!query.contains("latitude"));
    assert!(!query.contains("longitude"));
    assert!(!query.contains("sort_by"));
}

#[test]
fn test_groups_filters_uses_viewer_location_for_distance_searches() {
    // Setup filters with a viewer location
    let default_filters = SearchGroupsFilters {
        latitude: Some(51.5),
        longitude: Some(-0.12),
        ..Default::default()
    };
    let distance_filter_filters = SearchGroupsFilters {
        distance: Some(25000.0),
        ..default_filters.clone()
    };
    let distance_sort_filters = SearchGroupsFilters {
        sort_by: Some("distance".to_string()),
        ..default_filters.clone()
    };
    let no_location_filters = SearchGroupsFilters {
        distance: Some(25000.0),
        sort_by: Some("distance".to_string()),
        ..Default::default()
    };

    // Check only location sensitive searches with a location use it
    assert!(!default_filters.uses_viewer_location());
    assert!(distance_filter_filters.uses_viewer_location());
    assert!(distance_sort_filters.uses_viewer_location());
    assert!(!no_location_filters.uses_viewer_location());
}

// Helpers.

/// Runs `f` with today's UTC date, retrying if the date changes meanwhile.
fn with_stable_today<T>(f: impl Fn(NaiveDate) -> T) -> T {
    loop {
        let today = Utc::now().date_naive();
        let result = f(today);
        if Utc::now().date_naive() == today {
            return result;
        }
    }
}

/// Returns a fixed noon UTC instant for the given date.
fn sample_now(year: i32, month: u32, day: u32) -> DateTime<Utc> {
    Utc.with_ymd_and_hms(year, month, day, 12, 0, 0)
        .single()
        .expect("valid instant")
}
