use anyhow::anyhow;
use axum::{
    body::Body,
    http::{
        HeaderValue, Request, StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE, LOCATION},
    },
};
use chrono::TimeZone;
use serde_json::{from_slice, json};
use uuid::Uuid;

use crate::{
    activity_tracker::{Activity, MockActivityTracker},
    db::mock::{MockDB, expect_site_settings},
    handlers::tests::*,
    router::{CACHE_CONTROL_NO_STORE, CACHE_CONTROL_PRIVATE_NO_STORE, CACHE_CONTROL_PUBLIC_SHARED},
    services::{
        enrollment::{AttendOutcome, EnrollmentError, MockEnrollmentManager},
        inbox::{InboxError, MockInboxManager},
        payments::MockPaymentsManager,
    },
    types::{
        event::{EventEnrollmentState, EventEnrollmentStatus, EventFull, EventLeaveOutcome},
        inbox::{InboxContactContext, InboxContactViewer},
        payments::{
            EventPurchaseChargeModel, EventPurchaseStatus, EventTicketCurrentPrice,
            EventTicketType, EventTicketTypeAvailability, PreparedEventCheckout,
        },
        questionnaire::{QuestionnaireAnswer, QuestionnaireAnswerValue, QuestionnaireAnswers},
        user::User,
        utm::{EventUtmAllowlist, UtmParams},
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
    expect_test_community(&mut db, community_id);
    db.expect_get_event_full_by_slug()
        .times(1)
        .withf(move |id, group_slug, event_slug| {
            *id == community_id && group_slug == "test-group" && event_slug == "test-event"
        })
        .returning(move |_, _, _| Ok(Some(event.clone())));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = request(
        "GET",
        "/test-community/group/test-group/event/test-event/availability",
    )
    .body(Body::empty())
    .unwrap();
    let (parts, bytes) = send(router, request).await;
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
    expect_site_settings(&mut db);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = request(
        "GET",
        "/missing-community/group/test-group/event/test-event",
    )
    .body(Body::empty())
    .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::NOT_FOUND);
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
    // Setup database mock
    let community_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_event_page_reads(&mut db, community_id, "test-group", "missing-event", None);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = request(
        "GET",
        "/test-community/group/test-group/event/missing-event",
    )
    .body(Body::empty())
    .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::NOT_FOUND);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
    );
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("We could not find that page"));
    assert!(body.contains("Go to home page"));
}

#[tokio::test]
async fn test_page_renders_only_named_organizers() {
    // Setup an event with one named and one unnamed organizer
    let community_id = Uuid::new_v4();
    let mut event = sample_event_full(community_id, Uuid::new_v4(), Uuid::new_v4());
    event.community.name = "test-community".to_string();
    event.organizers = vec![
        User {
            user_id: Uuid::new_v4(),
            username: "ada-organizer".to_string(),

            name: Some("Ada Organizer".to_string()),
            ..Default::default()
        },
        User {
            user_id: Uuid::new_v4(),
            username: "bob-organizer".to_string(),
            ..Default::default()
        },
    ];
    event.group.slug = "test-group".to_string();
    event.slug = "test-event".to_string();

    // Setup database mock
    let mut db = MockDB::new();
    expect_event_page_reads(
        &mut db,
        community_id,
        "test-group",
        "test-event",
        Some(event),
    );

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = request("GET", "/test-community/group/test-group/event/test-event")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the organizers section lists only the named organizer
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("ada-organizer"));
    assert!(!body.contains("bob-organizer"));
}

#[tokio::test]
async fn test_page_renders_contact_opener_without_organizers() {
    // Setup an event without organizers
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let mut event = sample_event_full(community_id, event_id, Uuid::new_v4());
    event.community.name = "test-community".to_string();
    event.organizers = vec![];
    event.group.slug = "test-group".to_string();
    event.slug = "test-event".to_string();

    // Setup database mock
    let mut db = MockDB::new();
    expect_event_page_reads(
        &mut db,
        community_id,
        "test-group",
        "test-event",
        Some(event),
    );

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = request("GET", "/test-community/group/test-group/event/test-event")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the contact opener and modal render without organizers
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains(&format!(
        "hx-get=\"/test-community/event/{event_id}/contact-modal\""
    )));
    assert!(body.contains("<span>Contact organizers</span>"));
    assert!(body.contains("<div id=\"contact-modal-root\""));
}

