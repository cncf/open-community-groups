use std::sync::Arc;

use anyhow::anyhow;
use axum::http::{HeaderMap, HeaderValue};
use serde_json::{Value, json};
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::{
        mock::MockDB,
        payments::{
            CompletedEventPurchase, EventPurchaseNotificationContext,
            EventPurchaseRefundRecoveryContext, PrepareEventCheckoutPurchaseConflict,
            PrepareEventCheckoutPurchaseResult, UserPurchaseDocumentContext,
        },
    },
    services::{
        notifications::MockNotificationsManager,
        payments::{
            ApproveRefundRequestInput, AutomaticTaxReadiness, AutomaticTaxReadinessError,
            CompleteRefundRecoveryInput, DynPaymentsProvider, FinancialDocument,
            FinancialDocumentKind, FiscalSponsorReadinessError, HandleWebhookError,
            MockPaymentsProvider, PaymentJobRecovery, PaymentsError, PaymentsManager,
            PaymentsWebhookEvent, PgPaymentsManager, PrepareCheckoutOutcome,
            RejectRefundRequestInput, RequestRefundInput,
            provider::CheckoutSession,
            tests::{approval_template_matches, stripe_provider},
        },
    },
    types::{
        notifications::NotificationKind,
        payments::{
            CheckoutInput, EventPurchaseChargeModel, EventPurchaseStatus, EventPurchaseSummary,
            FiscalSponsorSeller, GroupPaymentRecipient, PaymentProvider, PreparedEventCheckout,
            TicketTaxBehavior, TicketTaxCalculationMode, TicketTaxJurisdiction, TicketTaxRate,
            TicketVenue,
        },
        site::SiteSettings,
        tests::{
            sample_event_purchase_summary, sample_event_summary, sample_group_payment_recipient,
        },
    },
};

use super::PaymentsWebhookEndpoint;

#[tokio::test]
async fn test_approve_refund_request_approves_external_purchases_locally() {
    // Setup identifiers and the local approval expectation
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_event_purchase_charge_model()
        .withf(move |purchase| *purchase == event_purchase_id)
        .times(1)
        .returning(|_| Ok(EventPurchaseChargeModel::External));
    db.expect_get_event_purchase_notification_context()
        .withf(move |group, purchase| *group == group_id && *purchase == event_purchase_id)
        .times(1)
        .returning(move |_, _| {
            Ok(Some(EventPurchaseNotificationContext {
                community_id,
                event_id,
            }))
        });
    expect_event_notification_context(&mut db, community_id, event_id);
    db.expect_approve_external_event_refund_request()
        .withf(move |actor, group, purchase, note, template| {
            *actor == actor_user_id
                && *group == group_id
                && *purchase == event_purchase_id
                && note.as_deref() == Some("Returned by bank transfer")
                && template
                    .as_ref()
                    .is_some_and(|data| approval_template_matches(data, event_id, true))
        })
        .times(1)
        .returning(move |_, _, _, _, _| {
            Ok(CompletedEventPurchase {
                community_id,
                event_id,
                user_id,

                transitioned: None,
            })
        });
    db.expect_queue_event_refund_request_approval().times(0);

    let manager = sample_payments_manager(db, MockNotificationsManager::new(), None);

    // Approve the external refund locally
    manager
        .approve_refund_request(&ApproveRefundRequestInput {
            actor_user_id,
            event_purchase_id,
            group_id,
            review_note: Some("Returned by bank transfer".to_string()),
        })
        .await
        .unwrap();
}

#[tokio::test]
async fn test_approve_refund_request_only_queues_durable_work() {
    // Setup identifiers and the durable queue expectation
    let actor_user_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_event_purchase_charge_model()
        .withf(move |purchase| *purchase == event_purchase_id)
        .times(1)
        .returning(|_| Ok(EventPurchaseChargeModel::DirectCharge));
    db.expect_queue_event_refund_request_approval()
        .withf(move |actor, group, purchase, note| {
            *actor == actor_user_id
                && *group == group_id
                && *purchase == event_purchase_id
                && note.as_deref() == Some("Approved by organizer")
        })
        .times(1)
        .returning(|_, _, _, _| Ok(()));

    let manager = sample_payments_manager(db, MockNotificationsManager::new(), None);

    // Approve the request without a configured provider
    manager
        .approve_refund_request(&ApproveRefundRequestInput {
            actor_user_id,
            event_purchase_id,
            group_id,
            review_note: Some("Approved by organizer".to_string()),
        })
        .await
        .unwrap();
}

#[tokio::test]
async fn test_approve_refund_request_propagates_queue_failure() {
    // Setup a durable queue failure
    let mut db = MockDB::new();
    db.expect_get_event_purchase_charge_model()
        .times(1)
        .returning(|_| Ok(EventPurchaseChargeModel::DirectCharge));
    db.expect_queue_event_refund_request_approval()
        .times(1)
        .returning(|_, _, _, _| Err(anyhow::anyhow!("queue unavailable")));
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), None);

    // Attempt to approve the request
    let err = manager
        .approve_refund_request(&ApproveRefundRequestInput {
            actor_user_id: Uuid::new_v4(),
            event_purchase_id: Uuid::new_v4(),
            group_id: Uuid::new_v4(),
            review_note: None,
        })
        .await
        .expect_err("durable refund queue failure to propagate");

    // Check the persistence failure remains visible
    assert_eq!(err.to_string(), "queue unavailable");
}

#[tokio::test]
async fn test_approve_refund_request_rejects_external_purchase_outside_group() {
    // Setup an external purchase that does not belong to the acting group
    let event_purchase_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_event_purchase_charge_model()
        .withf(move |purchase| *purchase == event_purchase_id)
        .times(1)
        .returning(|_| Ok(EventPurchaseChargeModel::External));
    db.expect_get_event_purchase_notification_context()
        .withf(move |group, purchase| *group == group_id && *purchase == event_purchase_id)
        .times(1)
        .returning(|_, _| Ok(None));
    db.expect_approve_external_event_refund_request().times(0);
    db.expect_queue_event_refund_request_approval().times(0);
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), None);

    // Attempt to approve the request
    let err = manager
        .approve_refund_request(&ApproveRefundRequestInput {
            actor_user_id: Uuid::new_v4(),
            event_purchase_id,
            group_id,
            review_note: None,
        })
        .await
        .expect_err("missing purchase to be rejected");

    // Check the rejection is user-facing and nothing was written
    assert!(
        matches!(err, PaymentsError::Rejected(ref message) if message == "refund request not found")
    );
}

