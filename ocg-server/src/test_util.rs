//! Test helpers that belong to no layer: byte fixtures, text normalization,
//! rendered-HTML scanning, and polling.

use std::{io::Cursor, iter, ops::Range, time::Duration};

use image::{DynamicImage, ImageFormat};
use tokio::time::{sleep, timeout};

/// HTML elements that never take a closing tag.
const VOID_ELEMENTS: [&str; 13] = [
    "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track",
    "wbr",
];

/// Returns the rendered element whose opening tag contains `needle`, from the
/// opening tag through its matching closing tag.
///
/// Void and self-closed elements return the opening tag alone. Nested
/// elements with the same name are counted. This is a heuristic scanner, not
/// an HTML parser: comments are skipped, but `<script>` text or unbalanced
/// markup can confuse it. Panics when no opening tag contains `needle` or the
/// element is not closed.
pub(crate) fn element_html_with<'a>(html: &'a str, needle: &str) -> &'a str {
    // Locate the opening tag and read its element name
    let tag = opening_tag_range_with(html, needle);
    let opening_tag = &html[tag.clone()];
    let name = tag_name(opening_tag);

    // Return void and self-closed elements as the opening tag alone
    if VOID_ELEMENTS.iter().any(|void| void.eq_ignore_ascii_case(name))
        || is_self_closed(opening_tag)
    {
        return opening_tag;
    }

    // Count nested same-name elements until the matching closing tag
    let rest = &html[tag.end..];
    let mut depth = 1;
    for range in markup_ranges(rest) {
        let markup = &rest[range.clone()];
        if !tag_name(markup).eq_ignore_ascii_case(name) {
            continue;
        }
        if markup.starts_with("</") {
            depth -= 1;
            if depth == 0 {
                return &html[tag.start..tag.end + range.end];
            }
        } else if !is_self_closed(markup) {
            depth += 1;
        }
    }
    panic!("element whose opening tag contains {needle} is not closed");
}

/// Returns the whitespace-normalized text of the rendered element whose
/// opening tag contains `needle`.
///
/// Tags and comments are stripped and entities stay as rendered. This shares
/// the limits of [`element_html_with`]: it is a heuristic scanner, not an
/// HTML parser, and `<script>` text can confuse it.
pub(crate) fn element_text_with(html: &str, needle: &str) -> String {
    // Collect the text between the element's tags and comments
    let element = element_html_with(html, needle);
    let mut text = String::with_capacity(element.len());
    let mut text_start = 0;
    for range in markup_ranges(element) {
        text.push_str(&element[text_start..range.start]);
        text_start = range.end;
    }
    text.push_str(&element[text_start..]);

    normalize_whitespace(&text)
}

/// Collapses whitespace runs so rendered text can be matched exactly.
pub(crate) fn normalize_whitespace(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Returns the first full rendered opening tag, from `<` through `>`, whose
/// text contains `needle`.
///
/// The closing `>` is found outside quoted attribute values, so Alpine and
/// htmx expressions are kept whole, and a needle that only occurs in text
/// content never matches. This is a heuristic scanner, not an HTML parser:
/// comments are skipped, but `<script>` text can confuse it. Panics when no
/// opening tag contains `needle`.
pub(crate) fn opening_tag_with<'a>(html: &'a str, needle: &str) -> &'a str {
    &html[opening_tag_range_with(html, needle)]
}

/// Encodes a transparent PNG image with the given dimensions.
pub(crate) fn sample_png(width: u32, height: u32) -> Vec<u8> {
    let mut output = Cursor::new(Vec::new());
    DynamicImage::new_rgba8(width, height)
        .write_to(&mut output, ImageFormat::Png)
        .unwrap();
    output.into_inner()
}

/// Polls `condition` until it holds, failing the test after five seconds.
pub(crate) async fn wait_until(condition: impl Fn() -> bool) {
    timeout(Duration::from_secs(5), async {
        while !condition() {
            sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .expect("condition to hold within the wait budget");
}

/// Reports whether a tag ends with `/>`.
fn is_self_closed(tag: &str) -> bool {
    tag[..tag.len() - 1].trim_end().ends_with('/')
}

/// Returns the end of the comment or tag starting at `start`, or `None` when
/// the `<` there is text or the tag is never closed.
fn markup_end(html: &str, start: usize) -> Option<usize> {
    let rest = &html[start..];

    // Skip comments through their terminator
    if let Some(comment) = rest.strip_prefix("<!--") {
        return Some(
            comment
                .find("-->")
                .map_or(html.len(), |offset| start + 4 + offset + 3),
        );
    }

    // Treat `<` as text unless a tag name follows it or its closing slash
    let name_start = if rest.starts_with("</") { 2 } else { 1 };
    if !rest.as_bytes().get(name_start).is_some_and(u8::is_ascii_alphabetic) {
        return None;
    }

    // Find the closing `>` outside quoted attribute values
    let mut quote = None;
    for (offset, byte) in rest.bytes().enumerate().skip(name_start) {
        match (quote, byte) {
            (None, b'"' | b'\'') => quote = Some(byte),
            (None, b'>') => return Some(start + offset + 1),
            (Some(open), _) if open == byte => quote = None,
            _ => {}
        }
    }
    None
}

/// Iterates over the byte ranges of the comments and tags in `html`.
fn markup_ranges(html: &str) -> impl Iterator<Item = Range<usize>> + '_ {
    let mut position = 0;
    iter::from_fn(move || {
        while let Some(offset) = html[position..].find('<') {
            let start = position + offset;
            if let Some(end) = markup_end(html, start) {
                position = end;
                return Some(start..end);
            }
            position = start + 1;
        }
        None
    })
}

/// Returns the byte range of the first opening tag that contains `needle`.
fn opening_tag_range_with(html: &str, needle: &str) -> Range<usize> {
    markup_ranges(html)
        .find(|range| {
            let markup = &html[range.clone()];
            markup.as_bytes().get(1).is_some_and(u8::is_ascii_alphabetic) && markup.contains(needle)
        })
        .unwrap_or_else(|| panic!("no opening tag contains {needle}"))
}

/// Returns the element name of an opening or closing tag, or an empty name
/// for a comment.
fn tag_name(tag: &str) -> &str {
    let name = tag.trim_start_matches('<').trim_start_matches('/');
    let end = name
        .find(|c: char| !(c.is_ascii_alphanumeric() || c == '-'))
        .unwrap_or(name.len());
    &name[..end]
}

#[cfg(test)]
mod tests;