#[tokio::test]
async fn test_page_temporarily_redirects_generated_group_slug_to_pretty_slug() {
    // Setup an event whose group has a pretty slug
    let community_id = Uuid::new_v4();
    let mut event = sample_event_full(community_id, Uuid::new_v4(), Uuid::new_v4());
    event.group.slug = "test-group".to_string();
    event.group.slug_pretty = Some("pretty-group".to_string());
    event.slug = "test-event".to_string();

    // Setup database mock
    let mut db = MockDB::new();
    expect_event_page_reads(
        &mut db,
        community_id,
        "test-group",
        "test-event",
        Some(event),
    );

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = request(
        "GET",
        "/test-community/group/test-group/event/test-event?utm_source=test",
    )
    .body(Body::empty())
    .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::TEMPORARY_REDIRECT);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
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
    let mut event = sample_event_full(community_id, event_id, Uuid::new_v4());
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
    expect_event_page_reads(
        &mut db,
        community_id,
        "pretty-group",
        "test-event",
        Some(event),
    );

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = request("GET", "/test-community/group/pretty-group/event/test-event")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
    );
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    let description = "Test Group in Test Community community. Open Community Groups, where Open Source communities thrive.";
    let url = "https://example.test/test-community/group/pretty-group/event/test-event";
    let image = "https://example.test/images/og/group-og.png";
    for tag in [
        "<title>Test Event - March 5</title>".to_string(),
        format!(r#"<meta name="description" content="{description}">"#),
        format!(r#"<link rel="canonical" href="{url}">"#),
        r#"<meta property="og:title" content="Test Event - March 5">"#.to_string(),
        format!(r#"<meta property="og:url" content="{url}">"#),
        format!(r#"<meta property="og:description" content="{description}">"#),
        format!(r#"<meta property="og:image" content="{image}">"#),
        r#"<meta name="twitter:title" content="Test Event - March 5">"#.to_string(),
        format!(r#"<meta name="twitter:description" content="{description}">"#),
        format!(r#"<meta name="twitter:image" content="{image}">"#),
    ] {
        assert!(body.contains(&tag), "missing {tag}");
    }
    assert!(body.contains(&format!(
        "hx-get=\"/test-community/event/{event_id}/contact-modal\""
    )));
    assert!(body.contains("data-modal-open-on-swap=\"contact-modal\""));
    assert!(!body.contains("data-contact-"));
}

#[tokio::test]
async fn test_cfs_modal_rejects_invalid_event_id_before_community_lookup() {
    // Prevent community resolution for an invalid event identifier
    let mut db = MockDB::new();
    db.expect_get_community_id_by_name().never();

    // Request the modal with a malformed event identifier
    let router = TestRouterBuilder::new(db).build().await;
    let request = request("GET", "/test-community/event/not-a-uuid/cfs-modal")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;
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
    let event_summary = sample_event_summary(event_id);

    // Setup database mock
    let mut db = MockDB::new();
    expect_test_community(&mut db, community_id);
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event_summary.clone()));
    db.expect_list_event_labels()
        .times(1)
        .withf(move |eid| *eid == event_id)
        .returning(|_| Ok(vec![]));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = request("GET", &event_uri(event_id, "cfs-modal"))
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the sign-in prompt replaces the submission form
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("You need to sign in to submit a proposal for this event."));
    assert!(body.contains("href=\"/log-in?next_url=/test-community/group/def5678/event/ghi9abc\""));
    assert!(!body.contains("id=\"cfs-submission-form\""));
}

#[tokio::test]
async fn test_cfs_modal_success_authenticated() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let session_proposal_id = Uuid::new_v4();
    let event_summary = sample_event_summary(event_id);
    let proposals = vec![sample_event_cfs_session_proposal(session_proposal_id)];

    // Setup database mock
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == ids.community_id && *eid == event_id)
        .returning(move |_, _| Ok(event_summary.clone()));
    db.expect_list_event_labels()
        .times(1)
        .withf(move |eid| *eid == event_id)
        .returning(|_| Ok(vec![]));
    db.expect_list_user_session_proposals_for_cfs_event()
        .times(1)
        .withf(move |uid, eid| *uid == ids.user_id && *eid == event_id)
        .returning(move |_, _| Ok(proposals.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(&event_uri(event_id, "cfs-modal"), ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the submission form lists the user's proposals
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("id=\"cfs-submission-form\""));
    assert!(body.contains(&format!("<option value=\"{session_proposal_id}\"")));
    assert!(body.contains("Sample Proposal"));
}

#[tokio::test]
async fn test_contact_modal_rejects_ineligible_event() {
    // Setup an event that does not accept contact
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_test_community(&mut db, community_id);
    expect_contact_context(&mut db, community_id, event_id, None, None);

    // Request the modal
    let router = TestRouterBuilder::new(db).build().await;
    let request = request("GET", &event_uri(event_id, "contact-modal"))
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the event is not found
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_contact_modal_rejects_invalid_event_id() {
    // Prevent community resolution for an invalid event identifier
    let mut db = MockDB::new();
    db.expect_get_community_id_by_name().never();

    // Request the modal with a malformed event identifier
    let router = TestRouterBuilder::new(db).build().await;
    let request = request("GET", "/test-community/event/not-a-uuid/contact-modal")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check path validation rejects the request
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert!(String::from_utf8(bytes.to_vec()).unwrap().contains("not-a-uuid"));
}

#[tokio::test]
async fn test_contact_modal_renders_blocked_notice() {
    // Setup a signed-in viewer blocked by spam reports
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let viewer = InboxContactViewer {
        is_blocked: true,
        ..sample_contact_viewer()
    };
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);
    expect_contact_context(
        &mut db,
        ids.community_id,
        event_id,
        Some(ids.user_id),
        Some(sample_contact_context(event_id, Some(viewer))),
    );

    // Request the modal
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(&event_uri(event_id, "contact-modal"), ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the blocked notice replaces the form
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("data-contact-blocked"));
    assert!(body.contains(
        "You can no longer contact <span class=\"font-semibold text-stone-900\">Test Group</span>."
    ));
    assert!(!body.contains("id=\"contact-form\""));
}

#[tokio::test]
async fn test_contact_modal_renders_daily_limit_notice() {
    // Setup a signed-in viewer who reached the daily limit
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let viewer = InboxContactViewer {
        can_start_conversation: false,
        ..sample_contact_viewer()
    };
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);
    expect_contact_context(
        &mut db,
        ids.community_id,
        event_id,
        Some(ids.user_id),
        Some(sample_contact_context(event_id, Some(viewer))),
    );

    // Request the modal
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(&event_uri(event_id, "contact-modal"), ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the limit notice replaces the form
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("data-contact-limit-reached"));
    assert!(!body.contains("id=\"contact-form\""));
}

#[tokio::test]
async fn test_contact_modal_renders_form_for_signed_in_users() {
    // Setup a signed-in viewer allowed to start a conversation
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);
    expect_contact_context(
        &mut db,
        ids.community_id,
        event_id,
        Some(ids.user_id),
        Some(sample_contact_context(
            event_id,
            Some(sample_contact_viewer()),
        )),
    );

    // Request the modal
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(&event_uri(event_id, "contact-modal"), ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the form contract and the private cache policy
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_PRIVATE_NO_STORE)
    );
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("id=\"contact-form\""));
    assert!(body.contains(&format!(
        "hx-post=\"/test-community/event/{event_id}/contact\""
    )));
    assert!(body.contains("name=\"body\""));
    assert!(!body.contains("maxlength="));
    assert!(body.contains("data-htmx-response"));
}

