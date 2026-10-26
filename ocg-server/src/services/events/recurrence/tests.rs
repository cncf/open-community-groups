use chrono::{NaiveDate, NaiveTime};
use serde_json::json;

use super::*;

// Public constructor behavior.

#[test]
fn test_from_event_builds_weekly_series_payloads_and_metadata() {
    // Setup recurring event form and base payload
    let starts_at = at(2030, 1, 7);
    let event = sample_event(
        EventRecurrencePattern::Weekly,
        Some(2),
        Some(starts_at),
        "UTC",
    );
    let base_payload = json!({
        "ends_at": "2030-01-07T11:00:00",
        "starts_at": "2030-01-07T10:00:00"
    });

    // Build recurring payloads
    let recurring_payloads = RecurringEventPayloads::from_event(&event, &base_payload)
        .unwrap()
        .unwrap();

    // Check recurrence metadata
    assert_eq!(
        recurring_payloads.recurrence,
        json!({
            "additional_occurrences": 2,
            "pattern": "weekly"
        })
    );

    // Check generated event payloads
    assert_eq!(recurring_payloads.events.len(), 3);
    assert_eq!(recurring_payloads.events[0], base_payload);
    assert_eq!(
        string_at(&recurring_payloads.events[1], "/starts_at"),
        "2030-01-14T10:00:00"
    );
    assert_eq!(
        string_at(&recurring_payloads.events[1], "/ends_at"),
        "2030-01-14T11:00:00"
    );
    assert_eq!(
        string_at(&recurring_payloads.events[2], "/starts_at"),
        "2030-01-21T10:00:00"
    );
    assert_eq!(
        string_at(&recurring_payloads.events[2], "/ends_at"),
        "2030-01-21T11:00:00"
    );
}

#[test]
fn test_from_event_applies_organizers_to_every_occurrence() {
    let first_organizer_id = Uuid::new_v4();
    let second_organizer_id = Uuid::new_v4();
    let cases = [
        ("cleared selection", None, Some(true), Some(json!([]))),
        (
            "selection in submitted order",
            Some(vec![second_organizer_id, first_organizer_id]),
            Some(true),
            Some(json!([second_organizer_id, first_organizer_id])),
        ),
        ("missing selection", None, None, None),
    ];
    for (case, organizers, organizers_present, expected) in cases {
        // Setup a weekly event with two additional occurrences
        let event = EventInput {
            organizers,
            organizers_present,
            ..sample_event(
                EventRecurrencePattern::Weekly,
                Some(2),
                Some(at(2030, 1, 7)),
                "UTC",
            )
        };

        // Check every occurrence submits the same organizers
        assert_eq!(recurring_organizers(&event), vec![expected; 3], "{case}");
    }
}

#[test]
fn test_from_event_rejects_invalid_recurrence_settings() {
    let starts_at = Some(at(2030, 1, 7));
    let pattern = EventRecurrencePattern::Weekly;
    let cases = [
        (
            "missing additional occurrences",
            sample_event(pattern, None, starts_at, "UTC"),
            "recurring events require recurrence_additional_occurrences",
        ),
        (
            "zero additional occurrences",
            sample_event(pattern, Some(0), starts_at, "UTC"),
            "recurrence_additional_occurrences must be between 1 and 12",
        ),
        (
            "too many additional occurrences",
            sample_event(
                pattern,
                Some(MAX_RECURRING_ADDITIONAL_OCCURRENCES + 1),
                starts_at,
                "UTC",
            ),
            "recurrence_additional_occurrences must be between 1 and 12",
        ),
        (
            "missing start",
            sample_event(pattern, Some(1), None, "UTC"),
            "recurring events require starts_at",
        ),
        (
            "invalid timezone",
            sample_event(pattern, Some(1), starts_at, "bad/timezone"),
            "invalid event timezone",
        ),
    ];
    let base_payload = json!({ "starts_at": "2030-01-07T10:00:00" });
    for (case, event, message) in cases {
        let err = unwrap_err_message(RecurringEventPayloads::from_event(&event, &base_payload));
        assert!(err.contains(message), "{case}: {err}");
    }
}

