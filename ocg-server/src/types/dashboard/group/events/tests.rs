use chrono::{DateTime, Utc};
use garde::Validate;
use serde_json::Value;
use uuid::Uuid;

use crate::{
    types::payments::{
        EventDiscountType, EventTicketTypeAvailability, TicketTaxBehavior, TicketTaxCalculationMode,
    },
    validation::MAX_EVENT_COHOSTS,
};

use super::{
    CohostsUpdate, DiscountCodeInput, EventInput, TicketPriceWindowInput, TicketTypeInput,
};

#[test]
fn cohosts_update_defaults_revision_when_selection_is_submitted() {
    let event = EventInput {
        cohost_group_ids_present: Some(true),
        ..sample_event()
    };

    assert_eq!(
        event.cohosts_update(),
        Some(CohostsUpdate {
            expected_revision: 0,
            group_ids: vec![],
        })
    );
}

#[test]
fn cohosts_update_is_none_without_present_marker() {
    let event = EventInput {
        cohost_group_ids: Some(vec![Uuid::new_v4()]),
        cohosts_revision: Some(2),
        ..sample_event()
    };

    assert!(event.cohosts_update().is_none());
}

#[test]
fn cohosts_update_returns_submitted_selection_and_revision() {
    let group_id = Uuid::new_v4();
    let event: EventInput = serde_qs::from_str(&format!(
        "category_id=00000000-0000-0000-0000-000000000001&description=d&kind_id=virtual&\
name=n&timezone=UTC&cohost_group_ids[0]={group_id}&cohost_group_ids_present=true&\
cohosts_revision=5"
    ))
    .unwrap();

    assert_eq!(
        event.cohosts_update(),
        Some(CohostsUpdate {
            expected_revision: 5,
            group_ids: vec![group_id],
        })
    );
}

#[test]
fn event_validation_rejects_too_many_cohosts() {
    let event = EventInput {
        cohost_group_ids: Some((0..=MAX_EVENT_COHOSTS).map(|_| Uuid::new_v4()).collect()),
        cohost_group_ids_present: Some(true),
        ..sample_event()
    };

    assert!(event.validate().is_err());
}

#[test]
fn discount_code_deserialization_keeps_explicit_availability_override_signals() {
    let discount_code: DiscountCodeInput = serde_qs::from_str(
        "active=true&available=12&available_override_active=true&code=EARLY20&kind=percentage&percentage=20&title=Early%20supporter",
    )
    .unwrap();

    assert_eq!(discount_code.available, Some(12));
    assert_eq!(discount_code.available_override_active, Some(true));
}

#[test]
fn event_deserialization_accepts_nested_registration_questions() {
    let event: EventInput = serde_qs::from_str(
        "\
category_id=00000000-0000-0000-0000-000000000001&\
description=Event%20description&\
kind_id=virtual&\
name=Sample%20Event&\
timezone=UTC&\
registration_questions_present=true&\
registration_questions[0][id]=00000000-0000-0000-0000-000000000101&\
registration_questions[0][kind]=single-select&\
registration_questions[0][prompt]=Meal%20preference&\
registration_questions[0][required]=true&\
registration_questions[0][options][0][id]=00000000-0000-0000-0000-000000000201&\
registration_questions[0][options][0][label]=Vegetarian",
    )
    .unwrap();

    assert!(event.registration_questions_present.is_some());
    assert_eq!(event.registration_questions.len(), 1);
    assert_eq!(event.registration_questions[0].prompt, "Meal preference");
    assert_eq!(
        event.registration_questions[0].options[0].label,
        "Vegetarian"
    );
}

#[test]
fn event_deserialization_tracks_empty_manual_tax_rate_selection() {
    let event: EventInput = serde_qs::from_str(
        "\
category_id=00000000-0000-0000-0000-000000000001&\
description=Event%20description&\
kind_id=virtual&\
manual_tax_rate_ids_present=true&\
name=Sample%20Event&\
tax_calculation_mode=manual&\
timezone=UTC",
    )
    .unwrap();

    assert!(event.manual_tax_rate_ids.is_none());
    assert_eq!(event.manual_tax_rate_ids_present, Some(true));
    assert_eq!(event.tax_calculation_mode, TicketTaxCalculationMode::Manual);
}

