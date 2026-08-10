use std::{future::pending, sync::Arc, time::Duration};

use tokio::{sync::Notify, time::timeout};
use uuid::Uuid;

use crate::{
    db::{
        DynDB,
        mock::MockDB,
        payments::{ClaimedEventPurchaseApplicationFeeAdjustment, ClaimedEventPurchaseCreditNote},
    },
    services::payments::{
        DynPaymentsProvider,
        provider::{ApplicationFeeAdjustmentResult, CreditNoteResult, MockPaymentsProvider},
    },
    types::payments::PaymentProvider,
};

use super::FinancialWorker;

#[tokio::test]
async fn process_next_financial_work_configuration_without_provider_leaves_jobs_unclaimed() {
    // Forbid durable claim mutation while no provider is configured
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_application_fee_adjustment().never();
    db.expect_claim_event_purchase_credit_note().never();

    // Attempt to process queued work without a provider
    let worker = test_worker(Arc::new(db), None);
    let processed = worker
        .process_next_financial_work()
        .await
        .expect("unconfigured worker to stay idle");

    // Check durable work remains queued
    assert!(!processed);
}

#[tokio::test]
async fn process_next_financial_work_empty_queue_returns_idle() {
    // Return no work from either durable queue
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_application_fee_adjustment()
        .times(1)
        .return_once(|_| Ok(None));
    db.expect_claim_event_purchase_credit_note()
        .times(1)
        .return_once(|_| Ok(None));
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(2)
        .return_const(PaymentProvider::Stripe);

    // Process one empty worker iteration
    let processed = test_worker(Arc::new(db), Some(provider))
        .process_next_financial_work()
        .await
        .expect("empty queues to remain idle");

    // Check the worker reports that it consumed no job
    assert!(!processed);
}

#[tokio::test]
async fn process_next_financial_work_fee_adjustment_prioritizes_due_work() {
    // Claim one fee adjustment and forbid a lower-priority credit-note claim
    let adjustment = sample_application_fee_adjustment();
    let adjustment_id = adjustment.event_purchase_application_fee_adjustment_id;
    let claim_id = adjustment.claim_id;
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_application_fee_adjustment()
        .times(1)
        .return_once(move |_| Ok(Some(adjustment)));
    db.expect_claim_event_purchase_credit_note().never();
    db.expect_record_event_purchase_application_fee_adjustment_succeeded()
        .withf(move |id, claim, provider_id| {
            *id == adjustment_id && *claim == claim_id && provider_id == "fr_test_123"
        })
        .times(1)
        .return_once(|_, _, _| Ok(()));

    // Reconcile the claimed adjustment with its immutable provider context
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    provider
        .expect_reconcile_application_fee_adjustment()
        .withf(|input| {
            input.amount_minor == 125
                && input.connected_seller_id == "acct_worker"
                && input.idempotency_key == "fee-adjustment-worker"
                && input.provider_application_fee_id == "fee_worker"
        })
        .times(1)
        .return_once(|_| {
            Box::pin(async {
                Ok(ApplicationFeeAdjustmentResult {
                    provider_application_fee_refund_id: "fr_test_123".to_string(),
                })
            })
        });

    // Process the priority queue
    let processed = test_worker(Arc::new(db), Some(provider))
        .process_next_financial_work()
        .await
        .expect("fee adjustment to succeed");
    assert!(processed);
}

#[tokio::test]
async fn process_next_financial_work_fee_adjustment_provider_failure_records_retry() {
    // Claim a fee adjustment whose provider operation fails
    let adjustment = sample_application_fee_adjustment();
    let adjustment_id = adjustment.event_purchase_application_fee_adjustment_id;
    let claim_id = adjustment.claim_id;
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_application_fee_adjustment()
        .times(1)
        .return_once(move |_| Ok(Some(adjustment)));
    db.expect_record_event_purchase_application_fee_adjustment_failure()
        .withf(move |id, claim, message| {
            *id == adjustment_id && *claim == claim_id && message == "provider unavailable"
        })
        .times(1)
        .return_once(|_, _, _| Ok(()));
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    provider
        .expect_reconcile_application_fee_adjustment()
        .times(1)
        .return_once(|_| Box::pin(async { Err(anyhow::anyhow!("provider unavailable")) }));

    // Process the failing provider request
    let err = test_worker(Arc::new(db), Some(provider))
        .process_next_financial_work()
        .await
        .expect_err("provider failure to remain visible");
    assert_eq!(err.to_string(), "provider unavailable");
}

#[tokio::test]
async fn process_next_financial_work_fee_adjustment_release_failure_preserves_provider_error() {
    // Claim a fee adjustment whose provider and retry-release operations fail
    let adjustment = sample_application_fee_adjustment();
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_application_fee_adjustment()
        .times(1)
        .return_once(move |_| Ok(Some(adjustment)));
    db.expect_record_event_purchase_application_fee_adjustment_failure()
        .times(1)
        .return_once(|_, _, _| Err(anyhow::anyhow!("claim release unavailable")));
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    provider
        .expect_reconcile_application_fee_adjustment()
        .times(1)
        .return_once(|_| Box::pin(async { Err(anyhow::anyhow!("provider unavailable")) }));

    // Process the provider failure while durable release also fails
    let err = test_worker(Arc::new(db), Some(provider))
        .process_next_financial_work()
        .await
        .expect_err("original provider failure to remain visible");

    // Check the boundary preserves the actionable external failure
    assert_eq!(err.to_string(), "provider unavailable");
}

