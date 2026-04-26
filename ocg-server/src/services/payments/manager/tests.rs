use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};

use axum::http::{HeaderMap, HeaderValue};
use serde_json::to_value;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::{
        mock::MockDB,
        payments::{CompletedEventPurchase, ReconcileEventPurchaseResult},
    },
    services::{
        notifications::{MockNotificationsManager, NotificationKind},
        payments::{CheckoutSession, MockPaymentsProvider, PaymentsWebhookEvent, RefundPaymentResult},
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
    db.expect_revert_event_refund_approval().times(0);

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
    payments_provider
        .expect_refund_payment()
        .times(1)
        .withf(move |input| {
            input.amount_minor == 2_500
                && input.provider_payment_reference == "pi_test_123"
                && input.purchase_id == event_purchase_id
        })
        .returning(|_| {
            Box::pin(async move {
                Ok(RefundPaymentResult {
                    provider_refund_id: "re_test_123".to_string(),
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
    db.expect_approve_event_refund_request().times(0);
    db.expect_revert_event_refund_approval()
        .times(1)
        .withf(move |gid, eid, uid| *gid == group_id && *eid == event_id && *uid == target_user_id)
        .returning(|_, _, _| Ok(()));

    // Setup notifications manager and payments provider mocks
    let notifications_manager = MockNotificationsManager::new();
    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider.expect_refund_payment().times(0);

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
    db.expect_begin_event_refund_approval().times(0);

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
async fn approve_refund_request_reverts_when_provider_refund_fails() {
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
    db.expect_approve_event_refund_request().times(0);
    db.expect_revert_event_refund_approval()
        .times(1)
        .withf(move |gid, eid, uid| *gid == group_id && *eid == event_id && *uid == target_user_id)
        .returning(|_, _, _| Ok(()));

    // Setup notifications manager and payments provider mocks
    let notifications_manager = MockNotificationsManager::new();
    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider
        .expect_refund_payment()
        .times(1)
        .withf(move |input| {
            input.amount_minor == 2_500
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

    // Run the checkout session workflow
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), Some(payments_provider));
    let redirect_url = manager
        .get_or_create_checkout_redirect_url(
            &sample_prepared_event_checkout(
                event_id,
                event_purchase_id,
                event_ticket_type_id,
                None,
                Some("SPRING".to_string()),
                recipient,
            ),
            user_id,
        )
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
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), Some(payments_provider));
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
async fn get_or_create_checkout_redirect_url_returns_error_when_checkout_url_is_missing_after_creation() {
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
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), Some(payments_provider));
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
    db.expect_get_event_purchase_summary().times(0);

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
    db.expect_get_event_purchase_summary().times(0);

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
            Ok(ReconcileEventPurchaseResult::Completed(CompletedEventPurchase {
                community_id,
                event_id,
                user_id,
            }))
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
                provider_payment_reference: Some("pi_test_123".to_string()),
                provider_session_id: "cs_test_123".to_string(),
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
    db.expect_get_event_summary_by_id().times(0);
    db.expect_get_site_settings().times(0);
    db.expect_expire_event_purchase_for_checkout_session()
        .times(1)
        .withf(|provider, session_id| *provider == PaymentProvider::Stripe && session_id == "cs_test_123")
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
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), Some(payments_provider));
    let headers = sample_webhook_headers();
    let result = manager.handle_webhook(&headers, "payload").await;

    // Check result matches expectations
    assert!(result.is_ok());
}

#[tokio::test]
async fn handle_webhook_ignores_noop_checkout_completion() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_summary_by_id().times(0);
    db.expect_get_site_settings().times(0);
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
    notifications_manager.expect_enqueue().times(0);

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
                provider_payment_reference: Some("pi_test_123".to_string()),
                provider_session_id: "cs_test_123".to_string(),
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

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_summary_by_id().times(0);
    db.expect_get_site_settings().times(0);
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
    payments_provider
        .expect_provider()
        .times(1)
        .return_const(PaymentProvider::Stripe);
    payments_provider
        .expect_refund_payment()
        .times(1)
        .withf(move |input| {
            input.amount_minor == 2_500
                && input.provider_payment_reference == "pi_test_123"
                && input.purchase_id == event_purchase_id
        })
        .returning(|_| {
            Box::pin(async move {
                Ok(RefundPaymentResult {
                    provider_refund_id: "re_test_123".to_string(),
                })
            })
        });
    payments_provider
        .expect_verify_and_parse_webhook()
        .times(1)
        .withf(|headers, body| has_test_signature_header(headers) && body == "payload")
        .returning(|_, _| {
            Ok(PaymentsWebhookEvent::CheckoutCompleted {
                provider_payment_reference: Some("pi_test_123".to_string()),
                provider_session_id: "cs_test_123".to_string(),
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

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_summary_by_id().times(0);
    db.expect_get_site_settings().times(0);
    db.expect_record_automatic_refund_for_event_purchase().times(0);
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
        .expect_provider()
        .times(1)
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
                provider_payment_reference: Some("pi_test_123".to_string()),
                provider_session_id: "cs_test_123".to_string(),
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
    // Setup identifiers and attempt tracking
    let event_purchase_id = Uuid::new_v4();
    let persist_attempt = Arc::new(AtomicUsize::new(0));

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_summary_by_id().times(0);
    db.expect_get_site_settings().times(0);
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
        .times(2)
        .withf(move |purchase_id, provider_refund_id| {
            *purchase_id == event_purchase_id && provider_refund_id == "re_test_123"
        })
        .returning({
            let persist_attempt = Arc::clone(&persist_attempt);
            move |_, _| {
                if persist_attempt.fetch_add(1, Ordering::SeqCst) == 0 {
                    Err(anyhow::anyhow!("persist automatic refund failed"))
                } else {
                    Ok(())
                }
            }
        });

    // Setup notifications manager mock
    let notifications_manager = MockNotificationsManager::new();

    // Setup payments provider mock
    let mut payments_provider = MockPaymentsProvider::new();
    payments_provider
        .expect_provider()
        .times(2)
        .return_const(PaymentProvider::Stripe);
    payments_provider.expect_refund_payment().times(2).returning(|_| {
        Box::pin(async move {
            Ok(RefundPaymentResult {
                provider_refund_id: "re_test_123".to_string(),
            })
        })
    });
    payments_provider
        .expect_verify_and_parse_webhook()
        .times(2)
        .returning(|_, _| {
            Ok(PaymentsWebhookEvent::CheckoutCompleted {
                provider_payment_reference: Some("pi_test_123".to_string()),
                provider_session_id: "cs_test_123".to_string(),
            })
        });

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
    // Setup identifiers and attempt tracking
    let event_purchase_id = Uuid::new_v4();
    let refund_attempt = Arc::new(AtomicUsize::new(0));

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_summary_by_id().times(0);
    db.expect_get_site_settings().times(0);
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
    payments_provider
        .expect_provider()
        .times(2)
        .return_const(PaymentProvider::Stripe);
    payments_provider.expect_refund_payment().times(2).returning({
        let refund_attempt = Arc::clone(&refund_attempt);
        move |_| {
            let refund_attempt = Arc::clone(&refund_attempt);
            Box::pin(async move {
                if refund_attempt.fetch_add(1, Ordering::SeqCst) == 0 {
                    Err(anyhow::anyhow!("Stripe refund failed"))
                } else {
                    Ok(RefundPaymentResult {
                        provider_refund_id: "re_test_123".to_string(),
                    })
                }
            })
        }
    });
    payments_provider
        .expect_verify_and_parse_webhook()
        .times(2)
        .returning(|_, _| {
            Ok(PaymentsWebhookEvent::CheckoutCompleted {
                provider_payment_reference: Some("pi_test_123".to_string()),
                provider_session_id: "cs_test_123".to_string(),
            })
        });

    // Run the webhook workflow twice to simulate Stripe retrying the event
    let manager = sample_payments_manager(db, notifications_manager, Some(payments_provider));
    let headers = sample_webhook_headers();
    let first_err = manager
        .handle_webhook(&headers, "payload")
        .await
        .expect_err("automatic refund to fail");
    let second_result = manager.handle_webhook(&headers, "payload").await;

    // Check the retry behavior
    match first_err {
        HandleWebhookError::Unexpected(err) => {
            assert_eq!(err.to_string(), "Stripe refund failed");
        }
        unexpected => panic!("unexpected error: {unexpected:?}"),
    }
    assert!(second_result.is_ok());
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
    let manager = sample_payments_manager(db, notifications_manager, Some(MockPaymentsProvider::new()));
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
    db.expect_request_event_refund().times(0);

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
        has_related_events: false,
        kind: EventKind::default(),
        logo_url: "https://example.test/logo.png".to_string(),
        name: "Event".to_string(),
        published: true,
        slug: "event".to_string(),
        timezone: chrono_tz::UTC,
        waitlist_count: 0,
        waitlist_enabled: false,
        capacity: None,
        description_short: None,
        ends_at: None,
        event_series_id: None,
        latitude: None,
        longitude: None,
        meeting_join_url: None,
        meeting_password: None,
        meeting_provider: None,
        payment_currency_code: None,
        popover_html: None,
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
        discount_code,
        event_purchase_id,
        event_ticket_type_id,
        provider_checkout_url,
        ticket_title: "General admission".to_string(),
        ..EventPurchaseSummary::default()
    }
}

/// Create a payments manager with mock dependencies.
fn sample_payments_manager(
    db: MockDB,
    notifications_manager: MockNotificationsManager,
    payments_provider: Option<MockPaymentsProvider>,
) -> PgPaymentsManager {
    // Promote the mock provider into the shared trait object used by the manager
    let payments_provider =
        payments_provider.map(|payments_provider| Arc::new(payments_provider) as DynPaymentsProvider);

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
    }
}

/// Builds the webhook headers used by payments manager tests.
fn sample_webhook_headers() -> HeaderMap {
    // Mirror the provider-specific header shape expected by the mock verifier
    let mut headers = HeaderMap::new();
    headers.insert("stripe-signature", HeaderValue::from_static("sig_test"));
    headers
}
