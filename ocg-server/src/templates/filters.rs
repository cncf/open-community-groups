//! Custom Askama template filters.
//!
//! This module provides custom filters that can be used in Askama templates to
//! transform data during rendering. These filters extend Askama's built-in
//! functionality with application-specific formatting needs.

use crate::templates::common::User;
use num_format::{Locale, ToFormattedString};
use unicode_segmentation::UnicodeSegmentation;

/// Removes all emoji characters from a string.
#[allow(clippy::unnecessary_wraps)]
pub(crate) fn demoji(s: &str, _: &dyn askama::Values) -> askama::Result<String> {
    Ok(s.graphemes(true).filter(|gc| emojis::get(gc).is_none()).collect())
}

/// Formats numbers with thousands separators.
#[allow(clippy::unnecessary_wraps)]
pub(crate) fn num_fmt<T: ToFormattedString>(n: &T, _: &dyn askama::Values) -> askama::Result<String> {
    Ok(n.to_formatted_string(&Locale::en))
}

/// Gets the full name of a User.
///
/// Returns the user's full name in the format "First Last".
/// - If only first name exists, returns just the first name
/// - If only last name exists, returns just the last name
/// - If neither exists, returns an empty string
///
/// Usage in templates:
/// {{ `user|full_name` }}
#[allow(clippy::unnecessary_wraps)]
pub(crate) fn full_name(user: &User, _: &dyn askama::Values) -> askama::Result<String> {
    match (&user.first_name, &user.last_name) {
        (Some(first), Some(last)) => Ok(format!("{} {}", first.trim(), last.trim())),
        (Some(first), None) => Ok(first.trim().to_string()),
        (None, Some(last)) => Ok(last.trim().to_string()),
        (None, None) => Ok(String::new()),
    }
}

