//! Template helper functions and utilities.
//!
//! This module provides utility functions used by templates for common tasks like
//! building location strings, generating consistent colors for entities, and extracting
//! geolocation data from HTTP headers.

use std::hash::{DefaultHasher, Hash, Hasher};

// Location related helpers.
pub(crate) mod location;

/// Predefined color palette for visual entity identification.
///
/// These soft pastel colors are used to generate consistent visual identifiers for
/// entities like groups or events, particularly in placeholder images.
const COLORS: &[&str] = &["#FDC8B9", "#FBEDC1", "#D1E4C9", "#C4DAEE"];

/// Format for date-time inputs used by templates (YYYY-MM-DDTHH:MM).
pub(crate) const DATE_FORMAT: &str = "%Y-%m-%dT%H:%M";

/// The date format used in templates (YYYY-MM-DD).
pub(crate) const DATE_FORMAT_2: &str = "%Y-%m-%d";

/// Returns a consistent color for any hashable value.
///
/// Uses a hash function to deterministically map values to colors from the predefined
/// palette. Ensures the same input always produces the same color, useful for visual
/// consistency across the application.
pub(crate) fn color<T: Hash + ?Sized>(value: &T) -> &str {
    // Calculate the hash of the value
    let mut hasher = DefaultHasher::new();
    value.hash(&mut hasher);
    let hash = hasher.finish();

    // Pick one of the colors based on the hash
    #[allow(clippy::cast_possible_truncation)]
    COLORS[(hash % COLORS.len() as u64) as usize]
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_color() {
        let cases = [
            ("value2", COLORS[0]),
            ("value1", COLORS[1]),
            ("value3", COLORS[2]),
            ("value5", COLORS[3]),
        ];

        // Assert that the same input always yields the same color
        for (value, expected) in cases {
            assert_eq!(color(&value), expected);
        }
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
        assert_eq!(user_initials(Some("Alexander Graham Bell Hamilton"), ""), "AH");

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
