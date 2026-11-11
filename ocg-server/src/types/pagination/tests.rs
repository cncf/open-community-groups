use serde::Serialize;

use super::{
    NavigationLinks, NavigationLinksOffsets, Pagination, ToRawQuery, get_url_filters_separator,
    page_position,
};

const TEST_PAGINATION_LIMIT: usize = 10;

#[test]
fn test_clamp_offset_to_last_page_moves_offset_to_last_page() {
    // (case, offset, total, clamped, expected offset)
    let cases = [
        ("empty results keep the offset", 10, 0, false, 10),
        ("offset within results is kept", 10, 11, false, 10),
        ("offset past a full last page moves", 20, 20, true, 10),
        ("offset past a partial last page moves", 30, 15, true, 10),
        ("unaligned offset moves to the page start", 12, 12, true, 10),
    ];
    for (case, offset, total, clamped, expected_offset) in cases {
        let mut filters = test_filters(Some(offset));

        assert_eq!(filters.clamp_offset_to_last_page(total), clamped, "{case}");
        assert_eq!(filters.offset, Some(expected_offset), "{case}");
    }
}

#[test]
fn test_navigation_links_default_is_first_of_one_page() {
    let links = NavigationLinks::default();

    assert_eq!(links.current_page, 1);
    assert_eq!(links.total_pages, 1);
    assert!(links.first.is_none());
    assert!(links.last.is_none());
    assert!(links.next.is_none());
    assert!(links.prev.is_none());
}

#[test]
fn test_navigation_links_from_filters_sets_page_position() {
    // (case, offset, total, current page, total pages)
    let cases = [
        ("first page", None, 25, 1, 3),
        ("middle page", Some(10), 25, 2, 3),
        ("offset past the end", Some(40), 25, 3, 3),
        ("no results", Some(0), 0, 1, 1),
    ];
    for (case, offset, total, current_page, total_pages) in cases {
        // Build the links for the filters
        let filters = test_filters(offset);
        let links =
            NavigationLinks::from_filters(&filters, total, "/explore", "/explore/results").unwrap();

        // Check the reported position
        assert_eq!(links.current_page, current_page, "{case}");
        assert_eq!(links.total_pages, total_pages, "{case}");
    }
}

#[test]
fn test_navigation_links_offsets_cover_page_positions() {
    // (case, offset, total, first, last, next, prev)
    let cases = [
        (
            "first of two full pages",
            Some(0),
            20,
            None,
            Some(10),
            Some(10),
            None,
        ),
        (
            "last of two full pages",
            Some(10),
            20,
            Some(0),
            None,
            None,
            Some(0),
        ),
        (
            "first page with a partial last page",
            Some(0),
            21,
            None,
            Some(20),
            Some(10),
            None,
        ),
        (
            "partial last page",
            Some(10),
            15,
            Some(0),
            None,
            None,
            Some(0),
        ),
        ("single full page", Some(0), 10, None, None, None, None),
        ("single partial page", Some(0), 5, None, None, None, None),
        ("no results", Some(0), 0, None, None, None, None),
        (
            "missing offset defaults to first page",
            None,
            15,
            None,
            Some(10),
            Some(10),
            None,
        ),
        (
            "middle page",
            Some(20),
            50,
            Some(0),
            Some(40),
            Some(30),
            Some(10),
        ),
        (
            "unaligned offset",
            Some(2),
            20,
            Some(0),
            Some(10),
            Some(12),
            Some(0),
        ),
        (
            "one result past a full page",
            Some(0),
            11,
            None,
            Some(10),
            Some(10),
            None,
        ),
    ];

    for (case, offset, total, first, last, next, prev) in cases {
        assert_eq!(
            NavigationLinksOffsets::new(offset, TEST_PAGINATION_LIMIT, total),
            NavigationLinksOffsets {
                first,
                last,
                next,
                prev,
            },
            "{case}"
        );
    }
}

#[test]
fn test_get_url_filters_separator_matches_query_state() {
    let cases = [
        ("no query string", "https://example.com", "?"),
        ("empty query string", "https://example.com?", ""),
        (
            "query with parameters",
            "https://example.com?param1=value1",
            "&",
        ),
        (
            "query ending with ampersand",
            "https://example.com?param1=value1&",
            "",
        ),
    ];

    for (case, url, expected) in cases {
        assert_eq!(get_url_filters_separator(url), expected, "{case}");
    }
}

#[test]
fn test_page_position_covers_result_positions() {
    // (case, offset, limit, total, current page, total pages)
    let cases = [
        ("first of three pages", Some(0), 10, 30, 1, 3),
        ("middle page", Some(10), 10, 30, 2, 3),
        ("partial last page", Some(20), 10, 25, 3, 3),
        ("unaligned offset", Some(12), 10, 30, 2, 3),
        ("offset past the end clamps", Some(50), 10, 25, 3, 3),
        ("no results gives one of one", Some(0), 10, 0, 1, 1),
        ("missing offset", None, 10, 25, 1, 3),
        ("limit zero gives one of one", Some(10), 0, 25, 1, 1),
    ];

    for (case, offset, limit, total, current_page, total_pages) in cases {
        assert_eq!(
            page_position(offset, limit, total),
            (current_page, total_pages),
            "{case}"
        );
    }
}

// Helpers.

/// Minimal paginated filters used to exercise the `Pagination` defaults.
#[derive(Clone, Serialize)]
struct TestFilters {
    /// Number of results per page.
    limit: Option<usize>,
    /// Pagination offset for results.
    offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(TestFilters, limit, offset);

/// Builds test filters with the default test page size and the given offset.
fn test_filters(offset: Option<usize>) -> TestFilters {
    TestFilters {
        limit: Some(TEST_PAGINATION_LIMIT),
        offset,
    }
}
