use askama::Template;
use chrono::{TimeZone, Utc};
use chrono_tz::America::New_York;
use uuid::Uuid;

use crate::{
    test_util::opening_tag_with,
    types::{dashboard::group::check_in::GroupCheckInEvent, event::EventKind},
};

use super::ListPage;

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

        logo_url: None,
        location: location.map(str::to_string),
    }
}
