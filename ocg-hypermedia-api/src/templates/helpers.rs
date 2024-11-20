//! Some helpers for handlers.

use axum::http::header::HeaderMap;

/// Parts used to build the location string.
pub(crate) struct LocationParts<'a> {
    group_city: &'a Option<String>,
    group_country_code: &'a Option<String>,
    group_country_name: &'a Option<String>,
    group_state: &'a Option<String>,
    venue_address: &'a Option<String>,
    venue_city: &'a Option<String>,
    venue_name: &'a Option<String>,
}

impl<'a> LocationParts<'a> {
    /// Create a new instance of `LocationParts`.
    pub(crate) fn new() -> Self {
        Self {
            group_city: &None,
            group_country_code: &None,
            group_country_name: &None,
            group_state: &None,
            venue_address: &None,
            venue_city: &None,
            venue_name: &None,
        }
    }

    /// Set the group city.
    pub(crate) fn group_city(mut self, group_city: &'a Option<String>) -> Self {
        self.group_city = group_city;
        self
    }

    /// Set the group country code.
    pub(crate) fn group_country_code(mut self, group_country_code: &'a Option<String>) -> Self {
        self.group_country_code = group_country_code;
        self
    }

    /// Set the group country name.
    pub(crate) fn group_country_name(mut self, group_country_name: &'a Option<String>) -> Self {
        self.group_country_name = group_country_name;
        self
    }

    /// Set the group state.
    pub(crate) fn group_state(mut self, group_state: &'a Option<String>) -> Self {
        self.group_state = group_state;
        self
    }

    /// Set the venue address.
    pub(crate) fn venue_address(mut self, venue_address: &'a Option<String>) -> Self {
        self.venue_address = venue_address;
        self
    }

    /// Set the venue city.
    pub(crate) fn venue_city(mut self, venue_city: &'a Option<String>) -> Self {
        self.venue_city = venue_city;
        self
    }

    /// Set the venue name.
    pub(crate) fn venue_name(mut self, venue_name: &'a Option<String>) -> Self {
        self.venue_name = venue_name;
        self
    }
}

/// Build location string from the location information provided.
pub(crate) fn build_location(max_len: usize, parts: &LocationParts) -> Option<String> {
    let mut location = String::new();
    let mut push = |part: &Option<String>| -> bool {
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

/// Extract the latitude and longitude from the headers provided.
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
    use super::{build_location, LocationParts};

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
                assert_eq!(build_location(100, $parts), $expected_location);
            }
        )*
        }
    }

    build_location_tests! {
        build_location_1: {
            parts: &LocationParts::new()
                .group_country_name(&Some("group country".to_string()))
                .group_state(&Some("group state".to_string()))
                .venue_name(&Some("venue name".to_string()))
                .venue_address(&Some("venue address".to_string()))
                .venue_city(&Some("venue city".to_string())),
            expected_location: Some("venue name, venue address, venue city, group state, group country".to_string())
        },

        build_location_2: {
            parts: &LocationParts::new()
                .group_city(&Some("group city".to_string()))
                .group_country_code(&Some("group country code".to_string()))
                .group_country_name(&Some("group country".to_string()))
                .group_state(&Some("group state".to_string()))
                .venue_address(&Some("venue address".to_string()))
                .venue_city(&Some("venue city".to_string())),
            expected_location: Some("venue address, venue city, group state, group country".to_string())
        },

        build_location_3: {
            parts: &LocationParts::new()
                .group_city(&Some("group city".to_string()))
                .group_country_code(&Some("group country code".to_string()))
                .group_country_name(&Some("group country".to_string()))
                .group_state(&Some("group state".to_string()))
                .venue_city(&Some("venue city".to_string())),
            expected_location: Some("venue city, group state, group country".to_string())
        },

        build_location_4: {
            parts: &LocationParts::new()
                .group_city(&Some("group city".to_string()))
                .group_country_code(&Some("group country code".to_string()))
                .group_country_name(&Some("group country".to_string()))
                .group_state(&Some("group state".to_string())),
            expected_location: Some("group city, group state, group country".to_string())
        },

        build_location_5: {
            parts: &LocationParts::new()
                .group_country_code(&Some("group country code".to_string()))
                .group_country_name(&Some("group country".to_string()))
                .group_state(&Some("group state".to_string())),
            expected_location: Some("group state, group country".to_string())
        },

        build_location_6: {
            parts: &LocationParts::new()
                .group_country_code(&Some("group country code".to_string()))
                .group_country_name(&Some("group country".to_string())),
            expected_location: Some("group country".to_string())
        },

        build_location_7: {
            parts: &LocationParts::new()
                .group_country_code(&Some("group country code".to_string())),
            expected_location: Some("group country code".to_string())
        },

        build_location_8: {
            parts: &LocationParts::new(),
            expected_location: None
        },
    }
}