#[tokio::test]
async fn test_complete_external_checkout_passes_welcome_payload_to_atomic_completion() {
    // Setup identifiers and the atomic completion receiving the welcome payload
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_event_purchase_notification_context()
        .withf(move |group, purchase| *group == group_id && *purchase == event_purchase_id)
        .times(1)
        .returning(move |_, _| {
            Ok(Some(EventPurchaseNotificationContext {
                community_id,
                event_id,
            }))
        });
    expect_event_notification_context(&mut db, community_id, event_id);
    db.expect_complete_external_event_purchase()
        .withf(
            move |actor, group, purchase, details, attachments, template| {
                *actor == actor_user_id
                    && *group == group_id
                    && *purchase == event_purchase_id
                    && details.as_deref() == Some("wire 123")
                    && attachments
                        .as_ref()
                        .is_some_and(|value| value.as_array().is_some_and(|items| items.len() == 1))
                    && template
                        .as_ref()
                        .is_some_and(|data| template_event_matches(data, event_id))
            },
        )
        .times(1)
        .returning(move |_, _, _, _, _, _| {
            Ok(CompletedEventPurchase {
                community_id,
                event_id,
                user_id,

                transitioned: None,
            })
        });

    // Complete the external checkout
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), None);
    manager
        .complete_external_checkout(
            actor_user_id,
            group_id,
            event_purchase_id,
            Some("wire 123".to_string()),
        )
        .await
        .unwrap();
}

#[tokio::test]
async fn test_complete_external_checkout_rejects_purchase_outside_group() {
    // Setup a purchase lookup scoped to a group that does not own it
    let event_purchase_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_event_purchase_notification_context()
        .withf(move |group, purchase| *group == group_id && *purchase == event_purchase_id)
        .times(1)
        .returning(|_, _| Ok(None));
    db.expect_complete_external_event_purchase().times(0);
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), None);

    // Attempt to complete the external checkout
    let err = manager
        .complete_external_checkout(Uuid::new_v4(), group_id, event_purchase_id, None)
        .await
        .expect_err("missing purchase to be rejected");

    // Check the rejection is user-facing and nothing was written
    assert!(matches!(err, PaymentsError::Rejected(ref message) if message == "purchase not found"));
}

#[tokio::test]
async fn test_complete_free_checkout_records_purchase_and_enqueues_notification() {
    // Setup checkout identifiers and notification context
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    // Setup free-purchase completion and notification context expectations
    let mut db = MockDB::new();
    db.expect_complete_free_event_purchase()
        .withf(move |purchase_id| *purchase_id == event_purchase_id)
        .times(1)
        .returning(move |_| {
            Ok(CompletedEventPurchase {
                community_id,
                event_id,
                user_id,

                transitioned: None,
            })
        });
    expect_event_notification_context(&mut db, community_id, event_id);

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
                    .is_some_and(|data| template_event_matches(data, event_id))
        })
        .times(1)
        .returning(|_| Box::pin(async { Ok(()) }));

    // Complete the free checkout
    let manager = sample_payments_manager(db, notifications_manager, None);

    manager
        .complete_free_checkout(community_id, event_id, event_purchase_id, user_id)
        .await
        .unwrap();
}

#[tokio::test]
async fn test_complete_payment_job_recovery_persists_recovery_evidence() {
    // Setup recovery identifiers and the durable completion expectation
    let actor_user_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let payment_job_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_complete_payment_job_recovery()
        .withf(move |input| {
            input.actor_user_id == actor_user_id
                && input.group_id == group_id
                && input.payment_job_id == payment_job_id
                && input.provider_object_id == "re_123"
                && input.recovery_note == "Refunded from the Stripe dashboard"
                && input.recovery_reference == "ticket-42"
        })
        .times(1)
        .returning(|_| Ok(()));

    // Complete the payment job recovery
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), None);
    manager
        .complete_payment_job_recovery(&PaymentJobRecovery {
            actor_user_id,
            group_id,
            payment_job_id,
            provider_object_id: "re_123".to_string(),
            recovery_note: "Refunded from the Stripe dashboard".to_string(),
            recovery_reference: "ticket-42".to_string(),
        })
        .await
        .unwrap();
}

#[tokio::test]
async fn test_complete_payment_job_recovery_propagates_database_failure() {
    // Setup a failing durable completion
    let mut db = MockDB::new();
    db.expect_complete_payment_job_recovery()
        .times(1)
        .returning(|_| Err(anyhow!("database failure")));

    // Complete the payment job recovery
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), None);
    let err = manager
        .complete_payment_job_recovery(&PaymentJobRecovery {
            actor_user_id: Uuid::new_v4(),
            group_id: Uuid::new_v4(),
            payment_job_id: Uuid::new_v4(),
            provider_object_id: "re_123".to_string(),
            recovery_note: "note".to_string(),
            recovery_reference: "reference".to_string(),
        })
        .await
        .unwrap_err();

    // Check the database failure remains visible
    assert_eq!(err.to_string(), "database failure");
}

#[tokio::test]
async fn test_complete_refund_recovery_composes_template_data_before_atomic_completion() {
    // Setup authoritative recovery and event context
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_event_purchase_refund_recovery_context()
        .times(1)
        .withf(move |group, purchase| *group == group_id && *purchase == event_purchase_id)
        .returning(move |_, _| {
            Ok(EventPurchaseRefundRecoveryContext {
                community_id,
                event_id,
                event_purchase_refund_id,
                notification_required: true,
            })
        });
    expect_event_notification_context(&mut db, community_id, event_id);
    db.expect_complete_event_purchase_refund_recovery()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == actor_user_id
                && input.group_id == group_id
                && input.event_purchase_refund_id == event_purchase_refund_id
                && input.recovery_reference == "bank-transfer-123"
                && input.recovery_note == "Verified bank receipt"
                && input
                    .notification_template_data
                    .as_ref()
                    .is_some_and(|data| approval_template_matches(data, event_id, false))
                && input.payment_provider == Some(PaymentProvider::Stripe)
        })
        .returning(|_| Ok(()));

    // Complete recovery through the same typed composer used by the refund worker
    let manager =
        sample_payments_manager(db, MockNotificationsManager::new(), Some(stripe_provider()));
    manager
        .complete_refund_recovery(&CompleteRefundRecoveryInput {
            actor_user_id,
            event_purchase_id,
            group_id,
            recovery_note: "Verified bank receipt".to_string(),
            recovery_reference: "bank-transfer-123".to_string(),
        })
        .await
        .unwrap();
}

#[tokio::test]
async fn test_complete_refund_recovery_skips_composition_after_local_finalization() {
    // Setup a recovery whose attendee notification was already finalized
    let actor_user_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_event_purchase_refund_recovery_context()
        .times(1)
        .returning(move |_, _| {
            Ok(EventPurchaseRefundRecoveryContext {
                community_id: Uuid::new_v4(),
                event_id: Uuid::new_v4(),
                event_purchase_refund_id,
                notification_required: false,
            })
        });
    db.expect_complete_event_purchase_refund_recovery()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == actor_user_id
                && input.group_id == group_id
                && input.event_purchase_refund_id == event_purchase_refund_id
                && input.notification_template_data.is_none()
                && input.payment_provider.is_none()
        })
        .returning(|_| Ok(()));

    // Complete recovery without loading event or theme template context
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), None);
    manager
        .complete_refund_recovery(&CompleteRefundRecoveryInput {
            actor_user_id,
            event_purchase_id,
            group_id,
            recovery_note: "Verified bank receipt".to_string(),
            recovery_reference: "bank-transfer-123".to_string(),
        })
        .await
        .unwrap();
}

