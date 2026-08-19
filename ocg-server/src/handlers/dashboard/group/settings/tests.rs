use anyhow::anyhow;
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
    handlers::tests::*,
    services::{
        notifications::MockNotificationsManager,
        payments::{AutomaticTaxReadiness, FiscalSponsorReadinessError, MockPaymentsManager},
    },
    types::{
        group::GroupParentOption,
        payments::{GroupPaymentRecipient, PaymentProvider},
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
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );
    let group = sample_group_full(community_id, group_id);
    let category = sample_group_category();
    let region = sample_group_region();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::SettingsWrite
        })
        .returning(|_, _, _, _| Ok(true));
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
        .returning(move |_| Ok(vec![category.clone()]));
    db.expect_list_group_parent_options()
        .times(1)
        .withf(move |cid, uid, gid| {
            *cid == community_id && *uid == user_id && *gid == Some(group_id)
        })
        .returning(|_, _, _| Ok(vec![]));
    db.expect_list_regions()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![region.clone()]));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group/settings/update")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
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
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );
    let group = sample_group_full(community_id, group_id);
    let category = sample_group_category();
    let parent_option = GroupParentOption {
        active: false,
        group_id: parent_group_id,
        is_current: true,
        is_selectable: false,
        name: "Inactive Parent".to_string(),
    };
    let region = sample_group_region();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::SettingsWrite
        })
        .returning(|_, _, _, _| Ok(true));
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
        .returning(move |_| Ok(vec![category.clone()]));
    db.expect_list_group_parent_options()
        .times(1)
        .withf(move |cid, uid, gid| {
            *cid == community_id && *uid == user_id && *gid == Some(group_id)
        })
        .returning(move |_, _, _| Ok(vec![parent_option.clone()]));
    db.expect_list_regions()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![region.clone()]));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group/settings/update")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
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
async fn test_update_page_db_error() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::SettingsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_get_group_full()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(move |_, _| Err(anyhow!("db error")));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group/settings/update")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_update_normalizes_unchanged_payment_recipient() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );
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
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::SettingsWrite
        })
        .returning(|_, _, _, _| Ok(true));
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
    let request = Request::builder()
        .method("PUT")
        .uri("/dashboard/group/settings/update")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
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
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::SettingsWrite
        })
        .returning(|_, _, _, _| Ok(true));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri("/dashboard/group/settings/update")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from("invalid"))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
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
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );
    let mut update = sample_group_update();
    update.payment_recipient = Some(GroupPaymentRecipient {
        provider: PaymentProvider::Stripe,
        recipient_id: "acct_new".to_string(),
        seller_display_name: "New Sponsor".to_string(),
    });
    let body = serde_qs::to_string(&update).unwrap();

    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::SettingsWrite
        })
        .returning(|_, _, _, _| Ok(true));
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
        .withf(|recipient, require_automatic_tax| {
            recipient.recipient_id == "acct_new" && *require_automatic_tax
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
    let request = Request::builder()
        .method("PUT")
        .uri("/dashboard/group/settings/update")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();

    assert_eq!(response.status(), StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_update_rejects_changed_sponsor_without_required_automatic_tax() {
    // Setup an authenticated settings update selecting a fiscal sponsor
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );
    let mut update = sample_group_update();
    update.payment_recipient = Some(GroupPaymentRecipient {
        provider: PaymentProvider::Stripe,
        recipient_id: "acct_unready".to_string(),
        seller_display_name: "Unready Sponsor".to_string(),
    });
    let body = serde_qs::to_string(&update).unwrap();

    // Authorize the request while forbidding any database write
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::SettingsWrite
        })
        .returning(|_, _, _, _| Ok(true));
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
    db.expect_group_requires_automatic_tax_readiness()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(true));
    db.expect_update_group().never();

    // Reject the sponsor at the provider boundary before persistence
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_validate_fiscal_sponsor()
        .withf(|recipient, require_automatic_tax| {
            recipient.provider == PaymentProvider::Stripe
                && recipient.recipient_id == "acct_unready"
                && *require_automatic_tax
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
    let request = Request::builder()
        .method("PUT")
        .uri("/dashboard/group/settings/update")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();

    // Check the provider failure prevents persistence
    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}