#[test]
fn test_from_event_returns_none_for_single_event() {
    // Setup single event form and base payload
    let event = EventInput::default();
    let base_payload = json!({ "starts_at": "2030-01-07T10:00:00" });

    // Build recurring payloads
    let recurring_payloads = RecurringEventPayloads::from_event(&event, &base_payload).unwrap();

    // Check no recurring payloads are generated
    assert!(recurring_payloads.is_none());
}

// Occurrence payload behavior.

#[test]
fn test_occurrence_payload_refreshes_label_ids_and_remaps_session_labels() {
    // Setup base payload with labels referenced by sessions
    let first_label_id = Uuid::new_v4();
    let second_label_id = Uuid::new_v4();
    let unknown_label_id = Uuid::new_v4();
    let base_payload = json!({
        "labels": [
            {
                "color": "#FFD866",
                "event_label_id": first_label_id,
                "is_new": false,
                "name": "Cloud"
            },
            {
                "color": "#FC9867",
                "event_label_id": second_label_id,
                "is_new": true,
                "name": "Security"
            }
        ],
        "sessions": [
            {
                "label_ids": [second_label_id, unknown_label_id],
                "starts_at": "2030-01-07T10:15:00"
            },
            {
                "starts_at": "2030-01-07T11:15:00"
            }
        ],
        "starts_at": "2030-01-07T10:00:00"
    });

    // Build shifted occurrence payload
    let payload = RecurringEventPayloads::build_occurrence_payload(
        &base_payload,
        at(2030, 1, 7),
        at(2030, 1, 14),
        "UTC".parse().unwrap(),
    )
    .unwrap();

    // Check labels get new identifiers and are marked as new
    let new_first_label_id = string_at(&payload, "/labels/0/event_label_id");
    let new_second_label_id = string_at(&payload, "/labels/1/event_label_id");
    assert_ne!(new_first_label_id, first_label_id.to_string());
    assert_ne!(new_second_label_id, second_label_id.to_string());
    assert_ne!(new_first_label_id, new_second_label_id);
    assert_eq!(payload["labels"][0]["is_new"], json!(true));
    assert_eq!(payload["labels"][1]["is_new"], json!(true));
    assert_eq!(string_at(&payload, "/labels/0/name"), "Cloud");
    assert_eq!(string_at(&payload, "/labels/1/color"), "#FC9867");

    // Check session label references are remapped and unknown IDs kept
    assert_eq!(
        payload["sessions"][0]["label_ids"],
        json!([new_second_label_id, unknown_label_id.to_string()])
    );
    assert!(payload["sessions"][1].get("label_ids").is_none());
}

#[test]
fn test_occurrence_payload_rejects_invalid_payload_shapes_and_dates() {
    // Setup recurrence inputs
    let base_starts_at = at(2030, 1, 7);
    let occurrence_starts_at = at(2030, 1, 14);
    let timezone: Tz = "UTC".parse().unwrap();

    // Check non-object payload rejection
    let non_object_err = unwrap_err_message(RecurringEventPayloads::build_occurrence_payload(
        &json!([]),
        base_starts_at,
        occurrence_starts_at,
        timezone,
    ));
    assert!(non_object_err.contains("event payload must be an object"));

    // Check invalid local datetime rejection
    let invalid_local_date_err =
        unwrap_err_message(RecurringEventPayloads::build_occurrence_payload(
            &json!({ "starts_at": "not-a-local-date" }),
            base_starts_at,
            occurrence_starts_at,
            timezone,
        ));
    assert!(invalid_local_date_err.contains("invalid local datetime: not-a-local-date"));

    // Check invalid UTC datetime rejection
    let invalid_utc_date_err =
        unwrap_err_message(RecurringEventPayloads::build_occurrence_payload(
            &json!({
                "discount_codes": [{
                    "starts_at": "not-a-utc-date"
                }]
            }),
            base_starts_at,
            occurrence_starts_at,
            timezone,
        ));
    assert!(invalid_utc_date_err.contains("invalid UTC datetime: not-a-utc-date"));
}

