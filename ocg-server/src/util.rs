//! Utility functions shared across modules.

use chrono::Utc;
use icalendar::{Calendar, Component as _, Event, EventLike as _, EventStatus, Property};
use sha2::{Digest, Sha256};

use crate::{services::notifications::Attachment, types::event::EventSummary};

/// Build an iCalendar (ICS) attachment for the specified event.
pub(crate) fn build_event_calendar_attachment(base_url: &str, event: &EventSummary) -> Attachment {
    // Prepare some event data
    let description = build_event_calendar_description(event);
    let location = event.location(512);
    let uid = format!("{}", event.event_id);

    // Setup ical event
    let mut ical_event = Event::new();
    ical_event
        .summary(&event.name)
        .uid(&uid)
        .timestamp(Utc::now())
        .created(Utc::now())
        .append_property(Property::new("URL", build_event_page_link(base_url, event)));
    if !description.is_empty() {
        ical_event.description(&description);
    }
    if event.canceled {
        ical_event.status(EventStatus::Cancelled);
    } else {
        ical_event.status(EventStatus::Confirmed);
    }
    if let Some(start) = event.starts_at {
        ical_event.starts(start);
    }
    if let Some(end) = event.ends_at {
        ical_event.ends(end);
    }
    if let Some(location) = &location {
        ical_event.location(location);
    }
    if let (Some(lat), Some(lon)) = (event.latitude, event.longitude) {
        ical_event.append_property(Property::new("GEO", format!("{lat:.6};{lon:.6}")));

        // Apple structured location
        let mut apple_loc = Property::new("X-APPLE-STRUCTURED-LOCATION", format!("geo:{lat:.6},{lon:.6}"));
        apple_loc
            .append_parameter(("VALUE", "URI"))
            .append_parameter(("X-APPLE-RADIUS", "100"))
            .append_parameter((
                "X-APPLE-TITLE",
                quote_ics_parameter_value(location.as_deref().unwrap_or(&event.name)).as_str(),
            ));
        if let Some(address) = &location {
            let escaped_address = quote_ics_parameter_value(address);
            apple_loc.append_parameter(("X-ADDRESS", escaped_address.as_str()));
        }
        ical_event.append_property(apple_loc);
    }

    // Setup calendar and add ical event
    let calendar_name = format!("{} - {}", event.group_name, event.name);
    let mut calendar = Calendar::new();
    calendar
        .name(&calendar_name)
        .description(&description)
        .push(ical_event.done());

    // Setup attachment and return it
    Attachment {
        data: calendar.to_string().into_bytes(),
        file_name: format!("event-{}.ics", event.slug),
        content_type: "text/calendar; charset=utf-8".to_string(),
    }
}

/// Build the event description for the calendar entry.
fn build_event_calendar_description(event: &EventSummary) -> String {
    let mut description = Vec::new();

    // Add cancellation notice on top if applicable
    if event.canceled {
        description.push("** This event has been canceled **".to_string());
    }

    // Add short description if available
    if let Some(description_short) = event
        .description_short
        .as_deref()
        .filter(|value| !value.trim().is_empty())
    {
        description.push(description_short.trim().to_string());
    }

    // Streaming URL if available
    if let Some(streaming_url) = event.streaming_url.as_deref().filter(|url| !url.trim().is_empty()) {
        description.push(format!("Streaming link: {streaming_url}"));
    }

    description.join("\n\n")
}

/// Build the event page link based on the base URL and event and group slugs.
pub(crate) fn build_event_page_link(base_url: &str, event: &EventSummary) -> String {
    let base = base_url.strip_suffix('/').unwrap_or(base_url);
    format!("{}/group/{}/event/{}", base, event.group_slug, event.slug)
}

/// Computes the SHA-256 hash of the provided bytes and returns a hex string.
pub(crate) fn compute_hash(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    format!("{:x}", hasher.finalize())
}

/// Quote parameter value for ICS output according to RFC 5545 section 3.2.
fn quote_ics_parameter_value(input: &str) -> String {
    let input = input.replace('"', "");
    if input.contains(',') || input.contains(';') || input.contains(':') {
        format!("\"{input}\"")
    } else {
        input
    }
}

#[cfg(test)]
mod tests {
    use chrono::{TimeZone, Utc};
    use chrono_tz::UTC;
    use uuid::Uuid;

    use crate::types::event::EventKind;

    use super::*;

    const BASE_URL: &str = "https://example.test";

