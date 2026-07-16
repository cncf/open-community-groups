use std::sync::Arc;

use uuid::Uuid;

use crate::{
    db::{
        DynDB,
        mock::MockDB,
        payments::{EventPurchaseRefund, EventPurchaseRefundKind, EventPurchaseRefundStatus},
    },
    services::payments::{RefundPaymentResult, RefundPaymentStatus},
    types::payments::PaymentProvider,
};

use super::{RecordedProviderRefund, persist_provider_refund_result};

#[tokio::test]
async fn persist_provider_refund_result_preserves_matching_terminal_failure() {
    // Setup an already-persisted terminal failure from the same provider refund
    let mut refund = sample_refund();
    refund.provider_refund_id = Some("re_terminal".to_string());
    refund.status = EventPurchaseRefundStatus::ProviderFailed;
    refund.terminal_failure = true;

    // Forbid rewriting the terminal outcome during an idempotent replay
    let mut db = MockDB::new();
    db.expect_record_event_purchase_refund_terminal_failed().never();
    let db: DynDB = Arc::new(db);

    // Persist the repeated terminal provider result
    let result = persist_provider_refund_result(
        &db,
        &refund,
        RefundPaymentResult {
            provider_refund_id: "re_terminal".to_string(),
            status: RefundPaymentStatus::Failed,
        },
    )
    .await
    .expect("matching terminal failure to be preserved");

    // Check the replay is acknowledged without another database transition
    assert!(matches!(result, RecordedProviderRefund::Failed));
}

#[tokio::test]
async fn persist_provider_refund_result_propagates_pending_persistence_error() {
    // Setup a pending provider result and its expected durable identifiers
    let refund = sample_refund();
    let claim_id = refund.claim_id;
    let idempotency_key = refund.idempotency_key.clone();
    let refund_id = refund.event_purchase_refund_id;

    // Fail the pending-state persistence operation
    let mut db = MockDB::new();
    db.expect_record_event_purchase_refund_pending()
        .withf(move |id, key, provider_refund_id, expected_claim_id| {
            *id == refund_id
                && key == &idempotency_key
                && provider_refund_id == "re_pending"
                && *expected_claim_id == claim_id
        })
        .times(1)
        .returning(|_, _, _, _| Err(anyhow::anyhow!("database unavailable")));
    db.expect_record_event_purchase_refund_succeeded().never();
    db.expect_record_event_purchase_refund_terminal_failed().never();
    let db: DynDB = Arc::new(db);

    // Persist the provider result
    let Err(err) = persist_provider_refund_result(
        &db,
        &refund,
        RefundPaymentResult {
            provider_refund_id: "re_pending".to_string(),
            status: RefundPaymentStatus::Pending,
        },
    )
    .await
    else {
        panic!("pending persistence failure to remain visible");
    };

    // Check both the operation context and database cause are preserved
    assert_eq!(err.to_string(), "failed to record pending provider refund");
    assert_eq!(err.root_cause().to_string(), "database unavailable");
}

#[tokio::test]
async fn persist_provider_refund_result_propagates_terminal_failure_persistence_error() {
    // Setup a terminal provider result and its expected durable identifiers
    let refund = sample_refund();
    let claim_id = refund.claim_id;
    let idempotency_key = refund.idempotency_key.clone();
    let refund_id = refund.event_purchase_refund_id;

    // Fail the terminal-state persistence operation
    let mut db = MockDB::new();
    db.expect_record_event_purchase_refund_pending().never();
    db.expect_record_event_purchase_refund_succeeded().never();
    db.expect_record_event_purchase_refund_terminal_failed()
        .withf(
            move |id, key, provider_refund_id, message, expected_claim_id| {
                *id == refund_id
                    && key == &idempotency_key
                    && provider_refund_id == "re_failed"
                    && message == "provider refund failed"
                    && *expected_claim_id == claim_id
            },
        )
        .times(1)
        .returning(|_, _, _, _, _| Err(anyhow::anyhow!("database unavailable")));
    let db: DynDB = Arc::new(db);

    // Persist the provider result
    let Err(err) = persist_provider_refund_result(
        &db,
        &refund,
        RefundPaymentResult {
            provider_refund_id: "re_failed".to_string(),
            status: RefundPaymentStatus::Failed,
        },
    )
    .await
    else {
        panic!("terminal failure persistence error to remain visible");
    };

    // Check both the operation context and database cause are preserved
    assert_eq!(
        err.to_string(),
        "failed to record terminal provider refund failure"
    );
    assert_eq!(err.root_cause().to_string(), "database unavailable");
}

// Helpers.

/// Creates a durable provider refund for persistence tests.
fn sample_refund() -> EventPurchaseRefund {
    EventPurchaseRefund {
        amount_minor: 2_500,
        currency_code: "USD".to_string(),
        event_purchase_id: Uuid::from_u128(1),
        event_purchase_refund_id: Uuid::from_u128(2),
        idempotency_key: "event-purchase-refund-test".to_string(),
        kind: EventPurchaseRefundKind::EventCancellation,
        payment_provider: PaymentProvider::Stripe,
        status: EventPurchaseRefundStatus::Processing,
        terminal_failure: false,

        attempt_count: 1,
        claim_id: Some(Uuid::from_u128(3)),
        failure_message: None,
        finalized_at: None,
        provider_payment_reference: Some("pi_test".to_string()),
        provider_refund_id: None,
        provider_refunded_at: None,
    }
}
