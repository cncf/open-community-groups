use std::sync::Arc;

use serde_json::json;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::{
        DynDB,
        mock::MockDB,
        payments::{
            CompletedEventPurchase, EventPurchaseRefund, EventPurchaseRefundKind,
            EventPurchaseRefundStatus, ReconcileEventPurchaseResult,
        },
    },
    services::{
        notifications::MockNotificationsManager,
        payments::{
            PaymentsWebhookEvent, RefundPaymentResult, RefundPaymentStatus,
            notification_composer::PaymentsNotificationComposer,
            provider::{CheckoutFinancialContext, MockPaymentsProvider},
        },
    },
    types::{
        notifications::NotificationKind,
        payments::{EventPurchaseStatus, EventPurchaseSummary, PaymentProvider},
        site::SiteSettings,
        tests::{sample_event_purchase_summary, sample_event_summary},
    },
};

use super::PaymentsWebhookReconciler;

#[tokio::test]
async fn test_handle_webhook_event_attaches_application_fee_to_direct_charge() {
    // Setup a platform fee created after its connected-account charge
    let mut db = MockDB::new();
    db.expect_attach_application_fee_to_event_purchase()
        .withf(|provider, account_id, charge_id, fee_id, amount| {
            *provider == PaymentProvider::Stripe
                && account_id == "acct_test_123"
                && charge_id == "ch_test_123"
                && fee_id == "fee_test_123"
                && *amount == 62
        })
        .times(1)
        .returning(|_, _, _, _, _| Ok(()));

    // Reconcile the asynchronously created platform object
    sample_reconciler(db, MockNotificationsManager::new(), webhook_provider())
        .handle_webhook_event(PaymentsWebhookEvent::ApplicationFeeCreated {
            amount_minor: 62,
            connected_account_id: "acct_test_123".to_string(),
            is_live: false,
            provider_application_fee_id: "fee_test_123".to_string(),
            provider_charge_id: "ch_test_123".to_string(),
        })
        .await
        .expect("application fee to attach");
}

#[tokio::test]
async fn test_handle_webhook_event_completes_checkout_and_enqueues_notification() {
    // Setup a checkout completion and its notification context
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    // Setup checkout reconciliation and notification context expectations
    let mut db = MockDB::new();
    db.expect_reconcile_event_purchase_for_checkout_session()
        .withf(|input| {
            input.payment_provider == PaymentProvider::Stripe
                && input.provider_object_account_id == "acct_test_123"
                && input.provider_session_id == "cs_test_123"
                && input.provider_payment_reference == "pi_test_123"
                && input.provider_charge_id == "ch_test_123"
                && input.provider_total_minor == 2_500
                && input.tax_amount_minor == 0
                && input.provider_application_fee_id.as_deref() == Some("fee_test_123")
        })
        .times(1)
        .returning(move |_| {
            Ok(ReconcileEventPurchaseResult::Completed(
                CompletedEventPurchase {
                    community_id,
                    event_id,
                    user_id,

                    transitioned: None,
                },
            ))
        });
    db.expect_get_event_summary_by_id()
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .times(1)
        .returning(move |_, _| Ok(sample_event_summary(event_id)));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(SiteSettings::default()));

    // Setup the attendee welcome notification expectation
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager
        .expect_enqueue()
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventWelcome)
                && notification.recipients == vec![user_id]
                && notification
                    .template_data
                    .as_ref()
                    .is_some_and(|data| data["event"]["event_id"] == json!(event_id))
        })
        .times(1)
        .returning(|_| Box::pin(async { Ok(()) }));

    // Guard the worker-owned provider refund methods
    let mut provider = webhook_provider();
    expect_checkout_financial_context(&mut provider, "cs_test_123");

    // Reconcile the completed checkout
    let reconciler = sample_reconciler(db, notifications_manager, provider);
    let result = reconciler
        .handle_webhook_event(PaymentsWebhookEvent::CheckoutCompleted {
            connected_account_id: "acct_test_123".to_string(),
            is_live: false,
            provider_session_id: "cs_test_123".to_string(),
        })
        .await;

    // Check local completion and best-effort notification succeed
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_handle_webhook_event_completes_checkout_before_application_fee_created() {
    // Setup checkout financial context whose direct-charge fee is still asynchronous
    let mut db = MockDB::new();
    db.expect_reconcile_event_purchase_for_checkout_session()
        .withf(|input| {
            input.payment_provider == PaymentProvider::Stripe
                && input.provider_object_account_id == "acct_test_123"
                && input.provider_session_id == "cs_async_fee"
                && input.provider_payment_reference == "pi_test_123"
                && input.provider_charge_id == "ch_test_123"
                && input.provider_total_minor == 2_500
                && input.tax_amount_minor == 0
                && input.provider_application_fee_id.is_none()
        })
        .times(1)
        .returning(|_| Ok(ReconcileEventPurchaseResult::Noop));
    let mut provider = webhook_provider();
    provider
        .expect_get_checkout_financial_context()
        .withf(|input| {
            input.connected_seller_id == "acct_test_123"
                && input.provider_session_id == "cs_async_fee"
        })
        .times(1)
        .returning(|_| {
            Box::pin(async {
                Ok(CheckoutFinancialContext {
                    provider_charge_id: "ch_test_123".to_string(),
                    provider_payment_reference: "pi_test_123".to_string(),
                    provider_total_minor: 2_500,
                    tax_amount_minor: 0,

                    provider_application_fee_id: None,
                })
            })
        });

    // Reconcile checkout without blocking fulfillment on fee creation timing
    sample_reconciler(db, MockNotificationsManager::new(), provider)
        .handle_webhook_event(PaymentsWebhookEvent::CheckoutCompleted {
            connected_account_id: "acct_test_123".to_string(),
            is_live: false,
            provider_session_id: "cs_async_fee".to_string(),
        })
        .await
        .expect("checkout without an application fee ID to reconcile");
}