#[tokio::test]
async fn test_get_or_create_checkout_redirect_url_creates_and_persists_session() {
    // Setup a checkout that requires a provider session
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let mut prepared_checkout =
        sample_prepared_event_checkout(event_id, event_purchase_id, event_ticket_type_id);
    prepared_checkout.purchase.discount_code = Some("SPRING".to_string());

    // Setup checkout attachment and canonical reload expectations
    let mut db = MockDB::new();
    db.expect_attach_checkout_session_to_event_purchase()
        .withf(move |input| {
            input.event_purchase_id == event_purchase_id
                && input.payment_provider == PaymentProvider::Stripe
                && input.provider_session_id == "cs_test_123"
        })
        .times(1)
        .returning(|_| Ok(()));
    db.expect_get_event_purchase_summary()
        .withf(move |purchase_id| *purchase_id == event_purchase_id)
        .times(1)
        .returning(move |_| {
            Ok(checkout_purchase_summary(
                event_purchase_id,
                event_ticket_type_id,
                Some("https://example.test/checkout".to_string()),
            ))
        });

    // Setup provider checkout creation expectations
    let mut provider = stripe_provider();
    provider
        .expect_create_checkout_session()
        .withf(move |input| {
            input.amount_minor == 2_500
                && input.discount_code.as_deref() == Some("SPRING")
                && input.event_id == event_id
                && input.provisional_platform_fee_amount_minor == 62
                && input.purchase_id == event_purchase_id
                && input.seller.connected_account_id == "acct_test"
                && input.user_id == user_id
        })
        .times(1)
        .returning(|_| {
            Box::pin(async {
                Ok(CheckoutSession {
                    provider_session_id: "cs_test_123".to_string(),
                    redirect_url: "https://example.test/checkout".to_string(),
                    ..CheckoutSession::default()
                })
            })
        });

    // Create the checkout session
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), Some(provider));
    let redirect_url = manager
        .get_or_create_checkout_redirect_url(&prepared_checkout, user_id)
        .await
        .unwrap();

    // Check the canonical persisted URL is returned
    assert_eq!(redirect_url, "https://example.test/checkout");
}

#[tokio::test]
async fn test_get_or_create_checkout_redirect_url_allows_manual_tax_without_tax_code() {
    // Setup a manual-tax checkout whose rates do not use a Product tax code
    let event_purchase_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let mut prepared_checkout =
        sample_prepared_event_checkout(Uuid::new_v4(), event_purchase_id, event_ticket_type_id);
    prepared_checkout.manual_tax_rate_ids = Some(vec!["txr_test".to_string()]);
    prepared_checkout.tax_calculation_mode = Some(TicketTaxCalculationMode::Manual);
    prepared_checkout.tax_code = None;

    // Setup checkout attachment and canonical reload expectations
    let mut db = MockDB::new();
    db.expect_attach_checkout_session_to_event_purchase()
        .times(1)
        .returning(|_| Ok(()));
    db.expect_get_event_purchase_summary().times(1).returning(move |_| {
        Ok(checkout_purchase_summary(
            event_purchase_id,
            event_ticket_type_id,
            Some("https://example.test/manual-checkout".to_string()),
        ))
    });

    // Require the provider contract to preserve the mode-specific optional tax code
    let mut provider = stripe_provider();
    provider
        .expect_create_checkout_session()
        .withf(|input| {
            input.tax_calculation_mode == TicketTaxCalculationMode::Manual
                && matches!(
                    input.manual_tax_rate_ids.as_deref(),
                    Some([rate_id]) if rate_id == "txr_test"
                )
                && input.tax_code.is_none()
        })
        .times(1)
        .returning(|_| {
            Box::pin(async {
                Ok(CheckoutSession {
                    provider_session_id: "cs_test_manual".to_string(),
                    redirect_url: "https://example.test/manual-checkout".to_string(),
                    ..CheckoutSession::default()
                })
            })
        });

    // Create and persist the manual-tax Checkout Session
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), Some(provider));
    let redirect_url = manager
        .get_or_create_checkout_redirect_url(&prepared_checkout, Uuid::new_v4())
        .await
        .expect("manual-tax checkout without a tax code to succeed");

    // Check the canonical provider URL is returned
    assert_eq!(redirect_url, "https://example.test/manual-checkout");
}

#[tokio::test]
async fn test_get_or_create_checkout_redirect_url_returns_canonical_url_after_racing_attach() {
    // Setup a checkout whose concurrent request wins the canonical URL
    let event_purchase_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let prepared_checkout =
        sample_prepared_event_checkout(Uuid::new_v4(), event_purchase_id, event_ticket_type_id);

    // Setup attachment and canonical purchase reload expectations
    let mut db = MockDB::new();
    db.expect_attach_checkout_session_to_event_purchase()
        .withf(move |input| {
            input.event_purchase_id == event_purchase_id
                && input.payment_provider == PaymentProvider::Stripe
                && input.provider_session_id == "cs_test_racing"
                && input.redirect_url == "https://example.test/checkout/racing"
        })
        .times(1)
        .returning(|_| Ok(()));
    db.expect_get_event_purchase_summary()
        .withf(move |purchase_id| *purchase_id == event_purchase_id)
        .times(1)
        .returning(move |_| {
            Ok(checkout_purchase_summary(
                event_purchase_id,
                event_ticket_type_id,
                Some("https://example.test/checkout/canonical".to_string()),
            ))
        });

    // Setup the provider session created by the losing request
    let mut provider = stripe_provider();
    provider.expect_create_checkout_session().times(1).returning(|_| {
        Box::pin(async {
            Ok(CheckoutSession {
                provider_session_id: "cs_test_racing".to_string(),
                redirect_url: "https://example.test/checkout/racing".to_string(),
                ..CheckoutSession::default()
            })
        })
    });

    // Create the checkout and reload its canonical persisted state
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), Some(provider));
    let redirect_url = manager
        .get_or_create_checkout_redirect_url(&prepared_checkout, Uuid::new_v4())
        .await
        .expect("canonical checkout URL to be returned");

    // Check the concurrent winner remains authoritative
    assert_eq!(redirect_url, "https://example.test/checkout/canonical");
}

#[tokio::test]
async fn test_get_or_create_checkout_redirect_url_returns_error_when_checkout_url_is_missing() {
    // Setup a checkout whose persisted purchase has no canonical URL
    let event_purchase_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let prepared_checkout =
        sample_prepared_event_checkout(Uuid::new_v4(), event_purchase_id, event_ticket_type_id);

    // Setup successful attachment followed by an incomplete purchase reload
    let mut db = MockDB::new();
    db.expect_attach_checkout_session_to_event_purchase()
        .times(1)
        .returning(|_| Ok(()));
    db.expect_get_event_purchase_summary()
        .withf(move |purchase_id| *purchase_id == event_purchase_id)
        .times(1)
        .returning(move |_| {
            Ok(checkout_purchase_summary(
                event_purchase_id,
                event_ticket_type_id,
                None,
            ))
        });

    // Setup provider checkout creation
    let mut provider = stripe_provider();
    provider.expect_create_checkout_session().times(1).returning(|_| {
        Box::pin(async {
            Ok(CheckoutSession {
                provider_session_id: "cs_test_123".to_string(),
                redirect_url: "https://example.test/checkout".to_string(),
                ..CheckoutSession::default()
            })
        })
    });

    // Attempt to create the checkout without a canonical persisted URL
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), Some(provider));
    let err = manager
        .get_or_create_checkout_redirect_url(&prepared_checkout, Uuid::new_v4())
        .await
        .expect_err("missing canonical checkout URL to fail");

    // Check the persistence invariant is explicit
    assert_eq!(
        err.to_string(),
        "provider checkout URL is missing after checkout creation"
    );
}

