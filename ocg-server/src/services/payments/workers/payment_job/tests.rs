use std::sync::{Arc, atomic::AtomicUsize};

use chrono::Utc;
use mockall::predicate::eq;
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
            tests::{approval_template_matches, stripe_provider},
        },
    },
    types::{
        payments::{PaymentJobKind, PaymentProvider},
        site::SiteSettings,
        tests::sample_event_summary,
    },
};

use super::Worker;

#[tokio::test]
async fn test_process_next_payment_job_configuration_without_provider_leaves_jobs_unclaimed() {
    // Forbid durable claim mutation while no provider is configured
    let mut db = MockDB::new();
    db.expect_claim_payment_job().never();

    // Attempt to process queued work without a provider
    let processed = worker(db, None)
        .process_next_payment_job()
        .await
        .expect("unconfigured worker to stay idle");

    // Check durable work remains queued
    assert!(!processed);
}

#[tokio::test]
async fn test_process_next_payment_job_creates_missing_provider_refund_and_finalizes_success() {
    // Setup a claimed refund without a known provider refund
    let claimed_refund = sample_refund();
    let job = refund_job(&claimed_refund);
    let claim_id = job.claim_id;
    let event_id = claimed_refund.event_id;
    let purchase_id = claimed_refund.event_purchase_id;
    let refund_id = claimed_refund.event_purchase_refund_id;
    let mut succeeded_refund = claimed_refund.refund.clone();
    succeeded_refund.provider_refund_id = Some("re_worker".to_string());
    succeeded_refund.provider_refunded_at = Some(Utc::now());

    // Setup durable claim, provider-success recording, and finalization
    let mut db = MockDB::new();
    expect_claimed_job(&mut db, job);
    expect_refund_approval_context(&mut db, &claimed_refund);
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
        .withf(move |id, claim, template_data, provider| {
            *id == refund_id
                && *claim == claim_id
                && approval_template_matches(template_data, event_id, false)
                && *provider == Some(PaymentProvider::Stripe)
        })
        .times(1)
        .return_once(|_, _, _, _| Ok(()));

    // Setup lookup-before-create and stable idempotency expectations
    let mut provider = stripe_provider();
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
    let processed = worker(db, Some(provider))
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
    for kind in PaymentJobKind::ALL {
        expect_empty_claim(&mut db, kind);
    }

    // Process one empty worker iteration
    let processed = worker(db, Some(stripe_provider()))
        .process_next_payment_job()
        .await
        .expect("empty payment job queue to remain idle");

    // Check the worker reports that it consumed no job
    assert!(!processed);
}

#[tokio::test]
async fn test_process_next_payment_job_finalizes_persisted_success_without_provider_call() {
    // Setup a claim whose provider success was already persisted
    let mut claimed_refund = sample_refund();
    claimed_refund.provider_refund_id = Some("re_persisted".to_string());
    claimed_refund.provider_refunded_at = Some(Utc::now());
    let job = refund_job(&claimed_refund);
    let claim_id = job.claim_id;
    let event_id = claimed_refund.event_id;
    let refund_id = claimed_refund.event_purchase_refund_id;

    // Setup local finalization and completion-notification context
    let mut db = MockDB::new();
    expect_claimed_job(&mut db, job);
    expect_refund_approval_context(&mut db, &claimed_refund);
    db.expect_finalize_event_purchase_refund()
        .withf(move |id, claim, template_data, provider| {
            *id == refund_id
                && *claim == claim_id
                && approval_template_matches(template_data, event_id, false)
                && *provider == Some(PaymentProvider::Stripe)
        })
        .times(1)
        .return_once(|_, _, _, _| Ok(()));

    // Forbid the legacy post-commit notification enqueue
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager.expect_enqueue().never();

    // Forbid provider calls after durable success
    let mut provider = stripe_provider();
    provider.expect_find_refund().never();
    provider.expect_refund_payment().never();

    // Resume local finalization
    let processed = worker_with_notifications(db, notifications_manager, Some(provider))
        .process_next_payment_job()
        .await
        .expect("persisted provider success to finalize");

    // Check finalization consumed one job without another provider operation
    assert!(processed);
}

