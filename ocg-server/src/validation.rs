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

use chrono::{DateTime, Datelike, NaiveDate, NaiveDateTime, Utc};
use garde::rules::email::parse_email;
use reqwest::Url;
use serde::{Deserialize, Deserializer};

use crate::types::payments::GroupPaymentRecipient;

/// Allowed event label colors.
pub const EVENT_LABEL_COLORS: [&str; 10] = [
    "#FFD866", "#FC9867", "#FF6188", "#AB9DF2", "#78DCE8", "#A9DC76", "#A88F6A", "#9DA5B4",
    "#FF9EBB", "#6272A4",
];

// Maximum length constants for validation.

// Generic size-based limits

/// Maximum length for long text fields.
pub const MAX_LEN_L: usize = 2000;

/// Maximum length for medium text fields.
pub const MAX_LEN_M: usize = 250;

/// Maximum length for short text fields.
pub const MAX_LEN_S: usize = 100;

// Purpose-specific limits

/// Maximum number of labels assigned to one CFS submission or session.
pub const MAX_ASSIGNED_EVENT_LABELS: usize = 10;

/// Maximum number of values accepted by each community contact filter. The
/// bound keeps filter queries small while covering every option a community
/// can reasonably offer.
pub const MAX_CONTACT_FILTER_VALUES: usize = 500;

/// Maximum number of groups that can co-host one event. The bound keeps the
/// co-host selector, invitation emails, and public credit lines small.
pub const MAX_EVENT_COHOSTS: usize = 10;

/// Maximum number of labels allowed per event.
pub const MAX_EVENT_LABELS_PER_EVENT: usize = 200;

/// Maximum number of surveys per event, matching the database limit.
pub const MAX_EVENT_SURVEYS: usize = 10;

/// Maximum number of questions per event survey, matching the database limit.
pub const MAX_EVENT_SURVEY_QUESTIONS: usize = 30;

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

/// Maximum length for CFS label names.
pub const MAX_LEN_EVENT_LABEL_NAME: usize = 80;

/// Maximum length for group pretty slugs.
pub const MAX_LEN_GROUP_PRETTY_SLUG: usize = 50;

/// Maximum length, in characters, for inbox message bodies. Matches the
/// character limit enforced by the database on stored messages.
pub const MAX_LEN_INBOX_MESSAGE: usize = 5000;

/// Maximum length for link labels in custom link maps.
pub const MAX_LEN_LINK_LABEL: usize = 80;

/// Maximum length for notification bodies.
pub const MAX_LEN_NOTIFICATION_BODY: usize = 5000;

/// Maximum length, in characters, for free-text questionnaire answers.
/// Matches the limit enforced by the database questionnaire validator.
pub const MAX_LEN_QUESTIONNAIRE_ANSWER: usize = MAX_LEN_DESCRIPTION;

/// Maximum length for sort keys and directions.
pub const MAX_LEN_SORT_KEY: usize = 32;

/// Maximum length for tag or interest values.
pub const MAX_LEN_TAG: usize = 50;

/// Maximum length for timezone identifiers.
pub const MAX_LEN_TIMEZONE: usize = 64;

/// Maximum length for UTM parameter values, matching the database constraints.
pub const MAX_LEN_UTM_VALUE: usize = 50;

/// Maximum pagination limit for results per page.
pub const MAX_PAGINATION_LIMIT: usize = 100;

/// Maximum number of additional occurrences created for a recurring event.
pub const MAX_RECURRING_ADDITIONAL_OCCURRENCES: i32 = 12;

/// Maximum duration for session proposals (minutes).
pub const MAX_SESSION_PROPOSAL_DURATION_MINUTES: i32 = 480;

/// Maximum page size for the survey answers, survey responses and user
/// surveys listings, matching the database caps.
pub const MAX_SURVEY_PAGE_LIMIT: usize = 50;

/// Maximum number of UTM values in each list a group defines, matching the
/// database constraints.
pub const MAX_UTM_VALUES: usize = 20;

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
/// Accepts absolute HTTP(S) URLs or relative URLs starting with `/`.
pub fn image_url(value: &impl AsRef<str>, _ctx: &()) -> garde::Result {
    validate_image_url(value.as_ref())
}

/// Validates that an optional string is a valid image URL (absolute or relative).
///
/// Accepts absolute HTTP(S) URLs or relative URLs starting with `/`.
pub fn image_url_opt(value: &Option<String>, _ctx: &()) -> garde::Result {
    if let Some(url) = value {
        validate_image_url(url)?;
    }
    Ok(())
}