#[tokio::test]
async fn test_contact_modal_renders_open_conversation_link() {
    // Setup a signed-in viewer with an open conversation
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let inbox_conversation_id = Uuid::new_v4();
    let viewer = InboxContactViewer {
        open_inbox_conversation_id: Some(inbox_conversation_id),
        ..sample_contact_viewer()
    };
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);
    expect_contact_context(
        &mut db,
        ids.community_id,
        event_id,
        Some(ids.user_id),
        Some(sample_contact_context(event_id, Some(viewer))),
    );

    // Request the modal
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(&event_uri(event_id, "contact-modal"), ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the open conversation link replaces the form
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("data-contact-open-conversation"));
    assert!(body.contains(&format!(
        "/dashboard/user?tab=inbox&conversation_id={inbox_conversation_id}"
    )));
    assert!(!body.contains("id=\"contact-form\""));
}

#[tokio::test]
async fn test_contact_modal_renders_organizer_note() {
    // Setup a signed-in group team member
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let viewer = InboxContactViewer {
        can_manage_inbox: true,
        is_group_team_member: true,
        ..sample_contact_viewer()
    };
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);
    expect_contact_context(
        &mut db,
        ids.community_id,
        event_id,
        Some(ids.user_id),
        Some(sample_contact_context(event_id, Some(viewer))),
    );

    // Request the modal
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(&event_uri(event_id, "contact-modal"), ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the organizer note replaces the form
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(
        body.contains(
            "You're an organizer of the <span class=\"font-semibold text-stone-900\">Test Group</span> group."
        )
    );
    assert!(body.contains("href=\"/dashboard/group?tab=inbox\""));
    assert!(!body.contains("id=\"contact-form\""));
}

#[tokio::test]
async fn test_contact_modal_renders_organizer_note_for_community_inbox_managers() {
    // Setup a signed-in community team member with Inbox access
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let viewer = InboxContactViewer {
        can_manage_inbox: true,
        ..sample_contact_viewer()
    };
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);
    expect_contact_context(
        &mut db,
        ids.community_id,
        event_id,
        Some(ids.user_id),
        Some(sample_contact_context(event_id, Some(viewer))),
    );

    // Request the modal
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(&event_uri(event_id, "contact-modal"), ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the organizer note with the Inbox link replaces the form
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("data-contact-organizer-note"));
    assert!(
        body.contains(
            "You're an organizer of the <span class=\"font-semibold text-stone-900\">Test Group</span> group."
        )
    );
    assert!(body.contains("href=\"/dashboard/group?tab=inbox\""));
    assert!(!body.contains("id=\"contact-form\""));
}

#[tokio::test]
async fn test_contact_modal_renders_sign_in_prompt_for_anonymous_visitors() {
    // Setup an anonymous request
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_test_community(&mut db, community_id);
    expect_contact_context(
        &mut db,
        community_id,
        event_id,
        None,
        Some(sample_contact_context(event_id, None)),
    );

    // Request the modal
    let router = TestRouterBuilder::new(db).build().await;
    let request = request("GET", &event_uri(event_id, "contact-modal"))
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the sign-in prompt and the private cache policy
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_PRIVATE_NO_STORE)
    );
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("data-contact-sign-in"));
    assert!(
        body.contains(
            "href=\"/log-in?next_url=/test-community/group/test-group/event/test-event\""
        )
    );
    assert!(!body.contains("id=\"contact-form\""));
}

