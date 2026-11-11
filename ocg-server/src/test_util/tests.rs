use std::panic::catch_unwind;

use super::{element_html_with, element_text_with, opening_tag_with};

#[test]
fn test_element_html_with_includes_nested_same_name_elements() {
    let cases = [
        (
            "nested div closes at the matching tag",
            r#"<div id="outer"><div class="inner">One</div><div>Two</div></div><div>After</div>"#,
            r#"id="outer""#,
            r#"<div id="outer"><div class="inner">One</div><div>Two</div></div>"#,
        ),
        (
            "self-closed same-name child does not open a level",
            r#"<svg id="icon"><svg/><path d="M0"/></svg><p>After</p>"#,
            r#"id="icon""#,
            r#"<svg id="icon"><svg/><path d="M0"/></svg>"#,
        ),
        (
            "similar names are not counted as the same element",
            r#"<tr id="row"><track src="a"><td>Cell</td></tr><tr>Next</tr>"#,
            r#"id="row""#,
            r#"<tr id="row"><track src="a"><td>Cell</td></tr>"#,
        ),
        (
            "quoted markup and comments are not counted",
            r#"<div id="box" x-html="'<div>'"><!-- <div> --><span>In</span></div></div>"#,
            r#"id="box""#,
            r#"<div id="box" x-html="'<div>'"><!-- <div> --><span>In</span></div>"#,
        ),
    ];

    for (label, html, needle, expected) in cases {
        assert_eq!(element_html_with(html, needle), expected, "{label}");
    }
}

#[test]
#[should_panic(expected = "element whose opening tag contains id=\"open\" is not closed")]
fn test_element_html_with_panics_when_not_closed() {
    element_html_with(r#"<div id="open"><div></div>"#, r#"id="open""#);
}

#[test]
fn test_element_html_with_returns_void_element_tag() {
    let cases = [
        (
            "void input",
            r#"<form><input id="name" type="text"><span>Hint</span></form>"#,
            r#"id="name""#,
            r#"<input id="name" type="text">"#,
        ),
        (
            "void element in uppercase",
            r#"<p>Line<BR id="break">Next</p>"#,
            r#"id="break""#,
            r#"<BR id="break">"#,
        ),
        (
            "self-closed custom element",
            r#"<section><x-icon id="logo" /><p>Text</p></section>"#,
            r#"id="logo""#,
            r#"<x-icon id="logo" />"#,
        ),
    ];

    for (label, html, needle, expected) in cases {
        assert_eq!(element_html_with(html, needle), expected, "{label}");
    }
}

#[test]
fn test_element_text_with_strips_tags_and_normalizes_whitespace() {
    let cases = [
        (
            "nested tags and whitespace runs",
            "<li id=\"item\">\n  <strong>Rust</strong>\n  <span>Meetup</span>\n</li>",
            r#"id="item""#,
            "Rust Meetup",
        ),
        (
            "quoted markup and comments are stripped",
            r#"<p id="copy" x-show="a > b">Open <!-- hidden --><b title="<i>">now</b></p>"#,
            r#"id="copy""#,
            "Open now",
        ),
        (
            "entities stay as rendered",
            r#"<p id="amp">Tom &amp; Jerry &lt;3</p>"#,
            r#"id="amp""#,
            "Tom &amp; Jerry &lt;3",
        ),
    ];

    for (label, html, needle, expected) in cases {
        assert_eq!(element_text_with(html, needle), expected, "{label}");
    }
}

#[test]
fn test_opening_tag_with_panics_on_needle_only_in_closing_tag_or_comment() {
    let cases = [
        ("closing tag", "<p>Text</p>", "/p"),
        (
            "comment",
            r#"<!-- <p id="ghost"> --><p>Text</p>"#,
            r#"id="ghost""#,
        ),
    ];

    for (label, html, needle) in cases {
        let result = catch_unwind(|| opening_tag_with(html, needle));
        assert!(result.is_err(), "{label}");
    }
}

#[test]
#[should_panic(expected = "no opening tag contains id=\"missing\"")]
fn test_opening_tag_with_panics_when_missing() {
    opening_tag_with(r#"<div id="present">Text</div>"#, r#"id="missing""#);
}

#[test]
fn test_opening_tag_with_returns_full_tag() {
    let cases = [
        (
            "attributes before the needle are included",
            r#"<main><input type="text" name="title" id="title" disabled></main>"#,
            r#"id="title""#,
            r#"<input type="text" name="title" id="title" disabled>"#,
        ),
        (
            "multi-line tags are kept whole",
            "<div>\n  <select\n    id=\"pick\"\n    class=\"input\">\n  </select>\n</div>",
            r#"id="pick""#,
            "<select\n    id=\"pick\"\n    class=\"input\">",
        ),
        (
            "first matching tag wins",
            r#"<a href="/one" class="link">One</a><a href="/two" class="link">Two</a>"#,
            r#"class="link""#,
            r#"<a href="/one" class="link">"#,
        ),
    ];

    for (label, html, needle, expected) in cases {
        assert_eq!(opening_tag_with(html, needle), expected, "{label}");
    }
}

#[test]
fn test_opening_tag_with_skips_gt_inside_quoted_attribute() {
    let cases = [
        (
            "gt inside a double-quoted Alpine expression",
            r#"<div id="panel" x-show="a > b" class="box">Body</div>"#,
            r#"id="panel""#,
            r#"<div id="panel" x-show="a > b" class="box">"#,
        ),
        (
            "lt inside a quoted value",
            r#"<div x-text="a < b ? 'x' : 'y'" id="cmp">Body</div>"#,
            r#"id="cmp""#,
            r#"<div x-text="a < b ? 'x' : 'y'" id="cmp">"#,
        ),
        (
            "markup inside a single-quoted value",
            r#"<template data-html='<p class="x">Hi</p>' id="tpl"></template>"#,
            r#"id="tpl""#,
            r#"<template data-html='<p class="x">Hi</p>' id="tpl">"#,
        ),
    ];

    for (label, html, needle, expected) in cases {
        assert_eq!(opening_tag_with(html, needle), expected, "{label}");
    }
}

#[test]
fn test_opening_tag_with_skips_needle_in_text_content() {
    let cases = [
        (
            "needle in text before the tag",
            r#"<p>Use id="target" here</p><span id="target">Hit</span>"#,
            r#"id="target""#,
            r#"<span id="target">"#,
        ),
        (
            "needle in text after a stray lt",
            r#"<p>1 < 2 and data-x</p><b data-x="1">Bold</b>"#,
            "data-x",
            r#"<b data-x="1">"#,
        ),
    ];

    for (label, html, needle, expected) in cases {
        assert_eq!(opening_tag_with(html, needle), expected, "{label}");
    }
}
