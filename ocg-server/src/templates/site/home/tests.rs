use uuid::Uuid;

use crate::{
    test_util::opening_tag_with,
    types::tests::{sample_community_summary, sample_site_settings},
};

use super::*;

#[test]
fn test_page_community_banner_renders_dark_variant_only_with_dark_banner() {
    // Setup one community with a dark mobile banner and one without
    let banner_url = "https://example.test/banner_mobile.png";
    let banner_dark_url = "https://example.test/banner_mobile-dark.png";
    let page = Page {
        communities: vec![
            CommunitySummary {
                banner_mobile_dark_url: Some(banner_dark_url.to_string()),
                ..sample_community_summary(Uuid::from_u128(1))
            },
            sample_community_summary(Uuid::from_u128(2)),
        ],
        ..sample_page()
    };

    // Render the home page
    let body = page.render().unwrap();

    // Check both light banners render and only the first is marked as light
    assert_eq!(body.matches(&format!(r#"src="{banner_url}""#)).count(), 2);
    assert_eq!(body.matches(r#"data-theme-image="light""#).count(), 1);
    let light = opening_tag_with(&body, r#"data-theme-image="light""#);
    assert!(light.contains(&format!(r#"src="{banner_url}""#)));

    // Check the lazy dark banner follows its light banner
    assert_eq!(body.matches(r#"data-theme-image="dark""#).count(), 1);
    let dark = opening_tag_with(&body, r#"data-theme-image="dark""#);
    assert!(dark.starts_with("<img"));
    assert!(dark.contains(&format!(r#"src="{banner_dark_url}""#)));
    assert!(dark.contains(r#"alt="Test banner""#));
    assert!(dark.contains(r#"loading="lazy""#));
    assert!(body.find(r#"data-theme-image="light""#) < body.find(r#"data-theme-image="dark""#));
}

#[test]
fn test_page_title_defaults_to_site_title() {
    // Render the home page, which sets no page title of its own
    let body = sample_page().render().unwrap();

    // Check the base template falls back to the site title
    assert!(body.contains("<title>Test Site</title>"));
}

#[test]
fn test_page_with_four_communities_renders_swipe_dots_row() {
    // Render the home page with one community more than a phone page holds
    let body = sample_page_with_communities(4).render().unwrap();

    // Check every banner renders and the decorative dots row follows the list
    assert_eq!(body.matches(r#"alt="Test banner""#).count(), 4);
    let dots_row = opening_tag_with(&body, "data-snap-dots");
    assert!(dots_row.contains(r#"aria-hidden="true""#));
    assert!(dots_row.contains(r#"data-snap-dots-max="24""#));
    assert!(!body.contains("data-snap-counter"));
}

#[test]
fn test_page_with_three_communities_renders_no_swipe_dots_row() {
    // Render the home page with the communities one phone page holds
    let body = sample_page_with_communities(3).render().unwrap();

    // Check every banner renders without a dots row
    assert_eq!(body.matches(r#"alt="Test banner""#).count(), 3);
    assert!(!body.contains("data-snap-dots"));
}

#[test]
fn test_page_without_communities_shows_placeholder_without_alert() {
    // Render the home page without communities
    let body = sample_page().render().unwrap();

    // Check the placeholder renders as static text, not an alert
    assert!(body.contains("No communities yet"));
    assert!(!body.contains(r#"role="alert""#));
}

// Helpers.

/// Builds a home page without communities, groups or events.
fn sample_page() -> Page {
    Page {
        communities: vec![],
        page_id: PageId::SiteHome,
        path: "/".into(),
        recently_added_groups: vec![],
        site_settings: sample_site_settings(),
        stats: SiteHomeStats::default(),
        upcoming_in_person_events: vec![],
        upcoming_virtual_events: vec![],
        user: UserMenuState::default(),
    }
}

/// Builds a home page listing `count` communities.
fn sample_page_with_communities(count: u128) -> Page {
    Page {
        communities: (1..=count)
            .map(|index| sample_community_summary(Uuid::from_u128(index)))
            .collect(),
        ..sample_page()
    }
}
