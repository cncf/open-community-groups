use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderValue, Request, StatusCode,
        header::{CONTENT_TYPE, COOKIE},
    },
};
use axum_login::tower_sessions::session;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::{error::HandlerError, tests::*},
    services::{
        notifications::MockNotificationsManager,
        payments::{
            AutomaticTaxReadiness, AutomaticTaxReadinessError, FiscalSponsorReadinessError,
            MockPaymentsManager,
        },
    },
    types::{
        group::{GroupFull, GroupParentOption},
        payments::{GroupExternalPaymentsContext, GroupPaymentRecipient, PaymentProvider},
        permissions::GroupPermission,
    },
};

#[tokio::test]
async fn test_update_page_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let group = sample_group_full(community_id, group_id);

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    expect_update_page_reads(
        &mut db,
        community_id,
        group_id,
        user_id,
        unconfigured_external_payments(),
        group,
        vec![],
    );

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let response = router.oneshot(update_page_request(session_id)).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8"),
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_update_page_selects_current_inactive_parent_option() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let parent_group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let group = sample_group_full(community_id, group_id);
    let parent_option = GroupParentOption {
        active: false,
        group_id: parent_group_id,
        is_current: true,
        is_selectable: false,
        name: "Inactive Parent".to_string(),
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    expect_update_page_reads(
        &mut db,
        community_id,
        group_id,
        user_id,
        unconfigured_external_payments(),
        group,
        vec![parent_option],
    );

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let response = router.oneshot(update_page_request(session_id)).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    let option_start = body
        .find(&format!("value=\"{parent_group_id}\""))
        .expect("parent option should render");
    let option_end = body[option_start..]
        .find("</option>")
        .expect("parent option should close");
    let option_html = &body[option_start..option_start + option_end];
    assert!(option_html.contains("selected"));
    assert!(option_html.contains("(current, no longer selectable)"));
}

