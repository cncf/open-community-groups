//! Template helper functions and utilities.
//!
//! This module provides utility functions used by templates for common tasks like
//! building location strings, generating consistent colors for entities, and extracting
//! geolocation data from HTTP headers.

use std::hash::{DefaultHasher, Hash, Hasher};

use axum::http::header::HeaderMap;

/// Predefined color palette for visual entity identification.
///
/// These soft pastel colors are used to generate consistent visual identifiers for
/// entities like groups or events, particularly in placeholder images.
const COLORS: &[&str] = &["#FDC8B9", "#FBEDC1", "#D1E4C9", "#C4DAEE"];

/// The date format used in the templates for datetime-local inputs (YYYY-MM-DDTHH:MM).
pub(crate) const DATE_FORMAT: &str = "%Y-%m-%dT%H:%M";

/// Builder for constructing location strings from various components.
///
/// Provides a mechanism to combine venue and group location information into a
/// human-readable location string with proper formatting.
pub(crate) struct LocationParts<'a> {
    /// City where the group is located (used when venue city is not available).
    group_city: Option<&'a String>,
    /// ISO country code of the group's location (e.g., "US", "GB").
    group_country_code: Option<&'a String>,
    /// Full country name of the group's location.
    group_country_name: Option<&'a String>,
    /// State or province where the group is located.
    group_state: Option<&'a String>,
    /// Street address of the event venue.
    venue_address: Option<&'a String>,
    /// City where the venue is located (takes precedence over group city).
    venue_city: Option<&'a String>,
    /// Name of the venue (e.g., "Community Center", "Conference Hall").
    venue_name: Option<&'a String>,
}

impl<'a> LocationParts<'a> {
    /// Creates a new empty `LocationParts` builder.
    pub(crate) fn new() -> Self {
        Self {
            group_city: None,
            group_country_code: None,
            group_country_name: None,
            group_state: None,
            venue_address: None,
            venue_city: None,
            venue_name: None,
        }
    }

    /// Sets the group's city for the location string.
    pub(crate) fn group_city(mut self, group_city: Option<&'a String>) -> Self {
        self.group_city = group_city;
        self
    }

    /// Sets the group's country code (e.g., "US", "GB").
    pub(crate) fn group_country_code(mut self, group_country_code: Option<&'a String>) -> Self {
        self.group_country_code = group_country_code;
        self
    }

    /// Sets the group's full country name.
    pub(crate) fn group_country_name(mut self, group_country_name: Option<&'a String>) -> Self {
        self.group_country_name = group_country_name;
        self
    }

    /// Sets the group's state or province.
    pub(crate) fn group_state(mut self, group_state: Option<&'a String>) -> Self {
        self.group_state = group_state;
        self
    }

    /// Sets the specific venue street address.
    pub(crate) fn venue_address(mut self, venue_address: Option<&'a String>) -> Self {
        self.venue_address = venue_address;
        self
    }

    /// Sets the venue's city, which takes precedence over group city.
    pub(crate) fn venue_city(mut self, venue_city: Option<&'a String>) -> Self {
        self.venue_city = venue_city;
        self
    }

    /// Sets the venue name (e.g., "Community Center").
    pub(crate) fn venue_name(mut self, venue_name: Option<&'a String>) -> Self {
        self.venue_name = venue_name;
        self
    }
}

/// Constructs a formatted location string from available parts.
///
/// Combines location components, preferring venue details over group defaults. Respects
/// the maximum length constraint and gracefully handles missing information. Returns
/// None if no location data is available.
pub(crate) fn build_location(parts: &LocationParts, max_len: usize) -> Option<String> {
    let mut location = String::new();
    let mut push = |part: Option<&String>| -> bool {
        if let Some(part) = part {
            if location.len() + part.len() > max_len {
                return false;
            }
            if !location.is_empty() {
                location.push_str(", ");
            }
            location.push_str(part.as_str());
            return true;
        }
        false
    };

    push(parts.venue_name);
    push(parts.venue_address);
    if !push(parts.venue_city) {
        push(parts.group_city);
    }
    push(parts.group_state);
    if !push(parts.group_country_name) {
        push(parts.group_country_code);
    }

    if !location.is_empty() {
        return Some(location);
    }
    None
}

/// Returns a consistent color for any hashable value.
///
/// Uses a hash function to deterministically map values to colors from the predefined
/// palette. Ensures the same input always produces the same color, useful for visual
/// consistency across the application.
pub(crate) fn color<T: Hash + ?Sized>(value: &T) -> &str {
    // Calculate the hash of the value
    let mut hasher = DefaultHasher::new();
    value.hash(&mut hasher);
    let hash = hasher.finish();

    // Pick one of the colors based on the hash
    #[allow(clippy::cast_possible_truncation)]
    COLORS[(hash % COLORS.len() as u64) as usize]
}

