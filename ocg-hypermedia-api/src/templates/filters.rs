//! Some custom filters for templates.

use num_format::{Locale, ToFormattedString};
use unicode_segmentation::UnicodeSegmentation;

/// Return the string with all emojis removed.
#[allow(clippy::unnecessary_wraps)]
pub fn demoji(s: &str) -> askama::Result<String> {
    Ok(s.graphemes(true).filter(|gc| emojis::get(gc).is_none()).collect())
}

/// Format number according to international standards.
#[allow(clippy::unnecessary_wraps)]
pub fn num_fmt<T: ToFormattedString>(n: &T) -> askama::Result<String> {
    Ok(n.to_formatted_string(&Locale::en))
}