#[test]
fn to_db_payload_clears_submitted_empty_external_payment_fields() {
    let mut event = sample_event();
    event.external_payment_instructions_present = Some(true);
    event.external_payment_url_present = Some(true);
    event.external_payment_window_hours_present = Some(true);

    let payload = event.to_db_payload().unwrap();

    assert_eq!(payload["external_payment_instructions"], Value::Null);
    assert_eq!(payload["external_payment_url"], Value::Null);
    assert_eq!(payload["external_payment_window_hours"], Value::Null);
    assert!(payload.get("external_payment_instructions_present").is_none());
    assert!(payload.get("external_payment_url_present").is_none());
    assert!(payload.get("external_payment_window_hours_present").is_none());
}

#[test]
fn to_db_payload_clears_submitted_empty_manual_tax_rate_selection() {
    let mut event = sample_event();
    event.manual_tax_rate_ids_present = Some(true);
    event.tax_calculation_mode = TicketTaxCalculationMode::Manual;

    let payload = event.to_db_payload().unwrap();

    assert_eq!(payload["manual_tax_rate_ids"], serde_json::json!([]));
    assert!(payload.get("manual_tax_rate_ids_present").is_none());
}

#[test]
fn to_db_payload_keeps_optional_section_keys_omitted_when_form_omits_inputs() {
    let payload = sample_event().to_db_payload().unwrap();

    assert_eq!(payload["cfs_labels"], Value::Array(Vec::new()));
    assert_eq!(payload["description"], "Event description");
    assert_eq!(payload["kind_id"], "virtual");
    assert_eq!(payload["name"], "Sample Event");
    assert_eq!(payload["timezone"], "UTC");
    assert!(payload.get("discount_codes").is_none());
    assert!(payload.get("external_payment_instructions").is_none());
    assert!(payload.get("external_payment_url").is_none());
    assert!(payload.get("external_payment_window_hours").is_none());
    assert!(payload.get("registration_questions").is_none());
    assert!(payload.get("ticket_types").is_none());
}

#[test]
fn to_db_payload_keeps_manual_tax_rate_ids() {
    let mut event = sample_event();
    event.manual_tax_rate_ids = Some(vec!["txr_state".to_string(), "txr_local".to_string()]);
    event.manual_tax_rate_ids_present = Some(true);
    event.tax_behavior = TicketTaxBehavior::Exclusive;
    event.tax_calculation_mode = TicketTaxCalculationMode::Manual;

    let payload = event.to_db_payload().unwrap();

    assert_eq!(
        payload["manual_tax_rate_ids"],
        serde_json::json!(["txr_state", "txr_local"])
    );
    assert!(payload.get("manual_tax_rate_ids_present").is_none());
    assert_eq!(payload["tax_behavior"], "exclusive");
    assert_eq!(payload["tax_calculation_mode"], "manual");
}

#[test]
fn to_db_payload_keeps_omitted_manual_tax_rate_selection_absent() {
    let mut event = sample_event();
    event.tax_calculation_mode = TicketTaxCalculationMode::Manual;

    let payload = event.to_db_payload().unwrap();

    assert!(payload.get("manual_tax_rate_ids").is_none());
    assert!(payload.get("manual_tax_rate_ids_present").is_none());
}

#[test]
fn to_db_payload_normalizes_external_event_tax() {
    let mut event = sample_event();
    event.external_payment_url = Some("https://pay.example.test/add".to_string());
    event.manual_tax_rate_ids = Some(vec!["txr_stale".to_string()]);
    event.tax_behavior = TicketTaxBehavior::Exclusive;
    event.tax_calculation_mode = TicketTaxCalculationMode::Automatic;

    let payload = event.to_db_payload().unwrap();

    assert_eq!(payload["manual_tax_rate_ids"], serde_json::json!([]));
    assert_eq!(payload["tax_behavior"], "inclusive");
    assert_eq!(payload["tax_calculation_mode"], "none");
}

