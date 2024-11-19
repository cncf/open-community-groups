//! Some custom filters for templates.

use unicode_segmentation::UnicodeSegmentation;

/// Return the string with all emojis removed.
#[allow(clippy::unnecessary_wraps)]
pub fn demoji(s: &str) -> askama::Result<String> {
    Ok(s.graphemes(true).filter(|gc| emojis::get(gc).is_none()).collect())
}