#[tokio::test]
async fn test_process_next_payment_job_finds_existing_success_without_creating_refund() {
    // Setup a claimed refund whose provider operation already exists
    let claimed_refund = sample_refund();
    let job = refund_job(&claimed_refund);
    let claim_id = job.claim_id;
    let event_id = claimed_refund.event_id;
    let refund_id = claimed_refund.event_purchase_refund_id;
    let mut succeeded_refund = claimed_refund.refund.clone();
    succeeded_refund.provider_refund_id = Some("re_existing".to_string());
    succeeded_refund.provider_refunded_at = Some(Utc::now());

    // Setup durable success recording and finalization
    let mut db = MockDB::new();
    expect_claimed_job(&mut db, job);
    expect_refund_approval_context(&mut db, &claimed_refund);
    db.expect_record_event_purchase_refund_succeeded()
        .withf(move |id, _, provider_refund_id, expected_claim_id| {
            *id == refund_id
                && provider_refund_id == "re_existing"
                && *expected_claim_id == Some(claim_id)
        })
        .times(1)
        .return_once(move |_, _, _, _| Ok(succeeded_refund));
    db.expect_finalize_event_purchase_refund()
        .withf(move |id, claim, template_data, provider| {
            *id == refund_id
                && *claim == claim_id
                && approval_template_matches(template_data, event_id, false)
                && *provider == Some(PaymentProvider::Stripe)
        })
        .times(1)
        .returning(|_, _, _, _| Ok(()));

    // Return the existing provider success and forbid another creation
    let mut provider = stripe_provider();
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
    let processed = worker(db, Some(provider))
        .process_next_payment_job()
        .await
        .expect("existing provider refund to finalize");

    // Check the worker consumed one job
    assert!(processed);
}

