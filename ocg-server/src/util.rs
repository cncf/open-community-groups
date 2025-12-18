//! Utility functions shared across modules.

use chrono::{DateTime, Datelike, Timelike, Utc};
use icalendar::{Calendar, Component as _, Event, EventLike as _, EventStatus, Property};
use sha2::{Digest, Sha256};

use crate::{services::notifications::Attachment, types::event::EventSummary};

/// Build an iCalendar (ICS) attachment for the specified event.
pub(crate) fn build_event_calendar_attachment(base_url: &str, event: &EventSummary) -> Attachment {
    // Prepare some event data
    let description = build_event_calendar_description(event);
    let location = event.location(512);
    let uid = format!("{}", event.event_id);
    let tz_string = event.timezone.to_string();

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

    // Add start time with timezone
    if let Some(start) = event.starts_at {
        let tz_start = start.with_timezone(&event.timezone);
        let mut dtstart_prop = Property::new("DTSTART", format_datetime_for_ics(&tz_start));
        dtstart_prop.add_parameter("TZID", &tz_string);
        ical_event.append_property(dtstart_prop);
    }

    // Add end time with timezone
    if let Some(end) = event.ends_at {
        let tz_end = end.with_timezone(&event.timezone);
        let mut dtend_prop = Property::new("DTEND", format_datetime_for_ics(&tz_end));
        dtend_prop.add_parameter("TZID", &tz_string);
        ical_event.append_property(dtend_prop);
    }

    // Add location and geo coordinates
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
        .append_property(Property::new("X-WR-TIMEZONE", event.timezone.to_string()))
        .push(ical_event.done());

    // Setup attachment and return it
    Attachment {
        data: calendar.to_string().into_bytes(),
        file_name: format!("event-{}.ics", event.slug),
        content_type: "text/calendar; charset=utf-8".to_string(),
    }
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

    // Meeting URL if available
    if let Some(meeting_join_url) = event.meeting_join_url.as_deref().filter(|url| !url.trim().is_empty()) {
        description.push(format!("Meeting link: {meeting_join_url}"));
    }

    // Meeting password if available
    if let Some(password) = event.meeting_password.as_deref().filter(|p| !p.trim().is_empty()) {
        description.push(format!("Meeting password: {password}"));
    }

    description.join("\n\n")
}

/// Helper function to format `DateTime` with timezone for ICS format (YYYYMMDDTHHMMSS)
fn format_datetime_for_ics<Tz: chrono::TimeZone>(dt: &DateTime<Tz>) -> String {
    format!(
        "{:04}{:02}{:02}T{:02}{:02}{:02}",
        dt.year(),
        dt.month(),
        dt.day(),
        dt.hour(),
        dt.minute(),
        dt.second()
    )
}

/// Quote parameter value for ICS output according to RFC 5545 section 3.2.
fn quote_ics_parameter_value(input: &str) -> String {
    // Remove characters not allowed
    let sanitized = input.replace('"', "");

    // Quote if it contains special characters
    if sanitized.contains(',') || sanitized.contains(';') || sanitized.contains(':') {
        format!("\"{sanitized}\"")
    } else {
        sanitized
    }
}

#[cfg(test)]
mod tests {
    use chrono::{TimeZone, Utc};
    use chrono_tz::America::Los_Angeles;
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
        assert!(unfolded.contains("Meeting link: https://example.test/live"));
        assert!(unfolded.contains("Meeting password: secret123"));
        assert!(unfolded.contains("DTEND;TZID=America/Los_Angeles:20260112T130000"));
        assert!(unfolded.contains("DTSTAMP:"));
        assert!(unfolded.contains("DTSTART;TZID=America/Los_Angeles:20260112T110000"));
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
        assert!(unfolded.contains("Meeting link: https://example.test/live"));
        assert!(unfolded.contains("Meeting password: secret123"));
        assert!(unfolded.contains("DTEND;TZID=America/Los_Angeles:20260112T130000"));
        assert!(unfolded.contains("DTSTAMP:"));
        assert!(unfolded.contains("DTSTART;TZID=America/Los_Angeles:20260112T110000"));
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
    fn test_format_datetime_for_ics() {
        let dt = Utc.with_ymd_and_hms(2026, 1, 12, 19, 0, 0).unwrap();
        let formatted = format_datetime_for_ics(&dt);
        assert_eq!(formatted, "20260112T190000");

        let dt_la = dt.with_timezone(&Los_Angeles);
        let formatted_la = format_datetime_for_ics(&dt_la);
        assert_eq!(formatted_la, "20260112T110000");
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
            timezone: Los_Angeles,
            description_short: Some("Short description".to_string()),
            ends_at: Some(Utc.with_ymd_and_hms(2026, 1, 12, 21, 0, 0).unwrap()),
            latitude: Some(37.78),
            logo_url: None,
            longitude: Some(-122.42),
            meeting_join_url: Some("https://example.test/live".to_string()),
            meeting_password: Some("secret123".to_string()),
            meeting_provider: None,
            popover_html: None,
            remaining_capacity: Some(15),
            starts_at: Some(Utc.with_ymd_and_hms(2026, 1, 12, 19, 0, 0).unwrap()),
            venue_address: Some("123 Main St".to_string()),
            venue_city: Some("San Francisco".to_string()),
            venue_country_code: Some("US".to_string()),
            venue_country_name: Some("United States".to_string()),
            venue_name: Some("Test Venue".to_string()),
            venue_state: Some("CA".to_string()),
            zip_code: Some("94105".to_string()),
        }
    }
}
