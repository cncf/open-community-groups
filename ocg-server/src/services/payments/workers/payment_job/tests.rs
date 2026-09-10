use std::sync::{Arc, atomic::AtomicUsize};

use chrono::Utc;
use mockall::predicate::eq;
use serde_json::{Value, to_value};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::{
        DynDB,
        mock::MockDB,
        payments::{
            ClaimedEventPurchaseApplicationFeeAdjustment, ClaimedEventPurchaseCreditNote,
            ClaimedEventPurchaseRefund, ClaimedPaymentJob, ClaimedPaymentJobWork,
            EventPurchaseRefund, EventPurchaseRefundKind, EventPurchaseRefundStatus,
        },
    },
    services::{
        notifications::MockNotificationsManager,
        payments::{
            DynPaymentsProvider, RefundPaymentResult, RefundPaymentStatus,
            notification_composer::PaymentsNotificationComposer,
            provider::{ApplicationFeeAdjustmentResult, CreditNoteResult, MockPaymentsProvider},
        },
    },
    templates::notifications::EventRefundApproved,
    types::{
        event::{EventKind, EventSummary},
        payments::{PaymentJobKind, PaymentProvider},
        site::SiteSettings,
    },
};

use super::Worker;

#[tokio::test]
async fn test_process_next_payment_job_configuration_without_provider_leaves_jobs_unclaimed() {
    // Forbid durable claim mutation while no provider is configured
    let mut db = MockDB::new();
    db.expect_claim_payment_job().never();

    // Attempt to process queued work without a provider
    let processed = worker(Arc::new(db), MockNotificationsManager::new(), None)
        .process_next_payment_job()
        .await
        .expect("unconfigured worker to stay idle");

    // Check durable work remains queued
    assert!(!processed);
}

#[tokio::test]
async fn test_process_next_payment_job_creates_missing_provider_refund_and_finalizes_success() {
    // Setup a claimed refund without a known provider refund
    let claim_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let payment_job_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let mut claimed_refund = sample_refund(claim_id, payment_job_id, purchase_id, refund_id);
    claimed_refund.community_id = community_id;
    claimed_refund.event_id = event_id;
    let mut succeeded_refund = claimed_refund.refund.clone();
    succeeded_refund.provider_refund_id = Some("re_worker".to_string());
    succeeded_refund.provider_refunded_at = Some(Utc::now());
    let job = sample_job(
        claim_id,
        payment_job_id,
        purchase_id,
        ClaimedPaymentJobWork::EventPurchaseRefund {
            refund: claimed_refund.clone(),
        },
    );

    // Setup durable claim, provider-success recording, and finalization
    let mut db = MockDB::new();
    expect_empty_application_fee_adjustment_claim(&mut db);
    expect_empty_credit_note_claim(&mut db);
    let expected_template_data = expect_refund_approval_context(&mut db, &claimed_refund);
    db.expect_claim_payment_job()
        .with(
            eq(PaymentJobKind::EventPurchaseRefund),
            eq(PaymentProvider::Stripe),
        )
        .times(1)
        .return_once(move |_, _| Ok(Some(job)));
    db.expect_record_event_purchase_refund_succeeded()
        .withf(move |id, key, provider_refund_id, expected_claim_id| {
            *id == refund_id
                && key == &format!("event-purchase-refund-{purchase_id}")
                && provider_refund_id == "re_worker"
                && *expected_claim_id == Some(claim_id)
        })
        .times(1)
        .return_once(move |_, _, _, _| Ok(succeeded_refund));
    db.expect_finalize_event_purchase_refund()
        .with(
            eq(refund_id),
            eq(claim_id),
            eq(expected_template_data),
            eq(Some(PaymentProvider::Stripe)),
        )
        .times(1)
        .return_once(|_, _, _, _| Ok(()));

    // Setup lookup-before-create and stable idempotency expectations
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    provider
        .expect_find_refund()
        .withf(move |input| {
            input.amount_minor == 2_500
                && input.provider_payment_reference == "pi_worker"
                && input.provider_refund_id.is_none()
                && input.purchase_id == purchase_id
        })
        .times(1)
        .return_once(|_| Box::pin(async { Ok(None) }));
    provider
        .expect_refund_payment()
        .withf(move |input| {
            input.amount_minor == 2_500
                && input.connected_seller_id == "acct_worker"
                && input.idempotency_key == format!("event-purchase-refund-{purchase_id}")
                && input.provider_payment_reference == "pi_worker"
                && input.purchase_id == purchase_id
        })
        .times(1)
        .return_once(|_| {
            Box::pin(async {
                Ok(RefundPaymentResult {
                    provider_refund_id: "re_worker".to_string(),
                    status: RefundPaymentStatus::Succeeded,
                })
            })
        });

    // Process the claimed refund
    let processed = worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    )
    .process_next_payment_job()
    .await
    .expect("provider refund to succeed");

    // Check the worker consumed one job
    assert!(processed);
}

#[tokio::test]
async fn test_process_next_payment_job_empty_queue_returns_idle() {
    // Return no work from any durable payment job kind
    let mut db = MockDB::new();
    expect_empty_application_fee_adjustment_claim(&mut db);
    expect_empty_credit_note_claim(&mut db);
    expect_empty_refund_claim(&mut db);
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);

    // Process one empty worker iteration
    let processed = worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    )
    .process_next_payment_job()
    .await
    .expect("empty payment job queue to remain idle");

    // Check the worker reports that it consumed no job
    assert!(!processed);
}