    #[test]
    fn test_build_event_calendar_attachment_confirmed() {
        let event = sample_event(false);
        let attachment = build_event_calendar_attachment(BASE_URL, &event);
        let data = String::from_utf8(attachment.data).unwrap();
        let unfolded = data.replace("\r\n ", "").replace("\n ", "");

        assert_eq!(attachment.content_type, "text/calendar; charset=utf-8");
        assert_eq!(attachment.file_name, "event-test-event.ics");
        assert!(unfolded.contains("CREATED:"));
        assert!(unfolded.contains("DESCRIPTION:"));
        assert!(unfolded.contains("Short description"));
        assert!(unfolded.contains("Streaming link: https://example.test/live"));
        assert!(unfolded.contains("DTEND:20260112T210000Z"));
        assert!(unfolded.contains("DTSTAMP:"));
        assert!(unfolded.contains("DTSTART:20260112T190000Z"));
        assert!(unfolded.contains("GEO:37.780000;-122.420000"));
        assert!(
            unfolded.contains("LOCATION:Test Venue\\, 123 Main St\\, San Francisco\\, CA\\, United States")
        );
        assert!(unfolded.contains("NAME:Test Group - Test Event"));
        assert!(unfolded.contains("STATUS:CONFIRMED"));
        assert!(unfolded.contains("SUMMARY:Test Event"));
        assert!(unfolded.contains("UID:00000000-0000-0000-0000-000000000001"));
        assert!(unfolded.contains("URL:https://example.test/group/test-group/event/test-event"));
        assert!(unfolded.contains("X-APPLE-STRUCTURED-LOCATION;VALUE=URI"));
        assert!(unfolded.contains("X-ADDRESS=\"Test Venue, 123 Main St, San Francisco, CA, United States\""));
        assert!(unfolded.contains("X-APPLE-RADIUS=100"));
        assert!(
            unfolded.contains("X-APPLE-TITLE=\"Test Venue, 123 Main St, San Francisco, CA, United States\"")
        );
    }

    #[test]
    fn test_build_event_calendar_attachment_canceled() {
        let event = sample_event(true);
        let attachment = build_event_calendar_attachment(BASE_URL, &event);
        let data = String::from_utf8(attachment.data).unwrap();
        let unfolded = data.replace("\r\n ", "").replace("\n ", "");

        assert_eq!(attachment.content_type, "text/calendar; charset=utf-8");
        assert_eq!(attachment.file_name, "event-test-event.ics");
        assert!(unfolded.contains("CREATED:"));
        assert!(unfolded.contains("DESCRIPTION:** This event has been canceled **"));
        assert!(unfolded.contains("Short description"));
        assert!(unfolded.contains("Streaming link: https://example.test/live"));
        assert!(unfolded.contains("DTEND:20260112T210000Z"));
        assert!(unfolded.contains("DTSTAMP:"));
        assert!(unfolded.contains("DTSTART:20260112T190000Z"));
        assert!(unfolded.contains("GEO:37.780000;-122.420000"));
        assert!(
            unfolded.contains("LOCATION:Test Venue\\, 123 Main St\\, San Francisco\\, CA\\, United States")
        );
        assert!(unfolded.contains("NAME:Test Group - Test Event"));
        assert!(unfolded.contains("STATUS:CANCELLED"));
        assert!(unfolded.contains("SUMMARY:Test Event"));
        assert!(unfolded.contains("URL:https://example.test/group/test-group/event/test-event"));
        assert!(unfolded.contains("UID:00000000-0000-0000-0000-000000000001"));
        assert!(unfolded.contains("X-APPLE-STRUCTURED-LOCATION;VALUE=URI"));
        assert!(unfolded.contains("X-ADDRESS=\"Test Venue, 123 Main St, San Francisco, CA, United States\""));
        assert!(unfolded.contains("X-APPLE-RADIUS=100"));
        assert!(
            unfolded.contains("X-APPLE-TITLE=\"Test Venue, 123 Main St, San Francisco, CA, United States\"")
        );
    }

    #[test]
    fn test_quote_ics_parameter_value_removes_double_quotes() {
        let input = r#"Joe's "Best" Venue, 123 Main St"#;
        let result = quote_ics_parameter_value(input);
        assert_eq!(result, r#""Joe's Best Venue, 123 Main St""#);
    }

    #[test]
    fn test_quote_ics_parameter_value_without_special_chars() {
        let input = "Simple Venue";
        let result = quote_ics_parameter_value(input);
        assert_eq!(result, "Simple Venue");
    }

    #[test]
    fn test_quote_ics_parameter_value_with_comma_no_quotes() {
        let input = "Venue, With Comma";
        let result = quote_ics_parameter_value(input);
        assert_eq!(result, "\"Venue, With Comma\"");
    }

    // Helpers

    fn sample_event(canceled: bool) -> EventSummary {
        EventSummary {
            canceled,
            event_id: Uuid::parse_str("00000000-0000-0000-0000-000000000001").unwrap(),
            group_category_name: "Community".to_string(),
            group_color: "#ff4081".to_string(),
            group_name: "Test Group".to_string(),
            group_slug: "test-group".to_string(),
            kind: EventKind::InPerson,
            name: "Test Event".to_string(),
            published: true,
            slug: "test-event".to_string(),
            timezone: UTC,
            description_short: Some("Short description".to_string()),
            ends_at: Some(Utc.with_ymd_and_hms(2026, 1, 12, 21, 0, 0).unwrap()),
            group_city: Some("Test City".to_string()),
            group_country_code: Some("US".to_string()),
            group_country_name: Some("United States".to_string()),
            group_state: Some("CA".to_string()),
            latitude: Some(37.78),
            logo_url: None,
            longitude: Some(-122.42),
            popover_html: None,
            remaining_capacity: Some(15),
            starts_at: Some(Utc.with_ymd_and_hms(2026, 1, 12, 19, 0, 0).unwrap()),
            streaming_url: Some("https://example.test/live".to_string()),
            venue_address: Some("123 Main St".to_string()),
            venue_city: Some("San Francisco".to_string()),
            venue_name: Some("Test Venue".to_string()),
            zip_code: Some("94105".to_string()),
        }
    }
}
