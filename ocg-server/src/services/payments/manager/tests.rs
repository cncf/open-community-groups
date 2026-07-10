use std::sync::Arc;

use axum::http::{HeaderMap, HeaderValue};
use mockall::Sequence;
use serde_json::to_value;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::{
        mock::MockDB,
        payments::{
            CompletedEventPurchase, CompletedEventRefund, EventPurchaseRefund,
            EventPurchaseRefundKind, EventPurchaseRefundStatus, ReconcileEventPurchaseResult,
        },
    },
    services::{
        notifications::{MockNotificationsManager, NotificationKind},
        payments::{
            CheckoutSession, MockPaymentsProvider, PaymentsWebhookEvent, RefundPaymentResult,
            RefundPaymentStatus,
        },
    },
    templates::notifications::EventRefundRequested,
    types::{
        event::{EventKind, EventSummary},
        payments::{
            EventPurchaseStatus, EventPurchaseSummary, GroupPaymentRecipient, PaymentProvider,
            PreparedEventCheckout,
        },
        site::SiteSettings,
    },
};

use super::{
    ApproveRefundRequestInput, DynPaymentsProvider, HandleWebhookError, PgPaymentsManager,
    RejectRefundRequestInput, RequestRefundInput,
};

#[tokio::test]
async fn approve_refund_request_approves_pending_refund_and_enqueues_notification() {
    // Setup identifiers and data structures
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let review_note = "Approved by organizer".to_string();
    let site_settings = SiteSettings::default();
    let target_user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_begin_event_refund_approval()
        .times(1)
        .withf(move |gid, eid, uid| *gid == group_id && *eid == event_id && *uid == target_user_id)
        .returning(move |_, _, _| {
            Ok(EventPurchaseSummary {
                amount_minor: 2_500,
                event_purchase_id,
                event_ticket_type_id,
                provider_payment_reference: Some("pi_test_123".to_string()),
                status: EventPurchaseStatus::RefundRequested,
                ticket_title: "General admission".to_string(),
                ..EventPurchaseSummary::default()
            })
        });
    db.expect_approve_event_refund_request()
        .times(1)
        .withf(move |actor_id, gid, eid, uid, refund_id, note| {
            *actor_id == actor_user_id
                && *gid == group_id
                && *eid == event_id
                && *uid == target_user_id
                && refund_id == "re_test_123"
                && note.as_deref() == Some(review_note.as_str())
        })
        .returning(move |_, _, _, _, _, _| {
            Ok(CompletedEventRefund {
                community_id,
                event_id,
                finalized_now: true,
                user_id: target_user_id,
            })
        });
    expect_event_purchase_refund_started(
        &mut db,
        event_purchase_id,
        event_purchase_refund_id,
        EventPurchaseRefundKind::RefundRequestApproval,
        None,
        true,
        EventPurchaseRefundStatus::ProviderPending,
    );
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    db.expect_record_event_purchase_refund_failed().never();
    expect_event_purchase_refund_succeeded(
        &mut db,
        event_purchase_id,
        event_purchase_refund_id,
        EventPurchaseRefundKind::RefundRequestApproval,
    );
    db.expect_revert_event_refund_approval().never();

    // Setup notifications manager mock
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager
        .expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventRefundApproved)
                && notification.recipients == vec![target_user_id]
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup payments provider mock
    let mut payments_provider = MockPaymentsProvider::new();
    expect_provider_refund_lookup_miss(&mut payments_provider, 1);
    payments_provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    expect_provider_refund_created(&mut payments_provider, event_purchase_id, 1);

    // Run the refund approval workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let result = manager
        .approve_refund_request(&ApproveRefundRequestInput {
            actor_user_id,
            community_id,
            event_id,
            group_id,
            user_id: target_user_id,

            review_note: Some("Approved by organizer".to_string()),
        })
        .await;

    // Check result matches expectations
    assert!(result.is_ok());
}

#[tokio::test]
async fn approve_refund_request_reverts_when_payment_reference_is_missing() {
    // Setup identifiers and data structures
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let target_user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_begin_event_refund_approval()
        .times(1)
        .withf(move |gid, eid, uid| *gid == group_id && *eid == event_id && *uid == target_user_id)
        .returning(move |_, _, _| {
            Ok(crate::types::payments::EventPurchaseSummary {
                amount_minor: 2_500,
                event_purchase_id,
                event_ticket_type_id,
                provider_payment_reference: None,
                status: EventPurchaseStatus::RefundRequested,
                ticket_title: "General admission".to_string(),
                ..crate::types::payments::EventPurchaseSummary::default()
            })
        });
    db.expect_approve_event_refund_request().never();
    db.expect_ensure_event_purchase_refund_started().never();
    db.expect_record_event_purchase_refund_failed().never();
    db.expect_record_event_purchase_refund_succeeded().never();
    db.expect_revert_event_refund_approval()
        .times(1)
        .withf(move |gid, eid, uid| *gid == group_id && *eid == event_id && *uid == target_user_id)
        .returning(|_, _, _| Ok(()));

    // Setup notifications manager and payments provider mocks
    let notifications_manager = MockNotificationsManager::new();
    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider.expect_find_refund().never();
    payments_provider.expect_refund_payment().never();

    // Run the refund approval workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let err = manager
        .approve_refund_request(&ApproveRefundRequestInput {
            actor_user_id,
            community_id,
            event_id,
            group_id,
            user_id: target_user_id,

            review_note: None,
        })
        .await
        .expect_err("refund approval to fail when the payment reference is missing");

    // Check the returned error
    assert_eq!(err.to_string(), "provider payment reference is missing");
}

#[tokio::test]
async fn approve_refund_request_returns_before_state_transition_when_payments_are_unconfigured() {
    // Setup identifiers and data structures
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let target_user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_begin_event_refund_approval().never();

    // Run the refund approval workflow without a configured payments provider
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), None);
    let err = manager
        .approve_refund_request(&ApproveRefundRequestInput {
            actor_user_id,
            community_id,
            event_id,
            group_id,
            user_id: target_user_id,

            review_note: None,
        })
        .await
        .expect_err("refund approval to fail when payments are not configured");

    // Check the returned error
    assert_eq!(err.to_string(), "payments are not configured");
}

#[tokio::test]
async fn approve_refund_request_fails_closed_when_provider_lookup_fails() {
    // Setup identifiers and data structures
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let target_user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_begin_event_refund_approval()
        .times(1)
        .returning(move |_, _, _| {
            Ok(EventPurchaseSummary {
                amount_minor: 2_500,
                event_purchase_id,
                event_ticket_type_id,
                provider_payment_reference: Some("pi_test_123".to_string()),
                status: EventPurchaseStatus::RefundRequested,
                ticket_title: "General admission".to_string(),
                ..EventPurchaseSummary::default()
            })
        });
    db.expect_approve_event_refund_request().never();
    db.expect_ensure_event_purchase_refund_started()
        .times(1)
        .returning(move |_, _, _| {
            Ok(sample_event_purchase_refund(
                event_purchase_id,
                event_purchase_refund_id,
                EventPurchaseRefundKind::RefundRequestApproval,
                None,
                true,
                EventPurchaseRefundStatus::ProviderPending,
            ))
        });
    db.expect_record_event_purchase_refund_failed().never();
    db.expect_record_event_purchase_refund_pending().never();
    db.expect_record_event_purchase_refund_succeeded().never();
    db.expect_record_event_purchase_refund_terminal_failed().never();
    db.expect_revert_event_refund_approval().never();

    // Setup notifications manager and payments provider mocks
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager.expect_enqueue().never();

    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider
        .expect_find_refund()
        .times(1)
        .returning(|_| Box::pin(async { Err(anyhow::anyhow!("refund lookup failed")) }));
    payments_provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    payments_provider.expect_refund_payment().never();

    // Run the refund approval workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let err = manager
        .approve_refund_request(&ApproveRefundRequestInput {
            actor_user_id,
            community_id,
            event_id,
            group_id,
            user_id: target_user_id,

            review_note: None,
        })
        .await
        .expect_err("provider lookup failure to stop refund creation");

    // Check the returned error
    assert_eq!(err.to_string(), "refund lookup failed");
}

#[tokio::test]
async fn approve_refund_request_keeps_approval_state_when_provider_refund_fails() {
    // Setup identifiers and data structures
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let target_user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_begin_event_refund_approval()
        .times(1)
        .withf(move |gid, eid, uid| *gid == group_id && *eid == event_id && *uid == target_user_id)
        .returning(move |_, _, _| {
            Ok(EventPurchaseSummary {
                amount_minor: 2_500,
                event_purchase_id,
                event_ticket_type_id,
                provider_payment_reference: Some("pi_test_123".to_string()),
                status: EventPurchaseStatus::RefundRequested,
                ticket_title: "General admission".to_string(),
                ..EventPurchaseSummary::default()
            })
        });
    db.expect_approve_event_refund_request().never();
    db.expect_ensure_event_purchase_refund_started()
        .times(1)
        .withf(move |purchase_id, provider, kind| {
            *purchase_id == event_purchase_id
                && *provider == PaymentProvider::Stripe
                && *kind == EventPurchaseRefundKind::RefundRequestApproval
        })
        .returning(move |_, _, _| {
            Ok(sample_event_purchase_refund(
                event_purchase_id,
                event_purchase_refund_id,
                EventPurchaseRefundKind::RefundRequestApproval,
                None,
                true,
                EventPurchaseRefundStatus::ProviderPending,
            ))
        });
    db.expect_record_event_purchase_refund_failed()
        .times(1)
        .withf(move |refund_id, failure_message| {
            *refund_id == event_purchase_refund_id && failure_message == "provider refund failed"
        })
        .returning(|_, _| Ok(()));
    db.expect_record_event_purchase_refund_succeeded().never();
    db.expect_revert_event_refund_approval().never();

    // Setup notifications manager and payments provider mocks
    let notifications_manager = MockNotificationsManager::new();
    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider
        .expect_find_refund()
        .times(1)
        .returning(|_| Box::pin(async { Ok(None) }));
    payments_provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    payments_provider
        .expect_refund_payment()
        .times(1)
        .withf(move |input| {
            input.amount_minor == 2_500
                && input.idempotency_key == format!("event-purchase-refund-{event_purchase_id}")
                && input.provider_payment_reference == "pi_test_123"
                && input.purchase_id == event_purchase_id
        })
        .returning(|_| Box::pin(async move { Err(anyhow::anyhow!("provider refund failed")) }));

    // Run the refund approval workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let err = manager
        .approve_refund_request(&ApproveRefundRequestInput {
            actor_user_id,
            community_id,
            event_id,
            group_id,
            user_id: target_user_id,

            review_note: None,
        })
        .await
        .expect_err("refund approval to fail when the provider refund fails");

    // Check the returned error
    assert_eq!(err.to_string(), "provider refund failed");
}