/// Extracts geolocation coordinates from HTTP headers.
///
/// Currently supports `CloudFront` geolocation headers. Returns a tuple of (latitude,
/// longitude) as Options, with both None if location cannot be determined from the
/// headers.
pub(crate) fn extract_location(headers: &HeaderMap) -> (Option<f64>, Option<f64>) {
    let try_from = |latitude_header: &str, longitude_header: &str| -> Option<(Option<f64>, Option<f64>)> {
        let latitude = headers.get(latitude_header)?.to_str().ok()?.parse().ok()?;
        let longitude = headers.get(longitude_header)?.to_str().ok()?.parse().ok()?;
        Some((Some(latitude), Some(longitude)))
    };

    // Try from CloudFront geolocation headers
    if let Some(coordinates) = try_from("CloudFront-Viewer-Latitude", "CloudFront-Viewer-Longitude") {
        return coordinates;
    }

    (None, None)
}

#[cfg(test)]
mod tests {
    use super::{COLORS, LocationParts, build_location, color};

    macro_rules! build_location_tests {
        ($(
            $name:ident: {
                parts: $parts:expr,
                expected_location: $expected_location:expr
            }
        ,)*) => {
        $(
            #[test]
            fn $name() {
                assert_eq!(build_location($parts, 100), $expected_location);
            }
        )*
        }
    }

    build_location_tests! {
        test_build_location_1: {
            parts: &LocationParts::new()
                .group_country_name(Some("group country".to_string()).as_ref())
                .group_state(Some("group state".to_string()).as_ref())
                .venue_name(Some("venue name".to_string()).as_ref())
                .venue_address(Some("venue address".to_string()).as_ref())
                .venue_city(Some("venue city".to_string()).as_ref()),
            expected_location: Some("venue name, venue address, venue city, group state, group country".to_string())
        },

        test_build_location_2: {
            parts: &LocationParts::new()
                .group_city(Some("group city".to_string()).as_ref())
                .group_country_code(Some("group country code".to_string()).as_ref())
                .group_country_name(Some("group country".to_string()).as_ref())
                .group_state(Some("group state".to_string()).as_ref())
                .venue_address(Some("venue address".to_string()).as_ref())
                .venue_city(Some("venue city".to_string()).as_ref()),
            expected_location: Some("venue address, venue city, group state, group country".to_string())
        },

        test_build_location_3: {
            parts: &LocationParts::new()
                .group_city(Some("group city".to_string()).as_ref())
                .group_country_code(Some("group country code".to_string()).as_ref())
                .group_country_name(Some("group country".to_string()).as_ref())
                .group_state(Some("group state".to_string()).as_ref())
                .venue_city(Some("venue city".to_string()).as_ref()),
            expected_location: Some("venue city, group state, group country".to_string())
        },

        test_build_location_4: {
            parts: &LocationParts::new()
                .group_city(Some("group city".to_string()).as_ref())
                .group_country_code(Some("group country code".to_string()).as_ref())
                .group_country_name(Some("group country".to_string()).as_ref())
                .group_state(Some("group state".to_string()).as_ref()),
            expected_location: Some("group city, group state, group country".to_string())
        },

        test_build_location_5: {
            parts: &LocationParts::new()
                .group_country_code(Some("group country code".to_string()).as_ref())
                .group_country_name(Some("group country".to_string()).as_ref())
                .group_state(Some("group state".to_string()).as_ref()),
            expected_location: Some("group state, group country".to_string())
        },

        test_build_location_6: {
            parts: &LocationParts::new()
                .group_country_code(Some("group country code".to_string()).as_ref())
                .group_country_name(Some("group country".to_string()).as_ref()),
            expected_location: Some("group country".to_string())
        },

        test_build_location_7: {
            parts: &LocationParts::new()
                .group_country_code(Some("group country code".to_string()).as_ref()),
            expected_location: Some("group country code".to_string())
        },

        test_build_location_8: {
            parts: &LocationParts::new(),
            expected_location: None
        },
    }

    macro_rules! color_tests {
        ($(
            $name:ident: $value:expr => $expected:expr
        ),*) => {
            $(
                #[test]
                fn $name() {
                    assert_eq!(color($value), $expected);
                }
            )*
        };
    }

    color_tests! {
        test_color_1: "value2" => COLORS[0],
        test_color_2: "value1" => COLORS[1],
        test_color_3: "value3" => COLORS[2],
        test_color_4: "value5" => COLORS[3]
    }
}
