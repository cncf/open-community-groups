//! Recurrence helpers for dashboard event creation.

use anyhow::{Context, Result, bail};
use chrono::{
    DateTime, Datelike, LocalResult, NaiveDate, NaiveDateTime, SecondsFormat, TimeDelta, TimeZone, Utc,
    Weekday,
};
use chrono_tz::Tz;
use serde_json::{Map, Value, json};
use uuid::Uuid;

use crate::{
    templates::dashboard::group::events::{Event, EventRecurrencePattern},
    validation::MAX_RECURRING_ADDITIONAL_OCCURRENCES,
};

/// Event-level local datetime fields shifted for each generated occurrence.
const EVENT_LOCAL_DATETIME_FIELD_NAMES: [&str; 4] = ["cfs_ends_at", "cfs_starts_at", "ends_at", "starts_at"];
/// Start and end field names shared by nested schedule-like payloads.
const START_END_FIELD_NAMES: [&str; 2] = ["ends_at", "starts_at"];

/// Generated event payloads and metadata for recurring event insertion.
pub(super) struct RecurringEventPayloads {
    /// Event payloads in chronological creation order, including the base event.
    pub(super) events: Vec<Value>,
    /// Recurrence metadata stored with the linked event series.
    pub(super) recurrence: Value,
}

impl RecurringEventPayloads {
    /// Builds recurring event payloads when the event form requests recurrence.
    pub(super) fn from_event(event: &Event, base_payload: &Value) -> Result<Option<Self>> {
        // Validate recurrence settings before generating occurrence payloads
        let Some(recurrence_request) = RecurrenceRequest::from_event(event)? else {
            return Ok(None);
        };

        // Generate the local start time for each additional occurrence
        let generated_start_times = Self::occurrence_start_times(&recurrence_request);

        // Build the base event plus each shifted occurrence payload
        let mut events = Vec::with_capacity(recurrence_request.additional_occurrences + 1);
        events.push(base_payload.clone());
        for occurrence_starts_at in generated_start_times {
            events.push(Self::build_occurrence_payload(
                base_payload,
                recurrence_request.base_starts_at,
                occurrence_starts_at,
                recurrence_request.timezone,
            )?);
        }

        Ok(Some(Self {
            events,
            recurrence: recurrence_request.recurrence_metadata()?,
        }))
    }

    /// Builds one shifted event payload for a generated occurrence.
    fn build_occurrence_payload(
        base_payload: &Value,
        base_starts_at: NaiveDateTime,
        occurrence_starts_at: NaiveDateTime,
        timezone: Tz,
    ) -> Result<Value> {
        let mut payload = base_payload.clone();

        // Calculate the local recurrence delta applied to event and nested fields
        let local_delta = occurrence_starts_at - base_starts_at;

        let Some(payload_obj) = payload.as_object_mut() else {
            bail!("event payload must be an object");
        };

        // Shift event-level local datetime fields
        shift_object_local_fields(payload_obj, &EVENT_LOCAL_DATETIME_FIELD_NAMES, local_delta)?;

        // Shift nested date fields and refresh IDs that must be unique per event
        if let Some(value) = payload_obj.get_mut("sessions") {
            Self::shift_session_dates(value, local_delta)?;
        }
        if let Some(value) = payload_obj.get_mut("discount_codes") {
            Self::shift_discount_dates(value, timezone, local_delta)?;
            Self::refresh_discount_code_ids(value);
        }
        if let Some(value) = payload_obj.get_mut("ticket_types") {
            Self::shift_ticket_dates(value, timezone, local_delta)?;
            Self::refresh_ticketing_ids(value);
        }

        Ok(payload)
    }

