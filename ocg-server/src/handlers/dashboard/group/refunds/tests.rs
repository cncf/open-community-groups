use axum::http::StatusCode;
use chrono::Utc;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::{error::HandlerError, tests::*},
    services::payments::MockPaymentsManager,
    types::{
        dashboard::{
            DASHBOARD_PAGINATION_LIMIT,
            group::refunds::{
                FinancialRecoveryKind, GroupFinancialRecovery, GroupRefund, GroupRefundStatus,
                RefundEvent, RefundsFilters, RefundsOutput, RefundsView,
            },
        },
        permissions::GroupPermission,
    },
};

#[tokio::test]
async fn test_list_page_renders_history_without_payments_setup() {
    // Setup a readable group after its current payment setup was removed
    let ids = DashboardIds::new();
    let output = RefundsOutput {
        events: vec![],
        financial_recoveries: vec![],
        refunds: vec![],
        total: 0,
    };

    // Setup authentication and historical refund-list expectations
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, false);
    db.expect_list_group_refunds()
        .times(1)
        .withf(move |gid, filters| {
            *gid == ids.group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && filters.view == RefundsView::Active
        })
        .returning(move |_, _| Ok(output.clone()));

    // Request the refunds partial without a configured payments provider; this
    // guards against gating the route on payments setup like the webhooks
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group/refunds", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check historical refund operations remain accessible
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains("Review attendee requests"));
}

#[tokio::test]
async fn test_list_page_renders_filtered_refund_workflows() {
    // Setup identifiers and filtered refund output
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let recovery_purchase_id = Uuid::new_v4();
    let mut output = RefundsOutput {
        events: vec![RefundEvent {
            event_id,
            name: "Test event".to_string(),
        }],
        financial_recoveries: vec![GroupFinancialRecovery {
            amount_minor: 125,
            attempt_count: 10,
            currency_code: "USD".to_string(),
            email: "alice@example.test".to_string(),
            event_name: "Test event".to_string(),
            failure_message: "Provider request failed".to_string(),
            kind: FinancialRecoveryKind::EventPurchaseApplicationFeeAdjustment,
            operation: "Application-fee refund".to_string(),
            payment_job_id: Uuid::new_v4(),
            username: "alice".to_string(),
            name: Some("Alice".to_string()),
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
            external: false,
            failure_message: None,
            kind: None,
            name: Some("Alice".to_string()),
            payment_job_id: None,
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
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);
    db.expect_list_group_refunds()
        .times(1)
        .withf(move |gid, filters| {
            *gid == ids.group_id
                && filters.event_id == Some(event_id)
                && filters.limit == Some(10)
                && filters.offset == Some(10)
                && filters.ts_query.as_deref() == Some("alice")
                && filters.view == RefundsView::Attention
        })
        .returning(move |_, _| Ok(output.clone()));

    // Request the filtered refunds partial
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!(
            "/dashboard/group/refunds?event_id={event_id}&limit=10&offset=10&ts_query=alice&view=attention"
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the rendered operational state, filtered refresh, and stable action address
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url").unwrap().to_str().unwrap(),
        format!(
            "/dashboard/group?tab=refunds&event_id={event_id}&limit=10&offset=10&ts_query=alice&view=attention"
        )
    );
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("Needs review"));
    assert!(body.contains("Financial work needs attention"));
    assert!(body.contains("Application-fee refund"));
    assert!(body.contains("Stripe application-fee refund ID"));
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
async fn test_list_page_rejects_invalid_pagination_limit() {
    // Expect invalid filters to fail before refund list work starts
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);

    // Request a page size outside the validated dashboard range
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group/refunds?limit=0", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the invalid page size is rejected
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "limit: lower than 1\n"
    );
}

#[tokio::test]
async fn test_complete_payment_job_recovery_records_provider_evidence() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let payment_job_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Expect provider evidence to reach the payments manager
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_complete_payment_job_recovery()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == ids.user_id
                && input.group_id == ids.group_id
                && input.payment_job_id == payment_job_id
                && input.provider_object_id == "fr_test_123"
                && input.recovery_note == "Verified Stripe activity"
                && input.recovery_reference == "ticket-456"
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Submit the payment job recovery evidence
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = form_request(
        "PUT",
        "/dashboard/group/payment-jobs/recovery",
        ids.session_id,
        format!(
            "payment_job_id={payment_job_id}&provider_object_id=fr_test_123&recovery_note=Verified+Stripe+activity&recovery_reference=ticket-456"
        ),
    );
    let (parts, bytes) = send(router, request).await;

    // Check the current financial-work view is refreshed
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-refunds",
    );
}

#[tokio::test]
async fn test_complete_payment_job_recovery_returns_rejection_message() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let payment_job_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup payments manager mock rejecting the recovery
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_complete_payment_job_recovery()
        .times(1)
        .withf(move |input| input.payment_job_id == payment_job_id)
        .returning(|_| {
            Box::pin(async {
                Err(HandlerError::Database("recoverable payment job not found".to_string()).into())
            })
        });

    // Submit the payment job recovery evidence
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = form_request(
        "PUT",
        "/dashboard/group/payment-jobs/recovery",
        ids.session_id,
        format!(
            "payment_job_id={payment_job_id}&provider_object_id=fr_test_123&recovery_note=Verified+Stripe+activity&recovery_reference=ticket-456"
        ),
    );
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "recoverable payment job not found"
    );
}

#[tokio::test]
async fn test_complete_refund_recovery_allows_event_manager() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_purchase_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Expect the validated recovery evidence to reach the payments service
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_complete_refund_recovery()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == ids.user_id
                && input.event_purchase_id == event_purchase_id
                && input.group_id == ids.group_id
                && input.recovery_note == "Verified bank receipt"
                && input.recovery_reference == "bank-transfer-123"
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Submit recovery from the refunds page
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = form_request(
        "PUT",
        "/dashboard/group/refunds/recovery",
        ids.session_id,
        format!(
            "event_purchase_id={event_purchase_id}&recovery_note=Verified+bank+receipt&recovery_reference=bank-transfer-123"
        ),
    );
    let (parts, bytes) = send(router, request).await;

    // Check both operational views are refreshed after completion
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-event-attendees, refresh-event-invitation-requests, refresh-event-waitlist, refresh-group-refunds",
    );
}

#[tokio::test]
async fn test_complete_refund_recovery_returns_rejection_message() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_purchase_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup payments manager mock rejecting the recovery
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_complete_refund_recovery()
        .times(1)
        .withf(move |input| input.event_purchase_id == event_purchase_id)
        .returning(|_| {
            Box::pin(async {
                Err(HandlerError::Database(
                    "recoverable event purchase refund not found".to_string(),
                )
                .into())
            })
        });

    // Submit recovery from the refunds page
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = form_request(
        "PUT",
        "/dashboard/group/refunds/recovery",
        ids.session_id,
        format!(
            "event_purchase_id={event_purchase_id}&recovery_note=Verified+bank+receipt&recovery_reference=bank-transfer-123"
        ),
    );
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "recoverable event purchase refund not found"
    );
}

#[tokio::test]
async fn test_retry_payment_job_requeues_selected_job() {
    // Expect the selected payment job to be requeued
    let ids = DashboardIds::new();
    let payment_job_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);
    db.expect_requeue_payment_job()
        .times(1)
        .withf(move |gid, id| *gid == ids.group_id && *id == payment_job_id)
        .returning(|_, _| Ok(()));

    // Submit a payment job retry request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/group/payment-jobs/{payment_job_id}/retry"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the current payment job view is refreshed
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-event-attendees, refresh-group-refunds",
    );
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
