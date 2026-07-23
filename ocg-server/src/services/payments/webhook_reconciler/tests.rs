use std::sync::Arc;

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
        notifications::{MockNotificationsManager, NotificationKind},
        payments::{
            PaymentsWebhookEvent, RefundPaymentResult, RefundPaymentStatus,
            notification_composer::PaymentsNotificationComposer, provider::MockPaymentsProvider,
        },
    },
    types::{
        event::{EventKind, EventSummary},
        payments::{EventPurchaseStatus, EventPurchaseSummary, PaymentProvider},
        site::SiteSettings,
    },
};

use super::PaymentsWebhookReconciler;

#[tokio::test]
async fn handle_webhook_event_completes_checkout_and_enqueues_notification() {
    // Setup a checkout completion and its notification context
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);

    // Setup checkout reconciliation and notification context expectations
    let mut db = MockDB::new();
    db.expect_reconcile_event_purchase_for_checkout_session()
        .withf(|provider, session_id, payment_reference| {
            *provider == PaymentProvider::Stripe
                && session_id == "cs_test_123"
                && payment_reference.as_deref() == Some("pi_test_123")
        })
        .times(1)
        .returning(move |_, _, _| {
            Ok(ReconcileEventPurchaseResult::Completed(
                CompletedEventPurchase {
                    community_id,
                    event_id,
                    user_id,
                },
            ))
        });
    db.expect_get_event_summary_by_id()
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .times(1)
        .returning(move |_, _| Ok(event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(SiteSettings::default()));

    // Setup the attendee welcome notification expectation
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager
        .expect_enqueue()
        .withf(move |notification| {
            notification.attachments.len() == 1
                && matches!(notification.kind, NotificationKind::EventWelcome)
                && notification.recipients == vec![user_id]
        })
        .times(1)
        .returning(|_| Box::pin(async { Ok(()) }));

    // Guard the worker-owned provider refund methods
    let mut provider = MockPaymentsProvider::new();
    guard_provider_refund_calls(&mut provider);
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);

    // Reconcile the completed checkout
    let reconciler = sample_reconciler(db, notifications_manager, provider);
    let result = reconciler
        .handle_webhook_event(PaymentsWebhookEvent::CheckoutCompleted {
            provider_session_id: "cs_test_123".to_string(),
            provider_payment_reference: Some("pi_test_123".to_string()),
        })
        .await;

    // Check local completion and best-effort notification succeed
    assert!(result.is_ok());
}

#[tokio::test]
async fn handle_webhook_event_expires_checkout_session() {
    // Setup checkout expiration persistence
    let mut db = MockDB::new();
    db.expect_expire_event_purchase_for_checkout_session()
        .withf(|provider, session_id| {
            *provider == PaymentProvider::Stripe && session_id == "cs_expired_123"
        })
        .times(1)
        .returning(|_, _| Ok(()));

    // Guard the worker-owned provider refund methods
    let mut provider = MockPaymentsProvider::new();
    guard_provider_refund_calls(&mut provider);
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);

    // Reconcile the expired checkout
    let reconciler = sample_reconciler(db, MockNotificationsManager::new(), provider);
    let result = reconciler
        .handle_webhook_event(PaymentsWebhookEvent::CheckoutExpired {
            provider_session_id: "cs_expired_123".to_string(),
        })
        .await;

    // Check expiration is acknowledged
    assert!(result.is_ok());
}

#[tokio::test]
async fn handle_webhook_event_persists_failed_refund_without_provider_call() {
    // Setup a provider failure for the current durable refund
    let purchase = sample_purchase();
    let purchase_id = purchase.event_purchase_id;
    let refund = sample_refund();
    let refund_id = refund.event_purchase_refund_id;
    let idempotency_key = refund.idempotency_key.clone();

    // Setup purchase/refund loading and terminal failure persistence
    let mut db = MockDB::new();
    db.expect_get_event_purchase_summary()
        .withf(move |id| *id == purchase_id)
        .times(1)
        .return_once(move |_| Ok(purchase));
    db.expect_get_event_purchase_refund()
        .withf(move |id| *id == purchase_id)
        .times(1)
        .return_once(move |_| Ok(refund));
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
    let mut provider = MockPaymentsProvider::new();
    guard_provider_refund_calls(&mut provider);
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);

    // Persist the verified provider failure
    let reconciler = sample_reconciler(db, MockNotificationsManager::new(), provider);
    let result = reconciler
        .handle_webhook_event(sample_refund_event(RefundPaymentStatus::Failed))
        .await;

    // Check the webhook never executes the provider operation itself
    assert!(result.is_ok());
}

