//! Validation utilities and custom validators for form input.
//!
//! This module provides custom garde validators for common validation patterns
//! used throughout the application.
//!
//! Note: garde custom validators require specific signatures that may trigger clippy warnings.
//! The `&()` context parameter and `&Option<T>` patterns are required by garde's API.

#![allow(clippy::trivially_copy_pass_by_ref)]
#![allow(clippy::ref_option)]
#![allow(clippy::collapsible_if)]

use std::collections::BTreeMap;

use reqwest::Url;

// Maximum length constants for validation.

/// Maximum length for short text fields (city, country, timezone, etc.).
pub const MAX_LEN_S: usize = 100;

/// Maximum length for medium text fields (names, titles, usernames).
pub const MAX_LEN_M: usize = 255;

/// Maximum length for long text fields (URLs, bios, short descriptions).
pub const MAX_LEN_L: usize = 2048;

/// Maximum length for extra-long text fields (full descriptions).
pub const MAX_LEN_XL: usize = 10000;

/// Maximum pagination limit.
pub const MAX_LIMIT: usize = 25;

// Custom validators.

/// Validates that each string in a vector is a valid email address within max length.
pub fn email_vec(value: &Option<Vec<String>>, _ctx: &()) -> garde::Result {
    if let Some(vec) = value {
        for email in vec {
            if !email.contains('@') || email.trim().is_empty() {
                return Err(garde::Error::new("invalid email address"));
            }
            if email.len() > MAX_LEN_M {
                return Err(garde::Error::new(format!(
                    "email exceeds max length of {MAX_LEN_M}"
                )));
            }
        }
    }
    Ok(())
}

/// Validates that a string is a valid hex color in #RRGGBB format.
pub fn hex_color(value: &impl AsRef<str>, _ctx: &()) -> garde::Result {
    let s = value.as_ref();
    if s.len() != 7 {
        return Err(garde::Error::new(
            "hex color must be 7 characters (e.g., #FF0000)",
        ));
    }
    if !s.starts_with('#') {
        return Err(garde::Error::new("hex color must start with #"));
    }
    if !s[1..].chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(garde::Error::new("hex color must contain valid hex digits"));
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
    if let Some(s) = value {
        if s.trim().is_empty() {
            return Err(garde::Error::new("value cannot be empty or whitespace-only"));
        }
    }
    Ok(())
}

/// Validates that each string in a vector is non-empty after trimming and within max length.
pub fn trimmed_non_empty_vec(value: &Option<Vec<String>>, _ctx: &()) -> garde::Result {
    if let Some(vec) = value {
        for s in vec {
            if s.trim().is_empty() {
                return Err(garde::Error::new("value cannot be empty or whitespace-only"));
            }
            if s.len() > MAX_LEN_M {
                return Err(garde::Error::new(format!(
                    "value exceeds max length of {MAX_LEN_M}"
                )));
            }
        }
    }
    Ok(())
}

