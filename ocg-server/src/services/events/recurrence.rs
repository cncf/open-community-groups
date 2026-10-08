//! Recurrence helpers for event series creation.

use std::collections::HashMap;

use anyhow::{Context, Result, bail};
use chrono::{
    DateTime, Datelike, LocalResult, NaiveDate, NaiveDateTime, SecondsFormat, TimeDelta, TimeZone,
    Utc, Weekday,
};
use chrono_tz::Tz;
use serde_json::{Map, Value, json};
use uuid::Uuid;

use crate::{
    types::dashboard::group::events::{EventInput, EventRecurrencePattern},
    validation::MAX_RECURRING_ADDITIONAL_OCCURRENCES,
};

#[cfg(test)]
mod tests;

/// Event-level local datetime fields shifted for each generated occurrence.
const EVENT_LOCAL_DATETIME_FIELD_NAMES: [&str; 6] = [
    "cfs_ends_at",
    "cfs_starts_at",
    "ends_at",
    "registration_ends_at",
    "registration_starts_at",
    "starts_at",
];
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
    pub(super) fn from_event(event: &EventInput, base_payload: &Value) -> Result<Option<Self>> {
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
        Self::refresh_label_ids(payload_obj);
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

    /// Replaces label identifiers for a generated occurrence, marking the labels
    /// as new and pointing session label references at the replacements.
    /// Unknown session label IDs are left unchanged for the database to reject.
    fn refresh_label_ids(payload_obj: &mut Map<String, Value>) {
        // Assign a new identifier to each label, remembering the replacement
        let mut label_ids = HashMap::new();
        if let Some(Value::Array(labels)) = payload_obj.get_mut("labels") {
            for label in labels {
                if let Some(label_obj) = label.as_object_mut() {
                    let new_label_id = Uuid::new_v4().to_string();
                    if let Some(Value::String(label_id)) = label_obj.get("event_label_id") {
                        label_ids.insert(label_id.clone(), new_label_id.clone());
                    }
                    label_obj.insert("event_label_id".to_string(), Value::String(new_label_id));
                    label_obj.insert("is_new".to_string(), Value::Bool(true));
                }
            }
        }

        // Point session label references at the occurrence labels
        if let Some(Value::Array(sessions)) = payload_obj.get_mut("sessions") {
            for session in sessions {
                if let Some(Value::Array(session_label_ids)) = session.get_mut("label_ids") {
                    for session_label_id in session_label_ids {
                        if let Some(new_label_id) =
                            session_label_id.as_str().and_then(|id| label_ids.get(id))
                        {
                            *session_label_id = Value::String(new_label_id.clone());
                        }
                    }
                }
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

                if let Some(Value::Array(price_windows)) = ticket_type_obj.get_mut("price_windows")
                {
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
                shift_object_utc_fields(
                    discount_code_obj,
                    timezone,
                    &START_END_FIELD_NAMES,
                    delta,
                )?;
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
                    shift_object_utc_fields(
                        price_window_obj,
                        timezone,
                        &START_END_FIELD_NAMES,
                        delta,
                    )?;
                }
            }
        }

        Ok(())
    }
}

/// Validated recurrence settings from the submitted event form.
struct RecurrenceRequest {
    /// Number of occurrences created after the base event.
    additional_occurrences: usize,
    /// Base event start time in its local timezone.
    base_starts_at: NaiveDateTime,
    /// Recurrence cadence selected by the organizer.
    pattern: EventRecurrencePattern,
    /// Timezone used to expand local occurrence dates.
    timezone: Tz,
}

impl RecurrenceRequest {
    /// Builds a recurrence request when the submitted form asks for a series.
    fn from_event(event: &EventInput) -> Result<Option<Self>> {
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
fn nth_weekday_in_month(
    year: i32,
    month: u32,
    weekday: Weekday,
    ordinal: u32,
) -> Option<NaiveDate> {
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
fn shift_rfc3339_field_preserving_wall_time(
    value: &mut Value,
    timezone: Tz,
    delta: TimeDelta,
) -> Result<()> {
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