#[tokio::test]
async fn test_contact_modal_renders_team_note_without_inbox_link_for_viewers() {
    // Setup a signed-in group team member without Inbox access
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let viewer = InboxContactViewer {
        is_group_team_member: true,
        ..sample_contact_viewer()
    };
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);
    expect_contact_context(
        &mut db,
        ids.community_id,
        event_id,
        Some(ids.user_id),
        Some(sample_contact_context(event_id, Some(viewer))),
    );

    // Request the modal
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(&event_uri(event_id, "contact-modal"), ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the team note replaces the form without the Inbox link
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("data-contact-organizer-note"));
    assert!(body.contains(
        "You're a team member of the <span class=\"font-semibold text-stone-900\">Test Group</span> group."
    ));
    assert!(!body.contains("You're an organizer of the <span"));
    assert!(!body.contains("/dashboard/group?tab=inbox"));
    assert!(!body.contains("id=\"contact-form\""));
}

#[tokio::test]
async fn test_attend_event_returns_checkout_redirect() {
    // Setup identifiers and the redirect outcome
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let ticket_type_id = Uuid::new_v4();
    let hold_expires_at = chrono::Utc.with_ymd_and_hms(2030, 1, 2, 3, 4, 5).unwrap();

    // Setup session and community resolution
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);

    // Setup the enrollment manager expectation
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager
        .expect_attend_event()
        .times(1)
        .withf(move |input| {
            input.community_id == ids.community_id
                && input.event_id == event_id
                && input.user_id == ids.user_id
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
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = form_request(
        "POST",
        &event_uri(event_id, "attend"),
        ids.session_id,
        format!("event_ticket_type_id={ticket_type_id}"),
    );
    let (parts, bytes) = send(router, request).await;

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
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);

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
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = form_request("POST", &event_uri(event_id, "attend"), ids.session_id, "");
    let (parts, bytes) = send(router, request).await;

    // Check the conflict payload
    assert_eq!(parts.status, StatusCode::CONFLICT);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "conflict": "event-capacity-unavailable" }));
}

#[tokio::test]
async fn test_attend_event_returns_enrollment_status_with_registration_answers() {
    // Setup identifiers and the submitted answers
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let question_id = Uuid::new_v4();
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
    expect_member_context(&mut db, &ids);

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
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = form_request(
        "POST",
        &event_uri(event_id, "attend"),
        ids.session_id,
        form_body,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the enrollment status payload
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "status": "waitlisted" }));
}

#[tokio::test]
async fn test_attend_event_returns_external_pending_payment() {
    // Setup identifiers and the external purchase snapshot
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let hold_expires_at = chrono::Utc.with_ymd_and_hms(2030, 1, 2, 3, 4, 5).unwrap();
    let mut purchase =
        sample_event_purchase_summary(event_purchase_id, EventPurchaseStatus::Pending);
    purchase.charge_model = EventPurchaseChargeModel::External;
    purchase.external_payment_instructions = Some("Use reference on the transfer.".to_string());
    purchase.external_payment_url = Some("https://pay.example.test/event".to_string());
    purchase.hold_expires_at = Some(hold_expires_at);

    // Setup database mock
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);

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
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = form_request("POST", &event_uri(event_id, "attend"), ids.session_id, "");
    let (parts, bytes) = send(router, request).await;

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
async fn test_attend_event_returns_unprocessable_entity_for_rejection() {
    // Setup identifiers and an application rejection
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);

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
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = form_request("POST", &event_uri(event_id, "attend"), ids.session_id, "");
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "questionnaire answers are required"
    );
}

