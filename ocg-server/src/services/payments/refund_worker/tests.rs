use std::{future::pending, sync::Arc, time::Duration};

use chrono::Utc;
use mockall::predicate::eq;
use serde_json::{Value, to_value};
use tokio::{sync::Notify, time::timeout};
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::{
        DynDB,
        mock::MockDB,
        payments::{
            ClaimedEventPurchaseRefund, EventPurchaseRefund, EventPurchaseRefundKind,
            EventPurchaseRefundStatus,
        },
    },
    services::{
        notifications::MockNotificationsManager,
        payments::{
            DynPaymentsProvider, RefundPaymentResult, RefundPaymentStatus,
            notification_composer::PaymentsNotificationComposer, provider::MockPaymentsProvider,
        },
    },
    templates::notifications::EventRefundApproved,
    types::{
        event::{EventKind, EventSummary},
        payments::PaymentProvider,
        site::SiteSettings,
    },
};

use super::{RefundRecoveryWorker, RefundWorker, run_until_cancelled};

#[tokio::test]
async fn process_next_refund_creates_missing_provider_refund_and_finalizes_success() {
    // Setup a claimed refund without a known provider refund
    let claim_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let mut claimed_refund = sample_refund(claim_id, purchase_id, refund_id);
    claimed_refund.community_id = community_id;
    claimed_refund.event_id = event_id;
    let mut succeeded_refund = claimed_refund.refund.clone();
    succeeded_refund.provider_refund_id = Some("re_worker".to_string());
    succeeded_refund.provider_refunded_at = Some(Utc::now());

    // Setup durable claim, provider-success recording, and finalization
    let mut db = MockDB::new();
    let expected_template_data = expect_refund_approval_context(&mut db, &claimed_refund);
    db.expect_claim_event_purchase_refund()
        .with(eq(PaymentProvider::Stripe))
        .times(1)
        .return_once(move |_| Ok(Some(claimed_refund)));
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
        .with(eq(refund_id), eq(claim_id), eq(expected_template_data))
        .times(1)
        .return_once(|_, _, _| Ok(()));

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
    let worker = refund_worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    );
    let processed = worker
        .process_next_refund()
        .await
        .expect("provider refund to succeed");

    // Check the worker consumed one job
    assert!(processed);
}

#[tokio::test]
async fn process_next_refund_finalizes_persisted_success_without_provider_call_and_notifies() {
    // Setup a claim whose provider success was already persisted
    let claim_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let mut claimed_refund = sample_refund(claim_id, purchase_id, refund_id);
    claimed_refund.community_id = community_id;
    claimed_refund.event_id = event_id;
    claimed_refund.provider_refund_id = Some("re_persisted".to_string());
    claimed_refund.provider_refunded_at = Some(Utc::now());

    // Setup local finalization and completion-notification context
    let mut db = MockDB::new();
    let expected_template_data = expect_refund_approval_context(&mut db, &claimed_refund);
    db.expect_claim_event_purchase_refund()
        .with(eq(PaymentProvider::Stripe))
        .times(1)
        .return_once(move |_| Ok(Some(claimed_refund)));
    db.expect_finalize_event_purchase_refund()
        .with(eq(refund_id), eq(claim_id), eq(expected_template_data))
        .times(1)
        .return_once(|_, _, _| Ok(()));

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
    let worker = refund_worker(Arc::new(db), notifications_manager, Some(provider));
    let processed = worker
        .process_next_refund()
        .await
        .expect("persisted provider success to finalize");

    // Check finalization consumed one job without another provider operation
    assert!(processed);
}

#[tokio::test]
async fn process_next_refund_finds_existing_success_without_creating_refund() {
    // Setup a claimed refund whose provider operation already exists
    let claim_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let claimed_refund = sample_refund(claim_id, purchase_id, refund_id);
    let mut succeeded_refund = claimed_refund.refund.clone();
    succeeded_refund.provider_refund_id = Some("re_existing".to_string());
    succeeded_refund.provider_refunded_at = Some(Utc::now());

    // Setup durable success recording and finalization
    let mut db = MockDB::new();
    let expected_template_data = expect_refund_approval_context(&mut db, &claimed_refund);
    db.expect_claim_event_purchase_refund()
        .times(1)
        .return_once(move |_| Ok(Some(claimed_refund)));
    db.expect_record_event_purchase_refund_succeeded()
        .withf(move |id, _, provider_refund_id, expected_claim_id| {
            *id == refund_id
                && provider_refund_id == "re_existing"
                && *expected_claim_id == Some(claim_id)
        })
        .times(1)
        .return_once(move |_, _, _, _| Ok(succeeded_refund));
    db.expect_finalize_event_purchase_refund()
        .with(eq(refund_id), eq(claim_id), eq(expected_template_data))
        .times(1)
        .returning(|_, _, _| Ok(()));

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
    let worker = refund_worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    );
    let processed = worker
        .process_next_refund()
        .await
        .expect("existing provider refund to finalize");

    // Check the worker consumed one job
    assert!(processed);
}