#[tokio::test]
async fn test_process_next_payment_job_finalizes_persisted_success_without_provider_call() {
    // Setup a claim whose provider success was already persisted
    let claim_id = Uuid::new_v4();
    let payment_job_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let mut claimed_refund = sample_refund(claim_id, payment_job_id, purchase_id, refund_id);
    claimed_refund.provider_refund_id = Some("re_persisted".to_string());
    claimed_refund.provider_refunded_at = Some(Utc::now());
    let job = sample_job(
        claim_id,
        payment_job_id,
        purchase_id,
        ClaimedPaymentJobWork::EventPurchaseRefund {
            refund: claimed_refund.clone(),
        },
    );

    // Setup local finalization and completion-notification context
    let mut db = MockDB::new();
    expect_empty_application_fee_adjustment_claim(&mut db);
    expect_empty_credit_note_claim(&mut db);
    let expected_template_data = expect_refund_approval_context(&mut db, &claimed_refund);
    db.expect_claim_payment_job()
        .with(
            eq(PaymentJobKind::EventPurchaseRefund),
            eq(PaymentProvider::Stripe),
        )
        .times(1)
        .return_once(move |_, _| Ok(Some(job)));
    db.expect_finalize_event_purchase_refund()
        .with(
            eq(refund_id),
            eq(claim_id),
            eq(expected_template_data),
            eq(Some(PaymentProvider::Stripe)),
        )
        .times(1)
        .return_once(|_, _, _, _| Ok(()));

    // Forbid the legacy post-commit notification enqueue
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager.expect_enqueue().never();

    // Forbid provider calls after durable success
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    provider.expect_find_refund().never();
    provider.expect_refund_payment().never();

    // Resume local finalization
    let processed = worker(Arc::new(db), notifications_manager, Some(provider))
        .process_next_payment_job()
        .await
        .expect("persisted provider success to finalize");

    // Check finalization consumed one job without another provider operation
    assert!(processed);
}

#[tokio::test]
async fn test_process_next_payment_job_finds_existing_success_without_creating_refund() {
    // Setup a claimed refund whose provider operation already exists
    let claim_id = Uuid::new_v4();
    let payment_job_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let claimed_refund = sample_refund(claim_id, payment_job_id, purchase_id, refund_id);
    let mut succeeded_refund = claimed_refund.refund.clone();
    succeeded_refund.provider_refund_id = Some("re_existing".to_string());
    succeeded_refund.provider_refunded_at = Some(Utc::now());
    let job = sample_job(
        claim_id,
        payment_job_id,
        purchase_id,
        ClaimedPaymentJobWork::EventPurchaseRefund {
            refund: claimed_refund.clone(),
        },
    );

    // Setup durable success recording and finalization
    let mut db = MockDB::new();
    expect_empty_application_fee_adjustment_claim(&mut db);
    expect_empty_credit_note_claim(&mut db);
    let expected_template_data = expect_refund_approval_context(&mut db, &claimed_refund);
    db.expect_claim_payment_job()
        .with(
            eq(PaymentJobKind::EventPurchaseRefund),
            eq(PaymentProvider::Stripe),
        )
        .times(1)
        .return_once(move |_, _| Ok(Some(job)));
    db.expect_record_event_purchase_refund_succeeded()
        .withf(move |id, _, provider_refund_id, expected_claim_id| {
            *id == refund_id
                && provider_refund_id == "re_existing"
                && *expected_claim_id == Some(claim_id)
        })
        .times(1)
        .return_once(move |_, _, _, _| Ok(succeeded_refund));
    db.expect_finalize_event_purchase_refund()
        .with(
            eq(refund_id),
            eq(claim_id),
            eq(expected_template_data),
            eq(Some(PaymentProvider::Stripe)),
        )
        .times(1)
        .returning(|_, _, _, _| Ok(()));

    // Return the existing provider success and forbid another creation
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    provider.expect_find_refund().times(1).return_once(|_| {
        Box::pin(async {
            Ok(Some(RefundPaymentResult {
                provider_refund_id: "re_existing".to_string(),
                status: RefundPaymentStatus::Succeeded,
            }))
        })
    });
    provider.expect_refund_payment().never();

    // Reconcile the existing provider refund
    let processed = worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    )
    .process_next_payment_job()
    .await
    .expect("existing provider refund to finalize");

    // Check the worker consumed one job
    assert!(processed);
}

