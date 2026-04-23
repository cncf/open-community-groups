//! Recurrence helpers for dashboard event creation.

use anyhow::{Context, Result, bail};
use chrono::{
    DateTime, Datelike, LocalResult, NaiveDate, NaiveDateTime, SecondsFormat, TimeDelta, TimeZone, Utc,
    Weekday,
};
use chrono_tz::Tz;
use serde_json::{Value, json};
use uuid::Uuid;

use crate::{
    templates::dashboard::group::events::{Event, EventRecurrencePattern},
    validation::MAX_RECURRING_ADDITIONAL_OCCURRENCES,
};

/// Generated event payloads and metadata for recurring event insertion.
pub(super) struct RecurringEventPayloads {
    /// Event payloads in chronological creation order, including the base event.
    pub(super) events: Vec<Value>,
    /// Recurrence metadata stored with the linked event series.
    pub(super) recurrence: Value,
}

/// Builds recurring event payloads when the event form requests recurrence.
pub(super) fn build_recurring_event_payloads(
    event: &Event,
    base_payload: &Value,
) -> Result<Option<RecurringEventPayloads>> {
    // Skip recurrence processing when the form requests a single event
    let pattern = event.recurrence_pattern.unwrap_or_default();
    if pattern == EventRecurrencePattern::JustOnce {
        return Ok(None);
    }

    // Validate recurrence settings from the submitted event form
    let additional_occurrences = event
        .recurrence_additional_occurrences
        .context("recurring events require recurrence_additional_occurrences")?;
    if !(1..=MAX_RECURRING_ADDITIONAL_OCCURRENCES).contains(&additional_occurrences) {
        bail!(
            "recurrence_additional_occurrences must be between 1 and {MAX_RECURRING_ADDITIONAL_OCCURRENCES}"
        );
    }
    let additional_occurrences: usize = additional_occurrences
        .try_into()
        .context("recurrence_additional_occurrences must be positive")?;
    let base_starts_at = event.starts_at.context("recurring events require starts_at")?;
    let timezone: Tz = event.timezone.parse().context("invalid event timezone")?;
    let generated_start_times = occurrences_start_times(base_starts_at, pattern, additional_occurrences);

    // Build the base event plus each shifted occurrence payload
    let mut events = Vec::with_capacity(additional_occurrences + 1);
    events.push(base_payload.clone());
    for occurrence_starts_at in generated_start_times {
        events.push(build_occurrence_payload(
            base_payload,
            base_starts_at,
            occurrence_starts_at,
            timezone,
        )?);
    }

    Ok(Some(RecurringEventPayloads {
        events,
        recurrence: json!({
            "additional_occurrences": additional_occurrences,
            "pattern": recurrence_pattern_db_value(pattern),
        }),
    }))
}

// Helpers.

/// Builds one shifted event payload for a generated occurrence.
fn build_occurrence_payload(
    base_payload: &Value,
    base_starts_at: NaiveDateTime,
    occurrence_starts_at: NaiveDateTime,
    timezone: Tz,
) -> Result<Value> {
    let mut payload = base_payload.clone();

    // Calculate local and UTC deltas for fields stored in different time bases
    let local_delta = occurrence_starts_at - base_starts_at;
    let utc_delta =
        utc_delta_for_occurrence(timezone, base_starts_at, occurrence_starts_at).unwrap_or(local_delta);

    let Some(payload_obj) = payload.as_object_mut() else {
        bail!("event payload must be an object");
    };

    // Shift event-level local datetime fields
    for field_name in ["cfs_ends_at", "cfs_starts_at", "ends_at", "starts_at"] {
        if let Some(value) = payload_obj.get_mut(field_name) {
            shift_local_field(value, local_delta)?;
        }
    }

    // Shift nested date fields and refresh IDs that must be unique per event
    if let Some(value) = payload_obj.get_mut("sessions") {
        shift_session_dates(value, local_delta)?;
    }
    if let Some(value) = payload_obj.get_mut("discount_codes") {
        shift_discount_dates(value, utc_delta)?;
        refresh_discount_code_ids(value);
    }
    if let Some(value) = payload_obj.get_mut("ticket_types") {
        shift_ticket_dates(value, utc_delta)?;
        refresh_ticketing_ids(value);
    }

    Ok(payload)
}