    /// Generates the local start datetime for each additional occurrence.
    fn occurrence_start_times(recurrence_request: &RecurrenceRequest) -> Vec<NaiveDateTime> {
        match recurrence_request.pattern {
            EventRecurrencePattern::JustOnce => Vec::new(),
            EventRecurrencePattern::Weekly => (1..=recurrence_request.additional_occurrences)
                .map(|index| {
                    let weeks = i64::try_from(index).expect("recurrence index is bounded");
                    recurrence_request.base_starts_at + TimeDelta::weeks(weeks)
                })
                .collect(),
            EventRecurrencePattern::Biweekly => (1..=recurrence_request.additional_occurrences)
                .map(|index| {
                    let weeks = i64::try_from(index * 2).expect("recurrence index is bounded");
                    recurrence_request.base_starts_at + TimeDelta::weeks(weeks)
                })
                .collect(),
            EventRecurrencePattern::Monthly => monthly_occurrences_start_times(
                recurrence_request.base_starts_at,
                recurrence_request.additional_occurrences,
            ),
        }
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

    /// Shifts discount code UTC datetime fields by the local recurrence delta.
    fn shift_discount_dates(value: &mut Value, timezone: Tz, delta: TimeDelta) -> Result<()> {
        let Value::Array(discount_codes) = value else {
            return Ok(());
        };

        // Shift each discount code window when present
        for discount_code in discount_codes {
            if let Some(discount_code_obj) = discount_code.as_object_mut() {
                shift_object_utc_fields(discount_code_obj, timezone, &START_END_FIELD_NAMES, delta)?;
            }
        }

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
                shift_object_local_fields(session_obj, &START_END_FIELD_NAMES, delta)?;
            }
        }

        Ok(())
    }

    /// Shifts ticket price window UTC datetime fields by the local recurrence delta.
    fn shift_ticket_dates(value: &mut Value, timezone: Tz, delta: TimeDelta) -> Result<()> {
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
                    shift_object_utc_fields(price_window_obj, timezone, &START_END_FIELD_NAMES, delta)?;
                }
            }
        }

        Ok(())
    }
}

/// Validated recurrence settings from the submitted event form.
struct RecurrenceRequest {
    additional_occurrences: usize,
    base_starts_at: NaiveDateTime,
    pattern: EventRecurrencePattern,
    timezone: Tz,
}

impl RecurrenceRequest {
    /// Builds a recurrence request when the submitted form asks for a series.
    fn from_event(event: &Event) -> Result<Option<Self>> {
        // Skip recurrence processing when the form requests a single event
        let pattern = event.recurrence_pattern.unwrap_or_default();
        if pattern == EventRecurrencePattern::JustOnce {
            return Ok(None);
        }

        // Validate recurrence settings from the submitted event form
        let additional_occurrences = event
            .recurrence_additional_occurrences
            .context("recurring events require recurrence_additional_occurrences")?;
        let max_occurrences = MAX_RECURRING_ADDITIONAL_OCCURRENCES;
        if !(1..=max_occurrences).contains(&additional_occurrences) {
            bail!("recurrence_additional_occurrences must be between 1 and {max_occurrences}");
        }
        let additional_occurrences: usize = additional_occurrences
            .try_into()
            .context("recurrence_additional_occurrences must be positive")?;
        let base_starts_at = event.starts_at.context("recurring events require starts_at")?;
        let timezone: Tz = event.timezone.parse().context("invalid event timezone")?;

        // Return normalized settings used by payload generation
        Ok(Some(Self {
            additional_occurrences,
            base_starts_at,
            pattern,
            timezone,
        }))
    }

    /// Returns recurrence metadata stored with the linked event series.
    fn recurrence_metadata(&self) -> Result<Value> {
        let pattern = self
            .pattern
            .recurrence_db_value()
            .context("recurring event pattern must be supported by the database")?;

        Ok(json!({
            "additional_occurrences": self.additional_occurrences,
            "pattern": pattern,
        }))
    }
}

// Helpers.

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
    // Anchor the search at the first day of the requested month
    let first_day = NaiveDate::from_ymd_opt(year, month, 1)?;

    // Calculate how many days to move forward to reach the first matching weekday
    let weekday_offset =
        (7 + weekday.num_days_from_monday() - first_day.weekday().num_days_from_monday()) % 7;

    // Move from the first matching weekday to the requested ordinal weekday
    let target_day = 1 + weekday_offset + ((ordinal - 1) * 7);
    let target_date = NaiveDate::from_ymd_opt(year, month, target_day)?;

    // Reject dates that overflowed into the next month
    if target_date.month() == month {
        Some(target_date)
    } else {
        None
    }
}

/// Parses a local datetime from an event payload string.
fn parse_local_datetime(value: &str) -> Result<NaiveDateTime> {
    value
        .parse::<NaiveDateTime>()
        .with_context(|| format!("invalid local datetime: {value}"))
}

/// Shifts a local datetime field by the occurrence delta.
fn shift_local_field(value: &mut Value, delta: TimeDelta) -> Result<()> {
    // Ignore missing, non-string, and empty form values
    let Value::String(raw_value) = value else {
        return Ok(());
    };
    if raw_value.is_empty() {
        return Ok(());
    }

    // Parse, shift, and write the local datetime back in form payload format
    let shifted = parse_local_datetime(raw_value)? + delta;
    *raw_value = format_naive_datetime(shifted);

    Ok(())
}

