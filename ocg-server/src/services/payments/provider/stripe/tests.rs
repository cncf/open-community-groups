use std::collections::BTreeMap;

use axum::http::{HeaderMap, HeaderValue};
use chrono::{TimeDelta, Utc};
use uuid::Uuid;

use crate::{
    config::PaymentsStripeConfig,
    services::payments::{
        CreateCheckoutSessionInput, FindRefundInput, PaymentsProvider, PaymentsWebhookEvent,
        RefundPaymentInput, RefundPaymentStatus,
    },
    types::payments::{GroupPaymentRecipient, PaymentMode, PaymentProvider},
};

use super::{StripeListedRefund, StripeProvider};

#[test]
fn build_checkout_session_form_fields_populates_checkout_metadata() {
    let provider = sample_stripe_provider();
    let input = sample_checkout_session_input();

    let form_fields = checkout_session_form_fields_map(&provider, &input);

    assert_eq!(
        form_fields.get("cancel_url"),
        Some(
            &"https://ocg.example.org/community/group/pretty-group/event/event?payment=canceled"
                .to_string()
        )
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
        Some(
            &"https://ocg.example.org/community/group/pretty-group/event/event?payment=success"
                .to_string()
        )
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
fn build_refund_form_fields_reverses_destination_transfer() {
    // Setup a refund for a destination charge
    let input = sample_refund_payment_input();

    // Build the provider form fields
    let form_fields = StripeProvider::build_refund_form_fields(&input);

    // Check the refund targets the payment and reverses its transfer
    assert_eq!(form_fields.get("amount"), Some(&"2500".to_string()));
    assert_eq!(
        form_fields.get("metadata[event_purchase_id]"),
        Some(&input.purchase_id.to_string())
    );
    assert_eq!(
        form_fields.get("payment_intent"),
        Some(&"pi_test_123".to_string())
    );
    assert_eq!(
        form_fields.get("reverse_transfer"),
        Some(&"true".to_string())
    );
}

#[test]
fn checkout_idempotency_key_is_deterministic_per_purchase() {
    let purchase_id = Uuid::new_v4();

    assert_eq!(
        StripeProvider::checkout_idempotency_key(purchase_id),
        format!("event-purchase-checkout-{purchase_id}")
    );
}

#[test]
fn find_matching_refund_result_ignores_terminal_refunds_when_unpinned() {
    // Setup an unpinned purchase refund lookup
    let purchase_id = Uuid::new_v4();
    let input = sample_find_refund_input(purchase_id);

    for status in ["canceled", "failed"] {
        // Find refunds without pinning a provider refund id
        let refunds = vec![sample_listed_refund(purchase_id, "re_test_123", status)];

        // Check terminal refunds do not block a fresh attempt
        assert_eq!(
            StripeProvider::find_matching_refund_result(&input, refunds)
                .expect("refund lookup to parse"),
            None,
            "expected {status} refund to be ignored"
        );
    }
}

#[test]
fn find_matching_refund_result_prefers_succeeded_refunds() {
    // Setup matching pending and successful provider refunds
    let purchase_id = Uuid::new_v4();
    let input = sample_find_refund_input(purchase_id);
    let refunds = vec![
        sample_listed_refund(purchase_id, "re_pending_123", "pending"),
        sample_listed_refund(purchase_id, "re_succeeded_123", "succeeded"),
    ];

    // Find the most useful matching provider refund
    let refund = StripeProvider::find_matching_refund_result(&input, refunds)
        .expect("refund lookup to parse")
        .expect("matching refund to exist");

    // Check provider success takes precedence over pending state
    assert_eq!(refund.provider_refund_id, "re_succeeded_123");
    assert_eq!(refund.status, RefundPaymentStatus::Succeeded);
}

#[test]
fn find_matching_refund_result_returns_matching_succeeded_refund() {
    // Setup a matching successful provider refund
    let purchase_id = Uuid::new_v4();
    let input = sample_find_refund_input(purchase_id);
    let refunds = vec![sample_listed_refund(
        purchase_id,
        "re_test_123",
        "succeeded",
    )];

    // Find the matching provider refund
    let refund = StripeProvider::find_matching_refund_result(&input, refunds)
        .expect("refund lookup to parse")
        .expect("succeeded refund to match");

    // Check the matching successful refund is returned
    assert_eq!(refund.provider_refund_id, "re_test_123");
    assert_eq!(refund.status, RefundPaymentStatus::Succeeded);
}

#[test]
fn find_matching_refund_result_returns_pending_refund_statuses() {
    // Setup a purchase refund lookup
    let purchase_id = Uuid::new_v4();
    let input = sample_find_refund_input(purchase_id);

    for status in ["pending", "requires_action"] {
        // Find each pending provider refund status
        let refunds = vec![sample_listed_refund(purchase_id, "re_test_123", status)];
        let refund = StripeProvider::find_matching_refund_result(&input, refunds)
            .expect("refund lookup to parse")
            .expect("pending refund to match");

        // Check the provider status maps to a pending refund
        assert_eq!(refund.status, RefundPaymentStatus::Pending);
    }
}

#[test]
fn find_matching_refund_result_returns_terminal_refund_when_pinned() {
    // Setup a lookup pinned to a terminal provider refund
    let purchase_id = Uuid::new_v4();
    let mut input = sample_find_refund_input(purchase_id);
    input.provider_refund_id = Some("re_failed_123".to_string());
    let refunds = vec![sample_listed_refund(purchase_id, "re_failed_123", "failed")];

    // Find the pinned provider refund
    let refund = StripeProvider::find_matching_refund_result(&input, refunds)
        .expect("refund lookup to parse")
        .expect("pinned refund to match");

    // Check the pinned terminal refund is returned for reconciliation
    assert_eq!(refund.provider_refund_id, "re_failed_123");
    assert_eq!(refund.status, RefundPaymentStatus::Failed);
}

#[test]
fn refund_result_rejects_unknown_statuses() {
    // Map an unsupported provider refund status
    let err = StripeProvider::refund_result("re_test_123".to_string(), "unknown")
        .expect_err("unknown refund status should be rejected");

    // Check the unsupported status remains actionable
    assert_eq!(err.to_string(), "unsupported Stripe refund status: unknown");
}

#[test]
fn verify_and_parse_webhook_accepts_recent_signature() {
    // Setup provider and webhook payload
    let provider = sample_stripe_provider();
    let body = r#"{"type":"checkout.session.completed","data":{"object":{"id":"cs_test_123","payment_intent":"pi_test_123"}}}"#;
    let signature_header = sample_signature_header(body, Utc::now().timestamp());

    // Verify and parse the webhook payload
    let webhook_event = provider
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
        .expect("recent webhook to verify");

    // Check the parsed event matches expectations
    assert_eq!(
        webhook_event,
        PaymentsWebhookEvent::CheckoutCompleted {
            provider_session_id: "cs_test_123".to_string(),

            provider_payment_reference: Some("pi_test_123".to_string()),
        }
    );
}

#[test]
fn verify_and_parse_webhook_accepts_any_matching_v1_signature() {
    // Setup provider and webhook payload
    let provider = sample_stripe_provider();
    let body = r#"{"type":"checkout.session.completed","data":{"object":{"id":"cs_test_123","payment_intent":"pi_test_123"}}}"#;
    let timestamp = Utc::now().timestamp();
    let expected_signature =
        StripeProvider::compute_signature("whsec_test", &format!("{timestamp}.{body}"));
    let rotated_signature =
        StripeProvider::compute_signature("whsec_rotated", &format!("{timestamp}.{body}"));
    let signature_header = format!("t={timestamp},v1={expected_signature},v1={rotated_signature}");

    // Verify and parse the webhook payload
    let webhook_event = provider
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
        .expect("rotated webhook to verify");

    // Check the parsed event matches expectations
    assert_eq!(
        webhook_event,
        PaymentsWebhookEvent::CheckoutCompleted {
            provider_session_id: "cs_test_123".to_string(),

            provider_payment_reference: Some("pi_test_123".to_string()),
        }
    );
}

#[test]
fn verify_and_parse_webhook_maps_checkout_session_expired_events() {
    // Setup provider and webhook payload
    let provider = sample_stripe_provider();
    let body = r#"{"type":"checkout.session.expired","data":{"object":{"id":"cs_test_123","payment_intent":null}}}"#;
    let signature_header = sample_signature_header(body, Utc::now().timestamp());

    // Verify and parse the webhook payload
    let webhook_event = provider
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
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
fn verify_and_parse_webhook_maps_refund_lifecycle_events() {
    // Setup provider and refund lifecycle scenarios
    let provider = sample_stripe_provider();
    let purchase_id = Uuid::new_v4();
    let scenarios = [
        ("refund.created", "pending", RefundPaymentStatus::Pending),
        ("refund.failed", "failed", RefundPaymentStatus::Failed),
        (
            "refund.updated",
            "succeeded",
            RefundPaymentStatus::Succeeded,
        ),
    ];

    for (event_type, status, expected_status) in scenarios {
        let body = format!(
            r#"{{"type":"{event_type}","data":{{"object":{{"id":"re_test_123","amount":2500,"currency":"usd","metadata":{{"event_purchase_id":"{purchase_id}"}},"payment_intent":"pi_test_123","status":"{status}"}}}}}}"#
        );
        let signature_header = sample_signature_header(&body, Utc::now().timestamp());

        // Verify and parse the webhook payload
        let webhook_event = provider
            .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), &body)
            .expect("refund webhook to verify");

        // Check the parsed event matches expectations
        assert_eq!(
            webhook_event,
            PaymentsWebhookEvent::RefundUpdated {
                amount_minor: 2_500,
                currency_code: "usd".to_string(),
                provider_payment_reference: "pi_test_123".to_string(),
                provider_refund_id: "re_test_123".to_string(),
                purchase_id,
                status: expected_status,
            }
        );
    }
}

#[test]
fn verify_and_parse_webhook_ignores_refunds_without_purchase_metadata() {
    // Setup provider and webhook payload
    let provider = sample_stripe_provider();
    let body =
        r#"{"type":"refund.updated","data":{"object":{"id":"re_test_123","status":"succeeded"}}}"#;
    let signature_header = sample_signature_header(body, Utc::now().timestamp());

    // Verify and parse the webhook payload
    let webhook_event = provider
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
        .expect("unrelated refund webhook to verify");

    // Check the unrelated refund is acknowledged without reconciliation
    assert_eq!(webhook_event, PaymentsWebhookEvent::Noop);
}

#[test]
fn verify_and_parse_webhook_rejects_incomplete_refund_events() {
    // Setup provider and incomplete OCG refund payloads
    let provider = sample_stripe_provider();
    let purchase_id = Uuid::new_v4();
    let scenarios = [
        (
            format!(
                r#"{{"type":"refund.updated","data":{{"object":{{"id":"re_test_123","currency":"usd","metadata":{{"event_purchase_id":"{purchase_id}"}},"payment_intent":"pi_test_123","status":"succeeded"}}}}}}"#
            ),
            "Stripe refund webhook is missing amount",
        ),
        (
            format!(
                r#"{{"type":"refund.updated","data":{{"object":{{"id":"re_test_123","amount":2500,"metadata":{{"event_purchase_id":"{purchase_id}"}},"payment_intent":"pi_test_123","status":"succeeded"}}}}}}"#
            ),
            "Stripe refund webhook is missing currency",
        ),
        (
            format!(
                r#"{{"type":"refund.updated","data":{{"object":{{"id":"re_test_123","amount":2500,"currency":"usd","metadata":{{"event_purchase_id":"{purchase_id}"}},"status":"succeeded"}}}}}}"#
            ),
            "Stripe refund webhook is missing payment intent",
        ),
    ];

    for (body, expected_error) in scenarios {
        // Sign and parse each incomplete provider payload
        let signature_header = sample_signature_header(&body, Utc::now().timestamp());
        let err = provider
            .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), &body)
            .expect_err("incomplete refund webhook to fail");

        // Check the missing financial field is identified
        assert_eq!(err.to_string(), expected_error);
    }
}

