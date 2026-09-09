use anyhow::anyhow;
use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderValue, Request, StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE, COOKIE, LOCATION},
    },
};
use axum_login::tower_sessions::session;
use chrono::TimeZone;
use serde_json::{from_slice, json};
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    activity_tracker::{Activity, MockActivityTracker},
    db::mock::MockDB,
    handlers::tests::*,
    router::{CACHE_CONTROL_NO_STORE, CACHE_CONTROL_PUBLIC_SHARED},
    services::{
        enrollment::{AttendOutcome, EnrollmentError, MockEnrollmentManager},
        notifications::MockNotificationsManager,
        payments::MockPaymentsManager,
    },
    types::{
        event::{EventEnrollmentState, EventEnrollmentStatus, EventLeaveOutcome},
        payments::{
            EventPurchaseChargeModel, EventPurchaseStatus, EventTicketCurrentPrice,
            EventTicketType, EventTicketTypeAvailability, PreparedEventCheckout,
        },
        questionnaire::{QuestionnaireAnswer, QuestionnaireAnswerValue, QuestionnaireAnswers},
    },
};

use super::HandlerError;

#[tokio::test]
async fn test_availability_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let free_event_ticket_type_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let mut event = sample_event_full(community_id, event_id, group_id);
    event.attendee_count = 4;
    event.starts_at = Some(chrono::Utc::now() + chrono::Duration::minutes(10));
    event.ends_at = Some(chrono::Utc::now() + chrono::Duration::hours(1));
    event.payment_currency_code = Some("usd".to_string());
    event.remaining_capacity = Some(7);
    event.ticket_types = Some(vec![
        EventTicketType {
            active: true,
            availability: EventTicketTypeAvailability::Public,
            event_ticket_type_id,
            order: 1,
            title: "General admission".to_string(),

            current_price: Some(EventTicketCurrentPrice {
                amount_minor: 1_500,

                ends_at: None,
                starts_at: None,
            }),
            description: Some("Lunch included.".to_string()),
            remaining_seats: Some(7),
            seats_total: Some(10),
            sold_out: false,
            ..Default::default()
        },
        EventTicketType {
            active: true,
            availability: EventTicketTypeAvailability::Public,
            event_ticket_type_id: free_event_ticket_type_id,
            order: 2,
            title: "Community pass".to_string(),

            current_price: Some(EventTicketCurrentPrice {
                amount_minor: 0,

                ends_at: None,
                starts_at: None,
            }),
            remaining_seats: Some(5),
            seats_total: Some(5),
            sold_out: false,
            ..Default::default()
        },
    ]);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));
    db.expect_get_event_full_by_slug()
        .times(1)
        .withf(move |id, group_slug, event_slug| {
            *id == community_id && group_slug == "test-group" && event_slug == "test-event"
        })
        .returning(move |_, _, _| Ok(Some(event.clone())));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/test-community/group/test-group/event/test-event/availability")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let payload: serde_json::Value = from_slice(&bytes).unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_NO_STORE)
    );
    assert_eq!(payload["attendee_count"], json!(4));
    assert_eq!(payload["capacity"], json!(100));
    assert_eq!(payload["has_sellable_ticket_types"], json!(true));
    assert_eq!(payload["is_live"], json!(true));
    assert_eq!(payload["remaining_capacity"], json!(7));
    let ticket = &payload["ticket_types"][0];
    assert_eq!(ticket["event_ticket_type_id"], json!(event_ticket_type_id));
    assert_eq!(ticket["is_sellable_now"], json!(true));
    assert_eq!(ticket["title"], json!("General admission"));
    assert_eq!(ticket["current_price_label"], json!("USD 15.00"));
    assert_eq!(ticket["description"], json!("Lunch included."));
    assert_eq!(ticket["remaining_seats"], json!(7));
    assert_eq!(
        payload["ticket_types"][1]["current_price_label"],
        json!("Free")
    );
}

