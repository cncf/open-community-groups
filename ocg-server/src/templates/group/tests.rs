use chrono::{TimeZone, Utc};
use chrono_tz::Europe::Madrid;
use uuid::Uuid;

use crate::{
    test_util::{element_html_with, opening_tag_with},
    types::{
        tests::{sample_event_summary, sample_group_full, sample_site_settings},
        user::User,
    },
};

use super::*;

#[test]
fn test_page_breadcrumb_pairs_banners_with_the_chosen_level_dark_variant() {
    // Setup cases: (label, group desktop pair, group mobile pair, expected desktop,
    // expected mobile), where the community pairs are always (c, c-dark) and
    // (cm, cm-dark)
    let cases = [
        (
            "group pairs",
            (Some("g"), Some("g-dark")),
            (Some("gm"), Some("gm-dark")),
            ("g", Some("g-dark")),
            ("gm", Some("gm-dark")),
        ),
        (
            "group light without dark while the community has a dark",
            (Some("g"), None),
            (Some("gm"), None),
            ("g", None),
            ("gm", None),
        ),
        (
            "orphan group darks fall through to the community pairs",
            (None, Some("g-dark")),
            (None, Some("gm-dark")),
            ("c", Some("c-dark")),
            ("cm", Some("cm-dark")),
        ),
        (
            "desktop and mobile resolve independently",
            (None, None),
            (Some("gm"), None),
            ("c", Some("c-dark")),
            ("gm", None),
        ),
    ];

    for (label, group_desktop, group_mobile, desktop, mobile) in cases {
        // Setup the case banners on the group and its community
        let url = |token: &str| format!("https://example.test/{token}.png");
        let mut page = sample_page(Vec::new());
        page.group.banner_dark_url = group_desktop.1.map(url);
        page.group.banner_mobile_dark_url = group_mobile.1.map(url);
        page.group.banner_mobile_url = group_mobile.0.map(url);
        page.group.banner_url = group_desktop.0.map(url);
        page.group.community.banner_dark_url = Some(url("c-dark"));
        page.group.community.banner_mobile_dark_url = Some(url("cm-dark"));
        page.group.community.banner_mobile_url = url("cm");
        page.group.community.banner_url = url("c");

        // Render the group page and keep its breadcrumb
        let html = page.render().unwrap();
        let breadcrumb = opening_tag_with(&html, "<breadcrumb-nav");

        // Check each banner carries only the dark variant of its own level
        assert_eq!(
            attribute_value(breadcrumb, "banner-url"),
            Some(url(desktop.0).as_str()),
            "{label}"
        );
        assert_eq!(
            attribute_value(breadcrumb, "banner-dark-url"),
            desktop.1.map(url).as_deref(),
            "{label}"
        );
        assert_eq!(
            attribute_value(breadcrumb, "banner-mobile-url"),
            Some(url(mobile.0).as_str()),
            "{label}"
        );
        assert_eq!(
            attribute_value(breadcrumb, "banner-mobile-dark-url"),
            mobile.1.map(url).as_deref(),
            "{label}"
        );
    }
}

#[test]
fn test_page_lists_only_named_organizers() {
    // Render the page with one named and one unnamed organizer
    let html = sample_page(vec![
        sample_organizer("ana-organizer", Some("Ana")),
        sample_organizer("ghost-organizer", None),
    ])
    .render()
    .unwrap();

    // Check only the named organizer gets a profile chip
    assert_eq!(html.matches("<user-chip").count(), 1);
    assert!(opening_tag_with(&html, "<user-chip").contains("ana-organizer"));
    assert!(!html.contains("ghost-organizer"));
}