#[tokio::test]
async fn test_handle_webhook_event_expires_checkout_session() {
    // Setup checkout expiration persistence
    let mut db = MockDB::new();
    db.expect_expire_event_purchase_for_checkout_session()
        .withf(|provider, account_id, session_id| {
            *provider == PaymentProvider::Stripe
                && account_id == "acct_test_123"
                && session_id == "cs_expired_123"
        })
        .times(1)
        .returning(|_, _, _| Ok(()));

    // Guard the worker-owned provider refund methods
    let provider = webhook_provider();

    // Reconcile the expired checkout
    let reconciler = sample_reconciler(db, MockNotificationsManager::new(), provider);
    let result = reconciler
        .handle_webhook_event(PaymentsWebhookEvent::CheckoutExpired {
            connected_account_id: "acct_test_123".to_string(),
            is_live: false,
            provider_session_id: "cs_expired_123".to_string(),
        })
        .await;

    // Check expiration is acknowledged
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_handle_webhook_event_persists_failed_refund_without_provider_call() {
    // Setup a provider failure for the current durable refund
    let purchase = sample_purchase();
    let refund = sample_refund();
    let refund_id = refund.event_purchase_refund_id;
    let idempotency_key = refund.idempotency_key.clone();

    // Setup purchase/refund loading and terminal failure persistence
    let mut db = MockDB::new();
    expect_refund_state(&mut db, purchase, refund);
    db.expect_record_event_purchase_refund_terminal_failed()
        .withf(
            move |id, key, provider_refund_id, message, expected_claim_id| {
                *id == refund_id
                    && key == &idempotency_key
                    && provider_refund_id == "re_test_123"
                    && message == "provider refund failed"
                    && expected_claim_id.is_none()
            },
        )
        .times(1)
        .returning(|_, _, _, _, _| Ok(()));

    // Guard the worker-owned provider refund methods
    let provider = webhook_provider();

    // Persist the verified provider failure
    let reconciler = sample_reconciler(db, MockNotificationsManager::new(), provider);
    let result = reconciler
        .handle_webhook_event(sample_refund_event(RefundPaymentStatus::Failed))
        .await;

    // Check the webhook never executes the provider operation itself
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_handle_webhook_event_persists_pending_refund_without_provider_call() {
    // Setup an in-progress provider update for the current durable refund
    let purchase = sample_purchase();
    let refund = sample_refund();
    let refund_id = refund.event_purchase_refund_id;
    let idempotency_key = refund.idempotency_key.clone();
    let persisted_refund = refund.clone();

    // Setup purchase/refund loading and pending-state persistence
    let mut db = MockDB::new();
    expect_refund_state(&mut db, purchase, refund);
    db.expect_record_event_purchase_refund_pending()
        .withf(move |id, key, provider_refund_id, expected_claim_id| {
            *id == refund_id
                && key == &idempotency_key
                && provider_refund_id == "re_test_123"
                && expected_claim_id.is_none()
        })
        .times(1)
        .return_once(move |_, _, _, _| Ok(persisted_refund));

    // Guard the worker-owned provider refund methods
    let provider = webhook_provider();

    // Persist the verified provider progress
    let reconciler = sample_reconciler(db, MockNotificationsManager::new(), provider);
    let result = reconciler
        .handle_webhook_event(sample_refund_event(RefundPaymentStatus::Pending))
        .await;

    // Check the webhook never polls or creates the refund
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_handle_webhook_event_persists_succeeded_refund_for_worker_finalization() {
    // Setup a provider success for the current durable refund
    let purchase = sample_purchase();
    let refund = sample_refund();
    let refund_id = refund.event_purchase_refund_id;
    let idempotency_key = refund.idempotency_key.clone();
    let mut persisted_refund = refund.clone();
    persisted_refund.status = EventPurchaseRefundStatus::ProviderSucceeded;

    // Setup purchase/refund loading and provider-success persistence
    let mut db = MockDB::new();
    expect_refund_state(&mut db, purchase, refund);
    db.expect_record_event_purchase_refund_succeeded()
        .withf(move |id, key, provider_refund_id, expected_claim_id| {
            *id == refund_id
                && key == &idempotency_key
                && provider_refund_id == "re_test_123"
                && expected_claim_id.is_none()
        })
        .times(1)
        .return_once(move |_, _, _, _| Ok(persisted_refund));
    db.expect_finalize_event_purchase_refund().never();

    // Guard the worker-owned provider refund methods
    let provider = webhook_provider();

    // Persist the verified provider success
    let reconciler = sample_reconciler(db, MockNotificationsManager::new(), provider);
    let result = reconciler
        .handle_webhook_event(sample_refund_event(RefundPaymentStatus::Succeeded))
        .await;

    // Check local finalization remains owned by the worker
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_handle_webhook_event_preserves_terminal_failure_on_late_pending_update() {
    // Setup a terminal refund followed by a delayed non-terminal update
    let purchase = sample_purchase();
    let mut refund = sample_refund();
    refund.status = EventPurchaseRefundStatus::ProviderFailed;
    refund.terminal_failure = true;

    // Setup durable state loading and forbid any downgrade
    let mut db = MockDB::new();
    expect_refund_state(&mut db, purchase, refund);
    db.expect_record_event_purchase_refund_pending().never();

    // Guard the worker-owned provider refund methods
    let provider = webhook_provider();

    // Reconcile the delayed pending update
    let reconciler = sample_reconciler(db, MockNotificationsManager::new(), provider);
    let result = reconciler
        .handle_webhook_event(sample_refund_event(RefundPaymentStatus::Pending))
        .await;

    // Check terminal state remains monotonic
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_handle_webhook_event_queues_unfulfillable_checkout_without_provider_call() {
    // Setup checkout reconciliation that durably queued a refund
    let mut db = MockDB::new();
    db.expect_reconcile_event_purchase_for_checkout_session()
        .withf(|input| {
            input.payment_provider == PaymentProvider::Stripe
                && input.provider_object_account_id == "acct_test_123"
                && input.provider_session_id == "cs_unfulfillable_123"
                && input.provider_payment_reference == "pi_test_123"
                && input.provider_charge_id == "ch_test_123"
                && input.provider_total_minor == 2_500
                && input.tax_amount_minor == 0
                && input.provider_application_fee_id.as_deref() == Some("fee_test_123")
        })
        .times(1)
        .returning(|_| Ok(ReconcileEventPurchaseResult::RefundQueued));

    // Guard notifications and worker-owned provider refund methods
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager.expect_enqueue().never();
    let mut provider = webhook_provider();
    expect_checkout_financial_context(&mut provider, "cs_unfulfillable_123");

    // Reconcile the completed but unfulfillable checkout
    let reconciler = sample_reconciler(db, notifications_manager, provider);
    let result = reconciler
        .handle_webhook_event(PaymentsWebhookEvent::CheckoutCompleted {
            connected_account_id: "acct_test_123".to_string(),
            is_live: false,
            provider_session_id: "cs_unfulfillable_123".to_string(),
        })
        .await;

    // Check durable queuing is sufficient for webhook acknowledgement
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_handle_webhook_event_refreshes_unpinned_success_before_persisting() {
    // Setup an unpinned success webhook whose current provider state is failed
    let purchase = sample_purchase();
    let purchase_id = purchase.event_purchase_id;
    let mut refund = sample_refund();
    refund.provider_refund_id = None;
    let refund_id = refund.event_purchase_refund_id;
    let idempotency_key = refund.idempotency_key.clone();

    // Setup purchase/refund loading and current failure persistence
    let mut db = MockDB::new();
    expect_refund_state(&mut db, purchase, refund);
    db.expect_record_event_purchase_refund_succeeded().never();
    db.expect_record_event_purchase_refund_terminal_failed()
        .withf(
            move |id, key, provider_refund_id, message, expected_claim_id| {
                *id == refund_id
                    && key == &idempotency_key
                    && provider_refund_id == "re_test_123"
                    && message == "provider refund failed"
                    && expected_claim_id.is_none()
            },
        )
        .times(1)
        .returning(|_, _, _, _, _| Ok(()));

    // Refresh the exact provider refund and forbid any new refund request
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_find_refund()
        .withf(move |input| {
            input.amount_minor == 2_500
                && input.provider_payment_reference == "pi_test_123"
                && input.provider_refund_id.as_deref() == Some("re_test_123")
                && input.purchase_id == purchase_id
        })
        .times(1)
        .return_once(|_| {
            Box::pin(async {
                Ok(Some(RefundPaymentResult {
                    provider_refund_id: "re_test_123".to_string(),
                    status: RefundPaymentStatus::Failed,
                }))
            })
        });
    provider.expect_refund_payment().never();
    provider.expect_provider().return_const(PaymentProvider::Stripe);

    // Reconcile the stale success webhook against current provider state
    let reconciler = sample_reconciler(db, MockNotificationsManager::new(), provider);
    let result = reconciler
        .handle_webhook_event(sample_refund_event(RefundPaymentStatus::Succeeded))
        .await;

    // Check the provider's current failure wins over the stale success event
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_handle_webhook_event_attaches_paid_invoice() {
    // Setup the invoice attachment with distinct provider values
    let purchase_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_attach_invoice_to_event_purchase()
        .withf(move |id, account_id, invoice_id, hosted_url, pdf_url| {
            *id == purchase_id
                && account_id == "acct_test_123"
                && invoice_id == "in_test_123"
                && hosted_url == "https://stripe.test/invoices/in_test_123"
                && pdf_url.as_deref() == Some("https://stripe.test/invoices/in_test_123.pdf")
        })
        .times(1)
        .returning(|_, _, _, _, _| Ok(()));

    // Reconcile the paid invoice
    sample_reconciler(db, MockNotificationsManager::new(), webhook_provider())
        .handle_webhook_event(PaymentsWebhookEvent::InvoicePaid {
            connected_account_id: "acct_test_123".to_string(),
            hosted_url: "https://stripe.test/invoices/in_test_123".to_string(),
            is_live: false,
            provider_invoice_id: "in_test_123".to_string(),
            purchase_id,
            pdf_url: Some("https://stripe.test/invoices/in_test_123.pdf".to_string()),
        })
        .await
        .expect("paid invoice to attach");
}

#[tokio::test]
async fn test_handle_webhook_event_preserves_succeeded_refund_on_late_pending_update() {
    // Setup a provider-succeeded refund followed by a delayed pending update
    let purchase = sample_purchase();
    let mut refund = sample_refund();
    refund.status = EventPurchaseRefundStatus::ProviderSucceeded;

    // Setup durable state loading and forbid any downgrade
    let mut db = MockDB::new();
    expect_refund_state(&mut db, purchase, refund);
    db.expect_record_event_purchase_refund_pending().never();

    // Reconcile the delayed pending update
    let reconciler = sample_reconciler(db, MockNotificationsManager::new(), webhook_provider());
    let result = reconciler
        .handle_webhook_event(sample_refund_event(RefundPaymentStatus::Pending))
        .await;

    // Check the completed provider outcome remains in place
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_handle_webhook_event_propagates_checkout_reconciliation_failure() {
    // Setup a local reconciliation failure after the provider lookup succeeds
    let mut db = MockDB::new();
    db.expect_reconcile_event_purchase_for_checkout_session()
        .times(1)
        .returning(|_| Err(anyhow::anyhow!("reconciliation unavailable")));

    // Guard notifications and worker-owned provider refund methods
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager.expect_enqueue().never();
    let mut provider = webhook_provider();
    expect_checkout_financial_context(&mut provider, "cs_test_123");

    // Reconcile the completed checkout
    let err = sample_reconciler(db, notifications_manager, provider)
        .handle_webhook_event(PaymentsWebhookEvent::CheckoutCompleted {
            connected_account_id: "acct_test_123".to_string(),
            is_live: false,
            provider_session_id: "cs_test_123".to_string(),
        })
        .await
        .expect_err("reconciliation failure to be retried by the provider");

    // Check the local failure is returned
    assert_eq!(err.to_string(), "reconciliation unavailable");
}

#[tokio::test]
async fn test_handle_webhook_event_rejects_mismatched_connected_account() {
    // Setup a purchase owned by another connected account
    let purchase = sample_purchase();
    let purchase_id = purchase.event_purchase_id;
    let mut db = MockDB::new();
    db.expect_get_event_purchase_summary()
        .withf(move |id| *id == purchase_id)
        .times(1)
        .return_once(move |_| Ok(purchase));
    db.expect_get_event_purchase_refund().never();

    // Reconcile a refund event signed for a different connected account
    let mut event = sample_refund_event(RefundPaymentStatus::Succeeded);
    if let PaymentsWebhookEvent::RefundUpdated {
        connected_account_id,
        ..
    } = &mut event
    {
        *connected_account_id = "acct_other".to_string();
    }
    let err = sample_reconciler(db, MockNotificationsManager::new(), webhook_provider())
        .handle_webhook_event(event)
        .await
        .expect_err("cross-account refund event to be rejected");

    // Check the account mismatch is reported before refund state is loaded
    assert_eq!(
        err.to_string(),
        "webhook connected account does not match purchase"
    );
}

#[tokio::test]
async fn test_handle_webhook_event_rejects_refund_for_purchase_not_awaiting_refund() {
    // Setup a completed purchase without a refund in progress
    let purchase = EventPurchaseSummary {
        status: EventPurchaseStatus::Completed,
        ..sample_purchase()
    };
    let mut db = MockDB::new();
    db.expect_get_event_purchase_summary()
        .times(1)
        .return_once(move |_| Ok(purchase));
    db.expect_get_event_purchase_refund().never();

    // Reconcile a refund event for the completed purchase
    let err = sample_reconciler(db, MockNotificationsManager::new(), webhook_provider())
        .handle_webhook_event(sample_refund_event(RefundPaymentStatus::Succeeded))
        .await
        .expect_err("refund event without a pending refund to be rejected");

    // Check the purchase state is reported
    assert_eq!(err.to_string(), "event purchase is not awaiting a refund");
}

#[test]
fn test_validate_refund_event_checks_financial_contract_and_current_attempt() {
    // Setup refund events that each change one field of the matching contract
    let unpinned = EventPurchaseRefund {
        provider_refund_id: None,
        ..sample_refund()
    };
    let wrong_durable_amount = EventPurchaseRefund {
        amount_minor: 100,
        ..sample_refund()
    };
    let cases = [
        (
            "matching contract",
            sample_refund(),
            2_500,
            "usd",
            "pi_test_123",
            "re_test_123",
            Ok(true),
        ),
        (
            "unpinned durable refund",
            unpinned,
            2_500,
            "usd",
            "pi_test_123",
            "re_test_123",
            Ok(true),
        ),
        (
            "different pinned refund",
            sample_refund(),
            2_500,
            "usd",
            "pi_test_123",
            "re_unrelated_123",
            Ok(false),
        ),
        (
            "durable amount mismatch",
            wrong_durable_amount,
            2_500,
            "usd",
            "pi_test_123",
            "re_test_123",
            Err("refund webhook amount does not match purchase"),
        ),
        (
            "partial refund amount",
            sample_refund(),
            100,
            "usd",
            "pi_test_123",
            "re_test_123",
            Err("refund webhook amount does not match purchase"),
        ),
        (
            "other currency",
            sample_refund(),
            2_500,
            "eur",
            "pi_test_123",
            "re_test_123",
            Err("refund webhook currency does not match purchase"),
        ),
        (
            "unrelated payment reference",
            sample_refund(),
            2_500,
            "usd",
            "pi_unrelated_123",
            "re_test_123",
            Err("refund webhook payment reference does not match purchase"),
        ),
    ];

    for (case, refund, amount_minor, currency_code, payment_reference, refund_id, expected) in cases
    {
        // Validate the event against the sample purchase
        let result = PaymentsWebhookReconciler::validate_refund_event(
            &sample_purchase(),
            &refund,
            PaymentProvider::Stripe,
            amount_minor,
            currency_code,
            payment_reference,
            refund_id,
        );

        // Check the current-attempt flag or the rejected field
        assert_eq!(
            result.map_err(|err| err.to_string()),
            expected.map_err(str::to_string),
            "{case}"
        );
    }
}

// Helpers.

/// Configures the authoritative provider lookup used by checkout webhooks.
fn expect_checkout_financial_context(
    provider: &mut MockPaymentsProvider,
    session_id: &'static str,
) {
    provider
        .expect_get_checkout_financial_context()
        .withf(move |input| {
            input.connected_seller_id == "acct_test_123" && input.provider_session_id == session_id
        })
        .times(1)
        .returning(|_| {
            Box::pin(async {
                Ok(CheckoutFinancialContext {
                    provider_application_fee_id: Some("fee_test_123".to_string()),
                    provider_charge_id: "ch_test_123".to_string(),
                    provider_payment_reference: "pi_test_123".to_string(),
                    provider_total_minor: 2_500,
                    tax_amount_minor: 0,
                })
            })
        });
}

/// Expects the purchase and durable refund loaded for a refund webhook.
fn expect_refund_state(
    db: &mut MockDB,
    purchase: EventPurchaseSummary,
    refund: EventPurchaseRefund,
) {
    let purchase_id = purchase.event_purchase_id;
    db.expect_get_event_purchase_summary()
        .withf(move |id| *id == purchase_id)
        .times(1)
        .return_once(move |_| Ok(purchase));
    db.expect_get_event_purchase_refund()
        .withf(move |id| *id == purchase_id)
        .times(1)
        .return_once(move |_| Ok(refund));
}

/// Creates a purchase summary matching the provider refund fixture.
fn sample_purchase() -> EventPurchaseSummary {
    EventPurchaseSummary {
        event_ticket_type_id: Uuid::from_u128(3),

        provider_object_account_id: Some("acct_test_123".to_string()),
        provider_payment_reference: Some("pi_test_123".to_string()),
        ..sample_event_purchase_summary(Uuid::from_u128(1), EventPurchaseStatus::RefundPending)
    }
}

/// Creates a webhook reconciler with the supplied test doubles.
fn sample_reconciler(
    db: MockDB,
    notifications_manager: MockNotificationsManager,
    provider: MockPaymentsProvider,
) -> PaymentsWebhookReconciler {
    let db = Arc::new(db) as DynDB;
    let notification_composer = PaymentsNotificationComposer::new(
        db.clone(),
        Arc::new(notifications_manager),
        HttpServerConfig::default(),
    );

    PaymentsWebhookReconciler::new(db, notification_composer, Arc::new(provider))
}

/// Creates a durable refund matching the provider webhook fixture.
fn sample_refund() -> EventPurchaseRefund {
    EventPurchaseRefund {
        amount_minor: 2_500,
        currency_code: "USD".to_string(),
        event_purchase_id: Uuid::from_u128(1),
        event_purchase_refund_id: Uuid::from_u128(2),
        idempotency_key: "event-purchase-refund-test".to_string(),
        kind: EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
        payment_job_id: Uuid::from_u128(4),
        payment_provider: PaymentProvider::Stripe,
        status: EventPurchaseRefundStatus::ProviderPending,
        terminal_failure: false,

        attempt_count: 0,
        claim_id: None,
        failure_message: None,
        finalized_at: None,
        provider_payment_reference: Some("pi_test_123".to_string()),
        provider_refund_id: Some("re_test_123".to_string()),
        provider_refunded_at: None,
    }
}

/// Creates a normalized provider refund event with the requested status.
fn sample_refund_event(status: RefundPaymentStatus) -> PaymentsWebhookEvent {
    PaymentsWebhookEvent::RefundUpdated {
        amount_minor: 2_500,
        connected_account_id: "acct_test_123".to_string(),
        currency_code: "usd".to_string(),
        is_live: false,
        provider_payment_reference: "pi_test_123".to_string(),
        provider_refund_id: "re_test_123".to_string(),
        purchase_id: Uuid::from_u128(1),
        status,
    }
}

/// Returns a Stripe provider mock for webhook-only reconciliation.
///
/// Refund lookup and creation belong to the payment job worker, so both are forbidden.
fn webhook_provider() -> MockPaymentsProvider {
    let mut provider = MockPaymentsProvider::new();
    provider.expect_provider().return_const(PaymentProvider::Stripe);
    provider.expect_find_refund().never();
    provider.expect_refund_payment().never();
    provider
}
