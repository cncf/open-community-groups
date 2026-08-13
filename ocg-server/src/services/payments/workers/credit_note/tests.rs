use std::sync::Arc;

use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::{
    db::{DynDB, mock::MockDB, payments::ClaimedEventPurchaseCreditNote},
    services::payments::{
        DynPaymentsProvider,
        provider::{CreditNoteResult, MockPaymentsProvider},
    },
    types::payments::PaymentProvider,
};

use super::Worker;

#[tokio::test]
async fn test_process_next_credit_note_configuration_without_provider_leaves_jobs_unclaimed() {
    // Forbid durable claim mutation while no provider is configured
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_credit_note().never();

    // Attempt to process queued work without a provider
    let processed = test_worker(Arc::new(db), None)
        .process_next_credit_note()
        .await
        .expect("unconfigured worker to stay idle");

    // Check durable work remains queued
    assert!(!processed);
}

#[tokio::test]
async fn test_process_next_credit_note_empty_queue_returns_idle() {
    // Return no work from the durable credit-note queue
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_credit_note()
        .times(1)
        .return_once(|_| Ok(None));
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);

    // Process one empty worker iteration
    let processed = test_worker(Arc::new(db), Some(provider))
        .process_next_credit_note()
        .await
        .expect("empty credit-note queue to remain idle");

    // Check the worker reports that it consumed no job
    assert!(!processed);
}

#[tokio::test]
async fn test_process_next_credit_note_provider_failure_records_retry() {
    // Claim a credit note whose provider operation fails
    let credit_note = sample_credit_note();
    let credit_note_id = credit_note.event_purchase_credit_note_id;
    let claim_id = credit_note.claim_id;
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_credit_note()
        .times(1)
        .return_once(move |_| Ok(Some(credit_note)));
    db.expect_record_event_purchase_credit_note_failure()
        .withf(move |id, claim, message| {
            *id == credit_note_id && *claim == claim_id && message == "credit note unavailable"
        })
        .times(1)
        .return_once(|_, _, _| Ok(()));
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    provider
        .expect_reconcile_credit_note()
        .times(1)
        .return_once(|_| Box::pin(async { Err(anyhow::anyhow!("credit note unavailable")) }));

    // Process the failing provider request
    let err = test_worker(Arc::new(db), Some(provider))
        .process_next_credit_note()
        .await
        .expect_err("credit-note failure to remain visible");

    // Check the provider failure remains the worker error
    assert_eq!(err.to_string(), "credit note unavailable");
}

#[tokio::test]
async fn test_process_next_credit_note_reconciles_due_work() {
    // Claim one due credit note and persist its provider document
    let credit_note = sample_credit_note();
    let credit_note_id = credit_note.event_purchase_credit_note_id;
    let claim_id = credit_note.claim_id;
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_credit_note()
        .times(1)
        .return_once(move |_| Ok(Some(credit_note)));
    db.expect_record_event_purchase_credit_note_succeeded()
        .withf(move |id, claim, provider_id, hosted_url, pdf_url| {
            *id == credit_note_id
                && *claim == claim_id
                && provider_id == "cn_test_123"
                && hosted_url.as_deref() == Some("https://stripe.test/credit-note")
                && pdf_url.is_none()
        })
        .times(1)
        .return_once(|_, _, _, _, _| Ok(()));

    // Reconcile the credit note with its immutable provider context
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    provider
        .expect_reconcile_credit_note()
        .withf(|input| {
            input.amount_minor == 2_500
                && input.provider_invoice_id == "in_worker"
                && input.provider_refund_id == "re_worker"
                && input.tax_amount_minor == 200
        })
        .times(1)
        .return_once(|_| {
            Box::pin(async {
                Ok(CreditNoteResult {
                    provider_credit_note_id: "cn_test_123".to_string(),
                    provider_hosted_url: Some("https://stripe.test/credit-note".to_string()),
                    provider_pdf_url: None,
                })
            })
        });

    // Process the claimed credit note
    let processed = test_worker(Arc::new(db), Some(provider))
        .process_next_credit_note()
        .await
        .expect("credit note to succeed");

    // Check the worker reports that it consumed the job
    assert!(processed);
}

// Helpers.

/// Creates a claimed credit note for worker tests.
fn sample_credit_note() -> ClaimedEventPurchaseCreditNote {
    ClaimedEventPurchaseCreditNote {
        amount_minor: 2_500,
        claim_id: Uuid::new_v4(),
        connected_seller_id: "acct_worker".to_string(),
        event_purchase_credit_note_id: Uuid::new_v4(),
        event_purchase_id: Uuid::new_v4(),
        event_purchase_refund_id: Uuid::new_v4(),
        idempotency_key: "credit-note-worker".to_string(),
        provider_invoice_id: "in_worker".to_string(),
        provider_refund_id: "re_worker".to_string(),
        tax_amount_minor: 200,
    }
}

/// Creates a credit-note worker with test doubles.
fn test_worker(db: DynDB, provider: Option<MockPaymentsProvider>) -> Worker {
    let payments_provider = provider.map(|provider| Arc::new(provider) as DynPaymentsProvider);

    Worker {
        cancellation_token: CancellationToken::new(),
        db,

        payments_provider,
    }
}