#[tokio::test]
async fn test_get_or_create_checkout_redirect_url_returns_error_when_payments_are_unconfigured() {
    // Setup a checkout that requires a provider session
    let prepared_checkout =
        sample_prepared_event_checkout(Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4());
    let mut db = MockDB::new();
    db.expect_get_event_purchase_summary().never();

    // Attempt checkout creation without a configured provider
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), None);
    let err = manager
        .get_or_create_checkout_redirect_url(&prepared_checkout, Uuid::new_v4())
        .await
        .expect_err("unconfigured payments to reject checkout creation");

    // Check no fallback hides the configuration error
    assert_eq!(err.to_string(), "payments are not configured");
}

#[tokio::test]
async fn test_get_or_create_checkout_redirect_url_requires_paid_currency() {
    // Setup a paid checkout without a currency snapshot
    let mut prepared_checkout =
        sample_prepared_event_checkout(Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4());
    prepared_checkout.purchase.currency_code = None;

    // Check the paid-only requirement fails before any provider request
    assert_eq!(
        checkout_contract_error(&prepared_checkout).await,
        "paid checkout is missing currency_code"
    );
}

#[tokio::test]
async fn test_get_or_create_checkout_redirect_url_requires_paid_recipient() {
    // Setup a paid checkout without a group recipient
    let mut prepared_checkout =
        sample_prepared_event_checkout(Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4());
    prepared_checkout.seller = None;

    // Check the paid-only requirement fails before any provider request
    assert_eq!(
        checkout_contract_error(&prepared_checkout).await,
        "paid checkout is missing a fiscal sponsor seller"
    );
}

#[tokio::test]
async fn test_get_or_create_checkout_redirect_url_requires_tax_behavior() {
    // Setup a paid checkout without its ticket tax behavior snapshot
    let mut prepared_checkout =
        sample_prepared_event_checkout(Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4());
    prepared_checkout.tax_behavior = None;

    // Check the paid-only requirement fails before any provider request
    assert_eq!(
        checkout_contract_error(&prepared_checkout).await,
        "paid checkout is missing tax behavior"
    );
}

#[tokio::test]
async fn test_get_or_create_checkout_redirect_url_requires_tax_calculation_mode() {
    // Setup a paid checkout without its tax calculation mode snapshot
    let mut prepared_checkout =
        sample_prepared_event_checkout(Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4());
    prepared_checkout.tax_calculation_mode = None;

    // Check the paid-only requirement fails before any provider request
    assert_eq!(
        checkout_contract_error(&prepared_checkout).await,
        "paid checkout is missing tax calculation mode"
    );
}

#[tokio::test]
async fn test_get_or_create_checkout_redirect_url_requires_tax_code_for_automatic_tax() {
    // Setup an automatic-tax checkout without its immutable Product tax code
    let mut prepared_checkout =
        sample_prepared_event_checkout(Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4());
    prepared_checkout.tax_code = None;

    // Check invalid state fails before any provider request
    assert_eq!(
        checkout_contract_error(&prepared_checkout).await,
        "paid checkout is missing ticket tax code"
    );
}

#[tokio::test]
async fn test_get_or_create_checkout_redirect_url_requires_venue_snapshot() {
    // Setup a paid checkout without its venue snapshot
    let mut prepared_checkout =
        sample_prepared_event_checkout(Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4());
    prepared_checkout.venue = None;

    // Check the paid-only requirement fails before any provider request
    assert_eq!(
        checkout_contract_error(&prepared_checkout).await,
        "paid checkout is missing venue snapshot"
    );
}

#[tokio::test]
async fn test_get_or_create_checkout_redirect_url_reuses_existing_url_without_provider() {
    // Setup a checkout with an existing provider URL
    let existing_url = "https://example.test/checkout".to_string();
    let mut prepared_checkout =
        sample_prepared_event_checkout(Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4());
    prepared_checkout.purchase.provider_checkout_url = Some(existing_url.clone());

    // Guard against database access before reusing the URL
    let mut db = MockDB::new();
    db.expect_get_event_purchase_summary().never();

    // Reuse the URL without a configured provider
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), None);
    let redirect_url = manager
        .get_or_create_checkout_redirect_url(&prepared_checkout, Uuid::new_v4())
        .await
        .unwrap();

    // Check the existing URL is preserved
    assert_eq!(redirect_url, existing_url);
}

#[tokio::test]
async fn test_get_purchase_document_url_hides_documents_not_owned_by_attendee() {
    // Setup a document lookup that is not owned by the attendee
    let mut db = MockDB::new();
    db.expect_get_user_purchase_document_context()
        .times(1)
        .returning(|_, _, _| Ok(None));
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), None);

    // Attempt to load the unavailable purchase document
    let url = manager
        .get_purchase_document_url(Uuid::new_v4(), Uuid::new_v4(), None)
        .await
        .unwrap();

    // Check the document remains hidden
    assert!(url.is_none());
}

#[tokio::test]
async fn test_get_purchase_document_url_retrieves_current_account_scoped_credit_note() {
    // Setup credit-note identifiers and attendee-owned document context
    let event_purchase_credit_note_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_user_purchase_document_context()
        .withf(move |user, purchase, credit_note| {
            *user == user_id
                && *purchase == event_purchase_id
                && *credit_note == Some(event_purchase_credit_note_id)
        })
        .times(1)
        .returning(|_, _, _| {
            Ok(Some(UserPurchaseDocumentContext {
                connected_seller_id: "acct_sponsor".to_string(),
                payment_provider: PaymentProvider::Stripe,
                provider_document_id: "cn_purchase".to_string(),
            }))
        });

    // Setup account-scoped credit-note retrieval
    let mut provider = stripe_provider();
    provider
        .expect_get_financial_document()
        .withf(|input| {
            input.connected_seller_id == "acct_sponsor"
                && input.kind == FinancialDocumentKind::CreditNote
                && input.provider_document_id == "cn_purchase"
        })
        .times(1)
        .returning(|_| {
            Box::pin(async {
                Ok(FinancialDocument {
                    hosted_url: None,
                    pdf_url: Some("https://credit.test/current.pdf".to_string()),
                })
            })
        });
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), Some(provider));

    // Retrieve the current credit-note URL
    let url = manager
        .get_purchase_document_url(
            user_id,
            event_purchase_id,
            Some(event_purchase_credit_note_id),
        )
        .await
        .unwrap();

    // Check the provider PDF URL is returned
    assert_eq!(url.as_deref(), Some("https://credit.test/current.pdf"));
}