#[tokio::test]
async fn test_page_community_not_found() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "missing-community")
        .returning(|_| Ok(None));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/missing-community/group/test-group/event/test-event")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NOT_FOUND);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
    );
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("We could not find that page"));
    assert!(body.contains("Go to home page"));
}

#[tokio::test]
async fn test_page_not_found() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_get_event_full_by_slug()
        .times(1)
        .withf(move |id, group_slug, event_slug| {
            *id == community_id && group_slug == "test-group" && event_slug == "missing-event"
        })
        .returning(move |_, _, _| Ok(None));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/test-community/group/test-group/event/missing-event")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NOT_FOUND);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
    );
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("We could not find that page"));
    assert!(body.contains("Go to home page"));
}

#[tokio::test]
async fn test_page_temporarily_redirects_generated_group_slug_to_pretty_slug() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let mut event = sample_event_full(community_id, event_id, group_id);
    event.group.slug = "test-group".to_string();
    event.group.slug_pretty = Some("pretty-group".to_string());
    event.slug = "test-event".to_string();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_get_event_full_by_slug()
        .times(1)
        .withf(move |id, group_slug, event_slug| {
            *id == community_id && group_slug == "test-group" && event_slug == "test-event"
        })
        .returning(move |_, _, _| Ok(Some(event.clone())));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/test-community/group/test-group/event/test-event?utm_source=test")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();

    // Check response matches expectations
    assert_eq!(response.status(), StatusCode::TEMPORARY_REDIRECT);
    assert_eq!(
        response.headers().get(LOCATION).unwrap(),
        &HeaderValue::from_static(
            "/test-community/group/pretty-group/event/test-event?utm_source=test"
        )
    );
}