#[tokio::test]
async fn test_process_next_payment_job_processes_application_fee_adjustment() {
    // Claim one due adjustment and persist its provider result
    let adjustment = sample_application_fee_adjustment();
    let adjustment_id = adjustment.event_purchase_application_fee_adjustment_id;
    let job = fee_adjustment_job(adjustment);
    let claim_id = job.claim_id;
    let idempotency_key = job.idempotency_key.clone();
    let purchase_id = job.event_purchase_id;
    let mut db = MockDB::new();
    expect_claimed_job(&mut db, job);
    db.expect_record_event_purchase_application_fee_adjustment_succeeded()
        .withf(move |id, claim, provider_id| {
            *id == adjustment_id && *claim == claim_id && provider_id == "fr_test_123"
        })
        .times(1)
        .return_once(|_, _, _| Ok(()));

    // Reconcile the adjustment with its immutable provider context
    let mut provider = stripe_provider();
    provider
        .expect_reconcile_application_fee_adjustment()
        .withf(move |input| {
            input.amount_minor == 125
                && input.connected_seller_id == "acct_worker"
                && input.currency_code == "USD"
                && input.event_purchase_id == purchase_id
                && input.idempotency_key == idempotency_key
                && input.kind == "tax-reconciliation"
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
    let processed = worker(db, Some(provider))
        .process_next_payment_job()
        .await
        .expect("fee adjustment to succeed");

    // Check the worker reports that it consumed the job
    assert!(processed);
}

#[tokio::test]
async fn test_process_next_payment_job_rotates_the_first_claimed_kind_between_iterations() {
    // Keep adjustments continuously claimable so a fixed order would starve other kinds
    let adjustment_job = fee_adjustment_job(sample_application_fee_adjustment());
    let credit_note_job = credit_note_job(sample_credit_note());
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
    let mut provider = stripe_provider();
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
    let worker = worker(db, Some(provider));
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
    let credit_note = sample_credit_note();
    let credit_note_id = credit_note.event_purchase_credit_note_id;
    let job = credit_note_job(credit_note);
    let claim_id = job.claim_id;
    let purchase_id = job.event_purchase_id;
    let mut db = MockDB::new();
    expect_claimed_job(&mut db, job);
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
    let mut provider = stripe_provider();
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
    let processed = worker(db, Some(provider))
        .process_next_payment_job()
        .await
        .expect("credit note to succeed");

    // Check the worker reports that it consumed the job
    assert!(processed);
}

#[tokio::test]
async fn test_process_next_payment_job_records_failure_after_application_fee_error() {
    // Claim an adjustment whose provider operation fails
    let job = fee_adjustment_job(sample_application_fee_adjustment());
    let (claim_id, payment_job_id) = (job.claim_id, job.payment_job_id);
    let mut db = MockDB::new();
    expect_claimed_job(&mut db, job);
    db.expect_record_payment_job_failure()
        .withf(move |id, claim, message| {
            *id == payment_job_id && *claim == claim_id && message == "provider unavailable"
        })
        .times(1)
        .return_once(|_, _, _| Ok(()));
    db.expect_record_event_purchase_application_fee_adjustment_succeeded()
        .never();
    let mut provider = stripe_provider();
    provider
        .expect_reconcile_application_fee_adjustment()
        .times(1)
        .return_once(|_| Box::pin(async { Err(anyhow::anyhow!("provider unavailable")) }));

    // Process the failing provider request
    let err = worker(db, Some(provider))
        .process_next_payment_job()
        .await
        .expect_err("provider failure to remain visible");

    // Check the provider failure remains the worker error
    assert_eq!(err.to_string(), "provider unavailable");
}

#[tokio::test]
async fn test_process_next_payment_job_records_failure_after_credit_note_error() {
    // Claim a credit note whose provider operation fails
    let job = credit_note_job(sample_credit_note());
    let (claim_id, payment_job_id) = (job.claim_id, job.payment_job_id);
    let mut db = MockDB::new();
    expect_claimed_job(&mut db, job);
    db.expect_record_payment_job_failure()
        .withf(move |id, claim, message| {
            *id == payment_job_id && *claim == claim_id && message == "credit note unavailable"
        })
        .times(1)
        .return_once(|_, _, _| Ok(()));
    let mut provider = stripe_provider();
    provider
        .expect_reconcile_credit_note()
        .times(1)
        .return_once(|_| Box::pin(async { Err(anyhow::anyhow!("credit note unavailable")) }));

    // Process the failing provider request
    let err = worker(db, Some(provider))
        .process_next_payment_job()
        .await
        .expect_err("credit-note failure to remain visible");

    // Check the provider failure remains the worker error
    assert_eq!(err.to_string(), "credit note unavailable");
}

#[tokio::test]
async fn test_process_next_payment_job_records_failure_after_creation_error() {
    // Setup a newly claimed refund without a known provider refund
    let job = refund_job(&sample_refund());
    let (claim_id, payment_job_id) = (job.claim_id, job.payment_job_id);

    // Setup claim release after provider refund creation fails
    let mut db = MockDB::new();
    expect_claimed_job(&mut db, job);
    db.expect_record_payment_job_failure()
        .withf(move |id, claim, message| {
            *id == payment_job_id && *claim == claim_id && message == "creation unavailable"
        })
        .times(1)
        .returning(|_, _, _| Ok(()));

    // Return a lookup miss followed by a retryable creation error
    let mut provider = stripe_provider();
    provider
        .expect_find_refund()
        .times(1)
        .return_once(|_| Box::pin(async { Ok(None) }));
    provider
        .expect_refund_payment()
        .times(1)
        .return_once(|_| Box::pin(async { Err(anyhow::anyhow!("creation unavailable")) }));

    // Process the failed provider attempt
    let err = worker(db, Some(provider))
        .process_next_payment_job()
        .await
        .expect_err("creation failure to remain visible");

    // Check the original provider error is returned after claim release
    assert_eq!(err.to_string(), "creation unavailable");
}

#[tokio::test]
async fn test_process_next_payment_job_records_failure_after_finalization_error() {
    // Setup a claimed refund whose provider operation has succeeded
    let claimed_refund = sample_refund();
    let job = refund_job(&claimed_refund);
    let (claim_id, payment_job_id) = (job.claim_id, job.payment_job_id);
    let event_id = claimed_refund.event_id;
    let refund_id = claimed_refund.event_purchase_refund_id;
    let mut succeeded_refund = claimed_refund.refund.clone();
    succeeded_refund.provider_refund_id = Some("re_finalize".to_string());
    succeeded_refund.provider_refunded_at = Some(Utc::now());

    // Fail local finalization and release the current claim for retry
    let mut db = MockDB::new();
    expect_claimed_job(&mut db, job);
    expect_refund_approval_context(&mut db, &claimed_refund);
    db.expect_record_event_purchase_refund_succeeded()
        .withf(move |_, _, _, expected_claim_id| *expected_claim_id == Some(claim_id))
        .times(1)
        .return_once(move |_, _, _, _| Ok(succeeded_refund));
    db.expect_finalize_event_purchase_refund()
        .withf(move |id, claim, template_data, provider| {
            *id == refund_id
                && *claim == claim_id
                && approval_template_matches(template_data, event_id, false)
                && *provider == Some(PaymentProvider::Stripe)
        })
        .times(1)
        .returning(|_, _, _, _| Err(anyhow::anyhow!("finalization unavailable")));
    db.expect_record_payment_job_failure()
        .withf(move |id, claim, message| {
            *id == payment_job_id && *claim == claim_id && message == "finalization unavailable"
        })
        .times(1)
        .returning(|_, _, _| Ok(()));

    // Reconcile the existing provider success without creating another refund
    let mut provider = stripe_provider();
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
    let err = worker(db, Some(provider))
        .process_next_payment_job()
        .await
        .expect_err("local finalization failure to remain retryable");

    // Check the local failure remains visible after claim release
    assert_eq!(err.to_string(), "finalization unavailable");
}

#[tokio::test]
async fn test_process_next_payment_job_records_failure_after_lookup_error() {
    // Setup a newly claimed refund
    let job = refund_job(&sample_refund());
    let (claim_id, payment_job_id) = (job.claim_id, job.payment_job_id);

    // Setup claim release after a retryable provider error
    let mut db = MockDB::new();
    expect_claimed_job(&mut db, job);
    db.expect_record_payment_job_failure()
        .withf(move |id, claim, message| {
            *id == payment_job_id && *claim == claim_id && message == "lookup unavailable"
        })
        .times(1)
        .returning(|_, _, _| Ok(()));

    // Fail provider lookup and forbid refund creation
    let mut provider = stripe_provider();
    provider
        .expect_find_refund()
        .times(1)
        .return_once(|_| Box::pin(async { Err(anyhow::anyhow!("lookup unavailable")) }));
    provider.expect_refund_payment().never();

    // Process the failed provider attempt
    let err = worker(db, Some(provider))
        .process_next_payment_job()
        .await
        .expect_err("lookup failure to remain visible");

    // Check the original provider error is returned after claim release
    assert_eq!(err.to_string(), "lookup unavailable");
}

#[tokio::test]
async fn test_process_next_payment_job_records_failure_after_missing_pinned_refund() {
    // Setup a claimed refund pinned to a provider refund identifier
    let mut claimed_refund = sample_refund();
    claimed_refund.provider_refund_id = Some("re_missing".to_string());
    let job = refund_job(&claimed_refund);
    let (claim_id, payment_job_id) = (job.claim_id, job.payment_job_id);

    // Setup claim release after the pinned provider refund cannot be found
    let mut db = MockDB::new();
    expect_claimed_job(&mut db, job);
    db.expect_record_payment_job_failure()
        .withf(move |id, claim, message| {
            *id == payment_job_id && *claim == claim_id && message == "provider refund not found"
        })
        .times(1)
        .returning(|_, _, _| Ok(()));

    // Return a miss for the pinned refund and forbid replacement creation
    let mut provider = stripe_provider();
    provider
        .expect_find_refund()
        .withf(|input| input.provider_refund_id.as_deref() == Some("re_missing"))
        .times(1)
        .return_once(|_| Box::pin(async { Ok(None) }));
    provider.expect_refund_payment().never();

    // Process the missing pinned provider refund
    let err = worker(db, Some(provider))
        .process_next_payment_job()
        .await
        .expect_err("missing pinned refund to remain retryable");

    // Check the reconciliation error remains explicit after claim release
    assert_eq!(err.to_string(), "provider refund not found");
}

#[tokio::test]
async fn test_process_next_payment_job_records_failure_after_notification_context_error() {
    // Setup a provider-complete claim that cannot load notification context
    let mut claimed_refund = sample_refund();
    claimed_refund.provider_refund_id = Some("re_persisted".to_string());
    claimed_refund.provider_refunded_at = Some(Utc::now());
    let community_id = claimed_refund.community_id;
    let event_id = claimed_refund.event_id;
    let job = refund_job(&claimed_refund);
    let (claim_id, payment_job_id) = (job.claim_id, job.payment_job_id);

    // Fail notification context loading before finalization and release the claim
    let mut db = MockDB::new();
    expect_claimed_job(&mut db, job);
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
                && message == "failed to build refund approval notification: event unavailable"
        })
        .times(1)
        .returning(|_, _, _| Ok(()));

    // Forbid provider calls after durable provider success
    let mut provider = stripe_provider();
    provider.expect_find_refund().never();
    provider.expect_refund_payment().never();

    // Process the provider-complete refund without required notification data
    let err = worker(db, Some(provider))
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
    let job = refund_job(&sample_refund());
    let (claim_id, payment_job_id) = (job.claim_id, job.payment_job_id);

    // Fail provider-success persistence and release the claim for reconciliation
    let mut db = MockDB::new();
    expect_claimed_job(&mut db, job);
    db.expect_record_event_purchase_refund_succeeded()
        .withf(move |_, _, _, expected_claim_id| *expected_claim_id == Some(claim_id))
        .times(1)
        .returning(|_, _, _, _| Err(anyhow::anyhow!("database unavailable")));
    db.expect_record_payment_job_failure()
        .withf(move |id, claim, message| {
            *id == payment_job_id
                && *claim == claim_id
                && message == "failed to record successful provider refund: database unavailable"
        })
        .times(1)
        .returning(|_, _, _| Ok(()));

    // Return provider success using the stable purchase refund operation
    let mut provider = stripe_provider();
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
    let err = worker(db, Some(provider))
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
    let mut claimed_refund = sample_refund();
    claimed_refund.provider_payment_reference = None;
    let job = refund_job(&claimed_refund);
    let (claim_id, payment_job_id) = (job.claim_id, job.payment_job_id);

    // Setup claim release for the local validation failure
    let mut db = MockDB::new();
    expect_claimed_job(&mut db, job);
    db.expect_record_payment_job_failure()
        .withf(move |id, claim, message| {
            *id == payment_job_id
                && *claim == claim_id
                && message == "provider payment reference is missing"
        })
        .times(1)
        .returning(|_, _, _| Ok(()));

    // Forbid provider access for malformed durable work
    let mut provider = stripe_provider();
    provider.expect_find_refund().never();
    provider.expect_refund_payment().never();

    // Process the malformed claim
    let err = worker(db, Some(provider))
        .process_next_payment_job()
        .await
        .expect_err("missing provider reference to fail before provider access");

    // Check the durable contract error remains explicit
    assert_eq!(err.to_string(), "provider payment reference is missing");
}

