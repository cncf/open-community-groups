use std::sync::Arc;

use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::{
    db::{DynDB, mock::MockDB, payments::ClaimedEventPurchaseApplicationFeeAdjustment},
    services::payments::{
        DynPaymentsProvider,
        provider::{ApplicationFeeAdjustmentResult, MockPaymentsProvider},
    },
    types::payments::PaymentProvider,
};

use super::Worker;

#[tokio::test]
async fn test_process_next_application_fee_adjustment_configuration_without_provider_leaves_jobs_unclaimed()
 {
    // Forbid durable claim mutation while no provider is configured
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_application_fee_adjustment().never();

    // Attempt to process queued work without a provider
    let processed = test_worker(Arc::new(db), None)
        .process_next_application_fee_adjustment()
        .await
        .expect("unconfigured worker to stay idle");

    // Check durable work remains queued
    assert!(!processed);
}

#[tokio::test]
async fn test_process_next_application_fee_adjustment_empty_queue_returns_idle() {
    // Return no work from the durable adjustment queue
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_application_fee_adjustment()
        .times(1)
        .return_once(|_| Ok(None));
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);

    // Process one empty worker iteration
    let processed = test_worker(Arc::new(db), Some(provider))
        .process_next_application_fee_adjustment()
        .await
        .expect("empty adjustment queue to remain idle");

    // Check the worker reports that it consumed no job
    assert!(!processed);
}

#[tokio::test]
async fn test_process_next_application_fee_adjustment_provider_failure_records_retry() {
    // Claim an adjustment whose provider operation fails
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
        .process_next_application_fee_adjustment()
        .await
        .expect_err("provider failure to remain visible");

    // Check the provider failure remains the worker error
    assert_eq!(err.to_string(), "provider unavailable");
}

#[tokio::test]
async fn test_process_next_application_fee_adjustment_reconciles_due_work() {
    // Claim one due adjustment and persist its provider result
    let adjustment = sample_application_fee_adjustment();
    let adjustment_id = adjustment.event_purchase_application_fee_adjustment_id;
    let claim_id = adjustment.claim_id;
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_application_fee_adjustment()
        .times(1)
        .return_once(move |_| Ok(Some(adjustment)));
    db.expect_record_event_purchase_application_fee_adjustment_succeeded()
        .withf(move |id, claim, provider_id| {
            *id == adjustment_id && *claim == claim_id && provider_id == "fr_test_123"
        })
        .times(1)
        .return_once(|_, _, _| Ok(()));

    // Reconcile the adjustment with its immutable provider context
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
                && input.currency_code == "USD"
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

    // Process the claimed adjustment
    let processed = test_worker(Arc::new(db), Some(provider))
        .process_next_application_fee_adjustment()
        .await
        .expect("fee adjustment to succeed");

    // Check the worker reports that it consumed the job
    assert!(processed);
}

#[tokio::test]
async fn test_process_next_application_fee_adjustment_release_failure_preserves_provider_error() {
    // Claim an adjustment whose provider and retry-release operations fail
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
        .process_next_application_fee_adjustment()
        .await
        .expect_err("original provider failure to remain visible");

    // Check the boundary preserves the actionable external failure
    assert_eq!(err.to_string(), "provider unavailable");
}

#[tokio::test]
async fn test_process_next_application_fee_adjustment_success_persistence_failure_propagates() {
    // Claim an adjustment whose provider operation succeeds
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
        .process_next_application_fee_adjustment()
        .await
        .expect_err("success persistence failure to propagate");

    // Check the persistence failure remains the worker error
    assert_eq!(err.to_string(), "database unavailable");
}

// Helpers.

/// Creates a claimed application-fee adjustment for worker tests.
fn sample_application_fee_adjustment() -> ClaimedEventPurchaseApplicationFeeAdjustment {
    ClaimedEventPurchaseApplicationFeeAdjustment {
        amount_minor: 125,
        claim_id: Uuid::new_v4(),
        connected_seller_id: "acct_worker".to_string(),
        currency_code: "USD".to_string(),
        event_purchase_application_fee_adjustment_id: Uuid::new_v4(),
        event_purchase_id: Uuid::new_v4(),
        idempotency_key: "fee-adjustment-worker".to_string(),
        kind: "tax-reconciliation".to_string(),
        provider_application_fee_id: "fee_worker".to_string(),
    }
}

/// Creates an application-fee adjustment worker with test doubles.
fn test_worker(db: DynDB, provider: Option<MockPaymentsProvider>) -> Worker {
    let payments_provider = provider.map(|provider| Arc::new(provider) as DynPaymentsProvider);

    Worker {
        cancellation_token: CancellationToken::new(),
        db,

        payments_provider,
    }
}