#[tokio::test]
async fn test_enrollment_state_paid_attendee_can_request_refund() {
    // Setup a paid attendee of an event that has not started yet
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut event_summary = sample_event_summary(event_id);
    event_summary.starts_at = Some(chrono::Utc::now() + chrono::Duration::days(1));

    // Setup database mock
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);
    db.expect_get_event_enrollment()
        .times(1)
        .withf(move |cid, eid, uid| {
            *cid == ids.community_id && *eid == event_id && *uid == ids.user_id
        })
        .returning(|_, _, _| {
            Ok(EventEnrollmentState {
                purchase_amount_minor: Some(2500),
                ..sample_enrollment_state(EventEnrollmentStatus::Attendee)
            })
        });
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == ids.community_id && *eid == event_id)
        .returning(move |_, _| Ok(event_summary.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(&event_uri(event_id, "enrollment"), ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the refund request is offered for the paid attendance
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body["can_request_refund"], json!(true));
    assert_eq!(body["purchase_amount_minor"], json!(2500));
    assert_eq!(body["status"], json!("attendee"));
}

#[tokio::test]
async fn test_enrollment_state_success() {
    // Setup a free attendee, whose refund eligibility needs no event read
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);
    db.expect_get_event_enrollment()
        .times(1)
        .withf(move |cid, eid, uid| {
            *cid == ids.community_id && *eid == event_id && *uid == ids.user_id
        })
        .returning(|_, _, _| Ok(sample_enrollment_state(EventEnrollmentStatus::Attendee)));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(&event_uri(event_id, "enrollment"), ids.session_id);
    let (parts, bytes) = send(router, request).await;

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
async fn test_cancel_checkout_success() {
    // Setup identifiers and the restored enrollment state
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);
    db.expect_cancel_event_checkout()
        .times(1)
        .withf(move |cid, eid, uid, payment_provider| {
            *cid == ids.community_id
                && *eid == event_id
                && *uid == ids.user_id
                && payment_provider.is_none()
        })
        .returning(|_, _, _, _| Ok(()));
    db.expect_get_event_enrollment()
        .times(1)
        .withf(move |cid, eid, uid| {
            *cid == ids.community_id && *eid == event_id && *uid == ids.user_id
        })
        .returning(|_, _, _| {
            Ok(EventEnrollmentState {
                admission_offer_id: Some(Uuid::from_u128(1)),
                event_ticket_type_id: Some(Uuid::from_u128(2)),
                ..sample_enrollment_state(EventEnrollmentStatus::InvitationApproved)
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request("DELETE", &event_uri(event_id, "checkout"), ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "status": "invitation-approved" }));
}

#[tokio::test]
async fn test_leave_event_returns_left_status() {
    // Setup identifiers and the leave outcome
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager
        .expect_leave_event()
        .times(1)
        .withf(move |input| {
            input.community_id == ids.community_id
                && input.event_id == event_id
                && input.user_id == ids.user_id
        })
        .returning(|_| {
            Box::pin(async {
                Ok(EventLeaveOutcome {
                    left_status: EventEnrollmentStatus::Attendee,
                })
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = empty_request("DELETE", &event_uri(event_id, "leave"), ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the left status payload
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "left_status": "attendee" }));
}

#[tokio::test]
async fn test_leave_event_returns_unprocessable_entity_for_rejection() {
    // Setup identifiers and the paid-attendee rejection
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager.expect_leave_event().times(1).returning(|_| {
        Box::pin(async {
            Err(EnrollmentError::Rejected(
                "paid attendance must be refunded before leaving".to_string(),
            ))
        })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = empty_request("DELETE", &event_uri(event_id, "leave"), ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "paid attendance must be refunded before leaving"
    );
}

#[tokio::test]
async fn test_request_refund_returns_unprocessable_entity_for_rejection() {
    // Setup identifiers and a refund request rejection
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);

    // Setup payments manager mock
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_request_refund().times(1).returning(|_| {
        Box::pin(async {
            Err(HandlerError::Database("refund request already exists".to_string()).into())
        })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = form_request(
        "POST",
        &event_uri(event_id, "refund-request"),
        ids.session_id,
        "requested_reason=Need%20to%20cancel",
    );
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "refund request already exists"
    );
}

#[tokio::test]
async fn test_request_refund_success() {
    // Setup identifiers and the refund request expectation
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);

    // Setup payments manager mock
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_request_refund()
        .times(1)
        .withf(move |input| {
            input.community_id == ids.community_id
                && input.event_id == event_id
                && input.requested_reason.as_deref() == Some("Need to cancel")
                && input.user_id == ids.user_id
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = form_request(
        "POST",
        &event_uri(event_id, "refund-request"),
        ids.session_id,
        "requested_reason=Need%20to%20cancel",
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "status": "refund-requested" }));
}

#[tokio::test]
async fn test_send_contact_message_redirects_anonymous_visitors_to_log_in() {
    // Setup an anonymous request without manager calls
    let event_id = Uuid::new_v4();
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager.expect_start_conversation().never();

    // Send the message
    let router = TestRouterBuilder::new(MockDB::new())
        .with_inbox_manager(inbox_manager)
        .build()
        .await;
    let request = request("POST", &event_uri(event_id, "contact"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from("body=Hello"))
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the visitor is sent to the log-in page
    assert_empty_response(&parts, &bytes, StatusCode::TEMPORARY_REDIRECT);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &format!("/log-in?next_url=%2Ftest-community%2Fevent%2F{event_id}%2Fcontact")
    );
}

#[tokio::test]
async fn test_send_contact_message_rejects_invalid_bodies() {
    // Setup the signed-in sender and invalid bodies
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let too_long = format!("body={}", "é".repeat(5001));

    for body in ["body=+%0A%09+".to_string(), too_long] {
        // Setup session and community expectations without manager calls
        let mut db = MockDB::new();
        expect_member_context(&mut db, &ids);
        let mut inbox_manager = MockInboxManager::new();
        inbox_manager.expect_start_conversation().never();

        // Send the message
        let router = TestRouterBuilder::new(db)
            .with_inbox_manager(inbox_manager)
            .build()
            .await;
        let label = body.chars().take(20).collect::<String>();
        let request = form_request(
            "POST",
            &event_uri(event_id, "contact"),
            ids.session_id,
            body,
        );
        let (parts, _) = send(router, request).await;

        // Check the validation failure
        assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY, "{label}");
    }
}

#[tokio::test]
async fn test_send_contact_message_returns_rejected_message() {
    // Setup the signed-in sender and an open conversation rejection
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager.expect_start_conversation().times(1).returning(|_| {
        Box::pin(async {
            Err(InboxError::Rejected(
                "you already have an open conversation about this event".to_string(),
            ))
        })
    });

    // Send the message
    let router = TestRouterBuilder::new(db)
        .with_inbox_manager(inbox_manager)
        .build()
        .await;
    let request = form_request(
        "POST",
        &event_uri(event_id, "contact"),
        ids.session_id,
        "body=Hello",
    );
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "you already have an open conversation about this event"
    );
}

#[tokio::test]
async fn test_send_contact_message_starts_conversation() {
    // Setup the signed-in sender and the started conversation
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let inbox_conversation_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);
    let mut inbox_manager = MockInboxManager::new();
    inbox_manager
        .expect_start_conversation()
        .times(1)
        .withf(move |input| {
            input.body == "Is there parking?"
                && input.community_id == ids.community_id
                && input.event_id == event_id
                && input.user_id == ids.user_id
        })
        .returning(move |_| Box::pin(async move { Ok(inbox_conversation_id) }));

    // Send the message
    let router = TestRouterBuilder::new(db)
        .with_inbox_manager(inbox_manager)
        .build()
        .await;
    let request = form_request(
        "POST",
        &event_uri(event_id, "contact"),
        ids.session_id,
        "body=Is+there+parking%3F",
    );
    let (parts, bytes) = send(router, request).await;

    // Check the sent notice links to the conversation
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("data-contact-sent-notice"));
    assert!(body.contains(&format!(
        "/dashboard/user?tab=inbox&conversation_id={inbox_conversation_id}"
    )));
}

#[tokio::test]
async fn test_start_checkout_returns_checkout_redirect() {
    // Setup identifiers and the redirect outcome
    let ids = DashboardIds::new();
    let admission_offer_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let ticket_type_id = Uuid::new_v4();
    let hold_expires_at = chrono::Utc.with_ymd_and_hms(2030, 1, 2, 3, 4, 5).unwrap();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);

    // Setup the enrollment manager expectation on the decoded form
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager
        .expect_start_checkout()
        .times(1)
        .withf(move |input| {
            input.community_id == ids.community_id
                && input.event_id == event_id
                && input.user_id == ids.user_id
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
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = form_request(
        "POST",
        &event_uri(event_id, "checkout"),
        ids.session_id,
        format!(
            "admission_offer_id={admission_offer_id}&discount_code=EARLY&event_ticket_type_id={ticket_type_id}"
        ),
    );
    let (parts, bytes) = send(router, request).await;

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
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager.expect_start_checkout().times(1).returning(|_| {
        Box::pin(async { Ok(AttendOutcome::Conflict("ticket-type-sold-out".to_string())) })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = form_request(
        "POST",
        &event_uri(event_id, "checkout"),
        ids.session_id,
        format!("event_ticket_type_id={}", Uuid::new_v4()),
    );
    let (parts, bytes) = send(router, request).await;

    // Check the conflict payload
    assert_eq!(parts.status, StatusCode::CONFLICT);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "conflict": "ticket-type-sold-out" }));
}

#[tokio::test]
async fn test_start_checkout_returns_enrollment_status() {
    // Setup identifiers and a completed free checkout
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager.expect_start_checkout().times(1).returning(|_| {
        Box::pin(async { Ok(AttendOutcome::Enrolled(EventEnrollmentStatus::Attendee)) })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = form_request(
        "POST",
        &event_uri(event_id, "checkout"),
        ids.session_id,
        format!("event_ticket_type_id={}", Uuid::new_v4()),
    );
    let (parts, bytes) = send(router, request).await;

    // Check the enrollment status payload
    assert_eq!(parts.status, StatusCode::OK);
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "status": "attendee" }));
}