#[tokio::test]
async fn test_get_purchase_document_url_retrieves_current_account_scoped_invoice() {
    // Setup invoice identifiers and attendee-owned document context
    let event_purchase_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_user_purchase_document_context()
        .withf(move |user, purchase, credit_note| {
            *user == user_id && *purchase == event_purchase_id && credit_note.is_none()
        })
        .times(1)
        .returning(|_, _, _| {
            Ok(Some(UserPurchaseDocumentContext {
                connected_seller_id: "acct_sponsor".to_string(),
                payment_provider: PaymentProvider::Stripe,
                provider_document_id: "in_purchase".to_string(),
            }))
        });

    // Setup account-scoped invoice retrieval
    let mut provider = stripe_provider();
    provider
        .expect_get_financial_document()
        .withf(|input| {
            input.connected_seller_id == "acct_sponsor"
                && input.kind == FinancialDocumentKind::Invoice
                && input.provider_document_id == "in_purchase"
        })
        .times(1)
        .returning(|_| {
            Box::pin(async {
                Ok(FinancialDocument {
                    hosted_url: Some("https://invoice.test/current".to_string()),
                    pdf_url: Some("https://invoice.test/current.pdf".to_string()),
                })
            })
        });
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), Some(provider));

    // Retrieve the current invoice URL
    let url = manager
        .get_purchase_document_url(user_id, event_purchase_id, None)
        .await
        .unwrap();

    // Check the provider-hosted URL is preferred
    assert_eq!(url.as_deref(), Some("https://invoice.test/current"));
}

#[tokio::test]
async fn test_get_purchase_document_url_rejects_document_without_current_url() {
    // Setup an attendee-owned invoice whose provider document has no URL
    let mut db = MockDB::new();
    db.expect_get_user_purchase_document_context()
        .times(1)
        .returning(|_, _, _| {
            Ok(Some(UserPurchaseDocumentContext {
                connected_seller_id: "acct_sponsor".to_string(),
                payment_provider: PaymentProvider::Stripe,
                provider_document_id: "in_purchase".to_string(),
            }))
        });
    let mut provider = stripe_provider();
    provider.expect_get_financial_document().times(1).returning(|_| {
        Box::pin(async {
            Ok(FinancialDocument {
                hosted_url: None,
                pdf_url: None,
            })
        })
    });
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), Some(provider));

    // Attempt to retrieve the current invoice URL
    let err = manager
        .get_purchase_document_url(Uuid::new_v4(), Uuid::new_v4(), None)
        .await
        .expect_err("document without a current URL to fail");

    // Check the missing provider URL is explicit
    assert_eq!(
        err.to_string(),
        "provider financial document has no current URL"
    );
}

#[tokio::test]
async fn test_handle_connected_webhook_verifies_connected_account_endpoint() {
    // Setup a provider verifier scoped to the connected-account endpoint
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_verify_and_parse_webhook()
        .withf(|endpoint, headers, body| {
            *endpoint == PaymentsWebhookEndpoint::ConnectedAccount
                && has_test_signature_header(headers)
                && body == "payload"
        })
        .times(1)
        .returning(|_, _, _| Ok(PaymentsWebhookEvent::Noop));

    // Verify and dispatch the connected-account webhook
    let manager = sample_payments_manager(
        MockDB::new(),
        MockNotificationsManager::new(),
        Some(provider),
    );
    let result = manager
        .handle_connected_webhook(&sample_webhook_headers(), "payload")
        .await;

    // Check the verified no-op is acknowledged
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_handle_webhook_accepts_verified_noop_event() {
    // Setup a provider verifier that returns an irrelevant signed event
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_verify_and_parse_webhook()
        .withf(|endpoint, headers, body| {
            *endpoint == PaymentsWebhookEndpoint::PlatformAccount
                && has_test_signature_header(headers)
                && body == "payload"
        })
        .times(1)
        .returning(|_, _, _| Ok(PaymentsWebhookEvent::Noop));

    // Verify and dispatch the webhook
    let manager = sample_payments_manager(
        MockDB::new(),
        MockNotificationsManager::new(),
        Some(provider),
    );
    let result = manager.handle_webhook(&sample_webhook_headers(), "payload").await;

    // Check a verified no-op is acknowledged
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_handle_webhook_returns_invalid_payload_when_verification_fails() {
    // Setup a provider signature verification failure
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_verify_and_parse_webhook()
        .withf(|endpoint, headers, body| {
            *endpoint == PaymentsWebhookEndpoint::PlatformAccount
                && has_test_signature_header(headers)
                && body == "payload"
        })
        .times(1)
        .returning(|_, _, _| Err(anyhow::anyhow!("invalid signature")));

    // Attempt to dispatch the invalid webhook
    let manager = sample_payments_manager(
        MockDB::new(),
        MockNotificationsManager::new(),
        Some(provider),
    );
    let err = manager
        .handle_webhook(&sample_webhook_headers(), "payload")
        .await
        .expect_err("invalid webhook signature to fail");

    // Check verification failures use the public invalid-payload error
    assert!(matches!(err, HandleWebhookError::InvalidPayload));
}

#[tokio::test]
async fn test_handle_webhook_returns_not_configured_without_provider() {
    // Attempt webhook verification without a configured provider
    let manager = sample_payments_manager(MockDB::new(), MockNotificationsManager::new(), None);
    let err = manager
        .handle_webhook(&sample_webhook_headers(), "payload")
        .await
        .expect_err("unconfigured webhook handling to fail");

    // Check configuration failures remain distinguishable
    assert!(matches!(err, HandleWebhookError::PaymentsNotConfigured));
}

#[tokio::test]
async fn test_prepare_checkout_rejects_missing_ticket_type_before_any_write() {
    // Setup the database, which must not be reached
    let mut db = MockDB::new();
    db.expect_prepare_event_checkout_purchase().never();

    // Prepare checkout without a ticket selection
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), None);
    let err = manager
        .prepare_checkout(
            Uuid::new_v4(),
            Uuid::new_v4(),
            Uuid::new_v4(),
            &CheckoutInput::default(),
        )
        .await
        .unwrap_err();

    // Check the rejection carries the user-facing message
    assert!(
        matches!(err, PaymentsError::Rejected(message) if message == "ticket type is required")
    );
}

#[tokio::test]
async fn test_prepare_checkout_returns_conflict_code() {
    // Setup identifiers and a sold-out checkout attempt
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_prepare_event_checkout_purchase()
        .withf(move |cid, input| {
            *cid == community_id
                && input.event_id == event_id
                && input.event_ticket_type_id == event_ticket_type_id
                && input.user_id == user_id
        })
        .times(1)
        .returning(|_, _| {
            Ok(PrepareEventCheckoutPurchaseResult::Conflict(
                PrepareEventCheckoutPurchaseConflict::TicketTypeSoldOut,
            ))
        });

    // Prepare the checkout
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), None);
    let outcome = manager
        .prepare_checkout(
            community_id,
            event_id,
            user_id,
            &CheckoutInput {
                event_ticket_type_id: Some(event_ticket_type_id),
                ..CheckoutInput::default()
            },
        )
        .await
        .unwrap();

    // Check the conflict uses the stable kebab-case code
    assert_eq!(
        outcome,
        PrepareCheckoutOutcome::Conflict("ticket-type-sold-out".to_string())
    );
}

