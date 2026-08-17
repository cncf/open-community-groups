use std::sync::Arc;

use anyhow::anyhow;
use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderValue, Request, StatusCode,
        header::{CONTENT_TYPE, COOKIE},
    },
};
use axum_login::tower_sessions::session;
use chrono::Utc;
use mockall::Sequence;
use serde_json::{from_slice, from_value, json, to_value};
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    config::{PaymentsConfig, PaymentsStripeConfig},
    db::mock::MockDB,
    handlers::{error::HandlerError, tests::*},
    services::{
        meetings::MeetingProvider,
        notifications::{MockNotificationsManager, NotificationKind},
        payments::{
            AutomaticTaxReadiness, AutomaticTaxReadinessError, DynPaymentsManager,
            FiscalSponsorReadinessError, MockPaymentsManager,
        },
    },
    templates::{
        dashboard::{DASHBOARD_PAGINATION_LIMIT, group::events::EventRecurrencePattern},
        notifications::{
            EventCanceled, EventPaidConfigured, EventPublished, EventRescheduled,
            EventSeriesCanceled, EventSeriesPublished, SpeakerWelcome,
        },
    },
    types::{
        event::{EventFull, EventSummary, Speaker},
        payments::{
            EventTicketPriceWindow, EventTicketType, PaymentMode, PaymentProvider,
            TicketTaxBehavior, TicketTaxCalculationMode,
        },
        permissions::GroupPermission,
    },
};

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_add_page_success() {
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
    let category = sample_event_category();
    let kind = sample_event_kind_summary();
    let payment_currency_codes = vec!["EUR".to_string(), "USD".to_string()];
    let session_kind = sample_session_kind_summary();
    let sponsor = sample_group_sponsor();
    let timezones = vec!["UTC".to_string()];
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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
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
                crate::templates::dashboard::group::sponsors::GroupSponsorsOutput {
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
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );
    let mut group_events = sample_group_events(Uuid::new_v4(), group_id);
    group_events.upcoming.events[0].canceled = true;
    group_events.upcoming.events[0].test_event = true;

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
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
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );
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
                crate::templates::dashboard::group::sponsors::GroupSponsorsOutput {
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
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );
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
                crate::templates::dashboard::group::sponsors::GroupSponsorsOutput {
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
async fn test_automatic_tax_readiness_uses_persisted_event_and_reports_cache() {
    // Setup an authenticated event manager and persisted venue
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut event = sample_event_full(community_id, event_id, group_id);
    event.venue_address = Some("1 Main St".to_string());
    event.venue_city = Some("Málaga".to_string());
    event.venue_country_code = Some("ES".to_string());
    event.venue_name = Some("Venue".to_string());
    event.venue_state_code = Some("MA".to_string());
    event.venue_zip_code = Some("29006".to_string());
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_get_event_full()
        .times(1)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_group_payment_recipient()
        .times(1)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));

    // Return a matching provider location through the typed manager boundary
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_ensure_automatic_tax_readiness()
        .withf(|recipient, venue| {
            recipient.recipient_id == "acct_test"
                && venue.country_code == "ES"
                && venue.state_code.as_deref() == Some("MA")
        })
        .times(1)
        .returning(|_, _| {
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
        .with_payments_manager(payments_manager)
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

    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        payload,
        json!({"status": "ready", "state_code": "MA", "cached": true})
    );
}

