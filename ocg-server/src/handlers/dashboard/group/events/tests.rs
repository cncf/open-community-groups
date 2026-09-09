use anyhow::anyhow;
use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderValue, Request, StatusCode,
        header::{CONTENT_TYPE, COOKIE},
    },
};
use axum_login::tower_sessions::session;
use serde_json::{from_slice, json, to_value};
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    config::{HttpClientConfig, PaymentsConfig, PaymentsStripeConfig},
    db::mock::MockDB,
    handlers::{error::HandlerError, tests::*},
    services::{
        events::{AutomaticTaxCheckError, EventsError, MockEventsManager},
        notifications::MockNotificationsManager,
        payments::{AutomaticTaxReadiness, AutomaticTaxReadinessError},
    },
    types::{
        dashboard::{DASHBOARD_PAGINATION_LIMIT, group::events::EventActionScope},
        event::EventFull,
        payments::{
            EventTicketPriceWindow, EventTicketType, GroupExternalPaymentsContext, PaymentMode,
            TicketTaxBehavior, TicketTaxRate,
        },
        permissions::GroupPermission,
    },
};

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_add_page_renders_external_ticketing_without_payment_recipient() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let category = sample_event_category();
    let kind = sample_event_kind_summary();
    let payment_currency_codes = vec!["EUR".to_string(), "USD".to_string()];
    let session_kind = sample_session_kind_summary();
    let sponsor = sample_group_sponsor();
    let timezones = vec!["UTC".to_string()];

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
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );
    db.expect_list_event_categories()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![category.clone()]));
    db.expect_list_event_kinds()
        .times(1)
        .returning(move || Ok(vec![kind.clone()]));
    db.expect_list_payment_currency_codes()
        .times(1)
        .returning(move || Ok(payment_currency_codes.clone()));
    db.expect_list_session_kinds()
        .times(1)
        .returning(move || Ok(vec![session_kind.clone()]));
    db.expect_list_group_sponsors()
        .times(1)
        .withf(move |id, filters, full_list| {
            *id == group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && *full_list
        })
        .returning(move |_, _, _| {
            Ok(
                crate::types::dashboard::group::sponsors::GroupSponsorsOutput {
                    sponsors: vec![sponsor.clone()],
                    total: 1,
                },
            )
        });
    db.expect_list_timezones()
        .times(1)
        .returning(move || Ok(timezones.clone()));
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(move |_, _| Ok(None));
    db.expect_get_group_external_payments_context()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| {
            Ok(GroupExternalPaymentsContext {
                configured: true,
                eligible: true,
                enabled: true,
                country_code: Some("KR".to_string()),
                default_payment_window_hours: Some(72),
                max_payment_window_hours: Some(336),
            })
        });

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_payments_cfg(PaymentsConfig::Stripe(PaymentsStripeConfig {
            connected_webhook_secret: "whsec_connect_test".to_string(),
            mode: PaymentMode::Test,
            secret_key: "sk_test_123".to_string(),
            ticket_tax_api_version: "2026-07-29.preview".to_string(),
            webhook_secret: "whsec_test_123".to_string(),

            http_client: HttpClientConfig::default(),
            platform_fee_bps: 0,
        }))
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group/events/add")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check external ticketing is available without a Stripe recipient
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains(">Tickets</"));
    assert!(body.contains("id=\"external_payment_url\""));
    assert!(body.contains("External payment URL"));
    assert!(body.contains("Set the ticket amount to 0 to make a specific tier free"));
    assert!(!body.contains("free-only"));
    assert!(!body.contains("Ticket prices are fixed at 0 until payments are configured"));
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_add_page_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let category = sample_event_category();
    let kind = sample_event_kind_summary();
    let payment_currency_codes = vec!["EUR".to_string(), "USD".to_string()];
    let session_kind = sample_session_kind_summary();
    let sponsor = sample_group_sponsor();
    let timezones = vec!["UTC".to_string()];
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
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );
    db.expect_list_event_categories()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![category.clone()]));
    db.expect_list_event_kinds()
        .times(1)
        .returning(move || Ok(vec![kind.clone()]));
    db.expect_list_payment_currency_codes()
        .times(1)
        .returning(move || Ok(payment_currency_codes.clone()));
    db.expect_list_session_kinds()
        .times(1)
        .returning(move || Ok(vec![session_kind.clone()]));
    db.expect_list_group_sponsors()
        .times(1)
        .withf(move |id, filters, full_list| {
            *id == group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && *full_list
        })
        .returning(move |_, _, _| {
            Ok(
                crate::types::dashboard::group::sponsors::GroupSponsorsOutput {
                    sponsors: vec![sponsor.clone()],
                    total: 1,
                },
            )
        });
    db.expect_list_timezones()
        .times(1)
        .returning(move || Ok(timezones.clone()));
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(move |_, _| Ok(None));
    db.expect_get_group_external_payments_context()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| {
            Ok(GroupExternalPaymentsContext {
                configured: false,
                eligible: false,
                enabled: false,
                country_code: None,
                default_payment_window_hours: None,
                max_payment_window_hours: None,
            })
        });

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_payments_cfg(PaymentsConfig::Stripe(PaymentsStripeConfig {
            connected_webhook_secret: "whsec_connect_test".to_string(),
            mode: PaymentMode::Test,
            secret_key: "sk_test_123".to_string(),
            ticket_tax_api_version: "2026-07-29.preview".to_string(),
            webhook_secret: "whsec_test_123".to_string(),

            http_client: HttpClientConfig::default(),
            platform_fee_bps: 0,
        }))
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group/events/add")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains(">Tickets</"));
    assert!(body.contains("free-only"));
    assert!(body.contains("Ticket prices are fixed at 0 until payments are configured"));
}

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut group_events = sample_group_events(Uuid::new_v4(), group_id);
    group_events.upcoming.events[0].canceled = true;
    group_events.upcoming.events[0].test_event = true;

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
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );
    db.expect_list_group_events()
        .times(1)
        .withf(move |id, filters| {
            *id == group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.past_offset == Some(0)
                && filters.upcoming_offset == Some(0)
        })
        .returning({
            let group_events = group_events.clone();
            move |_, _| Ok(group_events.clone())
        });

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_payments_cfg(PaymentsConfig::Stripe(PaymentsStripeConfig {
            connected_webhook_secret: "whsec_connect_test".to_string(),
            mode: PaymentMode::Test,
            secret_key: "sk_test_123".to_string(),
            ticket_tax_api_version: "2026-07-29.preview".to_string(),
            webhook_secret: "whsec_test_123".to_string(),

            http_client: HttpClientConfig::default(),
            platform_fee_bps: 0,
        }))
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group/events")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("aria-label=\"Open event details: Sample Event\""));
    assert!(body.contains(">Test</span>"));
    assert!(body.contains("title=\"View canceled event\""));
    assert!(!body.contains("disabled title=\"Event is canceled\""));
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_update_page_renders_paid_ticket_settings_read_only_after_purchases() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let category = sample_event_category();
    let kind = sample_event_kind_summary();
    let payment_currency_codes = vec!["EUR".to_string(), "USD".to_string()];
    let session_kind = sample_session_kind_summary();
    let sponsor = sample_group_sponsor();
    let timezones = vec!["UTC".to_string()];
    let event_full = EventFull {
        has_ticket_purchases: true,
        ticket_types: Some(vec![EventTicketType {
            event_ticket_type_id: Uuid::new_v4(),
            order: 1,
            price_windows: vec![EventTicketPriceWindow {
                amount_minor: 2500,
                ..Default::default()
            }],
            title: "General admission".to_string(),
            ..Default::default()
        }]),
        ..sample_event_full(community_id, event_id, group_id)
    };
    let event_full_db = event_full.clone();

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
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full_db.clone()));
    db.expect_list_event_categories()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![category.clone()]));
    db.expect_list_event_kinds()
        .times(1)
        .returning(move || Ok(vec![kind.clone()]));
    db.expect_list_payment_currency_codes()
        .times(1)
        .returning(move || Ok(payment_currency_codes.clone()));
    db.expect_list_session_kinds()
        .times(1)
        .returning(move || Ok(vec![session_kind.clone()]));
    db.expect_list_group_sponsors()
        .times(1)
        .withf(move |id, filters, full_list| {
            *id == group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && *full_list
        })
        .returning(move |_, _, _| {
            Ok(
                crate::types::dashboard::group::sponsors::GroupSponsorsOutput {
                    sponsors: vec![sponsor.clone()],
                    total: 1,
                },
            )
        });
    db.expect_list_timezones()
        .times(1)
        .returning(move || Ok(timezones.clone()));
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(move |_, _| Ok(None));
    db.expect_get_group_external_payments_context()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| {
            Ok(GroupExternalPaymentsContext {
                configured: false,
                eligible: false,
                enabled: false,
                country_code: None,
                default_payment_window_hours: None,
                max_payment_window_hours: None,
            })
        });
    db.expect_list_event_approved_cfs_submissions()
        .times(1)
        .withf(move |eid| *eid == event_id)
        .returning(|_| Ok(vec![]));
    db.expect_list_cfs_submission_statuses_for_review()
        .times(1)
        .returning(|| Ok(vec![]));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_payments_cfg(PaymentsConfig::Stripe(PaymentsStripeConfig {
            connected_webhook_secret: "whsec_connect_test".to_string(),
            mode: PaymentMode::Test,
            secret_key: "sk_test_123".to_string(),
            ticket_tax_api_version: "2026-07-29.preview".to_string(),
            webhook_secret: "whsec_test_123".to_string(),

            http_client: HttpClientConfig::default(),
            platform_fee_bps: 0,
        }))
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/dashboard/group/events/{event_id}/update"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("Paid ticket settings are read-only"));
    assert!(body.contains("data-disabled=\"true\""));
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_update_page_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut event_full = sample_event_full(community_id, event_id, group_id);
    event_full.payment_currency_code = Some("USD".to_string());
    let event_full_db = event_full.clone();
    let category = sample_event_category();
    let kind = sample_event_kind_summary();
    let payment_currency_codes = vec!["EUR".to_string(), "USD".to_string()];
    let session_kind = sample_session_kind_summary();
    let sponsor = sample_group_sponsor();
    let timezones = vec!["UTC".to_string()];
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
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full_db.clone()));
    db.expect_list_event_categories()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![category.clone()]));
    db.expect_list_event_kinds()
        .times(1)
        .returning(move || Ok(vec![kind.clone()]));
    db.expect_list_payment_currency_codes()
        .times(1)
        .returning(move || Ok(payment_currency_codes.clone()));
    db.expect_list_session_kinds()
        .times(1)
        .returning(move || Ok(vec![session_kind.clone()]));
    db.expect_list_group_sponsors()
        .times(1)
        .withf(move |id, filters, full_list| {
            *id == group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && *full_list
        })
        .returning(move |_, _, _| {
            Ok(
                crate::types::dashboard::group::sponsors::GroupSponsorsOutput {
                    sponsors: vec![sponsor.clone()],
                    total: 1,
                },
            )
        });
    db.expect_list_timezones()
        .times(1)
        .returning(move || Ok(timezones.clone()));
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(move |_, _| Ok(None));
    db.expect_get_group_external_payments_context()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| {
            Ok(GroupExternalPaymentsContext {
                configured: false,
                eligible: false,
                enabled: false,
                country_code: None,
                default_payment_window_hours: None,
                max_payment_window_hours: None,
            })
        });
    db.expect_list_event_approved_cfs_submissions()
        .times(1)
        .withf(move |eid| *eid == event_id)
        .returning(|_| Ok(vec![]));
    db.expect_list_cfs_submission_statuses_for_review()
        .times(1)
        .returning(|| Ok(vec![]));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_payments_cfg(PaymentsConfig::Stripe(PaymentsStripeConfig {
            connected_webhook_secret: "whsec_connect_test".to_string(),
            mode: PaymentMode::Test,
            secret_key: "sk_test_123".to_string(),
            ticket_tax_api_version: "2026-07-29.preview".to_string(),
            webhook_secret: "whsec_test_123".to_string(),

            http_client: HttpClientConfig::default(),
            platform_fee_bps: 0,
        }))
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/dashboard/group/events/{event_id}/update"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains(">Tickets</"));
    assert!(body.contains("free-only"));
}