/// Validates that each string in a vector is a valid image URL (absolute or relative).
///
/// Accepts absolute HTTP(S) URLs or relative URLs starting with `/`.
pub fn image_url_vec(value: &Option<Vec<String>>, _ctx: &()) -> garde::Result {
    if let Some(vec) = value {
        for url in vec {
            validate_image_url(url)?;
        }
    }
    Ok(())
}

/// Returns whether a URL is safe to render in an HTML href attribute.
pub(crate) fn is_safe_href(url: &str) -> bool {
    is_safe_web_url(url, true)
}

/// Returns whether a UTM value has the format accepted by the database.
pub(crate) fn is_valid_utm_value(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= MAX_LEN_UTM_VALUE
        && value.bytes().all(|byte| {
            byte.is_ascii_lowercase() || byte.is_ascii_digit() || matches!(byte, b'.' | b'-' | b'_')
        })
}

/// Validates that a string is non-empty after trimming whitespace.
///
/// Returns an error if the string is empty or contains only whitespace.
pub fn trimmed_non_empty(value: &impl AsRef<str>, _ctx: &()) -> garde::Result {
    if value.as_ref().trim().is_empty() {
        return Err(garde::Error::new(
            "value cannot be empty or whitespace-only",
        ));
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
        return Err(garde::Error::new(
            "value cannot be empty or whitespace-only",
        ));
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
                return Err(garde::Error::new(format!(
                    "URL for '{key}' cannot be empty"
                )));
            }
            if url.len() > MAX_LEN_L {
                return Err(garde::Error::new(format!(
                    "URL for '{key}' exceeds max length of {MAX_LEN_L}"
                )));
            }
            if !is_safe_web_url(url, false) {
                return Err(garde::Error::new(format!("invalid URL for '{key}': {url}")));
            }
        }
    }
    Ok(())
}

/// Validates an optional list of UTM values defined by a group.
pub fn utm_value_vec(value: &Option<Vec<String>>, _ctx: &()) -> garde::Result {
    let Some(values) = value else {
        return Ok(());
    };

    // Enforce the list size accepted by the database
    if values.len() > MAX_UTM_VALUES {
        return Err(garde::Error::new(format!(
            "value exceeds max items of {MAX_UTM_VALUES}"
        )));
    }

    // Require unique values in the format matched against UTM parameters
    for (index, value) in values.iter().enumerate() {
        if !is_valid_utm_value(value) {
            return Err(garde::Error::new(format!(
                "utm value '{value}' must have up to {MAX_LEN_UTM_VALUE} lowercase letters, numbers, dots, hyphens, or underscores"
            )));
        }
        if values[..index].contains(value) {
            return Err(garde::Error::new(format!(
                "utm value '{value}' is duplicated"
            )));
        }
    }

    Ok(())
}

/// Validates that an optional date has a year PostgreSQL accepts as `YYYY`.
///
/// `chrono` parses signed and five-digit years that `::date` rejects, so filters
/// forwarded to the database are limited to years 1 through 9999.
pub fn valid_date_opt(value: &Option<NaiveDate>, _ctx: &()) -> garde::Result {
    if let Some(date) = value
        && !(1..=9999).contains(&date.year())
    {
        return Err(garde::Error::new("year must be between 1 and 9999"));
    }
    Ok(())
}

/// Validates that an event label color belongs to the predefined palette.
pub fn valid_event_label_color(value: &impl AsRef<str>, _ctx: &()) -> garde::Result {
    if !EVENT_LABEL_COLORS.contains(&value.as_ref()) {
        return Err(garde::Error::new("invalid label color"));
    }
    Ok(())
}