#[tokio::test]
async fn handle_webhook_event_persists_pending_refund_without_provider_call() {
    // Setup an in-progress provider update for the current durable refund
    let purchase = sample_purchase();
    let purchase_id = purchase.event_purchase_id;
    let refund = sample_refund();
    let refund_id = refund.event_purchase_refund_id;
    let idempotency_key = refund.idempotency_key.clone();
    let persisted_refund = refund.clone();

    // Setup purchase/refund loading and pending-state persistence
    let mut db = MockDB::new();
    db.expect_get_event_purchase_summary()
        .withf(move |id| *id == purchase_id)
        .times(1)
        .return_once(move |_| Ok(purchase));
    db.expect_get_event_purchase_refund()
        .withf(move |id| *id == purchase_id)
        .times(1)
        .return_once(move |_| Ok(refund));
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
    let mut provider = MockPaymentsProvider::new();
    guard_provider_refund_calls(&mut provider);
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);

    // Persist the verified provider progress
    let reconciler = sample_reconciler(db, MockNotificationsManager::new(), provider);
    let result = reconciler
        .handle_webhook_event(sample_refund_event(RefundPaymentStatus::Pending))
        .await;

    // Check the webhook never polls or creates the refund
    assert!(result.is_ok());
}

#[tokio::test]
async fn handle_webhook_event_persists_succeeded_refund_for_worker_finalization() {
    // Setup a provider success for the current durable refund
    let purchase = sample_purchase();
    let purchase_id = purchase.event_purchase_id;
    let refund = sample_refund();
    let refund_id = refund.event_purchase_refund_id;
    let idempotency_key = refund.idempotency_key.clone();
    let mut persisted_refund = refund.clone();
    persisted_refund.status = EventPurchaseRefundStatus::ProviderSucceeded;

    // Setup purchase/refund loading and provider-success persistence
    let mut db = MockDB::new();
    db.expect_get_event_purchase_summary()
        .withf(move |id| *id == purchase_id)
        .times(1)
        .return_once(move |_| Ok(purchase));
    db.expect_get_event_purchase_refund()
        .withf(move |id| *id == purchase_id)
        .times(1)
        .return_once(move |_| Ok(refund));
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
    let mut provider = MockPaymentsProvider::new();
    guard_provider_refund_calls(&mut provider);
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);

    // Persist the verified provider success
    let reconciler = sample_reconciler(db, MockNotificationsManager::new(), provider);
    let result = reconciler
        .handle_webhook_event(sample_refund_event(RefundPaymentStatus::Succeeded))
        .await;

    // Check local finalization remains owned by the worker
    assert!(result.is_ok());
}

#[tokio::test]
async fn handle_webhook_event_preserves_terminal_failure_on_late_pending_update() {
    // Setup a terminal refund followed by a delayed non-terminal update
    let purchase = sample_purchase();
    let purchase_id = purchase.event_purchase_id;
    let mut refund = sample_refund();
    refund.status = EventPurchaseRefundStatus::ProviderFailed;
    refund.terminal_failure = true;

    // Setup durable state loading and forbid any downgrade
    let mut db = MockDB::new();
    db.expect_get_event_purchase_summary()
        .withf(move |id| *id == purchase_id)
        .times(1)
        .return_once(move |_| Ok(purchase));
    db.expect_get_event_purchase_refund()
        .withf(move |id| *id == purchase_id)
        .times(1)
        .return_once(move |_| Ok(refund));
    db.expect_record_event_purchase_refund_pending().never();

    // Guard the worker-owned provider refund methods
    let mut provider = MockPaymentsProvider::new();
    guard_provider_refund_calls(&mut provider);
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);

    // Reconcile the delayed pending update
    let reconciler = sample_reconciler(db, MockNotificationsManager::new(), provider);
    let result = reconciler
        .handle_webhook_event(sample_refund_event(RefundPaymentStatus::Pending))
        .await;

    // Check terminal state remains monotonic
    assert!(result.is_ok());
}

