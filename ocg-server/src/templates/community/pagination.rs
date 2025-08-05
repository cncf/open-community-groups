//! Pagination-related types and helpers for the explore page of the community site.

use std::fmt::Write as _;

use anyhow::Result;
use askama::Template;
use serde::{Deserialize, Serialize};

use super::explore::Entity;

/// Default pagination limit.
const DEFAULT_PAGINATION_LIMIT: usize = 10;

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