#[tokio::test]
async fn test_automatic_tax_readiness_returns_structured_state_error() {
    // Setup a permitted saved-event request
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    db.expect_user_has_group_permission()
        .times(1)
        .returning(|_, _, _, permission| Ok(permission == GroupPermission::EventsWrite));
    db.expect_get_event_full()
        .times(1)
        .returning(move |_, _, _| Ok(sample_event_full(community_id, event_id, group_id)));
    db.expect_get_group_payment_recipient()
        .times(1)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_ensure_automatic_tax_readiness()
        .times(1)
        .returning(|_, _| {
            Box::pin(async {
                Err(AutomaticTaxReadinessError::StateCodeRequired {
                    country_code: "US".to_string(),
                })
            })
        });

    // Check the exact organizer-correctable response contract
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(payments_manager)
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
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );
    let event_full = sample_event_full(community_id, event_id, group_id);
    let event_full_db = event_full.clone();

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
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );

    // Setup database mock for session and permission middleware only
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
async fn test_add_free_success() {
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
    let event_form = sample_event_form();
    let body = serde_qs::to_string(&event_form).unwrap();

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    let mut tx = MockDB::new();
    tx.expect_add_event()
        .times(1)
        .withf(
            move |uid, id, event, cfg_max_participants, payment_provider| {
                let event_name = event
                    .get("name")
                    .and_then(serde_json::Value::as_str)
                    .unwrap_or_default();
                *uid == user_id
                    && *id == group_id
                    && event_name == event_form.name
                    && cfg_max_participants.get(&MeetingProvider::Zoom) == Some(&100)
                    && payment_provider.is_none()
            },
        )
        .returning(move |_, _, _, _, _| Ok(Uuid::new_v4()));
    expect_successful_transaction(&mut db, tx);

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup meetings config with Zoom
    let meetings_cfg = sample_zoom_meetings_cfg("test-token");

    // Setup router with meetings config and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_meetings_cfg(meetings_cfg)
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

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::CREATED,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_add_paid_event_notification_failure_rolls_back() {
    // Setup identifiers and paid event input
    let admin_id = Uuid::new_v4();
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
    let body = sample_paid_event_body();
    let event_summary = sample_event_summary(event_id, group_id);

    // Setup authentication and permission checks
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

    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));

    // Setup a successful mutation followed by a required notification failure
    let mut tx = MockDB::new();
    tx.expect_add_event()
        .times(1)
        .withf(move |uid, gid, _, _, payment_provider| {
            *uid == user_id
                && *gid == group_id
                && *payment_provider == Some(PaymentProvider::Stripe)
        })
        .returning(move |_, _, _, _, _| Ok(event_id));
    tx.expect_list_community_admin_ids()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![admin_id]));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_summary.clone()));
    tx.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    tx.expect_enqueue_notification()
        .times(1)
        .returning(|_| Err(anyhow!("notification error")));
    expect_rolled_back_transaction(&mut db, tx);

    // Send the paid event creation request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_cfg(sample_payments_cfg())
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

    // Check the failed notification rolls back the event
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_add_paid_recurring_success() {
    // Setup identifiers and recurring paid event input
    let admin_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let related_event_id = Uuid::new_v4();
    let third_event_id = Uuid::new_v4();
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
    let mut event_form = sample_event_form();
    event_form.ends_at = Some((Utc::now() + chrono::Duration::days(8)).naive_utc());
    event_form.recurrence_additional_occurrences = Some(2);
    event_form.recurrence_pattern = Some(EventRecurrencePattern::Weekly);
    event_form.starts_at = Some((Utc::now() + chrono::Duration::days(7)).naive_utc());
    let body = format!(
        concat!(
            "{}",
            "&payment_currency_code=USD",
            "&ticket_types_present=true",
            "&ticket_types[0][active]=true",
            "&ticket_types[0][order]=1",
            "&ticket_types[0][price_windows][0][amount_minor]=1500",
            "&ticket_types[0][seats_total]=25",
            "&ticket_types[0][title]=General%20admission"
        ),
        serde_qs::to_string(&event_form).unwrap(),
    );

    // Setup authentication and permission checks
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

    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));

    // Setup atomic recurring creation and aggregate notification expectations
    let mut tx = MockDB::new();
    tx.expect_add_event().never();
    let returned_event_ids = vec![event_id, related_event_id, third_event_id];
    tx.expect_add_event_series()
        .times(1)
        .withf(move |uid, gid, events, _, _, payment_provider| {
            *uid == user_id
                && *gid == group_id
                && events.len() == 3
                && events.iter().all(|event| {
                    event["ticket_types"][0]["price_windows"][0]["amount_minor"].as_i64()
                        == Some(1500)
                })
                && *payment_provider == Some(PaymentProvider::Stripe)
        })
        .returning(move |_, _, _, _, _, _| Ok(returned_event_ids.clone()));
    tx.expect_list_community_admin_ids()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![admin_id]));
    let event_summary = sample_event_summary(event_id, group_id);
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_summary.clone()));
    let related_event_summary = sample_event_summary(related_event_id, group_id);
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == community_id && *gid == group_id && *eid == related_event_id
        })
        .returning(move |_, _, _| Ok(related_event_summary.clone()));
    let third_event_summary = sample_event_summary(third_event_id, group_id);
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == community_id && *gid == group_id && *eid == third_event_id
        })
        .returning(move |_, _, _| Ok(third_event_summary.clone()));
    tx.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    let expected_event_ids = vec![event_id, related_event_id, third_event_id];
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventPaidConfigured)
                && notification.recipients == vec![admin_id]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventPaidConfigured>(value.clone()).is_ok_and(|template| {
                        template.events.iter().map(|event| event.event_id).collect::<Vec<_>>()
                            == expected_event_ids
                    })
                })
        })
        .returning(|_| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Send the paid recurring event creation request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_cfg(PaymentsConfig::Stripe(PaymentsStripeConfig {
            connected_webhook_secret: "whsec_connect_test".to_string(),
            mode: PaymentMode::Test,
            secret_key: "sk_test_123".to_string(),
            ticket_tax_api_version: "2026-07-29.preview".to_string(),
            webhook_secret: "whsec_test_123".to_string(),

            platform_fee_bps: 0,
        }))
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

    // Check the recurring creation response
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::CREATED,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_add_paid_rejects_unready_fiscal_sponsor_without_persisting() {
    // Setup an authenticated automatic-tax paid event request
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

    // Authorize the request and return its configured sponsor
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
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));

    // Reject the sponsor before the event transaction can start
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_configured_provider()
        .times(1)
        .return_const(Some(PaymentProvider::Stripe));
    payments_manager
        .expect_validate_fiscal_sponsor()
        .withf(|recipient, require_automatic_tax| {
            recipient.provider == PaymentProvider::Stripe
                && recipient.recipient_id == "acct_test"
                && *require_automatic_tax
        })
        .times(1)
        .returning(|_, _| {
            Box::pin(async {
                Err(FiscalSponsorReadinessError::NotReady(
                    "Stripe Tax is not active".to_string(),
                ))
            })
        });

    // Submit the paid event through the routed handler
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri("/dashboard/group/events/add")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(sample_paid_event_body()))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();

    // Check no database transaction was opened after provider rejection
    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_add_paid_success() {
    let admin_id = Uuid::new_v4();
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
    let body = sample_paid_event_body();
    let event_summary = sample_event_summary(event_id, group_id);

    // Setup authentication and permission checks
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

    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));

    // Setup atomic creation and notification expectations
    let mut tx = MockDB::new();
    tx.expect_add_event()
        .times(1)
        .withf(move |uid, gid, event, _, payment_provider| {
            *uid == user_id
                && *gid == group_id
                && event
                    .get("ticket_types")
                    .and_then(serde_json::Value::as_array)
                    .is_some_and(|ticket_types| !ticket_types.is_empty())
                && event.get("_payment_validation").is_some_and(|validation| {
                    validation["require_automatic_tax"] == true
                        && validation["expected_payment_recipient"]["recipient_id"] == "acct_test"
                        && validation["validated_payment_recipient"]["recipient_id"] == "acct_test"
                })
                && *payment_provider == Some(PaymentProvider::Stripe)
        })
        .returning(move |_, _, _, _, _| Ok(event_id));
    tx.expect_list_community_admin_ids()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![admin_id]));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_summary.clone()));
    tx.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventPaidConfigured)
                && notification.recipients == vec![admin_id]
                && notification.attachments.is_empty()
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventPaidConfigured>(value.clone()).is_ok_and(|template| {
                        template.event_count == 1 && template.events[0].event_id == event_id
                    })
                })
        })
        .returning(|_| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Send the paid event creation request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_cfg(sample_payments_cfg())
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

    // Check the event creation response
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::CREATED,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_add_recurring_success() {
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
    let mut event_form = sample_event_form();
    event_form.ends_at = Some((Utc::now() + chrono::Duration::days(8)).naive_utc());
    event_form.recurrence_additional_occurrences = Some(2);
    event_form.recurrence_pattern = Some(EventRecurrencePattern::Weekly);
    event_form.starts_at = Some((Utc::now() + chrono::Duration::days(7)).naive_utc());
    let event_name = event_form.name.clone();
    let body = serde_qs::to_string(&event_form).unwrap();

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    let mut tx = MockDB::new();
    tx.expect_add_event().never();
    tx.expect_add_event_series()
        .times(1)
        .withf(
            move |uid, id, events, recurrence, cfg_max_participants, payment_provider| {
                let names_match = events.iter().all(|event| {
                    event
                        .get("name")
                        .and_then(serde_json::Value::as_str)
                        .is_some_and(|name| name == event_name)
                });

                *uid == user_id
                    && *id == group_id
                    && events.len() == 3
                    && names_match
                    && recurrence
                        .get("additional_occurrences")
                        .and_then(serde_json::Value::as_i64)
                        == Some(2)
                    && recurrence.get("pattern").and_then(serde_json::Value::as_str)
                        == Some("weekly")
                    && cfg_max_participants.get(&MeetingProvider::Zoom) == Some(&100)
                    && payment_provider.is_none()
            },
        )
        .returning(move |_, _, _, _, _, _| {
            Ok(vec![Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4()])
        });
    expect_successful_transaction(&mut db, tx);

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router with meetings config and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_meetings_cfg(sample_zoom_meetings_cfg("test-token"))
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

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::CREATED,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_add_validation_rejects_invalid_body() {
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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));

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
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );
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
async fn test_add_validation_rejects_paid_event_without_payments() {
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
    let body = sample_paid_event_body();

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_get_group_payment_recipient().times(0);
    let mut tx = MockDB::new();
    tx.expect_add_event()
        .times(1)
        .withf(move |uid, gid, _, _, payment_provider| {
            *uid == user_id && *gid == group_id && payment_provider.is_none()
        })
        .returning(|_, _, _, _, _| {
            Err(anyhow::Error::new(HandlerError::Database(
                "payments are not configured on this server".to_string(),
            )))
        });
    expect_rolled_back_transaction(&mut db, tx);

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
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "payments are not configured on this server",
    );
}

#[test]
fn test_is_event_payload_paid_capable_accepts_any_positive_price() {
    let payload = json!({
        "ticket_types": [
            {
                "active": false,
                "availability": "invitation_only",
                "price_windows": [
                    {"amount_minor": 0},
                    {"amount_minor": 1}
                ]
            }
        ]
    });

    assert!(super::is_event_payload_paid_capable(&payload));
}

#[test]
fn test_is_event_payload_paid_capable_rejects_missing_ticket_types() {
    assert!(!super::is_event_payload_paid_capable(&json!({})));
    assert!(!super::is_event_payload_paid_capable(
        &json!({"ticket_types": null})
    ));
}