#[tokio::test]
async fn test_process_next_payment_job_processes_application_fee_adjustment() {
    // Claim one due adjustment and persist its provider result
    let claim_id = Uuid::new_v4();
    let payment_job_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let adjustment = sample_application_fee_adjustment();
    let adjustment_id = adjustment.event_purchase_application_fee_adjustment_id;
    let job = sample_job(
        claim_id,
        payment_job_id,
        purchase_id,
        ClaimedPaymentJobWork::EventPurchaseApplicationFeeAdjustment {
            application_fee_adjustment: adjustment,
        },
    );
    let mut db = MockDB::new();
    db.expect_claim_payment_job()
        .with(
            eq(PaymentJobKind::EventPurchaseApplicationFeeAdjustment),
            eq(PaymentProvider::Stripe),
        )
        .times(1)
        .return_once(move |_, _| Ok(Some(job)));
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
        .withf(move |input| {
            input.amount_minor == 125
                && input.connected_seller_id == "acct_worker"
                && input.currency_code == "USD"
                && input.event_purchase_id == purchase_id
                && input.idempotency_key == format!("event-purchase-refund-{purchase_id}")
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
    let processed = worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    )
    .process_next_payment_job()
    .await
    .expect("fee adjustment to succeed");

    // Check the worker reports that it consumed the job
    assert!(processed);
}

#[tokio::test]
async fn test_process_next_payment_job_rotates_the_first_claimed_kind_between_iterations() {
    // Keep adjustments continuously claimable so a fixed order would starve other kinds
    let adjustment = sample_application_fee_adjustment();
    let adjustment_job = sample_job(
        Uuid::new_v4(),
        Uuid::new_v4(),
        Uuid::new_v4(),
        ClaimedPaymentJobWork::EventPurchaseApplicationFeeAdjustment {
            application_fee_adjustment: adjustment,
        },
    );
    let credit_note = sample_credit_note();
    let credit_note_job = sample_job(
        Uuid::new_v4(),
        Uuid::new_v4(),
        Uuid::new_v4(),
        ClaimedPaymentJobWork::EventPurchaseCreditNote { credit_note },
    );
    let mut db = MockDB::new();
    db.expect_claim_payment_job()
        .with(
            eq(PaymentJobKind::EventPurchaseApplicationFeeAdjustment),
            eq(PaymentProvider::Stripe),
        )
        .times(1)
        .return_once(move |_, _| Ok(Some(adjustment_job)));
    db.expect_claim_payment_job()
        .with(
            eq(PaymentJobKind::EventPurchaseCreditNote),
            eq(PaymentProvider::Stripe),
        )
        .times(1)
        .return_once(move |_, _| Ok(Some(credit_note_job)));
    db.expect_claim_payment_job()
        .with(
            eq(PaymentJobKind::EventPurchaseRefund),
            eq(PaymentProvider::Stripe),
        )
        .never();
    db.expect_record_event_purchase_application_fee_adjustment_succeeded()
        .times(1)
        .return_once(|_, _, _| Ok(()));
    db.expect_record_event_purchase_credit_note_succeeded()
        .times(1)
        .return_once(|_, _, _, _, _| Ok(()));

    // Let the provider succeed for both kinds
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(2)
        .return_const(PaymentProvider::Stripe);
    provider
        .expect_reconcile_application_fee_adjustment()
        .times(1)
        .return_once(|_| {
            Box::pin(async {
                Ok(ApplicationFeeAdjustmentResult {
                    provider_application_fee_refund_id: "fr_rotation".to_string(),
                })
            })
        });
    provider.expect_reconcile_credit_note().times(1).return_once(|_| {
        Box::pin(async {
            Ok(CreditNoteResult {
                provider_credit_note_id: "cn_rotation".to_string(),
                provider_hosted_url: None,
                provider_pdf_url: None,
            })
        })
    });

    // Process two iterations on the same worker
    let worker = worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    );
    let first = worker
        .process_next_payment_job()
        .await
        .expect("first iteration to claim the adjustment");
    let second = worker
        .process_next_payment_job()
        .await
        .expect("second iteration to claim the credit note first");

    // Check both iterations consumed a job without re-claiming the first kind
    assert!(first);
    assert!(second);
}