#[tokio::test]
async fn test_page_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let mut event = sample_event_full(community_id, event_id, group_id);
    event.community.name = "test-community".to_string();
    event.community.display_name = "Test Community".to_string();
    event.group.name = "Test Group".to_string();
    event.group.og_image_url = Some("/images/group-og.png".to_string());
    event.group.slug_pretty = Some("pretty-group".to_string());
    event.name = "Test Event".to_string();
    event.slug = "test-event".to_string();
    event.starts_at = Some(chrono::Utc.with_ymd_and_hms(2030, 3, 5, 18, 0, 0).unwrap());
    event.timezone = chrono_tz::UTC;

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_get_event_full_by_slug()
        .times(1)
        .withf(move |id, group_slug, event_slug| {
            *id == community_id && group_slug == "pretty-group" && event_slug == "test-event"
        })
        .returning(move |_, _, _| Ok(Some(event.clone())));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_server_cfg(sample_tracking_server_cfg())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/test-community/group/pretty-group/event/test-event")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
    );
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("<title>Test Event - March 5</title>"));
    assert!(body.contains(
        r#"<meta name="description" content="Test Group in Test Community community. Open Community Groups, where Open Source communities thrive.">"#
    ));
    assert!(body.contains(
        r#"<link rel="canonical" href="https://example.test/test-community/group/pretty-group/event/test-event">"#
    ));
    assert!(body.contains(r#"<meta property="og:title" content="Test Event - March 5">"#));
    assert!(body.contains(
        r#"<meta property="og:url" content="https://example.test/test-community/group/pretty-group/event/test-event">"#
    ));
    assert!(body.contains(
        r#"<meta property="og:description" content="Test Group in Test Community community. Open Community Groups, where Open Source communities thrive.">"#
    ));
    assert!(body.contains(
        r#"<meta property="og:image" content="https://example.test/images/og/group-og.png">"#
    ));
    assert!(body.contains(r#"<meta name="twitter:title" content="Test Event - March 5">"#));
    assert!(body.contains(
        r#"<meta name="twitter:description" content="Test Group in Test Community community. Open Community Groups, where Open Source communities thrive.">"#
    ));
    assert!(body.contains(
        r#"<meta name="twitter:image" content="https://example.test/images/og/group-og.png">"#
    ));
}

#[tokio::test]
async fn test_cfs_modal_rejects_invalid_event_id_before_community_lookup() {
    // Prevent community resolution for an invalid event identifier
    let mut db = MockDB::new();
    db.expect_get_community_id_by_name().never();

    // Request the modal with a malformed event identifier
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/test-community/event/not-a-uuid/cfs-modal")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check path validation rejects the request before community lookup
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert!(body.contains("Invalid URL:"));
    assert!(body.contains("not-a-uuid"));
}

#[tokio::test]
async fn test_cfs_modal_success_anonymous() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let event_summary = sample_event_summary(event_id, group_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event_summary.clone()));
    db.expect_list_event_cfs_labels()
        .times(1)
        .withf(move |eid| *eid == event_id)
        .returning(|_| Ok(vec![]));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/test-community/event/{event_id}/cfs-modal"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8")
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_cfs_modal_success_authenticated() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let session_proposal_id = Uuid::new_v4();
    let event_summary = sample_event_summary(event_id, group_id);
    let proposals = vec![sample_event_cfs_session_proposal(session_proposal_id)];

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event_summary.clone()));
    db.expect_list_event_cfs_labels()
        .times(1)
        .withf(move |eid| *eid == event_id)
        .returning(|_| Ok(vec![]));
    db.expect_list_user_session_proposals_for_cfs_event()
        .times(1)
        .withf(move |uid, eid| *uid == user_id && *eid == event_id)
        .returning(move |_, _| Ok(proposals.clone()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/test-community/event/{event_id}/cfs-modal"))
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
        &HeaderValue::from_static("text/html; charset=utf-8")
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_attend_event_returns_checkout_redirect() {
    // Setup identifiers and the redirect outcome
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let ticket_type_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let hold_expires_at = chrono::Utc.with_ymd_and_hms(2030, 1, 2, 3, 4, 5).unwrap();

    // Setup session and community resolution
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));

    // Setup the enrollment manager expectation
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager
        .expect_attend_event()
        .times(1)
        .withf(move |input| {
            input.community_id == community_id
                && input.event_id == event_id
                && input.user_id == user_id
                && input.attendance.event_ticket_type_id == Some(ticket_type_id)
                && input.attendance.registration_answers.registration_answers.is_none()
        })
        .returning(move |_| {
            Box::pin(async move {
                Ok(AttendOutcome::CheckoutRedirect {
                    hold_expires_at: Some(hold_expires_at),
                    redirect_url: "https://checkout.test/session".to_string(),
                })
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/attend"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(format!("event_ticket_type_id={ticket_type_id}")))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the redirect payload
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body["hold_expires_at"], json!(hold_expires_at));
    assert_eq!(body["redirect_url"], json!("https://checkout.test/session"));
    assert_eq!(body["status"], json!("pending-payment"));
}

#[tokio::test]
async fn test_attend_event_returns_conflict() {
    // Setup identifiers and the conflict outcome
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .returning(move |_| Ok(Some(community_id)));

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager.expect_attend_event().times(1).returning(|_| {
        Box::pin(async {
            Ok(AttendOutcome::Conflict(
                "event-capacity-unavailable".to_string(),
            ))
        })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/attend"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the conflict payload
    assert_eq!(parts.status, StatusCode::CONFLICT);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "conflict": "event-capacity-unavailable" }));
}

#[tokio::test]
async fn test_attend_event_returns_enrollment_status_with_registration_answers() {
    // Setup identifiers and the submitted answers
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let question_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let answers = QuestionnaireAnswers {
        answers: vec![QuestionnaireAnswer {
            question_id,
            value: QuestionnaireAnswerValue::One("Vegetarian".to_string()),
        }],
    };
    let form_body = serde_urlencoded::to_string([(
        "registration_answers",
        serde_json::to_string(&answers).unwrap(),
    )])
    .unwrap();

    // Setup session and community resolution
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .returning(move |_| Ok(Some(community_id)));

    // Setup the enrollment manager expectation on the decoded answers
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager
        .expect_attend_event()
        .times(1)
        .withf(move |input| {
            input.attendance.event_ticket_type_id.is_none()
                && input
                    .attendance
                    .registration_answers
                    .registration_answers
                    .as_ref()
                    .is_some_and(|answers| {
                        answers.answers.len() == 1 && answers.answers[0].question_id == question_id
                    })
        })
        .returning(|_| {
            Box::pin(async { Ok(AttendOutcome::Enrolled(EventEnrollmentStatus::Waitlisted)) })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/attend"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(form_body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the enrollment status payload
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "status": "waitlisted" }));
}

#[tokio::test]
async fn test_attend_event_returns_external_pending_payment() {
    // Setup identifiers and the external purchase snapshot
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let hold_expires_at = chrono::Utc.with_ymd_and_hms(2030, 1, 2, 3, 4, 5).unwrap();
    let mut purchase = sample_purchase_summary(EventPurchaseStatus::Pending);
    purchase.charge_model = EventPurchaseChargeModel::External;
    purchase.event_purchase_id = event_purchase_id;
    purchase.external_payment_instructions = Some("Use reference on the transfer.".to_string());
    purchase.external_payment_url = Some("https://pay.example.test/event".to_string());
    purchase.hold_expires_at = Some(hold_expires_at);

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .returning(move |_| Ok(Some(community_id)));

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager.expect_attend_event().times(1).returning(move |_| {
        let purchase = purchase.clone();
        Box::pin(async move {
            Ok(AttendOutcome::ExternalPendingPayment(Box::new(
                PreparedEventCheckout {
                    event_id,
                    purchase,
                    ..PreparedEventCheckout::default()
                },
            )))
        })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/attend"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the pending-payment payload uses the purchase snapshot
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body["status"], json!("pending-payment"));
    assert_eq!(body["hold_expires_at"], json!(hold_expires_at.timestamp()));
    assert_eq!(
        body["external_payment"],
        json!({
            "amount_minor": 2500,
            "currency_code": "USD",
            "deadline": hold_expires_at.timestamp(),
            "instructions": "Use reference on the transfer.",
            "reference": event_purchase_id,
            "url": "https://pay.example.test/event",
        })
    );
}

#[tokio::test]
async fn test_attend_event_returns_internal_server_error_when_manager_fails() {
    // Setup identifiers and an internal manager failure
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .returning(move |_| Ok(Some(community_id)));

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager.expect_attend_event().times(1).returning(|_| {
        Box::pin(async { Err(EnrollmentError::Other(anyhow!("database failure"))) })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/attend"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the internal failure is hidden
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_attend_event_returns_unprocessable_entity_for_database_rejection() {
    // Setup identifiers and a user-facing database rejection
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .returning(move |_| Ok(Some(community_id)));

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager.expect_attend_event().times(1).returning(|_| {
        Box::pin(async {
            Err(EnrollmentError::Other(
                HandlerError::Database("event not found or inactive".to_string()).into(),
            ))
        })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/attend"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "event not found or inactive"
    );
}

#[tokio::test]
async fn test_attend_event_returns_unprocessable_entity_for_rejection() {
    // Setup identifiers and an application rejection
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .returning(move |_| Ok(Some(community_id)));

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager.expect_attend_event().times(1).returning(|_| {
        Box::pin(async {
            Err(EnrollmentError::Rejected(
                "questionnaire answers are required".to_string(),
            ))
        })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/attend"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "questionnaire answers are required"
    );
}

#[tokio::test]
async fn test_enrollment_state_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));
    db.expect_get_event_enrollment()
        .times(1)
        .withf(move |id, eid, uid| *id == community_id && *eid == event_id && *uid == user_id)
        .returning(|_, _, _| {
            Ok(EventEnrollmentState {
                is_checked_in: false,
                status: EventEnrollmentStatus::Attendee,

                admission_offer_id: None,
                event_ticket_type_id: None,
                external_payment: None,
                manually_invited: false,
                purchase_amount_minor: None,
                purchase_charge_model: None,
                refund_rejection_reason: None,
                refund_request_status: None,
                resume_checkout_url: None,
            })
        });

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/test-community/event/{event_id}/enrollment"))
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
        &HeaderValue::from_static("application/json")
    );
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(
        body,
        json!({
            "admission_offer_id": null,
            "can_request_refund": false,
            "event_ticket_type_id": null,
            "external_payment": null,
            "is_checked_in": false,
            "manually_invited": false,
            "purchase_amount_minor": null,
            "refund_rejection_reason": null,
            "refund_request_status": null,
            "resume_checkout_url": null,
            "status": "attendee",
        })
    );
}

#[tokio::test]
async fn test_enrollment_state_stale_event_returns_none_without_summary_lookup() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));
    db.expect_get_event_enrollment()
        .times(1)
        .withf(move |id, eid, uid| *id == community_id && *eid == event_id && *uid == user_id)
        .returning(|_, _, _| {
            Ok(EventEnrollmentState {
                is_checked_in: false,
                status: EventEnrollmentStatus::None,

                admission_offer_id: None,
                event_ticket_type_id: None,
                external_payment: None,
                manually_invited: false,
                purchase_amount_minor: None,
                purchase_charge_model: None,
                refund_rejection_reason: None,
                refund_request_status: None,
                resume_checkout_url: None,
            })
        });

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/test-community/event/{event_id}/enrollment"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(
        body,
        json!({
            "admission_offer_id": null,
            "can_request_refund": false,
            "event_ticket_type_id": null,
            "external_payment": null,
            "is_checked_in": false,
            "manually_invited": false,
            "purchase_amount_minor": null,
            "refund_rejection_reason": null,
            "refund_request_status": null,
            "resume_checkout_url": null,
            "status": "none",
        })
    );
}

