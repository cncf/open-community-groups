//! Custom Askama template filters.
//!
//! This module provides custom filters that can be used in Askama templates to
//! transform data during rendering. These filters extend Askama's built-in
//! functionality with application-specific formatting needs.

// Askama custom filter functions should return Result types.
#![allow(
    clippy::inline_always,
    clippy::trivially_copy_pass_by_ref,
    clippy::unnecessary_wraps,
    clippy::unused_self
)]

use chrono::{DateTime, Utc};
use chrono_tz::Tz;
use num_format::{Locale, ToFormattedString};
use tracing::error;
use unicode_segmentation::UnicodeSegmentation;

/// Returns the current alliance brand page path for alliance-prefixed public pages.
#[askama::filter_fn]
pub(crate) fn alliance_brand_path<S: AsRef<str>>(
    s: S,
    _: &dyn askama::Values,
) -> askama::Result<String> {
    let path = s.as_ref().trim_start_matches('/');
    let Some(alliance_slug) = path.split('/').next().filter(|segment| !segment.is_empty()) else {
        return Ok(String::new());
    };
    let reserved_roots = [
        "about",
        "alliances",
        "api",
        "dashboard",
        "docs",
        "event",
        "explore",
        "favicon.ico",
        "health-check",
        "images",
        "jobs",
        "landscape",
        "log-in",
        "privacy",
        "profiles",
        "search",
        "sign-up",
        "sponsor",
        "static",
        "stats",
        "wiki",
    ];

    if reserved_roots.contains(&alliance_slug) || alliance_slug.contains('.') {
        return Ok(String::new());
    }

    Ok(format!("/{alliance_slug}/brand"))
}

/// Removes all emoji characters from a string.
#[askama::filter_fn]
pub(crate) fn demoji<S: AsRef<str>>(s: S, _: &dyn askama::Values) -> askama::Result<String> {
    Ok(s.as_ref()
        .graphemes(true)
        .filter(|gc| emojis::get(gc).is_none())
        .collect())
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

/// Displays the public label for a landscape entry kind.
#[askama::filter_fn]
pub(crate) fn landscape_kind_label<S: AsRef<str>>(
    kind: S,
    _: &dyn askama::Values,
) -> askama::Result<String> {
    let label = match kind.as_ref() {
        "github_project" => "GitHub project",
        "investor" => "Investor",
        "partner_community" => "Partner community",
        "podcast_lead" => "Podcast lead",
        "startup" => "Startup",
        other => other,
    };
    Ok(label.to_string())
}

// Tests.

#[cfg(test)]
mod tests {
    use chrono::TimeZone;

    use super::*;

    #[test]
    fn test_alliance_brand_path() {
        let values = askama::NO_VALUES;

        assert_eq!(
            alliance_brand_path::default()
                .execute("/goup/group/builders", values)
                .unwrap(),
            "/goup/brand"
        );
        assert_eq!(
            alliance_brand_path::default().execute("/goup", values).unwrap(),
            "/goup/brand"
        );
        assert_eq!(
            alliance_brand_path::default().execute("/jobs", values).unwrap(),
            ""
        );
        assert_eq!(
            alliance_brand_path::default().execute("/sponsor", values).unwrap(),
            ""
        );
        assert_eq!(
            alliance_brand_path::default().execute("/docs", values).unwrap(),
            ""
        );
        assert_eq!(
            alliance_brand_path::default().execute("/", values).unwrap(),
            ""
        );
    }

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
        assert_eq!(
            demoji::default().execute("👨‍👩‍👧‍👦Family", values).unwrap(),
            "Family"
        );
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

    #[test]
    fn test_landscape_kind_label() {
        let values = askama::NO_VALUES;

        assert_eq!(
            landscape_kind_label::default()
                .execute("partner_community", values)
                .unwrap(),
            "Partner community"
        );
        assert_eq!(
            landscape_kind_label::default()
                .execute("podcast_lead", values)
                .unwrap(),
            "Podcast lead"
        );
        assert_eq!(
            landscape_kind_label::default().execute("investor", values).unwrap(),
            "Investor"
        );
    }
}