#[test]
fn to_db_payload_normalizes_no_tax_configuration() {
    let mut event = sample_event();
    event.manual_tax_rate_ids = Some(vec!["txr_stale".to_string()]);
    event.tax_behavior = TicketTaxBehavior::Exclusive;
    event.tax_calculation_mode = TicketTaxCalculationMode::None;

    let payload = event.to_db_payload().unwrap();

    assert_eq!(payload["manual_tax_rate_ids"], serde_json::json!([]));
    assert_eq!(payload["tax_behavior"], "inclusive");
    assert_eq!(payload["tax_calculation_mode"], "none");
}

#[test]
fn to_db_payload_includes_empty_registration_questions_when_inputs_are_present() {
    let mut event = sample_event();
    event.registration_questions_present = Some(true);

    let payload = event.to_db_payload().unwrap();

    assert_eq!(payload["registration_questions"], Value::Array(Vec::new()));
}

#[test]
fn to_db_payload_removes_cohost_fields() {
    let event = EventInput {
        cohost_group_ids: Some(vec![Uuid::new_v4()]),
        cohost_group_ids_present: Some(true),
        cohosts_revision: Some(3),
        ..sample_event()
    };

    let payload = event.to_db_payload().unwrap();

    assert!(payload.get("cohost_group_ids").is_none());
    assert!(payload.get("cohost_group_ids_present").is_none());
    assert!(payload.get("cohosts_revision").is_none());
}

#[test]
fn to_db_payload_serializes_dated_ticketing_timestamps_as_utc_z() {
    // Setup a dated discount code and price window without a live inventory count
    let starts_at = "2030-01-01T10:00:00Z".parse::<DateTime<Utc>>().unwrap();
    let ends_at = "2030-06-01T10:00:00Z".parse::<DateTime<Utc>>().unwrap();
    let mut event = sample_event();
    event.discount_codes = Some(vec![DiscountCodeInput {
        active: true,
        code: "DATED10".to_string(),
        kind: EventDiscountType::Percentage,
        title: "Dated".to_string(),

        available: None,
        available_override_active: Some(true),
        available_cleared: None,
        amount_minor: None,
        ends_at: Some(ends_at),
        event_discount_code_id: Some(uuid::Uuid::new_v4()),
        percentage: Some(10),
        starts_at: Some(starts_at),
        total_available: Some(10),
    }]);
    event.discount_codes_present = Some(true);
    event.ticket_types = Some(vec![TicketTypeInput {
        active: true,
        availability: EventTicketTypeAvailability::Public,
        order: 1,
        price_windows: vec![TicketPriceWindowInput {
            amount_minor: 2500,

            ends_at: Some(ends_at),
            event_ticket_price_window_id: Some(uuid::Uuid::new_v4()),
            starts_at: Some(starts_at),
        }],
        title: "General".to_string(),

        description: None,
        event_ticket_type_id: Some(uuid::Uuid::new_v4()),
        seats_total: Some(10),
    }]);
    event.ticket_types_present = Some(true);

    // Serialize the payload
    let payload = event.to_db_payload().unwrap();

    // Check timestamps use the Z spelling and the omitted count stays absent
    assert_eq!(
        payload["discount_codes"][0]["ends_at"],
        "2030-06-01T10:00:00Z"
    );
    assert_eq!(
        payload["discount_codes"][0]["starts_at"],
        "2030-01-01T10:00:00Z"
    );
    assert!(payload["discount_codes"][0].get("available").is_none());
    assert_eq!(
        payload["ticket_types"][0]["price_windows"][0]["ends_at"],
        "2030-06-01T10:00:00Z"
    );
    assert_eq!(
        payload["ticket_types"][0]["price_windows"][0]["starts_at"],
        "2030-01-01T10:00:00Z"
    );
}

#[test]
fn to_db_payload_sets_ticketing_keys_to_null_when_inputs_are_present_but_empty() {
    let mut event = sample_event();
    event.discount_codes_present = Some(true);
    event.ticket_types_present = Some(true);

    let payload = event.to_db_payload().unwrap();

    assert_eq!(payload["discount_codes"], Value::Null);
    assert_eq!(payload["ticket_types"], Value::Null);
}