#[test]
fn test_page_logo_renders_dark_variant_only_with_dark_logo() {
    // Setup logo URLs
    let logo_url = "https://example.test/group-logo.png";
    let logo_dark_url = "https://example.test/group-logo-dark.png";

    // Render the group page without a dark logo
    let mut page = sample_page(Vec::new());
    page.group.logo_url = logo_url.to_string();
    let html = page.render().unwrap();

    // Check the plated logo renders alone and unmarked
    assert!(opening_tag_with(&html, &format!(r#"src="{logo_url}""#)).starts_with("<img"));
    assert!(!html.contains("data-theme-image"));

    // Render the group page with a dark logo
    page.group.logo_dark_url = Some(logo_dark_url.to_string());
    let html = page.render().unwrap();

    // Check the marked plated logo precedes the unplated lazy dark logo
    let light = element_html_with(&html, r#"data-theme-image="light""#);
    assert!(opening_tag_with(light, "data-theme-image").contains("plate"));
    assert!(opening_tag_with(light, &format!(r#"src="{logo_url}""#)).starts_with("<img"));
    let dark = element_html_with(&html, r#"data-theme-image="dark""#);
    assert!(!opening_tag_with(dark, "data-theme-image").contains("plate"));
    let dark_image = opening_tag_with(dark, &format!(r#"src="{logo_dark_url}""#));
    assert!(dark_image.starts_with("<img"));
    assert!(dark_image.contains(r#"loading="lazy""#));
    assert!(html.find(r#"data-theme-image="light""#) < html.find(r#"data-theme-image="dark""#));
    assert_eq!(html.matches("data-theme-image").count(), 2);
}

#[test]
fn test_page_omits_organizers_without_named_organizers() {
    // Render the page with organizers that have no public name
    let html = sample_page(vec![
        sample_organizer("ghost-organizer", None),
        sample_organizer("blank-organizer", Some("   ")),
    ])
    .render()
    .unwrap();

    // Check the organizers section is not rendered
    assert!(!html.contains("<user-chip"));
    assert!(!html.contains("Organizers"));
}

#[test]
fn test_page_pluralizes_member_count() {
    // (case, members count, expected label)
    let cases = [
        ("one member", 1, "1 member"),
        ("two members", 2, "2 members"),
    ];

    for (case, members_count, expected) in cases {
        // Render the page with the case members count
        let mut page = sample_page(Vec::new());
        page.group.members_count = members_count;
        let html = page.render().unwrap();

        // Check the members label matches the count
        assert!(html.contains(&format!(">{expected}<")), "{case}");
    }

    // Check a single member is not labelled as plural
    let mut page = sample_page(Vec::new());
    page.group.members_count = 1;
    assert!(!page.render().unwrap().contains("1 members"));
}

#[test]
fn test_page_renders_next_multi_day_event_times_with_timezone() {
    // Setup a next event spanning the EU daylight saving change
    let event = EventSummary {
        ends_at: Some(Utc.with_ymd_and_hms(2030, 3, 31, 18, 0, 0).unwrap()),
        starts_at: Some(Utc.with_ymd_and_hms(2030, 3, 30, 17, 0, 0).unwrap()),
        timezone: Madrid,
        ..sample_event_summary(Uuid::new_v4())
    };
    let mut page = sample_page(Vec::new());
    page.upcoming_events = vec![UpcomingEventCard {
        cohosted_by_page_group: false,
        event,
    }];

    // Render the group page
    let html = page.render().unwrap();

    // Check each column shows its own zone abbreviation
    assert!(html.contains("06:00 PM CET"));
    assert!(html.contains("08:00 PM CEST"));
}

#[test]
fn test_public_organizers_skips_unnamed_organizers() {
    // Setup a page with named, unnamed and blank-named organizers
    let page = sample_page(vec![
        sample_organizer("first-organizer", Some("First")),
        sample_organizer("unnamed-organizer", None),
        sample_organizer("blank-organizer", Some(" ")),
        sample_organizer("second-organizer", Some("Second")),
    ]);

    // Check only named organizers remain, in their original order
    let usernames: Vec<&str> = page
        .public_organizers()
        .into_iter()
        .map(|organizer| organizer.username.as_str())
        .collect();
    assert_eq!(usernames, ["first-organizer", "second-organizer"]);
}

// Helpers.

/// Returns the value of the named attribute in a rendered opening tag.
fn attribute_value<'a>(tag: &'a str, name: &str) -> Option<&'a str> {
    let (_, rest) = tag.split_once(&format!(r#" {name}=""#))?;
    rest.split('"').next()
}

/// Builds an organizer with the given username and name.
fn sample_organizer(username: &str, name: Option<&str>) -> User {
    User {
        user_id: Uuid::new_v4(),
        username: username.to_string(),

        name: name.map(str::to_string),
        ..Default::default()
    }
}

/// Builds a group page with the given organizers and no events.
fn sample_page(organizers: Vec<User>) -> Page {
    let mut group = sample_group_full(Uuid::new_v4(), Uuid::new_v4());
    group.organizers = organizers;

    Page {
        base_url: "https://example.test".to_string(),
        group,
        page_id: PageId::Group,
        past_events: Vec::new(),
        path: "/test/group/test-group".to_string(),
        site_settings: sample_site_settings(),
        upcoming_events: Vec::new(),
        user: UserMenuState::default(),
    }
}