/// Validates an optional group pretty slug.
pub fn valid_group_pretty_slug(value: &Option<String>, _ctx: &()) -> garde::Result {
    // Normalize optional form input
    let Some(value) = value.as_deref() else {
        return Ok(());
    };
    let value = value.trim();

    // Allow empty values so the database can clear the pretty slug
    if value.is_empty() {
        return Ok(());
    }

    // Enforce the public URL length limit
    if value.len() > MAX_LEN_GROUP_PRETTY_SLUG {
        return Err(garde::Error::new(
            "Pretty slug must be 50 characters or fewer",
        ));
    }

    // Enforce strict ASCII URL characters
    if !value
        .bytes()
        .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
    {
        return Err(garde::Error::new(
            "Pretty slug must use lowercase ASCII letters, numbers, and hyphens only",
        ));
    }

    // Enforce alphanumeric URL boundaries
    if !value
        .as_bytes()
        .first()
        .is_some_and(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit())
        || !value
            .as_bytes()
            .last()
            .is_some_and(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit())
    {
        return Err(garde::Error::new(
            "Pretty slug must start and end with a lowercase ASCII letter or number",
        ));
    }

    // Reject visually confusing duplicate separators
    if value.contains("--") {
        return Err(garde::Error::new(
            "Pretty slug cannot contain consecutive hyphens",
        ));
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

/// Validates the paired Stripe account and attendee-visible legal seller name.
pub fn valid_payment_recipient(value: &Option<GroupPaymentRecipient>, _ctx: &()) -> garde::Result {
    let Some(recipient) = value else {
        return Ok(());
    };
    let recipient_id = recipient.recipient_id.trim();
    let seller_display_name = recipient.seller_display_name.trim();

    if recipient_id.is_empty() && seller_display_name.is_empty() {
        return Ok(());
    }
    if recipient_id.is_empty() || seller_display_name.is_empty() {
        return Err(garde::Error::new(
            "payment recipient account and seller name must be provided together",
        ));
    }
    if recipient_id.len() > MAX_LEN_M {
        return Err(garde::Error::new(format!(
            "payment recipient account exceeds max length of {MAX_LEN_M}",
        )));
    }
    if seller_display_name.len() > MAX_LEN_ENTITY_NAME {
        return Err(garde::Error::new(format!(
            "seller name exceeds max length of {MAX_LEN_ENTITY_NAME}",
        )));
    }

    Ok(())
}

/// Validates that an optional string is an absolute HTTP or HTTPS URL.
pub fn web_url_opt(value: &Option<String>, _ctx: &()) -> garde::Result {
    if let Some(url) = value
        && !is_safe_web_url(url, false)
    {
        return Err(garde::Error::new(format!(
            "URL must be an absolute HTTP or HTTPS URL: {url}"
        )));
    }
    Ok(())
}

/// Checks an HTTP(S) URL and optionally permits root-relative paths.
fn is_safe_web_url(url: &str, allow_root_relative: bool) -> bool {
    // Reject characters browsers strip before parsing the URL
    if url.contains(['\t', '\n', '\r']) {
        return false;
    }

    // Permit unambiguous root-relative paths
    if allow_root_relative
        && url.starts_with('/')
        && !url.starts_with("//")
        && !url.starts_with("/\\")
    {
        return true;
    }

    // Require absolute URLs to use a web scheme and include a host
    Url::parse(url)
        .is_ok_and(|url| matches!(url.scheme(), "http" | "https") && url.host_str().is_some())
}

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
    // Accept absolute HTTP(S) URLs or root-relative paths
    if !is_safe_web_url(url, true) {
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
                return Err(garde::Error::new(
                    "value cannot be empty or whitespace-only",
                ));
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

// Custom deserializers.

/// Deserializes an optional local date and time (`YYYY-MM-DDTHH:MM:SS`, or
/// `YYYY-MM-DDTHH:MM` as browsers send `datetime-local` values without
/// seconds), treating blank values as absent.
pub fn blank_naive_datetime_as_none<'de, D>(
    deserializer: D,
) -> Result<Option<NaiveDateTime>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<String>::deserialize(deserializer)?;
    value
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| {
            value
                .parse::<NaiveDateTime>()
                .or_else(|_| NaiveDateTime::parse_from_str(value, "%Y-%m-%dT%H:%M"))
        })
        .transpose()
        .map_err(serde::de::Error::custom)
}

/// Deserializes an optional string, treating blank values as absent.
pub fn blank_string_as_none<'de, D>(deserializer: D) -> Result<Option<String>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<String>::deserialize(deserializer)?;
    Ok(value.filter(|value| !value.trim().is_empty()))
}

/// Deserializes an optional Unix timestamp in seconds, treating blank values as
/// absent.
pub fn blank_timestamp_seconds_as_none<'de, D>(
    deserializer: D,
) -> Result<Option<DateTime<Utc>>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<String>::deserialize(deserializer)?;
    value
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| {
            value
                .parse::<i64>()
                .ok()
                .and_then(|seconds| DateTime::from_timestamp(seconds, 0))
                .ok_or_else(|| serde::de::Error::custom("invalid unix timestamp"))
        })
        .transpose()
}

// Tests.

#[cfg(test)]
mod tests {
    use serde::Deserialize;

    use super::*;

    // Validators.