#[test]
fn test_occurrence_payload_shifts_local_and_utc_dates_and_refreshes_ids() {
    // Setup recurrence inputs and base payload
    let base_starts_at = at_time(2026, 3, 28, 10, 0);
    let occurrence_starts_at = at_time(2026, 4, 4, 10, 0);
    let timezone: Tz = "Europe/Madrid".parse().unwrap();
    let discount_code_id = Uuid::new_v4();
    let price_window_id = Uuid::new_v4();
    let ticket_type_id = Uuid::new_v4();
    let base_payload = json!({
        "cfs_ends_at": "2026-03-20T20:00:00",
        "cfs_starts_at": "2026-03-10T20:00:00",
        "discount_codes": [{
            "ends_at": "2026-03-28T09:00:00Z",
            "event_discount_code_id": discount_code_id,
            "starts_at": "2026-03-27T09:00:00Z"
        }],
        "ends_at": "2026-03-28T11:00:00",
        "sessions": [{
            "ends_at": "2026-03-28T10:45:00",
            "starts_at": "2026-03-28T10:15:00"
        }],
        "starts_at": "2026-03-28T10:00:00",
        "ticket_types": [{
            "event_ticket_type_id": ticket_type_id,
            "price_windows": [{
                "ends_at": "2026-03-28T09:00:00Z",
                "event_ticket_price_window_id": price_window_id,
                "starts_at": "2026-03-27T09:00:00Z"
            }]
        }]
    });

    // Build shifted occurrence payload
    let payload = RecurringEventPayloads::build_occurrence_payload(
        &base_payload,
        base_starts_at,
        occurrence_starts_at,
        timezone,
    )
    .unwrap();

    // Check shifted local datetime fields
    assert_eq!(string_at(&payload, "/cfs_ends_at"), "2026-03-27T20:00:00");
    assert_eq!(string_at(&payload, "/cfs_starts_at"), "2026-03-17T20:00:00");
    assert_eq!(string_at(&payload, "/ends_at"), "2026-04-04T11:00:00");
    assert_eq!(
        string_at(&payload, "/sessions/0/ends_at"),
        "2026-04-04T10:45:00"
    );
    assert_eq!(
        string_at(&payload, "/sessions/0/starts_at"),
        "2026-04-04T10:15:00"
    );
    assert_eq!(string_at(&payload, "/starts_at"), "2026-04-04T10:00:00");

    // Check shifted UTC datetime fields
    assert_eq!(
        string_at(&payload, "/discount_codes/0/ends_at"),
        "2026-04-04T08:00:00Z"
    );
    assert_eq!(
        string_at(&payload, "/discount_codes/0/starts_at"),
        "2026-04-03T08:00:00Z"
    );
    assert_eq!(
        string_at(&payload, "/ticket_types/0/price_windows/0/ends_at"),
        "2026-04-04T08:00:00Z"
    );
    assert_eq!(
        string_at(&payload, "/ticket_types/0/price_windows/0/starts_at"),
        "2026-04-03T08:00:00Z"
    );

    // Check generated identifiers are unique and valid
    assert_ne!(
        string_at(&payload, "/discount_codes/0/event_discount_code_id"),
        discount_code_id.to_string()
    );
    assert_ne!(
        string_at(&payload, "/ticket_types/0/event_ticket_type_id"),
        ticket_type_id.to_string()
    );
    assert_ne!(
        string_at(
            &payload,
            "/ticket_types/0/price_windows/0/event_ticket_price_window_id"
        ),
        price_window_id.to_string()
    );
    Uuid::parse_str(string_at(
        &payload,
        "/discount_codes/0/event_discount_code_id",
    ))
    .unwrap();
    Uuid::parse_str(string_at(&payload, "/ticket_types/0/event_ticket_type_id")).unwrap();
    Uuid::parse_str(string_at(
        &payload,
        "/ticket_types/0/price_windows/0/event_ticket_price_window_id",
    ))
    .unwrap();
}

