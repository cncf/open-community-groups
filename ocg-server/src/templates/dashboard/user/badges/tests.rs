use askama::Template;

use crate::test_util::element_text_with;

use super::ListPage;

#[test]
fn test_list_page_explains_profile_badge_limit() {
    // Render the badges pane with a configured profile badge limit
    let page = ListPage {
        badges: vec![],
        max_public_profile_badges: 7,
    };
    let html = page.render().unwrap();

    // Check the header explains the configured profile badge limit
    let text = element_text_with(&html, r#"aria-labelledby="user-badges-title""#);
    assert!(text.contains(
        "Your profile modal displays the first 7 visible badges in the order shown here."
    ));
}