    #[test]
    fn test_email_vec_invalid() {
        // An address parse_email accepts that is longer than MAX_LEN_M
        let long_email = format!(
            "user@{}example.com",
            format!("{}.", "a".repeat(60)).repeat(4)
        );
        assert!(long_email.len() > MAX_LEN_M);
        assert!(parse_email(&long_email).is_ok());

        let cases = [
            (
                "not an email",
                Some(strings(&["not-an-email"])),
                "invalid email: ",
            ),
            ("empty", Some(strings(&[""])), "invalid email: "),
            ("blank", Some(strings(&["   "])), "invalid email: "),
            (
                "valid then invalid",
                Some(strings(&["valid@example.com", "invalid"])),
                "invalid email: ",
            ),
            (
                "too long",
                Some(vec![long_email]),
                "email exceeds max length of 250",
            ),
        ];

        for (case, value, expected) in cases {
            let message = email_vec(&value, &()).expect_err(case).to_string();
            assert!(message.starts_with(expected), "{case}: {message}");
        }
    }

    #[test]
    fn test_email_vec_valid() {
        let cases = [
            ("none", None),
            ("one address", Some(strings(&["user@example.com"]))),
            (
                "two addresses",
                Some(strings(&["user@example.com", "other@test.org"])),
            ),
            ("empty list", Some(strings(&[]))),
        ];

        for (case, value) in cases {
            assert!(email_vec(&value, &()).is_ok(), "{case}");
        }
    }

    #[test]
    fn test_image_url_invalid() {
        let long_url = format!("/{}", "a".repeat(MAX_LEN_L));
        let cases = [
            ("malformed", "not-a-url"),
            ("missing scheme", "example.com/image.png"),
            ("protocol-relative", "//example.com/image.png"),
            ("backslash protocol-relative", "/\\evil.com/image.png"),
            ("data scheme", "data:image/png;base64,AA=="),
            ("file scheme", "file:///tmp/image.png"),
            ("javascript scheme", "javascript:alert(1)"),
            ("stripped tab", "/\t/evil.com/image.png"),
            ("stripped newline", "/\n/evil.com/image.png"),
            ("stripped carriage return", "/\r/evil.com/image.png"),
        ];

        for (case, url) in cases {
            let message = image_url(&url, &()).expect_err(case).to_string();
            assert_eq!(message, format!("invalid image URL: {url}"), "{case}");
        }
        for (case, url, expected) in [
            ("empty", "", "image URL cannot be empty"),
            ("blank", "   ", "image URL cannot be empty"),
            (
                "too long",
                long_url.as_str(),
                "image URL exceeds max length of 2000",
            ),
        ] {
            let message = image_url(&url, &()).expect_err(case).to_string();
            assert_eq!(message, expected, "{case}");
        }
    }

    #[test]
    fn test_image_url_opt_invalid() {
        let message = image_url_opt(&Some("not-a-url".to_string()), &())
            .unwrap_err()
            .to_string();

        assert_eq!(message, "invalid image URL: not-a-url");
    }

    #[test]
    fn test_image_url_opt_valid() {
        for (case, value) in [
            ("none", None),
            (
                "absolute",
                Some("https://example.com/image.png".to_string()),
            ),
            ("root-relative", Some("/images/logo.png".to_string())),
        ] {
            assert!(image_url_opt(&value, &()).is_ok(), "{case}");
        }
    }

    #[test]
    fn test_image_url_valid() {
        for url in [
            "https://example.com/image.png",
            "http://example.com/logo.svg",
            "https://cdn.example.com/path/to/image.jpg",
            "/images/logo.png",
            "/logo.svg",
            "/path/to/image.jpg",
        ] {
            assert!(image_url(&url, &()).is_ok(), "{url:?}");
        }
    }

    #[test]
    fn test_image_url_vec_invalid() {
        for (case, value) in [
            ("invalid", Some(strings(&["not-a-url"]))),
            (
                "valid then invalid",
                Some(strings(&["/valid/image.png", "not-a-url"])),
            ),
        ] {
            let message = image_url_vec(&value, &()).expect_err(case).to_string();
            assert_eq!(message, "invalid image URL: not-a-url", "{case}");
        }
    }

    #[test]
    fn test_image_url_vec_valid() {
        for (case, value) in [
            ("none", None),
            (
                "absolute and root-relative",
                Some(strings(&[
                    "https://example.com/image.png",
                    "/local/image.jpg",
                ])),
            ),
            ("empty list", Some(strings(&[]))),
        ] {
            assert!(image_url_vec(&value, &()).is_ok(), "{case}");
        }
    }