#[tokio::test]
async fn test_process_next_payment_job_processes_credit_note_after_empty_adjustment_queue() {
    // Claim one due credit note and persist its provider document
    let claim_id = Uuid::new_v4();
    let payment_job_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let credit_note = sample_credit_note();
    let credit_note_id = credit_note.event_purchase_credit_note_id;
    let job = sample_job(
        claim_id,
        payment_job_id,
        purchase_id,
        ClaimedPaymentJobWork::EventPurchaseCreditNote { credit_note },
    );
    let mut db = MockDB::new();
    expect_empty_application_fee_adjustment_claim(&mut db);
    db.expect_claim_payment_job()
        .with(
            eq(PaymentJobKind::EventPurchaseCreditNote),
            eq(PaymentProvider::Stripe),
        )
        .times(1)
        .return_once(move |_, _| Ok(Some(job)));
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
        .withf(move |input| {
            input.amount_minor == 2_500
                && input.event_purchase_id == purchase_id
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
    let processed = worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    )
    .process_next_payment_job()
    .await
    .expect("credit note to succeed");

    // Check the worker reports that it consumed the job
    assert!(processed);
}

#[tokio::test]
async fn test_process_next_payment_job_records_failure_after_application_fee_error() {
    // Claim an adjustment whose provider operation fails
    let claim_id = Uuid::new_v4();
    let payment_job_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let job = sample_job(
        claim_id,
        payment_job_id,
        purchase_id,
        ClaimedPaymentJobWork::EventPurchaseApplicationFeeAdjustment {
            application_fee_adjustment: sample_application_fee_adjustment(),
        },
    );
    let mut db = MockDB::new();
    db.expect_claim_payment_job()
        .with(
            eq(PaymentJobKind::EventPurchaseApplicationFeeAdjustment),
            eq(PaymentProvider::Stripe),
        )
        .times(1)
        .return_once(move |_, _| Ok(Some(job)));
    db.expect_record_payment_job_failure()
        .withf(move |id, claim, message| {
            *id == payment_job_id && *claim == claim_id && message == "provider unavailable"
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
    let err = worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    )
    .process_next_payment_job()
    .await
    .expect_err("provider failure to remain visible");

    // Check the provider failure remains the worker error
    assert_eq!(err.to_string(), "provider unavailable");
}

#[tokio::test]
async fn test_process_next_payment_job_records_failure_after_credit_note_error() {
    // Claim a credit note whose provider operation fails
    let claim_id = Uuid::new_v4();
    let payment_job_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let job = sample_job(
        claim_id,
        payment_job_id,
        purchase_id,
        ClaimedPaymentJobWork::EventPurchaseCreditNote {
            credit_note: sample_credit_note(),
        },
    );
    let mut db = MockDB::new();
    expect_empty_application_fee_adjustment_claim(&mut db);
    db.expect_claim_payment_job()
        .with(
            eq(PaymentJobKind::EventPurchaseCreditNote),
            eq(PaymentProvider::Stripe),
        )
        .times(1)
        .return_once(move |_, _| Ok(Some(job)));
    db.expect_record_payment_job_failure()
        .withf(move |id, claim, message| {
            *id == payment_job_id && *claim == claim_id && message == "credit note unavailable"
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
    let err = worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    )
    .process_next_payment_job()
    .await
    .expect_err("credit-note failure to remain visible");

    // Check the provider failure remains the worker error
    assert_eq!(err.to_string(), "credit note unavailable");
}

#[tokio::test]
async fn test_process_next_payment_job_records_failure_after_creation_error() {
    // Setup a newly claimed refund without a known provider refund
    let claim_id = Uuid::new_v4();
    let payment_job_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let claimed_refund = sample_refund(claim_id, payment_job_id, purchase_id, refund_id);
    let job = sample_job(
        claim_id,
        payment_job_id,
        purchase_id,
        ClaimedPaymentJobWork::EventPurchaseRefund {
            refund: claimed_refund,
        },
    );

    // Setup claim release after provider refund creation fails
    let mut db = MockDB::new();
    expect_empty_application_fee_adjustment_claim(&mut db);
    expect_empty_credit_note_claim(&mut db);
    db.expect_claim_payment_job()
        .with(
            eq(PaymentJobKind::EventPurchaseRefund),
            eq(PaymentProvider::Stripe),
        )
        .times(1)
        .return_once(move |_, _| Ok(Some(job)));
    db.expect_record_payment_job_failure()
        .withf(move |id, claim, message| {
            *id == payment_job_id && *claim == claim_id && message == "creation unavailable"
        })
        .times(1)
        .returning(|_, _, _| Ok(()));

    // Return a lookup miss followed by a retryable creation error
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    provider
        .expect_find_refund()
        .times(1)
        .return_once(|_| Box::pin(async { Ok(None) }));
    provider
        .expect_refund_payment()
        .times(1)
        .return_once(|_| Box::pin(async { Err(anyhow::anyhow!("creation unavailable")) }));

    // Process the failed provider attempt
    let err = worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    )
    .process_next_payment_job()
    .await
    .expect_err("creation failure to remain visible");

    // Check the original provider error is returned after claim release
    assert_eq!(err.to_string(), "creation unavailable");
}

#[tokio::test]
async fn test_process_next_payment_job_records_failure_after_finalization_error() {
    // Setup a claimed refund whose provider operation has succeeded
    let claim_id = Uuid::new_v4();
    let payment_job_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let claimed_refund = sample_refund(claim_id, payment_job_id, purchase_id, refund_id);
    let mut succeeded_refund = claimed_refund.refund.clone();
    succeeded_refund.provider_refund_id = Some("re_finalize".to_string());
    succeeded_refund.provider_refunded_at = Some(Utc::now());
    let job = sample_job(
        claim_id,
        payment_job_id,
        purchase_id,
        ClaimedPaymentJobWork::EventPurchaseRefund {
            refund: claimed_refund.clone(),
        },
    );

    // Fail local finalization and release the current claim for retry
    let mut db = MockDB::new();
    expect_empty_application_fee_adjustment_claim(&mut db);
    expect_empty_credit_note_claim(&mut db);
    let expected_template_data = expect_refund_approval_context(&mut db, &claimed_refund);
    db.expect_claim_payment_job()
        .with(
            eq(PaymentJobKind::EventPurchaseRefund),
            eq(PaymentProvider::Stripe),
        )
        .times(1)
        .return_once(move |_, _| Ok(Some(job)));
    db.expect_record_event_purchase_refund_succeeded()
        .withf(move |_, _, _, expected_claim_id| *expected_claim_id == Some(claim_id))
        .times(1)
        .return_once(move |_, _, _, _| Ok(succeeded_refund));
    db.expect_finalize_event_purchase_refund()
        .with(
            eq(refund_id),
            eq(claim_id),
            eq(expected_template_data),
            eq(Some(PaymentProvider::Stripe)),
        )
        .times(1)
        .returning(|_, _, _, _| Err(anyhow::anyhow!("finalization unavailable")));
    db.expect_record_payment_job_failure()
        .withf(move |id, claim, message| {
            *id == payment_job_id && *claim == claim_id && message == "finalization unavailable"
        })
        .times(1)
        .returning(|_, _, _| Ok(()));

    // Reconcile the existing provider success without creating another refund
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    provider.expect_find_refund().times(1).return_once(|_| {
        Box::pin(async {
            Ok(Some(RefundPaymentResult {
                provider_refund_id: "re_finalize".to_string(),
                status: RefundPaymentStatus::Succeeded,
            }))
        })
    });
    provider.expect_refund_payment().never();

    // Process the provider-complete refund
    let err = worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    )
    .process_next_payment_job()
    .await
    .expect_err("local finalization failure to remain retryable");

    // Check the local failure remains visible after claim release
    assert_eq!(err.to_string(), "finalization unavailable");
}

#[tokio::test]
async fn test_process_next_payment_job_records_failure_after_lookup_error() {
    // Setup a newly claimed refund
    let claim_id = Uuid::new_v4();
    let payment_job_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let claimed_refund = sample_refund(claim_id, payment_job_id, purchase_id, refund_id);
    let job = sample_job(
        claim_id,
        payment_job_id,
        purchase_id,
        ClaimedPaymentJobWork::EventPurchaseRefund {
            refund: claimed_refund,
        },
    );

    // Setup claim release after a retryable provider error
    let mut db = MockDB::new();
    expect_empty_application_fee_adjustment_claim(&mut db);
    expect_empty_credit_note_claim(&mut db);
    db.expect_claim_payment_job()
        .with(
            eq(PaymentJobKind::EventPurchaseRefund),
            eq(PaymentProvider::Stripe),
        )
        .times(1)
        .return_once(move |_, _| Ok(Some(job)));
    db.expect_record_payment_job_failure()
        .withf(move |id, claim, message| {
            *id == payment_job_id && *claim == claim_id && message == "lookup unavailable"
        })
        .times(1)
        .returning(|_, _, _| Ok(()));

    // Fail provider lookup and forbid refund creation
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    provider
        .expect_find_refund()
        .times(1)
        .return_once(|_| Box::pin(async { Err(anyhow::anyhow!("lookup unavailable")) }));
    provider.expect_refund_payment().never();

    // Process the failed provider attempt
    let err = worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    )
    .process_next_payment_job()
    .await
    .expect_err("lookup failure to remain visible");

    // Check the original provider error is returned after claim release
    assert_eq!(err.to_string(), "lookup unavailable");
}

