use std::sync::Arc;

use axum::http::{HeaderMap, HeaderValue};
use serde_json::to_value;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::{
        DynDB,
        mock::MockDB,
        payments::{CompletedEventPurchase, EventPurchaseRefundRecoveryContext},
    },
    services::{
        notifications::{MockNotificationsManager, NotificationKind},
        payments::{
            ApproveRefundRequestInput, CheckoutSession, CompleteRefundRecoveryInput,
            DynPaymentsProvider, HandleWebhookError, MockPaymentsProvider, PaymentsWebhookEvent,
            PgPaymentsManager, RejectRefundRequestInput, RequestRefundInput,
        },
    },
    templates::notifications::EventRefundRequested,
    types::{
        event::{EventKind, EventSummary},
        payments::{
            EventPurchaseSummary, GroupPaymentRecipient, PaymentProvider, PreparedEventCheckout,
        },
        site::SiteSettings,
    },
};

#[tokio::test]
async fn approve_refund_request_only_queues_durable_work() {
    // Setup identifiers and the durable queue expectation
    let actor_user_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_queue_event_refund_request_approval()
        .withf(move |actor, group, purchase, note| {
            *actor == actor_user_id
                && *group == group_id
                && *purchase == event_purchase_id
                && note.as_deref() == Some("Approved by organizer")
        })
        .times(1)
        .returning(|_, _, _, _| Ok(()));

    let manager = PgPaymentsManager::new(
        Arc::new(db) as DynDB,
        Arc::new(MockNotificationsManager::new()),
        None,
        HttpServerConfig::default(),
    );

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
async fn approve_refund_request_propagates_queue_failure() {
    // Setup a durable queue failure
    let mut db = MockDB::new();
    db.expect_queue_event_refund_request_approval()
        .times(1)
        .returning(|_, _, _, _| Err(anyhow::anyhow!("queue unavailable")));
    let manager = PgPaymentsManager::new(
        Arc::new(db) as DynDB,
        Arc::new(MockNotificationsManager::new()),
        None,
        HttpServerConfig::default(),
    );

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
async fn complete_refund_recovery_composes_template_data_before_atomic_completion() {
    // Setup authoritative recovery and event context
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let event_purchase_refund_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);
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
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |community, event| *community == community_id && *event == event_id)
        .returning(move |_, _| Ok(event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(SiteSettings::default()));
    db.expect_complete_event_purchase_refund_recovery()
        .times(1)
        .withf(
            move |actor, group, refund, reference, note, template_data| {
                *actor == actor_user_id
                    && *group == group_id
                    && *refund == event_purchase_refund_id
                    && reference == "bank-transfer-123"
                    && note == "Verified bank receipt"
                    && template_data.as_ref().is_some_and(|data| {
                        data.get("event")
                            .and_then(|event| event.get("event_id"))
                            .and_then(|event_id| event_id.as_str())
                            .is_some_and(|value| value == event_id.to_string())
                    })
            },
        )
        .returning(|_, _, _, _, _, _| Ok(()));

    // Complete recovery through the same typed composer used by the refund worker
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
async fn complete_refund_recovery_skips_composition_after_local_finalization() {
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
        .withf(move |actor, group, refund, _, _, template_data| {
            *actor == actor_user_id
                && *group == group_id
                && *refund == event_purchase_refund_id
                && template_data.is_none()
        })
        .returning(|_, _, _, _, _, _| Ok(()));

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
async fn complete_free_checkout_records_purchase_and_enqueues_notification() {
    // Setup checkout identifiers and notification context
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);

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
            })
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

    // Complete the free checkout
    let manager = sample_payments_manager(db, notifications_manager, None);

    manager
        .complete_free_checkout(community_id, event_id, event_purchase_id, user_id)
        .await
        .unwrap();
}