#[tokio::test]
async fn test_update_trims_external_payments_seller_display_name() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut update = sample_group_update();
    update.external_payments_enabled = Some(true);
    update.external_payments_seller_display_name = Some("  External Payee Co  ".to_string());
    let body = serde_qs::to_string(&update).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::SettingsWrite,
    );
    db.expect_update_group()
        .times(1)
        .withf(move |uid, cid, gid, group| {
            *uid == user_id
                && *cid == community_id
                && *gid == group_id
                && group.external_payments_enabled == Some(true)
                && group.external_payments_seller_display_name.as_deref()
                    == Some("External Payee Co")
        })
        .returning(move |_, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(MockPaymentsManager::new())
        .build()
        .await;
    let response = router.oneshot(update_request(session_id, body)).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_update_keeps_blank_external_payments_seller_display_name_for_clearing() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut update = sample_group_update();
    update.external_payments_enabled = Some(false);
    update.external_payments_seller_display_name = Some("   ".to_string());
    let body = serde_qs::to_string(&update).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::SettingsWrite,
    );
    db.expect_update_group()
        .times(1)
        .withf(move |uid, cid, gid, group| {
            *uid == user_id
                && *cid == community_id
                && *gid == group_id
                && group.external_payments_seller_display_name.as_deref() == Some("")
        })
        .returning(move |_, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(MockPaymentsManager::new())
        .build()
        .await;
    let response = router.oneshot(update_request(session_id, body)).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_update_normalizes_unchanged_payment_recipient() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut update = sample_group_update();
    let payment_recipient = sample_group_payment_recipient();
    update.payment_recipient = Some(GroupPaymentRecipient {
        recipient_id: format!("  {}  ", payment_recipient.recipient_id),
        seller_display_name: format!("  {}  ", payment_recipient.seller_display_name),
        ..payment_recipient.clone()
    });
    let body = serde_qs::to_string(&update).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::SettingsWrite,
    );
    db.expect_update_group()
        .times(1)
        .withf(move |uid, cid, gid, group| {
            *uid == user_id
                && *cid == community_id
                && *gid == group_id
                && group.name == update.name
                && group.payment_recipient.as_ref().is_some_and(|recipient| {
                    recipient.recipient_id == "acct_test"
                        && recipient.seller_display_name == "Test Fiscal Sponsor"
                })
        })
        .returning(move |_, _, _, _| Ok(()));
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(move |_, _| Ok(Some(payment_recipient.clone())));

    // Keep unchanged provider accounts independent of Stripe availability
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_validate_fiscal_sponsor().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let response = router.oneshot(update_request(session_id, body)).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get("HX-Trigger").unwrap(),
        &HeaderValue::from_static("refresh-body"),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_update_invalid_body() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::SettingsWrite,
    );

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let response = router
        .oneshot(update_request(session_id, "invalid".to_string()))
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(!bytes.is_empty());
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_update_binds_changed_sponsor_validation_to_locked_state() {
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut update = sample_group_update();
    update.payment_recipient = Some(GroupPaymentRecipient {
        provider: PaymentProvider::Stripe,
        recipient_id: "acct_new".to_string(),
        seller_display_name: "New Sponsor".to_string(),
    });
    let body = serde_qs::to_string(&update).unwrap();

    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::SettingsWrite,
    );
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| {
            Ok(Some(GroupPaymentRecipient {
                provider: PaymentProvider::Stripe,
                recipient_id: "acct_current".to_string(),
                seller_display_name: "Current Sponsor".to_string(),
            }))
        });
    db.expect_get_group_external_payments_eligibility()
        .times(1)
        .withf(move |cid, gid, country_code| {
            *cid == community_id && *gid == group_id && country_code.as_deref() == Some("US")
        })
        .returning(|_, _, _| Ok(false));
    db.expect_group_requires_automatic_tax_readiness()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(true));
    db.expect_list_group_automatic_tax_readiness_event_ids()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(move |_, _| Ok(vec![event_id]));
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(sample_event_full(community_id, event_id, group_id)));
    db.expect_update_group()
        .times(1)
        .withf(move |uid, cid, gid, group| {
            *uid == user_id
                && *cid == community_id
                && *gid == group_id
                && group.payment_validation.as_ref().is_some_and(|validation| {
                    validation.require_automatic_tax
                        && validation
                            .expected_payment_recipient
                            .as_ref()
                            .is_some_and(|recipient| recipient.recipient_id == "acct_current")
                        && validation
                            .validated_payment_recipient
                            .as_ref()
                            .is_some_and(|recipient| recipient.recipient_id == "acct_new")
                })
        })
        .returning(|_, _, _, _| Ok(()));

    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_validate_fiscal_sponsor()
        .withf(|recipient, automatic_tax_jurisdiction| {
            recipient.recipient_id == "acct_new" && automatic_tax_jurisdiction.is_none()
        })
        .times(1)
        .returning(|_, _| Box::pin(async { Ok(()) }));
    payments_manager
        .expect_ensure_automatic_tax_readiness()
        .withf(|recipient, _| recipient.recipient_id == "acct_new")
        .times(1)
        .returning(|_, _| {
            Box::pin(async {
                Ok(AutomaticTaxReadiness {
                    cached: false,
                    fingerprint: "fingerprint".to_string(),
                    provider_tax_location_id: "loc_new".to_string(),
                    state_code: None,
                })
            })
        });

    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let response = router.oneshot(update_request(session_id, body)).await.unwrap();

    assert_eq!(response.status(), StatusCode::NO_CONTENT);
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_update_rejects_changed_sponsor_when_upcoming_event_is_not_ready() {
    // Setup an authenticated settings update selecting a new fiscal sponsor
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut update = sample_group_update();
    update.payment_recipient = Some(GroupPaymentRecipient {
        provider: PaymentProvider::Stripe,
        recipient_id: "acct_new".to_string(),
        seller_display_name: "New Sponsor".to_string(),
    });
    let body = serde_qs::to_string(&update).unwrap();

    // Authorize the request and load the upcoming automatic-tax event
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::SettingsWrite,
    );
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| {
            Ok(Some(GroupPaymentRecipient {
                provider: PaymentProvider::Stripe,
                recipient_id: "acct_current".to_string(),
                seller_display_name: "Current Sponsor".to_string(),
            }))
        });
    db.expect_get_group_external_payments_eligibility()
        .times(1)
        .withf(move |cid, gid, country_code| {
            *cid == community_id && *gid == group_id && country_code.as_deref() == Some("US")
        })
        .returning(|_, _, _| Ok(false));
    db.expect_group_requires_automatic_tax_readiness()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(true));
    db.expect_list_group_automatic_tax_readiness_event_ids()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(move |_, _| Ok(vec![event_id]));
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(sample_event_full(community_id, event_id, group_id)));
    db.expect_update_group().never();

    // Accept the new sponsor, then reject the upcoming event venue
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_validate_fiscal_sponsor()
        .withf(|recipient, automatic_tax_jurisdiction| {
            recipient.recipient_id == "acct_new" && automatic_tax_jurisdiction.is_none()
        })
        .times(1)
        .returning(|_, _| Box::pin(async { Ok(()) }));
    payments_manager
        .expect_ensure_automatic_tax_readiness()
        .withf(|recipient, _| recipient.recipient_id == "acct_new")
        .times(1)
        .returning(|_, _| Box::pin(async { Err(AutomaticTaxReadinessError::InvalidAddress) }));

    // Submit the update through the routed handler
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let response = router.oneshot(update_request(session_id, body)).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the event-specific failure is reported without persisting
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "cannot update fiscal sponsor: upcoming event \"Test Event\" is not ready for payments: the venue address is invalid"
    );
}

