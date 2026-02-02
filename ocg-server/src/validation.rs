//! Validation utilities and custom validators for form input.
//!
//! This module provides custom garde validators for common validation patterns
//! used throughout the application.
//!
//! Note: garde custom validators require specific signatures that may trigger clippy warnings.
//! The `&()` context parameter and `&Option<T>` patterns are required by garde's API.

#![allow(clippy::trivially_copy_pass_by_ref)]
#![allow(clippy::ref_option)]

use std::collections::BTreeMap;

use garde::rules::email::parse_email;
use reqwest::Url;

// Maximum length constants for validation.

// Generic size-based limits

/// Maximum length for long text fields.
pub const MAX_LEN_L: usize = 2000;

/// Maximum length for medium text fields.
pub const MAX_LEN_M: usize = 250;

/// Maximum length for short text fields.
pub const MAX_LEN_S: usize = 100;

// Purpose-specific limits

/// Maximum number of elements in a collection (filters, tags, etc.).
pub const MAX_ITEMS: usize = 25;

/// Maximum length for biographies.
pub const MAX_LEN_BIO: usize = 1000;

/// Maximum length for country codes.
pub const MAX_LEN_COUNTRY_CODE: usize = 3;

/// Maximum length for date strings (YYYY-MM-DD).
pub const MAX_LEN_DATE: usize = 10;

/// Maximum length for full descriptions.
pub const MAX_LEN_DESCRIPTION: usize = 8000;

/// Maximum length for short descriptions.
pub const MAX_LEN_DESCRIPTION_SHORT: usize = 500;

/// Maximum length for display names shown to users.
pub const MAX_LEN_DISPLAY_NAME: usize = 80;

/// Maximum length for entity names (groups, events, sessions, sponsors, venues).
pub const MAX_LEN_ENTITY_NAME: usize = 120;

/// Maximum length for link labels in custom link maps.
pub const MAX_LEN_LINK_LABEL: usize = 80;

/// Maximum length for notification bodies.
pub const MAX_LEN_NOTIFICATION_BODY: usize = 5000;

/// Maximum length for sort keys and directions.
pub const MAX_LEN_SORT_KEY: usize = 32;

/// Maximum length for tag or interest values.
pub const MAX_LEN_TAG: usize = 50;

/// Maximum length for timezone identifiers.
pub const MAX_LEN_TIMEZONE: usize = 64;

/// Maximum pagination limit for results per page.
pub const MAX_PAGINATION_LIMIT: usize = 100;

/// Maximum duration for session proposals (minutes).
pub const MAX_SESSION_PROPOSAL_DURATION_MINUTES: i32 = 480;

/// Minimum length for passwords.
pub const MIN_PASSWORD_LEN: usize = 8;

// Custom validators.

/// Validates that each string in a vector is a valid email address within max length.
pub fn email_vec(value: &Option<Vec<String>>, _ctx: &()) -> garde::Result {
    if let Some(vec) = value {
        for email in vec {
            if email.len() > MAX_LEN_M {
                return Err(garde::Error::new(format!(
                    "email exceeds max length of {MAX_LEN_M}"
                )));
            }
            parse_email(email).map_err(|e| garde::Error::new(format!("invalid email: {e}")))?;
        }
    }
    Ok(())
}

/// Validates that a required string is a valid image URL (absolute or relative).
///
/// Accepts absolute URLs (with scheme) or relative URLs starting with `/`.
pub fn image_url(value: &impl AsRef<str>, _ctx: &()) -> garde::Result {
    validate_image_url(value.as_ref())
}

/// Validates that an optional string is a valid image URL (absolute or relative).
///
/// Accepts absolute URLs (with scheme) or relative URLs starting with `/`.
pub fn image_url_opt(value: &Option<String>, _ctx: &()) -> garde::Result {
    if let Some(url) = value {
        validate_image_url(url)?;
    }
    Ok(())
}

/// Validates that each string in a vector is a valid image URL (absolute or relative).
///
/// Accepts absolute URLs (with scheme) or relative URLs starting with `/`.
pub fn image_url_vec(value: &Option<Vec<String>>, _ctx: &()) -> garde::Result {
    if let Some(vec) = value {
        for url in vec {
            validate_image_url(url)?;
        }
    }
    Ok(())
}