#[tokio::test]
async fn get_or_create_checkout_redirect_url_creates_and_persists_session() {
    // Setup checkout identifiers and recipient
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let recipient = GroupPaymentRecipient {
        provider: PaymentProvider::Stripe,
        recipient_id: "acct_test_123".to_string(),
    };

    // Setup checkout attachment and canonical reload expectations
    let mut db = MockDB::new();
    db.expect_attach_checkout_session_to_event_purchase()
        .withf(move |purchase_id, provider, checkout_session| {
            *purchase_id == event_purchase_id
                && *provider == PaymentProvider::Stripe
                && checkout_session.provider_session_id == "cs_test_123"
        })
        .times(1)
        .returning(|_, _, _| Ok(()));
    db.expect_get_event_purchase_summary()
        .withf(move |purchase_id| *purchase_id == event_purchase_id)
        .times(1)
        .returning(move |_| {
            Ok(sample_event_purchase_summary(
                event_purchase_id,
                event_ticket_type_id,
                Some("https://example.test/checkout".to_string()),
                Some("SPRING".to_string()),
            ))
        });

    // Setup provider checkout creation expectations
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_provider()
        .times(2)
        .return_const(PaymentProvider::Stripe);
    provider
        .expect_create_checkout_session()
        .withf(move |input| {
            input.amount_minor == 2_500
                && input.discount_code.as_deref() == Some("SPRING")
                && input.event_id == event_id
                && input.purchase_id == event_purchase_id
                && input.recipient == recipient
                && input.user_id == user_id
        })
        .times(1)
        .returning(|_| {
            Box::pin(async {
                Ok(CheckoutSession {
                    provider_session_id: "cs_test_123".to_string(),
                    redirect_url: "https://example.test/checkout".to_string(),
                })
            })
        });
    // Prepare a checkout that requires a provider session
    let prepared_checkout = sample_prepared_event_checkout(
        event_id,
        event_purchase_id,
        event_ticket_type_id,
        None,
        Some("SPRING".to_string()),
        GroupPaymentRecipient {
            provider: PaymentProvider::Stripe,
            recipient_id: "acct_test_123".to_string(),
        },
    );
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
async fn get_or_create_checkout_redirect_url_returns_canonical_url_after_racing_attach() {
    // Setup a checkout whose concurrent request wins the canonical URL
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let recipient = GroupPaymentRecipient {
        provider: PaymentProvider::Stripe,
        recipient_id: "acct_test_123".to_string(),
    };

    // Setup attachment and canonical purchase reload expectations
    let mut db = MockDB::new();
    db.expect_attach_checkout_session_to_event_purchase()
        .withf(move |purchase_id, provider, checkout_session| {
            *purchase_id == event_purchase_id
                && *provider == PaymentProvider::Stripe
                && checkout_session.provider_session_id == "cs_test_racing"
                && checkout_session.redirect_url == "https://example.test/checkout/racing"
        })
        .times(1)
        .returning(|_, _, _| Ok(()));
    db.expect_get_event_purchase_summary()
        .withf(move |purchase_id| *purchase_id == event_purchase_id)
        .times(1)
        .returning(move |_| {
            Ok(sample_event_purchase_summary(
                event_purchase_id,
                event_ticket_type_id,
                Some("https://example.test/checkout/canonical".to_string()),
                None,
            ))
        });

    // Setup the provider session created by the losing request
    let mut provider = MockPaymentsProvider::new();
    provider.expect_create_checkout_session().times(1).returning(|_| {
        Box::pin(async {
            Ok(CheckoutSession {
                provider_session_id: "cs_test_racing".to_string(),
                redirect_url: "https://example.test/checkout/racing".to_string(),
            })
        })
    });
    provider
        .expect_provider()
        .times(2)
        .return_const(PaymentProvider::Stripe);

    // Create the checkout and reload its canonical persisted state
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), Some(provider));
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

    // Check the concurrent winner remains authoritative
    assert_eq!(redirect_url, "https://example.test/checkout/canonical");
}

#[tokio::test]
async fn get_or_create_checkout_redirect_url_returns_error_when_checkout_url_is_missing() {
    // Setup a checkout whose persisted purchase has no canonical URL
    let event_purchase_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let recipient = GroupPaymentRecipient {
        provider: PaymentProvider::Stripe,
        recipient_id: "acct_test_123".to_string(),
    };

    // Setup successful attachment followed by an incomplete purchase reload
    let mut db = MockDB::new();
    db.expect_attach_checkout_session_to_event_purchase()
        .times(1)
        .returning(|_, _, _| Ok(()));
    db.expect_get_event_purchase_summary()
        .withf(move |purchase_id| *purchase_id == event_purchase_id)
        .times(1)
        .returning(move |_| {
            Ok(sample_event_purchase_summary(
                event_purchase_id,
                event_ticket_type_id,
                None,
                None,
            ))
        });

    // Setup provider checkout creation
    let mut provider = MockPaymentsProvider::new();
    provider.expect_create_checkout_session().times(1).returning(|_| {
        Box::pin(async {
            Ok(CheckoutSession {
                provider_session_id: "cs_test_123".to_string(),
                redirect_url: "https://example.test/checkout".to_string(),
            })
        })
    });
    provider
        .expect_provider()
        .times(2)
        .return_const(PaymentProvider::Stripe);

    // Attempt to create the checkout without a canonical persisted URL
    let manager = sample_payments_manager(db, MockNotificationsManager::new(), Some(provider));
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
        .expect_err("missing canonical checkout URL to fail");

    // Check the persistence invariant is explicit
    assert_eq!(
        err.to_string(),
        "provider checkout URL is missing after checkout creation"
    );
}

