//! Custom Askama template filters.
//!
//! This module provides custom filters that can be used in Askama templates to
//! transform data during rendering. These filters extend Askama's built-in
//! functionality with application-specific formatting needs.

// Askama custom filter functions should return Result types.
#![allow(clippy::unnecessary_wraps)]

use chrono::{DateTime, Utc};
use chrono_tz::Tz;
use num_format::{Locale, ToFormattedString};
use tracing::error;
use unicode_segmentation::UnicodeSegmentation;

/// Removes all emoji characters from a string.
#[askama::filter_fn]
pub(crate) fn demoji(s: &str, _: &dyn askama::Values) -> askama::Result<String> {
    Ok(s.graphemes(true).filter(|gc| emojis::get(gc).is_none()).collect())
}

/// Display the formatted datetime in the provided timezone if present, otherwise
/// return an empty string.
#[askama::filter_fn]
#[allow(clippy::ref_option)]
pub(crate) fn display_some_datetime_tz(
    value: &Option<DateTime<Utc>>,
    _: &dyn askama::Values,
    format: &str,
    timezone: Tz,
) -> askama::Result<String> {
    Ok(match value.as_ref() {
        Some(value) => value.with_timezone(&timezone).format(format).to_string(),
        None => String::new(),
    })
}

/// Convert a markdown string to HTML using GitHub Flavored Markdown options.
#[askama::filter_fn]
pub(crate) fn md_to_html(s: &str, _: &dyn askama::Values) -> askama::Result<String> {
    let options = markdown::Options::gfm();
    Ok(match markdown::to_html_with_options(s, &options) {
        Ok(html) => html,
        Err(e) => {
            error!("error converting markdown to html: {}", e);
            "error converting markdown to html".to_string()
        }
    })
}

/// Formats numbers with thousands separators.
#[askama::filter_fn]
pub(crate) fn num_fmt(n: &i64, _: &dyn askama::Values) -> askama::Result<String> {
    Ok(n.to_formatted_string(&Locale::en))
}

// Tests.

#[cfg(test)]
mod tests {
    use chrono::TimeZone;

    use super::*;

    #[test]
    fn test_demoji() {
        let values = askama::NO_VALUES;

        // Basic emoji removal
        assert_eq!(demoji::default().execute("🙂Hi👋", values).unwrap(), "Hi");

        // Multiple emojis
        assert_eq!(
            demoji::default().execute("🎉Test🎊String🎈", values).unwrap(),
            "TestString"
        );

        // No emojis
        assert_eq!(
            demoji::default().execute("Hello World", values).unwrap(),
            "Hello World"
        );

        // Only emojis
        assert_eq!(demoji::default().execute("😀😃😄😁", values).unwrap(), "");

        // Mixed with special characters
        assert_eq!(
            demoji::default()
                .execute("Hello! 👋 How are you? 😊", values)
                .unwrap(),
            "Hello!  How are you? "
        );

        // Complex emojis (multi-codepoint)
        assert_eq!(demoji::default().execute("👨‍👩‍👧‍👦Family", values).unwrap(), "Family");
    }

    #[test]
    fn test_display_some_datetime_tz() {
        let values = askama::NO_VALUES;
        let datetime = Some(Utc.with_ymd_and_hms(2024, 1, 5, 18, 15, 0).unwrap());
        let timezone = chrono_tz::America::New_York;

        let formatted = display_some_datetime_tz::default()
            .with_format("%Y-%m-%d %H:%M")
            .with_timezone(timezone)
            .execute(&datetime, values)
            .unwrap();
        assert_eq!(formatted, "2024-01-05 13:15");

        let empty = display_some_datetime_tz::default()
            .with_format("%Y-%m-%d")
            .with_timezone(timezone)
            .execute(&None, values)
            .unwrap();
        assert_eq!(empty, "");
    }

    #[test]
    fn test_md_to_html() {
        let values = askama::NO_VALUES;

        assert_eq!(
            md_to_html::default().execute("# Title", values).unwrap(),
            "<h1>Title</h1>"
        );
        assert_eq!(
            md_to_html::default().execute("Plain text", values).unwrap(),
            "<p>Plain text</p>"
        );
    }

    #[test]
    fn test_num_fmt() {
        let values = askama::NO_VALUES;

        // Basic formatting
        assert_eq!(
            num_fmt::default().execute(&123_456_789, values).unwrap(),
            "123,456,789"
        );

        // Small numbers
        assert_eq!(num_fmt::default().execute(&999, values).unwrap(), "999");
        assert_eq!(num_fmt::default().execute(&1_000, values).unwrap(), "1,000");

        // Zero
        assert_eq!(num_fmt::default().execute(&0, values).unwrap(), "0");

        // Large numbers
        assert_eq!(
            num_fmt::default().execute(&1_234_567_890, values).unwrap(),
            "1,234,567,890"
        );
    }
}
