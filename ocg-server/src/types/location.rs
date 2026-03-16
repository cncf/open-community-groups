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
    push(parts.state);
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
    /// State or province.
    state: Option<&'a str>,
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

    /// Sets the state or province.
    pub(crate) fn state(mut self, state: Option<&'a str>) -> Self {
        self.state = state;
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_build_location_all_fields() {
        let address = "123 Main St".to_string();
        let city = "San Francisco".to_string();
        let country_name = "United States".to_string();
        let name = "Convention Center".to_string();
        let state = "CA".to_string();

        let parts = LocationParts::new()
            .address(Some(address.as_str()))
            .city(Some(city.as_str()))
            .country_name(Some(country_name.as_str()))
            .name(Some(name.as_str()))
            .state(Some(state.as_str()));

        assert_eq!(
            build_location(&parts, 100),
            Some("Convention Center, 123 Main St, San Francisco, CA, United States".to_string())
        );
    }

    #[test]
    fn test_build_location_city_state_country() {
        let city = "Boston".to_string();
        let country_name = "United States".to_string();
        let state = "MA".to_string();

        let parts = LocationParts::new()
            .city(Some(city.as_str()))
            .country_name(Some(country_name.as_str()))
            .state(Some(state.as_str()));

        assert_eq!(
            build_location(&parts, 100),
            Some("Boston, MA, United States".to_string())
        );
    }

    #[test]
    fn test_build_location_country_name_preferred_over_code() {
        let country_code = "US".to_string();
        let country_name = "United States".to_string();

        let parts = LocationParts::new()
            .country_code(Some(country_code.as_str()))
            .country_name(Some(country_name.as_str()));

        assert_eq!(build_location(&parts, 100), Some("United States".to_string()));
    }

    #[test]
    fn test_build_location_country_code_fallback() {
        let country_code = "US".to_string();

        let parts = LocationParts::new().country_code(Some(country_code.as_str()));

        assert_eq!(build_location(&parts, 100), Some("US".to_string()));
    }

    #[test]
    fn test_build_location_empty() {
        let parts = LocationParts::new();
        assert_eq!(build_location(&parts, 100), None);
    }

    #[test]
    fn test_build_location_max_length_exceeded() {
        let name = "very long venue name".to_string();

        let parts = LocationParts::new().name(Some(name.as_str()));

        assert_eq!(build_location(&parts, 5), None);
    }

    #[test]
    fn test_build_location_truncates_at_max_length() {
        let address = "very long street name".to_string();
        let city = "city".to_string();
        let name = "venue".to_string();

        let parts = LocationParts::new()
            .address(Some(address.as_str()))
            .city(Some(city.as_str()))
            .name(Some(name.as_str()));

        assert_eq!(build_location(&parts, 12), Some("venue, city".to_string()));
    }

    #[test]
    fn test_build_location_name_and_address_only() {
        let address = "456 Oak Ave".to_string();
        let name = "Tech Hub".to_string();

        let parts = LocationParts::new()
            .address(Some(address.as_str()))
            .name(Some(name.as_str()));

        assert_eq!(
            build_location(&parts, 100),
            Some("Tech Hub, 456 Oak Ave".to_string())
        );
    }
}