#[test]
fn test_is_event_payload_paid_capable_rejects_zero_prices() {
    let payload = json!({
        "ticket_types": [
            {
                "price_windows": [
                    {"amount_minor": 0},
                    {"amount_minor": -1}
                ]
            }
        ]
    });

    assert!(!super::is_event_payload_paid_capable(&payload));
}

#[allow(clippy::too_many_lines)]
#[tokio::test]
async fn test_cancel_success() {
    // Setup identifiers and data structures
    let attendee_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let speaker_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );
    let event_summary = sample_event_summary(event_id, group_id);
    let event_full = EventFull {
        speakers: vec![Speaker {
            featured: false,
            user: sample_template_user_with_id(speaker_id),
        }],
        ..sample_event_full(community_id, event_id, group_id)
    };
    let site_settings = sample_site_settings();
    let site_settings_for_notifications = site_settings.clone();

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    let mut sequence = Sequence::new();
    let mut tx = MockDB::new();
    tx.expect_lock_events_for_cancellation()
        .times(1)
        .withf(move |gid, event_ids| *gid == group_id && event_ids == [event_id].as_slice())
        .in_sequence(&mut sequence)
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .in_sequence(&mut sequence)
        .returning(move |_, _, _| Ok(event_summary.clone()));
    tx.expect_cancel_event()
        .times(1)
        .withf(move |uid, id, eid| *uid == user_id && *id == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(()));
    tx.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full.clone()));
    tx.expect_list_event_attendees_ids()
        .times(1)
        .withf(move |gid, eid, checked_in_only| {
            *gid == group_id && *eid == event_id && !checked_in_only
        })
        .returning(move |_, _, _| Ok(vec![attendee_id]));
    tx.expect_list_event_waitlist_ids()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .returning(move |_, _| Ok(vec![]));
    tx.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventCanceled)
                && notification.recipients.len() == 2
                && notification.recipients.contains(&attendee_id)
                && notification.recipients.contains(&speaker_id)
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventCanceled>(value.clone()).is_ok_and(|template| {
                        template.link == "/test/group/npq6789/event/abc1234"
                            && template.theme.primary_color
                                == site_settings_for_notifications.theme.primary_color
                    })
                })
        })
        .returning(|_| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/group/events/{event_id}/cancel"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_hx_location_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        r#"{"path":"/dashboard/group?tab=events", "target":"body"}"#,
    );
}

#[tokio::test]
async fn test_cancel_test_event_no_notification() {
    // Setup identifiers and data structures
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
    let test_event = EventSummary {
        test_event: true,
        ..sample_event_summary(event_id, group_id)
    };

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    let mut sequence = Sequence::new();
    let mut tx = MockDB::new();
    tx.expect_lock_events_for_cancellation()
        .times(1)
        .withf(move |gid, event_ids| *gid == group_id && event_ids == [event_id].as_slice())
        .in_sequence(&mut sequence)
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .in_sequence(&mut sequence)
        .returning(move |_, _, _| Ok(test_event.clone()));
    tx.expect_cancel_event()
        .times(1)
        .withf(move |uid, id, eid| *uid == user_id && *id == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/group/events/{event_id}/cancel"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_hx_location_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        r#"{"path":"/dashboard/group?tab=events", "target":"body"}"#,
    );
}

#[allow(clippy::too_many_lines)]
#[tokio::test]
async fn test_cancel_series_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let related_event_id = Uuid::new_v4();
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
    let series_event_ids = vec![event_id, related_event_id];
    let expected_lock_event_ids = series_event_ids.clone();
    let expected_series_event_ids = series_event_ids.clone();
    let event_summary = EventSummary {
        published: false,
        ..sample_event_summary(event_id, group_id)
    };
    let related_event_summary = EventSummary {
        event_id: related_event_id,
        published: false,
        ..sample_event_summary(related_event_id, group_id)
    };

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    let mut sequence = Sequence::new();
    let mut tx = MockDB::new();
    tx.expect_list_event_series_cancelable_event_ids()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .in_sequence(&mut sequence)
        .returning(move |_, _| Ok(series_event_ids.clone()));
    tx.expect_lock_events_for_cancellation()
        .times(1)
        .withf(move |gid, event_ids| {
            *gid == group_id && event_ids == expected_lock_event_ids.as_slice()
        })
        .in_sequence(&mut sequence)
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .in_sequence(&mut sequence)
        .returning(move |_, _, _| Ok(event_summary.clone()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == community_id && *gid == group_id && *eid == related_event_id
        })
        .in_sequence(&mut sequence)
        .returning(move |_, _, _| Ok(related_event_summary.clone()));
    tx.expect_cancel_event().times(0);
    tx.expect_cancel_event_series_events()
        .times(1)
        .withf(move |uid, gid, event_ids| {
            *uid == user_id && *gid == group_id && event_ids == expected_series_event_ids.as_slice()
        })
        .returning(move |_, _, _| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
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

    // Check response matches expectations
    assert_empty_hx_location_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        r#"{"path":"/dashboard/group?tab=events", "target":"body"}"#,
    );
}

#[allow(clippy::too_many_lines)]
#[tokio::test]
async fn test_cancel_series_sends_aggregate_notification() {
    // Setup identifiers and data structures
    let attendee_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let related_event_id = Uuid::new_v4();
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
    let event_summary = EventSummary {
        published: true,
        ..sample_event_summary(event_id, group_id)
    };
    let related_event_summary = EventSummary {
        event_id: related_event_id,
        published: true,
        ..sample_event_summary(related_event_id, group_id)
    };
    let event_full = EventFull {
        event_id,
        name: "First Series Event".to_string(),
        speakers: vec![],
        ..sample_event_full(community_id, event_id, group_id)
    };
    let related_event_full = EventFull {
        event_id: related_event_id,
        name: "Second Series Event".to_string(),
        speakers: vec![],
        ..sample_event_full(community_id, related_event_id, group_id)
    };
    let series_event_ids = vec![event_id, related_event_id];
    let expected_lock_event_ids = series_event_ids.clone();
    let expected_series_event_ids = series_event_ids.clone();
    let site_settings = sample_site_settings();
    let site_settings_for_notification = site_settings.clone();

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    let mut sequence = Sequence::new();
    let mut tx = MockDB::new();
    tx.expect_list_event_series_cancelable_event_ids()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .in_sequence(&mut sequence)
        .returning(move |_, _| Ok(series_event_ids.clone()));
    tx.expect_lock_events_for_cancellation()
        .times(1)
        .withf(move |gid, event_ids| {
            *gid == group_id && event_ids == expected_lock_event_ids.as_slice()
        })
        .in_sequence(&mut sequence)
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .in_sequence(&mut sequence)
        .returning(move |_, _, _| Ok(event_summary.clone()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == community_id && *gid == group_id && *eid == related_event_id
        })
        .in_sequence(&mut sequence)
        .returning(move |_, _, _| Ok(related_event_summary.clone()));
    tx.expect_cancel_event_series_events()
        .times(1)
        .withf(move |uid, gid, event_ids| {
            *uid == user_id && *gid == group_id && event_ids == expected_series_event_ids.as_slice()
        })
        .returning(move |_, _, _| Ok(()));
    tx.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full.clone()));
    tx.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == community_id && *gid == group_id && *eid == related_event_id
        })
        .returning(move |_, _, _| Ok(related_event_full.clone()));
    tx.expect_list_event_attendees_ids()
        .times(2)
        .withf(move |gid, eid, checked_in_only| {
            *gid == group_id && (*eid == event_id || *eid == related_event_id) && !checked_in_only
        })
        .returning(move |_, _, _| Ok(vec![attendee_id]));
    tx.expect_list_event_waitlist_ids()
        .times(2)
        .withf(move |gid, eid| *gid == group_id && (*eid == event_id || *eid == related_event_id))
        .returning(move |_, _| Ok(vec![]));
    tx.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventSeriesCanceled)
                && notification.attachments.is_empty()
                && notification.recipients == vec![attendee_id]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventSeriesCanceled>(value.clone()).is_ok_and(|template| {
                        template.event_count == 2
                            && template.events.len() == 2
                            && template.theme.primary_color
                                == site_settings_for_notification.theme.primary_color
                    })
                })
        })
        .returning(|_| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
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

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert!(bytes.is_empty());
}