#[test]
fn test_occurrence_payload_falls_back_across_missing_dst_local_time() {
    // Setup event recurrence with a UTC field shifted into a spring-forward gap
    let base_starts_at = at_time(2026, 3, 22, 2, 30);
    let occurrence_starts_at = at_time(2026, 3, 29, 2, 30);
    let timezone: Tz = "Europe/Madrid".parse().unwrap();
    let base_payload = json!({
        "discount_codes": [{
            "starts_at": "2026-03-22T01:30:00Z"
        }],
        "starts_at": "2026-03-22T02:30:00"
    });

    // Build shifted occurrence payload
    let payload = RecurringEventPayloads::build_occurrence_payload(
        &base_payload,
        base_starts_at,
        occurrence_starts_at,
        timezone,
    )
    .unwrap();

    // Check missing shifted local UTC fields use the absolute one-week delta
    assert_eq!(string_at(&payload, "/starts_at"), "2026-03-29T02:30:00");
    assert_eq!(
        string_at(&payload, "/discount_codes/0/starts_at"),
        "2026-03-29T01:30:00Z"
    );
}

#[test]
fn test_occurrence_payload_preserves_utc_field_wall_clock_across_dst() {
    // Setup event recurrence crossing DST with ticket windows before the transition
    let base_starts_at = at_time(2026, 3, 22, 10, 0);
    let occurrence_starts_at = at_time(2026, 3, 29, 10, 0);
    let timezone: Tz = "Europe/Madrid".parse().unwrap();
    let base_payload = json!({
        "discount_codes": [{
            "starts_at": "2026-03-10T09:00:00Z"
        }],
        "starts_at": "2026-03-22T10:00:00",
        "ticket_types": [{
            "price_windows": [{
                "starts_at": "2026-03-10T09:00:00Z"
            }]
        }]
    });

    // Build shifted occurrence payload
    let payload = RecurringEventPayloads::build_occurrence_payload(
        &base_payload,
        base_starts_at,
        occurrence_starts_at,
        timezone,
    )
    .unwrap();

    // Check UTC fields preserve 10:00 Europe/Madrid instead of using event-start UTC delta
    assert_eq!(string_at(&payload, "/starts_at"), "2026-03-29T10:00:00");
    assert_eq!(
        string_at(&payload, "/discount_codes/0/starts_at"),
        "2026-03-17T09:00:00Z"
    );
    assert_eq!(
        string_at(&payload, "/ticket_types/0/price_windows/0/starts_at"),
        "2026-03-17T09:00:00Z"
    );
}

// Occurrence start time behavior.

#[test]
fn test_occurrence_start_times_follow_the_recurrence_pattern() {
    let cases = [
        (
            "weekly keeps weekday and time",
            EventRecurrencePattern::Weekly,
            at(2030, 1, 7),
            vec![at(2030, 1, 14), at(2030, 1, 21)],
        ),
        (
            "biweekly",
            EventRecurrencePattern::Biweekly,
            at(2030, 1, 7),
            vec![at(2030, 1, 21), at(2030, 2, 4)],
        ),
        (
            "monthly second monday",
            EventRecurrencePattern::Monthly,
            at(2030, 1, 14),
            vec![at(2030, 2, 11), at(2030, 3, 11)],
        ),
        (
            "monthly across the year boundary",
            EventRecurrencePattern::Monthly,
            at(2030, 12, 9),
            vec![at(2031, 1, 13), at(2031, 2, 10)],
        ),
        (
            "monthly skips months without a fifth tuesday",
            EventRecurrencePattern::Monthly,
            at(2030, 1, 29),
            vec![at(2030, 4, 30), at(2030, 7, 30)],
        ),
    ];
    for (case, pattern, starts_at, expected) in cases {
        let recurrence_request = sample_recurrence_request(pattern, 2, starts_at);
        assert_eq!(
            RecurringEventPayloads::occurrence_start_times(&recurrence_request),
            expected,
            "{case}"
        );
    }
}