    #[test]
    fn test_is_safe_href_matches_safe_urls() {
        let cases = [
            ("absolute web URL", "https://example.com/path", true),
            ("plain HTTP URL", "http://example.com", true),
            ("root-relative path", "/relative/path", true),
            ("protocol-relative URL", "//evil.com", false),
            ("backslash protocol-relative URL", "/\\evil.com", false),
            ("data URL", "data:text/html,hello", false),
            ("javascript URL", "javascript:alert(1)", false),
            ("URL without host", "https://", false),
            ("stripped tab", "/\t/evil.com", false),
            ("stripped newline", "/\n/evil.com", false),
            ("stripped carriage return", "/\r/evil.com", false),
        ];

        for (case, url, expected) in cases {
            assert_eq!(is_safe_href(url), expected, "{case}");
        }
    }

    #[test]
    fn test_is_valid_utm_value_invalid() {
        let too_long = "a".repeat(MAX_LEN_UTM_VALUE + 1);
        for value in ["", "News", "news letter", "news!", "news\u{0}", &too_long] {
            assert!(!is_valid_utm_value(value), "{value:?} should be invalid");
        }
    }

    #[test]
    fn test_is_valid_utm_value_valid() {
        let longest = "a".repeat(MAX_LEN_UTM_VALUE);
        for value in ["newsletter", "partner.site", "spring-launch_2026", &longest] {
            assert!(is_valid_utm_value(value), "{value:?} should be valid");
        }
    }

    #[test]
    fn test_trimmed_non_empty_invalid() {
        for value in ["", "   ", "\t\n", "  \t  \n  "] {
            let message = trimmed_non_empty(&value, &()).unwrap_err().to_string();
            assert_eq!(
                message, "value cannot be empty or whitespace-only",
                "{value:?}"
            );
        }
    }

    #[test]
    fn test_trimmed_non_empty_opt_invalid() {
        for value in ["", "   ", "\t\n"] {
            let message = trimmed_non_empty_opt(&Some(value.to_string()), &())
                .unwrap_err()
                .to_string();
            assert_eq!(
                message, "value cannot be empty or whitespace-only",
                "{value:?}"
            );
        }
    }

    #[test]
    fn test_trimmed_non_empty_opt_valid() {
        for value in [None, Some("hello"), Some("  hello  ")] {
            assert!(
                trimmed_non_empty_opt(&value.map(str::to_string), &()).is_ok(),
                "{value:?}"
            );
        }
    }

    #[test]
    fn test_trimmed_non_empty_valid() {
        for value in ["hello", "  hello  ", "a"] {
            assert!(trimmed_non_empty(&value, &()).is_ok(), "{value:?}");
        }
    }

    #[test]
    fn test_valid_date_opt_invalid() {
        for year in [0, -5000, 10000] {
            let message = valid_date_opt(&NaiveDate::from_ymd_opt(year, 1, 1), &())
                .unwrap_err()
                .to_string();
            assert_eq!(message, "year must be between 1 and 9999", "{year}");
        }
    }

    #[test]
    fn test_valid_date_opt_valid() {
        for date in [
            None,
            NaiveDate::from_ymd_opt(1, 1, 1),
            NaiveDate::from_ymd_opt(2026, 9, 11),
            NaiveDate::from_ymd_opt(9999, 12, 31),
        ] {
            assert!(valid_date_opt(&date, &()).is_ok(), "{date:?}");
        }
    }

    #[test]
    fn test_valid_group_pretty_slug_invalid() {
        let too_long = "a".repeat(MAX_LEN_GROUP_PRETTY_SLUG + 1);
        let cases = [
            (
                "uppercase",
                "Pretty-Group",
                "Pretty slug must use lowercase ASCII letters, numbers, and hyphens only",
            ),
            (
                "underscore",
                "pretty_group",
                "Pretty slug must use lowercase ASCII letters, numbers, and hyphens only",
            ),
            (
                "leading hyphen",
                "-pretty-group",
                "Pretty slug must start and end with a lowercase ASCII letter or number",
            ),
            (
                "trailing hyphen",
                "pretty-group-",
                "Pretty slug must start and end with a lowercase ASCII letter or number",
            ),
            (
                "consecutive hyphens",
                "pretty--group",
                "Pretty slug cannot contain consecutive hyphens",
            ),
            (
                "too long",
                too_long.as_str(),
                "Pretty slug must be 50 characters or fewer",
            ),
        ];

        for (case, value, expected) in cases {
            let message = valid_group_pretty_slug(&Some(value.to_string()), &())
                .expect_err(case)
                .to_string();
            assert_eq!(message, expected, "{case}");
        }
    }