#[tokio::test]
async fn test_start_checkout_returns_unprocessable_entity_for_rejection() {
    // Setup identifiers and the missing ticket rejection
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);

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
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = form_request("POST", &event_uri(event_id, "checkout"), ids.session_id, "");
    let (parts, bytes) = send(router, request).await;

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
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let session_proposal_id = Uuid::new_v4();
    let event_summary = sample_event_summary(event_id);
    let mut proposal = sample_event_cfs_session_proposal(session_proposal_id);
    proposal.is_submitted = true;
    let proposals = vec![proposal];

    // Setup database mock
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);
    db.expect_add_cfs_submission()
        .times(1)
        .withf(move |cid, eid, uid, proposal_id, label_ids| {
            *cid == ids.community_id
                && *eid == event_id
                && *uid == ids.user_id
                && *proposal_id == session_proposal_id
                && label_ids.is_empty()
        })
        .returning(|_, _, _, _, _| Ok(Uuid::new_v4()));
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == ids.community_id && *eid == event_id)
        .returning(move |_, _| Ok(event_summary.clone()));
    db.expect_list_event_labels()
        .times(1)
        .withf(move |eid| *eid == event_id)
        .returning(|_| Ok(vec![]));
    db.expect_list_user_session_proposals_for_cfs_event()
        .times(1)
        .withf(move |uid, eid| *uid == ids.user_id && *eid == event_id)
        .returning(move |_, _| Ok(proposals.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "POST",
        &event_uri(event_id, "cfs-submissions"),
        ids.session_id,
        format!("session_proposal_id={session_proposal_id}"),
    );
    let (parts, bytes) = send(router, request).await;

    // Check the modal renders the notice and the refreshed proposals
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("data-cfs-submission-notice"));
    assert!(body.contains("Submission received."));
    assert!(body.contains("Sample Proposal"));
}