#[allow(clippy::too_many_lines)]
#[tokio::test]
async fn test_publish_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let member_id = Uuid::new_v4();
    let speaker_id = Uuid::new_v4();
    let team_member_id = Uuid::new_v4();
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
    let unpublished_event = EventSummary {
        published: false,
        ..sample_event_summary(event_id, group_id)
    };
    let event_full = EventFull {
        speakers: vec![Speaker {
            featured: false,
            user: sample_template_user_with_id(speaker_id),
        }],
        ..sample_event_full(community_id, event_id, group_id)
    };
    let site_settings = sample_site_settings();
    let site_settings_for_member_notification = site_settings.clone();
    let site_settings_for_speaker_notification = site_settings.clone();
    let mut expected_member_recipients = vec![member_id, team_member_id];
    expected_member_recipients.sort();

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    let mut tx = MockDB::new();
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(unpublished_event.clone()));
    tx.expect_publish_event()
        .times(1)
        .withf(move |uid, gid, eid, payment_provider, payment_validation| {
            *uid == user_id
                && *gid == group_id
                && *eid == event_id
                && payment_provider.is_none()
                && payment_validation.is_none()
        })
        .returning(move |_, _, _, _, _| Ok(()));
    tx.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full.clone()));
    tx.expect_list_group_members_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![member_id]));
    tx.expect_list_group_team_members_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![team_member_id]));
    tx.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventPublished)
                && notification.recipients == expected_member_recipients
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventPublished>(value.clone()).is_ok_and(|template| {
                        template.theme.primary_color
                            == site_settings_for_member_notification.theme.primary_color
                    })
                })
        })
        .returning(|_| Ok(()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::SpeakerWelcome)
                && notification.recipients == vec![speaker_id]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<SpeakerWelcome>(value.clone()).is_ok_and(|template| {
                        template.theme.primary_color
                            == site_settings_for_speaker_notification.theme.primary_color
                    })
                })
        })
        .returning(|_| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/group/events/{event_id}/publish"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_publish_test_event_no_notification() {
    // Setup identifiers and data structures
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
    let unpublished_test_event = EventSummary {
        published: false,
        test_event: true,
        ..sample_event_summary(event_id, group_id)
    };

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    let mut tx = MockDB::new();
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(unpublished_test_event.clone()));
    tx.expect_publish_event()
        .times(1)
        .withf(move |uid, gid, eid, payment_provider, payment_validation| {
            *uid == user_id
                && *gid == group_id
                && *eid == event_id
                && payment_provider.is_none()
                && payment_validation.is_none()
        })
        .returning(move |_, _, _, _, _| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/group/events/{event_id}/publish"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_publish_series_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let related_event_id = Uuid::new_v4();
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
    let event_summary = EventSummary {
        published: true,
        ..sample_event_summary(event_id, group_id)
    };
    let related_event_summary = EventSummary {
        event_id: related_event_id,
        published: true,
        ..sample_event_summary(related_event_id, group_id)
    };
    let series_event_ids = vec![event_id, related_event_id];
    let expected_series_event_ids = series_event_ids.clone();

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    let mut tx = MockDB::new();
    tx.expect_list_event_series_publishable_event_ids()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .returning(move |_, _| Ok(series_event_ids.clone()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_summary.clone()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == community_id && *gid == group_id && *eid == related_event_id
        })
        .returning(move |_, _, _| Ok(related_event_summary.clone()));
    tx.expect_publish_event().times(0);
    tx.expect_publish_event_series_events()
        .times(1)
        .withf(
            move |uid, gid, event_ids, payment_provider, payment_validation| {
                *uid == user_id
                    && *gid == group_id
                    && event_ids == expected_series_event_ids.as_slice()
                    && payment_provider.is_none()
                    && payment_validation.is_none()
            },
        )
        .returning(move |_, _, _, _, _| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!(
            "/dashboard/group/events/{event_id}/publish?scope=series"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[allow(clippy::too_many_lines)]
#[tokio::test]
async fn test_publish_series_sends_aggregate_notification() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let member_id = Uuid::new_v4();
    let related_event_id = Uuid::new_v4();
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
    let event_summary = EventSummary {
        published: false,
        ..sample_event_summary(event_id, group_id)
    };
    let related_event_summary = EventSummary {
        event_id: related_event_id,
        published: false,
        ..sample_event_summary(related_event_id, group_id)
    };
    let event_full = EventFull {
        event_id,
        name: "First Series Event".to_string(),
        speakers: vec![],
        ..sample_event_full(community_id, event_id, group_id)
    };
    let related_event_full = EventFull {
        event_id: related_event_id,
        name: "Second Series Event".to_string(),
        speakers: vec![],
        ..sample_event_full(community_id, related_event_id, group_id)
    };
    let series_event_ids = vec![event_id, related_event_id];
    let expected_series_event_ids = series_event_ids.clone();
    let site_settings = sample_site_settings();
    let site_settings_for_notification = site_settings.clone();

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    let mut tx = MockDB::new();
    tx.expect_list_event_series_publishable_event_ids()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .returning(move |_, _| Ok(series_event_ids.clone()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_summary.clone()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == community_id && *gid == group_id && *eid == related_event_id
        })
        .returning(move |_, _, _| Ok(related_event_summary.clone()));
    tx.expect_publish_event_series_events()
        .times(1)
        .withf(
            move |uid, gid, event_ids, payment_provider, payment_validation| {
                *uid == user_id
                    && *gid == group_id
                    && event_ids == expected_series_event_ids.as_slice()
                    && payment_provider.is_none()
                    && payment_validation.is_none()
            },
        )
        .returning(move |_, _, _, _, _| Ok(()));
    tx.expect_list_group_members_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![member_id]));
    tx.expect_list_group_team_members_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![]));
    tx.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full.clone()));
    tx.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == community_id && *gid == group_id && *eid == related_event_id
        })
        .returning(move |_, _, _| Ok(related_event_full.clone()));
    tx.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventSeriesPublished)
                && notification.attachments.is_empty()
                && notification.recipients == vec![member_id]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventSeriesPublished>(value.clone()).is_ok_and(|template| {
                        template.event_count == 2
                            && template.events.len() == 2
                            && template.theme.primary_color
                                == site_settings_for_notification.theme.primary_color
                    })
                })
        })
        .returning(|_| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!(
            "/dashboard/group/events/{event_id}/publish?scope=series"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_publish_already_published_no_notification() {
    // Setup identifiers and data structures
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
    // Event is already published, so no notification should be sent
    let already_published_event = EventSummary {
        published: true,
        ..sample_event_summary(event_id, group_id)
    };

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    let mut tx = MockDB::new();
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(already_published_event.clone()));
    tx.expect_publish_event()
        .times(1)
        .withf(move |uid, gid, eid, payment_provider, payment_validation| {
            *uid == user_id
                && *gid == group_id
                && *eid == event_id
                && payment_provider.is_none()
                && payment_validation.is_none()
        })
        .returning(move |_, _, _, _, _| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Setup notifications manager mock (no enqueue expected)
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/group/events/{event_id}/publish"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[allow(clippy::too_many_lines)]
#[tokio::test]
async fn test_publish_speakers_only() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let speaker_id = Uuid::new_v4();
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
    let unpublished_event = EventSummary {
        published: false,
        ..sample_event_summary(event_id, group_id)
    };
    let event_full = EventFull {
        speakers: vec![Speaker {
            featured: false,
            user: sample_template_user_with_id(speaker_id),
        }],
        ..sample_event_full(community_id, event_id, group_id)
    };
    let site_settings = sample_site_settings();
    let site_settings_for_speaker_notification = site_settings.clone();

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    let mut tx = MockDB::new();
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(unpublished_event.clone()));
    tx.expect_publish_event()
        .times(1)
        .withf(move |uid, gid, eid, payment_provider, payment_validation| {
            *uid == user_id
                && *gid == group_id
                && *eid == event_id
                && payment_provider.is_none()
                && payment_validation.is_none()
        })
        .returning(move |_, _, _, _, _| Ok(()));
    tx.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full.clone()));
    // No group members
    tx.expect_list_group_members_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![]));
    tx.expect_list_group_team_members_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![]));
    tx.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::SpeakerWelcome)
                && notification.recipients == vec![speaker_id]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<SpeakerWelcome>(value.clone()).is_ok_and(|template| {
                        template.theme.primary_color
                            == site_settings_for_speaker_notification.theme.primary_color
                    })
                })
        })
        .returning(|_| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/group/events/{event_id}/publish"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_publish_validation_rechecks_every_manual_tax_selection() {
    // Setup paid and free manual-tax events with separate rate selections
    let community_id = Uuid::new_v4();
    let free_event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let paid_event_id = Uuid::new_v4();
    let mut paid_event = sample_event_full(community_id, paid_event_id, group_id);
    paid_event.manual_tax_rate_ids = vec!["txr_state".to_string(), "txr_local".to_string()];
    paid_event.payment_currency_code = Some("USD".to_string());
    paid_event.tax_behavior = TicketTaxBehavior::Exclusive;
    paid_event.tax_calculation_mode = TicketTaxCalculationMode::Manual;
    paid_event.ticket_types = Some(vec![EventTicketType {
        event_ticket_type_id: Uuid::new_v4(),
        order: 1,
        price_windows: vec![EventTicketPriceWindow {
            amount_minor: 2500,
            ..Default::default()
        }],
        title: "General admission".to_string(),
        ..Default::default()
    }]);
    let mut free_event = sample_event_full(community_id, free_event_id, group_id);
    free_event.manual_tax_rate_ids = vec!["txr_free".to_string()];
    free_event.tax_behavior = TicketTaxBehavior::Inclusive;
    free_event.tax_calculation_mode = TicketTaxCalculationMode::Manual;

    // Return both events and their shared connected fiscal sponsor
    let mut db = MockDB::new();
    db.expect_get_event_full().times(2).returning(move |_, _, event_id| {
        if event_id == paid_event_id {
            Ok(paid_event.clone())
        } else {
            Ok(free_event.clone())
        }
    });
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));

    // Revalidate sponsor readiness once and every event-level Tax Rate selection
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_validate_fiscal_sponsor()
        .times(1)
        .withf(|recipient, require_automatic_tax| {
            recipient.recipient_id == "acct_test" && !require_automatic_tax
        })
        .returning(|_, _| Box::pin(async { Ok(()) }));
    payments_manager
        .expect_validate_tax_rates()
        .times(2)
        .withf(|recipient, rate_ids, behavior| {
            recipient.recipient_id == "acct_test"
                && (rate_ids == ["txr_state", "txr_local"]
                    && *behavior == TicketTaxBehavior::Exclusive
                    || rate_ids == ["txr_free"] && *behavior == TicketTaxBehavior::Inclusive)
        })
        .returning(|_, _, _| Box::pin(async { Ok(()) }));
    let payments_manager: DynPaymentsManager = Arc::new(payments_manager);

    // Validate the full publish set and retain the paid mutation binding
    let validation = super::validate_publish_fiscal_sponsor(
        &db,
        &payments_manager,
        community_id,
        group_id,
        &[paid_event_id, free_event_id],
    )
    .await
    .expect("manual Tax Rates to be ready")
    .expect("paid publish validation binding to be returned");

    assert!(!validation.require_automatic_tax);
    assert_eq!(
        validation.manual_tax_rate_ids,
        Some(vec!["txr_state".to_string(), "txr_local".to_string()])
    );
}