    #[test]
    fn test_valid_group_pretty_slug_valid() {
        let longest = "a".repeat(MAX_LEN_GROUP_PRETTY_SLUG);
        for (case, value) in [
            ("none", None),
            ("empty clears the slug", Some("")),
            ("blank clears the slug", Some("   ")),
            ("letters, numbers and hyphens", Some("pretty-group-2026")),
            ("longest", Some(longest.as_str())),
        ] {
            assert!(
                valid_group_pretty_slug(&value.map(str::to_string), &()).is_ok(),
                "{case}"
            );
        }
    }

    #[test]
    fn test_validate_trimmed_non_empty_vec_invalid() {
        let blank = "value cannot be empty or whitespace-only";
        let cases = [
            ("empty value", Some(strings(&[""])), MAX_LEN_TAG, blank),
            ("blank value", Some(strings(&["   "])), MAX_LEN_TAG, blank),
            (
                "valid then blank",
                Some(strings(&["valid", "   "])),
                MAX_LEN_TAG,
                blank,
            ),
            (
                "value longer than the limit",
                Some(vec!["a".repeat(MAX_LEN_TAG + 1)]),
                MAX_LEN_TAG,
                "value exceeds max length of 50",
            ),
            (
                "too many items",
                Some(vec!["tag".to_string(); MAX_ITEMS + 1]),
                MAX_LEN_TAG,
                "value exceeds max items of 25",
            ),
        ];

        for (case, value, max_len, expected) in cases {
            let message = validate_trimmed_non_empty_vec(&value, max_len)
                .expect_err(case)
                .to_string();
            assert_eq!(message, expected, "{case}");
        }
    }

    #[test]
    fn test_validate_trimmed_non_empty_vec_valid() {
        let cases = [
            ("none", None, MAX_LEN_TAG),
            ("one value", Some(strings(&["hello"])), MAX_LEN_M),
            ("two values", Some(strings(&["a", "b"])), MAX_LEN_M),
            ("padded value", Some(strings(&["  hello  "])), MAX_LEN_M),
            ("empty list", Some(strings(&[])), MAX_LEN_M),
            (
                "value within a larger limit",
                Some(vec!["a".repeat(MAX_LEN_TAG + 1)]),
                MAX_LEN_M,
            ),
            (
                "most items",
                Some(vec!["tag".to_string(); MAX_ITEMS]),
                MAX_LEN_TAG,
            ),
        ];

        for (case, value, max_len) in cases {
            assert!(
                validate_trimmed_non_empty_vec(&value, max_len).is_ok(),
                "{case}"
            );
        }
    }

    #[test]
    fn test_url_map_values_invalid() {
        let long_key = "a".repeat(MAX_LEN_LINK_LABEL + 1);
        let long_url = format!("https://example.com/{}", "a".repeat(MAX_LEN_L));
        let too_many: Vec<(String, &str)> = (0..=MAX_ITEMS)
            .map(|idx| (format!("key-{idx}"), "https://example.com"))
            .collect();
        let cases = [
            (
                "malformed",
                vec![("test".to_string(), "not-a-url")],
                "invalid URL for 'test': not-a-url".to_string(),
            ),
            (
                "empty",
                vec![("test".to_string(), "")],
                "URL for 'test' cannot be empty".to_string(),
            ),
            (
                "blank",
                vec![("test".to_string(), "   ")],
                "URL for 'test' cannot be empty".to_string(),
            ),
            (
                "valid and invalid",
                vec![
                    ("invalid".to_string(), "not-a-url"),
                    ("valid".to_string(), "https://example.com"),
                ],
                "invalid URL for 'invalid': not-a-url".to_string(),
            ),
            (
                "custom scheme",
                vec![("test".to_string(), "custom://example.com")],
                "invalid URL for 'test': custom://example.com".to_string(),
            ),
            (
                "data scheme",
                vec![("test".to_string(), "data:text/html,hello")],
                "invalid URL for 'test': data:text/html,hello".to_string(),
            ),
            (
                "file scheme",
                vec![("test".to_string(), "file:///tmp/file")],
                "invalid URL for 'test': file:///tmp/file".to_string(),
            ),
            (
                "javascript scheme",
                vec![("test".to_string(), "javascript:alert(1)")],
                "invalid URL for 'test': javascript:alert(1)".to_string(),
            ),
            (
                "root-relative path",
                vec![("test".to_string(), "/relative")],
                "invalid URL for 'test': /relative".to_string(),
            ),
            (
                "key too long",
                vec![(long_key.clone(), "https://example.com")],
                format!("key '{long_key}' exceeds max length of 80"),
            ),
            (
                "URL too long",
                vec![("test".to_string(), long_url.as_str())],
                "URL for 'test' exceeds max length of 2000".to_string(),
            ),
            (
                "too many items",
                too_many,
                "value exceeds max items of 25".to_string(),
            ),
        ];

        for (case, entries, expected) in cases {
            let map = entries.into_iter().map(|(key, url)| (key, url.to_string())).collect();
            let message = url_map_values(&Some(map), &()).expect_err(case).to_string();
            assert_eq!(message, expected, "{case}");
        }
    }