#[tokio::test]
async fn handle_webhook_event_queues_unfulfillable_checkout_without_provider_call() {
    // Setup checkout reconciliation that durably queued a refund
    let mut db = MockDB::new();
    db.expect_reconcile_event_purchase_for_checkout_session()
        .withf(|provider, session_id, payment_reference| {
            *provider == PaymentProvider::Stripe
                && session_id == "cs_unfulfillable_123"
                && payment_reference.as_deref() == Some("pi_test_123")
        })
        .times(1)
        .returning(|_, _, _| Ok(ReconcileEventPurchaseResult::RefundQueued));

    // Guard notifications and worker-owned provider refund methods
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager.expect_enqueue().never();
    let mut provider = MockPaymentsProvider::new();
    guard_provider_refund_calls(&mut provider);
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);

    // Reconcile the completed but unfulfillable checkout
    let reconciler = sample_reconciler(db, notifications_manager, provider);
    let result = reconciler
        .handle_webhook_event(PaymentsWebhookEvent::CheckoutCompleted {
            provider_session_id: "cs_unfulfillable_123".to_string(),
            provider_payment_reference: Some("pi_test_123".to_string()),
        })
        .await;

    // Check durable queuing is sufficient for webhook acknowledgement
    assert!(result.is_ok());
}

#[tokio::test]
async fn handle_webhook_event_refreshes_unpinned_success_before_persisting() {
    // Setup an unpinned success webhook whose current provider state is failed
    let purchase = sample_purchase();
    let purchase_id = purchase.event_purchase_id;
    let mut refund = sample_refund();
    refund.provider_refund_id = None;
    let refund_id = refund.event_purchase_refund_id;
    let idempotency_key = refund.idempotency_key.clone();

    // Setup purchase/refund loading and current failure persistence
    let mut db = MockDB::new();
    db.expect_get_event_purchase_summary()
        .withf(move |id| *id == purchase_id)
        .times(1)
        .return_once(move |_| Ok(purchase));
    db.expect_get_event_purchase_refund()
        .withf(move |id| *id == purchase_id)
        .times(1)
        .return_once(move |_| Ok(refund));
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
    provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);

    // Reconcile the stale success webhook against current provider state
    let reconciler = sample_reconciler(db, MockNotificationsManager::new(), provider);
    let result = reconciler
        .handle_webhook_event(sample_refund_event(RefundPaymentStatus::Succeeded))
        .await;

    // Check the provider's current failure wins over the stale success event
    assert!(result.is_ok());
}

#[test]
fn validate_refund_event_accepts_matching_financial_contract() {
    let result = PaymentsWebhookReconciler::validate_refund_event(
        &sample_purchase(),
        &sample_refund(),
        PaymentProvider::Stripe,
        2_500,
        "usd",
        "pi_test_123",
        "re_test_123",
    );

    assert!(result.expect("matching refund event to validate"));
}

#[test]
fn validate_refund_event_ignores_different_pinned_refund() {
    let result = PaymentsWebhookReconciler::validate_refund_event(
        &sample_purchase(),
        &sample_refund(),
        PaymentProvider::Stripe,
        2_500,
        "usd",
        "pi_test_123",
        "re_unrelated_123",
    );

    assert!(!result.expect("financially matching refund event to validate"));
}

#[test]
fn validate_refund_event_rejects_durable_amount_mismatch() {
    let mut refund = sample_refund();
    refund.amount_minor = 100;

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

    assert_eq!(
        err.to_string(),
        "refund webhook amount does not match purchase"
    );
}

#[test]
fn validate_refund_event_rejects_mismatched_amount() {
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

    assert_eq!(
        err.to_string(),
        "refund webhook amount does not match purchase"
    );
}

#[test]
fn validate_refund_event_rejects_mismatched_currency() {
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

    assert_eq!(
        err.to_string(),
        "refund webhook currency does not match purchase"
    );
}

#[test]
fn validate_refund_event_rejects_mismatched_payment_reference() {
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

    assert_eq!(
        err.to_string(),
        "refund webhook payment reference does not match purchase"
    );
}

// Helpers.

/// Forbids provider refund calls in webhook-only reconciliation tests.
fn guard_provider_refund_calls(provider: &mut MockPaymentsProvider) {
    provider.expect_find_refund().never();
    provider.expect_refund_payment().never();
}

/// Creates an event summary for webhook notification tests.
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

/// Creates a purchase summary matching the provider refund fixture.
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
        currency_code: "usd".to_string(),
        provider_payment_reference: "pi_test_123".to_string(),
        provider_refund_id: "re_test_123".to_string(),
        purchase_id: Uuid::from_u128(1),
        status,
    }
}