/// Formats a local datetime for the event payload.
fn format_naive_datetime(value: NaiveDateTime) -> String {
    value.format("%Y-%m-%dT%H:%M:%S").to_string()
}

/// Generates monthly occurrences on the same ordinal weekday.
fn monthly_occurrences_start_times(
    starts_at: NaiveDateTime,
    additional_occurrences: usize,
) -> Vec<NaiveDateTime> {
    // Capture the source ordinal weekday, such as the third Monday
    let date = starts_at.date();
    let ordinal = ((date.day() - 1) / 7) + 1;
    let time = starts_at.time();
    let weekday = date.weekday();
    let mut month = date.month();
    let mut occurrence_start_times = Vec::with_capacity(additional_occurrences);
    let mut year = date.year();

    // Skip months that do not contain the same ordinal weekday
    while occurrence_start_times.len() < additional_occurrences {
        (year, month) = next_month(year, month);
        if let Some(next_date) = nth_weekday_in_month(year, month, weekday, ordinal) {
            occurrence_start_times.push(next_date.and_time(time));
        }
    }

    occurrence_start_times
}

/// Returns the year and month immediately after the provided month.
fn next_month(year: i32, month: u32) -> (i32, u32) {
    if month == 12 {
        (year + 1, 1)
    } else {
        (year, month + 1)
    }
}

/// Finds the nth weekday in a month, if that ordinal exists.
fn nth_weekday_in_month(year: i32, month: u32, weekday: Weekday, ordinal: u32) -> Option<NaiveDate> {
    let first_day = NaiveDate::from_ymd_opt(year, month, 1)?;
    let weekday_offset =
        (7 + weekday.num_days_from_monday() - first_day.weekday().num_days_from_monday()) % 7;
    let target_day = 1 + weekday_offset + ((ordinal - 1) * 7);
    let target_date = NaiveDate::from_ymd_opt(year, month, target_day)?;
    if target_date.month() == month {
        Some(target_date)
    } else {
        None
    }
}

/// Generates the local start datetime for each additional occurrence.
fn occurrences_start_times(
    starts_at: NaiveDateTime,
    pattern: EventRecurrencePattern,
    additional_occurrences: usize,
) -> Vec<NaiveDateTime> {
    match pattern {
        EventRecurrencePattern::JustOnce => Vec::new(),
        EventRecurrencePattern::Weekly => (1..=additional_occurrences)
            .map(|index| {
                let weeks = i64::try_from(index).expect("recurrence index is bounded");
                starts_at + TimeDelta::weeks(weeks)
            })
            .collect(),
        EventRecurrencePattern::Biweekly => (1..=additional_occurrences)
            .map(|index| {
                let weeks = i64::try_from(index * 2).expect("recurrence index is bounded");
                starts_at + TimeDelta::weeks(weeks)
            })
            .collect(),
        EventRecurrencePattern::Monthly => monthly_occurrences_start_times(starts_at, additional_occurrences),
    }
}

/// Parses a local datetime from an event payload string.
fn parse_local_datetime(value: &str) -> Result<NaiveDateTime> {
    value
        .parse::<NaiveDateTime>()
        .with_context(|| format!("invalid local datetime: {value}"))
}

/// Replaces discount code identifiers for a generated occurrence.
fn refresh_discount_code_ids(value: &mut Value) {
    let Value::Array(discount_codes) = value else {
        return;
    };

    for discount_code in discount_codes {
        if let Some(discount_code_obj) = discount_code.as_object_mut() {
            discount_code_obj.insert(
                "event_discount_code_id".to_string(),
                Value::String(Uuid::new_v4().to_string()),
            );
        }
    }
}