    #[test]
    fn test_url_map_values_valid() {
        let cases = [
            ("none", None),
            (
                "one link",
                Some(BTreeMap::from([(
                    "website".to_string(),
                    "https://example.com".to_string(),
                )])),
            ),
            (
                "two links",
                Some(BTreeMap::from([
                    (
                        "docs".to_string(),
                        "https://docs.example.com/path".to_string(),
                    ),
                    ("website".to_string(), "https://example.com".to_string()),
                ])),
            ),
            ("empty map", Some(BTreeMap::new())),
        ];

        for (case, value) in cases {
            assert!(url_map_values(&value, &()).is_ok(), "{case}");
        }
    }

    #[test]
    fn test_utm_value_vec_invalid() {
        let too_many = (0..=MAX_UTM_VALUES).map(|i| format!("value-{i}")).collect();
        let cases = [
            (
                "unsupported format",
                Some(strings(&["News Letter"])),
                "utm value 'News Letter' must have up to 50 lowercase letters, numbers, dots, hyphens, or underscores",
            ),
            (
                "duplicated value",
                Some(strings(&["newsletter", "newsletter"])),
                "utm value 'newsletter' is duplicated",
            ),
            (
                "too many items",
                Some(too_many),
                "value exceeds max items of 20",
            ),
        ];

        for (case, value, expected) in cases {
            let message = utm_value_vec(&value, &()).expect_err(case).to_string();
            assert_eq!(message, expected, "{case}");
        }
    }

    #[test]
    fn test_utm_value_vec_valid() {
        let most = (0..MAX_UTM_VALUES).map(|i| format!("value-{i}")).collect();
        for (case, value) in [
            ("none", None),
            ("most items", Some(most)),
            ("empty list", Some(strings(&[]))),
        ] {
            assert!(utm_value_vec(&value, &()).is_ok(), "{case}");
        }
    }

    #[test]
    fn test_valid_latitude_invalid() {
        for latitude in [90.1, -90.1, 180.0, -180.0] {
            let message = valid_latitude(&Some(latitude), &()).unwrap_err().to_string();
            assert_eq!(message, "latitude must be between -90 and 90", "{latitude}");
        }
    }

    #[test]
    fn test_valid_latitude_valid() {
        for latitude in [
            None,
            Some(0.0),
            Some(90.0),
            Some(-90.0),
            Some(45.5),
            Some(-45.5),
        ] {
            assert!(valid_latitude(&latitude, &()).is_ok(), "{latitude:?}");
        }
    }

    #[test]
    fn test_valid_longitude_invalid() {
        for longitude in [180.1, -180.1, 360.0] {
            let message = valid_longitude(&Some(longitude), &()).unwrap_err().to_string();
            assert_eq!(
                message, "longitude must be between -180 and 180",
                "{longitude}"
            );
        }
    }

    #[test]
    fn test_valid_longitude_valid() {
        for longitude in [
            None,
            Some(0.0),
            Some(180.0),
            Some(-180.0),
            Some(90.0),
            Some(-90.0),
        ] {
            assert!(valid_longitude(&longitude, &()).is_ok(), "{longitude:?}");
        }
    }

    #[test]
    fn test_valid_payment_recipient_invalid() {
        let pair = "payment recipient account and seller name must be provided together";
        let cases = [
            (
                "missing seller name",
                "acct_test".to_string(),
                String::new(),
                pair,
            ),
            (
                "missing account",
                String::new(),
                "Fiscal Sponsor".to_string(),
                pair,
            ),
            (
                "account too long",
                "a".repeat(MAX_LEN_M + 1),
                "Fiscal Sponsor".to_string(),
                "payment recipient account exceeds max length of 250",
            ),
            (
                "seller name too long",
                "acct_test".to_string(),
                "a".repeat(MAX_LEN_ENTITY_NAME + 1),
                "seller name exceeds max length of 120",
            ),
        ];

        for (case, recipient_id, seller_display_name, expected) in cases {
            let recipient = GroupPaymentRecipient {
                recipient_id,
                seller_display_name,
                ..GroupPaymentRecipient::default()
            };

            let message = valid_payment_recipient(&Some(recipient), &())
                .expect_err(case)
                .to_string();
            assert_eq!(message, expected, "{case}");
        }
    }