#[tokio::test]
async fn test_process_next_payment_job_records_failure_after_missing_pinned_refund() {
    // Setup a claimed refund pinned to a provider refund identifier
    let claim_id = Uuid::new_v4();
    let payment_job_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let mut claimed_refund = sample_refund(claim_id, payment_job_id, purchase_id, refund_id);
    claimed_refund.provider_refund_id = Some("re_missing".to_string());
    let job = sample_job(
        claim_id,
        payment_job_id,
        purchase_id,
        ClaimedPaymentJobWork::EventPurchaseRefund {
            refund: claimed_refund,
        },
    );

    // Setup claim release after the pinned provider refund cannot be found
    let mut db = MockDB::new();
    expect_empty_application_fee_adjustment_claim(&mut db);
    expect_empty_credit_note_claim(&mut db);
    db.expect_claim_payment_job()
        .with(
            eq(PaymentJobKind::EventPurchaseRefund),
            eq(PaymentProvider::Stripe),
        )
        .times(1)
        .return_once(move |_, _| Ok(Some(job)));
    db.expect_record_payment_job_failure()
        .withf(move |id, claim, message| {
            *id == payment_job_id && *claim == claim_id && message == "provider refund not found"
        })
        .times(1)
        .returning(|_, _, _| Ok(()));

    // Return a miss for the pinned refund and forbid replacement creation
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    provider
        .expect_find_refund()
        .withf(|input| input.provider_refund_id.as_deref() == Some("re_missing"))
        .times(1)
        .return_once(|_| Box::pin(async { Ok(None) }));
    provider.expect_refund_payment().never();

    // Process the missing pinned provider refund
    let err = worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    )
    .process_next_payment_job()
    .await
    .expect_err("missing pinned refund to remain retryable");

    // Check the reconciliation error remains explicit after claim release
    assert_eq!(err.to_string(), "provider refund not found");
}

#[tokio::test]
async fn test_process_next_payment_job_records_failure_after_notification_context_error() {
    // Setup a provider-complete claim that cannot load notification context
    let claim_id = Uuid::new_v4();
    let payment_job_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let mut claimed_refund = sample_refund(claim_id, payment_job_id, purchase_id, refund_id);
    let community_id = claimed_refund.community_id;
    let event_id = claimed_refund.event_id;
    claimed_refund.provider_refund_id = Some("re_persisted".to_string());
    claimed_refund.provider_refunded_at = Some(Utc::now());
    let job = sample_job(
        claim_id,
        payment_job_id,
        purchase_id,
        ClaimedPaymentJobWork::EventPurchaseRefund {
            refund: claimed_refund,
        },
    );

    // Fail notification context loading before finalization and release the claim
    let mut db = MockDB::new();
    expect_empty_application_fee_adjustment_claim(&mut db);
    expect_empty_credit_note_claim(&mut db);
    db.expect_claim_payment_job()
        .with(
            eq(PaymentJobKind::EventPurchaseRefund),
            eq(PaymentProvider::Stripe),
        )
        .times(1)
        .return_once(move |_, _| Ok(Some(job)));
    db.expect_finalize_event_purchase_refund().never();
    db.expect_get_event_summary_by_id()
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .times(1)
        .returning(|_, _| Err(anyhow::anyhow!("event unavailable")));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(SiteSettings::default()));
    db.expect_record_payment_job_failure()
        .withf(move |id, claim, message| {
            *id == payment_job_id
                && *claim == claim_id
                && message == "failed to build refund approval notification"
        })
        .times(1)
        .returning(|_, _, _| Ok(()));

    // Forbid provider calls after durable provider success
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    provider.expect_find_refund().never();
    provider.expect_refund_payment().never();

    // Process the provider-complete refund without required notification data
    let err = worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    )
    .process_next_payment_job()
    .await
    .expect_err("notification context failure to remain retryable");

    // Check finalization did not run without its atomic notification payload
    assert_eq!(
        err.to_string(),
        "failed to build refund approval notification"
    );
}

