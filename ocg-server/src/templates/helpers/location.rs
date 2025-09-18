//!/ Helpers for formatting and extracting location information.

use axum::http::HeaderMap;

/// Constructs a formatted location string from available parts.
///
/// Combines location components, preferring venue details over group defaults. Respects
/// the maximum length constraint and gracefully handles missing information. Returns
/// None if no location data is available.
pub(crate) fn build_location(parts: &LocationParts, max_len: usize) -> Option<String> {
    let mut location = String::new();

    // Helper to push location parts to the final location string.
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

    // Attempt to add parts in the order we'd like them to appear.
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

// Tests.

#[cfg(test)]
mod tests {
    use axum::http::{HeaderMap, HeaderValue};

    use super::*;

    #[test]
    fn test_build_location_1() {
        let group_country = "group country".to_string();
        let group_state = "group state".to_string();
        let venue_address = "venue address".to_string();
        let venue_city = "venue city".to_string();
        let venue_name = "venue name".to_string();

        let parts = LocationParts::new()
            .group_country_name(Some(&group_country))
            .group_state(Some(&group_state))
            .venue_address(Some(&venue_address))
            .venue_city(Some(&venue_city))
            .venue_name(Some(&venue_name));

        assert_eq!(
            build_location(&parts, 100),
            Some("venue name, venue address, venue city, group state, group country".to_string())
        );
    }

    #[test]
    fn test_build_location_2() {
        let group_city = "group city".to_string();
        let group_country = "group country".to_string();
        let group_country_code = "group country code".to_string();
        let group_state = "group state".to_string();
        let venue_address = "venue address".to_string();
        let venue_city = "venue city".to_string();

        let parts = LocationParts::new()
            .group_city(Some(&group_city))
            .group_country_code(Some(&group_country_code))
            .group_country_name(Some(&group_country))
            .group_state(Some(&group_state))
            .venue_address(Some(&venue_address))
            .venue_city(Some(&venue_city));

        assert_eq!(
            build_location(&parts, 100),
            Some("venue address, venue city, group state, group country".to_string())
        );
    }

    #[test]
    fn test_build_location_3() {
        let group_city = "group city".to_string();
        let group_country = "group country".to_string();
        let group_country_code = "group country code".to_string();
        let group_state = "group state".to_string();
        let venue_city = "venue city".to_string();

        let parts = LocationParts::new()
            .group_city(Some(&group_city))
            .group_country_code(Some(&group_country_code))
            .group_country_name(Some(&group_country))
            .group_state(Some(&group_state))
            .venue_city(Some(&venue_city));

        assert_eq!(
            build_location(&parts, 100),
            Some("venue city, group state, group country".to_string())
        );
    }

    #[test]
    fn test_build_location_4() {
        let group_city = "group city".to_string();
        let group_country = "group country".to_string();
        let group_country_code = "group country code".to_string();
        let group_state = "group state".to_string();

        let parts = LocationParts::new()
            .group_city(Some(&group_city))
            .group_country_code(Some(&group_country_code))
            .group_country_name(Some(&group_country))
            .group_state(Some(&group_state));

        assert_eq!(
            build_location(&parts, 100),
            Some("group city, group state, group country".to_string())
        );
    }

    #[test]
    fn test_build_location_5() {
        let group_country = "group country".to_string();
        let group_country_code = "group country code".to_string();
        let group_state = "group state".to_string();

        let parts = LocationParts::new()
            .group_country_code(Some(&group_country_code))
            .group_country_name(Some(&group_country))
            .group_state(Some(&group_state));

        assert_eq!(
            build_location(&parts, 100),
            Some("group state, group country".to_string())
        );
    }

    #[test]
    fn test_build_location_6() {
        let group_country = "group country".to_string();
        let group_country_code = "group country code".to_string();

        let parts = LocationParts::new()
            .group_country_code(Some(&group_country_code))
            .group_country_name(Some(&group_country));

        assert_eq!(build_location(&parts, 100), Some("group country".to_string()));
    }

    #[test]
    fn test_build_location_7() {
        let group_country_code = "group country code".to_string();

        let parts = LocationParts::new().group_country_code(Some(&group_country_code));

        assert_eq!(
            build_location(&parts, 100),
            Some("group country code".to_string())
        );
    }

    #[test]
    fn test_build_location_8() {
        let parts = LocationParts::new();

        assert_eq!(build_location(&parts, 100), None);
    }

    #[test]
    fn test_build_location_9() {
        let venue_name = "very long venue name".to_string();

        let parts = LocationParts::new().venue_name(Some(&venue_name));

        assert_eq!(build_location(&parts, 5), None);
    }

    #[test]
    fn test_build_location_10() {
        let venue_address = "very long street name".to_string();
        let venue_city = "city".to_string();
        let venue_name = "venue".to_string();

        let parts = LocationParts::new()
            .venue_address(Some(&venue_address))
            .venue_city(Some(&venue_city))
            .venue_name(Some(&venue_name));

        assert_eq!(build_location(&parts, 12), Some("venue, city".to_string()));
    }

    #[test]
    fn test_extract_location_1() {
        let mut headers = HeaderMap::new();
        headers.insert("CloudFront-Viewer-Latitude", HeaderValue::from_static("10.123"));
        headers.insert("CloudFront-Viewer-Longitude", HeaderValue::from_static("-20.456"));

        let (latitude, longitude) = extract_location(&headers);

        assert_eq!(latitude, Some(10.123));
        assert_eq!(longitude, Some(-20.456));
    }

    #[test]
    fn test_extract_location_2() {
        let headers = HeaderMap::new();

        let (latitude, longitude) = extract_location(&headers);

        assert_eq!(latitude, None);
        assert_eq!(longitude, None);
    }

    #[test]
    fn test_extract_location_3() {
        let mut headers = HeaderMap::new();
        headers.insert("CloudFront-Viewer-Latitude", HeaderValue::from_static("invalid"));
        headers.insert("CloudFront-Viewer-Longitude", HeaderValue::from_static("10.0"));

        let (latitude, longitude) = extract_location(&headers);

        assert_eq!(latitude, None);
        assert_eq!(longitude, None);
    }
}
