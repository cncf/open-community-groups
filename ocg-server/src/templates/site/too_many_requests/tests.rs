use askama::Template;

use crate::test_util::opening_tag_with;

use super::*;

#[test]
fn test_page_renders_message_home_link_and_standalone_assets() {
    // Render the page with a message holding markup
    let html = Page {
        message: "Please wait <b>2 minutes</b> & try again.".to_string(),
    }
    .render()
    .unwrap();

    // Check the message is escaped under the only heading
    assert!(html.contains("Please wait &#60;b&#62;2 minutes&#60;/b&#62; &#38; try again."));
    assert!(!html.contains("<b>"));
    assert_eq!(html.matches("<h1").count(), 1);

    // Check the page links home without htmx
    assert!(opening_tag_with(&html, r#"href="/""#).starts_with("<a "));
    assert!(!html.contains("hx-"));

    // Check the preferences script runs before the hashed site stylesheet
    let preferences = html.find("data-ocg-preferences").unwrap();
    let stylesheet = opening_tag_with(&html, r#"rel="stylesheet""#);
    assert!(stylesheet.contains(r#"href="/static/css/styles."#));
    assert!(preferences < html.find(stylesheet).unwrap());
    assert!(html.contains(r#"href="/static/images/favicon.svg""#));
    assert!(!html.contains("<script src"));

    // Check the default brand ramp is emitted
    assert_eq!(html.matches("--ocg-primary-dark-fill:").count(), 1);

    // Check the canvas background grows with content taller than the viewport
    let body = opening_tag_with(&html, "<body ");
    let body_classes: Vec<&str> = body
        .split(r#"class=""#)
        .nth(1)
        .and_then(|rest| rest.split('"').next())
        .unwrap()
        .split_whitespace()
        .collect();
    assert!(body_classes.contains(&"bg-canvas"));
    assert!(body_classes.contains(&"min-h-full"));
    assert!(!body_classes.contains(&"h-full"));
}