#[tokio::test]
async fn test_track_view_accepts_same_origin_request() {
    // Setup a view without UTM values to look up
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_event_utm_allowlist().never();
    let activity_tracker = expect_event_view(event_id, None);

    // Setup router and send the tracking request
    let router = TestRouterBuilder::new(db)
        .with_activity_tracker(activity_tracker)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = track_view_request(&format!("/events/{event_id}/views"));
    let (parts, bytes) = send(router, request).await;

    // Check the view is accepted
    assert_empty_response(&parts, &bytes, StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_track_view_drops_utm_params_not_accepted_by_event() {
    // Setup an allowlist without the requested campaign
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_event_utm_allowlist()
        .times(1)
        .withf(move |id| *id == event_id)
        .returning(|_| {
            Ok(Some(EventUtmAllowlist {
                sources: vec!["newsletter".to_string()],
                ..EventUtmAllowlist::default()
            }))
        });
    let activity_tracker = expect_event_view(event_id, None);

    // Setup router and send the tracking request
    let router = TestRouterBuilder::new(db)
        .with_activity_tracker(activity_tracker)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = track_view_request(&format!(
        "/events/{event_id}/views?utm_campaign=spring-launch&utm_source=newsletter"
    ));
    let (parts, bytes) = send(router, request).await;

    // Check the view is counted without attribution
    assert_empty_response(&parts, &bytes, StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_track_view_drops_utm_params_of_unpublished_event() {
    // Setup no allowlist for an unpublished event
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_event_utm_allowlist()
        .times(1)
        .withf(move |id| *id == event_id)
        .returning(|_| Ok(None));
    let activity_tracker = expect_event_view(event_id, None);

    // Setup router and send the tracking request
    let router = TestRouterBuilder::new(db)
        .with_activity_tracker(activity_tracker)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = track_view_request(&format!("/events/{event_id}/views?utm_source=newsletter"));
    let (parts, bytes) = send(router, request).await;

    // Check the view is counted without attribution
    assert_empty_response(&parts, &bytes, StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_track_view_drops_utm_params_when_lookup_fails() {
    // Setup a failing allowlist lookup
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_event_utm_allowlist()
        .times(1)
        .withf(move |id| *id == event_id)
        .returning(|_| Err(anyhow!("db error")));
    let activity_tracker = expect_event_view(event_id, None);

    // Setup router and send the tracking request
    let router = TestRouterBuilder::new(db)
        .with_activity_tracker(activity_tracker)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = track_view_request(&format!("/events/{event_id}/views?utm_source=newsletter"));
    let (parts, bytes) = send(router, request).await;

    // Check the view is counted without attribution
    assert_empty_response(&parts, &bytes, StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_track_view_ignores_invalid_utm_params() {
    // Setup a view whose invalid UTM values need no lookup
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_event_utm_allowlist().never();
    let activity_tracker = expect_event_view(event_id, None);

    // Setup router and send the tracking request
    let router = TestRouterBuilder::new(db)
        .with_activity_tracker(activity_tracker)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = track_view_request(&format!(
        "/events/{event_id}/views?utm_campaign=spring-launch&utm_source=news%20letter"
    ));
    let (parts, bytes) = send(router, request).await;

    // Check the view is counted without attribution
    assert_empty_response(&parts, &bytes, StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_track_view_ignores_malformed_query() {
    // Setup a view whose malformed query needs no lookup
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_event_utm_allowlist().never();
    let activity_tracker = expect_event_view(event_id, None);

    // Setup router and send the tracking request
    let router = TestRouterBuilder::new(db)
        .with_activity_tracker(activity_tracker)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = track_view_request(&format!(
        "/events/{event_id}/views?utm_source[x]=newsletter"
    ));
    let (parts, bytes) = send(router, request).await;

    // Check the view is still counted
    assert_empty_response(&parts, &bytes, StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_track_view_ignores_utm_params_without_source_or_campaign() {
    // Setup a view whose blank source and campaign need no lookup
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_event_utm_allowlist().never();
    let activity_tracker = expect_event_view(event_id, None);

    // Setup router and send the tracking request
    let router = TestRouterBuilder::new(db)
        .with_activity_tracker(activity_tracker)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = track_view_request(&format!(
        "/events/{event_id}/views?utm_campaign=%20&utm_medium=email&utm_source=%20"
    ));
    let (parts, bytes) = send(router, request).await;

    // Check the view is counted without attribution
    assert_empty_response(&parts, &bytes, StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_track_view_records_utm_params_accepted_by_event() {
    // Setup the values accepted for the event
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_event_utm_allowlist()
        .times(1)
        .withf(move |id| *id == event_id)
        .returning(|_| Ok(Some(sample_event_utm_allowlist())));
    let activity_tracker = expect_event_view(
        event_id,
        UtmParams::new(Some("spring-launch"), None, Some("newsletter")),
    );

    // Setup router and send the tracking request
    let router = TestRouterBuilder::new(db)
        .with_activity_tracker(activity_tracker)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = track_view_request(&format!(
        "/events/{event_id}/views?utm_campaign=Spring-Launch&utm_medium=&utm_source=%20Newsletter%20"
    ));
    let (parts, bytes) = send(router, request).await;

    // Check the view is counted with its normalized attribution
    assert_empty_response(&parts, &bytes, StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_track_view_rejects_cross_origin_request() {
    // Setup an activity tracker that must not record the request
    let mut activity_tracker = MockActivityTracker::new();
    activity_tracker.expect_track().times(0);

    // Setup router and send request
    let router = TestRouterBuilder::new(MockDB::new())
        .with_activity_tracker(activity_tracker)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = request("POST", &format!("/events/{}/views", Uuid::new_v4()))
        .header("origin", "https://evil.test")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_track_view_rejects_missing_origin_request() {
    // Setup an activity tracker that must not record the request
    let mut activity_tracker = MockActivityTracker::new();
    activity_tracker.expect_track().times(0);

    // Send a request without origin headers, which the middleware lets through
    let router = TestRouterBuilder::new(MockDB::new())
        .with_activity_tracker(activity_tracker)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = request("POST", &format!("/events/{}/views", Uuid::new_v4()))
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the handler rejects the request without same-origin evidence
    assert_empty_response(&parts, &bytes, StatusCode::FORBIDDEN);
}

// Helpers.

/// Builds the URI of an event-scoped route of the test community.
fn event_uri(event_id: Uuid, action: &str) -> String {
    format!("/test-community/event/{event_id}/{action}")
}

/// Expects one contact context read for the viewer, returning `context`.
fn expect_contact_context(
    db: &mut MockDB,
    community_id: Uuid,
    event_id: Uuid,
    user_id: Option<Uuid>,
    context: Option<InboxContactContext>,
) {
    db.expect_get_inbox_contact_context()
        .times(1)
        .withf(move |cid, eid, uid| *cid == community_id && *eid == event_id && *uid == user_id)
        .returning(move |_, _, _| Ok(context.clone()));
}

/// Expects the reads the event page always performs: the test community, the
/// site settings and the event lookup by slug, which returns `event`.
fn expect_event_page_reads(
    db: &mut MockDB,
    community_id: Uuid,
    group_slug: &'static str,
    event_slug: &'static str,
    event: Option<EventFull>,
) {
    expect_test_community(db, community_id);
    expect_site_settings(db);
    db.expect_get_event_full_by_slug()
        .times(1)
        .withf(move |id, gslug, eslug| {
            *id == community_id && gslug == group_slug && eslug == event_slug
        })
        .returning(move |_, _, _| Ok(event.clone()));
}

/// Expects one tracked view of the event with the given attribution.
fn expect_event_view(event_id: Uuid, utm: Option<UtmParams>) -> MockActivityTracker {
    let mut activity_tracker = MockActivityTracker::new();
    activity_tracker
        .expect_track()
        .times(1)
        .withf(move |activity| {
            *activity
                == Activity::EventView {
                    event_id,
                    utm: utm.clone(),
                }
        })
        .returning(|_| Box::pin(async { Ok(()) }));
    activity_tracker
}

/// Builds the contact context of the test event.
fn sample_contact_context(
    event_id: Uuid,
    viewer: Option<InboxContactViewer>,
) -> InboxContactContext {
    InboxContactContext {
        community_name: "test-community".to_string(),
        event_id,
        event_name: "Test Event".to_string(),
        event_slug: "test-event".to_string(),
        group_name: "Test Group".to_string(),
        group_slug: "test-group".to_string(),

        group_slug_pretty: None,
        viewer,
    }
}

/// Builds the state of a signed-in viewer allowed to start a conversation.
fn sample_contact_viewer() -> InboxContactViewer {
    InboxContactViewer {
        can_manage_inbox: false,
        can_start_conversation: true,
        is_blocked: false,
        is_group_team_member: false,

        open_inbox_conversation_id: None,
    }
}

/// Builds a same-origin view tracking request.
fn track_view_request(uri: &str) -> Request<Body> {
    request("POST", uri)
        .header("origin", "https://example.test")
        .body(Body::empty())
        .unwrap()
}