#[tokio::test]
async fn approve_refund_request_uses_rotated_idempotency_key_after_terminal_failure() {
    // Setup identifiers and data structures
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let idempotency_key = format!("event-purchase-refund-{event_purchase_id}-retry");
    let site_settings = SiteSettings::default();
    let target_user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_begin_event_refund_approval()
        .times(1)
        .returning(move |_, _, _| {
            Ok(EventPurchaseSummary {
                amount_minor: 2_500,
                event_purchase_id,
                event_ticket_type_id,
                provider_payment_reference: Some("pi_test_123".to_string()),
                status: EventPurchaseStatus::RefundRequested,
                ticket_title: "General admission".to_string(),
                ..EventPurchaseSummary::default()
            })
        });
    db.expect_approve_event_refund_request()
        .times(1)
        .withf(move |_, _, _, _, provider_refund_id, _| provider_refund_id == "re_retry_123")
        .returning(move |_, _, _, _, _, _| {
            Ok(CompletedEventRefund {
                community_id,
                event_id,
                finalized_now: true,
                user_id: target_user_id,
            })
        });
    expect_event_purchase_refund_started_with(
        &mut db,
        EventPurchaseRefundStartedExpectation {
            event_purchase_id,
            event_purchase_refund_id,
            idempotency_key: idempotency_key.clone(),
            kind: EventPurchaseRefundKind::RefundRequestApproval,
            started_now: false,
            status: EventPurchaseRefundStatus::ProviderFailed,

            provider_refund_id: None,
        },
    );
    db.expect_get_event_summary_by_id()
        .times(1)
        .returning(move |_, _| Ok(event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    db.expect_record_event_purchase_refund_failed().never();
    db.expect_record_event_purchase_refund_pending().never();
    expect_event_purchase_refund_succeeded_with_provider_id(
        &mut db,
        event_purchase_id,
        event_purchase_refund_id,
        EventPurchaseRefundKind::RefundRequestApproval,
        "re_retry_123",
    );
    db.expect_record_event_purchase_refund_terminal_failed().never();
    db.expect_revert_event_refund_approval().never();

    // Setup notifications manager and payments provider mocks
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager
        .expect_enqueue()
        .times(1)
        .returning(|_| Box::pin(async { Ok(()) }));

    let mut payments_provider = MockPaymentsProvider::new();
    expect_provider_refund_lookup_miss(&mut payments_provider, 1);
    payments_provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    expect_provider_refund_created_with_idempotency_key(
        &mut payments_provider,
        event_purchase_id,
        &idempotency_key,
        "re_retry_123",
        RefundPaymentStatus::Succeeded,
        1,
    );

    // Run the refund approval workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let result = manager
        .approve_refund_request(&ApproveRefundRequestInput {
            actor_user_id,
            community_id,
            event_id,
            group_id,
            user_id: target_user_id,

            review_note: None,
        })
        .await;

    // Check result matches expectations
    assert!(result.is_ok());
}

#[tokio::test]
async fn approve_refund_request_rotates_attempt_when_provider_refund_terminally_fails() {
    // Setup identifiers and data structures
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let target_user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_begin_event_refund_approval()
        .times(1)
        .returning(move |_, _, _| {
            Ok(EventPurchaseSummary {
                amount_minor: 2_500,
                event_purchase_id,
                event_ticket_type_id,
                provider_payment_reference: Some("pi_test_123".to_string()),
                status: EventPurchaseStatus::RefundRequested,
                ticket_title: "General admission".to_string(),
                ..EventPurchaseSummary::default()
            })
        });
    db.expect_approve_event_refund_request().never();
    db.expect_ensure_event_purchase_refund_started()
        .times(1)
        .returning(move |_, _, _| {
            Ok(sample_event_purchase_refund(
                event_purchase_id,
                event_purchase_refund_id,
                EventPurchaseRefundKind::RefundRequestApproval,
                None,
                true,
                EventPurchaseRefundStatus::ProviderPending,
            ))
        });
    db.expect_record_event_purchase_refund_failed().never();
    db.expect_record_event_purchase_refund_pending().never();
    db.expect_record_event_purchase_refund_succeeded().never();
    db.expect_record_event_purchase_refund_terminal_failed()
        .times(1)
        .withf(
            move |refund_id, expected_idempotency_key, provider_refund_id, failure_message| {
                *refund_id == event_purchase_refund_id
                    && expected_idempotency_key
                        == &format!("event-purchase-refund-{event_purchase_id}")
                    && provider_refund_id == "re_failed_123"
                    && failure_message == "provider refund failed"
            },
        )
        .returning(|_, _, _, _| Ok(()));
    db.expect_revert_event_refund_approval().never();

    // Setup notifications manager and payments provider mocks
    let notifications_manager = MockNotificationsManager::new();
    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider
        .expect_find_refund()
        .times(1)
        .returning(|_| Box::pin(async { Ok(None) }));
    payments_provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    payments_provider.expect_refund_payment().times(1).returning(|_| {
        Box::pin(async move {
            Ok(RefundPaymentResult {
                provider_refund_id: "re_failed_123".to_string(),
                status: RefundPaymentStatus::Failed,
            })
        })
    });

    // Run the refund approval workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let err = manager
        .approve_refund_request(&ApproveRefundRequestInput {
            actor_user_id,
            community_id,
            event_id,
            group_id,
            user_id: target_user_id,

            review_note: None,
        })
        .await
        .expect_err("terminal provider refund failure to stop finalization");

    // Check the returned error
    assert_eq!(err.to_string(), "provider refund failed");
}

#[tokio::test]
async fn approve_refund_request_records_pending_provider_refund_without_finalizing() {
    // Setup identifiers and data structures
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let target_user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_begin_event_refund_approval()
        .times(1)
        .returning(move |_, _, _| {
            Ok(EventPurchaseSummary {
                amount_minor: 2_500,
                event_purchase_id,
                event_ticket_type_id,
                provider_payment_reference: Some("pi_test_123".to_string()),
                status: EventPurchaseStatus::RefundRequested,
                ticket_title: "General admission".to_string(),
                ..EventPurchaseSummary::default()
            })
        });
    db.expect_approve_event_refund_request().never();
    db.expect_ensure_event_purchase_refund_started()
        .times(1)
        .returning(move |_, _, _| {
            Ok(sample_event_purchase_refund(
                event_purchase_id,
                event_purchase_refund_id,
                EventPurchaseRefundKind::RefundRequestApproval,
                None,
                true,
                EventPurchaseRefundStatus::ProviderPending,
            ))
        });
    db.expect_record_event_purchase_refund_failed().never();
    db.expect_record_event_purchase_refund_pending()
        .times(1)
        .withf(
            move |refund_id, expected_idempotency_key, provider_refund_id| {
                *refund_id == event_purchase_refund_id
                    && expected_idempotency_key
                        == &format!("event-purchase-refund-{event_purchase_id}")
                    && provider_refund_id == "re_pending_123"
            },
        )
        .returning(move |_, _, _| {
            Ok(sample_event_purchase_refund(
                event_purchase_id,
                event_purchase_refund_id,
                EventPurchaseRefundKind::RefundRequestApproval,
                Some("re_pending_123".to_string()),
                false,
                EventPurchaseRefundStatus::ProviderPending,
            ))
        });
    db.expect_record_event_purchase_refund_succeeded().never();
    db.expect_revert_event_refund_approval().never();

    // Setup notifications manager and payments provider mocks
    let notifications_manager = MockNotificationsManager::new();
    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider
        .expect_find_refund()
        .times(1)
        .returning(|_| Box::pin(async { Ok(None) }));
    payments_provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    payments_provider.expect_refund_payment().times(1).returning(|_| {
        Box::pin(async move {
            Ok(RefundPaymentResult {
                provider_refund_id: "re_pending_123".to_string(),
                status: RefundPaymentStatus::Pending,
            })
        })
    });

    // Run the refund approval workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let err = manager
        .approve_refund_request(&ApproveRefundRequestInput {
            actor_user_id,
            community_id,
            event_id,
            group_id,
            user_id: target_user_id,

            review_note: None,
        })
        .await
        .expect_err("pending provider refund to stop local finalization");

    // Check the returned error
    assert_eq!(err.to_string(), "provider refund is not complete yet");
}

#[tokio::test]
async fn approve_refund_request_ignores_stale_pending_result_after_attempt_rotation() {
    // Setup identifiers and data structures
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let target_user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_begin_event_refund_approval()
        .times(1)
        .returning(move |_, _, _| {
            Ok(EventPurchaseSummary {
                amount_minor: 2_500,
                event_purchase_id,
                event_ticket_type_id,
                provider_payment_reference: Some("pi_test_123".to_string()),
                status: EventPurchaseStatus::RefundRequested,
                ticket_title: "General admission".to_string(),
                ..EventPurchaseSummary::default()
            })
        });
    db.expect_approve_event_refund_request().never();
    expect_event_purchase_refund_started(
        &mut db,
        event_purchase_id,
        event_purchase_refund_id,
        EventPurchaseRefundKind::RefundRequestApproval,
        None,
        true,
        EventPurchaseRefundStatus::ProviderPending,
    );
    db.expect_record_event_purchase_refund_failed().never();
    db.expect_record_event_purchase_refund_pending()
        .times(1)
        .withf(
            move |refund_id, expected_idempotency_key, provider_refund_id| {
                *refund_id == event_purchase_refund_id
                    && expected_idempotency_key
                        == &format!("event-purchase-refund-{event_purchase_id}")
                    && provider_refund_id == "re_pending_123"
            },
        )
        .returning(move |_, _, _| {
            Ok(sample_event_purchase_refund_with_idempotency_key(
                event_purchase_id,
                event_purchase_refund_id,
                EventPurchaseRefundKind::RefundRequestApproval,
                None,
                false,
                EventPurchaseRefundStatus::ProviderFailed,
                format!("event-purchase-refund-{event_purchase_id}-retry"),
            ))
        });
    db.expect_record_event_purchase_refund_succeeded().never();
    db.expect_record_event_purchase_refund_terminal_failed().never();
    db.expect_revert_event_refund_approval().never();

    // Setup notifications manager and payments provider mocks
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager.expect_enqueue().never();

    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider
        .expect_find_refund()
        .times(1)
        .returning(|_| Box::pin(async { Ok(None) }));
    payments_provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    payments_provider.expect_refund_payment().times(1).returning(|_| {
        Box::pin(async move {
            Ok(RefundPaymentResult {
                provider_refund_id: "re_pending_123".to_string(),
                status: RefundPaymentStatus::Pending,
            })
        })
    });

    // Run the refund approval workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let err = manager
        .approve_refund_request(&ApproveRefundRequestInput {
            actor_user_id,
            community_id,
            event_id,
            group_id,
            user_id: target_user_id,

            review_note: None,
        })
        .await
        .expect_err("stale pending result to leave the terminal state unchanged");

    // Check the returned error
    assert_eq!(err.to_string(), "provider refund is not complete yet");
}

#[tokio::test]
async fn approve_refund_request_accepts_concurrently_finalized_pending_result() {
    // Setup identifiers and data structures
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let target_user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_begin_event_refund_approval()
        .times(1)
        .returning(move |_, _, _| {
            Ok(EventPurchaseSummary {
                amount_minor: 2_500,
                event_purchase_id,
                event_ticket_type_id,
                provider_payment_reference: Some("pi_test_123".to_string()),
                status: EventPurchaseStatus::RefundRequested,
                ticket_title: "General admission".to_string(),
                ..EventPurchaseSummary::default()
            })
        });
    db.expect_approve_event_refund_request()
        .times(1)
        .withf(move |_, _, _, _, provider_refund_id, _| provider_refund_id == "re_pending_123")
        .returning(move |_, _, _, _, _, _| {
            Ok(CompletedEventRefund {
                community_id,
                event_id,
                finalized_now: false,
                user_id: target_user_id,
            })
        });
    expect_event_purchase_refund_started(
        &mut db,
        event_purchase_id,
        event_purchase_refund_id,
        EventPurchaseRefundKind::RefundRequestApproval,
        None,
        true,
        EventPurchaseRefundStatus::ProviderPending,
    );
    db.expect_record_event_purchase_refund_failed().never();
    db.expect_record_event_purchase_refund_pending()
        .times(1)
        .returning(move |_, _, _| {
            Ok(sample_event_purchase_refund(
                event_purchase_id,
                event_purchase_refund_id,
                EventPurchaseRefundKind::RefundRequestApproval,
                Some("re_pending_123".to_string()),
                false,
                EventPurchaseRefundStatus::Finalized,
            ))
        });
    db.expect_record_event_purchase_refund_succeeded().never();
    db.expect_record_event_purchase_refund_terminal_failed().never();
    db.expect_revert_event_refund_approval().never();

    // Setup notifications manager and payments provider mocks
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager.expect_enqueue().never();

    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider
        .expect_find_refund()
        .times(1)
        .returning(|_| Box::pin(async { Ok(None) }));
    payments_provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    payments_provider.expect_refund_payment().times(1).returning(|_| {
        Box::pin(async move {
            Ok(RefundPaymentResult {
                provider_refund_id: "re_pending_123".to_string(),
                status: RefundPaymentStatus::Pending,
            })
        })
    });

    // Run the refund approval workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let result = manager
        .approve_refund_request(&ApproveRefundRequestInput {
            actor_user_id,
            community_id,
            event_id,
            group_id,
            user_id: target_user_id,

            review_note: None,
        })
        .await;

    // Check result matches expectations
    assert!(result.is_ok());
}

#[tokio::test]
async fn approve_refund_request_polls_pending_provider_refund_on_retry() {
    // Setup identifiers and data structures
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let site_settings = SiteSettings::default();
    let target_user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_begin_event_refund_approval()
        .times(1)
        .returning(move |_, _, _| {
            Ok(EventPurchaseSummary {
                amount_minor: 2_500,
                event_purchase_id,
                event_ticket_type_id,
                provider_payment_reference: Some("pi_test_123".to_string()),
                status: EventPurchaseStatus::RefundRequested,
                ticket_title: "General admission".to_string(),
                ..EventPurchaseSummary::default()
            })
        });
    db.expect_approve_event_refund_request()
        .times(1)
        .withf(move |_, _, _, _, provider_refund_id, _| provider_refund_id == "re_pending_123")
        .returning(move |_, _, _, _, _, _| {
            Ok(CompletedEventRefund {
                community_id,
                event_id,
                finalized_now: true,
                user_id: target_user_id,
            })
        });
    expect_event_purchase_refund_started(
        &mut db,
        event_purchase_id,
        event_purchase_refund_id,
        EventPurchaseRefundKind::RefundRequestApproval,
        Some("re_pending_123"),
        false,
        EventPurchaseRefundStatus::ProviderPending,
    );
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    db.expect_record_event_purchase_refund_failed().never();
    db.expect_record_event_purchase_refund_pending().never();
    expect_event_purchase_refund_succeeded_with_provider_id(
        &mut db,
        event_purchase_id,
        event_purchase_refund_id,
        EventPurchaseRefundKind::RefundRequestApproval,
        "re_pending_123",
    );
    db.expect_revert_event_refund_approval().never();

    // Setup notifications manager and payments provider mocks
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager
        .expect_enqueue()
        .times(1)
        .returning(|_| Box::pin(async { Ok(()) }));

    let mut payments_provider = MockPaymentsProvider::new();
    expect_provider_refund_lookup_hit(
        &mut payments_provider,
        event_purchase_id,
        "re_pending_123",
        RefundPaymentStatus::Succeeded,
    );
    payments_provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    payments_provider.expect_refund_payment().never();

    // Run the refund approval workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let result = manager
        .approve_refund_request(&ApproveRefundRequestInput {
            actor_user_id,
            community_id,
            event_id,
            group_id,
            user_id: target_user_id,

            review_note: None,
        })
        .await;

    // Check result matches expectations
    assert!(result.is_ok());
}

#[tokio::test]
async fn approve_refund_request_keeps_state_when_finalization_fails_after_provider_refund() {
    // Setup identifiers and data structures
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let target_user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_begin_event_refund_approval()
        .times(1)
        .returning(move |_, _, _| {
            Ok(EventPurchaseSummary {
                amount_minor: 2_500,
                event_purchase_id,
                event_ticket_type_id,
                provider_payment_reference: Some("pi_test_123".to_string()),
                status: EventPurchaseStatus::RefundRequested,
                ticket_title: "General admission".to_string(),
                ..EventPurchaseSummary::default()
            })
        });
    db.expect_approve_event_refund_request()
        .times(1)
        .returning(|_, _, _, _, _, _| Err(anyhow::anyhow!("approval finalization failed")));
    db.expect_ensure_event_purchase_refund_started()
        .times(1)
        .returning(move |_, _, _| {
            Ok(sample_event_purchase_refund(
                event_purchase_id,
                event_purchase_refund_id,
                EventPurchaseRefundKind::RefundRequestApproval,
                None,
                true,
                EventPurchaseRefundStatus::ProviderPending,
            ))
        });
    db.expect_get_event_summary_by_id().never();
    db.expect_get_site_settings().never();
    db.expect_record_event_purchase_refund_failed().never();
    db.expect_record_event_purchase_refund_succeeded()
        .times(1)
        .returning(move |_, _| {
            Ok(sample_event_purchase_refund(
                event_purchase_id,
                event_purchase_refund_id,
                EventPurchaseRefundKind::RefundRequestApproval,
                Some("re_test_123".to_string()),
                false,
                EventPurchaseRefundStatus::ProviderSucceeded,
            ))
        });
    db.expect_revert_event_refund_approval().never();

    // Setup notifications manager and payments provider mocks
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager.expect_enqueue().never();

    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider
        .expect_find_refund()
        .times(1)
        .returning(|_| Box::pin(async { Ok(None) }));
    payments_provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    payments_provider.expect_refund_payment().times(1).returning(|_| {
        Box::pin(async move {
            Ok(RefundPaymentResult {
                provider_refund_id: "re_test_123".to_string(),
                status: RefundPaymentStatus::Succeeded,
            })
        })
    });

    // Run the refund approval workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let err = manager
        .approve_refund_request(&ApproveRefundRequestInput {
            actor_user_id,
            community_id,
            event_id,
            group_id,
            user_id: target_user_id,

            review_note: None,
        })
        .await
        .expect_err("approval finalization to fail");

    // Check the returned error
    assert_eq!(err.to_string(), "approval finalization failed");
}

#[tokio::test]
async fn approve_refund_request_reuses_recorded_provider_refund() {
    // Setup identifiers and data structures
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let site_settings = SiteSettings::default();
    let target_user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_begin_event_refund_approval()
        .times(1)
        .returning(move |_, _, _| {
            Ok(EventPurchaseSummary {
                amount_minor: 2_500,
                event_purchase_id,
                event_ticket_type_id,
                provider_payment_reference: Some("pi_test_123".to_string()),
                status: EventPurchaseStatus::RefundRequested,
                ticket_title: "General admission".to_string(),
                ..EventPurchaseSummary::default()
            })
        });
    db.expect_approve_event_refund_request()
        .times(1)
        .withf(move |_, _, _, _, provider_refund_id, _| provider_refund_id == "re_test_123")
        .returning(move |_, _, _, _, _, _| {
            Ok(CompletedEventRefund {
                community_id,
                event_id,
                finalized_now: true,
                user_id: target_user_id,
            })
        });
    db.expect_ensure_event_purchase_refund_started()
        .times(1)
        .returning(move |_, _, _| {
            Ok(sample_event_purchase_refund(
                event_purchase_id,
                event_purchase_refund_id,
                EventPurchaseRefundKind::RefundRequestApproval,
                Some("re_test_123".to_string()),
                false,
                EventPurchaseRefundStatus::ProviderSucceeded,
            ))
        });
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    db.expect_record_event_purchase_refund_failed().never();
    db.expect_record_event_purchase_refund_succeeded().never();
    db.expect_revert_event_refund_approval().never();

    // Setup notifications manager and payments provider mocks
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager
        .expect_enqueue()
        .times(1)
        .returning(|_| Box::pin(async { Ok(()) }));

    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider.expect_find_refund().never();
    payments_provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    payments_provider.expect_refund_payment().never();

    // Run the refund approval workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let result = manager
        .approve_refund_request(&ApproveRefundRequestInput {
            actor_user_id,
            community_id,
            event_id,
            group_id,
            user_id: target_user_id,

            review_note: None,
        })
        .await;

    // Check result matches expectations
    assert!(result.is_ok());
}

#[tokio::test]
async fn complete_free_checkout_records_purchase_and_enqueues_notification() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let site_settings = SiteSettings::default();
    let user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_complete_free_event_purchase()
        .times(1)
        .withf(move |purchase_id| *purchase_id == event_purchase_id)
        .returning(move |_| {
            Ok(CompletedEventPurchase {
                community_id,
                event_id,
                user_id,
            })
        });
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));

    // Setup notifications manager mock
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager
        .expect_enqueue()
        .times(1)
        .withf(move |notification| {
            notification.attachments.len() == 1
                && matches!(notification.kind, NotificationKind::EventWelcome)
                && notification.recipients == vec![user_id]
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Run the checkout completion workflow
    let manager = sample_payments_manager(db, notifications_manager, None);
    let result = manager
        .complete_free_checkout(community_id, event_id, event_purchase_id, user_id)
        .await;

    // Check result matches expectations
    assert!(result.is_ok());
}

#[tokio::test]
async fn get_or_create_checkout_redirect_url_creates_session_and_persists_it() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let recipient = GroupPaymentRecipient {
        provider: PaymentProvider::Stripe,
        recipient_id: "acct_test_123".to_string(),
    };
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_attach_checkout_session_to_event_purchase()
        .times(1)
        .withf(move |purchase_id, provider, checkout_session| {
            *purchase_id == event_purchase_id
                && *provider == PaymentProvider::Stripe
                && checkout_session
                    == &CheckoutSession {
                        provider_session_id: "cs_test_123".to_string(),
                        redirect_url: "https://example.test/checkout".to_string(),
                    }
        })
        .returning(|_, _, _| Ok(()));
    db.expect_get_event_purchase_summary()
        .times(1)
        .withf(move |purchase_id| *purchase_id == event_purchase_id)
        .returning(move |_| {
            Ok(sample_event_purchase_summary(
                event_purchase_id,
                event_ticket_type_id,
                Some("https://example.test/checkout".to_string()),
                Some("SPRING".to_string()),
            ))
        });

    // Setup payments provider mock
    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider
        .expect_create_checkout_session()
        .times(1)
        .withf(move |input| {
            input.amount_minor == 2_500
                && input.base_url.is_empty()
                && input.community_name == "community"
                && input.currency_code == "usd"
                && input.discount_code.as_deref() == Some("SPRING")
                && input.event_id == event_id
                && input.event_slug == "event"
                && input.group_slug == "group"
                && input.group_slug_pretty.as_deref() == Some("pretty-group")
                && input.purchase_id == event_purchase_id
                && input.recipient
                    == GroupPaymentRecipient {
                        provider: PaymentProvider::Stripe,
                        recipient_id: "acct_test_123".to_string(),
                    }
                && input.ticket_title == "General admission"
                && input.user_id == user_id
        })
        .returning(|_| {
            Box::pin(async move {
                Ok(CheckoutSession {
                    provider_session_id: "cs_test_123".to_string(),
                    redirect_url: "https://example.test/checkout".to_string(),
                })
            })
        });
    payments_provider
        .expect_provider()
        .times(2)
        .return_const(PaymentProvider::Stripe);

    // Prepare checkout data with a pretty group slug
    let mut prepared_checkout = sample_prepared_event_checkout(
        event_id,
        event_purchase_id,
        event_ticket_type_id,
        None,
        Some("SPRING".to_string()),
        recipient,
    );
    prepared_checkout.group_slug_pretty = Some("pretty-group".to_string());

    // Run the checkout session workflow
    let manager =
        sample_payments_manager(db, MockNotificationsManager::new(), Some(payments_provider));
    let redirect_url = manager
        .get_or_create_checkout_redirect_url(&prepared_checkout, user_id)
        .await
        .expect("checkout session to be created");

    // Check result matches expectations
    assert_eq!(redirect_url, "https://example.test/checkout");
}