#[tokio::test]
async fn test_prepare_checkout_returns_prepared_checkout_with_manager_configuration() {
    // Setup identifiers and the provider-configured manager
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let mut prepared_checkout =
        sample_prepared_event_checkout(event_id, event_purchase_id, event_ticket_type_id);
    prepared_checkout.purchase.discount_code = Some("EARLY".to_string());
    let expected_checkout = prepared_checkout.clone();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_prepare_event_checkout_purchase()
        .withf(move |cid, input| {
            *cid == community_id
                && input.event_id == event_id
                && input.event_ticket_type_id == event_ticket_type_id
                && input.platform_fee_bps == 250
                && input.user_id == user_id
                && input.admission_offer_id.is_none()
                && input.discount_code.as_deref() == Some("EARLY")
                && input.payment_provider == Some(PaymentProvider::Stripe)
                && input.registration_answers.is_none()
        })
        .times(1)
        .returning(move |_, _| {
            Ok(PrepareEventCheckoutPurchaseResult::Prepared(Box::new(
                prepared_checkout.clone(),
            )))
        });

    // Prepare the checkout
    let manager =
        sample_payments_manager(db, MockNotificationsManager::new(), Some(stripe_provider()));
    let outcome = manager
        .prepare_checkout(
            community_id,
            event_id,
            user_id,
            &CheckoutInput {
                discount_code: Some("EARLY".to_string()),
                event_ticket_type_id: Some(event_ticket_type_id),
                ..CheckoutInput::default()
            },
        )
        .await
        .unwrap();

    // Check the prepared checkout is returned unchanged
    assert_eq!(
        outcome,
        PrepareCheckoutOutcome::Prepared(Box::new(expected_checkout))
    );
}

#[tokio::test]
async fn test_reject_refund_request_persists_rejection_and_enqueues_notification() {
    // Setup review identifiers and notification context
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let target_user_id = Uuid::new_v4();

    // Setup rejection persistence and context expectations
    let mut db = MockDB::new();
    db.expect_reject_event_refund_request()
        .withf(move |actor, group, purchase, note| {
            *actor == actor_user_id
                && *group == group_id
                && *purchase == event_purchase_id
                && note == "Not eligible"
        })
        .times(1)
        .returning(move |_, _, _, _| {
            Ok(CompletedEventPurchase {
                community_id,
                event_id,
                user_id: target_user_id,

                transitioned: None,
            })
        });
    expect_event_notification_context(&mut db, community_id, event_id);

    // Setup the attendee rejection notification expectation
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager
        .expect_enqueue()
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventRefundRejected)
                && notification.recipients == vec![target_user_id]
                && notification
                    .template_data
                    .as_ref()
                    .and_then(|data| data.get("rejection_reason"))
                    .and_then(serde_json::Value::as_str)
                    == Some("Not eligible")
        })
        .times(1)
        .returning(|_| Box::pin(async { Ok(()) }));
    // Reject the request and enqueue its notification
    let manager = sample_payments_manager(db, notifications_manager, None);

    manager
        .reject_refund_request(&RejectRefundRequestInput {
            actor_user_id,
            event_purchase_id,
            group_id,
            review_note: "  Not eligible  ".to_string(),
        })
        .await
        .unwrap();
}

#[tokio::test]
async fn test_request_refund_records_request_with_notification_context() {
    // Setup refund request identifiers
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    // Setup notification context and request persistence expectations
    let mut db = MockDB::new();
    expect_event_notification_context(&mut db, community_id, event_id);
    db.expect_request_event_refund()
        .withf(move |community, event, user, reason, template_data| {
            *community == community_id
                && *event == event_id
                && *user == user_id
                && reason.as_deref() == Some("Need to cancel")
                && template_event_matches(template_data, event_id)
        })
        .times(1)
        .returning(|_, _, _, _, _| Ok(()));

    // Record the attendee refund request
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), None);

    manager
        .request_refund(&RequestRefundInput {
            community_id,
            event_id,
            user_id,
            requested_reason: Some("Need to cancel".to_string()),
        })
        .await
        .unwrap();
}

#[tokio::test]
async fn test_request_refund_returns_error_when_notification_context_load_fails() {
    // Setup a notification context load failure and guard request persistence
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_event_summary_by_id().never();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Err(anyhow::anyhow!("context unavailable")));
    db.expect_request_event_refund().never();

    // Attempt to create a request without its durable notification payload
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), None);
    let err = manager
        .request_refund(&RequestRefundInput {
            community_id,
            event_id,
            user_id: Uuid::new_v4(),
            requested_reason: Some("Need to cancel".to_string()),
        })
        .await
        .expect_err("missing notification context to stop request persistence");

    // Check the context error remains visible
    assert_eq!(err.to_string(), "context unavailable");
}

#[tokio::test]
async fn test_validate_fiscal_sponsor_forwards_provider_account_and_tax_jurisdiction() {
    // Setup a provider expectation for the selected fiscal sponsor
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_validate_fiscal_sponsor()
        .withf(|input| {
            input.connected_seller_id == "acct_sponsor"
                && input.provider == PaymentProvider::Stripe
                && input.automatic_tax_jurisdiction.as_ref().is_some_and(|jurisdiction| {
                    jurisdiction.country_code == "US"
                        && jurisdiction.state_code.as_deref() == Some("CA")
                })
        })
        .times(1)
        .returning(|_| Box::pin(async { Ok(()) }));
    let manager = sample_payments_manager(
        MockDB::new(),
        MockNotificationsManager::new(),
        Some(provider),
    );

    // Validate automatic-tax readiness through the manager boundary
    let jurisdiction = TicketTaxJurisdiction {
        country_code: "US".to_string(),
        state_code: Some("CA".to_string()),
    };
    manager
        .validate_fiscal_sponsor(
            &GroupPaymentRecipient {
                provider: PaymentProvider::Stripe,
                recipient_id: "acct_sponsor".to_string(),
                seller_display_name: "Sponsor".to_string(),
            },
            Some(jurisdiction),
        )
        .await
        .expect("provider readiness to be forwarded");
}

