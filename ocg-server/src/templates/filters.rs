//! Custom Askama template filters.
//!
//! This module provides custom filters that can be used in Askama templates to
//! transform data during rendering. These filters extend Askama's built-in
//! functionality with application-specific formatting needs.

use chrono::{DateTime, Utc};
use chrono_tz::Tz;
use num_format::{Locale, ToFormattedString};
use tracing::error;
use unicode_segmentation::UnicodeSegmentation;

/// Removes all emoji characters from a string.
#[allow(clippy::unnecessary_wraps)]
pub(crate) fn demoji(s: &str, _: &dyn askama::Values) -> askama::Result<String> {
    Ok(s.graphemes(true).filter(|gc| emojis::get(gc).is_none()).collect())
}

/// Display the value if present, otherwise return an empty string.
#[allow(clippy::unnecessary_wraps, clippy::ref_option)]
pub(crate) fn display_some<T>(value: &Option<T>, _: &dyn askama::Values) -> askama::Result<String>
where
    T: std::fmt::Display,
{
    match value {
        Some(value) => Ok(value.to_string()),
        None => Ok(String::new()),
    }
}

/// Display the formatted datetime if present, otherwise return an empty string.
#[allow(clippy::unnecessary_wraps, clippy::ref_option)]
pub(crate) fn display_some_datetime(
    value: &Option<DateTime<Utc>>,
    _: &dyn askama::Values,
    format: &str,
) -> askama::Result<String> {
    match value {
        Some(value) => Ok(value.format(format).to_string()),
        None => Ok(String::new()),
    }
}

/// Display the formatted datetime in the provided timezone if present, otherwise
/// return an empty string.
#[allow(clippy::unnecessary_wraps, clippy::ref_option, dead_code)]
pub(crate) fn display_some_datetime_tz(
    value: &Option<DateTime<Utc>>,
    _: &dyn askama::Values,
    format: &str,
    timezone: Tz,
) -> askama::Result<String> {
    match value {
        Some(value) => Ok(value.with_timezone(&timezone).format(format).to_string()),
        None => Ok(String::new()),
    }
}

/// Display the value if present, otherwise return the provided alternative value.
#[allow(clippy::unnecessary_wraps, clippy::ref_option)]
pub(crate) fn display_some_or<T, U>(
    value: &Option<T>,
    _: &dyn askama::Values,
    alternative: U,
) -> askama::Result<String>
where
    T: std::fmt::Display,
    U: std::fmt::Display,
{
    match value {
        Some(value) => Ok(value.to_string()),
        None => Ok(alternative.to_string()),
    }
}

/// Convert a markdown string to HTML using GitHub Flavored Markdown options.
#[allow(clippy::unnecessary_wraps, clippy::ref_option)]
pub(crate) fn md_to_html(s: &str, _: &dyn askama::Values) -> askama::Result<String> {
    let options = markdown::Options::gfm();
    match markdown::to_html_with_options(s, &options) {
        Ok(html) => Ok(html),
        Err(e) => {
            error!("error converting markdown to html: {}", e);
            Ok("error converting markdown to html".to_string())
        }
    }
}

/// Formats numbers with thousands separators.
#[allow(clippy::unnecessary_wraps)]
pub(crate) fn num_fmt<T: ToFormattedString>(n: &T, _: &dyn askama::Values) -> askama::Result<String> {
    Ok(n.to_formatted_string(&Locale::en))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_demoji() {
        // Basic emoji removal
        assert_eq!(demoji("🙂Hi👋", &()).unwrap(), "Hi");

        // Multiple emojis
        assert_eq!(demoji("🎉Test🎊String🎈", &()).unwrap(), "TestString");

        // No emojis
        assert_eq!(demoji("Hello World", &()).unwrap(), "Hello World");

        // Only emojis
        assert_eq!(demoji("😀😃😄😁", &()).unwrap(), "");

        // Mixed with special characters
        assert_eq!(
            demoji("Hello! 👋 How are you? 😊", &()).unwrap(),
            "Hello!  How are you? "
        );

        // Complex emojis (multi-codepoint)
        assert_eq!(demoji("👨‍👩‍👧‍👦Family", &()).unwrap(), "Family");
    }

    #[test]
    fn test_num_fmt() {
        // Basic formatting
        assert_eq!(num_fmt(&123_456_789, &()).unwrap(), "123,456,789");

        // Small numbers
        assert_eq!(num_fmt(&999, &()).unwrap(), "999");
        assert_eq!(num_fmt(&1_000, &()).unwrap(), "1,000");

        // Zero
        assert_eq!(num_fmt(&0, &()).unwrap(), "0");

        // Large numbers
        assert_eq!(num_fmt(&1_234_567_890, &()).unwrap(), "1,234,567,890");

        // Different integer types
        assert_eq!(num_fmt(&1_234u32, &()).unwrap(), "1,234");
        assert_eq!(num_fmt(&1_234i64, &()).unwrap(), "1,234");
    }
}
