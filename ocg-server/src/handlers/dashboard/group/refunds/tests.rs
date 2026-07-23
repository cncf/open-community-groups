use axum::{
    body::{Body, to_bytes},
    http::{
        Request, StatusCode,
        header::{CONTENT_TYPE, COOKIE},
    },
};
use axum_login::tower_sessions::session;
use chrono::Utc;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    services::{notifications::MockNotificationsManager, payments::MockPaymentsManager},
    templates::dashboard::group::refunds::{
        GroupRefund, GroupRefundStatus, RefundEvent, RefundsFilters, RefundsOutput, RefundsView,
    },
    types::permissions::GroupPermission,
};

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_list_page_renders_filtered_refund_workflows() {
    // Setup identifiers and filtered refund output
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let recovery_purchase_id = Uuid::new_v4();
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
    let mut output = RefundsOutput {
        events: vec![RefundEvent {
            event_id,
            name: "Test event".to_string(),
        }],
        refunds: vec![GroupRefund {
            amount_minor: 2500,
            created_at: Utc::now(),
            currency_code: "USD".to_string(),
            email: "alice@example.test".to_string(),
            event_id,
            event_name: "Test event".to_string(),
            event_purchase_id,
            status: GroupRefundStatus::NeedsReview,
            ticket_title: "General admission".to_string(),
            updated_at: Utc::now(),
            user_id: Uuid::new_v4(),
            username: "alice".to_string(),
            attempt_count: None,
            failure_message: None,
            kind: None,
            name: Some("Alice".to_string()),
            photo_url: None,
            provider_refund_id: None,
            requested_reason: Some("Unable to attend".to_string()),
            review_note: None,
        }],
        total: 11,
    };
    let mut recovery_refund = output.refunds[0].clone();
    recovery_refund.event_purchase_id = recovery_purchase_id;
    recovery_refund.status = GroupRefundStatus::RecoveryRequired;
    output.refunds.push(recovery_refund);

    // Setup authentication, authorization, and filtered database expectations
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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_list_group_refunds()
        .times(1)
        .withf(move |gid, filters| {
            *gid == group_id
                && filters.event_id == Some(event_id)
                && filters.limit == Some(10)
                && filters.offset == Some(10)
                && filters.ts_query.as_deref() == Some("alice")
                && filters.view == RefundsView::Attention
        })
        .returning(move |_, _| Ok(output.clone()));

    // Request the filtered refunds partial
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!(
            "/dashboard/group/refunds?event_id={event_id}&limit=10&offset=10&ts_query=alice&view=attention"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the rendered operational state, filtered refresh, and stable action address
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        "text/html; charset=utf-8"
    );
    assert_eq!(
        parts.headers.get("hx-push-url").unwrap().to_str().unwrap(),
        format!(
            "/dashboard/group?tab=refunds&event_id={event_id}&limit=10&offset=10&ts_query=alice&view=attention"
        )
    );
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("Needs review"));
    assert!(body.contains("alice@example.test"));
    assert!(body.contains(&format!(
        "hx-get=\"/dashboard/group/refunds?event_id={event_id}&#38;limit=10&#38;offset=10&#38;ts_query=alice&#38;view=attention\""
    )));
    assert!(body.contains(&format!(
        "/dashboard/group/refunds/{event_purchase_id}/approve"
    )));
    assert!(body.contains("data-refund-recovery-open"));
    assert!(body.contains("id=\"refund-recovery-modal\""));
}

#[tokio::test]
async fn test_complete_refund_recovery_allows_event_manager() {
    // Setup an authenticated event manager
    let community_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    // Expect the validated recovery evidence to reach the payments service
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_complete_refund_recovery()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == user_id
                && input.event_purchase_id == event_purchase_id
                && input.group_id == group_id
                && input.recovery_note == "Verified bank receipt"
                && input.recovery_reference == "bank-transfer-123"
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Submit recovery from the refunds page
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("PUT")
        .uri("/dashboard/group/refunds/recovery")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(format!(
            "event_purchase_id={event_purchase_id}&recovery_note=Verified+bank+receipt&recovery_reference=bank-transfer-123"
        )))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check both operational views are refreshed after completion
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-event-attendees, refresh-group-refunds",
    );
}

#[tokio::test]
async fn test_complete_refund_recovery_forbids_user_without_event_write_access() {
    // Setup an authenticated group member without event-management access
    let community_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(true));
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_complete_refund_recovery().never();

    // Attempt recovery with otherwise valid evidence
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("PUT")
        .uri("/dashboard/group/refunds/recovery")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(format!(
            "event_purchase_id={event_purchase_id}&recovery_note=Verified+bank+receipt&recovery_reference=bank-transfer-123"
        )))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the route rejects recovery before calling the payments service
    assert_empty_response(&parts, &bytes, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_list_page_rejects_invalid_pagination_limit() {
    // Setup authenticated group dashboard context
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

    // Request a page size outside the validated dashboard range
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group/refunds?limit=0")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check invalid filters fail before database list work starts
    assert_non_empty_response(&parts, &bytes, StatusCode::UNPROCESSABLE_ENTITY);
}

#[test]
fn test_refunds_filters_treat_blank_event_as_unselected() {
    // Parse the browser's no-event filter value without requiring JavaScript
    let filters: RefundsFilters = crate::router::serde_qs_config()
        .deserialize_str("event_id=&ts_query=")
        .unwrap();

    // Check blank optional filters normalize to absence
    assert_eq!(filters.event_id, None);
    assert_eq!(filters.ts_query, None);
}