/// Replaces ticketing identifiers for a generated occurrence.
fn refresh_ticketing_ids(value: &mut Value) {
    let Value::Array(ticket_types) = value else {
        return;
    };

    for ticket_type in ticket_types {
        if let Some(ticket_type_obj) = ticket_type.as_object_mut() {
            // Refresh the ticket type identifier
            ticket_type_obj.insert(
                "event_ticket_type_id".to_string(),
                Value::String(Uuid::new_v4().to_string()),
            );

            if let Some(Value::Array(price_windows)) = ticket_type_obj.get_mut("price_windows") {
                // Refresh each nested price window identifier
                for price_window in price_windows {
                    if let Some(price_window_obj) = price_window.as_object_mut() {
                        price_window_obj.insert(
                            "event_ticket_price_window_id".to_string(),
                            Value::String(Uuid::new_v4().to_string()),
                        );
                    }
                }
            }
        }
    }
}

/// Returns the database representation for recurrence metadata.
fn recurrence_pattern_db_value(pattern: EventRecurrencePattern) -> &'static str {
    match pattern {
        EventRecurrencePattern::JustOnce => "just-once",
        EventRecurrencePattern::Weekly => "weekly",
        EventRecurrencePattern::Biweekly => "biweekly",
        EventRecurrencePattern::Monthly => "monthly",
    }
}

/// Shifts discount code UTC datetime fields by the occurrence delta.
fn shift_discount_dates(value: &mut Value, delta: TimeDelta) -> Result<()> {
    let Value::Array(discount_codes) = value else {
        return Ok(());
    };

    // Shift each discount code window when present
    for discount_code in discount_codes {
        if let Some(discount_code_obj) = discount_code.as_object_mut() {
            if let Some(value) = discount_code_obj.get_mut("ends_at") {
                shift_utc_field(value, delta)?;
            }
            if let Some(value) = discount_code_obj.get_mut("starts_at") {
                shift_utc_field(value, delta)?;
            }
        }
    }

    Ok(())
}

/// Shifts a local datetime field by the occurrence delta.
fn shift_local_field(value: &mut Value, delta: TimeDelta) -> Result<()> {
    let Value::String(raw_value) = value else {
        return Ok(());
    };
    if raw_value.is_empty() {
        return Ok(());
    }

    let shifted = parse_local_datetime(raw_value)? + delta;
    *raw_value = format_naive_datetime(shifted);
    Ok(())
}

/// Shifts session local datetime fields by the occurrence delta.
fn shift_session_dates(value: &mut Value, delta: TimeDelta) -> Result<()> {
    let Value::Array(sessions) = value else {
        return Ok(());
    };

    // Shift each session schedule when present
    for session in sessions {
        if let Some(session_obj) = session.as_object_mut() {
            if let Some(value) = session_obj.get_mut("ends_at") {
                shift_local_field(value, delta)?;
            }
            if let Some(value) = session_obj.get_mut("starts_at") {
                shift_local_field(value, delta)?;
            }
        }
    }

    Ok(())
}

/// Shifts ticket price window UTC datetime fields by the occurrence delta.
fn shift_ticket_dates(value: &mut Value, delta: TimeDelta) -> Result<()> {
    let Value::Array(ticket_types) = value else {
        return Ok(());
    };

    // Shift each ticket type price window when present
    for ticket_type in ticket_types {
        let Some(ticket_type_obj) = ticket_type.as_object_mut() else {
            continue;
        };
        let Some(Value::Array(price_windows)) = ticket_type_obj.get_mut("price_windows") else {
            continue;
        };

        for price_window in price_windows {
            if let Some(price_window_obj) = price_window.as_object_mut() {
                if let Some(value) = price_window_obj.get_mut("ends_at") {
                    shift_utc_field(value, delta)?;
                }
                if let Some(value) = price_window_obj.get_mut("starts_at") {
                    shift_utc_field(value, delta)?;
                }
            }
        }
    }

    Ok(())
}

/// Shifts a UTC datetime field by the occurrence delta.
fn shift_utc_field(value: &mut Value, delta: TimeDelta) -> Result<()> {
    let Value::String(raw_value) = value else {
        return Ok(());
    };
    if raw_value.is_empty() {
        return Ok(());
    }

    let shifted = DateTime::parse_from_rfc3339(raw_value)
        .with_context(|| format!("invalid UTC datetime: {raw_value}"))?
        .with_timezone(&Utc)
        + delta;
    *raw_value = shifted.to_rfc3339_opts(SecondsFormat::Secs, true);
    Ok(())
}