#[test]
fn verify_and_parse_webhook_rejects_invalid_signature() {
    // Setup provider and webhook payload
    let provider = sample_stripe_provider();
    let body = r#"{"type":"checkout.session.completed","data":{"object":{"id":"cs_test_123","payment_intent":"pi_test_123"}}}"#;
    let signature_header = format!("t={},v1=invalid", Utc::now().timestamp());

    // Verify and parse the webhook payload
    let err = provider
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
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
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
        .expect_err("webhook without object data to be rejected");

    // Check the returned error matches expectations
    assert_eq!(
        err.to_string(),
        "Stripe webhook payload is missing object data"
    );
}

#[test]
fn verify_and_parse_webhook_rejects_missing_signature() {
    // Setup provider and webhook payload
    let provider = sample_stripe_provider();
    let body = r#"{"type":"checkout.session.completed","data":{"object":{"id":"cs_test_123","payment_intent":"pi_test_123"}}}"#;
    let signature_header = format!("t={}", Utc::now().timestamp());

    // Verify and parse the webhook payload
    let err = provider
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
        .expect_err("webhook without signature to be rejected");

    // Check the returned error matches expectations
    assert_eq!(err.to_string(), "missing Stripe webhook signature");
}

#[test]
fn verify_and_parse_webhook_rejects_missing_timestamp() {
    // Setup provider and webhook payload
    let provider = sample_stripe_provider();
    let body = r#"{"type":"checkout.session.completed","data":{"object":{"id":"cs_test_123","payment_intent":"pi_test_123"}}}"#;
    let signature = StripeProvider::compute_signature(
        "whsec_test",
        &format!("{}.{body}", Utc::now().timestamp()),
    );
    let signature_header = format!("v1={signature}");

    // Verify and parse the webhook payload
    let err = provider
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
        .expect_err("webhook without timestamp to be rejected");

    // Check the returned error matches expectations
    assert_eq!(err.to_string(), "missing Stripe webhook timestamp");
}