/// Validates that all values in a `BTreeMap` are valid URLs within max length.
pub fn url_map_values(value: &Option<BTreeMap<String, String>>, _ctx: &()) -> garde::Result {
    if let Some(map) = value {
        for (key, url) in map {
            if key.len() > MAX_LEN_M {
                return Err(garde::Error::new(format!(
                    "key '{key}' exceeds max length of {MAX_LEN_M}"
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

/// Validates that each string in a vector is a valid URL within max length.
pub fn url_vec(value: &Option<Vec<String>>, _ctx: &()) -> garde::Result {
    if let Some(vec) = value {
        for url in vec {
            if url.trim().is_empty() {
                return Err(garde::Error::new("URL cannot be empty"));
            }
            if url.len() > MAX_LEN_L {
                return Err(garde::Error::new(format!(
                    "URL exceeds max length of {MAX_LEN_L}"
                )));
            }
            if Url::parse(url).is_err() {
                return Err(garde::Error::new(format!("invalid URL: {url}")));
            }
        }
    }
    Ok(())
}

/// Validates that a latitude value is within valid range (-90 to 90).
pub fn valid_latitude(value: &Option<f64>, _ctx: &()) -> garde::Result {
    if let Some(lat) = value {
        if !(-90.0..=90.0).contains(lat) {
            return Err(garde::Error::new("latitude must be between -90 and 90"));
        }
    }
    Ok(())
}

/// Validates that a longitude value is within valid range (-180 to 180).
pub fn valid_longitude(value: &Option<f64>, _ctx: &()) -> garde::Result {
    if let Some(lon) = value {
        if !(-180.0..=180.0).contains(lon) {
            return Err(garde::Error::new("longitude must be between -180 and 180"));
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
    fn test_hex_color_invalid() {
        // Missing #
        assert!(hex_color(&"FF0000", &()).is_err());
        // Too short
        assert!(hex_color(&"#FFF", &()).is_err());
        // Too long
        assert!(hex_color(&"#FF00000", &()).is_err());
        // Invalid hex digits
        assert!(hex_color(&"#GGGGGG", &()).is_err());
        assert!(hex_color(&"#ZZZZZZ", &()).is_err());
        // Empty
        assert!(hex_color(&"", &()).is_err());
        // Wrong prefix
        assert!(hex_color(&"0xFF0000", &()).is_err());
    }

    #[test]
    fn test_hex_color_valid() {
        assert!(hex_color(&"#FF0000", &()).is_ok());
        assert!(hex_color(&"#000000", &()).is_ok());
        assert!(hex_color(&"#ffffff", &()).is_ok());
        assert!(hex_color(&"#FFFFFF", &()).is_ok());
        assert!(hex_color(&"#123abc", &()).is_ok());
        assert!(hex_color(&"#D62293", &()).is_ok());
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
    fn test_trimmed_non_empty_vec_invalid() {
        assert!(trimmed_non_empty_vec(&Some(vec![String::new()]), &()).is_err());
        assert!(trimmed_non_empty_vec(&Some(vec!["   ".to_string()]), &()).is_err());
        assert!(trimmed_non_empty_vec(&Some(vec!["valid".to_string(), String::new()]), &()).is_err());
        assert!(trimmed_non_empty_vec(&Some(vec!["valid".to_string(), "   ".to_string()]), &()).is_err());
    }

    #[test]
    fn test_trimmed_non_empty_vec_length_exceeded() {
        // String exceeding MAX_LEN_M
        let long_string = "a".repeat(MAX_LEN_M + 1);
        assert!(trimmed_non_empty_vec(&Some(vec![long_string]), &()).is_err());

        // One valid, one too long
        let long_string = "a".repeat(MAX_LEN_M + 1);
        assert!(trimmed_non_empty_vec(&Some(vec!["valid".to_string(), long_string]), &()).is_err());
    }

    #[test]
    fn test_trimmed_non_empty_vec_none() {
        assert!(trimmed_non_empty_vec(&None, &()).is_ok());
    }

    #[test]
    fn test_trimmed_non_empty_vec_valid() {
        assert!(trimmed_non_empty_vec(&Some(vec!["hello".to_string()]), &()).is_ok());
        assert!(trimmed_non_empty_vec(&Some(vec!["a".to_string(), "b".to_string()]), &()).is_ok());
        assert!(trimmed_non_empty_vec(&Some(vec!["  hello  ".to_string()]), &()).is_ok());
        // Empty vec is valid (no invalid elements)
        assert!(trimmed_non_empty_vec(&Some(vec![]), &()).is_ok());
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
        // Key exceeding MAX_LEN_M
        let mut map = BTreeMap::new();
        let long_key = "a".repeat(MAX_LEN_M + 1);
        map.insert(long_key, "https://example.com".to_string());
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
    fn test_url_vec_invalid() {
        assert!(url_vec(&Some(vec!["not-a-url".to_string()]), &()).is_err());
        assert!(url_vec(&Some(vec![String::new()]), &()).is_err());
        assert!(url_vec(&Some(vec!["   ".to_string()]), &()).is_err());
        assert!(
            url_vec(
                &Some(vec!["https://example.com".to_string(), "not-a-url".to_string()]),
                &()
            )
            .is_err()
        );
    }

    #[test]
    fn test_url_vec_length_exceeded() {
        // URL exceeding MAX_LEN_L
        let long_url = format!("https://example.com/{}", "a".repeat(MAX_LEN_L));
        assert!(url_vec(&Some(vec![long_url]), &()).is_err());

        // One valid, one too long
        let long_url = format!("https://example.com/{}", "a".repeat(MAX_LEN_L));
        assert!(url_vec(&Some(vec!["https://example.com".to_string(), long_url]), &()).is_err());
    }

    #[test]
    fn test_url_vec_none() {
        assert!(url_vec(&None, &()).is_ok());
    }

    #[test]
    fn test_url_vec_valid() {
        assert!(url_vec(&Some(vec!["https://example.com".to_string()]), &()).is_ok());
        assert!(
            url_vec(
                &Some(vec![
                    "https://example.com".to_string(),
                    "https://other.com/path".to_string()
                ]),
                &()
            )
            .is_ok()
        );
        // Empty vec is valid
        assert!(url_vec(&Some(vec![]), &()).is_ok());
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