#[tokio::test]
async fn test_cancel_checkout_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));
    db.expect_cancel_event_checkout()
        .times(1)
        .withf(move |cid, eid, uid, payment_provider| {
            *cid == community_id
                && *eid == event_id
                && *uid == user_id
                && payment_provider.is_none()
        })
        .returning(|_, _, _, _| Ok(()));
    db.expect_get_event_enrollment()
        .times(1)
        .withf(move |cid, eid, uid| *cid == community_id && *eid == event_id && *uid == user_id)
        .returning(|_, _, _| {
            Ok(EventEnrollmentState {
                is_checked_in: false,
                status: EventEnrollmentStatus::InvitationApproved,

                admission_offer_id: Some(Uuid::from_u128(1)),
                event_ticket_type_id: Some(Uuid::from_u128(2)),
                external_payment: None,
                manually_invited: false,
                purchase_amount_minor: None,
                purchase_charge_model: None,
                refund_rejection_reason: None,
                refund_request_status: None,
                resume_checkout_url: None,
            })
        });

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!("/test-community/event/{event_id}/checkout"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "status": "invitation-approved" }));
}

#[tokio::test]
async fn test_cancel_checkout_returns_internal_server_error_when_db_fails() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));
    db.expect_cancel_event_checkout()
        .times(1)
        .withf(move |cid, eid, uid, payment_provider| {
            *cid == community_id
                && *eid == event_id
                && *uid == user_id
                && payment_provider.is_none()
        })
        .returning(|_, _, _, _| Err(anyhow!("db error")));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!("/test-community/event/{event_id}/checkout"))
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
async fn test_leave_event_returns_internal_server_error_when_manager_fails() {
    // Setup identifiers and an internal manager failure
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .returning(move |_| Ok(Some(community_id)));

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager.expect_leave_event().times(1).returning(|_| {
        Box::pin(async { Err(EnrollmentError::Other(anyhow!("database failure"))) })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!("/test-community/event/{event_id}/leave"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the internal failure is hidden
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_leave_event_returns_left_status() {
    // Setup identifiers and the leave outcome
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager
        .expect_leave_event()
        .times(1)
        .withf(move |input| {
            input.community_id == community_id
                && input.event_id == event_id
                && input.user_id == user_id
        })
        .returning(|_| {
            Box::pin(async {
                Ok(EventLeaveOutcome {
                    left_status: EventEnrollmentStatus::Attendee,
                })
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!("/test-community/event/{event_id}/leave"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the left status payload
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "left_status": "attendee" }));
}

#[tokio::test]
async fn test_leave_event_returns_unprocessable_entity_for_database_rejection() {
    // Setup identifiers and the paid-attendee database rejection
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .returning(move |_| Ok(Some(community_id)));

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager.expect_leave_event().times(1).returning(|_| {
        Box::pin(async {
            Err(EnrollmentError::Other(
                HandlerError::Database(
                    "paid attendance must be refunded before leaving".to_string(),
                )
                .into(),
            ))
        })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!("/test-community/event/{event_id}/leave"))
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
        "paid attendance must be refunded before leaving"
    );
}

#[tokio::test]
async fn test_request_refund_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));

    // Setup payments manager mock
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_request_refund()
        .times(1)
        .withf(move |input| {
            input.community_id == community_id
                && input.event_id == event_id
                && input.requested_reason.as_deref() == Some("Need to cancel")
                && input.user_id == user_id
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/refund-request"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from("requested_reason=Need%20to%20cancel"))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "status": "refund-requested" }));
}

#[tokio::test]
async fn test_request_refund_returns_internal_server_error_when_payments_manager_fails() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));

    // Setup payments manager mock
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_request_refund()
        .times(1)
        .withf(move |input| {
            input.community_id == community_id
                && input.event_id == event_id
                && input.requested_reason.as_deref() == Some("Need to cancel")
                && input.user_id == user_id
        })
        .returning(|_| Box::pin(async { Err(anyhow!("payments error")) }));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/refund-request"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from("requested_reason=Need%20to%20cancel"))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_start_checkout_returns_checkout_redirect() {
    // Setup identifiers and the redirect outcome
    let admission_offer_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let ticket_type_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let hold_expires_at = chrono::Utc.with_ymd_and_hms(2030, 1, 2, 3, 4, 5).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));

    // Setup the enrollment manager expectation on the decoded form
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager
        .expect_start_checkout()
        .times(1)
        .withf(move |input| {
            input.community_id == community_id
                && input.event_id == event_id
                && input.user_id == user_id
                && input.checkout.admission_offer_id == Some(admission_offer_id)
                && input.checkout.discount_code.as_deref() == Some("EARLY")
                && input.checkout.event_ticket_type_id == Some(ticket_type_id)
                && input.checkout.registration_answers.registration_answers.is_none()
        })
        .returning(move |_| {
            Box::pin(async move {
                Ok(AttendOutcome::CheckoutRedirect {
                    hold_expires_at: Some(hold_expires_at),
                    redirect_url: "https://checkout.test/session".to_string(),
                })
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/checkout"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(format!(
            "admission_offer_id={admission_offer_id}&discount_code=EARLY&event_ticket_type_id={ticket_type_id}"
        )))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the redirect payload
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body["hold_expires_at"], json!(hold_expires_at));
    assert_eq!(body["redirect_url"], json!("https://checkout.test/session"));
    assert_eq!(body["status"], json!("pending-payment"));
}