#[tokio::test]
async fn get_or_create_checkout_redirect_url_returns_canonical_url_after_racing_attach() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let recipient = GroupPaymentRecipient {
        provider: PaymentProvider::Stripe,
        recipient_id: "acct_test_123".to_string(),
    };
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_attach_checkout_session_to_event_purchase()
        .times(1)
        .withf(move |purchase_id, provider, checkout_session| {
            *purchase_id == event_purchase_id
                && *provider == PaymentProvider::Stripe
                && checkout_session
                    == &CheckoutSession {
                        provider_session_id: "cs_test_racing".to_string(),
                        redirect_url: "https://example.test/checkout/racing".to_string(),
                    }
        })
        .returning(|_, _, _| Ok(()));
    db.expect_get_event_purchase_summary()
        .times(1)
        .withf(move |purchase_id| *purchase_id == event_purchase_id)
        .returning(move |_| {
            Ok(sample_event_purchase_summary(
                event_purchase_id,
                event_ticket_type_id,
                Some("https://example.test/checkout/canonical".to_string()),
                None,
            ))
        });

    // Setup payments provider mock
    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider
        .expect_create_checkout_session()
        .times(1)
        .returning(|_| {
            Box::pin(async move {
                Ok(CheckoutSession {
                    provider_session_id: "cs_test_racing".to_string(),
                    redirect_url: "https://example.test/checkout/racing".to_string(),
                })
            })
        });
    payments_provider
        .expect_provider()
        .times(2)
        .return_const(PaymentProvider::Stripe);

    // Run the checkout session workflow
    let manager =
        sample_payments_manager(db, MockNotificationsManager::new(), Some(payments_provider));
    let redirect_url = manager
        .get_or_create_checkout_redirect_url(
            &sample_prepared_event_checkout(
                event_id,
                event_purchase_id,
                event_ticket_type_id,
                None,
                None,
                recipient,
            ),
            user_id,
        )
        .await
        .expect("canonical checkout URL to be returned");

    // Check result matches expectations
    assert_eq!(redirect_url, "https://example.test/checkout/canonical");
}