#[tokio::test]
async fn test_process_next_payment_job_records_failure_after_success_persistence_error() {
    // Setup a newly claimed refund whose provider operation succeeds
    let claim_id = Uuid::new_v4();
    let payment_job_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let claimed_refund = sample_refund(claim_id, payment_job_id, purchase_id, refund_id);
    let job = sample_job(
        claim_id,
        payment_job_id,
        purchase_id,
        ClaimedPaymentJobWork::EventPurchaseRefund {
            refund: claimed_refund,
        },
    );

    // Fail provider-success persistence and release the claim for reconciliation
    let mut db = MockDB::new();
    expect_empty_application_fee_adjustment_claim(&mut db);
    expect_empty_credit_note_claim(&mut db);
    db.expect_claim_payment_job()
        .with(
            eq(PaymentJobKind::EventPurchaseRefund),
            eq(PaymentProvider::Stripe),
        )
        .times(1)
        .return_once(move |_, _| Ok(Some(job)));
    db.expect_record_event_purchase_refund_succeeded()
        .withf(move |_, _, _, expected_claim_id| *expected_claim_id == Some(claim_id))
        .times(1)
        .returning(|_, _, _, _| Err(anyhow::anyhow!("database unavailable")));
    db.expect_record_payment_job_failure()
        .withf(move |id, claim, message| {
            *id == payment_job_id
                && *claim == claim_id
                && message == "failed to record successful provider refund"
        })
        .times(1)
        .returning(|_, _, _| Ok(()));

    // Return provider success using the stable purchase refund operation
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    provider
        .expect_find_refund()
        .times(1)
        .return_once(|_| Box::pin(async { Ok(None) }));
    provider.expect_refund_payment().times(1).return_once(|_| {
        Box::pin(async {
            Ok(RefundPaymentResult {
                provider_refund_id: "re_uncertain".to_string(),
                status: RefundPaymentStatus::Succeeded,
            })
        })
    });

    // Process the provider success with failed local persistence
    let err = worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    )
    .process_next_payment_job()
    .await
    .expect_err("provider-success persistence failure to remain visible");

    // Check the error is contextualized for retry reconciliation
    assert_eq!(
        err.to_string(),
        "failed to record successful provider refund"
    );
}

#[tokio::test]
async fn test_process_next_payment_job_records_failure_when_payment_reference_is_missing() {
    // Setup a malformed claimed refund without its provider payment reference
    let claim_id = Uuid::new_v4();
    let payment_job_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let mut claimed_refund = sample_refund(claim_id, payment_job_id, purchase_id, refund_id);
    claimed_refund.provider_payment_reference = None;
    let job = sample_job(
        claim_id,
        payment_job_id,
        purchase_id,
        ClaimedPaymentJobWork::EventPurchaseRefund {
            refund: claimed_refund,
        },
    );

    // Setup claim release for the local validation failure
    let mut db = MockDB::new();
    expect_empty_application_fee_adjustment_claim(&mut db);
    expect_empty_credit_note_claim(&mut db);
    db.expect_claim_payment_job()
        .with(
            eq(PaymentJobKind::EventPurchaseRefund),
            eq(PaymentProvider::Stripe),
        )
        .times(1)
        .return_once(move |_, _| Ok(Some(job)));
    db.expect_record_payment_job_failure()
        .withf(move |id, claim, message| {
            *id == payment_job_id
                && *claim == claim_id
                && message == "provider payment reference is missing"
        })
        .times(1)
        .returning(|_, _, _| Ok(()));

    // Forbid provider access for malformed durable work
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    provider.expect_find_refund().never();
    provider.expect_refund_payment().never();

    // Process the malformed claim
    let err = worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    )
    .process_next_payment_job()
    .await
    .expect_err("missing provider reference to fail before provider access");

    // Check the durable contract error remains explicit
    assert_eq!(err.to_string(), "provider payment reference is missing");
}

#[tokio::test]
async fn test_process_next_payment_job_persists_pending_provider_result() {
    // Setup a claimed refund pinned to an in-progress provider refund
    let claim_id = Uuid::new_v4();
    let payment_job_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let mut claimed_refund = sample_refund(claim_id, payment_job_id, purchase_id, refund_id);
    claimed_refund.provider_refund_id = Some("re_pending".to_string());
    let persisted_refund = claimed_refund.refund.clone();
    let job = sample_job(
        claim_id,
        payment_job_id,
        purchase_id,
        ClaimedPaymentJobWork::EventPurchaseRefund {
            refund: claimed_refund,
        },
    );

    // Setup durable pending-state recording without finalization
    let mut db = MockDB::new();
    expect_empty_application_fee_adjustment_claim(&mut db);
    expect_empty_credit_note_claim(&mut db);
    db.expect_claim_payment_job()
        .with(
            eq(PaymentJobKind::EventPurchaseRefund),
            eq(PaymentProvider::Stripe),
        )
        .times(1)
        .return_once(move |_, _| Ok(Some(job)));
    db.expect_record_event_purchase_refund_pending()
        .withf(move |id, _, provider_refund_id, expected_claim_id| {
            *id == refund_id
                && provider_refund_id == "re_pending"
                && *expected_claim_id == Some(claim_id)
        })
        .times(1)
        .return_once(move |_, _, _, _| Ok(persisted_refund));
    db.expect_finalize_event_purchase_refund().never();
    db.expect_record_payment_job_failure().never();

    // Poll the pinned provider refund and forbid duplicate creation
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    provider
        .expect_find_refund()
        .withf(|input| input.provider_refund_id.as_deref() == Some("re_pending"))
        .times(1)
        .return_once(|_| {
            Box::pin(async {
                Ok(Some(RefundPaymentResult {
                    provider_refund_id: "re_pending".to_string(),
                    status: RefundPaymentStatus::Pending,
                }))
            })
        });
    provider.expect_refund_payment().never();

    // Reconcile provider progress
    let processed = worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    )
    .process_next_payment_job()
    .await
    .expect("pending provider refund to persist");

    // Check the claimed job was released for later polling
    assert!(processed);
}

