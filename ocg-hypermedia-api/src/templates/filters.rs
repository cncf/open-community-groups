//! Some custom filters and helpers for templates.

use std::hash::{DefaultHasher, Hash, Hasher};

use num_format::{Locale, ToFormattedString};
use unicode_segmentation::UnicodeSegmentation;

/// Colors used to make it easier to identify some entities. We use them as the
/// tint for placeholder images, for example.
const COLORS: &[&str] = &["#FDC8B9", "#FBEDC1", "#D1E4C9", "#C4DAEE"];

/// Get the color corresponding to the value provided. The same value should
/// always return the same color.
pub(crate) fn color<T: Hash + ?Sized>(value: &T) -> &str {
    // Calculate the hash of the value
    let mut hasher = DefaultHasher::new();
    value.hash(&mut hasher);
    let hash = hasher.finish();

    // Pick one of the colors based on the hash
    #[allow(clippy::cast_possible_truncation)]
    COLORS[(hash % COLORS.len() as u64) as usize]
}

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
    use super::{color, demoji, num_fmt, COLORS};

    macro_rules! color_tests {
        ($(
            $name:ident: $value:expr => $expected:expr
        ),*) => {
            $(
                #[test]
                fn $name() {
                    assert_eq!(color($value), $expected);
                }
            )*
        };
    }

    color_tests! {
        color_1: "value2" => COLORS[0],
        color_2: "value1" => COLORS[1],
        color_3: "value3" => COLORS[2],
        color_4: "value5" => COLORS[3]
    }

    #[test]
    fn test_demoji() {
        assert_eq!(demoji("🙂Hi👋").unwrap(), "Hi");
    }

    #[test]
    fn test_num_fmt() {
        assert_eq!(num_fmt(&123_456_789).unwrap(), "123,456,789");
    }
}
