use chrono::{TimeZone, Utc};
use chrono_tz::Europe::Madrid;
use uuid::Uuid;

use crate::{
    test_util::opening_tag_with,
    types::{
        tests::{sample_event_summary, sample_group_full, sample_site_settings},
        user::User,
    },
};

use super::*;

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
