use askama::Template;
use chrono::{TimeZone, Utc};
use chrono_tz::America::New_York;
use uuid::Uuid;

use crate::{
    test_util::{element_html_with, opening_tag_with},
    types::{dashboard::group::check_in::GroupCheckInEvent, event::EventKind},
};

use super::ListPage;

#[test]
fn test_list_page_card_renders_dark_logo_only_with_both_logos() {
    // Setup logo URLs
    let logo_url = "https://example.test/event-logo.png";
    let logo_dark_url = "https://example.test/event-logo-dark.png";

    // Setup cases: (label, light url, dark url)
    let cases = [
        ("both logos", Some(logo_url), Some(logo_dark_url)),
        ("light logo only", Some(logo_url), None),
        ("dark logo only", None, Some(logo_dark_url)),
        ("no logo", None, None),
    ];

    for (label, light_url, dark_url) in cases {
        // Render one event card with the case logos
        let html = ListPage {
            events: vec![GroupCheckInEvent {
                logo_dark_url: dark_url.map(str::to_string),
                logo_url: light_url.map(str::to_string),
                ..sample_event(EventKind::InPerson, Some("Main Hall"), false)
            }],
        }
        .render()
        .unwrap();
        let paired = light_url.is_some() && dark_url.is_some();

        // Check the light logo always renders when set
        assert_eq!(
            html.contains(&format!(r#"src="{logo_url}""#)),
            light_url.is_some(),
            "{label}"
        );

        // Check the dark logo renders only together with the light logo
        assert_eq!(html.contains(logo_dark_url), paired, "{label}");
        assert_eq!(
            html.matches(r#"data-theme-image="light""#).count(),
            usize::from(paired),
            "{label}"
        );
        assert_eq!(
            html.matches(r#"data-theme-image="dark""#).count(),
            usize::from(paired),
            "{label}"
        );

        // Check the plated light box precedes the unplated lazy dark box
        if paired {
            let light = opening_tag_with(&html, r#"data-theme-image="light""#);
            assert!(light.contains("plate"), "{label}");
            let dark = element_html_with(&html, r#"data-theme-image="dark""#);
            assert!(
                !opening_tag_with(dark, "data-theme-image").contains("plate"),
                "{label}"
            );
            let dark_image = opening_tag_with(dark, &format!(r#"src="{logo_dark_url}""#));
            assert!(dark_image.contains(r#"loading="lazy""#), "{label}");
            assert!(
                html.find(r#"data-theme-image="light""#) < html.find(r#"data-theme-image="dark""#),
                "{label}"
            );
        }
    }
}

#[test]
fn test_list_page_marks_only_in_progress_events() {
    let badge = ">In progress</span>";
    let cases = [("in progress", true, true), ("upcoming", false, false)];

    for (case, in_progress, expects_badge) in cases {
        // Render one event card for the progress state
        let page = ListPage {
            events: vec![sample_event(
                EventKind::InPerson,
                Some("Main Hall"),
                in_progress,
            )],
        };
        let html = page.render().unwrap();

        // Check the in-progress badge
        assert_eq!(html.contains(badge), expects_badge, "{case}");
    }
}

#[test]
fn test_list_page_renders_scanner_opener_payload() {
    let cases = [
        ("virtual", EventKind::Virtual, Some("Main Hall"), "Virtual"),
        (
            "in person",
            EventKind::InPerson,
            Some("Main Hall"),
            "Main Hall",
        ),
        (
            "in person without venue",
            EventKind::InPerson,
            None,
            "Venue details pending",
        ),
    ];

    for (case, kind, location, expected_location) in cases {
        // Render one event card for the delivery kind and venue
        let event = sample_event(kind, location, false);
        let event_id = event.event_id;
        let html = ListPage {
            events: vec![event],
        }
        .render()
        .unwrap();

        // Check the scanner opener payload
        let opener = opening_tag_with(&html, "data-group-check-in-open");
        assert!(
            opener.contains(&format!(r#"data-event-id="{event_id}""#)),
            "{case}: event id"
        );
        assert!(
            opener.contains(&format!(r#"data-event-location="{expected_location}""#)),
            "{case}: event location"
        );
        assert!(
            opener.contains(r#"data-event-name="Community meetup""#),
            "{case}: event name"
        );
        assert!(
            opener.contains(r#"data-event-timezone="America/New_York""#),
            "{case}: event timezone"
        );
        assert!(
            opener.contains(r#"data-event-date="Jun 15, 2030 · 2:00 PM EDT""#),
            "{case}: event date"
        );
        assert!(
            opener.contains(&format!(
                r#"data-scan-url="/dashboard/group/events/{event_id}/check-ins/scan""#
            )),
            "{case}: scan url"
        );
    }
}

// Helpers.

/// Builds a group check-in event starting during daylight saving time in New
/// York, so the rendered timezone abbreviation is stable.
fn sample_event(kind: EventKind, location: Option<&str>, in_progress: bool) -> GroupCheckInEvent {
    GroupCheckInEvent {
        cohosts: vec![],
        event_id: Uuid::from_u128(1),
        in_progress,
        kind,
        name: "Community meetup".to_string(),
        starts_at: Utc.with_ymd_and_hms(2030, 6, 15, 18, 0, 0).unwrap(),
        timezone: New_York,

        logo_dark_url: None,
        logo_url: None,
        location: location.map(str::to_string),
    }
}