#[tokio::test]
async fn test_update_rejects_changed_sponsor_without_required_automatic_tax() {
    // Setup an authenticated settings update selecting a fiscal sponsor
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut update = sample_group_update();
    update.payment_recipient = Some(GroupPaymentRecipient {
        provider: PaymentProvider::Stripe,
        recipient_id: "acct_unready".to_string(),
        seller_display_name: "Unready Sponsor".to_string(),
    });
    let body = serde_qs::to_string(&update).unwrap();

    // Authorize the request while forbidding any database write
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::SettingsWrite,
    );
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| {
            Ok(Some(GroupPaymentRecipient {
                provider: PaymentProvider::Stripe,
                recipient_id: "acct_current".to_string(),
                seller_display_name: "Current Sponsor".to_string(),
            }))
        });
    db.expect_get_group_external_payments_eligibility()
        .times(1)
        .withf(move |cid, gid, country_code| {
            *cid == community_id && *gid == group_id && country_code.as_deref() == Some("US")
        })
        .returning(|_, _, _| Ok(false));
    db.expect_group_requires_automatic_tax_readiness()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(true));
    db.expect_update_group().never();

    // Reject the sponsor at the provider boundary before persistence
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_validate_fiscal_sponsor()
        .withf(|recipient, automatic_tax_jurisdiction| {
            recipient.provider == PaymentProvider::Stripe
                && recipient.recipient_id == "acct_unready"
                && automatic_tax_jurisdiction.is_none()
        })
        .times(1)
        .returning(|_, _| {
            Box::pin(async {
                Err(FiscalSponsorReadinessError::NotReady(
                    "Stripe account is not ready".to_string(),
                ))
            })
        });

    // Submit the update through the routed handler
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let response = router.oneshot(update_request(session_id, body)).await.unwrap();

    // Check the provider failure prevents persistence
    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_update_rejects_new_sponsor_when_resulting_country_is_allowlisted() {
    // Setup a settings update adding a first fiscal sponsor
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut update = sample_group_update();
    update.payment_recipient = Some(GroupPaymentRecipient {
        provider: PaymentProvider::Stripe,
        recipient_id: "acct_new".to_string(),
        seller_display_name: "New Sponsor".to_string(),
    });
    let body = serde_qs::to_string(&update).unwrap();

    // Authorize the request and report the resulting country as allowlisted
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::SettingsWrite,
    );
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(None));
    db.expect_get_group_external_payments_eligibility()
        .times(1)
        .withf(move |cid, gid, country_code| {
            *cid == community_id && *gid == group_id && country_code.as_deref() == Some("US")
        })
        .returning(|_, _, _| Ok(true));
    db.expect_group_requires_automatic_tax_readiness().never();
    db.expect_list_group_automatic_tax_readiness_event_ids().never();
    db.expect_update_group().never();

    // Forbid any provider call for the blocked request
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_validate_fiscal_sponsor().never();
    payments_manager.expect_ensure_automatic_tax_readiness().never();

    // Submit the update through the routed handler
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let response = router.oneshot(update_request(session_id, body)).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the policy rejection is reported before any provider call
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "stripe connected account cannot be added or changed for this group country"
    );
}