/// Shifts local datetime object fields by the occurrence delta.
fn shift_object_local_fields(
    object: &mut Map<String, Value>,
    field_names: &[&str],
    delta: TimeDelta,
) -> Result<()> {
    for field_name in field_names.iter().copied() {
        if let Some(value) = object.get_mut(field_name) {
            shift_local_field(value, delta)?;
        }
    }

    Ok(())
}

/// Shifts RFC3339 UTC object fields while preserving local wall-clock time.
fn shift_object_utc_fields(
    object: &mut Map<String, Value>,
    timezone: Tz,
    field_names: &[&str],
    delta: TimeDelta,
) -> Result<()> {
    for field_name in field_names.iter().copied() {
        if let Some(value) = object.get_mut(field_name) {
            shift_rfc3339_field_preserving_wall_time(value, timezone, delta)?;
        }
    }

    Ok(())
}

/// Shifts an RFC3339 field by preserving its local wall-clock time.
fn shift_rfc3339_field_preserving_wall_time(value: &mut Value, timezone: Tz, delta: TimeDelta) -> Result<()> {
    // Ignore missing, non-string, and empty form values
    let Value::String(raw_value) = value else {
        return Ok(());
    };
    if raw_value.is_empty() {
        return Ok(());
    }

    // Parse the stored UTC instant and shift its local wall-clock representation
    let base_utc = DateTime::parse_from_rfc3339(raw_value)
        .with_context(|| format!("invalid UTC datetime: {raw_value}"))?
        .with_timezone(&Utc);
    let shifted_local = base_utc.with_timezone(&timezone).naive_local() + delta;

    // Resolve the shifted local time back to UTC, falling back across DST gaps
    let shifted = to_utc(timezone, shifted_local).unwrap_or(base_utc + delta);
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

#[cfg(test)]
mod tests {
    use chrono::{NaiveDate, NaiveTime};
    use serde_json::json;

    use super::*;

    // Public constructor behavior.

    #[test]
    fn from_event_builds_weekly_series_payloads_and_metadata() {
        // Setup recurring event form and base payload
        let starts_at = at(2030, 1, 7);
        let event = sample_event(EventRecurrencePattern::Weekly, Some(2), Some(starts_at), "UTC");
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
    fn from_event_rejects_invalid_recurrence_settings() {
        // Setup shared recurring event inputs
        let base_starts_at = at(2030, 1, 7);
        let base_payload = json!({ "starts_at": "2030-01-07T10:00:00" });

        // Check missing additional occurrence count rejection
        let missing_count_err = unwrap_err_message(RecurringEventPayloads::from_event(
            &sample_event(EventRecurrencePattern::Weekly, None, Some(base_starts_at), "UTC"),
            &base_payload,
        ));
        assert!(missing_count_err.contains("recurring events require recurrence_additional_occurrences"));

        // Check invalid additional occurrence count rejection
        let invalid_count_err = unwrap_err_message(RecurringEventPayloads::from_event(
            &sample_event(
                EventRecurrencePattern::Weekly,
                Some(MAX_RECURRING_ADDITIONAL_OCCURRENCES + 1),
                Some(base_starts_at),
                "UTC",
            ),
            &base_payload,
        ));
        assert!(invalid_count_err.contains("recurrence_additional_occurrences must be between 1 and 12"));

        // Check missing start date rejection
        let missing_start_err = unwrap_err_message(RecurringEventPayloads::from_event(
            &sample_event(EventRecurrencePattern::Weekly, Some(1), None, "UTC"),
            &base_payload,
        ));
        assert!(missing_start_err.contains("recurring events require starts_at"));

        // Check invalid timezone rejection
        let invalid_timezone_err = unwrap_err_message(RecurringEventPayloads::from_event(
            &sample_event(
                EventRecurrencePattern::Weekly,
                Some(1),
                Some(base_starts_at),
                "bad/timezone",
            ),
            &base_payload,
        ));
        assert!(invalid_timezone_err.contains("invalid event timezone"));
    }

    #[test]
    fn from_event_returns_none_for_single_event() {
        // Setup single event form and base payload
        let event = Event::default();
        let base_payload = json!({ "starts_at": "2030-01-07T10:00:00" });

        // Build recurring payloads
        let recurring_payloads = RecurringEventPayloads::from_event(&event, &base_payload).unwrap();

        // Check no recurring payloads are generated
        assert!(recurring_payloads.is_none());
    }

    // Occurrence payload behavior.

    #[test]
    fn occurrence_payload_rejects_invalid_payload_shapes_and_dates() {
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
        let invalid_local_date_err = unwrap_err_message(RecurringEventPayloads::build_occurrence_payload(
            &json!({ "starts_at": "not-a-local-date" }),
            base_starts_at,
            occurrence_starts_at,
            timezone,
        ));
        assert!(invalid_local_date_err.contains("invalid local datetime: not-a-local-date"));

        // Check invalid UTC datetime rejection
        let invalid_utc_date_err = unwrap_err_message(RecurringEventPayloads::build_occurrence_payload(
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
    fn occurrence_payload_shifts_local_and_utc_dates_and_refreshes_ids() {
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
    fn occurrence_payload_falls_back_across_missing_dst_local_time() {
        // Setup event recurrence with a UTC field shifted into a spring-forward gap
        let base_starts_at = NaiveDate::from_ymd_opt(2026, 3, 22)
            .unwrap()
            .and_time(NaiveTime::from_hms_opt(2, 30, 0).unwrap());
        let occurrence_starts_at = NaiveDate::from_ymd_opt(2026, 3, 29)
            .unwrap()
            .and_time(NaiveTime::from_hms_opt(2, 30, 0).unwrap());
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
    fn occurrence_payload_preserves_utc_field_wall_clock_across_dst() {
        // Setup event recurrence crossing DST with ticket windows before the transition
        let base_starts_at = NaiveDate::from_ymd_opt(2026, 3, 22)
            .unwrap()
            .and_time(NaiveTime::from_hms_opt(10, 0, 0).unwrap());
        let occurrence_starts_at = NaiveDate::from_ymd_opt(2026, 3, 29)
            .unwrap()
            .and_time(NaiveTime::from_hms_opt(10, 0, 0).unwrap());
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
    fn occurrence_start_times_preserves_weekday_and_time() {
        // Setup weekly recurrence anchor
        let starts_at = at(2030, 1, 7);
        let recurrence_request = sample_recurrence_request(EventRecurrencePattern::Weekly, 2, starts_at);

        // Generate weekly occurrence start times
        let occurrence_start_times = RecurringEventPayloads::occurrence_start_times(&recurrence_request);

        // Check weekday and local time are preserved
        assert_eq!(occurrence_start_times, vec![at(2030, 1, 14), at(2030, 1, 21)]);
    }

    #[test]
    fn occurrence_start_times_skips_months_without_matching_ordinal_weekday() {
        // Setup fifth Tuesday recurrence anchor
        let starts_at = at(2030, 1, 29);
        let recurrence_request = sample_recurrence_request(EventRecurrencePattern::Monthly, 2, starts_at);

        // Generate monthly occurrence start times
        let occurrence_start_times = RecurringEventPayloads::occurrence_start_times(&recurrence_request);

        // Check months without a fifth Tuesday are skipped
        assert_eq!(occurrence_start_times, vec![at(2030, 4, 30), at(2030, 7, 30)]);
    }

    #[test]
    fn occurrence_start_times_supports_weekly_and_biweekly_patterns() {
        // Setup weekly recurrence anchor
        let starts_at = at(2030, 1, 7);
        let biweekly_request = sample_recurrence_request(EventRecurrencePattern::Biweekly, 2, starts_at);
        let weekly_request = sample_recurrence_request(EventRecurrencePattern::Weekly, 2, starts_at);

        // Generate weekly and biweekly start times
        let weekly_start_times = RecurringEventPayloads::occurrence_start_times(&weekly_request);
        let biweekly_start_times = RecurringEventPayloads::occurrence_start_times(&biweekly_request);

        // Check expected weekly intervals
        assert_eq!(weekly_start_times, vec![at(2030, 1, 14), at(2030, 1, 21)]);
        assert_eq!(biweekly_start_times, vec![at(2030, 1, 21), at(2030, 2, 4)]);
    }

    // Date and timezone helper behavior.

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

    // Helpers.

    /// Builds a test datetime at 10:00:00.
    fn at(year: i32, month: u32, day: u32) -> NaiveDateTime {
        NaiveDate::from_ymd_opt(year, month, day)
            .unwrap()
            .and_time(NaiveTime::from_hms_opt(10, 0, 0).unwrap())
    }

    /// Builds a test event with recurrence fields populated.
    fn sample_event(
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
}