#[tokio::test]
async fn test_publish_validation_requires_automatic_tax_location_readiness() {
    // Setup a paid automatic-tax event and its connected fiscal sponsor
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let mut event = sample_event_full(community_id, event_id, group_id);
    event.payment_currency_code = Some("USD".to_string());
    event.tax_calculation_mode = TicketTaxCalculationMode::Automatic;
    event.ticket_types = Some(vec![EventTicketType {
        event_ticket_type_id: Uuid::new_v4(),
        order: 1,
        price_windows: vec![EventTicketPriceWindow {
            amount_minor: 2500,
            ..Default::default()
        }],
        title: "General admission".to_string(),
        ..Default::default()
    }]);
    let mut db = MockDB::new();
    db.expect_get_event_full()
        .times(1)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_group_payment_recipient()
        .times(1)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));

    // Reject the venue after sponsor readiness succeeds
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_validate_fiscal_sponsor()
        .times(1)
        .returning(|_, _| Box::pin(async { Ok(()) }));
    payments_manager
        .expect_ensure_automatic_tax_readiness()
        .times(1)
        .returning(|_, _| {
            Box::pin(async {
                Err(AutomaticTaxReadinessError::StateCodeInvalid {
                    country_code: "ES".to_string(),
                    state_code: "ZZ".to_string(),
                })
            })
        });
    let payments_manager: DynPaymentsManager = Arc::new(payments_manager);

    // Check publication stops before a database publish mutation is possible
    let error = super::validate_publish_fiscal_sponsor(
        &db,
        &payments_manager,
        community_id,
        group_id,
        &[event_id],
    )
    .await
    .expect_err("invalid provider location to stop publication");

    assert!(matches!(
        error,
        HandlerError::Database(message)
            if message == "the state code ZZ is invalid for ES"
    ));
}

