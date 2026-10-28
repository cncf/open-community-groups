//! Template helper functions and utilities.
//!
//! This module provides utility functions used by templates for common tasks.

use num_format::{Locale, ToFormattedString};

use crate::util::base_url_without_trailing_slash;

/// Format for date-time inputs used by templates (YYYY-MM-DDTHH:MM).
pub(crate) const DATE_FORMAT: &str = "%Y-%m-%dT%H:%M";

/// The date format used in templates (YYYY-MM-DD).
pub(crate) const DATE_FORMAT_2: &str = "%Y-%m-%d";

/// Placeholder displayed when a metric does not apply.
pub(crate) const NOT_APPLICABLE_LABEL: &str = "-";

/// Builds an absolute URL from a configured base URL and path.
pub(crate) fn absolute_url(base_url: &str, path: &str) -> String {
    let base_url = base_url_without_trailing_slash(base_url);
    if path.starts_with('/') {
        format!("{base_url}{path}")
    } else {
        format!("{base_url}/{path}")
    }
}

/// Returns a bar width as a percentage of a total, clamped to 0 and 100.
#[allow(clippy::cast_precision_loss)]
pub(crate) fn bar_width(value: i64, total: i64) -> String {
    if total <= 0 {
        return "0".to_string();
    }
    let width = (value as f64 / total as f64 * 100.0).clamp(0.0, 100.0);
    format!("{width:.1}")
}

/// Formats a count with thousands separators.
pub(crate) fn count_label(count: i64) -> String {
    count.to_formatted_string(&Locale::en)
}

/// Builds the public URL for a configured Open Graph image.
pub(crate) fn open_graph_image_url(base_url: &str, image_url: &str) -> String {
    // Route uploaded images through the public Open Graph image endpoint
    if let Some(file_name) = image_url.strip_prefix("/images/") {
        return absolute_url(base_url, &format!("/images/og/{file_name}"));
    }

    // Convert other local paths into absolute URLs
    if image_url.starts_with('/') {
        return absolute_url(base_url, image_url);
    }

    // Keep already-absolute external URLs unchanged
    image_url.to_string()
}

/// Formats a ratio as a percentage, or as a dash when missing.
pub(crate) fn percent_label(value: Option<f64>) -> String {
    let Some(value) = value else {
        return NOT_APPLICABLE_LABEL.to_string();
    };
    let percent = value * 100.0;
    if percent >= 10.0 || (percent - percent.round()).abs() < f64::EPSILON {
        format!("{percent:.0}%")
    } else {
        format!("{percent:.1}%")
    }
}

/// Generates initials from a name and username.
pub(crate) fn user_initials(name: Option<&str>, username: &str) -> String {
    // Helper to split a string into words based on whitespace and non-alphabetic chars
    fn split_words(value: &str) -> Vec<&str> {
        value
            .trim()
            .split(|c: char| c.is_whitespace() || !c.is_alphabetic())
            .filter(|word| !word.is_empty())
            .collect()
    }

    // Helper to get the nth alphabetic character from a string, uppercased
    let get_nth_alpha = |s: &str, n: usize| {
        s.chars()
            .filter(|c| c.is_alphabetic())
            .nth(n)
            .map(|c| c.to_ascii_uppercase())
    };

    // Prefer name if available, otherwise derive from username
    let words = name
        .and_then(|name| {
            let words = split_words(name);
            if words.is_empty() { None } else { Some(words) }
        })
        .unwrap_or_else(|| split_words(username));

    // Generate initials based on number of words
    match words.len() {
        0 => "?".to_string(),
        1 => {
            // Single word: first two chars (one if only one letter)
            let first_word = words[0];
            match (get_nth_alpha(first_word, 0), get_nth_alpha(first_word, 1)) {
                (Some(first_char), Some(second_char)) => format!("{first_char}{second_char}"),
                (Some(first_char), None) => format!("{first_char}"),
                _ => "?".to_string(),
            }
        }
        _ => {
            // Two or more words: first char of first and last words
            let (first_word, last_word) = (words[0], words[words.len() - 1]);
            match (get_nth_alpha(first_word, 0), get_nth_alpha(last_word, 0)) {
                (Some(first_char), Some(second_char)) => format!("{first_char}{second_char}"),
                (Some(first_char), None) => format!("{first_char}"),
                (None, Some(second_char)) => format!("{second_char}"),
                _ => "?".to_string(),
            }
        }
    }
}