#[test]
fn verify_and_parse_webhook_rejects_stale_signature() {
    // Setup provider and stale webhook payload
    let provider = sample_stripe_provider();
    let body = r#"{"type":"checkout.session.expired","data":{"object":{"id":"cs_test_123","payment_intent":null}}}"#;
    let signature_header =
        sample_signature_header(body, (Utc::now() - TimeDelta::minutes(10)).timestamp());

    // Verify and parse the webhook payload
    let err = provider
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
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
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
        .expect_err("unsupported webhook event to be rejected");

    // Check the returned error matches expectations
    assert_eq!(
        err.to_string(),
        "unsupported Stripe webhook event: payment_intent.succeeded"
    );
}

// Helpers.

/// Converts checkout session form fields into a map for assertions.
fn checkout_session_form_fields_map(
    provider: &StripeProvider,
    input: &CreateCheckoutSessionInput,
) -> BTreeMap<String, String> {
    provider
        .build_checkout_session_form_fields(input)
        .into_iter()
        .collect()
}

/// Creates sample checkout session input.
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
        group_slug_pretty: Some("pretty-group".to_string()),
    }
}

/// Creates sample refund lookup input.
fn sample_find_refund_input(purchase_id: Uuid) -> FindRefundInput {
    FindRefundInput {
        amount_minor: 2_500,
        provider_payment_reference: "pi_test_123".to_string(),
        purchase_id,

        provider_refund_id: None,
    }
}