#[tokio::test]
async fn test_process_next_payment_job_persists_pending_provider_result() {
    // Setup a claimed refund pinned to an in-progress provider refund
    let mut claimed_refund = sample_refund();
    claimed_refund.provider_refund_id = Some("re_pending".to_string());
    let persisted_refund = claimed_refund.refund.clone();
    let job = refund_job(&claimed_refund);
    let claim_id = job.claim_id;
    let refund_id = claimed_refund.event_purchase_refund_id;

    // Setup durable pending-state recording without finalization
    let mut db = MockDB::new();
    expect_claimed_job(&mut db, job);
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
    let mut provider = stripe_provider();
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
    let processed = worker(db, Some(provider))
        .process_next_payment_job()
        .await
        .expect("pending provider refund to persist");

    // Check the claimed job was released for later polling
    assert!(processed);
}

#[tokio::test]
async fn test_process_next_payment_job_persists_terminal_provider_failure() {
    // Setup a claimed refund pinned to a terminal provider result
    let mut claimed_refund = sample_refund();
    claimed_refund.provider_refund_id = Some("re_failed".to_string());
    let idempotency_key = claimed_refund.idempotency_key.clone();
    let job = refund_job(&claimed_refund);
    let claim_id = job.claim_id;
    let refund_id = claimed_refund.event_purchase_refund_id;

    // Setup durable terminal-failure persistence
    let mut db = MockDB::new();
    expect_claimed_job(&mut db, job);
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
    let mut provider = stripe_provider();
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
    let processed = worker(db, Some(provider))
        .process_next_payment_job()
        .await
        .expect("terminal provider failure to persist");

    // Check the worker consumed the claim without local finalization
    assert!(processed);
}