#[tokio::test]
async fn test_automatic_tax_readiness_reports_cache() {
    // Setup an authenticated event manager and a cached provider location
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
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
        GroupPermission::EventsWrite,
    );

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_check_automatic_tax_readiness()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(|_, _, _| {
            Box::pin(async {
                Ok(AutomaticTaxReadiness {
                    cached: true,
                    fingerprint: "fingerprint".to_string(),
                    provider_tax_location_id: "loc_cached".to_string(),
                    state_code: Some("MA".to_string()),
                })
            })
        });

    // Check the protected saved-event endpoint
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_events_manager(events_manager)
        .build()
        .await;
    let response = router
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/dashboard/group/events/{event_id}/automatic-tax/readiness"
                ))
                .header(COOKIE, format!("id={session_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let payload: serde_json::Value =
        from_slice(&to_bytes(body, usize::MAX).await.unwrap()).unwrap();

    // Check the ready payload
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        payload,
        json!({"status": "ready", "state_code": "MA", "cached": true})
    );
}

#[tokio::test]
async fn test_automatic_tax_readiness_returns_bad_gateway_for_provider_failure() {
    // Setup a permitted request whose provider check fails unexpectedly
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
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
        GroupPermission::EventsWrite,
    );

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_check_automatic_tax_readiness()
        .times(1)
        .returning(|_, _, _| {
            Box::pin(async {
                Err(AutomaticTaxReadinessError::Unexpected(anyhow!("provider unavailable")).into())
            })
        });

    // Check the provider failure contract
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_events_manager(events_manager)
        .build()
        .await;
    let response = router
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/dashboard/group/events/{event_id}/automatic-tax/readiness"
                ))
                .header(COOKIE, format!("id={session_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let payload: serde_json::Value =
        from_slice(&to_bytes(body, usize::MAX).await.unwrap()).unwrap();

    // Check the not-ready payload hides the provider detail
    assert_eq!(parts.status, StatusCode::BAD_GATEWAY);
    assert_eq!(payload["status"], "not_ready");
    assert_eq!(payload["code"], "provider_unavailable");
}

#[tokio::test]
async fn test_automatic_tax_readiness_returns_internal_error_for_context_failure() {
    // Setup a permitted saved-event request whose context load fails
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
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
        GroupPermission::EventsWrite,
    );

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_check_automatic_tax_readiness()
        .times(1)
        .returning(|_, _, _| {
            Box::pin(async {
                Err(AutomaticTaxCheckError::Other(anyhow!(
                    "database unavailable"
                )))
            })
        });

    // Check the context failure keeps the regular error contract
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_events_manager(events_manager)
        .build()
        .await;
    let response = router
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/dashboard/group/events/{event_id}/automatic-tax/readiness"
                ))
                .header(COOKIE, format!("id={session_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let body = to_bytes(body, usize::MAX).await.unwrap();

    // Check the failure is not reported as a provider outage
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(body.is_empty());
}

#[tokio::test]
async fn test_automatic_tax_readiness_returns_structured_state_error() {
    // Setup a permitted saved-event request with a correctable failure
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
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
        GroupPermission::EventsWrite,
    );

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_check_automatic_tax_readiness()
        .times(1)
        .returning(|_, _, _| {
            Box::pin(async {
                Err(AutomaticTaxReadinessError::StateCodeRequired {
                    country_code: "US".to_string(),
                }
                .into())
            })
        });

    // Check the exact organizer-correctable response contract
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_events_manager(events_manager)
        .build()
        .await;
    let response = router
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/dashboard/group/events/{event_id}/automatic-tax/readiness"
                ))
                .header(COOKIE, format!("id={session_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let payload: serde_json::Value =
        from_slice(&to_bytes(body, usize::MAX).await.unwrap()).unwrap();

    // Check the not-ready payload
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(payload["status"], "not_ready");
    assert_eq!(payload["code"], "state_code_required");
    assert_eq!(payload["fields"], json!(["venue_state_code"]));
}

#[tokio::test]
async fn test_details_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let event_full = sample_event_full(community_id, event_id, group_id);
    let event_full_db = event_full.clone();

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
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full_db.clone()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/dashboard/group/events/{event_id}/details"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let payload: EventFull = from_slice(&bytes).unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("application/json"),
    );
    assert_eq!(to_value(payload).unwrap(), to_value(event_full).unwrap());
}