/// Converts a local datetime to UTC, resolving ambiguous times to the earlier instant.
fn to_utc(timezone: Tz, value: NaiveDateTime) -> Option<DateTime<Utc>> {
    match timezone.from_local_datetime(&value) {
        LocalResult::Single(value) => Some(value.with_timezone(&Utc)),
        LocalResult::Ambiguous(earlier, _) => Some(earlier.with_timezone(&Utc)),
        LocalResult::None => None,
    }
}

/// Calculates the UTC delta between the base event and one occurrence.
fn utc_delta_for_occurrence(
    timezone: Tz,
    base_starts_at: NaiveDateTime,
    occurrence_starts_at: NaiveDateTime,
) -> Option<TimeDelta> {
    Some(to_utc(timezone, occurrence_starts_at)? - to_utc(timezone, base_starts_at)?)
}

#[cfg(test)]
mod tests {
    use chrono::{NaiveDate, NaiveTime};
    use serde_json::json;

    use super::*;

    #[test]
    fn build_occurrence_payload_rejects_invalid_payload_shapes_and_dates() {
        // Setup recurrence inputs
        let base_starts_at = at(2030, 1, 7);
        let occurrence_starts_at = at(2030, 1, 14);
        let timezone: Tz = "UTC".parse().unwrap();

        // Check non-object payload rejection
        let non_object_err = unwrap_err_message(build_occurrence_payload(
            &json!([]),
            base_starts_at,
            occurrence_starts_at,
            timezone,
        ));
        assert!(non_object_err.contains("event payload must be an object"));

        // Check invalid local datetime rejection
        let invalid_local_date_err = unwrap_err_message(build_occurrence_payload(
            &json!({ "starts_at": "not-a-local-date" }),
            base_starts_at,
            occurrence_starts_at,
            timezone,
        ));
        assert!(invalid_local_date_err.contains("invalid local datetime: not-a-local-date"));

        // Check invalid UTC datetime rejection
        let invalid_utc_date_err = unwrap_err_message(build_occurrence_payload(
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
    fn build_occurrence_payload_shifts_dates_and_refreshes_nested_ids() {
        // Setup recurrence inputs and base payload
        let base_starts_at = NaiveDate::from_ymd_opt(2026, 3, 28)
            .unwrap()
            .and_time(NaiveTime::from_hms_opt(10, 0, 0).unwrap());
        let occurrence_starts_at = NaiveDate::from_ymd_opt(2026, 4, 4)
            .unwrap()
            .and_time(NaiveTime::from_hms_opt(10, 0, 0).unwrap());
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
        let payload =
            build_occurrence_payload(&base_payload, base_starts_at, occurrence_starts_at, timezone).unwrap();

        // Check shifted local datetime fields
        assert_eq!(string_at(&payload, "/cfs_ends_at"), "2026-03-27T20:00:00");
        assert_eq!(string_at(&payload, "/cfs_starts_at"), "2026-03-17T20:00:00");
        assert_eq!(string_at(&payload, "/ends_at"), "2026-04-04T11:00:00");
        assert_eq!(string_at(&payload, "/sessions/0/ends_at"), "2026-04-04T10:45:00");
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
        Uuid::parse_str(string_at(&payload, "/discount_codes/0/event_discount_code_id")).unwrap();
        Uuid::parse_str(string_at(&payload, "/ticket_types/0/event_ticket_type_id")).unwrap();
        Uuid::parse_str(string_at(
            &payload,
            "/ticket_types/0/price_windows/0/event_ticket_price_window_id",
        ))
        .unwrap();
    }

    #[test]
    fn build_recurring_event_payloads_builds_shifted_payloads_and_metadata() {
        // Setup recurring event form and base payload
        let starts_at = at(2030, 1, 7);
        let event = event(EventRecurrencePattern::Weekly, Some(2), Some(starts_at), "UTC");
        let base_payload = json!({
            "ends_at": "2030-01-07T11:00:00",
            "starts_at": "2030-01-07T10:00:00"
        });

        // Build recurring payloads
        let recurring_payloads = build_recurring_event_payloads(&event, &base_payload)
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
    fn build_recurring_event_payloads_returns_none_for_single_events() {
        // Setup single event form and base payload
        let event = Event::default();
        let base_payload = json!({ "starts_at": "2030-01-07T10:00:00" });

        // Build recurring payloads
        let recurring_payloads = build_recurring_event_payloads(&event, &base_payload).unwrap();

        // Check no recurring payloads are generated
        assert!(recurring_payloads.is_none());
    }

    #[test]
    fn build_recurring_event_payloads_validates_recurring_form_fields() {
        // Setup shared recurring event inputs
        let starts_at = at(2030, 1, 7);
        let base_payload = json!({ "starts_at": "2030-01-07T10:00:00" });

        // Check missing additional occurrence count rejection
        let missing_count_err = unwrap_err_message(build_recurring_event_payloads(
            &event(EventRecurrencePattern::Weekly, None, Some(starts_at), "UTC"),
            &base_payload,
        ));
        assert!(missing_count_err.contains("recurring events require recurrence_additional_occurrences"));

        // Check invalid additional occurrence count rejection
        let invalid_count_err = unwrap_err_message(build_recurring_event_payloads(
            &event(
                EventRecurrencePattern::Weekly,
                Some(MAX_RECURRING_ADDITIONAL_OCCURRENCES + 1),
                Some(starts_at),
                "UTC",
            ),
            &base_payload,
        ));
        assert!(invalid_count_err.contains("recurrence_additional_occurrences must be between 1 and 12"));

        // Check missing start date rejection
        let missing_start_err = unwrap_err_message(build_recurring_event_payloads(
            &event(EventRecurrencePattern::Weekly, Some(1), None, "UTC"),
            &base_payload,
        ));
        assert!(missing_start_err.contains("recurring events require starts_at"));

        // Check invalid timezone rejection
        let invalid_timezone_err = unwrap_err_message(build_recurring_event_payloads(
            &event(
                EventRecurrencePattern::Weekly,
                Some(1),
                Some(starts_at),
                "bad/timezone",
            ),
            &base_payload,
        ));
        assert!(invalid_timezone_err.contains("invalid event timezone"));
    }

    #[test]
    fn monthly_occurrences_start_times_skips_missing_ordinal_weekdays() {
        // Setup fifth Tuesday recurrence anchor
        let starts_at = at(2030, 1, 29);

        // Generate monthly occurrence start times
        let occurrence_start_times = occurrences_start_times(starts_at, EventRecurrencePattern::Monthly, 2);

        // Check months without a fifth Tuesday are skipped
        assert_eq!(occurrence_start_times, vec![at(2030, 4, 30), at(2030, 7, 30)]);
    }

    #[test]
    fn nth_weekday_in_month_returns_none_when_ordinal_is_missing() {
        // Find present and missing ordinal weekdays
        let fifth_monday = nth_weekday_in_month(2030, 2, Weekday::Mon, 5);
        let second_monday = nth_weekday_in_month(2030, 2, Weekday::Mon, 2);

        // Check missing ordinal returns none
        assert_eq!(fifth_monday, None);
        assert_eq!(second_monday, Some(NaiveDate::from_ymd_opt(2030, 2, 11).unwrap()));
    }

    #[test]
    fn occurrences_start_times_supports_weekly_and_biweekly_patterns() {
        // Setup weekly recurrence anchor
        let starts_at = at(2030, 1, 7);

        // Generate weekly and biweekly start times
        let weekly_start_times = occurrences_start_times(starts_at, EventRecurrencePattern::Weekly, 2);
        let biweekly_start_times = occurrences_start_times(starts_at, EventRecurrencePattern::Biweekly, 2);

        // Check expected weekly intervals
        assert_eq!(weekly_start_times, vec![at(2030, 1, 14), at(2030, 1, 21)]);
        assert_eq!(biweekly_start_times, vec![at(2030, 1, 21), at(2030, 2, 4)]);
    }

    #[test]
    fn to_utc_resolves_ambiguous_and_missing_local_times() {
        // Setup DST edge-case local times
        let timezone: Tz = "Europe/Madrid".parse().unwrap();
        let ambiguous = NaiveDate::from_ymd_opt(2026, 10, 25)
            .unwrap()
            .and_time(NaiveTime::from_hms_opt(2, 30, 0).unwrap());
        let missing = NaiveDate::from_ymd_opt(2026, 3, 29)
            .unwrap()
            .and_time(NaiveTime::from_hms_opt(2, 30, 0).unwrap());

        // Check ambiguous times are resolved and missing times are rejected
        assert_eq!(
            to_utc(timezone, ambiguous).unwrap().to_rfc3339(),
            "2026-10-25T00:30:00+00:00"
        );
        assert_eq!(to_utc(timezone, missing), None);
    }

    #[test]
    fn utc_delta_for_occurrence_returns_none_for_missing_local_times() {
        // Setup recurrence crossing a spring-forward DST gap
        let timezone: Tz = "Europe/Madrid".parse().unwrap();
        let base_starts_at = NaiveDate::from_ymd_opt(2026, 3, 22)
            .unwrap()
            .and_time(NaiveTime::from_hms_opt(2, 30, 0).unwrap());
        let occurrence_starts_at = NaiveDate::from_ymd_opt(2026, 3, 29)
            .unwrap()
            .and_time(NaiveTime::from_hms_opt(2, 30, 0).unwrap());

        // Check missing local occurrence start cannot produce a UTC delta
        assert_eq!(
            utc_delta_for_occurrence(timezone, base_starts_at, occurrence_starts_at),
            None
        );
    }

    #[test]
    fn utc_fields_fall_back_to_local_delta_for_missing_occurrence_time() {
        // Setup event recurrence crossing a spring-forward DST gap
        let base_starts_at = NaiveDate::from_ymd_opt(2026, 3, 22)
            .unwrap()
            .and_time(NaiveTime::from_hms_opt(2, 30, 0).unwrap());
        let occurrence_starts_at = NaiveDate::from_ymd_opt(2026, 3, 29)
            .unwrap()
            .and_time(NaiveTime::from_hms_opt(2, 30, 0).unwrap());
        let timezone: Tz = "Europe/Madrid".parse().unwrap();
        let base_payload = json!({
            "discount_codes": [{
                "starts_at": "2026-03-21T01:30:00Z"
            }],
            "starts_at": "2026-03-22T02:30:00"
        });

        // Build shifted occurrence payload
        let payload =
            build_occurrence_payload(&base_payload, base_starts_at, occurrence_starts_at, timezone).unwrap();

        // Check UTC fields use the local one-week delta, not a next-day DST fallback
        assert_eq!(string_at(&payload, "/starts_at"), "2026-03-29T02:30:00");
        assert_eq!(
            string_at(&payload, "/discount_codes/0/starts_at"),
            "2026-03-28T01:30:00Z"
        );
    }

    #[test]
    fn weekly_occurrences_start_times_preserves_weekday_and_time() {
        // Setup weekly recurrence anchor
        let starts_at = at(2030, 1, 7);

        // Generate weekly occurrence start times
        let occurrence_start_times = occurrences_start_times(starts_at, EventRecurrencePattern::Weekly, 2);

        // Check weekday and local time are preserved
        assert_eq!(occurrence_start_times, vec![at(2030, 1, 14), at(2030, 1, 21)]);
    }

    // Helpers.

    /// Builds a test datetime at 10:00:00.
    fn at(year: i32, month: u32, day: u32) -> NaiveDateTime {
        NaiveDate::from_ymd_opt(year, month, day)
            .unwrap()
            .and_time(NaiveTime::from_hms_opt(10, 0, 0).unwrap())
    }

    /// Builds a test event with recurrence fields populated.
    fn event(
        pattern: EventRecurrencePattern,
        additional_occurrences: Option<i32>,
        starts_at: Option<NaiveDateTime>,
        timezone: &str,
    ) -> Event {
        Event {
            recurrence_additional_occurrences: additional_occurrences,
            recurrence_pattern: Some(pattern),
            starts_at,
            timezone: timezone.to_string(),
            ..Default::default()
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
}