#[tokio::test]
async fn test_process_next_payment_job_release_failure_preserves_provider_error() {
    // Claim an adjustment whose provider and retry-release operations fail
    let job = fee_adjustment_job(sample_application_fee_adjustment());
    let mut db = MockDB::new();
    expect_claimed_job(&mut db, job);
    db.expect_record_payment_job_failure()
        .times(1)
        .return_once(|_, _, _| Err(anyhow::anyhow!("claim release unavailable")));
    let mut provider = stripe_provider();
    provider
        .expect_reconcile_application_fee_adjustment()
        .times(1)
        .return_once(|_| Box::pin(async { Err(anyhow::anyhow!("provider unavailable")) }));

    // Process the provider failure while durable release also fails
    let err = worker(db, Some(provider))
        .process_next_payment_job()
        .await
        .expect_err("original provider failure to remain visible");

    // Check the boundary preserves the actionable external failure
    assert_eq!(err.to_string(), "provider unavailable");
}

// Helpers.

/// Expects the claim sequence that reaches `job`: empty claims for earlier kinds, then `job`.
///
/// Tests that assert the claim order itself register their claims explicitly.
fn expect_claimed_job(db: &mut MockDB, job: ClaimedPaymentJob) {
    let kind = match job.work {
        ClaimedPaymentJobWork::EventPurchaseApplicationFeeAdjustment { .. } => {
            PaymentJobKind::EventPurchaseApplicationFeeAdjustment
        }
        ClaimedPaymentJobWork::EventPurchaseCreditNote { .. } => {
            PaymentJobKind::EventPurchaseCreditNote
        }
        ClaimedPaymentJobWork::EventPurchaseRefund { .. } => PaymentJobKind::EventPurchaseRefund,
    };
    for earlier_kind in PaymentJobKind::ALL.into_iter().take_while(|k| *k != kind) {
        expect_empty_claim(db, earlier_kind);
    }
    db.expect_claim_payment_job()
        .with(eq(kind), eq(PaymentProvider::Stripe))
        .times(1)
        .return_once(move |_, _| Ok(Some(job)));
}

