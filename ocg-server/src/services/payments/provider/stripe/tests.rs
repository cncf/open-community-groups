use std::collections::BTreeMap;

use chrono::{TimeDelta, Utc};
use uuid::Uuid;

use crate::{
    config::PaymentsStripeConfig,
    services::payments::{CreateCheckoutSessionInput, PaymentsProvider, PaymentsWebhookEvent},
    types::payments::{GroupPaymentRecipient, PaymentMode, PaymentProvider},
};

use super::StripeProvider;

#[test]
fn build_checkout_session_form_fields_populates_checkout_metadata() {
    let provider = sample_stripe_provider();
    let input = sample_checkout_session_input();

    let form_fields = checkout_session_form_fields_map(&provider, &input);

    assert_eq!(
        form_fields.get("cancel_url"),
        Some(&"https://ocg.example.org/community/group/group/event/event?payment=canceled".to_string())
    );
    assert_eq!(
        form_fields.get("client_reference_id"),
        Some(&input.purchase_id.to_string())
    );
    assert_eq!(
        form_fields.get("line_items[0][price_data][currency]"),
        Some(&"usd".to_string())
    );
    assert_eq!(
        form_fields.get("payment_intent_data[metadata][discount_code]"),
        Some(&"EARLYBIRD".to_string())
    );
    assert_eq!(
        form_fields.get("payment_intent_data[transfer_data][destination]"),
        Some(&"acct_test_123".to_string())
    );
    assert_eq!(
        form_fields.get("metadata[environment]"),
        Some(&"test".to_string())
    );
    assert_eq!(
        form_fields.get("success_url"),
        Some(&"https://ocg.example.org/community/group/group/event/event?payment=success".to_string())
    );
}

#[test]
fn build_checkout_session_form_fields_restricts_checkout_to_card_payments() {
    let provider = sample_stripe_provider();
    let input = sample_checkout_session_input();

    let form_fields = provider.build_checkout_session_form_fields(&input);

    assert!(form_fields.contains(&("payment_method_types[0]".to_string(), "card".to_string())));
}

#[test]
fn verify_and_parse_webhook_accepts_recent_signature() {
    // Setup provider and webhook payload
    let provider = sample_stripe_provider();
    let body = r#"{"type":"checkout.session.completed","data":{"object":{"id":"cs_test_123","payment_intent":"pi_test_123"}}}"#;
    let signature_header = sample_signature_header(body, Utc::now().timestamp());

    // Verify and parse the webhook payload
    let webhook_event = provider
        .verify_and_parse_webhook(&signature_header, body)
        .expect("recent webhook to verify");

    // Check the parsed event matches expectations
    assert_eq!(
        webhook_event,
        PaymentsWebhookEvent::CheckoutCompleted {
            provider_payment_reference: Some("pi_test_123".to_string()),
            provider_session_id: "cs_test_123".to_string(),
        }
    );
}

#[test]
fn verify_and_parse_webhook_maps_checkout_session_expired_events() {
    // Setup provider and webhook payload
    let provider = sample_stripe_provider();
    let body =
        r#"{"type":"checkout.session.expired","data":{"object":{"id":"cs_test_123","payment_intent":null}}}"#;
    let signature_header = sample_signature_header(body, Utc::now().timestamp());

    // Verify and parse the webhook payload
    let webhook_event = provider
        .verify_and_parse_webhook(&signature_header, body)
        .expect("expired webhook to verify");

    // Check the parsed event matches expectations
    assert_eq!(
        webhook_event,
        PaymentsWebhookEvent::CheckoutExpired {
            provider_session_id: "cs_test_123".to_string(),
        }
    );
}

#[test]
fn verify_and_parse_webhook_rejects_invalid_signature() {
    // Setup provider and webhook payload
    let provider = sample_stripe_provider();
    let body = r#"{"type":"checkout.session.completed","data":{"object":{"id":"cs_test_123","payment_intent":"pi_test_123"}}}"#;
    let signature_header = format!("t={},v1=invalid", Utc::now().timestamp());

    // Verify and parse the webhook payload
    let err = provider
        .verify_and_parse_webhook(&signature_header, body)
        .expect_err("invalid webhook signature to be rejected");

    // Check the returned error matches expectations
    assert_eq!(err.to_string(), "invalid Stripe webhook signature");
}

#[test]
fn verify_and_parse_webhook_rejects_missing_object_data() {
    // Setup provider and webhook payload
    let provider = sample_stripe_provider();
    let body = r#"{"type":"checkout.session.completed","data":{"object":null}}"#;
    let signature_header = sample_signature_header(body, Utc::now().timestamp());

    // Verify and parse the webhook payload
    let err = provider
        .verify_and_parse_webhook(&signature_header, body)
        .expect_err("webhook without object data to be rejected");

    // Check the returned error matches expectations
    assert_eq!(err.to_string(), "Stripe webhook payload is missing object data");
}