#[tokio::test]
async fn get_or_create_checkout_redirect_url_returns_error_when_checkout_url_is_missing_after_creation()
 {
    // Setup identifiers and data structures
    let event_purchase_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let recipient = GroupPaymentRecipient {
        provider: PaymentProvider::Stripe,
        recipient_id: "acct_test_123".to_string(),
    };

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_attach_checkout_session_to_event_purchase()
        .times(1)
        .returning(|_, _, _| Ok(()));
    db.expect_get_event_purchase_summary()
        .times(1)
        .withf(move |purchase_id| *purchase_id == event_purchase_id)
        .returning(move |_| {
            Ok(sample_event_purchase_summary(
                event_purchase_id,
                event_ticket_type_id,
                None,
                None,
            ))
        });

    // Setup payments provider mock
    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider
        .expect_create_checkout_session()
        .times(1)
        .returning(|_| {
            Box::pin(async move {
                Ok(CheckoutSession {
                    provider_session_id: "cs_test_123".to_string(),
                    redirect_url: "https://example.test/checkout".to_string(),
                })
            })
        });
    payments_provider
        .expect_provider()
        .times(2)
        .return_const(PaymentProvider::Stripe);

    // Run the checkout session workflow
    let manager =
        sample_payments_manager(db, MockNotificationsManager::new(), Some(payments_provider));
    let err = manager
        .get_or_create_checkout_redirect_url(
            &sample_prepared_event_checkout(
                Uuid::new_v4(),
                event_purchase_id,
                event_ticket_type_id,
                None,
                None,
                recipient,
            ),
            Uuid::new_v4(),
        )
        .await
        .expect_err("checkout session creation to fail when the canonical URL is missing");

    // Check the returned error
    assert_eq!(
        err.to_string(),
        "provider checkout URL is missing after checkout creation"
    );
}

#[tokio::test]
async fn get_or_create_checkout_redirect_url_returns_error_when_payments_are_unconfigured() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_purchase_summary().never();

    // Run the checkout session workflow without a configured payments provider
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), None);
    let err = manager
        .get_or_create_checkout_redirect_url(
            &sample_prepared_event_checkout(
                Uuid::new_v4(),
                Uuid::new_v4(),
                Uuid::new_v4(),
                None,
                None,
                GroupPaymentRecipient {
                    provider: PaymentProvider::Stripe,
                    recipient_id: "acct_test_123".to_string(),
                },
            ),
            Uuid::new_v4(),
        )
        .await
        .expect_err("checkout session creation to fail when payments are not configured");

    // Check the returned error
    assert_eq!(err.to_string(), "payments are not configured");
}

#[tokio::test]
async fn get_or_create_checkout_redirect_url_returns_existing_url_without_hitting_dependencies() {
    // Setup identifiers and data structures
    let existing_url = "https://example.test/checkout".to_string();
    let prepared_checkout = PreparedEventCheckout {
        purchase: EventPurchaseSummary {
            provider_checkout_url: Some(existing_url.clone()),
            ..sample_event_purchase_summary(Uuid::new_v4(), Uuid::new_v4(), None, None)
        },
        ..sample_prepared_event_checkout(
            Uuid::new_v4(),
            Uuid::new_v4(),
            Uuid::new_v4(),
            None,
            None,
            GroupPaymentRecipient {
                provider: PaymentProvider::Stripe,
                recipient_id: "acct_test_123".to_string(),
            },
        )
    };

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_purchase_summary().never();

    // Run the checkout session workflow
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), None);
    let redirect_url = manager
        .get_or_create_checkout_redirect_url(&prepared_checkout, Uuid::new_v4())
        .await
        .expect("existing checkout URL to be reused");

    // Check result matches expectations
    assert_eq!(redirect_url, existing_url);
}

#[tokio::test]
async fn handle_webhook_completes_checkout_and_enqueues_welcome_notification() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let site_settings = SiteSettings::default();
    let user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    db.expect_reconcile_event_purchase_for_checkout_session()
        .times(1)
        .withf(|provider, session_id, provider_payment_reference| {
            *provider == PaymentProvider::Stripe
                && session_id == "cs_test_123"
                && provider_payment_reference == &Some("pi_test_123".to_string())
        })
        .returning(move |_, _, _| {
            Ok(ReconcileEventPurchaseResult::Completed(
                CompletedEventPurchase {
                    community_id,
                    event_id,
                    user_id,
                },
            ))
        });

    // Setup notifications manager mock
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager
        .expect_enqueue()
        .times(1)
        .withf(move |notification| {
            notification.attachments.len() == 1
                && matches!(notification.kind, NotificationKind::EventWelcome)
                && notification.recipients == vec![user_id]
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup payments provider mock
    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    payments_provider
        .expect_verify_and_parse_webhook()
        .times(1)
        .withf(|headers, body| has_test_signature_header(headers) && body == "payload")
        .returning(|_, _| {
            Ok(PaymentsWebhookEvent::CheckoutCompleted {
                provider_session_id: "cs_test_123".to_string(),

                provider_payment_reference: Some("pi_test_123".to_string()),
            })
        });

    // Run the webhook workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let headers = sample_webhook_headers();
    let result = manager.handle_webhook(&headers, "payload").await;

    // Check result matches expectations
    assert!(result.is_ok());
}

#[tokio::test]
async fn handle_webhook_expires_checkout_session() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_summary_by_id().never();
    db.expect_get_site_settings().never();
    db.expect_expire_event_purchase_for_checkout_session()
        .times(1)
        .withf(|provider, session_id| {
            *provider == PaymentProvider::Stripe && session_id == "cs_test_123"
        })
        .returning(|_, _| Ok(()));

    // Setup payments provider mock
    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    payments_provider
        .expect_verify_and_parse_webhook()
        .times(1)
        .withf(|headers, body| has_test_signature_header(headers) && body == "payload")
        .returning(|_, _| {
            Ok(PaymentsWebhookEvent::CheckoutExpired {
                provider_session_id: "cs_test_123".to_string(),
            })
        });

    // Run the webhook workflow
    let manager =
        sample_payments_manager(db, MockNotificationsManager::new(), Some(payments_provider));
    let headers = sample_webhook_headers();
    let result = manager.handle_webhook(&headers, "payload").await;

    // Check result matches expectations
    assert!(result.is_ok());
}

#[tokio::test]
async fn handle_webhook_ignores_noop_checkout_completion() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_summary_by_id().never();
    db.expect_get_site_settings().never();
    db.expect_reconcile_event_purchase_for_checkout_session()
        .times(1)
        .withf(|provider, session_id, provider_payment_reference| {
            *provider == PaymentProvider::Stripe
                && session_id == "cs_test_123"
                && provider_payment_reference == &Some("pi_test_123".to_string())
        })
        .returning(|_, _, _| Ok(ReconcileEventPurchaseResult::Noop));

    // Setup notifications manager mock
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager.expect_enqueue().never();

    // Setup payments provider mock
    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    payments_provider
        .expect_verify_and_parse_webhook()
        .times(1)
        .withf(|headers, body| has_test_signature_header(headers) && body == "payload")
        .returning(|_, _| {
            Ok(PaymentsWebhookEvent::CheckoutCompleted {
                provider_session_id: "cs_test_123".to_string(),

                provider_payment_reference: Some("pi_test_123".to_string()),
            })
        });

    // Run the webhook workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let headers = sample_webhook_headers();
    let result = manager.handle_webhook(&headers, "payload").await;

    // Check result matches expectations
    assert!(result.is_ok());
}

#[tokio::test]
async fn handle_webhook_refunds_completed_checkout_that_is_no_longer_finalizable() {
    // Setup identifiers and data structures
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_event_purchase_refund_started(
        &mut db,
        event_purchase_id,
        event_purchase_refund_id,
        EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
        None,
        true,
        EventPurchaseRefundStatus::ProviderPending,
    );
    db.expect_get_event_summary_by_id().never();
    db.expect_get_site_settings().never();
    db.expect_record_event_purchase_refund_failed().never();
    expect_event_purchase_refund_succeeded(
        &mut db,
        event_purchase_id,
        event_purchase_refund_id,
        EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
    );
    db.expect_record_automatic_refund_for_event_purchase()
        .times(1)
        .withf(move |purchase_id, provider_refund_id| {
            *purchase_id == event_purchase_id && provider_refund_id == "re_test_123"
        })
        .returning(|_, _| Ok(()));
    db.expect_reconcile_event_purchase_for_checkout_session()
        .times(1)
        .withf(|provider, session_id, provider_payment_reference| {
            *provider == PaymentProvider::Stripe
                && session_id == "cs_test_123"
                && provider_payment_reference == &Some("pi_test_123".to_string())
        })
        .returning(move |_, _, _| {
            Ok(ReconcileEventPurchaseResult::RefundRequired(
                crate::db::payments::RefundRequiredEventPurchase {
                    amount_minor: 2_500,
                    event_purchase_id,
                    provider_payment_reference: "pi_test_123".to_string(),
                },
            ))
        });

    // Setup notifications manager mock
    let notifications_manager = MockNotificationsManager::new();

    // Setup payments provider mock
    let mut payments_provider = MockPaymentsProvider::new();
    expect_provider_refund_lookup_miss(&mut payments_provider, 1);
    payments_provider
        .expect_provider()
        .times(2)
        .return_const(PaymentProvider::Stripe);
    expect_provider_refund_created(&mut payments_provider, event_purchase_id, 1);
    payments_provider
        .expect_verify_and_parse_webhook()
        .times(1)
        .withf(|headers, body| has_test_signature_header(headers) && body == "payload")
        .returning(|_, _| {
            Ok(PaymentsWebhookEvent::CheckoutCompleted {
                provider_session_id: "cs_test_123".to_string(),

                provider_payment_reference: Some("pi_test_123".to_string()),
            })
        });

    // Run the webhook workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let headers = sample_webhook_headers();
    let result = manager.handle_webhook(&headers, "payload").await;

    // Check result matches expectations
    assert!(result.is_ok());
}