// Date and timezone helper behavior.

#[test]
fn test_nth_weekday_in_month_returns_none_when_ordinal_is_missing() {
    // Find present and missing ordinal weekdays
    let fifth_monday = nth_weekday_in_month(2030, 2, Weekday::Mon, 5);
    let second_monday = nth_weekday_in_month(2030, 2, Weekday::Mon, 2);

    // Check missing ordinal returns none
    assert_eq!(fifth_monday, None);
    assert_eq!(
        second_monday,
        Some(NaiveDate::from_ymd_opt(2030, 2, 11).unwrap())
    );
}

#[test]
fn test_to_utc_resolves_ambiguous_and_missing_local_times() {
    // Setup DST edge-case local times
    let timezone: Tz = "Europe/Madrid".parse().unwrap();
    let ambiguous = at_time(2026, 10, 25, 2, 30);
    let missing = at_time(2026, 3, 29, 2, 30);

    // Check ambiguous times are resolved and missing times are rejected
    assert_eq!(
        to_utc(timezone, ambiguous).unwrap().to_rfc3339(),
        "2026-10-25T00:30:00+00:00"
    );
    assert_eq!(to_utc(timezone, missing), None);
}

// Helpers.

/// Builds a test datetime at 10:00:00.
fn at(year: i32, month: u32, day: u32) -> NaiveDateTime {
    at_time(year, month, day, 10, 0)
}

/// Builds a test datetime at the given local time.
fn at_time(year: i32, month: u32, day: u32, hour: u32, minute: u32) -> NaiveDateTime {
    NaiveDate::from_ymd_opt(year, month, day)
        .unwrap()
        .and_time(NaiveTime::from_hms_opt(hour, minute, 0).unwrap())
}

/// Returns the organizers submitted in each recurring payload built from the event.
fn recurring_organizers(event: &EventInput) -> Vec<Option<Value>> {
    let base_payload = event.to_db_payload().unwrap();

    RecurringEventPayloads::from_event(event, &base_payload)
        .unwrap()
        .unwrap()
        .events
        .iter()
        .map(|payload| payload.get("organizers").cloned())
        .collect()
}

/// Builds a test event with recurrence fields populated.
fn sample_event(
    pattern: EventRecurrencePattern,
    additional_occurrences: Option<i32>,
    starts_at: Option<NaiveDateTime>,
    timezone: &str,
) -> EventInput {
    EventInput {
        recurrence_additional_occurrences: additional_occurrences,
        recurrence_pattern: Some(pattern),
        starts_at,
        timezone: timezone.to_string(),
        ..Default::default()
    }
}

/// Builds a test recurrence request.
fn sample_recurrence_request(
    pattern: EventRecurrencePattern,
    additional_occurrences: usize,
    starts_at: NaiveDateTime,
) -> RecurrenceRequest {
    RecurrenceRequest {
        additional_occurrences,
        base_starts_at: starts_at,
        pattern,
        timezone: "UTC".parse().unwrap(),
    }
}

/// Reads a string value from a JSON pointer.
fn string_at<'a>(value: &'a Value, pointer: &str) -> &'a str {
    value.pointer(pointer).unwrap().as_str().unwrap()
}

/// Extracts an error message without requiring the success type to implement `Debug`.
fn unwrap_err_message<T>(result: Result<T>) -> String {
    match result {
        Ok(_) => panic!("expected error"),
        Err(err) => err.to_string(),
    }
}