#[tokio::test]
async fn process_next_financial_work_fee_adjustment_success_persistence_failure_propagates() {
    // Claim a fee adjustment whose provider operation succeeds
    let adjustment = sample_application_fee_adjustment();
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_application_fee_adjustment()
        .times(1)
        .return_once(move |_| Ok(Some(adjustment)));
    db.expect_record_event_purchase_application_fee_adjustment_succeeded()
        .times(1)
        .return_once(|_, _, _| Err(anyhow::anyhow!("database unavailable")));
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    provider
        .expect_reconcile_application_fee_adjustment()
        .times(1)
        .return_once(|_| {
            Box::pin(async {
                Ok(ApplicationFeeAdjustmentResult {
                    provider_application_fee_refund_id: "fr_test_123".to_string(),
                })
            })
        });

    // Persist the provider result and surface the durable-state failure
    let err = test_worker(Arc::new(db), Some(provider))
        .process_next_financial_work()
        .await
        .expect_err("success persistence failure to propagate");
    assert_eq!(err.to_string(), "database unavailable");
}

#[tokio::test]
async fn process_next_financial_work_secondary_credit_note_processes_after_empty_priority_queue() {
    // Claim one credit note after the fee-adjustment queue is empty
    let credit_note = sample_credit_note();
    let credit_note_id = credit_note.event_purchase_credit_note_id;
    let claim_id = credit_note.claim_id;
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_application_fee_adjustment()
        .times(1)
        .return_once(|_| Ok(None));
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

    // Reconcile the credit note and return its provider document
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(2)
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

    // Process the lower-priority queue
    let processed = test_worker(Arc::new(db), Some(provider))
        .process_next_financial_work()
        .await
        .expect("credit note to succeed");
    assert!(processed);
}

#[tokio::test]
async fn process_next_financial_work_secondary_credit_note_records_provider_failure() {
    // Claim a credit note whose provider operation fails
    let credit_note = sample_credit_note();
    let credit_note_id = credit_note.event_purchase_credit_note_id;
    let claim_id = credit_note.claim_id;
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_application_fee_adjustment()
        .times(1)
        .return_once(|_| Ok(None));
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
        .times(2)
        .return_const(PaymentProvider::Stripe);
    provider
        .expect_reconcile_credit_note()
        .times(1)
        .return_once(|_| Box::pin(async { Err(anyhow::anyhow!("credit note unavailable")) }));

    // Process the failing provider request
    let err = test_worker(Arc::new(db), Some(provider))
        .process_next_financial_work()
        .await
        .expect_err("credit-note failure to remain visible");
    assert_eq!(err.to_string(), "credit note unavailable");
}

#[tokio::test]
async fn run_financial_worker_does_not_claim_after_cancellation() {
    // Forbid queue access after graceful cancellation begins
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_application_fee_adjustment().never();
    db.expect_claim_event_purchase_credit_note().never();
    let cancellation_token = tokio_util::sync::CancellationToken::new();
    cancellation_token.cancel();
    let worker = FinancialWorker {
        cancellation_token,
        db: Arc::new(db),
        payments_provider: Some(Arc::new(MockPaymentsProvider::new())),
    };

    // Run the already-canceled worker
    worker.run().await;
}

#[tokio::test]
async fn run_financial_worker_stops_during_provider_request_after_cancellation() {
    // Claim work whose provider request remains in flight
    let adjustment = sample_application_fee_adjustment();
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_application_fee_adjustment()
        .times(1)
        .return_once(move |_| Ok(Some(adjustment)));
    db.expect_claim_event_purchase_credit_note().never();
    db.expect_record_event_purchase_application_fee_adjustment_failure()
        .never();

    // Hold provider reconciliation until cancellation drops the future
    let provider_started = Arc::new(Notify::new());
    let provider_started_for_request = provider_started.clone();
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    provider
        .expect_reconcile_application_fee_adjustment()
        .times(1)
        .return_once(move |_| {
            Box::pin(async move {
                provider_started_for_request.notify_one();
                pending::<anyhow::Result<ApplicationFeeAdjustmentResult>>().await
            })
        });

    // Start the worker and wait for the provider boundary
    let cancellation_token = tokio_util::sync::CancellationToken::new();
    let worker = FinancialWorker {
        cancellation_token: cancellation_token.clone(),
        db: Arc::new(db),
        payments_provider: Some(Arc::new(provider)),
    };
    let worker_task = tokio::spawn(async move {
        worker.run().await;
    });
    timeout(Duration::from_secs(1), provider_started.notified())
        .await
        .expect("financial provider request to start");

    // Cancel and require shutdown without waiting for the provider future
    cancellation_token.cancel();
    timeout(Duration::from_secs(1), worker_task)
        .await
        .expect("financial worker to stop promptly")
        .expect("financial worker task to complete");
}

// Helpers.

/// Creates a claimed application-fee adjustment for worker tests.
fn sample_application_fee_adjustment() -> ClaimedEventPurchaseApplicationFeeAdjustment {
    ClaimedEventPurchaseApplicationFeeAdjustment {
        amount_minor: 125,
        claim_id: Uuid::new_v4(),
        connected_seller_id: "acct_worker".to_string(),
        event_purchase_application_fee_adjustment_id: Uuid::new_v4(),
        event_purchase_id: Uuid::new_v4(),
        idempotency_key: "fee-adjustment-worker".to_string(),
        kind: "tax-reconciliation".to_string(),
        provider_application_fee_id: "fee_worker".to_string(),
    }
}

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

/// Creates a financial worker with test doubles and a fresh cancellation token.
fn test_worker(db: DynDB, provider: Option<MockPaymentsProvider>) -> FinancialWorker {
    let payments_provider = provider.map(|provider| Arc::new(provider) as DynPaymentsProvider);

    FinancialWorker {
        cancellation_token: tokio_util::sync::CancellationToken::new(),
        db,
        payments_provider,
    }
}