#[tokio::test]
async fn test_validate_tax_rates_forwards_venue_jurisdiction() {
    // Setup provider expectations for the selected sponsor, rates, and venue
    let mut provider = stripe_provider();
    provider
        .expect_validate_tax_rates()
        .withf(|input| {
            input.connected_seller_id == "acct_sponsor"
                && input.manual_tax_rate_ids == ["txr_state"]
                && input.tax_behavior == TicketTaxBehavior::Exclusive
                && input.jurisdiction.as_ref().is_some_and(|jurisdiction| {
                    jurisdiction.country_code == "US"
                        && jurisdiction.state_code.as_deref() == Some("CA")
                })
        })
        .times(1)
        .returning(|_| Box::pin(async { Ok(()) }));
    let manager = sample_payments_manager(
        MockDB::new(),
        MockNotificationsManager::new(),
        Some(provider),
    );
    let jurisdiction = TicketTaxJurisdiction {
        country_code: "US".to_string(),
        state_code: Some("CA".to_string()),
    };
    let recipient = GroupPaymentRecipient {
        provider: PaymentProvider::Stripe,
        recipient_id: "acct_sponsor".to_string(),
        seller_display_name: "Sponsor".to_string(),
    };

    // Validate manual rates through the manager boundary
    manager
        .validate_tax_rates(
            &recipient,
            &["txr_state".to_string()],
            TicketTaxBehavior::Exclusive,
            Some(jurisdiction),
        )
        .await
        .expect("manual Tax Rate jurisdiction to be forwarded");
}

#[tokio::test]
async fn test_ensure_automatic_tax_readiness_reuses_cached_location_without_state() {
    // Setup a normalized venue and matching account-scoped cache entry
    let recipient = GroupPaymentRecipient {
        provider: PaymentProvider::Stripe,
        recipient_id: "acct_sponsor".to_string(),
        seller_display_name: "Sponsor".to_string(),
    };
    let venue = TicketVenue {
        address: " 123 Example Street ".to_string(),
        city: " Example City ".to_string(),
        country_code: " pt ".to_string(),
        name: " Example Venue ".to_string(),
        zip_code: " 12345 ".to_string(),
        state_code: None,
        state_name: None,
    };
    let mut db = MockDB::new();
    db.expect_get_payment_provider_tax_location()
        .withf(|provider, seller, fingerprint| {
            *provider == PaymentProvider::Stripe
                && seller == "acct_sponsor"
                && !fingerprint.is_empty()
        })
        .times(1)
        .returning(|_, _, _| Ok(Some("loc_cached".to_string())));
    db.expect_upsert_payment_provider_tax_location().never();

    // Setup provider validation and cache reuse expectations
    let mut provider = stripe_provider();
    provider
        .expect_validate_fiscal_sponsor()
        .withf(|input| {
            input.connected_seller_id == "acct_sponsor"
                && input.automatic_tax_jurisdiction.as_ref().is_some_and(|jurisdiction| {
                    jurisdiction.country_code == "PT" && jurisdiction.state_code.is_none()
                })
        })
        .times(1)
        .returning(|_| Box::pin(async { Ok(()) }));
    provider
        .expect_ensure_performance_location()
        .withf(|input| {
            input.connected_seller_id == "acct_sponsor"
                && input.venue.country_code == "PT"
                && input.venue.state_code.is_none()
                && input.cached_fingerprint.is_some()
                && input.cached_provider_tax_location_id.as_deref() == Some("loc_cached")
        })
        .times(1)
        .returning(|input| {
            let fingerprint = input.venue.performance_location_fingerprint();
            Box::pin(async move {
                Ok(AutomaticTaxReadiness {
                    cached: true,
                    fingerprint,
                    provider_tax_location_id: "loc_cached".to_string(),
                    state_code: None,
                })
            })
        });
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), Some(provider));

    // Resolve readiness through the shared manager boundary
    let readiness = manager
        .ensure_automatic_tax_readiness(&recipient, &venue)
        .await
        .expect("matching cached location to be reused");

    assert!(readiness.cached);
    assert_eq!(readiness.provider_tax_location_id, "loc_cached");
    assert_eq!(readiness.state_code, None);
}

#[tokio::test]
async fn test_ensure_automatic_tax_readiness_reports_all_incomplete_venue_fields() {
    // Setup a matching provider without allowing remote validation
    let mut provider = stripe_provider();
    provider.expect_validate_fiscal_sponsor().never();
    provider.expect_ensure_performance_location().never();
    let manager = sample_payments_manager(
        MockDB::new(),
        MockNotificationsManager::new(),
        Some(provider),
    );

    // Check every required persisted venue field is returned for correction
    let error = manager
        .ensure_automatic_tax_readiness(
            &GroupPaymentRecipient {
                provider: PaymentProvider::Stripe,
                recipient_id: "acct_sponsor".to_string(),
                seller_display_name: "Sponsor".to_string(),
            },
            &TicketVenue::default(),
        )
        .await
        .expect_err("empty venue to be rejected locally");

    assert!(matches!(
        error,
        AutomaticTaxReadinessError::IncompleteVenue { fields }
            if fields == [
                "venue_address",
                "venue_city",
                "venue_country_code",
                "venue_name",
                "venue_zip_code",
            ]
    ));
}

#[tokio::test]
async fn test_ensure_automatic_tax_readiness_maps_fiscal_sponsor_readiness_failure() {
    // Setup a sponsor whose provider readiness check fails
    let mut db = MockDB::new();
    db.expect_get_payment_provider_tax_location().never();
    let mut provider = stripe_provider();
    provider.expect_validate_fiscal_sponsor().times(1).returning(|_| {
        Box::pin(async {
            Err(FiscalSponsorReadinessError::NotReady(
                "fiscal sponsor Stripe Tax settings are not active".to_string(),
            ))
        })
    });
    provider.expect_ensure_performance_location().never();
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), Some(provider));

    // Resolve readiness for a complete venue
    let error = manager
        .ensure_automatic_tax_readiness(&sample_group_payment_recipient(), &sample_ticket_venue())
        .await
        .expect_err("unready sponsor to be rejected");

    // Check the organizer-correctable provider message is preserved
    assert!(matches!(
        error,
        AutomaticTaxReadinessError::FiscalSponsorNotReady(message)
            if message == "fiscal sponsor Stripe Tax settings are not active"
    ));
}

#[tokio::test]
async fn test_ensure_automatic_tax_readiness_persists_new_location() {
    // Setup a venue without a cached provider location
    let mut db = MockDB::new();
    db.expect_get_payment_provider_tax_location()
        .times(1)
        .returning(|_, _, _| Ok(None));
    db.expect_upsert_payment_provider_tax_location()
        .withf(|provider, seller, fingerprint, location_id, venue| {
            *provider == PaymentProvider::Stripe
                && seller == "acct_test"
                && fingerprint == "fingerprint_created"
                && location_id == "loc_created"
                && *venue == sample_ticket_venue()
        })
        .times(1)
        .returning(|_, _, _, _, _| Ok(()));

    // Setup provider validation and location creation
    let mut provider = stripe_provider();
    provider
        .expect_validate_fiscal_sponsor()
        .times(1)
        .returning(|_| Box::pin(async { Ok(()) }));
    provider
        .expect_ensure_performance_location()
        .withf(|input| {
            input.cached_fingerprint.is_none() && input.cached_provider_tax_location_id.is_none()
        })
        .times(1)
        .returning(|_| {
            Box::pin(async {
                Ok(AutomaticTaxReadiness {
                    cached: false,
                    fingerprint: "fingerprint_created".to_string(),
                    provider_tax_location_id: "loc_created".to_string(),
                    state_code: Some("CA".to_string()),
                })
            })
        });
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), Some(provider));

    // Resolve readiness through the shared manager boundary
    let readiness = manager
        .ensure_automatic_tax_readiness(&sample_group_payment_recipient(), &sample_ticket_venue())
        .await
        .expect("new location to be created and cached");

    // Check the created location is returned
    assert!(!readiness.cached);
    assert_eq!(readiness.provider_tax_location_id, "loc_created");
}