#[tokio::test]
async fn process_next_refund_handles_persisted_success_finalization_error() {
    // Setup a claimed refund whose provider success was already persisted
    let claim_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let mut claimed_refund = sample_refund(claim_id, purchase_id, refund_id);
    claimed_refund.provider_refund_id = Some("re_persisted".to_string());
    claimed_refund.provider_refunded_at = Some(Utc::now());

    // Fail local finalization and release the persisted-success claim for retry
    let mut db = MockDB::new();
    let expected_template_data = expect_refund_approval_context(&mut db, &claimed_refund);
    db.expect_claim_event_purchase_refund()
        .times(1)
        .return_once(move |_| Ok(Some(claimed_refund)));
    db.expect_finalize_event_purchase_refund()
        .with(eq(refund_id), eq(claim_id), eq(expected_template_data))
        .times(1)
        .returning(|_, _, _| Err(anyhow::anyhow!("finalization unavailable")));
    db.expect_record_event_purchase_refund_retryable_failure()
        .withf(move |id, claim, message| {
            *id == refund_id && *claim == claim_id && message == "finalization unavailable"
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

    // Process the provider-complete refund
    let worker = refund_worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    );
    let err = worker
        .process_next_refund()
        .await
        .expect_err("persisted finalization failure to remain retryable");

    // Check the local failure remains visible after claim release
    assert_eq!(err.to_string(), "finalization unavailable");
}

#[tokio::test]
async fn process_next_refund_persists_pending_provider_result() {
    // Setup a claimed refund pinned to an in-progress provider refund
    let claim_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let mut claimed_refund = sample_refund(claim_id, purchase_id, refund_id);
    claimed_refund.provider_refund_id = Some("re_pending".to_string());
    let persisted_refund = claimed_refund.refund.clone();

    // Setup durable pending-state recording without finalization
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_refund()
        .times(1)
        .return_once(move |_| Ok(Some(claimed_refund)));
    db.expect_record_event_purchase_refund_pending()
        .withf(move |id, _, provider_refund_id, expected_claim_id| {
            *id == refund_id
                && provider_refund_id == "re_pending"
                && *expected_claim_id == Some(claim_id)
        })
        .times(1)
        .return_once(move |_, _, _, _| Ok(persisted_refund));
    db.expect_finalize_event_purchase_refund().never();

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
    let worker = refund_worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    );
    let processed = worker
        .process_next_refund()
        .await
        .expect("pending provider refund to persist");

    // Check the claimed job was released for later polling
    assert!(processed);
}

#[tokio::test]
async fn process_next_refund_persists_terminal_provider_failure() {
    // Setup a claimed refund pinned to a terminal provider result
    let claim_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let mut claimed_refund = sample_refund(claim_id, purchase_id, refund_id);
    claimed_refund.provider_refund_id = Some("re_failed".to_string());
    let idempotency_key = claimed_refund.idempotency_key.clone();

    // Setup durable terminal-failure persistence
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_refund()
        .times(1)
        .return_once(move |_| Ok(Some(claimed_refund)));
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
    let worker = refund_worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    );
    let processed = worker
        .process_next_refund()
        .await
        .expect("terminal provider failure to persist");

    // Check the worker consumed the claim without local finalization
    assert!(processed);
}