#[tokio::test]
async fn handle_webhook_fails_closed_when_automatic_refund_lookup_fails() {
    // Setup identifiers and data structures
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_event_purchase_refund_started(
        &mut db,
        event_purchase_id,
        event_purchase_refund_id,
        EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
        None,
        true,
        EventPurchaseRefundStatus::ProviderPending,
    );
    db.expect_record_event_purchase_refund_failed().never();
    db.expect_record_event_purchase_refund_pending().never();
    db.expect_record_event_purchase_refund_succeeded().never();
    db.expect_record_event_purchase_refund_terminal_failed().never();
    db.expect_record_automatic_refund_for_event_purchase().never();
    db.expect_reconcile_event_purchase_for_checkout_session()
        .times(1)
        .returning(move |_, _, _| {
            Ok(ReconcileEventPurchaseResult::RefundRequired(
                crate::db::payments::RefundRequiredEventPurchase {
                    amount_minor: 2_500,
                    event_purchase_id,
                    provider_payment_reference: "pi_test_123".to_string(),
                },
            ))
        });

    // Setup notifications manager and payments provider mocks
    let notifications_manager = MockNotificationsManager::new();
    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider
        .expect_find_refund()
        .times(1)
        .returning(|_| Box::pin(async { Err(anyhow::anyhow!("refund lookup failed")) }));
    payments_provider
        .expect_provider()
        .times(2)
        .return_const(PaymentProvider::Stripe);
    payments_provider.expect_refund_payment().never();
    payments_provider
        .expect_verify_and_parse_webhook()
        .times(1)
        .returning(|_, _| {
            Ok(PaymentsWebhookEvent::CheckoutCompleted {
                provider_session_id: "cs_test_123".to_string(),

                provider_payment_reference: Some("pi_test_123".to_string()),
            })
        });

    // Run the webhook workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let headers = sample_webhook_headers();
    let err = manager
        .handle_webhook(&headers, "payload")
        .await
        .expect_err("provider lookup failure to stop automatic refund creation");

    // Check the returned error
    match err {
        HandleWebhookError::Unexpected(err) => {
            assert_eq!(err.to_string(), "refund lookup failed");
        }
        unexpected => panic!("unexpected error: {unexpected:?}"),
    }
}

#[tokio::test]
async fn handle_webhook_uses_rotated_idempotency_key_after_terminal_failure() {
    // Setup identifiers and data structures
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();
    let idempotency_key = format!("event-purchase-refund-{event_purchase_id}-retry");

    // Setup database mock
    let mut db = MockDB::new();
    expect_event_purchase_refund_started_with(
        &mut db,
        EventPurchaseRefundStartedExpectation {
            event_purchase_id,
            event_purchase_refund_id,
            idempotency_key: idempotency_key.clone(),
            kind: EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
            started_now: false,
            status: EventPurchaseRefundStatus::ProviderFailed,

            provider_refund_id: None,
        },
    );
    db.expect_get_event_summary_by_id().never();
    db.expect_get_site_settings().never();
    db.expect_record_event_purchase_refund_failed().never();
    db.expect_record_event_purchase_refund_pending().never();
    expect_event_purchase_refund_succeeded_with_provider_id(
        &mut db,
        event_purchase_id,
        event_purchase_refund_id,
        EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
        "re_retry_123",
    );
    db.expect_record_event_purchase_refund_terminal_failed().never();
    db.expect_record_automatic_refund_for_event_purchase()
        .times(1)
        .withf(move |purchase_id, provider_refund_id| {
            *purchase_id == event_purchase_id && provider_refund_id == "re_retry_123"
        })
        .returning(|_, _| Ok(()));
    db.expect_reconcile_event_purchase_for_checkout_session()
        .times(1)
        .returning(move |_, _, _| {
            Ok(ReconcileEventPurchaseResult::RefundRequired(
                crate::db::payments::RefundRequiredEventPurchase {
                    amount_minor: 2_500,
                    event_purchase_id,
                    provider_payment_reference: "pi_test_123".to_string(),
                },
            ))
        });

    // Setup notifications manager and payments provider mocks
    let notifications_manager = MockNotificationsManager::new();
    let mut payments_provider = MockPaymentsProvider::new();
    expect_provider_refund_lookup_miss(&mut payments_provider, 1);
    payments_provider
        .expect_provider()
        .times(2)
        .return_const(PaymentProvider::Stripe);
    expect_provider_refund_created_with_idempotency_key(
        &mut payments_provider,
        event_purchase_id,
        &idempotency_key,
        "re_retry_123",
        RefundPaymentStatus::Succeeded,
        1,
    );
    payments_provider
        .expect_verify_and_parse_webhook()
        .times(1)
        .returning(|_, _| {
            Ok(PaymentsWebhookEvent::CheckoutCompleted {
                provider_session_id: "cs_test_123".to_string(),

                provider_payment_reference: Some("pi_test_123".to_string()),
            })
        });

    // Run the webhook workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let headers = sample_webhook_headers();
    let result = manager.handle_webhook(&headers, "payload").await;

    // Check result matches expectations
    assert!(result.is_ok());
}

#[tokio::test]
async fn handle_webhook_awaits_pending_automatic_refund_webhook() {
    // Setup identifiers and data structures
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_ensure_event_purchase_refund_started()
        .times(1)
        .returning(move |_, _, _| {
            Ok(sample_event_purchase_refund(
                event_purchase_id,
                event_purchase_refund_id,
                EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
                None,
                true,
                EventPurchaseRefundStatus::ProviderPending,
            ))
        });
    db.expect_get_event_summary_by_id().never();
    db.expect_get_site_settings().never();
    db.expect_record_event_purchase_refund_failed().never();
    db.expect_record_event_purchase_refund_pending()
        .times(1)
        .withf(
            move |refund_id, expected_idempotency_key, provider_refund_id| {
                *refund_id == event_purchase_refund_id
                    && expected_idempotency_key
                        == &format!("event-purchase-refund-{event_purchase_id}")
                    && provider_refund_id == "re_pending_123"
            },
        )
        .returning(move |_, _, _| {
            Ok(sample_event_purchase_refund(
                event_purchase_id,
                event_purchase_refund_id,
                EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
                Some("re_pending_123".to_string()),
                false,
                EventPurchaseRefundStatus::ProviderPending,
            ))
        });
    db.expect_record_event_purchase_refund_succeeded().never();
    db.expect_record_automatic_refund_for_event_purchase().never();
    db.expect_reconcile_event_purchase_for_checkout_session()
        .times(1)
        .returning(move |_, _, _| {
            Ok(ReconcileEventPurchaseResult::RefundRequired(
                crate::db::payments::RefundRequiredEventPurchase {
                    amount_minor: 2_500,
                    event_purchase_id,
                    provider_payment_reference: "pi_test_123".to_string(),
                },
            ))
        });

    // Setup notifications manager mock
    let notifications_manager = MockNotificationsManager::new();

    // Setup payments provider mock
    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider
        .expect_find_refund()
        .times(1)
        .returning(|_| Box::pin(async { Ok(None) }));
    payments_provider
        .expect_provider()
        .times(2)
        .return_const(PaymentProvider::Stripe);
    payments_provider.expect_refund_payment().times(1).returning(|_| {
        Box::pin(async move {
            Ok(RefundPaymentResult {
                provider_refund_id: "re_pending_123".to_string(),
                status: RefundPaymentStatus::Pending,
            })
        })
    });
    payments_provider
        .expect_verify_and_parse_webhook()
        .times(1)
        .returning(|_, _| {
            Ok(PaymentsWebhookEvent::CheckoutCompleted {
                provider_session_id: "cs_test_123".to_string(),

                provider_payment_reference: Some("pi_test_123".to_string()),
            })
        });

    // Run the webhook workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let headers = sample_webhook_headers();
    let result = manager.handle_webhook(&headers, "payload").await;

    // Check result matches expectations
    assert!(result.is_ok());
}

#[tokio::test]
async fn handle_webhook_finalizes_pending_automatic_refund_after_provider_update() {
    // Setup identifiers and data structures
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_purchase_summary()
        .times(1)
        .withf(move |purchase_id| *purchase_id == event_purchase_id)
        .returning(move |_| {
            Ok(EventPurchaseSummary {
                amount_minor: 2_500,
                event_purchase_id,
                event_ticket_type_id,
                provider_payment_reference: Some("pi_test_123".to_string()),
                status: EventPurchaseStatus::RefundPending,
                ticket_title: "General admission".to_string(),
                ..EventPurchaseSummary::default()
            })
        });
    expect_event_purchase_refund_started(
        &mut db,
        event_purchase_id,
        event_purchase_refund_id,
        EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
        Some("re_pending_123"),
        false,
        EventPurchaseRefundStatus::ProviderPending,
    );
    db.expect_record_event_purchase_refund_failed().never();
    db.expect_record_event_purchase_refund_pending().never();
    expect_event_purchase_refund_succeeded_with_provider_id(
        &mut db,
        event_purchase_id,
        event_purchase_refund_id,
        EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
        "re_pending_123",
    );
    db.expect_record_event_purchase_refund_terminal_failed().never();
    db.expect_record_automatic_refund_for_event_purchase()
        .times(1)
        .withf(move |purchase_id, provider_refund_id| {
            *purchase_id == event_purchase_id && provider_refund_id == "re_pending_123"
        })
        .returning(|_, _| Ok(()));

    // Setup notifications manager and payments provider mocks
    let notifications_manager = MockNotificationsManager::new();
    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider.expect_find_refund().never();
    payments_provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    payments_provider.expect_refund_payment().never();
    payments_provider
        .expect_verify_and_parse_webhook()
        .times(1)
        .returning(move |_, _| {
            Ok(PaymentsWebhookEvent::RefundUpdated {
                purchase_id: event_purchase_id,
                provider_refund_id: "re_pending_123".to_string(),
                status: RefundPaymentStatus::Succeeded,
            })
        });

    // Run the refund update workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let headers = sample_webhook_headers();
    let result = manager.handle_webhook(&headers, "payload").await;

    // Check result matches expectations
    assert!(result.is_ok());
}

#[tokio::test]
async fn handle_webhook_records_refund_request_success_without_finalizing() {
    // Setup identifiers and data structures
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_purchase_summary()
        .times(1)
        .withf(move |purchase_id| *purchase_id == event_purchase_id)
        .returning(move |_| {
            Ok(EventPurchaseSummary {
                amount_minor: 2_500,
                event_purchase_id,
                event_ticket_type_id,
                provider_payment_reference: Some("pi_test_123".to_string()),
                status: EventPurchaseStatus::RefundRequested,
                ticket_title: "General admission".to_string(),
                ..EventPurchaseSummary::default()
            })
        });
    expect_event_purchase_refund_started(
        &mut db,
        event_purchase_id,
        event_purchase_refund_id,
        EventPurchaseRefundKind::RefundRequestApproval,
        Some("re_pending_123"),
        false,
        EventPurchaseRefundStatus::ProviderPending,
    );
    db.expect_record_event_purchase_refund_failed().never();
    db.expect_record_event_purchase_refund_pending().never();
    expect_event_purchase_refund_succeeded_with_provider_id(
        &mut db,
        event_purchase_id,
        event_purchase_refund_id,
        EventPurchaseRefundKind::RefundRequestApproval,
        "re_pending_123",
    );
    db.expect_record_event_purchase_refund_terminal_failed().never();
    db.expect_record_automatic_refund_for_event_purchase().never();

    // Setup notifications manager and payments provider mocks
    let notifications_manager = MockNotificationsManager::new();
    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider.expect_find_refund().never();
    payments_provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    payments_provider.expect_refund_payment().never();
    payments_provider
        .expect_verify_and_parse_webhook()
        .times(1)
        .returning(move |_, _| {
            Ok(PaymentsWebhookEvent::RefundUpdated {
                purchase_id: event_purchase_id,
                provider_refund_id: "re_pending_123".to_string(),
                status: RefundPaymentStatus::Succeeded,
            })
        });

    // Run the refund update workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let headers = sample_webhook_headers();
    let result = manager.handle_webhook(&headers, "payload").await;

    // Check result matches expectations
    assert!(result.is_ok());
}

