//! Shared location helpers used across the application.

/// Constructs a formatted location string from available parts.
///
/// Combines location components into a human-readable string. Respects the maximum length
/// constraint and gracefully handles missing information. Returns None if no location data
/// is available.
pub(crate) fn build_location(parts: &LocationParts, max_len: usize) -> Option<String> {
    let mut location = String::new();

    // Helper to push location parts to the final location string
    let mut push = |part: Option<&str>| -> bool {
        if let Some(part) = part {
            if location.len() + part.len() > max_len {
                return false;
            }
            if !location.is_empty() {
                location.push_str(", ");
            }
            location.push_str(part);
            return true;
        }
        false
    };

    // Attempt to add parts in the order we'd like them to appear
    push(parts.name);
    push(parts.address);
    push(parts.city);
    if !push(parts.state_name) {
        push(parts.state_code);
    }
    if !push(parts.country_name) {
        push(parts.country_code);
    }

    if !location.is_empty() {
        return Some(location);
    }
    None
}

/// Builder for constructing location strings from various components.
///
/// Provides a mechanism to combine location information into a human-readable location
/// string with proper formatting.
#[derive(Default)]
pub(crate) struct LocationParts<'a> {
    /// Street address.
    address: Option<&'a str>,
    /// City name.
    city: Option<&'a str>,
    /// ISO country code (e.g., "US", "GB").
    country_code: Option<&'a str>,
    /// Full country name.
    country_name: Option<&'a str>,
    /// Location name (e.g., "Community Center", "Conference Hall").
    name: Option<&'a str>,
    /// ISO state or province code.
    state_code: Option<&'a str>,
    /// Full state or province name.
    state_name: Option<&'a str>,
}

impl<'a> LocationParts<'a> {
    /// Creates a new empty `LocationParts` builder.
    pub(crate) fn new() -> Self {
        Self::default()
    }

    /// Sets the street address.
    pub(crate) fn address(mut self, address: Option<&'a str>) -> Self {
        self.address = address;
        self
    }

    /// Sets the city name.
    pub(crate) fn city(mut self, city: Option<&'a str>) -> Self {
        self.city = city;
        self
    }

    /// Sets the country code (e.g., "US", "GB").
    pub(crate) fn country_code(mut self, country_code: Option<&'a str>) -> Self {
        self.country_code = country_code;
        self
    }

    /// Sets the full country name.
    pub(crate) fn country_name(mut self, country_name: Option<&'a str>) -> Self {
        self.country_name = country_name;
        self
    }

    /// Sets the location name (e.g., "Community Center").
    pub(crate) fn name(mut self, name: Option<&'a str>) -> Self {
        self.name = name;
        self
    }

    /// Sets the ISO state or province code.
    pub(crate) fn state_code(mut self, state_code: Option<&'a str>) -> Self {
        self.state_code = state_code;
        self
    }

    /// Sets the full state or province name.
    pub(crate) fn state_name(mut self, state_name: Option<&'a str>) -> Self {
        self.state_name = state_name;
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_build_location_joins_available_parts() {
        // (case, parts, max length, expected)
        let cases = [
            (
                "all fields",
                LocationParts::new()
                    .address(Some("123 Main St"))
                    .city(Some("San Francisco"))
                    .country_name(Some("United States"))
                    .name(Some("Convention Center"))
                    .state_code(Some("CA"))
                    .state_name(Some("California")),
                100,
                Some("Convention Center, 123 Main St, San Francisco, California, United States"),
            ),
            (
                "city, state and country",
                LocationParts::new()
                    .city(Some("Boston"))
                    .country_name(Some("United States"))
                    .state_name(Some("Massachusetts")),
                100,
                Some("Boston, Massachusetts, United States"),
            ),
            (
                "state code fallback",
                LocationParts::new().city(Some("Boston")).state_code(Some("MA")),
                100,
                Some("Boston, MA"),
            ),
            (
                "country name preferred over code",
                LocationParts::new()
                    .country_code(Some("US"))
                    .country_name(Some("United States")),
                100,
                Some("United States"),
            ),
            (
                "country code fallback",
                LocationParts::new().country_code(Some("US")),
                100,
                Some("US"),
            ),
            (
                "name and address only",
                LocationParts::new()
                    .address(Some("456 Oak Ave"))
                    .name(Some("Tech Hub")),
                100,
                Some("Tech Hub, 456 Oak Ave"),
            ),
            ("empty", LocationParts::new(), 100, None),
            (
                "single part above max length",
                LocationParts::new().name(Some("very long venue name")),
                5,
                None,
            ),
            (
                "parts truncated at max length",
                LocationParts::new()
                    .address(Some("very long street name"))
                    .city(Some("city"))
                    .name(Some("venue")),
                12,
                Some("venue, city"),
            ),
        ];

        for (case, parts, max_len, expected) in cases {
            assert_eq!(
                build_location(&parts, max_len).as_deref(),
                expected,
                "{case}"
            );
        }
    }
}