/// Expects one empty claim attempt for the given job kind.
fn expect_empty_claim(db: &mut MockDB, kind: PaymentJobKind) {
    db.expect_claim_payment_job()
        .with(eq(kind), eq(PaymentProvider::Stripe))
        .times(1)
        .return_once(|_, _| Ok(None));
}

/// Expects the event and site context loaded for the refund approval payload.
fn expect_refund_approval_context(db: &mut MockDB, refund: &ClaimedEventPurchaseRefund) {
    let community_id = refund.community_id;
    let event_id = refund.event_id;
    db.expect_get_event_summary_by_id()
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .times(1)
        .returning(move |_, _| Ok(sample_event_summary(event_id)));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(SiteSettings::default()));
}

/// Wraps a credit note in a freshly claimed payment job.
fn credit_note_job(credit_note: ClaimedEventPurchaseCreditNote) -> ClaimedPaymentJob {
    sample_job(ClaimedPaymentJobWork::EventPurchaseCreditNote { credit_note })
}

/// Wraps an application-fee adjustment in a freshly claimed payment job.
fn fee_adjustment_job(
    application_fee_adjustment: ClaimedEventPurchaseApplicationFeeAdjustment,
) -> ClaimedPaymentJob {
    sample_job(
        ClaimedPaymentJobWork::EventPurchaseApplicationFeeAdjustment {
            application_fee_adjustment,
        },
    )
}