#[tokio::test]
async fn test_process_next_payment_job_persists_terminal_provider_failure() {
    // Setup a claimed refund pinned to a terminal provider result
    let claim_id = Uuid::new_v4();
    let payment_job_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let mut claimed_refund = sample_refund(claim_id, payment_job_id, purchase_id, refund_id);
    claimed_refund.provider_refund_id = Some("re_failed".to_string());
    let idempotency_key = claimed_refund.idempotency_key.clone();
    let job = sample_job(
        claim_id,
        payment_job_id,
        purchase_id,
        ClaimedPaymentJobWork::EventPurchaseRefund {
            refund: claimed_refund,
        },
    );

    // Setup durable terminal-failure persistence
    let mut db = MockDB::new();
    expect_empty_application_fee_adjustment_claim(&mut db);
    expect_empty_credit_note_claim(&mut db);
    db.expect_claim_payment_job()
        .with(
            eq(PaymentJobKind::EventPurchaseRefund),
            eq(PaymentProvider::Stripe),
        )
        .times(1)
        .return_once(move |_, _| Ok(Some(job)));
    db.expect_record_event_purchase_refund_terminal_failed()
        .withf(
            move |id, key, provider_refund_id, message, expected_claim_id| {
                *id == refund_id
                    && key == &idempotency_key
                    && provider_refund_id == "re_failed"
                    && message == "provider refund failed"
                    && *expected_claim_id == Some(claim_id)
            },
        )
        .times(1)
        .returning(|_, _, _, _, _| Ok(()));
    db.expect_finalize_event_purchase_refund().never();
    db.expect_record_payment_job_failure().never();

    // Poll the pinned failure and forbid duplicate creation
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    provider.expect_find_refund().times(1).return_once(|_| {
        Box::pin(async {
            Ok(Some(RefundPaymentResult {
                provider_refund_id: "re_failed".to_string(),
                status: RefundPaymentStatus::Failed,
            }))
        })
    });
    provider.expect_refund_payment().never();

    // Reconcile the terminal provider result
    let processed = worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    )
    .process_next_payment_job()
    .await
    .expect("terminal provider failure to persist");

    // Check the worker consumed the claim without local finalization
    assert!(processed);
}

#[tokio::test]
async fn test_process_next_payment_job_release_failure_preserves_provider_error() {
    // Claim an adjustment whose provider and retry-release operations fail
    let claim_id = Uuid::new_v4();
    let payment_job_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let job = sample_job(
        claim_id,
        payment_job_id,
        purchase_id,
        ClaimedPaymentJobWork::EventPurchaseApplicationFeeAdjustment {
            application_fee_adjustment: sample_application_fee_adjustment(),
        },
    );
    let mut db = MockDB::new();
    db.expect_claim_payment_job()
        .with(
            eq(PaymentJobKind::EventPurchaseApplicationFeeAdjustment),
            eq(PaymentProvider::Stripe),
        )
        .times(1)
        .return_once(move |_, _| Ok(Some(job)));
    db.expect_record_payment_job_failure()
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
    let err = worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    )
    .process_next_payment_job()
    .await
    .expect_err("original provider failure to remain visible");

    // Check the boundary preserves the actionable external failure
    assert_eq!(err.to_string(), "provider unavailable");
}

// Helpers.