#[tokio::test]
async fn handle_webhook_records_failed_automatic_refund_without_retrying() {
    // Setup identifiers for the terminal automatic refund
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_purchase_summary()
        .times(1)
        .withf(move |purchase_id| *purchase_id == event_purchase_id)
        .returning(move |_| {
            Ok(EventPurchaseSummary {
                amount_minor: 2_500,
                event_purchase_id,
                event_ticket_type_id,
                provider_payment_reference: Some("pi_test_123".to_string()),
                status: EventPurchaseStatus::RefundPending,
                ticket_title: "General admission".to_string(),
                ..EventPurchaseSummary::default()
            })
        });
    expect_event_purchase_refund_started(
        &mut db,
        event_purchase_id,
        event_purchase_refund_id,
        EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
        Some("re_failed_123"),
        false,
        EventPurchaseRefundStatus::ProviderPending,
    );
    db.expect_record_event_purchase_refund_failed().never();
    db.expect_record_event_purchase_refund_pending().never();
    db.expect_record_event_purchase_refund_succeeded().never();
    db.expect_record_event_purchase_refund_terminal_failed()
        .times(1)
        .withf(
            move |refund_id, expected_idempotency_key, provider_refund_id, failure_message| {
                *refund_id == event_purchase_refund_id
                    && expected_idempotency_key
                        == &format!("event-purchase-refund-{event_purchase_id}")
                    && provider_refund_id == "re_failed_123"
                    && failure_message == "provider refund failed"
            },
        )
        .returning(|_, _, _, _| Ok(()));
    db.expect_record_automatic_refund_for_event_purchase().never();

    // Setup notifications manager and payments provider mocks
    let notifications_manager = MockNotificationsManager::new();
    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider.expect_find_refund().never();
    payments_provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    payments_provider.expect_refund_payment().never();
    payments_provider
        .expect_verify_and_parse_webhook()
        .times(1)
        .returning(move |_, _| {
            Ok(PaymentsWebhookEvent::RefundUpdated {
                purchase_id: event_purchase_id,
                provider_refund_id: "re_failed_123".to_string(),
                status: RefundPaymentStatus::Failed,
            })
        });

    // Run the refund update workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let headers = sample_webhook_headers();
    let result = manager.handle_webhook(&headers, "payload").await;

    // Check result matches expectations
    assert!(result.is_ok());
}

#[tokio::test]
async fn handle_webhook_ignores_stale_pending_update_after_terminal_failure() {
    // Setup identifiers and data structures
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_purchase_summary()
        .times(1)
        .withf(move |purchase_id| *purchase_id == event_purchase_id)
        .returning(move |_| {
            Ok(EventPurchaseSummary {
                amount_minor: 2_500,
                event_purchase_id,
                event_ticket_type_id,
                provider_payment_reference: Some("pi_test_123".to_string()),
                status: EventPurchaseStatus::RefundPending,
                ticket_title: "General admission".to_string(),
                ..EventPurchaseSummary::default()
            })
        });
    expect_event_purchase_refund_started(
        &mut db,
        event_purchase_id,
        event_purchase_refund_id,
        EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
        None,
        false,
        EventPurchaseRefundStatus::ProviderFailed,
    );
    db.expect_record_event_purchase_refund_failed().never();
    db.expect_record_event_purchase_refund_pending().never();
    db.expect_record_event_purchase_refund_succeeded().never();
    db.expect_record_event_purchase_refund_terminal_failed().never();
    db.expect_record_automatic_refund_for_event_purchase().never();

    // Setup notifications manager and payments provider mocks
    let notifications_manager = MockNotificationsManager::new();
    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider.expect_find_refund().never();
    payments_provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    payments_provider.expect_refund_payment().never();
    payments_provider
        .expect_verify_and_parse_webhook()
        .times(1)
        .returning(move |_, _| {
            Ok(PaymentsWebhookEvent::RefundUpdated {
                purchase_id: event_purchase_id,
                provider_refund_id: "re_failed_123".to_string(),
                status: RefundPaymentStatus::Pending,
            })
        });

    // Run the stale refund update workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let headers = sample_webhook_headers();
    let result = manager.handle_webhook(&headers, "payload").await;

    // Check result matches expectations
    assert!(result.is_ok());
}

#[tokio::test]
async fn handle_webhook_accepts_concurrently_finalized_pending_refund() {
    // Setup identifiers and data structures
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_event_purchase_refund_started(
        &mut db,
        event_purchase_id,
        event_purchase_refund_id,
        EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
        None,
        true,
        EventPurchaseRefundStatus::ProviderPending,
    );
    db.expect_record_event_purchase_refund_failed().never();
    db.expect_record_event_purchase_refund_pending()
        .times(1)
        .returning(move |_, _, _| {
            Ok(sample_event_purchase_refund(
                event_purchase_id,
                event_purchase_refund_id,
                EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
                Some("re_pending_123".to_string()),
                false,
                EventPurchaseRefundStatus::Finalized,
            ))
        });
    db.expect_record_event_purchase_refund_succeeded().never();
    db.expect_record_event_purchase_refund_terminal_failed().never();
    db.expect_record_automatic_refund_for_event_purchase()
        .times(1)
        .withf(move |purchase_id, provider_refund_id| {
            *purchase_id == event_purchase_id && provider_refund_id == "re_pending_123"
        })
        .returning(|_, _| Ok(()));
    db.expect_reconcile_event_purchase_for_checkout_session()
        .times(1)
        .returning(move |_, _, _| {
            Ok(ReconcileEventPurchaseResult::RefundRequired(
                crate::db::payments::RefundRequiredEventPurchase {
                    amount_minor: 2_500,
                    event_purchase_id,
                    provider_payment_reference: "pi_test_123".to_string(),
                },
            ))
        });

    // Setup notifications manager and payments provider mocks
    let notifications_manager = MockNotificationsManager::new();
    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider
        .expect_find_refund()
        .times(1)
        .returning(|_| Box::pin(async { Ok(None) }));
    payments_provider
        .expect_provider()
        .times(2)
        .return_const(PaymentProvider::Stripe);
    payments_provider.expect_refund_payment().times(1).returning(|_| {
        Box::pin(async move {
            Ok(RefundPaymentResult {
                provider_refund_id: "re_pending_123".to_string(),
                status: RefundPaymentStatus::Pending,
            })
        })
    });
    payments_provider
        .expect_verify_and_parse_webhook()
        .times(1)
        .returning(|_, _| {
            Ok(PaymentsWebhookEvent::CheckoutCompleted {
                provider_session_id: "cs_test_123".to_string(),

                provider_payment_reference: Some("pi_test_123".to_string()),
            })
        });

    // Run the webhook workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let headers = sample_webhook_headers();
    let result = manager.handle_webhook(&headers, "payload").await;

    // Check result matches expectations
    assert!(result.is_ok());
}

#[tokio::test]
async fn handle_webhook_rotates_attempt_when_automatic_provider_refund_terminally_fails() {
    // Setup identifiers and data structures
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_ensure_event_purchase_refund_started()
        .times(1)
        .returning(move |_, _, _| {
            Ok(sample_event_purchase_refund(
                event_purchase_id,
                event_purchase_refund_id,
                EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
                None,
                true,
                EventPurchaseRefundStatus::ProviderPending,
            ))
        });
    db.expect_get_event_summary_by_id().never();
    db.expect_get_site_settings().never();
    db.expect_record_event_purchase_refund_failed().never();
    db.expect_record_event_purchase_refund_pending().never();
    db.expect_record_event_purchase_refund_succeeded().never();
    db.expect_record_event_purchase_refund_terminal_failed()
        .times(1)
        .withf(
            move |refund_id, expected_idempotency_key, provider_refund_id, failure_message| {
                *refund_id == event_purchase_refund_id
                    && expected_idempotency_key
                        == &format!("event-purchase-refund-{event_purchase_id}")
                    && provider_refund_id == "re_failed_123"
                    && failure_message == "provider refund failed"
            },
        )
        .returning(|_, _, _, _| Ok(()));
    db.expect_record_automatic_refund_for_event_purchase().never();
    db.expect_reconcile_event_purchase_for_checkout_session()
        .times(1)
        .returning(move |_, _, _| {
            Ok(ReconcileEventPurchaseResult::RefundRequired(
                crate::db::payments::RefundRequiredEventPurchase {
                    amount_minor: 2_500,
                    event_purchase_id,
                    provider_payment_reference: "pi_test_123".to_string(),
                },
            ))
        });

    // Setup notifications manager mock
    let notifications_manager = MockNotificationsManager::new();

    // Setup payments provider mock
    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider
        .expect_find_refund()
        .times(1)
        .returning(|_| Box::pin(async { Ok(None) }));
    payments_provider
        .expect_provider()
        .times(2)
        .return_const(PaymentProvider::Stripe);
    payments_provider.expect_refund_payment().times(1).returning(|_| {
        Box::pin(async move {
            Ok(RefundPaymentResult {
                provider_refund_id: "re_failed_123".to_string(),
                status: RefundPaymentStatus::Failed,
            })
        })
    });
    payments_provider
        .expect_verify_and_parse_webhook()
        .times(1)
        .returning(|_, _| {
            Ok(PaymentsWebhookEvent::CheckoutCompleted {
                provider_session_id: "cs_test_123".to_string(),

                provider_payment_reference: Some("pi_test_123".to_string()),
            })
        });

    // Run the webhook workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let headers = sample_webhook_headers();
    let err = manager
        .handle_webhook(&headers, "payload")
        .await
        .expect_err("terminal automatic provider refund failure to stop finalization");

    // Check the returned error
    match err {
        HandleWebhookError::Unexpected(err) => {
            assert_eq!(err.to_string(), "provider refund failed");
        }
        unexpected => panic!("unexpected error: {unexpected:?}"),
    }
}

#[tokio::test]
async fn handle_webhook_returns_invalid_payload_when_verification_fails() {
    // Setup payments provider mock
    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider
        .expect_verify_and_parse_webhook()
        .times(1)
        .withf(|headers, body| has_test_signature_header(headers) && body == "payload")
        .returning(|_, _| Err(anyhow::anyhow!("invalid signature")));

    // Run the webhook workflow
    let manager = sample_payments_manager(
        MockDB::new(),
        MockNotificationsManager::new(),
        Some(payments_provider),
    );
    let headers = sample_webhook_headers();
    let err = manager
        .handle_webhook(&headers, "payload")
        .await
        .expect_err("webhook verification to fail");

    // Check the returned error
    assert!(matches!(err, HandleWebhookError::InvalidPayload));
}

#[tokio::test]
async fn handle_webhook_returns_not_configured_when_payments_are_unavailable() {
    // Run the webhook workflow without a configured payments provider
    let manager = sample_payments_manager(MockDB::new(), MockNotificationsManager::new(), None);
    let headers = sample_webhook_headers();
    let err = manager
        .handle_webhook(&headers, "payload")
        .await
        .expect_err("webhook handling to fail when payments are not configured");

    // Check the returned error
    assert!(matches!(err, HandleWebhookError::PaymentsNotConfigured));
}

