//! Some custom filters for templates.

use num_format::{Locale, ToFormattedString};
use unicode_segmentation::UnicodeSegmentation;

/// Return the string with all emojis removed.
#[allow(clippy::unnecessary_wraps)]
pub(crate) fn demoji(s: &str) -> askama::Result<String> {
    Ok(s.graphemes(true).filter(|gc| emojis::get(gc).is_none()).collect())
}

/// Format number according to international standards.
#[allow(clippy::unnecessary_wraps)]
pub(crate) fn num_fmt<T: ToFormattedString>(n: &T) -> askama::Result<String> {
    Ok(n.to_formatted_string(&Locale::en))
}

#[cfg(test)]
mod tests {
    use super::{demoji, num_fmt};

    #[test]
    fn test_demoji() {
        assert_eq!(demoji("🙂Hi👋").unwrap(), "Hi");
    }

    #[test]
    fn test_num_fmt() {
        assert_eq!(num_fmt(&123_456_789).unwrap(), "123,456,789");
    }
}