/// Gets initials from a User with specified count.
///
/// Extracts initials from the user's first and last names:
/// - If count is 1: Returns first letter of first name (or last name if no first name)
/// - If count is 2: Returns first letter of first name + first letter of last name
///
/// Usage in templates:
/// - For 2 initials: {{ `user|user_initials(2)` }}
/// - For 1 initial: {{ `user|user_initials(1)` }}
///
/// Note: Askama passes Values as second argument when filter has parameters.
#[allow(clippy::unnecessary_wraps)]
pub(crate) fn user_initials(user: &User, _: &dyn askama::Values, count: usize) -> askama::Result<String> {
    let mut initials = String::new();

    // Get the first character of first name
    if let Some(first_name) = &user.first_name
        && let Some(first_char) = first_name.trim().chars().next()
        && first_char.is_alphabetic()
    {
        initials.push(first_char.to_ascii_uppercase());
    }

    // If count is 2 and we need a second initial, get first character of last name
    if count >= 2
        && initials.len() < 2
        && let Some(last_name) = &user.last_name
        && let Some(first_char) = last_name.trim().chars().next()
        && first_char.is_alphabetic()
    {
        initials.push(first_char.to_ascii_uppercase());
    }

    // If no first name but we have a last name, use it as the first initial
    if initials.is_empty()
        && let Some(last_name) = &user.last_name
        && let Some(first_char) = last_name.trim().chars().next()
        && first_char.is_alphabetic()
    {
        initials.push(first_char.to_ascii_uppercase());
    }

    Ok(initials)
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

    #[test]
    fn test_full_name() {
        use uuid::Uuid;

        // Test with both first and last name
        let user = User {
            id: Uuid::new_v4(),
            first_name: Some("John".to_string()),
            last_name: Some("Doe".to_string()),
            company: None,
            title: None,
            photo_url: None,
            facebook_url: None,
            linkedin_url: None,
            twitter_url: None,
            website_url: None,
        };
        assert_eq!(full_name(&user, &()).unwrap(), "John Doe");

        // Test with only first name
        let user = User {
            id: Uuid::new_v4(),
            first_name: Some("Alice".to_string()),
            last_name: None,
            company: None,
            title: None,
            photo_url: None,
            facebook_url: None,
            linkedin_url: None,
            twitter_url: None,
            website_url: None,
        };
        assert_eq!(full_name(&user, &()).unwrap(), "Alice");

        // Test with only last name
        let user = User {
            id: Uuid::new_v4(),
            first_name: None,
            last_name: Some("Smith".to_string()),
            company: None,
            title: None,
            photo_url: None,
            facebook_url: None,
            linkedin_url: None,
            twitter_url: None,
            website_url: None,
        };
        assert_eq!(full_name(&user, &()).unwrap(), "Smith");

        // Test with no names
        let user = User {
            id: Uuid::new_v4(),
            first_name: None,
            last_name: None,
            company: None,
            title: None,
            photo_url: None,
            facebook_url: None,
            linkedin_url: None,
            twitter_url: None,
            website_url: None,
        };
        assert_eq!(full_name(&user, &()).unwrap(), "");

        // Test with names that have leading/trailing spaces
        let user = User {
            id: Uuid::new_v4(),
            first_name: Some("  Bob  ".to_string()),
            last_name: Some("  Johnson  ".to_string()),
            company: None,
            title: None,
            photo_url: None,
            facebook_url: None,
            linkedin_url: None,
            twitter_url: None,
            website_url: None,
        };
        assert_eq!(full_name(&user, &()).unwrap(), "Bob Johnson");
    }

    #[test]
    fn test_user_initials() {
        use uuid::Uuid;

        // Test with both first and last name (default 2 initials)
        let user = User {
            id: Uuid::new_v4(),
            first_name: Some("John".to_string()),
            last_name: Some("Doe".to_string()),
            company: None,
            title: None,
            photo_url: None,
            facebook_url: None,
            linkedin_url: None,
            twitter_url: None,
            website_url: None,
        };
        assert_eq!(user_initials(&user, &() as &dyn askama::Values, 2).unwrap(), "JD");

        // Test with only first name
        let user = User {
            id: Uuid::new_v4(),
            first_name: Some("Alice".to_string()),
            last_name: None,
            company: None,
            title: None,
            photo_url: None,
            facebook_url: None,
            linkedin_url: None,
            twitter_url: None,
            website_url: None,
        };
        assert_eq!(user_initials(&user, &() as &dyn askama::Values, 2).unwrap(), "A");

        // Test with only last name
        let user = User {
            id: Uuid::new_v4(),
            first_name: None,
            last_name: Some("Smith".to_string()),
            company: None,
            title: None,
            photo_url: None,
            facebook_url: None,
            linkedin_url: None,
            twitter_url: None,
            website_url: None,
        };
        assert_eq!(user_initials(&user, &() as &dyn askama::Values, 2).unwrap(), "S");

        // Test with no names
        let user = User {
            id: Uuid::new_v4(),
            first_name: None,
            last_name: None,
            company: None,
            title: None,
            photo_url: None,
            facebook_url: None,
            linkedin_url: None,
            twitter_url: None,
            website_url: None,
        };
        assert_eq!(user_initials(&user, &() as &dyn askama::Values, 2).unwrap(), "");

        // Test with names that have leading/trailing spaces
        let user = User {
            id: Uuid::new_v4(),
            first_name: Some("  Bob  ".to_string()),
            last_name: Some("  Johnson  ".to_string()),
            company: None,
            title: None,
            photo_url: None,
            facebook_url: None,
            linkedin_url: None,
            twitter_url: None,
            website_url: None,
        };
        assert_eq!(user_initials(&user, &() as &dyn askama::Values, 2).unwrap(), "BJ");

        // Test with single character names
        let user = User {
            id: Uuid::new_v4(),
            first_name: Some("X".to_string()),
            last_name: Some("Y".to_string()),
            company: None,
            title: None,
            photo_url: None,
            facebook_url: None,
            linkedin_url: None,
            twitter_url: None,
            website_url: None,
        };
        assert_eq!(user_initials(&user, &() as &dyn askama::Values, 2).unwrap(), "XY");
    }

    #[test]
    fn test_user_initials_with_count() {
        use uuid::Uuid;

        // Test with count of 1 - should get only first name initial
        let user = User {
            id: Uuid::new_v4(),
            first_name: Some("Jane".to_string()),
            last_name: Some("Doe".to_string()),
            company: None,
            title: None,
            photo_url: None,
            facebook_url: None,
            linkedin_url: None,
            twitter_url: None,
            website_url: None,
        };
        assert_eq!(user_initials(&user, &() as &dyn askama::Values, 1).unwrap(), "J");

        // Test with count of 3
        let user = User {
            id: Uuid::new_v4(),
            first_name: Some("Alexander".to_string()),
            last_name: Some("Hamilton".to_string()),
            company: None,
            title: None,
            photo_url: None,
            facebook_url: None,
            linkedin_url: None,
            twitter_url: None,
            website_url: None,
        };
        // With our new logic, count > 2 still returns only first + last initials
        assert_eq!(user_initials(&user, &() as &dyn askama::Values, 3).unwrap(), "AH");

        // Test with count of 1 and only first name
        let user = User {
            id: Uuid::new_v4(),
            first_name: Some("Alice".to_string()),
            last_name: None,
            company: None,
            title: None,
            photo_url: None,
            facebook_url: None,
            linkedin_url: None,
            twitter_url: None,
            website_url: None,
        };
        assert_eq!(user_initials(&user, &() as &dyn askama::Values, 1).unwrap(), "A");

        // Test with count of 1 and only last name
        let user = User {
            id: Uuid::new_v4(),
            first_name: None,
            last_name: Some("Smith".to_string()),
            company: None,
            title: None,
            photo_url: None,
            facebook_url: None,
            linkedin_url: None,
            twitter_url: None,
            website_url: None,
        };
        assert_eq!(user_initials(&user, &() as &dyn askama::Values, 1).unwrap(), "S");

        // Test with count of 4 with only first name
        let user = User {
            id: Uuid::new_v4(),
            first_name: Some("Margaret".to_string()),
            last_name: None,
            company: None,
            title: None,
            photo_url: None,
            facebook_url: None,
            linkedin_url: None,
            twitter_url: None,
            website_url: None,
        };
        // With our new logic, count > 2 still returns only the first initial when no last name
        assert_eq!(user_initials(&user, &() as &dyn askama::Values, 4).unwrap(), "M");
    }
}
