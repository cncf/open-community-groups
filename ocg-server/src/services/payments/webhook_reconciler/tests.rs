use uuid::Uuid;

use crate::{
    db::payments::{EventPurchaseRefund, EventPurchaseRefundKind, EventPurchaseRefundStatus},
    types::payments::{EventPurchaseStatus, EventPurchaseSummary, PaymentProvider},
};

use super::PaymentsWebhookReconciler;

#[test]
fn validate_refund_event_accepts_matching_financial_contract() {
    // Validate the provider event against its purchase and durable refund
    let result = PaymentsWebhookReconciler::validate_refund_event(
        &sample_purchase(),
        &sample_refund(),
        PaymentProvider::Stripe,
        2_500,
        "usd",
        "pi_test_123",
        "re_test_123",
    );

    // Check the current provider attempt is accepted
    assert!(result.expect("matching refund event to validate"));
}

#[test]
fn validate_refund_event_ignores_different_pinned_refund() {
    // Validate a refund id that does not own the current durable attempt
    let result = PaymentsWebhookReconciler::validate_refund_event(
        &sample_purchase(),
        &sample_refund(),
        PaymentProvider::Stripe,
        2_500,
        "usd",
        "pi_test_123",
        "re_unrelated_123",
    );

    // Check stale or unrelated provider attempts are ignored
    assert!(!result.expect("financially matching refund event to validate"));
}

#[test]
fn validate_refund_event_rejects_durable_amount_mismatch() {
    // Build a durable refund whose amount differs from its owning purchase
    let mut refund = sample_refund();
    refund.amount_minor = 100;

    // Validate the signed purchase amount against the inconsistent durable record
    let err = PaymentsWebhookReconciler::validate_refund_event(
        &sample_purchase(),
        &refund,
        PaymentProvider::Stripe,
        2_500,
        "usd",
        "pi_test_123",
        "re_test_123",
    )
    .expect_err("durable refund amount mismatch to fail");

    // Check the durable amount mismatch is explicit
    assert_eq!(
        err.to_string(),
        "refund webhook amount does not match purchase"
    );
}

#[test]
fn validate_refund_event_rejects_mismatched_amount() {
    // Validate a partial refund against the full durable amount
    let err = PaymentsWebhookReconciler::validate_refund_event(
        &sample_purchase(),
        &sample_refund(),
        PaymentProvider::Stripe,
        100,
        "usd",
        "pi_test_123",
        "re_test_123",
    )
    .expect_err("partial refund event to fail");

    // Check the financial mismatch is explicit
    assert_eq!(
        err.to_string(),
        "refund webhook amount does not match purchase"
    );
}

#[test]
fn validate_refund_event_rejects_mismatched_currency() {
    // Validate a refund denominated in a different currency
    let err = PaymentsWebhookReconciler::validate_refund_event(
        &sample_purchase(),
        &sample_refund(),
        PaymentProvider::Stripe,
        2_500,
        "eur",
        "pi_test_123",
        "re_test_123",
    )
    .expect_err("cross-currency refund event to fail");

    // Check the currency mismatch is explicit
    assert_eq!(
        err.to_string(),
        "refund webhook currency does not match purchase"
    );
}

#[test]
fn validate_refund_event_rejects_mismatched_payment_reference() {
    // Validate a refund belonging to a different payment intent
    let err = PaymentsWebhookReconciler::validate_refund_event(
        &sample_purchase(),
        &sample_refund(),
        PaymentProvider::Stripe,
        2_500,
        "usd",
        "pi_unrelated_123",
        "re_test_123",
    )
    .expect_err("unrelated payment refund event to fail");

    // Check the payment ownership mismatch is explicit
    assert_eq!(
        err.to_string(),
        "refund webhook payment reference does not match purchase"
    );
}

// Helpers.

/// Creates a purchase summary used by webhook validation tests.
fn sample_purchase() -> EventPurchaseSummary {
    EventPurchaseSummary {
        amount_minor: 2_500,
        currency_code: "USD".to_string(),
        event_purchase_id: Uuid::from_u128(1),
        event_ticket_type_id: Uuid::from_u128(3),
        status: EventPurchaseStatus::RefundPending,
        ticket_title: "General admission".to_string(),

        provider_payment_reference: Some("pi_test_123".to_string()),
        ..EventPurchaseSummary::default()
    }
}

/// Creates a durable refund used by webhook validation tests.
fn sample_refund() -> EventPurchaseRefund {
    EventPurchaseRefund {
        amount_minor: 2_500,
        currency_code: "USD".to_string(),
        event_purchase_id: Uuid::from_u128(1),
        event_purchase_refund_id: Uuid::from_u128(2),
        idempotency_key: "event-purchase-refund-test".to_string(),
        kind: EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
        payment_provider: PaymentProvider::Stripe,
        started_now: false,
        status: EventPurchaseRefundStatus::ProviderPending,

        failure_message: None,
        finalized_at: None,
        provider_refund_id: Some("re_test_123".to_string()),
        provider_refunded_at: None,
    }
}