#[tokio::test]
async fn test_delete_success() {
    // Setup identifiers and data structures
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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_delete_event()
        .times(1)
        .withf(move |uid, gid, eid| *uid == user_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!("/dashboard/group/events/{event_id}/delete"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_delete_series_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let related_event_id = Uuid::new_v4();
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
    let series_event_ids = vec![event_id, related_event_id];
    let expected_series_event_ids = series_event_ids.clone();

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_list_event_series_event_ids()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .returning(move |_, _| Ok(series_event_ids.clone()));
    db.expect_delete_event().times(0);
    db.expect_delete_event_series_events()
        .times(1)
        .withf(move |uid, gid, event_ids| {
            *uid == user_id && *gid == group_id && event_ids == expected_series_event_ids.as_slice()
        })
        .returning(move |_, _, _| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!(
            "/dashboard/group/events/{event_id}/delete?scope=series"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_unpublish_success() {
    // Setup identifiers and data structures
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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_unpublish_event()
        .times(1)
        .withf(move |uid, gid, eid| *uid == user_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/group/events/{event_id}/unpublish"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_unpublish_series_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let related_event_id = Uuid::new_v4();
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
    let series_event_ids = vec![event_id, related_event_id];
    let expected_series_event_ids = series_event_ids.clone();

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_list_event_series_event_ids()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .returning(move |_, _| Ok(series_event_ids.clone()));
    db.expect_unpublish_event().times(0);
    db.expect_unpublish_event_series_events()
        .times(1)
        .withf(move |uid, gid, event_ids| {
            *uid == user_id && *gid == group_id && event_ids == expected_series_event_ids.as_slice()
        })
        .returning(move |_, _, _| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
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

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_update_free_manual_event_without_tax_rates_skips_fiscal_sponsor_validation() {
    // Setup a free manual-tax event submission with an explicit empty selection
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
    let before = sample_event_summary(event_id, group_id);
    let after = before.clone();
    let mut event_form = sample_event_form();
    event_form.manual_tax_rate_ids_present = Some(true);
    event_form.tax_calculation_mode = TicketTaxCalculationMode::Manual;
    let body = serde_qs::to_string(&event_form).unwrap();

    // Authorize the update and report that free ticketing needs no provider validation
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
    db.expect_event_ticketing_configuration_changed()
        .times(1)
        .withf(move |cid, gid, eid, event| {
            *cid == community_id
                && *gid == group_id
                && *eid == event_id
                && event["manual_tax_rate_ids"] == json!([])
                && event["tax_calculation_mode"] == "manual"
                && event.get("manual_tax_rate_ids_present").is_none()
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_get_group_payment_recipient().never();

    // Persist the explicit empty selection without a provider validation snapshot
    let mut tx = MockDB::new();
    tx.expect_get_event_summary()
        .times(2)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning({
            let mut first_call = true;
            move |_, _, _| {
                let result = if first_call {
                    first_call = false;
                    before.clone()
                } else {
                    after.clone()
                };
                Ok(result)
            }
        });
    tx.expect_update_event()
        .times(1)
        .withf(move |uid, gid, eid, event, _, payment_provider| {
            *uid == user_id
                && *gid == group_id
                && *eid == event_id
                && event["manual_tax_rate_ids"] == json!([])
                && event["tax_calculation_mode"] == "manual"
                && event.get("_payment_validation").is_none()
                && event.get("manual_tax_rate_ids_present").is_none()
                && *payment_provider == Some(PaymentProvider::Stripe)
        })
        .returning(|_, _, _, _, _, _| Ok(false));
    expect_successful_transaction(&mut db, tx);

    // Keep free empty selections independent of fiscal sponsor availability
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_configured_provider()
        .times(1)
        .return_const(Some(PaymentProvider::Stripe));
    payments_manager.expect_validate_fiscal_sponsor().never();
    payments_manager.expect_validate_tax_rates().never();

    // Submit the free manual-tax update through the routed handler
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(payments_manager)
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

    // Check the update succeeds without sponsor validation
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_update_free_success() {
    // Setup identifiers and data structures
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
    let before = sample_event_summary(event_id, group_id);
    let after = before.clone();
    let event_form = sample_event_form();
    let body = serde_qs::to_string(&event_form).unwrap();

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    let mut tx = MockDB::new();
    tx.expect_get_event_summary()
        .times(2)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning({
            let mut first_call = true;
            move |_, _, _| {
                let result = if first_call {
                    first_call = false;
                    before.clone()
                } else {
                    after.clone()
                };
                Ok(result)
            }
        });
    tx.expect_update_event()
        .times(1)
        .withf(
            move |uid, gid, eid, event, cfg_max_participants, payment_provider| {
                *uid == user_id
                    && *gid == group_id
                    && *eid == event_id
                    && event.get("name").and_then(serde_json::Value::as_str)
                        == Some(event_form.name.as_str())
                    && cfg_max_participants.is_empty()
                    && payment_provider.is_none()
            },
        )
        .returning(move |_, _, _, _, _, _| Ok(false));
    expect_successful_transaction(&mut db, tx);

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
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_update_free_test_to_paid_live_sends_admin_notification() {
    // Setup identifiers and a test-event promotion with paid tickets
    let admin_id = Uuid::new_v4();
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
    let before = EventSummary {
        published: false,
        test_event: true,
        ..sample_event_summary(event_id, group_id)
    };
    let after = EventSummary {
        published: false,
        test_event: false,
        ..sample_event_summary(event_id, group_id)
    };
    let body = format!("{}&test_event=false", sample_paid_event_body());

    // Setup authentication and permission checks
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

    db.expect_event_ticketing_configuration_changed()
        .times(1)
        .withf(move |cid, gid, eid, event| {
            *cid == community_id
                && *gid == group_id
                && *eid == event_id
                && event.get("ticket_types").is_some()
        })
        .returning(|_, _, _, _| Ok(true));

    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| {
            Ok(EventFull {
                published: false,
                ..sample_event_full(community_id, event_id, group_id)
            })
        });

    // Setup the ordered state transition and notification expectations
    let mut sequence = Sequence::new();
    let mut tx = MockDB::new();
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .in_sequence(&mut sequence)
        .returning(move |_, _, _| Ok(before.clone()));
    tx.expect_update_event()
        .times(1)
        .withf(move |uid, gid, eid, event, _, payment_provider| {
            *uid == user_id
                && *gid == group_id
                && *eid == event_id
                && event.get("ticket_types").is_some()
                && event.get("test_event").and_then(serde_json::Value::as_bool) == Some(false)
                && event.get("_payment_validation").is_some_and(|validation| {
                    validation["require_automatic_tax"] == true
                        && validation["expected_payment_recipient"]["recipient_id"] == "acct_test"
                })
                && *payment_provider == Some(PaymentProvider::Stripe)
        })
        .in_sequence(&mut sequence)
        .returning(|_, _, _, _, _, _| Ok(true));
    tx.expect_list_community_admin_ids()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![admin_id]));
    tx.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .in_sequence(&mut sequence)
        .returning(move |_, _, _| Ok(after.clone()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventPaidConfigured)
                && notification.recipients == vec![admin_id]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventPaidConfigured>(value.clone()).is_ok_and(|template| {
                        template.event_count == 1 && template.events[0].event_id == event_id
                    })
                })
        })
        .returning(|_| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Promote the test event while adding paid tickets
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_cfg(PaymentsConfig::Stripe(PaymentsStripeConfig {
            connected_webhook_secret: "whsec_connect_test".to_string(),
            mode: PaymentMode::Test,
            secret_key: "sk_test_123".to_string(),
            ticket_tax_api_version: "2026-07-29.preview".to_string(),
            webhook_secret: "whsec_test_123".to_string(),

            platform_fee_bps: 0,
        }))
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

    // Check the update response
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_update_invalid_ticketing_fields_returns_unprocessable_entity() {
    // Setup identifiers and data structures
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
async fn test_update_published_automatic_tax_event_stops_before_mutation_when_not_ready() {
    // Setup a paid automatic-tax update for an already-published event
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    db.expect_user_has_group_permission()
        .times(1)
        .returning(|_, _, _, permission| Ok(permission == GroupPermission::EventsWrite));
    db.expect_event_ticketing_configuration_changed()
        .times(1)
        .returning(|_, _, _, _| Ok(true));
    db.expect_get_group_payment_recipient()
        .times(2)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));
    let mut persisted_event = sample_event_full(community_id, event_id, group_id);
    persisted_event.published = true;
    db.expect_get_event_full()
        .times(1)
        .returning(move |_, _, _| Ok(persisted_event.clone()));
    db.expect_begin().never();

    // Allow sponsor validation but reject the proposed venue location
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_configured_provider()
        .times(1)
        .return_const(Some(PaymentProvider::Stripe));
    payments_manager
        .expect_validate_fiscal_sponsor()
        .times(1)
        .returning(|_, _| Box::pin(async { Ok(()) }));
    payments_manager
        .expect_ensure_automatic_tax_readiness()
        .times(1)
        .returning(|_, _| Box::pin(async { Err(AutomaticTaxReadinessError::InvalidAddress) }));

    // Submit the update and confirm no transaction begins
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let response = router
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/dashboard/group/events/{event_id}/update"))
                .header(COOKIE, format!("id={session_id}"))
                .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                .body(Body::from(sample_paid_event_body()))
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "the venue address is invalid"
    );
}

#[tokio::test]
async fn test_update_paid_event_without_payment_recipient_returns_unprocessable_entity() {
    // Setup identifiers and data structures
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
    let body = sample_paid_event_body();

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_event_ticketing_configuration_changed()
        .times(1)
        .withf(move |cid, gid, eid, event| {
            *cid == community_id
                && *gid == group_id
                && *eid == event_id
                && event.get("ticket_types").is_some()
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_get_group_payment_recipient()
        .times(2)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(None));
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(sample_event_full(community_id, event_id, group_id)));
    db.expect_begin().never();

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_payments_cfg(PaymentsConfig::Stripe(PaymentsStripeConfig {
            connected_webhook_secret: "whsec_connect_test".to_string(),
            mode: PaymentMode::Test,
            secret_key: "sk_test".to_string(),
            ticket_tax_api_version: "2026-07-29.preview".to_string(),
            webhook_secret: "whsec_test".to_string(),

            platform_fee_bps: 0,
        }))
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

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "configure a fiscal sponsor before updating this published event",
    );
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_update_paid_notification_failure_rolls_back() {
    // Setup identifiers and paid update input
    let admin_id = Uuid::new_v4();
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
    let before = sample_event_summary(event_id, group_id);
    let body = sample_paid_event_body();

    // Setup authentication and permission checks
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

    db.expect_event_ticketing_configuration_changed()
        .times(1)
        .withf(move |cid, gid, eid, event| {
            *cid == community_id
                && *gid == group_id
                && *eid == event_id
                && event.get("ticket_types").is_some()
        })
        .returning(|_, _, _, _| Ok(true));

    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| {
            Ok(EventFull {
                published: false,
                ..sample_event_full(community_id, event_id, group_id)
            })
        });

    // Setup a successful update followed by a required notification failure
    let mut tx = MockDB::new();
    tx.expect_get_event_summary()
        .times(2)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(before.clone()));
    tx.expect_update_event()
        .times(1)
        .withf(move |uid, gid, eid, _, _, payment_provider| {
            *uid == user_id
                && *gid == group_id
                && *eid == event_id
                && *payment_provider == Some(PaymentProvider::Stripe)
        })
        .returning(|_, _, _, _, _, _| Ok(true));
    tx.expect_list_community_admin_ids()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![admin_id]));
    tx.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    tx.expect_enqueue_notification()
        .times(1)
        .returning(|_| Err(anyhow!("notification error")));
    tx.expect_get_event_full().never();
    tx.expect_list_event_attendees_ids().never();
    expect_rolled_back_transaction(&mut db, tx);

    // Send the free-to-paid update request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_cfg(PaymentsConfig::Stripe(PaymentsStripeConfig {
            connected_webhook_secret: "whsec_connect_test".to_string(),
            mode: PaymentMode::Test,
            secret_key: "sk_test_123".to_string(),
            ticket_tax_api_version: "2026-07-29.preview".to_string(),
            webhook_secret: "whsec_test_123".to_string(),

            platform_fee_bps: 0,
        }))
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

    // Check the failed notification rolls back the update
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_update_reschedule_notification_success() {
    // Setup identifiers and data structures
    let attendee_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let speaker_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );
    let before = sample_event_summary(event_id, group_id);
    let after = EventSummary {
        starts_at: before.starts_at.map(|ts| ts + chrono::Duration::minutes(30)),
        ..before.clone()
    };
    let event_full = EventFull {
        speakers: vec![Speaker {
            featured: false,
            user: sample_template_user_with_id(speaker_id),
        }],
        ..sample_event_full(community_id, event_id, group_id)
    };
    let site_settings = sample_site_settings();
    let site_settings_for_reschedule_notification = site_settings.clone();
    let event_form = sample_event_form();
    let body = serde_qs::to_string(&event_form).unwrap();

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    let mut tx = MockDB::new();
    tx.expect_get_event_summary()
        .times(2)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning({
            let mut call_count = 0;
            move |_, _, _| {
                call_count += 1;
                match call_count {
                    1 => Ok(before.clone()),
                    2 => Ok(after.clone()),
                    _ => unreachable!(),
                }
            }
        });
    tx.expect_update_event()
        .times(1)
        .withf(
            move |uid, gid, eid, event, cfg_max_participants, payment_provider| {
                *uid == user_id
                    && *gid == group_id
                    && *eid == event_id
                    && event.get("name").and_then(serde_json::Value::as_str)
                        == Some(event_form.name.as_str())
                    && cfg_max_participants.is_empty()
                    && payment_provider.is_none()
            },
        )
        .returning(move |_, _, _, _, _, _| Ok(false));
    tx.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full.clone()));
    tx.expect_list_event_attendees_ids()
        .times(1)
        .withf(move |gid, eid, checked_in_only| {
            *gid == group_id && *eid == event_id && !checked_in_only
        })
        .returning(move |_, _, _| Ok(vec![attendee_id]));
    tx.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventRescheduled)
                && notification.recipients.len() == 2
                && notification.recipients.contains(&attendee_id)
                && notification.recipients.contains(&speaker_id)
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventRescheduled>(value.clone()).is_ok_and(|template| {
                        template.link == "/test/group/npq6789/event/abc1234"
                            && template.theme.primary_color
                                == site_settings_for_reschedule_notification.theme.primary_color
                    })
                })
        })
        .returning(|_| Ok(()));
    expect_successful_transaction(&mut db, tx);

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
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_update_reschedule_rollback_on_enqueue_failure() {
    // Setup identifiers and data structures
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
    let before = sample_event_summary(event_id, group_id);
    let after = EventSummary {
        starts_at: before.starts_at.map(|ts| ts + chrono::Duration::minutes(30)),
        ..before.clone()
    };
    let event_full = sample_event_full(community_id, event_id, group_id);
    let site_settings = sample_site_settings();
    let site_settings_for_notification = site_settings.clone();
    let event_form = sample_event_form();
    let body = serde_qs::to_string(&event_form).unwrap();

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    let mut tx = MockDB::new();
    tx.expect_get_event_summary()
        .times(2)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning({
            let mut first_call = true;
            move |_, _, _| {
                let result = if first_call {
                    first_call = false;
                    before.clone()
                } else {
                    after.clone()
                };
                Ok(result)
            }
        });
    tx.expect_update_event()
        .times(1)
        .withf(
            move |uid, gid, eid, event, cfg_max_participants, payment_provider| {
                *uid == user_id
                    && *gid == group_id
                    && *eid == event_id
                    && event.get("name").and_then(serde_json::Value::as_str)
                        == Some(event_form.name.as_str())
                    && cfg_max_participants.is_empty()
                    && payment_provider.is_none()
            },
        )
        .returning(move |_, _, _, _, _, _| Ok(false));
    tx.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full.clone()));
    tx.expect_list_event_attendees_ids()
        .times(1)
        .withf(move |gid, eid, checked_in_only| {
            *gid == group_id && *eid == event_id && !checked_in_only
        })
        .returning(move |_, _, _| Ok(vec![user_id]));
    tx.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventRescheduled)
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventRescheduled>(value.clone()).is_ok_and(|template| {
                        template.theme.primary_color
                            == site_settings_for_notification.theme.primary_color
                    })
                })
        })
        .returning(|_| Err(anyhow!("notification error")));
    expect_rolled_back_transaction(&mut db, tx);

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
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_update_reschedule_rollback_on_notification_context_failure() {
    // Setup identifiers and data structures
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
    let before = sample_event_summary(event_id, group_id);
    let event_form = sample_event_form();
    let body = serde_qs::to_string(&event_form).unwrap();

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    let mut tx = MockDB::new();
    tx.expect_get_event_summary()
        .times(2)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning({
            let mut call_count = 0;
            move |_, _, _| {
                call_count += 1;
                match call_count {
                    1 => Ok(before.clone()),
                    2 => Err(anyhow!("db error")),
                    _ => unreachable!(),
                }
            }
        });
    tx.expect_update_event()
        .times(1)
        .withf(
            move |uid, gid, eid, event, cfg_max_participants, payment_provider| {
                *uid == user_id
                    && *gid == group_id
                    && *eid == event_id
                    && event.get("name").and_then(serde_json::Value::as_str)
                        == Some(event_form.name.as_str())
                    && cfg_max_participants.is_empty()
                    && payment_provider.is_none()
            },
        )
        .returning(move |_, _, _, _, _, _| Ok(false));
    expect_rolled_back_transaction(&mut db, tx);

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
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_update_reschedule_skips_notification_when_shift_too_small() {
    // Setup identifiers and data structures
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
    let before = sample_event_summary(event_id, group_id);
    // Shift by only 10 minutes (below MIN_RESCHEDULE_SHIFT of 15 minutes)
    let after = EventSummary {
        starts_at: before.starts_at.map(|ts| ts + chrono::Duration::minutes(10)),
        ..before.clone()
    };
    let event_form = sample_event_form();
    let body = serde_qs::to_string(&event_form).unwrap();

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    let mut tx = MockDB::new();
    tx.expect_get_event_summary()
        .times(2)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning({
            let mut first_call = true;
            move |_, _, _| {
                let result = if first_call {
                    first_call = false;
                    before.clone()
                } else {
                    after.clone()
                };
                Ok(result)
            }
        });
    tx.expect_update_event()
        .times(1)
        .withf(
            move |uid, gid, eid, event, cfg_max_participants, payment_provider| {
                *uid == user_id
                    && *gid == group_id
                    && *eid == event_id
                    && event.get("name").and_then(serde_json::Value::as_str)
                        == Some(event_form.name.as_str())
                    && cfg_max_participants.is_empty()
                    && payment_provider.is_none()
            },
        )
        .returning(move |_, _, _, _, _, _| Ok(false));
    expect_successful_transaction(&mut db, tx);

    // Setup notifications manager mock (no enqueue expected - shift too small)
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
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_update_reschedule_skips_notification_when_unpublished() {
    // Setup identifiers and data structures
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
    // Event is unpublished, so no reschedule notification should be sent
    let before = EventSummary {
        published: false,
        ..sample_event_summary(event_id, group_id)
    };
    // Significant reschedule (30 minutes), but event is unpublished
    let after = EventSummary {
        starts_at: before.starts_at.map(|ts| ts + chrono::Duration::minutes(30)),
        ..before.clone()
    };
    let event_form = sample_event_form();
    let body = serde_qs::to_string(&event_form).unwrap();

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    let mut tx = MockDB::new();
    tx.expect_get_event_summary()
        .times(2)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning({
            let mut first_call = true;
            move |_, _, _| {
                let result = if first_call {
                    first_call = false;
                    before.clone()
                } else {
                    after.clone()
                };
                Ok(result)
            }
        });
    tx.expect_update_event()
        .times(1)
        .withf(
            move |uid, gid, eid, event, cfg_max_participants, payment_provider| {
                *uid == user_id
                    && *gid == group_id
                    && *eid == event_id
                    && event.get("name").and_then(serde_json::Value::as_str)
                        == Some(event_form.name.as_str())
                    && cfg_max_participants.is_empty()
                    && payment_provider.is_none()
            },
        )
        .returning(move |_, _, _, _, _, _| Ok(false));
    expect_successful_transaction(&mut db, tx);

    // Setup notifications manager mock (no enqueue expected - event unpublished)
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
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_update_skips_notification_for_past_event() {
    // Setup identifiers and data structures
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
    let past_event = {
        let past_time = Utc::now() - chrono::Duration::hours(2);
        EventSummary {
            ends_at: Some(past_time + chrono::Duration::hours(1)),
            starts_at: Some(past_time),
            ..sample_event_summary(event_id, group_id)
        }
    };
    let mut past_event_form = sample_event_form();
    past_event_form.description = "Updated past event description".to_string();
    past_event_form.name = "Past Event Updated".to_string();
    let body = serde_qs::to_string(&past_event_form).unwrap();

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
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    let mut tx = MockDB::new();
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(past_event.clone()));
    tx.expect_update_event()
        .times(1)
        .withf(
            move |uid, gid, eid, event, cfg_max_participants, payment_provider| {
                *uid == user_id
                    && *gid == group_id
                    && *eid == event_id
                    && event.get("description").and_then(serde_json::Value::as_str)
                        == Some("Updated past event description")
                    && event.get("name").and_then(serde_json::Value::as_str)
                        == Some("Past Event Updated")
                    && cfg_max_participants.is_empty()
                    && payment_provider.is_none()
            },
        )
        .returning(move |_, _, _, _, _, _| Ok(false));
    expect_successful_transaction(&mut db, tx);

    // Setup notifications manager mock (no expectations - past events don't notify)
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
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_update_unrelated_paid_event_edit_skips_fiscal_sponsor_validation() {
    // Setup an unrelated mutation whose submitted ticketing configuration is unchanged
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
    let before = sample_event_summary(event_id, group_id);
    let body = sample_paid_event_body();

    // Authorize the update and report that paid-ticket readiness fields are unchanged
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
    db.expect_event_ticketing_configuration_changed()
        .times(1)
        .withf(move |cid, gid, eid, event| {
            *cid == community_id
                && *gid == group_id
                && *eid == event_id
                && event.get("ticket_types").is_some()
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_get_group_payment_recipient().never();

    // Persist the unrelated edit without entering a notifiable paid state
    let mut tx = MockDB::new();
    tx.expect_get_event_summary()
        .times(2)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(before.clone()));
    tx.expect_update_event()
        .times(1)
        .withf(move |uid, gid, eid, event, _, payment_provider| {
            *uid == user_id
                && *gid == group_id
                && *eid == event_id
                && event.get("ticket_types").is_some()
                && *payment_provider == Some(PaymentProvider::Stripe)
        })
        .returning(|_, _, _, _, _, _| Ok(false));
    expect_successful_transaction(&mut db, tx);

    // Keep unrelated edits independent of live provider availability
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_configured_provider()
        .times(1)
        .return_const(Some(PaymentProvider::Stripe));
    payments_manager.expect_validate_fiscal_sponsor().never();

    // Submit the unrelated edit through the routed handler
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(payments_manager)
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

    // Check the update succeeds without sponsor validation
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}