#[tokio::test]
async fn test_ensure_automatic_tax_readiness_rejects_invalid_country_code() {
    // Setup a provider that must not be contacted for an invalid venue country
    let mut provider = stripe_provider();
    provider.expect_validate_fiscal_sponsor().never();
    provider.expect_ensure_performance_location().never();
    let manager = sample_payments_manager(
        MockDB::new(),
        MockNotificationsManager::new(),
        Some(provider),
    );

    // Resolve readiness for a venue whose country is not an ISO alpha-2 code
    let venue = TicketVenue {
        country_code: "USA".to_string(),
        ..sample_ticket_venue()
    };
    let error = manager
        .ensure_automatic_tax_readiness(&sample_group_payment_recipient(), &venue)
        .await
        .expect_err("invalid venue country to be rejected locally");

    // Check the normalized rejected country is reported
    assert!(matches!(
        error,
        AutomaticTaxReadinessError::CountryInvalid { country_code } if country_code == "USA"
    ));
}

#[tokio::test]
async fn test_list_tax_rates_forwards_recipient_account_and_tax_behavior() {
    // Setup the provider listing for the recipient account
    let rate = TicketTaxRate {
        display_name: "Sales tax".to_string(),
        id: "txr_state".to_string(),
        inclusive: false,
        percentage: "8.875".to_string(),

        jurisdiction: Some("California".to_string()),
    };
    let listed_rate = rate.clone();
    let mut provider = stripe_provider();
    provider
        .expect_list_tax_rates()
        .withf(|input| {
            input.connected_seller_id == "acct_test"
                && input.tax_behavior == TicketTaxBehavior::Exclusive
        })
        .times(1)
        .returning(move |_| {
            let listed_rate = listed_rate.clone();
            Box::pin(async move { Ok(vec![listed_rate]) })
        });
    let manager = sample_payments_manager(
        MockDB::new(),
        MockNotificationsManager::new(),
        Some(provider),
    );

    // List the recipient's rates through the manager boundary
    let rates = manager
        .list_tax_rates(
            &sample_group_payment_recipient(),
            TicketTaxBehavior::Exclusive,
        )
        .await
        .expect("Tax Rates to be listed");

    // Check the provider rates are returned unchanged
    assert_eq!(rates, vec![rate]);
}

// Helpers.

/// Returns the error raised by checkout creation for an incomplete prepared checkout.
async fn checkout_contract_error(prepared_checkout: &PreparedEventCheckout) -> String {
    let mut provider = MockPaymentsProvider::new();
    provider.expect_create_checkout_session().never();
    let manager = sample_payments_manager(
        MockDB::new(),
        MockNotificationsManager::new(),
        Some(provider),
    );

    manager
        .get_or_create_checkout_redirect_url(prepared_checkout, Uuid::new_v4())
        .await
        .expect_err("incomplete paid checkout to fail")
        .to_string()
}

/// Expects the event summary and site settings every payments notification loads.
fn expect_event_notification_context(db: &mut MockDB, community_id: Uuid, event_id: Uuid) {
    db.expect_get_event_summary_by_id()
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .times(1)
        .returning(move |_, _| Ok(sample_event_summary(event_id)));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(SiteSettings::default()));
}

/// Reports whether test webhook headers contain the expected signature.
fn has_test_signature_header(headers: &HeaderMap) -> bool {
    matches!(
        headers.get("stripe-signature").and_then(|value| value.to_str().ok()),
        Some("sig_test")
    )
}

/// Creates a pending purchase summary for checkout manager tests.
fn checkout_purchase_summary(
    event_purchase_id: Uuid,
    event_ticket_type_id: Uuid,
    provider_checkout_url: Option<String>,
) -> EventPurchaseSummary {
    EventPurchaseSummary {
        event_ticket_type_id,
        provisional_platform_fee_amount_minor: 62,

        currency_code: Some("usd".to_string()),
        provider_checkout_url,
        ..sample_event_purchase_summary(event_purchase_id, EventPurchaseStatus::Pending)
    }
}

/// Creates a payments manager with the supplied test doubles.
fn sample_payments_manager(
    db: MockDB,
    notifications_manager: MockNotificationsManager,
    payments_provider: Option<MockPaymentsProvider>,
) -> PgPaymentsManager {
    let payments_provider =
        payments_provider.map(|provider| Arc::new(provider) as DynPaymentsProvider);

    PgPaymentsManager::new(
        Arc::new(db),
        Arc::new(notifications_manager),
        payments_provider,
        250,
        HttpServerConfig::default(),
    )
}

/// Creates a prepared paid checkout for the sample payment recipient.
fn sample_prepared_event_checkout(
    event_id: Uuid,
    event_purchase_id: Uuid,
    event_ticket_type_id: Uuid,
) -> PreparedEventCheckout {
    let recipient = sample_group_payment_recipient();

    PreparedEventCheckout {
        community_display_name: "Community".to_string(),
        community_name: "community".to_string(),
        event_id,
        event_name: "Event".to_string(),
        event_slug: "event".to_string(),
        event_timezone: "UTC".to_string(),
        group_name: "Group".to_string(),
        group_slug: "group".to_string(),
        purchase: checkout_purchase_summary(event_purchase_id, event_ticket_type_id, None),
        group_slug_pretty: None,
        seller: Some(FiscalSponsorSeller {
            connected_account_id: recipient.recipient_id,
            display_name: "Fiscal sponsor".to_string(),
            provider: recipient.provider,
        }),
        tax_behavior: Some(TicketTaxBehavior::Inclusive),
        tax_calculation_mode: Some(TicketTaxCalculationMode::Automatic),
        tax_code: Some("txcd_50013001".to_string()),
        venue: Some(sample_ticket_venue()),
        ..PreparedEventCheckout::default()
    }
}

/// Creates a complete, normalized ticket venue snapshot.
fn sample_ticket_venue() -> TicketVenue {
    TicketVenue {
        address: "123 Example Street".to_string(),
        city: "Example City".to_string(),
        country_code: "US".to_string(),
        name: "Example Venue".to_string(),
        zip_code: "12345".to_string(),
        state_code: Some("CA".to_string()),
        state_name: Some("California".to_string()),
    }
}

/// Creates signed webhook headers accepted by the mock provider.
fn sample_webhook_headers() -> HeaderMap {
    let mut headers = HeaderMap::new();
    headers.insert("stripe-signature", HeaderValue::from_static("sig_test"));
    headers
}

/// Reports whether notification template data names the event.
fn template_event_matches(template_data: &Value, event_id: Uuid) -> bool {
    template_data["event"]["event_id"] == json!(event_id)
}