#[tokio::test]
async fn test_preview_uses_submitted_payload_without_event_db_calls() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock for session and permission middleware only
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let body = concat!(
        "kind_id=virtual",
        "&timezone=Europe%2FMadrid",
        "&waitlist_enabled=false",
        "&sessions%5B0%5D%5Bname%5D=Opening%20session",
        "&sessions%5B0%5D%5Bkind%5D=talk",
        "&sessions%5B0%5D%5Bstarts_at%5D=2026-06-01T19%3A00%3A00",
        "&preview_context=%7B%22kind_label%22%3A%22Virtual%22%2C%22category_label%22%3A%22Meetup%22%2C",
        "%22group%22%3A%7B%22name%22%3A%22Test%20Group%22%7D%2C",
        "%22community%22%3A%7B%22display_name%22%3A%22Test%20Community%22%7D%7D"
    );
    let request = Request::builder()
        .method("POST")
        .uri("/dashboard/group/events/preview")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains("Event preview"));
    assert!(body.contains("Missing event name"));
    assert!(body.contains("Missing start date"));
    assert!(body.contains("Online meeting details"));
    assert!(body.contains("Test Group"));
    assert!(body.contains("Test Community"));
    assert!(body.contains("7:00 PM Europe/Madrid"));
}

#[tokio::test]
async fn test_add_returns_created_with_editor_location() {
    // Setup identifiers and the submitted form
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let event_form = sample_event_form();
    let body = serde_qs::to_string(&event_form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_add()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == user_id
                && input.community_id == community_id
                && input.group_id == group_id
                && input.event.name == event_form.name
        })
        .returning(move |_| Box::pin(async move { Ok(vec![event_id, Uuid::new_v4()]) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri("/dashboard/group/events/add")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the editor reloads the base event
    assert_event_editor_location_response(&parts, &bytes, StatusCode::CREATED, event_id);
}

#[tokio::test]
async fn test_add_returns_internal_server_error_when_manager_fails() {
    // Setup identifiers and an internal manager failure
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let body = serde_qs::to_string(&sample_event_form()).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_add()
        .times(1)
        .returning(|_| Box::pin(async { Err(EventsError::Other(anyhow!("notification error"))) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri("/dashboard/group/events/add")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the internal failure is hidden
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_add_returns_unprocessable_entity_for_database_rejection() {
    // Setup identifiers and a user-facing database rejection
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let body = serde_qs::to_string(&sample_event_form()).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager.expect_add().times(1).returning(|_| {
        Box::pin(async {
            Err(EventsError::Other(
                HandlerError::Database("payments are not configured on this server".to_string())
                    .into(),
            ))
        })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri("/dashboard/group/events/add")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "payments are not configured on this server"
    );
}

#[tokio::test]
async fn test_add_returns_unprocessable_entity_for_rejection() {
    // Setup identifiers and an application rejection
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let body = serde_qs::to_string(&sample_event_form()).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager.expect_add().times(1).returning(|_| {
        Box::pin(async {
            Err(EventsError::Rejected(
                "configure a fiscal sponsor before selecting Stripe Tax Rates".to_string(),
            ))
        })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri("/dashboard/group/events/add")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "configure a fiscal sponsor before selecting Stripe Tax Rates"
    );
}

#[tokio::test]
async fn test_add_validation_rejects_invalid_body() {
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
        GroupPermission::EventsWrite,
    );

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("POST")
        .uri("/dashboard/group/events/add")
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
async fn test_add_validation_rejects_invalid_ticketing_fields() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let event_form = sample_event_form();
    let body = format!(
        concat!(
            "{}",
            "&ticket_types_present=true",
            "&ticket_types[0][active]=true",
            "&ticket_types[0][order]=1",
            "&ticket_types[0][title]=General%20admission",
            "&ticket_types[0][price_windows][0][amount_minor]=invalid",
        ),
        serde_qs::to_string(&event_form).unwrap(),
    );

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("POST")
        .uri("/dashboard/group/events/add")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_update_invalid_ticketing_fields_returns_unprocessable_entity() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let event_form = sample_event_form();
    let body = format!(
        concat!(
            "{}",
            "&discount_codes_present=true",
            "&discount_codes[0][active]=true",
            "&discount_codes[0][code]=EARLY20",
            "&discount_codes[0][kind]=percentage",
            "&discount_codes[0][title]=Early%20supporter",
            "&discount_codes[0][percentage]=invalid",
        ),
        serde_qs::to_string(&event_form).unwrap(),
    );

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );
    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/group/events/{event_id}/update"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_cancel_series_returns_no_content_with_location() {
    // Setup identifiers and the series cancellation
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
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
        GroupPermission::EventsWrite,
    );

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_cancel()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == user_id
                && input.community_id == community_id
                && input.event_id == event_id
                && input.group_id == group_id
                && input.scope == EventActionScope::Series
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!(
            "/dashboard/group/events/{event_id}/cancel?scope=series"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the events tab location
    assert_empty_hx_location_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        r#"{"path":"/dashboard/group?tab=events", "target":"body"}"#,
    );
}

#[tokio::test]
async fn test_cancel_returns_unprocessable_entity_for_database_rejection() {
    // Setup identifiers and a user-facing database rejection
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
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
        GroupPermission::EventsWrite,
    );

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_cancel()
        .times(1)
        .withf(|input| input.scope == EventActionScope::This)
        .returning(|_| {
            Box::pin(async {
                Err(EventsError::Other(
                    HandlerError::Database("event is already canceled".to_string()).into(),
                ))
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/group/events/{event_id}/cancel"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "event is already canceled"
    );
}

#[tokio::test]
async fn test_delete_returns_no_content_with_table_refresh() {
    // Setup identifiers and the deletion
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
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
        GroupPermission::EventsWrite,
    );

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_delete()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == user_id
                && input.event_id == event_id
                && input.group_id == group_id
                && input.scope == EventActionScope::This
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!("/dashboard/group/events/{event_id}/delete"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the table refresh trigger
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_publish_return_editor_success() {
    // Setup identifiers and the publication
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
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
        GroupPermission::EventsWrite,
    );

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_publish()
        .times(1)
        .withf(|input| input.scope == EventActionScope::This)
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!(
            "/dashboard/group/events/{event_id}/publish?return=editor"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the editor reload
    assert_event_editor_location_response(&parts, &bytes, StatusCode::NO_CONTENT, event_id);
}

#[tokio::test]
async fn test_publish_return_editor_with_series_scope_success() {
    // Setup identifiers and the series publication
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
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
        GroupPermission::EventsWrite,
    );

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_publish()
        .times(1)
        .withf(|input| input.scope == EventActionScope::Series)
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!(
            "/dashboard/group/events/{event_id}/publish?scope=series&return=editor"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the editor reload
    assert_event_editor_location_response(&parts, &bytes, StatusCode::NO_CONTENT, event_id);
}

#[tokio::test]
async fn test_publish_return_unknown_keeps_table_refresh() {
    // Setup identifiers and the publication
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
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
        GroupPermission::EventsWrite,
    );

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_publish()
        .times(1)
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!(
            "/dashboard/group/events/{event_id}/publish?return=elsewhere"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the table refresh trigger
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_publish_returns_unprocessable_entity_for_rejection() {
    // Setup identifiers and a sponsor rejection
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
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
        GroupPermission::EventsWrite,
    );

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager.expect_publish().times(1).returning(|_| {
        Box::pin(async {
            Err(EventsError::Rejected(
                "configure a fiscal sponsor before publishing this automatic-tax event".to_string(),
            ))
        })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/group/events/{event_id}/publish"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "configure a fiscal sponsor before publishing this automatic-tax event"
    );
}

#[tokio::test]
async fn test_tax_rates_returns_rates() {
    // Setup identifiers and the provider rates
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
        GroupPermission::Read,
    );

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_list_tax_rates()
        .times(1)
        .withf(move |cid, gid, tax_behavior| {
            *cid == community_id
                && *gid == group_id
                && *tax_behavior == TicketTaxBehavior::Inclusive
        })
        .returning(|_, _, _| {
            Box::pin(async {
                Ok(vec![TicketTaxRate {
                    display_name: "VAT".to_string(),
                    id: "txr_vat".to_string(),
                    inclusive: true,
                    percentage: "21".to_string(),

                    jurisdiction: Some("ES".to_string()),
                }])
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group/events/tax-rates?tax_behavior=inclusive")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let payload: serde_json::Value =
        from_slice(&to_bytes(body, usize::MAX).await.unwrap()).unwrap();

    // Check the rates payload
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(payload[0]["id"], json!("txr_vat"));
}

#[tokio::test]
async fn test_tax_rates_returns_unprocessable_entity_for_rejection() {
    // Setup identifiers and the sponsor rejection
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
        GroupPermission::Read,
    );

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager.expect_list_tax_rates().times(1).returning(|_, _, _| {
        Box::pin(async {
            Err(EventsError::Rejected(
                "configure a fiscal sponsor before selecting Stripe Tax Rates".to_string(),
            ))
        })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group/events/tax-rates?tax_behavior=exclusive")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "configure a fiscal sponsor before selecting Stripe Tax Rates"
    );
}

#[tokio::test]
async fn test_unpublish_series_returns_no_content_with_table_refresh() {
    // Setup identifiers and the series unpublication
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
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
        GroupPermission::EventsWrite,
    );

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_unpublish()
        .times(1)
        .withf(move |input| input.event_id == event_id && input.scope == EventActionScope::Series)
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!(
            "/dashboard/group/events/{event_id}/unpublish?scope=series"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the table refresh trigger
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_update_returns_no_content_with_editor_location() {
    // Setup identifiers and the submitted form
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let event_form = sample_event_form();
    let body = serde_qs::to_string(&event_form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_update()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == user_id
                && input.community_id == community_id
                && input.event_id == event_id
                && input.group_id == group_id
                && input.event.name == event_form.name
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/group/events/{event_id}/update"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the editor reload
    assert_event_editor_location_response(&parts, &bytes, StatusCode::NO_CONTENT, event_id);
}

// Helpers.

/// Asserts an empty event-editor HTMX location response without a table refresh.
fn assert_event_editor_location_response(
    parts: &axum::http::response::Parts,
    bytes: &[u8],
    status: StatusCode,
    event_id: Uuid,
) {
    assert_empty_hx_location_response(
        parts,
        bytes,
        status,
        &super::event_editor_location_json(event_id),
    );
    assert!(parts.headers.get("HX-Trigger").is_none());
}