/// Creates sample Stripe refund list item.
fn sample_listed_refund(purchase_id: Uuid, id: &str, status: &str) -> StripeListedRefund {
    StripeListedRefund {
        amount: 2_500,
        id: id.to_string(),
        status: status.to_string(),

        metadata: BTreeMap::from([("event_purchase_id".to_string(), purchase_id.to_string())]),
    }
}

/// Creates sample refund payment input.
fn sample_refund_payment_input() -> RefundPaymentInput {
    RefundPaymentInput {
        amount_minor: 2_500,
        idempotency_key: "event-purchase-refund-test".to_string(),
        provider_payment_reference: "pi_test_123".to_string(),
        purchase_id: Uuid::new_v4(),
    }
}

/// Builds a signed Stripe webhook header for tests.
fn sample_signature_header(body: &str, timestamp: i64) -> String {
    let signature = StripeProvider::compute_signature("whsec_test", &format!("{timestamp}.{body}"));
    format!("t={timestamp},v1={signature}")
}

/// Creates a sample Stripe provider.
fn sample_stripe_provider() -> StripeProvider {
    StripeProvider::new(PaymentsStripeConfig {
        mode: PaymentMode::Test,
        publishable_key: "pk_test".to_string(),
        secret_key: "sk_test".to_string(),
        webhook_secret: "whsec_test".to_string(),
    })
}

/// Creates sample webhook headers with the given signature header value.
fn sample_webhook_headers(signature_header: &str) -> HeaderMap {
    let mut headers = HeaderMap::new();
    headers.insert(
        "stripe-signature",
        HeaderValue::from_str(signature_header).expect("Stripe signature header to be valid"),
    );
    headers
}