/// Configures and returns the approval payload required by refund finalization.
fn expect_refund_approval_context(db: &mut MockDB, refund: &ClaimedEventPurchaseRefund) -> Value {
    let community_id = refund.community_id;
    let event_id = refund.event_id;
    let event = sample_event_summary(event_id);
    db.expect_get_event_summary_by_id()
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .times(1)
        .returning(move |_, _| Ok(event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(SiteSettings::default()));

    to_value(&EventRefundApproved {
        event: sample_event_summary(event_id),
        external_payment: false,
        link: "/community/group/group/event/event".to_string(),
        theme: SiteSettings::default().theme,
    })
    .unwrap()
}

/// Configures an empty application-fee adjustment claim attempt.
fn expect_empty_application_fee_adjustment_claim(db: &mut MockDB) {
    db.expect_claim_payment_job()
        .with(
            eq(PaymentJobKind::EventPurchaseApplicationFeeAdjustment),
            eq(PaymentProvider::Stripe),
        )
        .times(1)
        .return_once(|_, _| Ok(None));
}

/// Configures an empty credit-note claim attempt.
fn expect_empty_credit_note_claim(db: &mut MockDB) {
    db.expect_claim_payment_job()
        .with(
            eq(PaymentJobKind::EventPurchaseCreditNote),
            eq(PaymentProvider::Stripe),
        )
        .times(1)
        .return_once(|_, _| Ok(None));
}

/// Configures an empty refund claim attempt.
fn expect_empty_refund_claim(db: &mut MockDB) {
    db.expect_claim_payment_job()
        .with(
            eq(PaymentJobKind::EventPurchaseRefund),
            eq(PaymentProvider::Stripe),
        )
        .times(1)
        .return_once(|_, _| Ok(None));
}

/// Creates a claimed application-fee adjustment for worker tests.
fn sample_application_fee_adjustment() -> ClaimedEventPurchaseApplicationFeeAdjustment {
    ClaimedEventPurchaseApplicationFeeAdjustment {
        amount_minor: 125,
        connected_seller_id: "acct_worker".to_string(),
        currency_code: "USD".to_string(),
        event_purchase_application_fee_adjustment_id: Uuid::new_v4(),
        kind: "tax-reconciliation".to_string(),
        provider_application_fee_id: "fee_worker".to_string(),
    }
}

/// Creates a claimed credit note for worker tests.
fn sample_credit_note() -> ClaimedEventPurchaseCreditNote {
    ClaimedEventPurchaseCreditNote {
        amount_minor: 2_500,
        connected_seller_id: "acct_worker".to_string(),
        event_purchase_credit_note_id: Uuid::new_v4(),
        event_purchase_refund_id: Uuid::new_v4(),
        provider_invoice_id: "in_worker".to_string(),
        provider_refund_id: "re_worker".to_string(),
        tax_amount_minor: 200,
    }
}

/// Creates an event summary for refund-completion notification tests.
fn sample_event_summary(event_id: Uuid) -> EventSummary {
    EventSummary {
        attendee_approval_required: false,
        canceled: false,
        community_display_name: "Community".to_string(),
        community_name: "community".to_string(),
        event_id,
        group_category_name: "Technology".to_string(),
        group_name: "Group".to_string(),
        group_slug: "group".to_string(),
        has_external_payment: false,
        has_registration_questions: false,
        has_related_events: false,
        kind: EventKind::default(),
        logo_url: "https://example.test/logo.png".to_string(),
        name: "Event".to_string(),
        published: true,
        slug: "event".to_string(),
        test_event: false,
        timezone: chrono_tz::UTC,
        waitlist_count: 0,
        waitlist_enabled: false,

        attendee_count: None,
        capacity: None,
        created_by_display_name: None,
        created_by_username: None,
        delete_eligibility: None,
        description_short: None,
        ends_at: None,
        event_series_id: None,
        group_slug_pretty: None,
        latitude: None,
        longitude: None,
        meeting_join_instructions: None,
        meeting_join_url: None,
        meeting_password: None,
        meeting_provider: None,
        payment_currency_code: None,
        popover_html: None,
        registration_ends_at: None,
        registration_starts_at: None,
        remaining_capacity: None,
        starts_at: None,
        ticket_types: None,
        venue_address: None,
        venue_city: None,
        venue_country_code: None,
        venue_country_name: None,
        venue_name: None,
        venue_state_code: None,
        venue_state_name: None,
        zip_code: None,
    }
}

/// Creates a claimed durable payment job for worker lifecycle tests.
fn sample_job(
    claim_id: Uuid,
    payment_job_id: Uuid,
    purchase_id: Uuid,
    work: ClaimedPaymentJobWork,
) -> ClaimedPaymentJob {
    ClaimedPaymentJob {
        attempt_count: 1,
        claim_id,
        event_purchase_id: purchase_id,
        idempotency_key: format!("event-purchase-refund-{purchase_id}"),
        payment_job_id,
        payment_provider: PaymentProvider::Stripe,
        work,
    }
}

/// Creates a claimed durable refund for worker lifecycle tests.
fn sample_refund(
    claim_id: Uuid,
    payment_job_id: Uuid,
    purchase_id: Uuid,
    refund_id: Uuid,
) -> ClaimedEventPurchaseRefund {
    ClaimedEventPurchaseRefund {
        community_id: Uuid::new_v4(),
        connected_seller_id: "acct_worker".to_string(),
        event_id: Uuid::new_v4(),
        refund: EventPurchaseRefund {
            amount_minor: 2_500,
            currency_code: "USD".to_string(),
            event_purchase_id: purchase_id,
            event_purchase_refund_id: refund_id,
            idempotency_key: format!("event-purchase-refund-{purchase_id}"),
            kind: EventPurchaseRefundKind::EventCancellation,
            payment_job_id,
            payment_provider: PaymentProvider::Stripe,
            status: EventPurchaseRefundStatus::ProviderPending,
            terminal_failure: false,

            attempt_count: 1,
            claim_id: Some(claim_id),
            failure_message: None,
            finalized_at: None,
            provider_payment_reference: Some("pi_worker".to_string()),
            provider_refund_id: None,
            provider_refunded_at: None,
        },
    }
}

/// Creates a payment job worker with test doubles and a fresh cancellation token.
fn worker(
    db: Arc<MockDB>,
    notifications_manager: MockNotificationsManager,
    payments_provider: Option<MockPaymentsProvider>,
) -> Worker {
    let db = db as DynDB;
    let payments_provider =
        payments_provider.map(|provider| Arc::new(provider) as DynPaymentsProvider);

    Worker {
        cancellation_token: CancellationToken::new(),
        db: db.clone(),
        next_kind_index: AtomicUsize::new(0),
        notification_composer: PaymentsNotificationComposer::new(
            db,
            Arc::new(notifications_manager),
            HttpServerConfig::default(),
        ),
        payments_provider,
    }
}
