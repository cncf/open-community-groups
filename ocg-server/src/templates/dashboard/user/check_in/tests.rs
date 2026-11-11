use askama::Template;
use chrono::{TimeZone, Utc};
use chrono_tz::America::Los_Angeles;
use uuid::Uuid;

use crate::{
    test_util::opening_tag_with,
    types::{dashboard::user::check_in::UserCheckInEvent, event::EventKind},
};

use super::ListPage;

#[test]
fn test_list_page_lists_only_events_awaiting_check_in() {
    // Render one event awaiting check-in and one already checked in
    let awaiting_id = Uuid::from_u128(1);
    let checked_in_id = Uuid::from_u128(2);
    let page = ListPage {
        events: vec![
            sample_event(awaiting_id, false),
            sample_event(checked_in_id, true),
        ],
        name: "Ada Lovelace".to_string(),
        username: "ada".to_string(),
        photo_url: None,
    };
    let html = page.render().unwrap();

    // Check the awaiting event renders an opener with its QR code payload
    let opener = opening_tag_with(&html, &format!(r#"data-event-id="{awaiting_id}""#));
    assert!(opener.contains("data-user-check-in-open"));
    assert!(opener.contains(&format!(
        r#"data-qr-code-url="/dashboard/user/check-in/{awaiting_id}/qr-code""#
    )));

    // Check the checked-in event renders no opener
    assert!(!html.contains(&format!(r#"data-event-id="{checked_in_id}""#)));
    assert!(!html.contains(&format!("/dashboard/user/check-in/{checked_in_id}/qr-code")));
}

// Helpers.

/// Builds a check-in event with the given identifier and check-in state.
fn sample_event(event_id: Uuid, checked_in: bool) -> UserCheckInEvent {
    UserCheckInEvent {
        checked_in,
        cohosts: vec![],
        event_id,
        in_progress: false,
        kind: EventKind::InPerson,
        name: "Community meetup".to_string(),
        starts_at: Los_Angeles
            .with_ymd_and_hms(2030, 3, 5, 18, 0, 0)
            .unwrap()
            .with_timezone(&Utc),
        timezone: Los_Angeles,

        logo_dark_url: None,
        logo_url: None,
        location: Some("Main hall".to_string()),
        ticket_title: Some("General admission".to_string()),
    }
}