/// Wraps a claimed refund in the payment job that carries its lifecycle identifiers.
fn refund_job(refund: &ClaimedEventPurchaseRefund) -> ClaimedPaymentJob {
    ClaimedPaymentJob {
        attempt_count: 1,
        claim_id: refund.claim_id.expect("sample refund to carry its claim"),
        event_purchase_id: refund.event_purchase_id,
        idempotency_key: refund.idempotency_key.clone(),
        payment_job_id: refund.payment_job_id,
        payment_provider: PaymentProvider::Stripe,
        work: ClaimedPaymentJobWork::EventPurchaseRefund {
            refund: refund.clone(),
        },
    }
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

/// Creates a claimed durable payment job with fresh lifecycle identifiers.
fn sample_job(work: ClaimedPaymentJobWork) -> ClaimedPaymentJob {
    let event_purchase_id = Uuid::new_v4();

    ClaimedPaymentJob {
        attempt_count: 1,
        claim_id: Uuid::new_v4(),
        event_purchase_id,
        idempotency_key: format!("event-purchase-refund-{event_purchase_id}"),
        payment_job_id: Uuid::new_v4(),
        payment_provider: PaymentProvider::Stripe,
        work,
    }
}

/// Creates a claimed durable refund with fresh identifiers for worker lifecycle tests.
fn sample_refund() -> ClaimedEventPurchaseRefund {
    let event_purchase_id = Uuid::new_v4();

    ClaimedEventPurchaseRefund {
        community_id: Uuid::new_v4(),
        connected_seller_id: "acct_worker".to_string(),
        event_id: Uuid::new_v4(),
        refund: EventPurchaseRefund {
            amount_minor: 2_500,
            currency_code: "USD".to_string(),
            event_purchase_id,
            event_purchase_refund_id: Uuid::new_v4(),
            idempotency_key: format!("event-purchase-refund-{event_purchase_id}"),
            kind: EventPurchaseRefundKind::EventCancellation,
            payment_job_id: Uuid::new_v4(),
            payment_provider: PaymentProvider::Stripe,
            status: EventPurchaseRefundStatus::ProviderPending,
            terminal_failure: false,

            attempt_count: 1,
            claim_id: Some(Uuid::new_v4()),
            failure_message: None,
            finalized_at: None,
            provider_payment_reference: Some("pi_worker".to_string()),
            provider_refund_id: None,
            provider_refunded_at: None,
        },
    }
}

/// Creates a payment job worker with no expected notifications.
fn worker(db: MockDB, payments_provider: Option<MockPaymentsProvider>) -> Worker {
    worker_with_notifications(db, MockNotificationsManager::new(), payments_provider)
}

/// Creates a payment job worker with test doubles and a fresh cancellation token.
fn worker_with_notifications(
    db: MockDB,
    notifications_manager: MockNotificationsManager,
    payments_provider: Option<MockPaymentsProvider>,
) -> Worker {
    let db = Arc::new(db) as DynDB;
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