#[test]
fn to_db_payload_accepts_new_ticketing_rows_without_ids() {
    let mut event = sample_event();
    event.discount_codes = Some(vec![DiscountCodeInput {
        active: true,
        code: "EARLY20".to_string(),
        kind: EventDiscountType::Percentage,
        title: "Early supporter".to_string(),

        available: None,
        available_override_active: None,
        available_cleared: None,
        amount_minor: None,
        ends_at: None,
        event_discount_code_id: None,
        percentage: Some(20),
        starts_at: None,
        total_available: None,
    }]);
    event.discount_codes_present = Some(true);
    event.ticket_types = Some(vec![TicketTypeInput {
        active: true,
        availability: EventTicketTypeAvailability::InvitationOnly,
        order: 1,
        price_windows: vec![TicketPriceWindowInput {
            amount_minor: 2500,

            ends_at: None,
            event_ticket_price_window_id: None,
            starts_at: None,
        }],
        title: "General admission".to_string(),

        description: None,
        event_ticket_type_id: None,
        seats_total: Some(100),
    }]);
    event.ticket_types_present = Some(true);

    let payload = event.to_db_payload().unwrap();

    assert_eq!(payload["discount_codes"][0]["code"], "EARLY20");
    assert!(
        uuid::Uuid::parse_str(
            payload["discount_codes"][0]["event_discount_code_id"]
                .as_str()
                .unwrap()
        )
        .is_ok()
    );
    assert_eq!(payload["ticket_types"][0]["title"], "General admission");
    assert_eq!(
        payload["ticket_types"][0]["availability"],
        "invitation_only"
    );
    assert!(
        uuid::Uuid::parse_str(payload["ticket_types"][0]["event_ticket_type_id"].as_str().unwrap())
            .is_ok()
    );
    assert!(
        uuid::Uuid::parse_str(
            payload["ticket_types"][0]["price_windows"][0]["event_ticket_price_window_id"]
                .as_str()
                .unwrap()
        )
        .is_ok()
    );
}

#[test]
fn to_db_payload_keeps_explicit_discount_availability_override_state() {
    let mut event = sample_event();
    event.discount_codes = Some(vec![DiscountCodeInput {
        active: true,
        code: "EARLY20".to_string(),
        kind: EventDiscountType::Percentage,
        title: "Early supporter".to_string(),

        available: None,
        available_override_active: Some(true),
        available_cleared: None,
        amount_minor: None,
        ends_at: None,
        event_discount_code_id: None,
        percentage: Some(20),
        starts_at: None,
        total_available: Some(50),
    }]);
    event.discount_codes_present = Some(true);

    let payload = event.to_db_payload().unwrap();

    assert!(payload["discount_codes"][0].get("available").is_none());
    assert_eq!(
        payload["discount_codes"][0]["available_override_active"],
        Value::Bool(true)
    );
}

#[test]
fn to_db_payload_omits_discount_availability_override_state_when_form_omits_it() {
    let mut event = sample_event();
    event.discount_codes = Some(vec![DiscountCodeInput {
        active: true,
        code: "EARLY20".to_string(),
        kind: EventDiscountType::Percentage,
        title: "Early supporter".to_string(),

        available: None,
        available_override_active: None,
        available_cleared: None,
        amount_minor: None,
        ends_at: None,
        event_discount_code_id: None,
        percentage: Some(20),
        starts_at: None,
        total_available: Some(50),
    }]);
    event.discount_codes_present = Some(true);

    let payload = event.to_db_payload().unwrap();

    assert!(
        payload["discount_codes"][0]
            .get("available_override_active")
            .is_none()
    );
}

// Helpers.

/// Creates a sample event with required fields for testing.
fn sample_event() -> EventInput {
    EventInput {
        category_id: uuid::Uuid::new_v4(),
        description: "Event description".to_string(),
        kind_id: "virtual".to_string(),
        name: "Sample Event".to_string(),
        timezone: "UTC".to_string(),
        ..EventInput::default()
    }
}