#[tokio::test]
async fn test_update_rejects_replacement_sponsor_when_moving_between_allowlisted_countries() {
    // Setup a settings update replacing the sponsor while moving to another allowlisted country
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut update = sample_group_update();
    update.country_code = Some("JP".to_string());
    update.country_name = Some("Japan".to_string());
    update.payment_recipient = Some(GroupPaymentRecipient {
        provider: PaymentProvider::Stripe,
        recipient_id: "acct_replacement".to_string(),
        seller_display_name: "Replacement Sponsor".to_string(),
    });
    let body = serde_qs::to_string(&update).unwrap();

    // Authorize the request and evaluate the submitted country
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::SettingsWrite,
    );
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));
    db.expect_get_group_external_payments_eligibility()
        .times(1)
        .withf(move |cid, gid, country_code| {
            *cid == community_id && *gid == group_id && country_code.as_deref() == Some("JP")
        })
        .returning(|_, _, _| Ok(true));
    db.expect_group_requires_automatic_tax_readiness().never();
    db.expect_list_group_automatic_tax_readiness_event_ids().never();
    db.expect_update_group().never();

    // Forbid any provider call for the blocked request
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_validate_fiscal_sponsor().never();
    payments_manager.expect_ensure_automatic_tax_readiness().never();

    // Submit the update through the routed handler
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let response = router.oneshot(update_request(session_id, body)).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the policy rejection is reported before any provider call
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "stripe connected account cannot be added or changed for this group country"
    );
}