#[tokio::test]
async fn test_start_checkout_returns_conflict() {
    // Setup identifiers and the sold-out conflict
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .returning(move |_| Ok(Some(community_id)));

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager.expect_start_checkout().times(1).returning(|_| {
        Box::pin(async { Ok(AttendOutcome::Conflict("ticket-type-sold-out".to_string())) })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/checkout"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(format!(
            "event_ticket_type_id={}",
            Uuid::new_v4()
        )))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the conflict payload
    assert_eq!(parts.status, StatusCode::CONFLICT);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "conflict": "ticket-type-sold-out" }));
}

#[tokio::test]
async fn test_start_checkout_returns_enrollment_status() {
    // Setup identifiers and a completed free checkout
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .returning(move |_| Ok(Some(community_id)));

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager.expect_start_checkout().times(1).returning(|_| {
        Box::pin(async { Ok(AttendOutcome::Enrolled(EventEnrollmentStatus::Attendee)) })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/checkout"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(format!(
            "event_ticket_type_id={}",
            Uuid::new_v4()
        )))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the enrollment status payload
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "status": "attendee" }));
}

#[tokio::test]
async fn test_start_checkout_returns_internal_server_error_when_manager_fails() {
    // Setup identifiers and an internal manager failure
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .returning(move |_| Ok(Some(community_id)));

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager.expect_start_checkout().times(1).returning(|_| {
        Box::pin(async { Err(EnrollmentError::Other(anyhow!("provider unavailable"))) })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/checkout"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(format!(
            "event_ticket_type_id={}",
            Uuid::new_v4()
        )))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the internal failure is hidden
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_start_checkout_returns_unprocessable_entity_for_rejection() {
    // Setup identifiers and the missing ticket rejection
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .returning(move |_| Ok(Some(community_id)));

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager
        .expect_start_checkout()
        .times(1)
        .withf(|input| input.checkout.event_ticket_type_id.is_none())
        .returning(|_| {
            Box::pin(async {
                Err(EnrollmentError::Rejected(
                    "ticket type is required".to_string(),
                ))
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/checkout"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(""))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "ticket type is required"
    );
}

#[tokio::test]
async fn test_submit_cfs_submission_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let session_proposal_id = Uuid::new_v4();
    let event_summary = sample_event_summary(event_id, group_id);
    let proposals = vec![sample_event_cfs_session_proposal(session_proposal_id)];
    let form_data = format!("session_proposal_id={session_proposal_id}");

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .returning(move |_| Ok(Some(community_id)));
    db.expect_add_cfs_submission()
        .times(1)
        .withf(move |cid, eid, uid, proposal_id, label_ids| {
            *cid == community_id
                && *eid == event_id
                && *uid == user_id
                && *proposal_id == session_proposal_id
                && label_ids.is_empty()
        })
        .returning(|_, _, _, _, _| Ok(Uuid::new_v4()));
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event_summary.clone()));
    db.expect_list_event_cfs_labels()
        .times(1)
        .withf(move |eid| *eid == event_id)
        .returning(|_| Ok(vec![]));
    db.expect_list_user_session_proposals_for_cfs_event()
        .times(1)
        .withf(move |uid, eid| *uid == user_id && *eid == event_id)
        .returning(move |_, _| Ok(proposals.clone()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-community/event/{event_id}/cfs-submissions"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(form_data))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8")
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_track_view_accepts_same_origin_request() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();

    // Setup database mock
    let db = MockDB::new();

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup activity tracker mock
    let mut activity_tracker = MockActivityTracker::new();
    activity_tracker
        .expect_track()
        .times(1)
        .withf(move |activity| *activity == Activity::EventView { event_id })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_activity_tracker(activity_tracker)
        .with_server_cfg(sample_tracking_server_cfg())
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/events/{event_id}/views"))
        .header("origin", "https://example.test")
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
async fn test_track_view_rejects_cross_origin_request() {
    // Setup database mock
    let db = MockDB::new();

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup activity tracker mock
    let mut activity_tracker = MockActivityTracker::new();
    activity_tracker.expect_track().times(0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_activity_tracker(activity_tracker)
        .with_server_cfg(sample_tracking_server_cfg())
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/events/{}/views", Uuid::new_v4()))
        .header("origin", "https://evil.test")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::FORBIDDEN);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_track_view_rejects_missing_origin_request() {
    // Setup dependencies that must not record the unverified request
    let db = MockDB::new();

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();
    let mut activity_tracker = MockActivityTracker::new();
    activity_tracker.expect_track().never();

    // Send a headerless tracking request
    let router = TestRouterBuilder::new(db, nm)
        .with_activity_tracker(activity_tracker)
        .with_server_cfg(sample_tracking_server_cfg())
        .build()
        .await;
    let response = router
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/events/{}/views", Uuid::new_v4()))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check missing same-origin evidence is forbidden
    assert_eq!(parts.status, StatusCode::FORBIDDEN);
    assert!(bytes.is_empty());
}