#[tokio::test]
async fn process_next_refund_records_retryable_failure_after_creation_error() {
    // Setup a newly claimed refund without a known provider refund
    let claim_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let claimed_refund = sample_refund(claim_id, purchase_id, refund_id);

    // Setup claim release after provider refund creation fails
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_refund()
        .times(1)
        .return_once(move |_| Ok(Some(claimed_refund)));
    db.expect_record_event_purchase_refund_retryable_failure()
        .withf(move |id, claim, message| {
            *id == refund_id && *claim == claim_id && message == "creation unavailable"
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
    let worker = refund_worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    );
    let err = worker
        .process_next_refund()
        .await
        .expect_err("creation failure to remain visible");

    // Check the original provider error is returned after claim release
    assert_eq!(err.to_string(), "creation unavailable");
}

#[tokio::test]
async fn process_next_refund_records_retryable_failure_after_finalization_error() {
    // Setup a claimed refund whose provider operation has succeeded
    let claim_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let claimed_refund = sample_refund(claim_id, purchase_id, refund_id);
    let mut succeeded_refund = claimed_refund.refund.clone();
    succeeded_refund.provider_refund_id = Some("re_finalize".to_string());
    succeeded_refund.provider_refunded_at = Some(Utc::now());

    // Fail local finalization and release the current claim for retry
    let mut db = MockDB::new();
    let expected_template_data = expect_refund_approval_context(&mut db, &claimed_refund);
    db.expect_claim_event_purchase_refund()
        .times(1)
        .return_once(move |_| Ok(Some(claimed_refund)));
    db.expect_record_event_purchase_refund_succeeded()
        .withf(move |_, _, _, expected_claim_id| *expected_claim_id == Some(claim_id))
        .times(1)
        .return_once(move |_, _, _, _| Ok(succeeded_refund));
    db.expect_finalize_event_purchase_refund()
        .with(eq(refund_id), eq(claim_id), eq(expected_template_data))
        .times(1)
        .returning(|_, _, _| Err(anyhow::anyhow!("finalization unavailable")));
    db.expect_record_event_purchase_refund_retryable_failure()
        .withf(move |id, claim, message| {
            *id == refund_id && *claim == claim_id && message == "finalization unavailable"
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
    let worker = refund_worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    );
    let err = worker
        .process_next_refund()
        .await
        .expect_err("local finalization failure to remain retryable");

    // Check the local failure remains visible after claim release
    assert_eq!(err.to_string(), "finalization unavailable");
}

#[tokio::test]
async fn process_next_refund_records_retryable_failure_after_lookup_error() {
    // Setup a newly claimed refund
    let claim_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let claimed_refund = sample_refund(claim_id, purchase_id, refund_id);

    // Setup claim release after a retryable provider error
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_refund()
        .times(1)
        .return_once(move |_| Ok(Some(claimed_refund)));
    db.expect_record_event_purchase_refund_retryable_failure()
        .withf(move |id, claim, message| {
            *id == refund_id && *claim == claim_id && message == "lookup unavailable"
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
    let worker = refund_worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    );
    let err = worker
        .process_next_refund()
        .await
        .expect_err("lookup failure to remain visible");

    // Check the original provider error is returned after claim release
    assert_eq!(err.to_string(), "lookup unavailable");
}

#[tokio::test]
async fn process_next_refund_records_retryable_failure_after_missing_pinned_refund() {
    // Setup a claimed refund pinned to a provider refund identifier
    let claim_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let mut claimed_refund = sample_refund(claim_id, purchase_id, refund_id);
    claimed_refund.provider_refund_id = Some("re_missing".to_string());

    // Setup claim release after the pinned provider refund cannot be found
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_refund()
        .times(1)
        .return_once(move |_| Ok(Some(claimed_refund)));
    db.expect_record_event_purchase_refund_retryable_failure()
        .withf(move |id, claim, message| {
            *id == refund_id && *claim == claim_id && message == "provider refund not found"
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
    let worker = refund_worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    );
    let err = worker
        .process_next_refund()
        .await
        .expect_err("missing pinned refund to remain retryable");

    // Check the reconciliation error remains explicit after claim release
    assert_eq!(err.to_string(), "provider refund not found");
}

#[tokio::test]
async fn process_next_refund_records_retryable_failure_after_notification_context_error() {
    // Setup a provider-complete claim that cannot load notification context
    let claim_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let mut claimed_refund = sample_refund(claim_id, purchase_id, refund_id);
    let community_id = claimed_refund.community_id;
    let event_id = claimed_refund.event_id;
    claimed_refund.provider_refund_id = Some("re_persisted".to_string());
    claimed_refund.provider_refunded_at = Some(Utc::now());

    // Fail notification context loading before finalization and release the claim
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_refund()
        .times(1)
        .return_once(move |_| Ok(Some(claimed_refund)));
    db.expect_finalize_event_purchase_refund().never();
    db.expect_get_event_summary_by_id()
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .times(1)
        .returning(|_, _| Err(anyhow::anyhow!("event unavailable")));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(SiteSettings::default()));
    db.expect_record_event_purchase_refund_retryable_failure()
        .withf(move |id, claim, message| {
            *id == refund_id
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
    let worker = refund_worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    );
    let err = worker
        .process_next_refund()
        .await
        .expect_err("notification context failure to remain retryable");

    // Check finalization did not run without its atomic notification payload
    assert_eq!(
        err.to_string(),
        "failed to build refund approval notification"
    );
}

#[tokio::test]
async fn process_next_refund_records_retryable_failure_after_success_persistence_error() {
    // Setup a newly claimed refund whose provider operation succeeds
    let claim_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let claimed_refund = sample_refund(claim_id, purchase_id, refund_id);

    // Fail provider-success persistence and release the claim for reconciliation
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_refund()
        .times(1)
        .return_once(move |_| Ok(Some(claimed_refund)));
    db.expect_record_event_purchase_refund_succeeded()
        .withf(move |_, _, _, expected_claim_id| *expected_claim_id == Some(claim_id))
        .times(1)
        .returning(|_, _, _, _| Err(anyhow::anyhow!("database unavailable")));
    db.expect_record_event_purchase_refund_retryable_failure()
        .withf(move |id, claim, message| {
            *id == refund_id
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
    let worker = refund_worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    );
    let err = worker
        .process_next_refund()
        .await
        .expect_err("provider-success persistence failure to remain visible");

    // Check the error is contextualized for retry reconciliation
    assert_eq!(
        err.to_string(),
        "failed to record successful provider refund"
    );
}

#[tokio::test]
async fn process_next_refund_records_retryable_failure_when_payment_reference_is_missing() {
    // Setup a malformed claimed refund without its provider payment reference
    let claim_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let mut claimed_refund = sample_refund(claim_id, purchase_id, refund_id);
    claimed_refund.provider_payment_reference = None;

    // Setup claim release for the local validation failure
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_refund()
        .times(1)
        .return_once(move |_| Ok(Some(claimed_refund)));
    db.expect_record_event_purchase_refund_retryable_failure()
        .withf(move |id, claim, message| {
            *id == refund_id
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
    let worker = refund_worker(
        Arc::new(db),
        MockNotificationsManager::new(),
        Some(provider),
    );
    let err = worker
        .process_next_refund()
        .await
        .expect_err("missing provider reference to fail before provider access");

    // Check the durable contract error remains explicit
    assert_eq!(err.to_string(), "provider payment reference is missing");
}

#[tokio::test]
async fn process_next_refund_without_provider_leaves_durable_work_unclaimed() {
    // Forbid claim mutation while no provider is configured
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_refund().never();

    // Attempt to process queued work without a provider
    let worker = refund_worker(Arc::new(db), MockNotificationsManager::new(), None);
    let processed = worker
        .process_next_refund()
        .await
        .expect("unconfigured worker to stay idle");

    // Check durable work remains queued
    assert!(!processed);
}

#[tokio::test]
async fn refund_recovery_worker_run_does_not_mutate_after_cancellation() {
    // Forbid stale-claim recovery after cancellation
    let mut db = MockDB::new();
    db.expect_requeue_stale_event_purchase_refund_claims().never();
    let cancellation_token = tokio_util::sync::CancellationToken::new();
    cancellation_token.cancel();
    let worker = RefundRecoveryWorker {
        cancellation_token,
        db: Arc::new(db),
    };

    // Run the already canceled recovery worker
    worker.run().await;
}

#[tokio::test]
async fn refund_recovery_worker_run_stops_pending_work_after_cancellation() {
    // Setup recovery work that remains pending after it starts
    let cancellation_token = tokio_util::sync::CancellationToken::new();
    let cancellation_token_for_task = cancellation_token.clone();
    let recovery_started = Arc::new(Notify::new());
    let recovery_started_for_task = recovery_started.clone();
    let recovery_task = tokio::spawn(async move {
        run_until_cancelled(&cancellation_token_for_task, async move {
            recovery_started_for_task.notify_one();
            pending::<()>().await;
        })
        .await
    });
    timeout(Duration::from_secs(1), recovery_started.notified())
        .await
        .expect("refund recovery to start");

    // Cancel and require the pending operation to be dropped promptly
    cancellation_token.cancel();
    let result = timeout(Duration::from_secs(1), recovery_task)
        .await
        .expect("refund recovery wait to stop promptly")
        .expect("refund recovery wait task to complete");
    assert!(result.is_none());
}

#[tokio::test]
async fn refund_worker_run_does_not_claim_after_cancellation() {
    // Forbid claims after cancellation begins
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_refund().never();
    let cancellation_token = tokio_util::sync::CancellationToken::new();
    cancellation_token.cancel();
    let mut provider = MockPaymentsProvider::new();
    provider.expect_provider().never();
    provider.expect_find_refund().never();
    provider.expect_refund_payment().never();
    let db = Arc::new(db) as DynDB;
    let worker = RefundWorker {
        cancellation_token,
        db: db.clone(),
        notification_composer: PaymentsNotificationComposer::new(
            db,
            Arc::new(MockNotificationsManager::new()),
            HttpServerConfig::default(),
        ),
        payments_provider: Some(Arc::new(provider)),
    };

    // Run the already canceled provider worker
    worker.run().await;
}

#[tokio::test]
async fn refund_worker_run_stops_during_provider_request_after_cancellation() {
    // Setup claimed work whose provider lookup remains in flight
    let claim_id = Uuid::new_v4();
    let purchase_id = Uuid::new_v4();
    let refund_id = Uuid::new_v4();
    let claimed_refund = sample_refund(claim_id, purchase_id, refund_id);
    let mut db = MockDB::new();
    db.expect_claim_event_purchase_refund()
        .times(1)
        .return_once(move |_| Ok(Some(claimed_refund)));
    db.expect_record_event_purchase_refund_retryable_failure().never();

    // Hold the provider request until graceful cancellation drops it
    let provider_started = Arc::new(Notify::new());
    let provider_started_for_lookup = provider_started.clone();
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    provider.expect_find_refund().times(1).return_once(move |_| {
        Box::pin(async move {
            provider_started_for_lookup.notify_one();
            pending().await
        })
    });
    provider.expect_refund_payment().never();

    // Start the worker and wait until its provider request is in flight
    let cancellation_token = tokio_util::sync::CancellationToken::new();
    let db = Arc::new(db) as DynDB;
    let worker = RefundWorker {
        cancellation_token: cancellation_token.clone(),
        db: db.clone(),
        notification_composer: PaymentsNotificationComposer::new(
            db,
            Arc::new(MockNotificationsManager::new()),
            HttpServerConfig::default(),
        ),
        payments_provider: Some(Arc::new(provider)),
    };
    let worker_task = tokio::spawn(async move {
        worker.run().await;
    });
    timeout(Duration::from_secs(1), provider_started.notified())
        .await
        .expect("provider request to start");

    // Cancel and require shutdown without waiting for the provider future
    cancellation_token.cancel();
    timeout(Duration::from_secs(1), worker_task)
        .await
        .expect("refund worker to stop promptly")
        .expect("refund worker task to complete");
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
        link: "/community/group/group/event/event".to_string(),
        theme: SiteSettings::default().theme,
    })
    .unwrap()
}

/// Creates a refund worker with test doubles and a fresh cancellation token.
fn refund_worker(
    db: Arc<MockDB>,
    notifications_manager: MockNotificationsManager,
    payments_provider: Option<MockPaymentsProvider>,
) -> RefundWorker {
    let db = db as DynDB;
    let payments_provider =
        payments_provider.map(|provider| Arc::new(provider) as DynPaymentsProvider);

    RefundWorker {
        cancellation_token: tokio_util::sync::CancellationToken::new(),
        db: db.clone(),
        notification_composer: PaymentsNotificationComposer::new(
            db,
            Arc::new(notifications_manager),
            HttpServerConfig::default(),
        ),
        payments_provider,
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
        venue_state: None,
        zip_code: None,
    }
}

/// Creates a claimed durable refund for worker lifecycle tests.
fn sample_refund(claim_id: Uuid, purchase_id: Uuid, refund_id: Uuid) -> ClaimedEventPurchaseRefund {
    ClaimedEventPurchaseRefund {
        community_id: Uuid::new_v4(),
        event_id: Uuid::new_v4(),
        refund: EventPurchaseRefund {
            amount_minor: 2_500,
            currency_code: "USD".to_string(),
            event_purchase_id: purchase_id,
            event_purchase_refund_id: refund_id,
            idempotency_key: format!("event-purchase-refund-{purchase_id}"),
            kind: EventPurchaseRefundKind::EventCancellation,
            payment_provider: PaymentProvider::Stripe,
            status: EventPurchaseRefundStatus::Processing,
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
