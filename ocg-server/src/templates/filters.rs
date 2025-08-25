//! Custom Askama template filters.
//!
//! This module provides custom filters that can be used in Askama templates to
//! transform data during rendering. These filters extend Askama's built-in
//! functionality with application-specific formatting needs.

use chrono::{DateTime, Utc};
use num_format::{Locale, ToFormattedString};
use unicode_segmentation::UnicodeSegmentation;

use crate::templates::common::User;

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
#[allow(clippy::unnecessary_wraps, clippy::ref_option, dead_code)]
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

/// Formats numbers with thousands separators.
#[allow(clippy::unnecessary_wraps)]
pub(crate) fn num_fmt<T: ToFormattedString>(n: &T, _: &dyn askama::Values) -> askama::Result<String> {
    Ok(n.to_formatted_string(&Locale::en))
}

/// Gets initials from a User with specified count.
///
/// Extracts initials from the user's name:
/// - If count is 1: Returns first letter of name
/// - If count is 2: Returns first letter of first word + first letter of last word
///
/// Usage in templates:
/// - For 2 initials: {{ `user|user_initials(2)` }}
/// - For 1 initial: {{ `user|user_initials(1)` }}
#[allow(clippy::unnecessary_wraps)]
pub(crate) fn user_initials(user: &User, _: &dyn askama::Values, count: usize) -> askama::Result<String> {
    let mut initials = String::new();

    if let Some(name) = &user.name {
        let words: Vec<&str> = name.split_whitespace().collect();

        // Get first initial
        if let Some(first_word) = words.first()
            && let Some(first_char) = first_word.chars().next()
            && first_char.is_alphabetic()
        {
            initials.push(first_char.to_ascii_uppercase());
        }

        // Get second initial if count >= 2 and there are multiple words
        if count >= 2
            && words.len() > 1
            && let Some(last_word) = words.last()
            && let Some(first_char) = last_word.chars().next()
            && first_char.is_alphabetic()
        {
            initials.push(first_char.to_ascii_uppercase());
        }
    }

    Ok(initials)
}

#[cfg(test)]
mod tests {
    use uuid::Uuid;

    use super::*;

    fn create_user(name: Option<&str>) -> User {
        User {
            user_id: Uuid::new_v4(),
            name: name.map(str::to_string),
            company: None,
            title: None,
            photo_url: None,
            facebook_url: None,
            linkedin_url: None,
            twitter_url: None,
            website_url: None,
        }
    }

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

    #[test]
    fn test_user_initials() {
        // Test with full name (count 2)
        let user = create_user(Some("John Doe"));
        assert_eq!(user_initials(&user, &() as &dyn askama::Values, 2).unwrap(), "JD");

        // Test with single name (count 2)
        let user = create_user(Some("Alice"));
        assert_eq!(user_initials(&user, &() as &dyn askama::Values, 2).unwrap(), "A");

        // Test with no name (count 2)
        let user = create_user(None);
        assert_eq!(user_initials(&user, &() as &dyn askama::Values, 2).unwrap(), "");

        // Test with names that have leading/trailing spaces (count 2)
        let user = create_user(Some("  Bob Johnson  "));
        assert_eq!(user_initials(&user, &() as &dyn askama::Values, 2).unwrap(), "BJ");

        // Test with three-word name (count 2) - should get first and last
        let user = create_user(Some("John Jacob Smith"));
        assert_eq!(user_initials(&user, &() as &dyn askama::Values, 2).unwrap(), "JS");

        // Test with count of 1 - should get only first initial
        let user = create_user(Some("Jane Doe"));
        assert_eq!(user_initials(&user, &() as &dyn askama::Values, 1).unwrap(), "J");

        // Test with count of 1 and single name
        let user = create_user(Some("Alice"));
        assert_eq!(user_initials(&user, &() as &dyn askama::Values, 1).unwrap(), "A");

        // Test with multiple middle names
        let user = create_user(Some("Alexander Graham Bell Hamilton"));
        assert_eq!(user_initials(&user, &() as &dyn askama::Values, 2).unwrap(), "AH");
    }
}