/// Validates that a string is non-empty after trimming whitespace.
///
/// Returns an error if the string is empty or contains only whitespace.
pub fn trimmed_non_empty(value: &impl AsRef<str>, _ctx: &()) -> garde::Result {
    if value.as_ref().trim().is_empty() {
        return Err(garde::Error::new("value cannot be empty or whitespace-only"));
    }
    Ok(())
}

/// Validates that an optional string is non-empty after trimming if present.
///
/// Returns Ok if the value is None, or if it's Some with non-whitespace content.
/// Returns an error if the value is Some but empty or whitespace-only.
pub fn trimmed_non_empty_opt(value: &Option<String>, _ctx: &()) -> garde::Result {
    if let Some(s) = value
        && s.trim().is_empty()
    {
        return Err(garde::Error::new("value cannot be empty or whitespace-only"));
    }
    Ok(())
}

/// Validates that each tag in a vector is non-empty, within max length, and within max items.
pub fn trimmed_non_empty_tag_vec(value: &Option<Vec<String>>, _ctx: &()) -> garde::Result {
    validate_trimmed_non_empty_vec(value, MAX_LEN_TAG)
}

/// Validates that each string in a vector is non-empty after trimming and within max length.
pub fn trimmed_non_empty_vec(value: &Option<Vec<String>>, _ctx: &()) -> garde::Result {
    validate_trimmed_non_empty_vec(value, MAX_LEN_M)
}

/// Validates that all values in a `BTreeMap` are valid URLs within max length.
pub fn url_map_values(value: &Option<BTreeMap<String, String>>, _ctx: &()) -> garde::Result {
    if let Some(map) = value {
        if map.len() > MAX_ITEMS {
            return Err(garde::Error::new(format!(
                "value exceeds max items of {MAX_ITEMS}"
            )));
        }
        for (key, url) in map {
            if key.len() > MAX_LEN_LINK_LABEL {
                return Err(garde::Error::new(format!(
                    "key '{key}' exceeds max length of {MAX_LEN_LINK_LABEL}"
                )));
            }
            if url.trim().is_empty() {
                return Err(garde::Error::new(format!("URL for '{key}' cannot be empty")));
            }
            if url.len() > MAX_LEN_L {
                return Err(garde::Error::new(format!(
                    "URL for '{key}' exceeds max length of {MAX_LEN_L}"
                )));
            }
            if Url::parse(url).is_err() {
                return Err(garde::Error::new(format!("invalid URL for '{key}': {url}")));
            }
        }
    }
    Ok(())
}

/// Validates that a latitude value is within valid range (-90 to 90).
pub fn valid_latitude(value: &Option<f64>, _ctx: &()) -> garde::Result {
    if let Some(lat) = value
        && !(-90.0..=90.0).contains(lat)
    {
        return Err(garde::Error::new("latitude must be between -90 and 90"));
    }
    Ok(())
}

/// Validates that a longitude value is within valid range (-180 to 180).
pub fn valid_longitude(value: &Option<f64>, _ctx: &()) -> garde::Result {
    if let Some(lon) = value
        && !(-180.0..=180.0).contains(lon)
    {
        return Err(garde::Error::new("longitude must be between -180 and 180"));
    }
    Ok(())
}

// Helpers.

// Validates a single image URL string (absolute or relative)
fn validate_image_url(url: &str) -> garde::Result {
    if url.trim().is_empty() {
        return Err(garde::Error::new("image URL cannot be empty"));
    }
    if url.len() > MAX_LEN_L {
        return Err(garde::Error::new(format!(
            "image URL exceeds max length of {MAX_LEN_L}"
        )));
    }
    // Accept absolute URLs or relative URLs starting with /
    if !url.starts_with('/') && Url::parse(url).is_err() {
        return Err(garde::Error::new(format!("invalid image URL: {url}")));
    }
    Ok(())
}

// Validates a vector of trimmed non-empty strings with size and item limits
fn validate_trimmed_non_empty_vec(value: &Option<Vec<String>>, max_len: usize) -> garde::Result {
    if let Some(vec) = value {
        if vec.len() > MAX_ITEMS {
            return Err(garde::Error::new(format!(
                "value exceeds max items of {MAX_ITEMS}"
            )));
        }
        for s in vec {
            if s.trim().is_empty() {
                return Err(garde::Error::new("value cannot be empty or whitespace-only"));
            }
            if s.len() > max_len {
                return Err(garde::Error::new(format!(
                    "value exceeds max length of {max_len}"
                )));
            }
        }
    }
    Ok(())
}