// Tests.

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_absolute_url_joins_base_url_and_path() {
        let cases = [
            (
                "rooted path",
                "https://example.test",
                "/events",
                "https://example.test/events",
            ),
            (
                "relative path",
                "https://example.test",
                "events",
                "https://example.test/events",
            ),
            (
                "base with trailing slash",
                "https://example.test/",
                "/events",
                "https://example.test/events",
            ),
        ];

        for (case, base_url, path, expected) in cases {
            assert_eq!(absolute_url(base_url, path), expected, "{case}");
        }
    }

    #[test]
    fn test_bar_width_clamps_to_the_total() {
        assert_eq!(bar_width(1, 4), "25.0");
        assert_eq!(bar_width(5, 4), "100.0");
        assert_eq!(bar_width(-1, 4), "0.0");
    }

    #[test]
    fn test_bar_width_is_zero_without_total() {
        assert_eq!(bar_width(3, 0), "0");
        assert_eq!(bar_width(3, -1), "0");
    }

    #[test]
    fn test_count_label_uses_thousands_separators() {
        assert_eq!(count_label(999), "999");
        assert_eq!(count_label(1_234_567), "1,234,567");
    }

    #[test]
    fn test_open_graph_image_url_resolves_image_locations() {
        let cases = [
            (
                "uploaded image",
                "/images/logo.png",
                "https://example.test/images/og/logo.png",
            ),
            (
                "other local path",
                "/static/images/default.png",
                "https://example.test/static/images/default.png",
            ),
            (
                "external URL",
                "https://cdn.example.org/logo.png",
                "https://cdn.example.org/logo.png",
            ),
        ];

        for (case, image_url, expected) in cases {
            assert_eq!(
                open_graph_image_url("https://example.test/", image_url),
                expected,
                "{case}"
            );
        }
    }

    #[test]
    fn test_percent_label_formats_ratios() {
        assert_eq!(percent_label(None), NOT_APPLICABLE_LABEL);
        assert_eq!(percent_label(Some(0.004)), "0.4%");
        assert_eq!(percent_label(Some(0.05)), "5%");
        assert_eq!(percent_label(Some(0.123)), "12%");
        assert_eq!(percent_label(Some(2.0)), "200%");
    }

    #[test]
    fn test_user_initials() {
        // Name present, two words -> first and last initials
        assert_eq!(user_initials(Some("John Doe"), ""), "JD");

        // Single-word name -> first two letters
        assert_eq!(user_initials(Some("Alice"), ""), "AL");

        // Single-letter name -> keep one letter
        assert_eq!(user_initials(Some("A"), ""), "A");

        // Leading and trailing spaces -> trimmed before processing
        assert_eq!(user_initials(Some("  Bob Johnson  "), ""), "BJ");

        // Multiple middle names -> still first and last
        assert_eq!(
            user_initials(Some("Alexander Graham Bell Hamilton"), ""),
            "AH"
        );

        // Hyphenated names -> treat as separate words
        assert_eq!(user_initials(Some("Mary-Jane Watson-Parker"), ""), "MP");

        // Name with no alphabetic characters in first name
        assert_eq!(user_initials(Some("123 Doe"), ""), "DO");

        // Name missing -> derive from username
        assert_eq!(user_initials(None, "jdoe"), "JD");

        // Name with no alphabetic characters -> fallback to username
        assert_eq!(user_initials(Some("123"), "alpha"), "AL");

        // Username with separators -> split into words
        assert_eq!(user_initials(None, "john_doe"), "JD");

        // Username without letters -> fallback placeholder
        assert_eq!(user_initials(None, "1234"), "?");
    }
}