#[tokio::test]
async fn test_update_validates_sponsor_when_same_save_leaves_allowlist() {
    // Setup a settings update adding a sponsor while moving off the allowlist
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut update = sample_group_update();
    update.country_code = Some("US".to_string());
    update.payment_recipient = Some(GroupPaymentRecipient {
        provider: PaymentProvider::Stripe,
        recipient_id: "acct_new".to_string(),
        seller_display_name: "New Sponsor".to_string(),
    });
    let body = serde_qs::to_string(&update).unwrap();

    // Authorize the request and report the submitted country as not allowlisted
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::SettingsWrite,
    );
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(None));
    db.expect_get_group_external_payments_eligibility()
        .times(1)
        .withf(move |cid, gid, country_code| {
            *cid == community_id && *gid == group_id && country_code.as_deref() == Some("US")
        })
        .returning(|_, _, _| Ok(false));
    db.expect_group_requires_automatic_tax_readiness()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(false));
    db.expect_update_group()
        .times(1)
        .withf(move |uid, cid, gid, group| {
            *uid == user_id
                && *cid == community_id
                && *gid == group_id
                && group.country_code.as_deref() == Some("US")
                && group.payment_validation.as_ref().is_some_and(|validation| {
                    !validation.require_automatic_tax
                        && validation.expected_payment_recipient.is_none()
                        && validation
                            .validated_payment_recipient
                            .as_ref()
                            .is_some_and(|recipient| recipient.recipient_id == "acct_new")
                })
        })
        .returning(|_, _, _, _| Ok(()));

    // Validate the new sponsor once at the provider boundary
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_validate_fiscal_sponsor()
        .withf(|recipient, automatic_tax_jurisdiction| {
            recipient.recipient_id == "acct_new" && automatic_tax_jurisdiction.is_none()
        })
        .times(1)
        .returning(|_, _| Box::pin(async { Ok(()) }));

    // Submit the update through the routed handler
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let response = router.oneshot(update_request(session_id, body)).await.unwrap();

    // Check the update is persisted
    assert_eq!(response.status(), StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_update_saves_without_recipient_controls() {
    // Setup a settings update that omits every payment recipient field
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let update = sample_group_update();
    let body = serde_qs::to_string(&update).unwrap();
    assert!(!body.contains("payment_recipient"));

    // Authorize the request and persist without any recipient reads
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::SettingsWrite,
    );
    db.expect_get_group_payment_recipient().never();
    db.expect_get_group_external_payments_eligibility().never();
    db.expect_update_group()
        .times(1)
        .withf(move |uid, cid, gid, group| {
            *uid == user_id
                && *cid == community_id
                && *gid == group_id
                && group.payment_recipient.is_none()
                && group.payment_validation.is_none()
        })
        .returning(|_, _, _, _| Ok(()));

    // Forbid any provider call
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_validate_fiscal_sponsor().never();

    // Submit the update through the routed handler
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let response = router.oneshot(update_request(session_id, body)).await.unwrap();

    // Check the update is persisted with the recipient left untouched
    assert_eq!(response.status(), StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_update_renames_stored_sponsor_without_provider_calls() {
    // Setup a settings update changing only the stored sponsor's legal name
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let stored_recipient = sample_group_payment_recipient();
    let mut update = sample_group_update();
    update.payment_recipient = Some(GroupPaymentRecipient {
        seller_display_name: "Renamed Fiscal Sponsor".to_string(),
        ..stored_recipient.clone()
    });
    let body = serde_qs::to_string(&update).unwrap();

    // Authorize the request and persist the rename without policy or provider checks
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::SettingsWrite,
    );
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(move |_, _| Ok(Some(stored_recipient.clone())));
    db.expect_get_group_external_payments_eligibility().never();
    db.expect_update_group()
        .times(1)
        .withf(move |uid, cid, gid, group| {
            *uid == user_id
                && *cid == community_id
                && *gid == group_id
                && group.payment_validation.is_none()
                && group.payment_recipient.as_ref().is_some_and(|recipient| {
                    recipient.recipient_id == "acct_test"
                        && recipient.seller_display_name == "Renamed Fiscal Sponsor"
                })
        })
        .returning(|_, _, _, _| Ok(()));

    // Forbid any provider call
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_validate_fiscal_sponsor().never();

    // Submit the update through the routed handler
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let response = router.oneshot(update_request(session_id, body)).await.unwrap();

    // Check the rename is persisted
    assert_eq!(response.status(), StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_update_clear_propagates_recipient_safeguard() {
    // Setup a settings update submitting both sponsor fields blank
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut update = sample_group_update();
    update.payment_recipient = Some(GroupPaymentRecipient {
        provider: PaymentProvider::Stripe,
        recipient_id: String::new(),
        seller_display_name: String::new(),
    });
    let body = serde_qs::to_string(&update).unwrap();

    // Authorize the request and reject the clear with the database safeguard
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::SettingsWrite,
    );
    db.expect_get_group_payment_recipient().never();
    db.expect_get_group_external_payments_eligibility().never();
    db.expect_update_group()
        .times(1)
        .withf(move |uid, cid, gid, group| {
            *uid == user_id
                && *cid == community_id
                && *gid == group_id
                && group.payment_validation.is_none()
                && group.payment_recipient.as_ref().is_some_and(|recipient| {
                    recipient.provider == PaymentProvider::Stripe
                        && recipient.recipient_id.is_empty()
                        && recipient.seller_display_name.is_empty()
                })
        })
        .returning(|_, _, _, _| {
            Err(HandlerError::Database(
                "paid-capable events require a payment recipient".to_string(),
            )
            .into())
        });

    // Forbid any provider call
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_validate_fiscal_sponsor().never();

    // Submit the update through the routed handler
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let response = router.oneshot(update_request(session_id, body)).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the safeguard message reaches the organizer
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "paid-capable events require a payment recipient"
    );
}

#[tokio::test]
async fn test_update_clears_stored_sponsor_without_provider_calls() {
    // Setup a settings update submitting both sponsor fields blank
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut update = sample_group_update();
    update.payment_recipient = Some(GroupPaymentRecipient {
        provider: PaymentProvider::Stripe,
        recipient_id: String::new(),
        seller_display_name: String::new(),
    });
    let body = serde_qs::to_string(&update).unwrap();

    // Authorize the request and hand the clearing recipient to the database
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::SettingsWrite,
    );
    db.expect_get_group_payment_recipient().never();
    db.expect_get_group_external_payments_eligibility().never();
    db.expect_update_group()
        .times(1)
        .withf(move |uid, cid, gid, group| {
            *uid == user_id
                && *cid == community_id
                && *gid == group_id
                && group.payment_validation.is_none()
                && group.payment_recipient.as_ref().is_some_and(|recipient| {
                    recipient.provider == PaymentProvider::Stripe
                        && recipient.recipient_id.is_empty()
                        && recipient.seller_display_name.is_empty()
                })
        })
        .returning(|_, _, _, _| Ok(()));

    // Forbid any provider call
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_validate_fiscal_sponsor().never();

    // Submit the update through the routed handler
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let response = router.oneshot(update_request(session_id, body)).await.unwrap();

    // Check the clear is handed to the database
    assert_eq!(response.status(), StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_update_page_hides_fiscal_sponsor_controls_when_onboarding_is_blocked() {
    // Setup an allowlisted group without a stored recipient
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let group = sample_group_full(community_id, group_id);

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    expect_update_page_reads(
        &mut db,
        community_id,
        group_id,
        user_id,
        allowlisted_external_payments(),
        group,
        vec![],
    );

    // Render the page with Stripe payments enabled
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let response = router.oneshot(update_page_request(session_id)).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the notice replaces every payment recipient control
    assert_eq!(parts.status, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("A Stripe connected account cannot be added or changed here"));
    assert!(body.contains("United States"));
    assert!(!body.contains("name=\"payment_recipient[provider]\""));
    assert!(!body.contains("name=\"payment_recipient[recipient_id]\""));
    assert!(!body.contains("name=\"payment_recipient[seller_display_name]\""));
    assert!(!body.contains("id=\"payment_recipient_recipient_id\""));
    assert!(body.contains(
        "data-hx-keep-empty=\"external_payments_seller_display_name payment_recipient[recipient_id] payment_recipient[seller_display_name]\""
    ));
}

#[tokio::test]
async fn test_update_page_keeps_fiscal_sponsor_controls_for_stored_recipient_when_blocked() {
    // Setup an allowlisted group with a stored recipient
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut group = sample_group_full(community_id, group_id);
    group.payment_recipient = Some(sample_group_payment_recipient());

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    expect_update_page_reads(
        &mut db,
        community_id,
        group_id,
        user_id,
        allowlisted_external_payments(),
        group,
        vec![],
    );

    // Render the page with Stripe payments enabled
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let response = router.oneshot(update_page_request(session_id)).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the notice and the prefilled controls render together
    assert_eq!(parts.status, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("A Stripe connected account cannot be added or changed here"));
    assert!(body.contains("The stored fiscal sponsor can still be used for paid events on Stripe"));
    assert!(body.contains("name=\"payment_recipient[provider]\""));
    assert!(body.contains("name=\"payment_recipient[recipient_id]\""));
    assert!(body.contains("name=\"payment_recipient[seller_display_name]\""));
    assert!(body.contains("value=\"acct_test\""));
    assert!(body.contains("value=\"Test Fiscal Sponsor\""));
}

#[tokio::test]
async fn test_update_page_shows_fiscal_sponsor_controls_when_onboarding_is_open() {
    // Setup a group whose country is not allowlisted
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let group = sample_group_full(community_id, group_id);
    let external_payments = GroupExternalPaymentsContext {
        configured: true,
        eligible: false,
        enabled: false,
        country_code: Some("US".to_string()),
        default_payment_window_hours: Some(72),
        max_payment_window_hours: Some(336),
        seller_display_name: None,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    expect_update_page_reads(
        &mut db,
        community_id,
        group_id,
        user_id,
        external_payments,
        group,
        vec![],
    );

    // Render the page with Stripe payments enabled
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let response = router.oneshot(update_page_request(session_id)).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the regular Fiscal Sponsor section renders
    assert_eq!(parts.status, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(!body.contains("A Stripe connected account cannot be added or changed here"));
    assert!(body.contains("The fiscal sponsor owns Tax Rate definitions in Stripe."));
    assert!(body.contains("name=\"payment_recipient[provider]\""));
    assert!(body.contains("name=\"payment_recipient[recipient_id]\""));
    assert!(body.contains("name=\"payment_recipient[seller_display_name]\""));
}

#[tokio::test]
async fn test_update_page_renders_external_payee_legal_name_for_enabled_group() {
    // Setup an allowlisted group that opted into external payments
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut group = sample_group_full(community_id, group_id);
    group.external_payments_enabled = true;
    group.external_payments_seller_display_name = Some("External Payee Co".to_string());
    let external_payments = GroupExternalPaymentsContext {
        enabled: true,
        seller_display_name: Some("External Payee Co".to_string()),
        ..allowlisted_external_payments()
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    expect_update_page_reads(
        &mut db,
        community_id,
        group_id,
        user_id,
        external_payments,
        group,
        vec![],
    );

    // Render the page
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let response = router.oneshot(update_page_request(session_id)).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the editable legal name input renders with the stored value
    assert_eq!(parts.status, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    let input = external_payee_input(&body);
    assert!(input.contains("value=\"External Payee Co\""));
    assert!(!input.contains("disabled"));
}

#[tokio::test]
async fn test_update_page_keeps_external_payee_input_editable_for_delisted_enabled_group() {
    // Setup an enabled legacy group whose country left the allowlist without a payee name
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut group = sample_group_full(community_id, group_id);
    group.external_payments_enabled = true;
    let external_payments = GroupExternalPaymentsContext {
        configured: true,
        eligible: false,
        enabled: true,
        country_code: Some("US".to_string()),
        default_payment_window_hours: Some(72),
        max_payment_window_hours: Some(336),
        seller_display_name: None,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    expect_update_page_reads(
        &mut db,
        community_id,
        group_id,
        user_id,
        external_payments,
        group,
        vec![],
    );

    // Render the page
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let response = router.oneshot(update_page_request(session_id)).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the legal name stays editable while the toggle is locked on
    assert_eq!(parts.status, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("name=\"external_payments_enabled\""));
    let input = external_payee_input(&body);
    assert!(!input.contains("value="));
    assert!(!input.contains("disabled"));
}

#[tokio::test]
async fn test_update_page_disables_external_payee_input_for_ineligible_opted_out_group() {
    // Setup a group that cannot opt into external payments
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let group = sample_group_full(community_id, group_id);
    let external_payments = GroupExternalPaymentsContext {
        configured: true,
        eligible: false,
        enabled: false,
        country_code: Some("US".to_string()),
        default_payment_window_hours: Some(72),
        max_payment_window_hours: Some(336),
        seller_display_name: None,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    expect_update_page_reads(
        &mut db,
        community_id,
        group_id,
        user_id,
        external_payments,
        group,
        vec![],
    );

    // Render the page
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let response = router.oneshot(update_page_request(session_id)).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the legal name input is disabled alongside the toggle
    assert_eq!(parts.status, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    let input = external_payee_input(&body);
    assert!(input.contains("disabled"));
}

#[tokio::test]
async fn test_update_page_renders_external_payments_section_for_enabled_group_without_config() {
    // Setup an enabled legacy group after the operator removed the external payments config
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut group = sample_group_full(community_id, group_id);
    group.external_payments_enabled = true;
    let external_payments = GroupExternalPaymentsContext {
        enabled: true,
        ..unconfigured_external_payments()
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    expect_update_page_reads(
        &mut db,
        community_id,
        group_id,
        user_id,
        external_payments,
        group,
        vec![],
    );

    // Render the page without Stripe payments enabled
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let response = router.oneshot(update_page_request(session_id)).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the section renders so the missing legal name can be saved
    assert_eq!(parts.status, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("name=\"external_payments_enabled\""));
    let input = external_payee_input(&body);
    assert!(!input.contains("disabled"));
}

// Helpers.

/// Returns the rendered external payee legal name input tag.
fn external_payee_input(body: &str) -> &str {
    let start = body
        .find("id=\"external_payments_seller_display_name\"")
        .expect("external payee input should render");
    let end = body[start..].find('>').expect("external payee input should close");
    &body[start..start + end]
}

/// External-payments context for a group whose country is allowlisted.
fn allowlisted_external_payments() -> GroupExternalPaymentsContext {
    GroupExternalPaymentsContext {
        configured: true,
        eligible: true,
        enabled: false,
        country_code: Some("US".to_string()),
        default_payment_window_hours: Some(72),
        max_payment_window_hours: Some(336),
        seller_display_name: None,
    }
}

/// Registers the database reads performed while preparing the settings page.
fn expect_update_page_reads(
    db: &mut MockDB,
    community_id: Uuid,
    group_id: Uuid,
    user_id: Uuid,
    external_payments: GroupExternalPaymentsContext,
    group: GroupFull,
    parent_options: Vec<GroupParentOption>,
) {
    expect_group_permission(
        db,
        community_id,
        group_id,
        user_id,
        GroupPermission::SettingsWrite,
    );
    db.expect_get_group_full()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(move |_, _| Ok(group.clone()));
    db.expect_group_has_child_links()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(false));
    db.expect_list_group_categories()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(|_| Ok(vec![sample_group_category()]));
    db.expect_list_group_parent_options()
        .times(1)
        .withf(move |cid, uid, gid| {
            *cid == community_id && *uid == user_id && *gid == Some(group_id)
        })
        .returning(move |_, _, _| Ok(parent_options.clone()));
    db.expect_list_regions()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(|_| Ok(vec![sample_group_region()]));
    db.expect_get_group_external_payments_context()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(move |_, _| Ok(external_payments.clone()));
}

/// External-payments context for a community without payments configured.
fn unconfigured_external_payments() -> GroupExternalPaymentsContext {
    GroupExternalPaymentsContext {
        configured: false,
        eligible: false,
        enabled: false,
        country_code: None,
        default_payment_window_hours: None,
        max_payment_window_hours: None,
        seller_display_name: None,
    }
}

/// Builds an authenticated GET request for the settings update page.
fn update_page_request(session_id: session::Id) -> Request<Body> {
    Request::builder()
        .method("GET")
        .uri("/dashboard/group/settings/update")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap()
}

/// Builds an authenticated form-encoded PUT request for the settings update.
fn update_request(session_id: session::Id, body: String) -> Request<Body> {
    Request::builder()
        .method("PUT")
        .uri("/dashboard/group/settings/update")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap()
}