#[tokio::test]
async fn handle_webhook_returns_unexpected_when_automatic_refund_fails() {
    // Setup identifiers and data structures
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_ensure_event_purchase_refund_started()
        .times(1)
        .returning(move |_, _, _| {
            Ok(sample_event_purchase_refund(
                event_purchase_id,
                event_purchase_refund_id,
                EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
                None,
                true,
                EventPurchaseRefundStatus::ProviderPending,
            ))
        });
    db.expect_get_event_summary_by_id().never();
    db.expect_get_site_settings().never();
    db.expect_record_event_purchase_refund_failed()
        .times(1)
        .withf(move |refund_id, failure_message| {
            *refund_id == event_purchase_refund_id && failure_message == "Stripe refund failed"
        })
        .returning(|_, _| Ok(()));
    db.expect_record_event_purchase_refund_succeeded().never();
    db.expect_record_automatic_refund_for_event_purchase().never();
    db.expect_reconcile_event_purchase_for_checkout_session()
        .times(1)
        .returning(move |_, _, _| {
            Ok(ReconcileEventPurchaseResult::RefundRequired(
                crate::db::payments::RefundRequiredEventPurchase {
                    amount_minor: 2_500,
                    event_purchase_id,
                    provider_payment_reference: "pi_test_123".to_string(),
                },
            ))
        });

    // Setup notifications manager mock
    let notifications_manager = MockNotificationsManager::new();

    // Setup payments provider mock
    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider
        .expect_find_refund()
        .times(1)
        .returning(|_| Box::pin(async { Ok(None) }));
    payments_provider
        .expect_provider()
        .times(2)
        .return_const(PaymentProvider::Stripe);
    payments_provider
        .expect_refund_payment()
        .times(1)
        .returning(|_| Box::pin(async move { Err(anyhow::anyhow!("Stripe refund failed")) }));
    payments_provider
        .expect_verify_and_parse_webhook()
        .times(1)
        .returning(|_, _| {
            Ok(PaymentsWebhookEvent::CheckoutCompleted {
                provider_session_id: "cs_test_123".to_string(),

                provider_payment_reference: Some("pi_test_123".to_string()),
            })
        });

    // Run the webhook workflow
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let headers = sample_webhook_headers();
    let err = manager
        .handle_webhook(&headers, "payload")
        .await
        .expect_err("automatic refund to fail");

    // Check the returned error
    match err {
        HandleWebhookError::Unexpected(err) => {
            assert_eq!(err.to_string(), "Stripe refund failed");
        }
        unexpected => panic!("unexpected error: {unexpected:?}"),
    }
}

#[tokio::test]
async fn handle_webhook_retries_automatic_refund_after_persist_failure() {
    // Setup identifiers and ordered retry expectations
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();
    let mut ensure_sequence = Sequence::new();
    let mut persist_sequence = Sequence::new();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_ensure_event_purchase_refund_started()
        .times(1)
        .in_sequence(&mut ensure_sequence)
        .returning(move |_, _, _| {
            Ok(sample_event_purchase_refund(
                event_purchase_id,
                event_purchase_refund_id,
                EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
                None,
                true,
                EventPurchaseRefundStatus::ProviderPending,
            ))
        });
    db.expect_ensure_event_purchase_refund_started()
        .times(1)
        .in_sequence(&mut ensure_sequence)
        .returning(move |_, _, _| {
            Ok(sample_event_purchase_refund(
                event_purchase_id,
                event_purchase_refund_id,
                EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
                Some("re_test_123".to_string()),
                false,
                EventPurchaseRefundStatus::ProviderSucceeded,
            ))
        });
    db.expect_get_event_summary_by_id().never();
    db.expect_get_site_settings().never();
    db.expect_record_event_purchase_refund_failed().never();
    expect_event_purchase_refund_succeeded(
        &mut db,
        event_purchase_id,
        event_purchase_refund_id,
        EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
    );
    db.expect_reconcile_event_purchase_for_checkout_session()
        .times(2)
        .returning(move |_, _, _| {
            Ok(ReconcileEventPurchaseResult::RefundRequired(
                crate::db::payments::RefundRequiredEventPurchase {
                    amount_minor: 2_500,
                    event_purchase_id,
                    provider_payment_reference: "pi_test_123".to_string(),
                },
            ))
        });
    db.expect_record_automatic_refund_for_event_purchase()
        .times(1)
        .in_sequence(&mut persist_sequence)
        .withf(move |purchase_id, provider_refund_id| {
            *purchase_id == event_purchase_id && provider_refund_id == "re_test_123"
        })
        .returning(|_, _| Err(anyhow::anyhow!("persist automatic refund failed")));
    db.expect_record_automatic_refund_for_event_purchase()
        .times(1)
        .in_sequence(&mut persist_sequence)
        .withf(move |purchase_id, provider_refund_id| {
            *purchase_id == event_purchase_id && provider_refund_id == "re_test_123"
        })
        .returning(|_, _| Ok(()));

    // Setup notifications manager mock
    let notifications_manager = MockNotificationsManager::new();

    // Setup payments provider mock
    let mut payments_provider = MockPaymentsProvider::new();
    expect_provider_refund_lookup_miss(&mut payments_provider, 1);
    payments_provider
        .expect_provider()
        .times(4)
        .return_const(PaymentProvider::Stripe);
    expect_provider_refund_created(&mut payments_provider, event_purchase_id, 1);
    expect_checkout_completed_webhooks(&mut payments_provider, 2);

    // Run the webhook workflow twice to simulate Stripe retrying the event
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let headers = sample_webhook_headers();
    let first_err = manager
        .handle_webhook(&headers, "payload")
        .await
        .expect_err("automatic refund persistence to fail");
    let second_result = manager.handle_webhook(&headers, "payload").await;

    // Check the retry behavior
    match first_err {
        HandleWebhookError::Unexpected(err) => {
            assert_eq!(err.to_string(), "persist automatic refund failed");
        }
        unexpected => panic!("unexpected error: {unexpected:?}"),
    }
    assert!(second_result.is_ok());
}

#[tokio::test]
async fn handle_webhook_retries_automatic_refund_after_provider_failure() {
    // Setup identifiers and ordered retry expectations
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();
    let mut ensure_sequence = Sequence::new();
    let mut refund_sequence = Sequence::new();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_ensure_event_purchase_refund_started()
        .times(1)
        .in_sequence(&mut ensure_sequence)
        .returning(move |_, _, _| {
            Ok(sample_event_purchase_refund(
                event_purchase_id,
                event_purchase_refund_id,
                EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
                None,
                true,
                EventPurchaseRefundStatus::ProviderPending,
            ))
        });
    db.expect_ensure_event_purchase_refund_started()
        .times(1)
        .in_sequence(&mut ensure_sequence)
        .returning(move |_, _, _| {
            Ok(sample_event_purchase_refund(
                event_purchase_id,
                event_purchase_refund_id,
                EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
                None,
                false,
                EventPurchaseRefundStatus::ProviderFailed,
            ))
        });
    db.expect_get_event_summary_by_id().never();
    db.expect_get_site_settings().never();
    db.expect_record_event_purchase_refund_failed()
        .times(1)
        .withf(move |refund_id, failure_message| {
            *refund_id == event_purchase_refund_id && failure_message == "Stripe refund failed"
        })
        .returning(|_, _| Ok(()));
    expect_event_purchase_refund_succeeded(
        &mut db,
        event_purchase_id,
        event_purchase_refund_id,
        EventPurchaseRefundKind::AutomaticUnfulfillableCheckout,
    );
    db.expect_reconcile_event_purchase_for_checkout_session()
        .times(2)
        .returning(move |_, _, _| {
            Ok(ReconcileEventPurchaseResult::RefundRequired(
                crate::db::payments::RefundRequiredEventPurchase {
                    amount_minor: 2_500,
                    event_purchase_id,
                    provider_payment_reference: "pi_test_123".to_string(),
                },
            ))
        });
    db.expect_record_automatic_refund_for_event_purchase()
        .times(1)
        .withf(move |purchase_id, provider_refund_id| {
            *purchase_id == event_purchase_id && provider_refund_id == "re_test_123"
        })
        .returning(|_, _| Ok(()));

    // Setup notifications manager mock
    let notifications_manager = MockNotificationsManager::new();

    // Setup payments provider mock
    let mut payments_provider = MockPaymentsProvider::new();
    expect_provider_refund_lookup_miss(&mut payments_provider, 2);
    payments_provider
        .expect_provider()
        .times(4)
        .return_const(PaymentProvider::Stripe);
    payments_provider
        .expect_refund_payment()
        .times(1)
        .in_sequence(&mut refund_sequence)
        .returning(|_| Box::pin(async { Err(anyhow::anyhow!("Stripe refund failed")) }));
    payments_provider
        .expect_refund_payment()
        .times(1)
        .in_sequence(&mut refund_sequence)
        .returning(|_| {
            Box::pin(async {
                Ok(RefundPaymentResult {
                    provider_refund_id: "re_test_123".to_string(),
                    status: RefundPaymentStatus::Succeeded,
                })
            })
        });
    expect_checkout_completed_webhooks(&mut payments_provider, 2);

    // Run the webhook workflow twice and check the Stripe retry succeeds
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let headers = sample_webhook_headers();
    let first_err = manager
        .handle_webhook(&headers, "payload")
        .await
        .expect_err("automatic refund to fail");
    assert!(manager.handle_webhook(&headers, "payload").await.is_ok());

    // Check the retry behavior
    match first_err {
        HandleWebhookError::Unexpected(err) => {
            assert_eq!(err.to_string(), "Stripe refund failed");
        }
        unexpected => panic!("unexpected error: {unexpected:?}"),
    }
}

#[tokio::test]
async fn reject_refund_request_persists_rejection_and_enqueues_notification() {
    // Setup identifiers and data structures
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let review_note = "Not eligible".to_string();
    let site_settings = SiteSettings::default();
    let target_user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_reject_event_refund_request()
        .times(1)
        .withf(move |actor_id, gid, eid, uid, note| {
            *actor_id == actor_user_id
                && *gid == group_id
                && *eid == event_id
                && *uid == target_user_id
                && note.as_deref() == Some(review_note.as_str())
        })
        .returning(move |_, _, _, _, _| {
            Ok(CompletedEventPurchase {
                community_id,
                event_id,
                user_id: target_user_id,
            })
        });
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));

    // Setup notifications manager mock
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager
        .expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventRefundRejected)
                && notification.recipients == vec![target_user_id]
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Run the refund rejection workflow
    let manager =
        sample_payments_manager(db, notifications_manager, Some(MockPaymentsProvider::new()));
    let result = manager
        .reject_refund_request(&RejectRefundRequestInput {
            actor_user_id,
            community_id,
            event_id,
            group_id,
            user_id: target_user_id,

            review_note: Some("Not eligible".to_string()),
        })
        .await;

    // Check result matches expectations
    assert!(result.is_ok());
}

#[tokio::test]
async fn request_refund_records_the_refund_request() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);
    let site_settings = SiteSettings::default();
    let user_id = Uuid::new_v4();
    let expected_template_data = to_value(&EventRefundRequested {
        event: event.clone(),
        link: "/dashboard/group?tab=events".to_string(),
        theme: site_settings.theme.clone(),
    })
    .unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    db.expect_request_event_refund()
        .times(1)
        .withf(move |cid, eid, uid, reason, template_data| {
            *cid == community_id
                && *eid == event_id
                && *uid == user_id
                && reason.as_deref() == Some("Need to cancel")
                && template_data == &expected_template_data
        })
        .returning(move |_, _, _, _, _| Ok(()));

    // Run the refund request workflow
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), None);
    let result = manager
        .request_refund(&RequestRefundInput {
            community_id,
            event_id,
            user_id,

            requested_reason: Some("Need to cancel".to_string()),
        })
        .await;

    // Check result matches expectations
    assert!(result.is_ok());
}