    #[test]
    fn test_valid_payment_recipient_valid() {
        let cases = [
            ("none", None),
            ("blank pair", Some(GroupPaymentRecipient::default())),
            (
                "account and seller name",
                Some(GroupPaymentRecipient {
                    recipient_id: "acct_test".to_string(),
                    seller_display_name: "Fiscal Sponsor".to_string(),
                    ..GroupPaymentRecipient::default()
                }),
            ),
        ];

        for (case, recipient) in cases {
            assert!(valid_payment_recipient(&recipient, &()).is_ok(), "{case}");
        }
    }

    #[test]
    fn test_web_url_opt_invalid() {
        for url in [
            "/relative",
            "//example.com",
            "custom://example.com",
            "data:text/html,hello",
            "file:///tmp/file",
            "javascript:alert(1)",
            "https://",
        ] {
            let message = web_url_opt(&Some(url.to_string()), &()).unwrap_err().to_string();
            assert_eq!(
                message,
                format!("URL must be an absolute HTTP or HTTPS URL: {url}"),
                "{url:?}"
            );
        }
    }

    #[test]
    fn test_web_url_opt_valid() {
        for url in [
            None,
            Some("https://example.com/path"),
            Some("http://example.com"),
        ] {
            assert!(
                web_url_opt(&url.map(str::to_string), &()).is_ok(),
                "{url:?}"
            );
        }
    }

    // Deserializers.

    #[derive(Debug, Deserialize)]
    struct OptionalDateTime {
        #[serde(default, deserialize_with = "blank_naive_datetime_as_none")]
        value: Option<NaiveDateTime>,
    }

    #[derive(Debug, Deserialize)]
    struct OptionalText {
        #[serde(default, deserialize_with = "blank_string_as_none")]
        value: Option<String>,
    }

    #[derive(Debug, Deserialize)]
    struct OptionalTimestamp {
        #[serde(default, deserialize_with = "blank_timestamp_seconds_as_none")]
        value: Option<DateTime<Utc>>,
    }

    #[test]
    fn test_blank_naive_datetime_as_none() {
        let at_18_30 = NaiveDate::from_ymd_opt(2099, 5, 1).unwrap().and_hms_opt(18, 30, 0);
        let cases = [
            ("absent", serde_json::json!({}), None),
            ("blank", serde_json::json!({ "value": "  " }), None),
            (
                "with seconds",
                serde_json::json!({ "value": "2099-05-01T18:30:00" }),
                at_18_30,
            ),
            (
                "without seconds",
                serde_json::json!({ "value": "2099-05-01T18:30" }),
                at_18_30,
            ),
        ];

        for (case, json, expected) in cases {
            let date: OptionalDateTime = serde_json::from_value(json).expect(case);
            assert_eq!(date.value, expected, "{case}");
        }
        let invalid = serde_json::json!({ "value": "tomorrow" });
        assert!(
            serde_json::from_value::<OptionalDateTime>(invalid).is_err(),
            "invalid"
        );
    }

    #[test]
    fn test_blank_string_as_none() {
        let cases = [
            ("absent", serde_json::json!({}), None),
            ("blank", serde_json::json!({ "value": "   " }), None),
            (
                "present keeps padding",
                serde_json::json!({ "value": "  rust  " }),
                Some("  rust  "),
            ),
        ];

        for (case, json, expected) in cases {
            let text: OptionalText = serde_json::from_value(json).expect(case);
            assert_eq!(text.value.as_deref(), expected, "{case}");
        }
    }

    #[test]
    fn test_blank_timestamp_seconds_as_none() {
        let cases = [
            ("absent", "", None),
            ("blank", "value=", None),
            (
                "present",
                "value=4081420800",
                DateTime::from_timestamp(4_081_420_800, 0),
            ),
        ];

        for (case, query, expected) in cases {
            let timestamp: OptionalTimestamp = serde_urlencoded::from_str(query).expect(case);
            assert_eq!(timestamp.value, expected, "{case}");
        }
        assert!(
            serde_urlencoded::from_str::<OptionalTimestamp>("value=soon").is_err(),
            "invalid"
        );
    }

    // Helpers.

    /// Returns the given values as owned strings.
    fn strings(values: &[&str]) -> Vec<String> {
        values.iter().map(ToString::to_string).collect()
    }
}