// Tests.

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_email_vec_invalid() {
        assert!(email_vec(&Some(vec!["not-an-email".to_string()]), &()).is_err());
        assert!(email_vec(&Some(vec![String::new()]), &()).is_err());
        assert!(email_vec(&Some(vec!["   ".to_string()]), &()).is_err());
        assert!(
            email_vec(
                &Some(vec!["valid@example.com".to_string(), "invalid".to_string()]),
                &()
            )
            .is_err()
        );
    }

    #[test]
    fn test_email_vec_length_exceeded() {
        // Email exceeding MAX_LEN_M
        let long_email = format!("{}@example.com", "a".repeat(MAX_LEN_M));
        assert!(email_vec(&Some(vec![long_email]), &()).is_err());
    }

    #[test]
    fn test_email_vec_none() {
        assert!(email_vec(&None, &()).is_ok());
    }

    #[test]
    fn test_email_vec_valid() {
        assert!(email_vec(&Some(vec!["user@example.com".to_string()]), &()).is_ok());
        assert!(
            email_vec(
                &Some(vec!["user@example.com".to_string(), "other@test.org".to_string()]),
                &()
            )
            .is_ok()
        );
        // Empty vec is valid (no invalid elements)
        assert!(email_vec(&Some(vec![]), &()).is_ok());
    }

    #[test]
    fn test_image_url_invalid() {
        // Not a valid URL and doesn't start with /
        assert!(image_url(&"not-a-url", &()).is_err());
        assert!(image_url(&"example.com/image.png", &()).is_err());
        // Empty
        assert!(image_url(&"", &()).is_err());
        // Whitespace only
        assert!(image_url(&"   ", &()).is_err());
    }

    #[test]
    fn test_image_url_length_exceeded() {
        let long_url = format!("/{}", "a".repeat(MAX_LEN_L));
        assert!(image_url(&long_url, &()).is_err());
    }

    #[test]
    fn test_image_url_opt_invalid() {
        assert!(image_url_opt(&Some("not-a-url".to_string()), &()).is_err());
        assert!(image_url_opt(&Some(String::new()), &()).is_err());
        assert!(image_url_opt(&Some("   ".to_string()), &()).is_err());
    }

    #[test]
    fn test_image_url_opt_length_exceeded() {
        let long_url = format!("/{}", "a".repeat(MAX_LEN_L));
        assert!(image_url_opt(&Some(long_url), &()).is_err());
    }

    #[test]
    fn test_image_url_opt_none() {
        assert!(image_url_opt(&None, &()).is_ok());
    }

    #[test]
    fn test_image_url_opt_valid() {
        // Absolute URLs
        assert!(image_url_opt(&Some("https://example.com/image.png".to_string()), &()).is_ok());
        assert!(image_url_opt(&Some("http://example.com/logo.svg".to_string()), &()).is_ok());
        // Relative URLs
        assert!(image_url_opt(&Some("/images/logo.png".to_string()), &()).is_ok());
        assert!(image_url_opt(&Some("/logo.svg".to_string()), &()).is_ok());
    }

    #[test]
    fn test_image_url_valid() {
        // Absolute URLs
        assert!(image_url(&"https://example.com/image.png", &()).is_ok());
        assert!(image_url(&"http://example.com/logo.svg", &()).is_ok());
        assert!(image_url(&"https://cdn.example.com/path/to/image.jpg", &()).is_ok());
        // Relative URLs
        assert!(image_url(&"/images/logo.png", &()).is_ok());
        assert!(image_url(&"/logo.svg", &()).is_ok());
        assert!(image_url(&"/path/to/image.jpg", &()).is_ok());
    }

    #[test]
    fn test_image_url_vec_invalid() {
        assert!(image_url_vec(&Some(vec!["not-a-url".to_string()]), &()).is_err());
        assert!(image_url_vec(&Some(vec![String::new()]), &()).is_err());
        assert!(image_url_vec(&Some(vec!["   ".to_string()]), &()).is_err());
        // One valid, one invalid
        assert!(
            image_url_vec(
                &Some(vec!["/valid/image.png".to_string(), "not-a-url".to_string()]),
                &()
            )
            .is_err()
        );
    }

    #[test]
    fn test_image_url_vec_length_exceeded() {
        let long_url = format!("/{}", "a".repeat(MAX_LEN_L));
        assert!(image_url_vec(&Some(vec![long_url]), &()).is_err());
    }

    #[test]
    fn test_image_url_vec_none() {
        assert!(image_url_vec(&None, &()).is_ok());
    }

    #[test]
    fn test_image_url_vec_valid() {
        // Absolute URLs
        assert!(image_url_vec(&Some(vec!["https://example.com/image.png".to_string()]), &()).is_ok());
        // Relative URLs
        assert!(image_url_vec(&Some(vec!["/images/logo.png".to_string()]), &()).is_ok());
        // Mix of absolute and relative
        assert!(
            image_url_vec(
                &Some(vec![
                    "https://example.com/image.png".to_string(),
                    "/local/image.jpg".to_string()
                ]),
                &()
            )
            .is_ok()
        );
        // Empty vec is valid
        assert!(image_url_vec(&Some(vec![]), &()).is_ok());
    }

    #[test]
    fn test_trimmed_non_empty_invalid() {
        assert!(trimmed_non_empty(&"", &()).is_err());
        assert!(trimmed_non_empty(&"   ", &()).is_err());
        assert!(trimmed_non_empty(&"\t\n", &()).is_err());
        assert!(trimmed_non_empty(&"  \t  \n  ", &()).is_err());
    }

    #[test]
    fn test_trimmed_non_empty_opt_invalid() {
        assert!(trimmed_non_empty_opt(&Some(String::new()), &()).is_err());
        assert!(trimmed_non_empty_opt(&Some("   ".to_string()), &()).is_err());
        assert!(trimmed_non_empty_opt(&Some("\t\n".to_string()), &()).is_err());
    }

    #[test]
    fn test_trimmed_non_empty_opt_none() {
        assert!(trimmed_non_empty_opt(&None, &()).is_ok());
    }

    #[test]
    fn test_trimmed_non_empty_opt_valid() {
        assert!(trimmed_non_empty_opt(&Some("hello".to_string()), &()).is_ok());
        assert!(trimmed_non_empty_opt(&Some("  hello  ".to_string()), &()).is_ok());
    }

    #[test]
    fn test_trimmed_non_empty_valid() {
        assert!(trimmed_non_empty(&"hello", &()).is_ok());
        assert!(trimmed_non_empty(&"  hello  ", &()).is_ok());
        assert!(trimmed_non_empty(&"a", &()).is_ok());
    }

    #[test]
    fn test_validate_trimmed_non_empty_vec_invalid() {
        assert!(validate_trimmed_non_empty_vec(&Some(vec![String::new()]), MAX_LEN_TAG).is_err());
        assert!(validate_trimmed_non_empty_vec(&Some(vec!["   ".to_string()]), MAX_LEN_TAG).is_err());
        assert!(
            validate_trimmed_non_empty_vec(&Some(vec!["valid".to_string(), "   ".to_string()]), MAX_LEN_TAG)
                .is_err()
        );
    }

    #[test]
    fn test_validate_trimmed_non_empty_vec_length_exceeded() {
        let long_tag = "a".repeat(MAX_LEN_TAG + 1);
        assert!(validate_trimmed_non_empty_vec(&Some(vec![long_tag.clone()]), MAX_LEN_TAG).is_err());
        assert!(validate_trimmed_non_empty_vec(&Some(vec![long_tag]), MAX_LEN_M).is_ok());
    }

    #[test]
    fn test_validate_trimmed_non_empty_vec_max_items() {
        let tags = vec!["tag".to_string(); MAX_ITEMS + 1];
        assert!(validate_trimmed_non_empty_vec(&Some(tags), MAX_LEN_TAG).is_err());
    }

    #[test]
    fn test_validate_trimmed_non_empty_vec_none() {
        assert!(validate_trimmed_non_empty_vec(&None, MAX_LEN_TAG).is_ok());
    }

    #[test]
    fn test_validate_trimmed_non_empty_vec_valid() {
        assert!(validate_trimmed_non_empty_vec(&Some(vec!["hello".to_string()]), MAX_LEN_M).is_ok());
        assert!(
            validate_trimmed_non_empty_vec(&Some(vec!["a".to_string(), "b".to_string()]), MAX_LEN_M).is_ok()
        );
        assert!(validate_trimmed_non_empty_vec(&Some(vec!["  hello  ".to_string()]), MAX_LEN_M).is_ok());
        // Empty vec is valid (no invalid elements)
        assert!(validate_trimmed_non_empty_vec(&Some(vec![]), MAX_LEN_M).is_ok());
    }

    #[test]
    fn test_url_map_values_invalid() {
        let mut map = BTreeMap::new();
        map.insert("test".to_string(), "not-a-url".to_string());
        assert!(url_map_values(&Some(map), &()).is_err());

        let mut map = BTreeMap::new();
        map.insert("test".to_string(), String::new());
        assert!(url_map_values(&Some(map), &()).is_err());

        let mut map = BTreeMap::new();
        map.insert("test".to_string(), "   ".to_string());
        assert!(url_map_values(&Some(map), &()).is_err());

        // One valid, one invalid
        let mut map = BTreeMap::new();
        map.insert("valid".to_string(), "https://example.com".to_string());
        map.insert("invalid".to_string(), "not-a-url".to_string());
        assert!(url_map_values(&Some(map), &()).is_err());
    }

    #[test]
    fn test_url_map_values_length_exceeded() {
        // Key exceeding MAX_LEN_LINK_LABEL
        let mut map = BTreeMap::new();
        let long_key = "a".repeat(MAX_LEN_LINK_LABEL + 1);
        map.insert(long_key, "https://example.com".to_string());
        assert!(url_map_values(&Some(map), &()).is_err());

        // Exceeds MAX_ITEMS
        let mut map = BTreeMap::new();
        for idx in 0..=MAX_ITEMS {
            map.insert(format!("key-{idx}"), "https://example.com".to_string());
        }
        assert!(url_map_values(&Some(map), &()).is_err());

        // URL exceeding MAX_LEN_L
        let mut map = BTreeMap::new();
        let long_url = format!("https://example.com/{}", "a".repeat(MAX_LEN_L));
        map.insert("test".to_string(), long_url);
        assert!(url_map_values(&Some(map), &()).is_err());
    }

    #[test]
    fn test_url_map_values_none() {
        assert!(url_map_values(&None, &()).is_ok());
    }

    #[test]
    fn test_url_map_values_valid() {
        let mut map = BTreeMap::new();
        map.insert("website".to_string(), "https://example.com".to_string());
        assert!(url_map_values(&Some(map), &()).is_ok());

        let mut map = BTreeMap::new();
        map.insert("website".to_string(), "https://example.com".to_string());
        map.insert("docs".to_string(), "https://docs.example.com/path".to_string());
        assert!(url_map_values(&Some(map), &()).is_ok());

        // Empty map is valid
        assert!(url_map_values(&Some(BTreeMap::new()), &()).is_ok());
    }

    #[test]
    fn test_valid_latitude_invalid() {
        assert!(valid_latitude(&Some(90.1), &()).is_err());
        assert!(valid_latitude(&Some(-90.1), &()).is_err());
        assert!(valid_latitude(&Some(180.0), &()).is_err());
        assert!(valid_latitude(&Some(-180.0), &()).is_err());
    }

    #[test]
    fn test_valid_latitude_none() {
        assert!(valid_latitude(&None, &()).is_ok());
    }

    #[test]
    fn test_valid_latitude_valid() {
        assert!(valid_latitude(&Some(0.0), &()).is_ok());
        assert!(valid_latitude(&Some(90.0), &()).is_ok());
        assert!(valid_latitude(&Some(-90.0), &()).is_ok());
        assert!(valid_latitude(&Some(45.5), &()).is_ok());
        assert!(valid_latitude(&Some(-45.5), &()).is_ok());
    }

    #[test]
    fn test_valid_longitude_invalid() {
        assert!(valid_longitude(&Some(180.1), &()).is_err());
        assert!(valid_longitude(&Some(-180.1), &()).is_err());
        assert!(valid_longitude(&Some(360.0), &()).is_err());
    }

    #[test]
    fn test_valid_longitude_none() {
        assert!(valid_longitude(&None, &()).is_ok());
    }

    #[test]
    fn test_valid_longitude_valid() {
        assert!(valid_longitude(&Some(0.0), &()).is_ok());
        assert!(valid_longitude(&Some(180.0), &()).is_ok());
        assert!(valid_longitude(&Some(-180.0), &()).is_ok());
        assert!(valid_longitude(&Some(90.0), &()).is_ok());
        assert!(valid_longitude(&Some(-90.0), &()).is_ok());
    }
}