#[tokio::test]
async fn request_refund_returns_error_when_notification_context_load_fails() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(sample_event_summary(event_id)));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Err(anyhow::anyhow!("db error")));
    db.expect_request_event_refund().never();

    // Run the refund request workflow
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), None);
    let err = manager
        .request_refund(&RequestRefundInput {
            community_id,
            event_id,
            user_id: Uuid::new_v4(),

            requested_reason: Some("Need to cancel".to_string()),
        })
        .await
        .expect_err("refund request to fail when notification context cannot be loaded");

    // Check the returned error
    assert_eq!(err.to_string(), "db error");
}

// Helpers.

/// Durable refund row expectation used by payments manager tests.
struct EventPurchaseRefundStartedExpectation {
    /// Event purchase identifier.
    event_purchase_id: Uuid,
    /// Durable refund row identifier.
    event_purchase_refund_id: Uuid,
    /// Idempotency key that should be returned to the service.
    idempotency_key: String,
    /// Durable refund kind.
    kind: EventPurchaseRefundKind,
    /// Whether the row was created by the current attempt.
    started_now: bool,
    /// Durable refund status.
    status: EventPurchaseRefundStatus,

    /// Provider refund identifier, when a provider refund is pinned.
    provider_refund_id: Option<String>,
}

/// Expects checkout-completed webhooks with the standard test identifiers.
fn expect_checkout_completed_webhooks(payments_provider: &mut MockPaymentsProvider, times: usize) {
    payments_provider
        .expect_verify_and_parse_webhook()
        .times(times)
        .returning(|_, _| {
            Ok(PaymentsWebhookEvent::CheckoutCompleted {
                provider_session_id: "cs_test_123".to_string(),

                provider_payment_reference: Some("pi_test_123".to_string()),
            })
        });
}

/// Expect a durable refund row to be started or returned.
fn expect_event_purchase_refund_started(
    db: &mut MockDB,
    event_purchase_id: Uuid,
    event_purchase_refund_id: Uuid,
    kind: EventPurchaseRefundKind,
    provider_refund_id: Option<&str>,
    started_now: bool,
    status: EventPurchaseRefundStatus,
) {
    expect_event_purchase_refund_started_with(
        db,
        EventPurchaseRefundStartedExpectation {
            event_purchase_id,
            event_purchase_refund_id,
            idempotency_key: format!("event-purchase-refund-{event_purchase_id}"),
            kind,
            started_now,
            status,

            provider_refund_id: provider_refund_id.map(str::to_string),
        },
    );
}

/// Expect a durable refund row to be started or returned.
fn expect_event_purchase_refund_started_with(
    db: &mut MockDB,
    expectation: EventPurchaseRefundStartedExpectation,
) {
    let event_purchase_id = expectation.event_purchase_id;
    let event_purchase_refund_id = expectation.event_purchase_refund_id;
    let idempotency_key = expectation.idempotency_key;
    let kind = expectation.kind;
    let provider_refund_id = expectation.provider_refund_id;
    let started_now = expectation.started_now;
    let status = expectation.status;

    db.expect_ensure_event_purchase_refund_started()
        .times(1)
        .withf(move |purchase_id, provider, refund_kind| {
            *purchase_id == event_purchase_id
                && *provider == PaymentProvider::Stripe
                && *refund_kind == kind
        })
        .returning(move |_, _, _| {
            Ok(sample_event_purchase_refund_with_idempotency_key(
                event_purchase_id,
                event_purchase_refund_id,
                kind,
                provider_refund_id.clone(),
                started_now,
                status,
                idempotency_key.clone(),
            ))
        });
}

/// Expect a provider refund success to be recorded locally.
fn expect_event_purchase_refund_succeeded(
    db: &mut MockDB,
    event_purchase_id: Uuid,
    event_purchase_refund_id: Uuid,
    kind: EventPurchaseRefundKind,
) {
    expect_event_purchase_refund_succeeded_with_provider_id(
        db,
        event_purchase_id,
        event_purchase_refund_id,
        kind,
        "re_test_123",
    );
}

/// Expect a provider refund success with a specific provider refund identifier.
fn expect_event_purchase_refund_succeeded_with_provider_id(
    db: &mut MockDB,
    event_purchase_id: Uuid,
    event_purchase_refund_id: Uuid,
    kind: EventPurchaseRefundKind,
    provider_refund_id: &str,
) {
    let provider_refund_id = provider_refund_id.to_string();
    let expected_provider_refund_id = provider_refund_id.clone();

    db.expect_record_event_purchase_refund_succeeded()
        .times(1)
        .withf(move |refund_id, provider_refund_id| {
            *refund_id == event_purchase_refund_id
                && provider_refund_id == expected_provider_refund_id.as_str()
        })
        .returning(move |_, _| {
            Ok(sample_event_purchase_refund(
                event_purchase_id,
                event_purchase_refund_id,
                kind,
                Some(provider_refund_id.clone()),
                false,
                EventPurchaseRefundStatus::ProviderSucceeded,
            ))
        });
}

/// Expect a provider refund lookup that does not find an existing refund.
fn expect_provider_refund_lookup_miss(payments_provider: &mut MockPaymentsProvider, times: usize) {
    payments_provider
        .expect_find_refund()
        .times(times)
        .returning(|_| Box::pin(async { Ok(None) }));
}

/// Expect a provider refund lookup that finds a refund.
fn expect_provider_refund_lookup_hit(
    payments_provider: &mut MockPaymentsProvider,
    event_purchase_id: Uuid,
    provider_refund_id: &str,
    status: RefundPaymentStatus,
) {
    let provider_refund_id = provider_refund_id.to_string();
    let expected_provider_refund_id = provider_refund_id.clone();

    payments_provider
        .expect_find_refund()
        .times(1)
        .withf(move |input| {
            input.amount_minor == 2_500
                && input.provider_payment_reference == "pi_test_123"
                && input.purchase_id == event_purchase_id
                && input.provider_refund_id.as_deref() == Some(expected_provider_refund_id.as_str())
        })
        .returning(move |_| {
            let provider_refund_id = provider_refund_id.clone();

            Box::pin(async move {
                Ok(Some(RefundPaymentResult {
                    provider_refund_id,
                    status,
                }))
            })
        });
}

/// Expect a provider refund to be created successfully.
fn expect_provider_refund_created(
    payments_provider: &mut MockPaymentsProvider,
    event_purchase_id: Uuid,
    times: usize,
) {
    expect_provider_refund_created_with_idempotency_key(
        payments_provider,
        event_purchase_id,
        &format!("event-purchase-refund-{event_purchase_id}"),
        "re_test_123",
        RefundPaymentStatus::Succeeded,
        times,
    );
}

/// Expect a provider refund to be created with a specific idempotency key.
fn expect_provider_refund_created_with_idempotency_key(
    payments_provider: &mut MockPaymentsProvider,
    event_purchase_id: Uuid,
    idempotency_key: &str,
    provider_refund_id: &str,
    status: RefundPaymentStatus,
    times: usize,
) {
    let idempotency_key = idempotency_key.to_string();
    let expected_idempotency_key = idempotency_key.clone();
    let provider_refund_id = provider_refund_id.to_string();

    payments_provider
        .expect_refund_payment()
        .times(times)
        .withf(move |input| {
            input.amount_minor == 2_500
                && input.idempotency_key == expected_idempotency_key
                && input.provider_payment_reference == "pi_test_123"
                && input.purchase_id == event_purchase_id
        })
        .returning(move |_| {
            let provider_refund_id = provider_refund_id.clone();

            Box::pin(async move {
                Ok(RefundPaymentResult {
                    provider_refund_id,
                    status,
                })
            })
        });
}

/// Returns true when the test webhook headers include the expected signature.
fn has_test_signature_header(headers: &HeaderMap) -> bool {
    matches!(
        headers.get("stripe-signature").and_then(|value| value.to_str().ok()),
        Some("sig_test")
    )
}

/// Create a sample event summary.
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

/// Create a sample purchase summary.
fn sample_event_purchase_summary(
    event_purchase_id: Uuid,
    event_ticket_type_id: Uuid,
    provider_checkout_url: Option<String>,
    discount_code: Option<String>,
) -> EventPurchaseSummary {
    EventPurchaseSummary {
        amount_minor: 2_500,
        currency_code: "usd".to_string(),
        event_purchase_id,
        event_ticket_type_id,
        ticket_title: "General admission".to_string(),

        discount_code,
        provider_checkout_url,
        ..EventPurchaseSummary::default()
    }
}

/// Create a durable refund record used by payments manager tests.
fn sample_event_purchase_refund(
    event_purchase_id: Uuid,
    event_purchase_refund_id: Uuid,
    kind: EventPurchaseRefundKind,
    provider_refund_id: Option<String>,
    started_now: bool,
    status: EventPurchaseRefundStatus,
) -> EventPurchaseRefund {
    sample_event_purchase_refund_with_idempotency_key(
        event_purchase_id,
        event_purchase_refund_id,
        kind,
        provider_refund_id,
        started_now,
        status,
        format!("event-purchase-refund-{event_purchase_id}"),
    )
}

/// Create a durable refund record with a custom idempotency key.
fn sample_event_purchase_refund_with_idempotency_key(
    event_purchase_id: Uuid,
    event_purchase_refund_id: Uuid,
    kind: EventPurchaseRefundKind,
    provider_refund_id: Option<String>,
    started_now: bool,
    status: EventPurchaseRefundStatus,
    idempotency_key: String,
) -> EventPurchaseRefund {
    EventPurchaseRefund {
        amount_minor: 2_500,
        currency_code: "usd".to_string(),
        event_purchase_id,
        event_purchase_refund_id,
        idempotency_key,
        kind,
        payment_provider: PaymentProvider::Stripe,
        started_now,
        status,

        failure_message: None,
        finalized_at: None,
        provider_refund_id,
        provider_refunded_at: None,
    }
}

/// Create a payments manager with mock dependencies.
fn sample_payments_manager(
    db: MockDB,
    notifications_manager: MockNotificationsManager,
    payments_provider: Option<MockPaymentsProvider>,
) -> PgPaymentsManager {
    // Promote the mock provider into the shared trait object used by the manager
    let payments_provider = payments_provider
        .map(|payments_provider| Arc::new(payments_provider) as DynPaymentsProvider);

    PgPaymentsManager::new(
        Arc::new(db),
        Arc::new(notifications_manager),
        payments_provider,
        HttpServerConfig::default(),
    )
}

/// Create a prepared checkout for the payments manager.
fn sample_prepared_event_checkout(
    event_id: Uuid,
    event_purchase_id: Uuid,
    event_ticket_type_id: Uuid,
    provider_checkout_url: Option<String>,
    discount_code: Option<String>,
    recipient: GroupPaymentRecipient,
) -> PreparedEventCheckout {
    PreparedEventCheckout {
        community_name: "community".to_string(),
        event_id,
        event_slug: "event".to_string(),
        group_slug: "group".to_string(),
        purchase: sample_event_purchase_summary(
            event_purchase_id,
            event_ticket_type_id,
            provider_checkout_url,
            discount_code,
        ),
        recipient,

        group_slug_pretty: None,
    }
}

/// Builds the webhook headers used by payments manager tests.
fn sample_webhook_headers() -> HeaderMap {
    // Mirror the provider-specific header shape expected by the mock verifier
    let mut headers = HeaderMap::new();
    headers.insert("stripe-signature", HeaderValue::from_static("sig_test"));
    headers
}