#[test]
fn verify_and_parse_webhook_rejects_missing_signature() {
    // Setup provider and webhook payload
    let provider = sample_stripe_provider();
    let body = r#"{"type":"checkout.session.completed","data":{"object":{"id":"cs_test_123","payment_intent":"pi_test_123"}}}"#;
    let signature_header = format!("t={}", Utc::now().timestamp());

    // Verify and parse the webhook payload
    let err = provider
        .verify_and_parse_webhook(&signature_header, body)
        .expect_err("webhook without signature to be rejected");

    // Check the returned error matches expectations
    assert_eq!(err.to_string(), "missing Stripe webhook signature");
}

#[test]
fn verify_and_parse_webhook_rejects_missing_timestamp() {
    // Setup provider and webhook payload
    let provider = sample_stripe_provider();
    let body = r#"{"type":"checkout.session.completed","data":{"object":{"id":"cs_test_123","payment_intent":"pi_test_123"}}}"#;
    let signature =
        StripeProvider::compute_signature("whsec_test", &format!("{}.{body}", Utc::now().timestamp()));
    let signature_header = format!("v1={signature}");

    // Verify and parse the webhook payload
    let err = provider
        .verify_and_parse_webhook(&signature_header, body)
        .expect_err("webhook without timestamp to be rejected");

    // Check the returned error matches expectations
    assert_eq!(err.to_string(), "missing Stripe webhook timestamp");
}

#[test]
fn verify_and_parse_webhook_rejects_stale_signature() {
    // Setup provider and stale webhook payload
    let provider = sample_stripe_provider();
    let body =
        r#"{"type":"checkout.session.expired","data":{"object":{"id":"cs_test_123","payment_intent":null}}}"#;
    let signature_header = sample_signature_header(body, (Utc::now() - TimeDelta::minutes(10)).timestamp());

    // Verify and parse the webhook payload
    let err = provider
        .verify_and_parse_webhook(&signature_header, body)
        .expect_err("stale webhook to be rejected");

    // Check the returned error matches expectations
    assert_eq!(err.to_string(), "stale Stripe webhook timestamp");
}

#[test]
fn verify_and_parse_webhook_rejects_unsupported_event_types() {
    // Setup provider and webhook payload
    let provider = sample_stripe_provider();
    let body = r#"{"type":"payment_intent.succeeded","data":{"object":{"id":"pi_test_123","payment_intent":"pi_test_123"}}}"#;
    let signature_header = sample_signature_header(body, Utc::now().timestamp());

    // Verify and parse the webhook payload
    let err = provider
        .verify_and_parse_webhook(&signature_header, body)
        .expect_err("unsupported webhook event to be rejected");

    // Check the returned error matches expectations
    assert_eq!(
        err.to_string(),
        "unsupported Stripe webhook event: payment_intent.succeeded"
    );
}

// Helpers.

/// Convert checkout session form fields into a map for assertions.
fn checkout_session_form_fields_map(
    provider: &StripeProvider,
    input: &CreateCheckoutSessionInput,
) -> BTreeMap<String, String> {
    provider
        .build_checkout_session_form_fields(input)
        .into_iter()
        .collect()
}

/// Create sample checkout session input.
fn sample_checkout_session_input() -> CreateCheckoutSessionInput {
    CreateCheckoutSessionInput {
        amount_minor: 2_500,
        base_url: "https://ocg.example.org".to_string(),
        community_name: "community".to_string(),
        currency_code: "USD".to_string(),
        event_id: Uuid::new_v4(),
        event_slug: "event".to_string(),
        group_slug: "group".to_string(),
        purchase_id: Uuid::new_v4(),
        recipient: GroupPaymentRecipient {
            provider: PaymentProvider::Stripe,
            recipient_id: "acct_test_123".to_string(),
        },
        ticket_title: "Ticket".to_string(),
        user_id: Uuid::new_v4(),

        discount_code: Some("EARLYBIRD".to_string()),
    }
}

/// Build a signed Stripe webhook header for tests.
fn sample_signature_header(body: &str, timestamp: i64) -> String {
    let signature = StripeProvider::compute_signature("whsec_test", &format!("{timestamp}.{body}"));
    format!("t={timestamp},v1={signature}")
}

/// Create a sample Stripe provider.
fn sample_stripe_provider() -> StripeProvider {
    StripeProvider::new(PaymentsStripeConfig {
        mode: PaymentMode::Test,
        publishable_key: "pk_test".to_string(),
        secret_key: "sk_test".to_string(),
        webhook_secret: "whsec_test".to_string(),
    })
}