#[tokio::test]
async fn get_or_create_checkout_redirect_url_returns_error_when_payments_are_unconfigured() {
    // Setup a checkout that requires a provider session
    let prepared_checkout = sample_prepared_event_checkout(
        Uuid::new_v4(),
        Uuid::new_v4(),
        Uuid::new_v4(),
        None,
        None,
        GroupPaymentRecipient {
            provider: PaymentProvider::Stripe,
            recipient_id: "acct_test_123".to_string(),
        },
    );
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
async fn get_or_create_checkout_redirect_url_reuses_existing_url_without_provider() {
    // Setup a checkout with an existing provider URL
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
async fn handle_webhook_accepts_verified_noop_event() {
    // Setup a provider verifier that returns an irrelevant signed event
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_verify_and_parse_webhook()
        .withf(|headers, body| has_test_signature_header(headers) && body == "payload")
        .times(1)
        .returning(|_, _| Ok(PaymentsWebhookEvent::Noop));

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
async fn handle_webhook_returns_invalid_payload_when_verification_fails() {
    // Setup a provider signature verification failure
    let mut provider = MockPaymentsProvider::new();
    provider
        .expect_verify_and_parse_webhook()
        .withf(|headers, body| has_test_signature_header(headers) && body == "payload")
        .times(1)
        .returning(|_, _| Err(anyhow::anyhow!("invalid signature")));

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
async fn handle_webhook_returns_not_configured_without_provider() {
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
async fn reject_refund_request_persists_rejection_and_enqueues_notification() {
    // Setup review identifiers and notification context
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let target_user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);

    // Setup rejection persistence and context expectations
    let mut db = MockDB::new();
    db.expect_reject_event_refund_request()
        .withf(move |actor, group, purchase, note| {
            *actor == actor_user_id
                && *group == group_id
                && *purchase == event_purchase_id
                && note.as_deref() == Some("Not eligible")
        })
        .times(1)
        .returning(move |_, _, _, _| {
            Ok(CompletedEventPurchase {
                community_id,
                event_id,
                user_id: target_user_id,
            })
        });
    db.expect_get_event_summary_by_id()
        .times(1)
        .returning(move |_, _| Ok(event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(SiteSettings::default()));
    // Setup the attendee rejection notification expectation
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager
        .expect_enqueue()
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventRefundRejected)
                && notification.recipients == vec![target_user_id]
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
            review_note: Some("Not eligible".to_string()),
        })
        .await
        .unwrap();
}

#[tokio::test]
async fn request_refund_records_request_with_notification_context() {
    // Setup refund request identifiers and expected notification payload
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);
    let site_settings = SiteSettings::default();
    let expected_template_data = to_value(&EventRefundRequested {
        event: event.clone(),
        link: "/dashboard/group?tab=refunds".to_string(),
        theme: site_settings.theme.clone(),
    })
    .unwrap();

    // Setup notification context and request persistence expectations
    let mut db = MockDB::new();
    db.expect_get_event_summary_by_id()
        .times(1)
        .returning(move |_, _| Ok(event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    db.expect_request_event_refund()
        .withf(move |community, event, user, reason, template_data| {
            *community == community_id
                && *event == event_id
                && *user == user_id
                && reason.as_deref() == Some("Need to cancel")
                && template_data == &expected_template_data
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
async fn request_refund_returns_error_when_notification_context_load_fails() {
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

// Helpers.

/// Reports whether test webhook headers contain the expected signature.
fn has_test_signature_header(headers: &HeaderMap) -> bool {
    matches!(
        headers.get("stripe-signature").and_then(|value| value.to_str().ok()),
        Some("sig_test")
    )
}

/// Creates an event summary for payment notification tests.
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

/// Creates a purchase summary for checkout manager tests.
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
        HttpServerConfig::default(),
    )
}

/// Creates a prepared checkout result for manager tests.
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

/// Creates signed webhook headers accepted by the mock provider.
fn sample_webhook_headers() -> HeaderMap {
    let mut headers = HeaderMap::new();
    headers.insert("stripe-signature", HeaderValue::from_static("sig_test"));
    headers
}
