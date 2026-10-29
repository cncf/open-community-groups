use anyhow::anyhow;
use axum::{
    body::Body,
    http::{HeaderValue, Request, StatusCode, header::CONTENT_TYPE, response::Parts},
};
use serde_json::{Value, from_slice, json, to_value};
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::{error::INVALID_REQUEST_PAYLOAD, tests::*},
    services::{
        events::{AutomaticTaxCheckError, EventsError, MockEventsManager},
        payments::{AutomaticTaxReadiness, AutomaticTaxReadinessError},
    },
    types::{
        dashboard::{
            DASHBOARD_PAGINATION_LIMIT,
            group::{
                events::{EventActionScope, EventCohostInvitation, EventCohostsEditor},
                invitation_requests::{InvitationRequestsOutput, InvitationRequestsStatusFilter},
                sponsors::GroupSponsorsOutput,
                waitlist::WaitlistOutput,
            },
        },
        event::{EventCohostStatus, EventFull},
        payments::{
            EventTicketPriceWindow, EventTicketType, GroupExternalPaymentsContext,
            GroupPaymentRecipient, TicketTaxBehavior, TicketTaxRate,
        },
        permissions::GroupPermission,
        user::User,
    },
};

#[tokio::test]
async fn test_add_page_renders_external_ticketing_without_payment_recipient() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let external_payments = GroupExternalPaymentsContext {
        configured: true,
        eligible: true,
        enabled: true,
        country_code: Some("KR".to_string()),
        default_payment_window_hours: Some(72),
        max_payment_window_hours: Some(336),
        seller_display_name: Some("External Payee Co".to_string()),
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);
    expect_event_editor_option_reads(&mut db, &ids, external_payments, vec![], None);

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let request = get_request("/dashboard/group/events/add", ids.session_id);
    let (parts, bytes) = send(router, request).await;

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
async fn test_add_page_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);
    expect_event_editor_option_reads(
        &mut db,
        &ids,
        GroupExternalPaymentsContext::default(),
        sample_team_members(),
        None,
    );

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let request = get_request("/dashboard/group/events/add", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains(">Tickets</"));
    assert!(body.contains("free-only"));
    assert!(body.contains("Ticket prices are fixed at 0 until payments are configured"));

    // Check the authoring tabs are grouped without review groups
    assert!(appear_in_order(
        &body,
        &[
            "<optgroup label=\"EVENT\">",
            "<optgroup label=\"REGISTRATION\">",
            "<optgroup label=\"PROGRAM\">",
        ],
    ));
    assert!(!body.contains("<optgroup label=\"PEOPLE\">"));
    assert!(!body.contains("<optgroup label=\"FOLLOW-UP\">"));
    assert!(!body.contains("data-section=\"attendees\""));

    // Check the contributors tab selects organizers from the group team
    assert!(body.contains("data-section=\"contributors\""));
    assert!(body.contains("<form id=\"contributors-form\" data-event-form>"));
    let team_attribute = users_attribute(&sample_team_members());
    let organizers_selector = selector_tag(&body, "id=\"event-organizers-selector\"");
    assert!(organizers_selector.contains(&format!("selected-users=\"{team_attribute}\"")));
    assert!(organizers_selector.contains(&format!("available-users=\"{team_attribute}\"")));
    assert!(organizers_selector.contains("field-name=\"organizers\""));
    assert!(!organizers_selector.contains("can-award-badges"));
    assert!(body.contains("<input type=\"hidden\" name=\"organizers_present\" value=\"true\">"));
    assert!(!body.contains("event-organizers-award-button"));

    // Check the contributor sections follow the public page order
    assert!(appear_in_order(
        &body,
        &[
            "id=\"event-speakers-selector\"",
            "id=\"event-hosts-selector\"",
            "id=\"event-organizers-selector\"",
            "<sponsors-section",
        ],
    ));
}

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let mut group_events = sample_group_events(Uuid::new_v4());
    group_events.upcoming.events[0].canceled = true;
    group_events.upcoming.events[0].test_event = true;

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);
    db.expect_list_group_events()
        .times(1)
        .withf(move |group_id, filters| {
            *group_id == ids.group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.past_offset == Some(0)
                && filters.upcoming_offset == Some(0)
        })
        .returning(move |_, _| Ok(group_events.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group/events", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url").unwrap(),
        "/dashboard/group?tab=events&limit=50&past_offset=0&upcoming_offset=0"
    );
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("aria-label=\"Open event details: Sample Event\""));
    assert!(body.contains(">Test</span>"));
    assert!(body.contains("title=\"View canceled event\""));
    assert!(!body.contains("disabled title=\"Event is canceled\""));
}

#[tokio::test]
async fn test_list_page_waits_for_pending_cohosts_before_publishing() {
    // Setup identifiers and an unpublished event with pending co-hosts
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut group_events = sample_group_events(event_id);
    group_events.past.events.clear();
    group_events.past.total = 0;
    group_events.upcoming.events[0].pending_cohosts_count = Some(2);
    group_events.upcoming.events[0].published = false;

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);
    db.expect_list_group_events()
        .times(1)
        .returning(move |_, _| Ok(group_events.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group/events", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the publish action is disabled with the pending co-hosts reason
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    let publish_button = body
        .split(&format!("id=\"publish-event-{event_id}\""))
        .nth(1)
        .and_then(|rest| rest.split("</button>").next())
        .expect("publish action to be rendered");
    assert!(publish_button.contains("disabled title=\"Waiting for 2 co-host(s) to respond.\""));
    assert!(publish_button.contains("cursor-not-allowed"));
}

#[tokio::test]
async fn test_update_page_hides_awards_and_surveys_for_canceled_events() {
    // Setup identifiers and a canceled event
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_full = EventFull {
        canceled: true,
        ..sample_event_full(ids.community_id, event_id, ids.group_id)
    };

    // Setup database mock without enrollment rows
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);
    expect_update_page_reads(
        &mut db,
        &ids,
        event_full,
        EventCohostsEditor::default(),
        None,
    );
    expect_invitation_requests_tab_search(&mut db, &ids, event_id, 0);
    expect_waitlist_tab_search(&mut db, &ids, event_id, 0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let request = update_page_request(&ids, event_id);
    let (parts, bytes) = send(router, request).await;

    // Check organizers render without award wiring
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    let organizers_selector = selector_tag(&body, "id=\"event-organizers-selector\"");
    assert!(!organizers_selector.contains("can-award-badges"));
    assert!(!organizers_selector.contains("award-button-id="));
    assert!(!body.contains("event-organizers-award-button"));
    assert!(!body.contains("event-hosts-award-button"));
    assert!(!body.contains("can-award-badges"));

    // Check the surveys tab and its content are not rendered
    assert!(!body.contains("<option value=\"surveys\""));
    assert!(!body.contains("data-section=\"surveys\""));
    assert!(!body.contains("data-content=\"surveys\""));
    assert!(body.contains("data-section=\"analytics\""));
}

#[tokio::test]
async fn test_update_page_hides_contributor_awards_for_read_only_users() {
    // Setup identifiers and an active event
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_full = sample_event_full(ids.community_id, event_id, ids.group_id);

    // Setup database mock for a user who cannot manage events
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, false);
    expect_update_page_reads(
        &mut db,
        &ids,
        event_full,
        EventCohostsEditor::default(),
        None,
    );
    expect_invitation_requests_tab_search(&mut db, &ids, event_id, 0);
    expect_waitlist_tab_search(&mut db, &ids, event_id, 0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let request = update_page_request(&ids, event_id);
    let (parts, bytes) = send(router, request).await;

    // Check organizers render without award wiring
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    let organizers_selector = selector_tag(&body, "id=\"event-organizers-selector\"");
    assert!(!organizers_selector.contains("can-award-badges"));
    assert!(!organizers_selector.contains("award-button-id="));
    assert!(!body.contains("event-organizers-award-button"));
    assert!(!body.contains("event-hosts-award-button"));
    assert!(!body.contains("can-award-badges"));
}

#[tokio::test]
async fn test_update_page_renders_paid_ticket_settings_read_only_after_purchases() {
    // Setup identifiers and a paid event with purchases
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
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
        ..sample_event_full(ids.community_id, event_id, ids.group_id)
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);
    expect_update_page_reads(
        &mut db,
        &ids,
        event_full,
        EventCohostsEditor::default(),
        None,
    );
    expect_invitation_requests_tab_search(&mut db, &ids, event_id, 0);
    expect_waitlist_tab_search(&mut db, &ids, event_id, 0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let request = update_page_request(&ids, event_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("Paid ticket settings are read-only"));
    assert!(body.contains("data-disabled=\"true\""));
}

#[tokio::test]
async fn test_update_page_leaves_logo_field_empty_without_own_logo() {
    // Setup identifiers and an event whose logo falls back to the group logo
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut event_full = sample_event_full(ids.community_id, event_id, ids.group_id);
    event_full.custom_logo_url = None;
    event_full.group.logo_url = "https://example.test/group-logo.png".to_string();
    event_full.logo_url = "https://example.test/group-logo.png".to_string();

    // Setup database mock without enrollment rows
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);
    expect_update_page_reads(
        &mut db,
        &ids,
        event_full,
        EventCohostsEditor::default(),
        None,
    );
    expect_invitation_requests_tab_search(&mut db, &ids, event_id, 0);
    expect_waitlist_tab_search(&mut db, &ids, event_id, 0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = update_page_request(&ids, event_id);
    let (parts, bytes) = send(router, request).await;

    // Check the fallback logo stays out of the form but remains available to the preview
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert_image_field_value(&body, "logo_url", "");
    assert!(body.contains(r#"data-group-logo-url="https://example.test/group-logo.png""#));
}

#[tokio::test]
async fn test_update_page_shows_enabled_invitation_requests_tab_without_search() {
    // Setup identifiers and an approval event without the waitlist
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_full = EventFull {
        attendee_approval_required: true,
        ..sample_event_full(ids.community_id, event_id, ids.group_id)
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);
    expect_update_page_reads(
        &mut db,
        &ids,
        event_full,
        EventCohostsEditor::default(),
        None,
    );
    db.expect_search_event_invitation_requests().never();
    expect_waitlist_tab_search(&mut db, &ids, event_id, 0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let request = update_page_request(&ids, event_id);
    let (parts, bytes) = send(router, request).await;

    // Check only the enabled enrollment tab is shown
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("<option value=\"invitation-requests\""));
    assert!(body.contains("data-section=\"invitation-requests\""));
    assert!(body.contains("data-content=\"invitation-requests\""));
    assert!(body.contains(&format!(
        "hx-get=\"/dashboard/group/events/{event_id}/invitation-requests\""
    )));
    assert!(!body.contains("<option value=\"waitlist\""));
    assert!(!body.contains("data-section=\"waitlist\""));
    assert!(!body.contains("data-content=\"waitlist\""));
}

#[tokio::test]
async fn test_update_page_shows_enabled_waitlist_tab_without_search() {
    // Setup identifiers and a waitlist event without approval
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_full = EventFull {
        waitlist_enabled: true,
        ..sample_event_full(ids.community_id, event_id, ids.group_id)
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);
    expect_update_page_reads(
        &mut db,
        &ids,
        event_full,
        EventCohostsEditor::default(),
        None,
    );
    expect_invitation_requests_tab_search(&mut db, &ids, event_id, 0);
    db.expect_search_event_waitlist().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let request = update_page_request(&ids, event_id);
    let (parts, bytes) = send(router, request).await;

    // Check only the enabled enrollment tab is shown
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(!body.contains("<option value=\"invitation-requests\""));
    assert!(!body.contains("data-section=\"invitation-requests\""));
    assert!(!body.contains("data-content=\"invitation-requests\""));
    assert!(body.contains("<option value=\"waitlist\""));
    assert!(body.contains("data-section=\"waitlist\""));
    assert!(body.contains("data-content=\"waitlist\""));
}

#[tokio::test]
async fn test_update_page_shows_enrollment_tabs_while_rows_remain() {
    // Setup identifiers and an event with both enrollment features disabled
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_full = sample_event_full(ids.community_id, event_id, ids.group_id);

    // Setup database mock with remaining enrollment rows
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);
    expect_update_page_reads(
        &mut db,
        &ids,
        event_full,
        EventCohostsEditor::default(),
        None,
    );
    expect_invitation_requests_tab_search(&mut db, &ids, event_id, 1);
    expect_waitlist_tab_search(&mut db, &ids, event_id, 1);

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let request = update_page_request(&ids, event_id);
    let (parts, bytes) = send(router, request).await;

    // Check both enrollment tabs stay visible
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("<option value=\"invitation-requests\""));
    assert!(body.contains("data-section=\"invitation-requests\""));
    assert!(body.contains("data-content=\"invitation-requests\""));

    // Check the requests tab opens with every status when no request can be pending
    assert!(body.contains(&format!(
        "hx-get=\"/dashboard/group/events/{event_id}/invitation-requests?status=all\""
    )));
    assert!(body.contains("<option value=\"waitlist\""));
    assert!(body.contains("data-section=\"waitlist\""));
    assert!(body.contains("data-content=\"waitlist\""));
}

#[tokio::test]
async fn test_update_page_success() {
    // Setup identifiers and an event with both enrollment features disabled
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut event_full = sample_event_full(ids.community_id, event_id, ids.group_id);
    event_full.custom_logo_url = Some("https://example.test/event-logo.png".to_string());
    event_full.logo_url = "https://example.test/event-logo.png".to_string();
    event_full.payment_currency_code = Some("USD".to_string());
    let organizers = event_full.organizers.clone();

    // Setup database mock without enrollment rows
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);
    expect_update_page_reads(
        &mut db,
        &ids,
        event_full,
        EventCohostsEditor::default(),
        None,
    );
    expect_invitation_requests_tab_search(&mut db, &ids, event_id, 0);
    expect_waitlist_tab_search(&mut db, &ids, event_id, 0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let request = update_page_request(&ids, event_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert_image_field_value(&body, "logo_url", "https://example.test/event-logo.png");
    assert!(body.contains(">Tickets</"));
    assert!(body.contains("free-only"));

    // Check the tabs are grouped by lifecycle in the Next button order
    assert!(appear_in_order(
        &body,
        &[
            "<optgroup label=\"EVENT\">",
            "<optgroup label=\"REGISTRATION\">",
            "<optgroup label=\"PROGRAM\">",
            "<optgroup label=\"PEOPLE\">",
            "<optgroup label=\"FOLLOW-UP\">",
        ],
    ));
    assert!(appear_in_order(
        &body,
        &[
            "data-section=\"details\"",
            "data-section=\"date-venue\"",
            "data-section=\"cohosts\"",
            "data-section=\"contributors\"",
            "data-section=\"payments\"",
            "data-section=\"questions\"",
            "data-section=\"labels\"",
            "data-section=\"cfs\"",
            "data-section=\"submissions\"",
            "data-section=\"sessions\"",
            "data-section=\"attendees\"",
            "data-section=\"surveys\"",
            "data-section=\"analytics\"",
        ],
    ));

    // Check the surveys tab lazy-loads its content outside the event forms
    assert!(body.contains("<option value=\"surveys\""));
    assert!(body.contains("data-content=\"surveys\""));
    assert!(body.contains(&format!(
        "hx-get=\"/dashboard/group/events/{event_id}/surveys\" hx-trigger=\"click once\""
    )));

    // Check disabled enrollment tabs without rows are hidden
    assert!(!body.contains("<option value=\"invitation-requests\""));
    assert!(!body.contains("data-section=\"invitation-requests\""));
    assert!(!body.contains("data-content=\"invitation-requests\""));
    assert!(!body.contains("<option value=\"waitlist\""));
    assert!(!body.contains("data-section=\"waitlist\""));
    assert!(!body.contains("data-content=\"waitlist\""));

    // Check the stored organizers render with team search and award wiring for managers
    let organizers_attribute = users_attribute(&organizers);
    let team_attribute = users_attribute(&sample_team_members());
    assert!(body.contains("<form id=\"contributors-form\" data-event-form>"));
    let organizers_selector = selector_tag(&body, "id=\"event-organizers-selector\"");
    assert!(organizers_selector.contains(&format!("selected-users=\"{organizers_attribute}\"")));
    assert!(organizers_selector.contains(&format!("available-users=\"{team_attribute}\"")));
    assert!(organizers_selector.contains("can-award-badges"));
    assert!(organizers_selector.contains("award-button-id=\"event-organizers-award-button\""));
    assert!(body.contains("<button id=\"event-organizers-award-button\""));
    assert!(body.contains("<input type=\"hidden\" name=\"organizers_present\" value=\"true\">"));

    // Check the contributor sections follow the public page order
    assert!(appear_in_order(
        &body,
        &[
            "id=\"event-speakers-selector\"",
            "id=\"event-hosts-selector\"",
            "id=\"event-organizers-selector\"",
            "<sponsors-section",
        ],
    ));
}

#[tokio::test]
async fn test_update_page_waits_for_pending_cohosts_before_publishing() {
    // Setup identifiers and an unpublished event with one pending co-host
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut event_full = sample_event_full(ids.community_id, event_id, ids.group_id);
    event_full.published = false;
    let cohosts = EventCohostsEditor {
        cohosts: vec![EventCohostInvitation {
            community_display_name: "Other Community".to_string(),
            community_name: "other".to_string(),
            group_active: true,
            group_id: Uuid::new_v4(),
            invitation_id: Uuid::new_v4(),
            invited_at: chrono::Utc::now(),
            logo_url: "https://example.test/logo.png".to_string(),
            name: "Co-host Group".to_string(),
            slug: "cohost-group".to_string(),
            status: EventCohostStatus::Pending,

            slug_pretty: None,
        }],
        revision: 4,
    };

    // Setup database mock with the pending co-host
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);
    expect_update_page_reads(&mut db, &ids, event_full, cohosts, None);
    expect_invitation_requests_tab_search(&mut db, &ids, event_id, 0);
    expect_waitlist_tab_search(&mut db, &ids, event_id, 0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let request = update_page_request(&ids, event_id);
    let (parts, bytes) = send(router, request).await;

    // Check the co-hosts tab and the disabled publish action
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("cohosts-selector"));
    assert!(body.contains("Co-host Group"));
    assert!(body.contains("revision=\"4\""));
    assert!(body.contains("Waiting for 1 co-host(s) to respond."));
}

#[tokio::test]
async fn test_automatic_tax_readiness_reports_cache() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup events manager mock with a cached provider location
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_check_automatic_tax_readiness()
        .times(1)
        .withf(move |community_id, group_id, eid| {
            *community_id == ids.community_id && *group_id == ids.group_id && *eid == event_id
        })
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

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = automatic_tax_readiness_request(&ids, event_id);
    let (parts, bytes) = send(router, request).await;
    let payload: Value = from_slice(&bytes).unwrap();

    // Check the ready payload
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        payload,
        json!({"status": "ready", "state_code": "MA", "cached": true})
    );
}

#[tokio::test]
async fn test_automatic_tax_readiness_returns_bad_gateway_for_provider_failure() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup events manager mock whose provider check fails unexpectedly
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_check_automatic_tax_readiness()
        .times(1)
        .returning(|_, _, _| {
            Box::pin(async {
                Err(AutomaticTaxReadinessError::Unexpected(anyhow!("provider unavailable")).into())
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = automatic_tax_readiness_request(&ids, Uuid::new_v4());
    let (parts, bytes) = send(router, request).await;
    let payload: Value = from_slice(&bytes).unwrap();

    // Check the not-ready payload hides the provider detail
    assert_eq!(parts.status, StatusCode::BAD_GATEWAY);
    assert_eq!(payload["status"], "not_ready");
    assert_eq!(payload["code"], "provider_unavailable");
}

#[tokio::test]
async fn test_automatic_tax_readiness_returns_internal_error_for_context_failure() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup events manager mock whose context load fails
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

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = automatic_tax_readiness_request(&ids, Uuid::new_v4());
    let (parts, bytes) = send(router, request).await;

    // Check the failure is not reported as a provider outage
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_automatic_tax_readiness_returns_structured_state_error() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup events manager mock with a correctable failure
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

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = automatic_tax_readiness_request(&ids, Uuid::new_v4());
    let (parts, bytes) = send(router, request).await;
    let payload: Value = from_slice(&bytes).unwrap();

    // Check the exact organizer-correctable response contract
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(payload["status"], "not_ready");
    assert_eq!(payload["code"], "state_code_required");
    assert_eq!(payload["fields"], json!(["venue_state_code"]));
}

#[tokio::test]
async fn test_details_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_full = EventFull {
        custom_logo_url: Some("https://example.test/event-logo.png".to_string()),
        ..sample_event_full(ids.community_id, event_id, ids.group_id)
    };
    let event_full_db = event_full.clone();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    db.expect_get_event_full()
        .times(1)
        .withf(move |community_id, group_id, eid| {
            *community_id == ids.community_id && *group_id == ids.group_id && *eid == event_id
        })
        .returning(move |_, _, _| Ok(event_full_db.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/details"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
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
async fn test_preview_renders_named_organizers_after_hosts() {
    // Setup identifiers and a preview with contributors for every role
    let ids = DashboardIds::new();
    let preview_context = json!({
        "hosts": [{"name": "Host Name", "username": "host"}],
        "organizers": [
            {"name": "Organizer Name", "username": "organizer"},
            {"username": "organizer-without-name"}
        ],
        "speakers": [{"name": "Speaker Name", "username": "speaker"}]
    });
    let body =
        serde_urlencoded::to_string([("preview_context", preview_context.to_string())]).unwrap();

    // Setup database mock for session and permission middleware only
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "POST",
        "/dashboard/group/events/preview",
        ids.session_id,
        body,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the people sections follow the public page order
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(appear_in_order(
        &body,
        &[
            "data-preview-name=\"Speaker Name\"",
            "Hosts",
            "data-preview-name=\"Host Name\"",
            "Organizers",
            "data-preview-name=\"Organizer Name\"",
        ],
    ));

    // Check organizers without a full name are left out
    assert!(!body.contains("organizer-without-name"));
}

#[tokio::test]
async fn test_preview_uses_submitted_payload_without_event_db_calls() {
    // Setup identifiers and database mock for session and permission middleware only
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
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
    let request = form_request(
        "POST",
        "/dashboard/group/events/preview",
        ids.session_id,
        body,
    );
    let (parts, bytes) = send(router, request).await;
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
    assert!(!body.contains("Only approved co-hosts are shown on the public page."));
}

#[tokio::test]
async fn test_search_rejects_invalid_filters() {
    // Setup identifiers and database mock (search must not be reached)
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    db.expect_get_group_summary().never();
    db.expect_search_events().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        "/dashboard/group/events/search?date_from=not-a-date",
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the request is rejected before searching
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), INVALID_REQUEST_PAYLOAD.as_bytes());
}

#[tokio::test]
async fn test_search_scopes_events_to_selected_group() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let group = sample_group_summary(ids.group_id);

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    db.expect_get_group_summary()
        .times(1)
        .withf(move |community_id, group_id| {
            *community_id == ids.community_id && *group_id == ids.group_id
        })
        .returning(move |_, _| Ok(group.clone()));
    db.expect_search_events()
        .times(1)
        .withf(|filters| {
            filters.community == vec!["test-community".to_string()]
                && filters.group == vec!["npq6789".to_string()]
                && filters.date_from.is_some()
                && filters.latitude.is_none()
                && filters.limit == Some(5)
                && filters.longitude.is_none()
                && filters.sort_direction.as_deref() == Some("desc")
                && filters.ts_query.as_deref() == Some("kubernetes")
        })
        .returning(move |_| Ok(sample_search_events_output(event_id)));

    // Setup router and send request with filters for another group and location
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        "/dashboard/group/events/search?community[0]=other-community&group[0]=other-group\
         &latitude=51.5&limit=5&longitude=-0.12&sort_direction=desc&ts_query=kubernetes",
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let payload: Value = from_slice(&bytes).unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("application/json"),
    );
    assert_eq!(payload["events"][0]["event_id"], event_id.to_string());
    assert_eq!(payload["total"], 1);
}

#[tokio::test]
async fn test_add_returns_created_with_editor_location() {
    // Setup identifiers and the submitted form
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_form = sample_event_form();
    let body = serde_qs::to_string(&event_form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_add()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == ids.user_id
                && input.community_id == ids.community_id
                && input.group_id == ids.group_id
                && input.event.name == event_form.name
        })
        .returning(move |_| Box::pin(async move { Ok(vec![event_id, Uuid::new_v4()]) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = form_request("POST", "/dashboard/group/events/add", ids.session_id, body);
    let (parts, bytes) = send(router, request).await;

    // Check the editor reloads the base event
    assert_event_editor_location_response(&parts, &bytes, StatusCode::CREATED, event_id);
}

#[tokio::test]
async fn test_add_returns_unprocessable_entity_for_rejection() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let body = serde_qs::to_string(&sample_event_form()).unwrap();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

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
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = form_request("POST", "/dashboard/group/events/add", ids.session_id, body);
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "configure a fiscal sponsor before selecting Stripe Tax Rates"
    );
}

#[tokio::test]
async fn test_add_validation_rejects_invalid_ticketing_fields() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let body = format!(
        concat!(
            "{}",
            "&ticket_types_present=true",
            "&ticket_types[0][active]=true",
            "&ticket_types[0][order]=1",
            "&ticket_types[0][title]=General%20admission",
            "&ticket_types[0][price_windows][0][amount_minor]=invalid",
        ),
        serde_qs::to_string(&sample_event_form()).unwrap(),
    );

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request("POST", "/dashboard/group/events/add", ids.session_id, body);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), INVALID_REQUEST_PAYLOAD.as_bytes());
}

#[tokio::test]
async fn test_update_validation_rejects_invalid_discount_codes() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
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
        serde_qs::to_string(&sample_event_form()).unwrap(),
    );

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/group/events/{event_id}/update"),
        ids.session_id,
        body,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), INVALID_REQUEST_PAYLOAD.as_bytes());
}

#[tokio::test]
async fn test_cancel_series_returns_no_content_with_table_refresh() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_cancel()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == ids.user_id
                && input.community_id == ids.community_id
                && input.event_id == event_id
                && input.group_id == ids.group_id
                && input.scope == EventActionScope::Series
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = event_action_request(&ids, "PUT", event_id, "cancel?scope=series");
    let (parts, bytes) = send(router, request).await;

    // Check the table refresh trigger
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_cancel_returns_unprocessable_entity_for_rejection() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup events manager mock, checking the default scope
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_cancel()
        .times(1)
        .withf(|input| input.scope == EventActionScope::This)
        .returning(|_| {
            Box::pin(async {
                Err(EventsError::Rejected(
                    "event is already canceled".to_string(),
                ))
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = event_action_request(&ids, "PUT", Uuid::new_v4(), "cancel");
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "event is already canceled"
    );
}

#[tokio::test]
async fn test_delete_returns_no_content_with_table_refresh() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_delete()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == ids.user_id
                && input.community_id == ids.community_id
                && input.event_id == event_id
                && input.group_id == ids.group_id
                && input.scope == EventActionScope::This
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = event_action_request(&ids, "DELETE", event_id, "delete");
    let (parts, bytes) = send(router, request).await;

    // Check the table refresh trigger
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_delete_returns_unprocessable_entity_for_rejection() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager.expect_delete().times(1).returning(|_| {
        Box::pin(async { Err(EventsError::Rejected("event not found".to_string())) })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = event_action_request(&ids, "DELETE", Uuid::new_v4(), "delete");
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "event not found"
    );
}

#[tokio::test]
async fn test_publish_return_editor_with_series_scope_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_publish()
        .times(1)
        .withf(move |input| input.event_id == event_id && input.scope == EventActionScope::Series)
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = event_action_request(&ids, "PUT", event_id, "publish?scope=series&return=editor");
    let (parts, bytes) = send(router, request).await;

    // Check the editor reload
    assert_event_editor_location_response(&parts, &bytes, StatusCode::NO_CONTENT, event_id);
}

#[tokio::test]
async fn test_publish_return_unknown_keeps_table_refresh() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup events manager mock, checking the default scope
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_publish()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == ids.user_id
                && input.community_id == ids.community_id
                && input.event_id == event_id
                && input.group_id == ids.group_id
                && input.scope == EventActionScope::This
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = event_action_request(&ids, "PUT", event_id, "publish?return=elsewhere");
    let (parts, bytes) = send(router, request).await;

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
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

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
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = event_action_request(&ids, "PUT", Uuid::new_v4(), "publish");
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "configure a fiscal sponsor before publishing this automatic-tax event"
    );
}

#[tokio::test]
async fn test_tax_rates_returns_rates() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);

    // Setup events manager mock with the provider rates
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_list_tax_rates()
        .times(1)
        .withf(move |community_id, group_id, tax_behavior| {
            *community_id == ids.community_id
                && *group_id == ids.group_id
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
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = get_request(
        "/dashboard/group/events/tax-rates?tax_behavior=inclusive",
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let payload: Value = from_slice(&bytes).unwrap();

    // Check the rates payload
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(payload[0]["id"], json!("txr_vat"));
}

#[tokio::test]
async fn test_tax_rates_returns_unprocessable_entity_for_rejection() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);

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
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = get_request(
        "/dashboard/group/events/tax-rates?tax_behavior=exclusive",
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "configure a fiscal sponsor before selecting Stripe Tax Rates"
    );
}

#[tokio::test]
async fn test_unpublish_series_returns_no_content_with_table_refresh() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_unpublish()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == ids.user_id
                && input.community_id == ids.community_id
                && input.event_id == event_id
                && input.group_id == ids.group_id
                && input.scope == EventActionScope::Series
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = event_action_request(&ids, "PUT", event_id, "unpublish?scope=series");
    let (parts, bytes) = send(router, request).await;

    // Check the table refresh trigger
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_unpublish_returns_unprocessable_entity_for_rejection() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager.expect_unpublish().times(1).returning(|_| {
        Box::pin(async { Err(EventsError::Rejected("event is not published".to_string())) })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = event_action_request(&ids, "PUT", Uuid::new_v4(), "unpublish");
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "event is not published"
    );
}

#[tokio::test]
async fn test_update_returns_no_content_with_editor_location() {
    // Setup identifiers and the submitted form
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event_form = sample_event_form();
    let body = serde_qs::to_string(&event_form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_update()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == ids.user_id
                && input.community_id == ids.community_id
                && input.event_id == event_id
                && input.group_id == ids.group_id
                && input.event.name == event_form.name
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/group/events/{event_id}/update"),
        ids.session_id,
        body,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the editor reload
    assert_event_editor_location_response(&parts, &bytes, StatusCode::NO_CONTENT, event_id);
}

#[tokio::test]
async fn test_update_returns_unprocessable_entity_for_rejection() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let body = serde_qs::to_string(&sample_event_form()).unwrap();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager.expect_update().times(1).returning(|_| {
        Box::pin(async {
            Err(EventsError::Rejected(
                "configure a fiscal sponsor before updating this published event".to_string(),
            ))
        })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/group/events/{}/update", Uuid::new_v4()),
        ids.session_id,
        body,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "configure a fiscal sponsor before updating this published event"
    );
}

// Helpers.

/// Returns true when every needle appears in the body after the previous one.
fn appear_in_order(body: &str, needles: &[&str]) -> bool {
    let mut offset = 0;
    for needle in needles {
        let Some(index) = body[offset..].find(needle) else {
            return false;
        };
        offset += index + needle.len();
    }
    true
}

/// Asserts an empty event-editor HTMX location response without a table refresh.
fn assert_event_editor_location_response(
    parts: &Parts,
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

/// Builds the saved-event automatic-tax readiness request.
fn automatic_tax_readiness_request(ids: &DashboardIds, event_id: Uuid) -> Request<Body> {
    empty_request(
        "POST",
        &format!("/dashboard/group/events/{event_id}/automatic-tax/readiness"),
        ids.session_id,
    )
}

/// Builds an event action request; `action` may carry a query string.
fn event_action_request(
    ids: &DashboardIds,
    method: &str,
    event_id: Uuid,
    action: &str,
) -> Request<Body> {
    empty_request(
        method,
        &format!("/dashboard/group/events/{event_id}/{action}"),
        ids.session_id,
    )
}

/// Registers the editor option reads shared by the add and update pages.
fn expect_event_editor_option_reads(
    db: &mut MockDB,
    ids: &DashboardIds,
    external_payments: GroupExternalPaymentsContext,
    organizers: Vec<User>,
    payment_recipient: Option<GroupPaymentRecipient>,
) {
    let DashboardIds {
        community_id,
        group_id,
        ..
    } = *ids;
    db.expect_list_event_categories()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(|_| Ok(vec![sample_event_category()]));
    db.expect_list_communities()
        .times(1)
        .returning(move || Ok(sample_user_communities(community_id)));
    db.expect_list_event_kinds()
        .times(1)
        .returning(|| Ok(vec![sample_event_kind_summary()]));
    db.expect_list_payment_currency_codes()
        .times(1)
        .returning(|| Ok(vec!["EUR".to_string(), "USD".to_string()]));
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(move |_, _| Ok(payment_recipient.clone()));
    db.expect_list_session_kinds()
        .times(1)
        .returning(|| Ok(vec![sample_session_kind_summary()]));
    db.expect_list_group_sponsors()
        .times(1)
        .withf(move |gid, filters, full_list| {
            *gid == group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && *full_list
        })
        .returning(|_, _, _| {
            Ok(GroupSponsorsOutput {
                sponsors: vec![sample_group_sponsor()],
                total: 1,
            })
        });
    db.expect_list_timezones()
        .times(1)
        .returning(|| Ok(vec!["UTC".to_string()]));
    db.expect_get_group_external_payments_context()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(move |_, _| Ok(external_payments.clone()));
    db.expect_list_group_organizers()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(organizers.clone()));
}

/// Registers the invitation requests lookup used to decide the tab visibility.
fn expect_invitation_requests_tab_search(
    db: &mut MockDB,
    ids: &DashboardIds,
    event_id: Uuid,
    total: usize,
) {
    let group_id = ids.group_id;
    db.expect_search_event_invitation_requests()
        .times(1)
        .withf(move |gid, eid, filters| {
            *gid == group_id
                && *eid == event_id
                && filters.status == InvitationRequestsStatusFilter::All
                && filters.limit == Some(1)
                && filters.offset == Some(0)
                && filters.ts_query.is_none()
        })
        .returning(move |_, _, _| {
            Ok(InvitationRequestsOutput {
                invitation_requests: vec![],
                total,
            })
        });
}

/// Registers the event and editor option reads every update page performs.
fn expect_update_page_reads(
    db: &mut MockDB,
    ids: &DashboardIds,
    event_full: EventFull,
    cohosts: EventCohostsEditor,
    payment_recipient: Option<GroupPaymentRecipient>,
) {
    let DashboardIds {
        community_id,
        group_id,
        ..
    } = *ids;
    let event_id = event_full.event_id;
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full.clone()));
    db.expect_list_event_approved_cfs_submissions()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .returning(|_, _| Ok(vec![]));
    db.expect_list_cfs_submission_statuses_for_review()
        .times(1)
        .returning(|| Ok(vec![]));
    db.expect_list_event_cohosts()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .returning(move |_, _| Ok(cohosts.clone()));
    expect_event_editor_option_reads(
        db,
        ids,
        GroupExternalPaymentsContext::default(),
        sample_team_members(),
        payment_recipient,
    );
}

/// Registers the waitlist lookup used to decide the tab visibility.
fn expect_waitlist_tab_search(db: &mut MockDB, ids: &DashboardIds, event_id: Uuid, total: usize) {
    let group_id = ids.group_id;
    db.expect_search_event_waitlist()
        .times(1)
        .withf(move |gid, eid, filters| {
            *gid == group_id
                && *eid == event_id
                && filters.limit == Some(1)
                && filters.offset == Some(0)
                && filters.ts_query.is_none()
        })
        .returning(move |_, _, _| {
            Ok(WaitlistOutput {
                total,
                waitlist: vec![],
            })
        });
}

/// Returns the group team members listed as available organizers.
fn sample_team_members() -> Vec<User> {
    vec![User {
        user_id: Uuid::from_u128(0x7ea0),
        username: "team-organizer".to_string(),

        name: Some("Team Organizer".to_string()),
        ..Default::default()
    }]
}

/// Returns the opening tag that contains the given attribute.
fn selector_tag<'a>(body: &'a str, attribute: &str) -> &'a str {
    let attribute_index = body.find(attribute).expect("attribute should be rendered");
    let start = body[..attribute_index].rfind('<').expect("tag start should exist");
    let end = attribute_index + body[attribute_index..].find('>').expect("tag end should exist");
    &body[start..=end]
}

/// Builds the event editor page request.
fn update_page_request(ids: &DashboardIds, event_id: Uuid) -> Request<Body> {
    get_request(
        &format!("/dashboard/group/events/{event_id}/update"),
        ids.session_id,
    )
}

/// Returns the users JSON as Askama renders it in a double-quoted attribute.
fn users_attribute(users: &[User]) -> String {
    serde_json::to_string(users).unwrap().replace('"', "&#34;")
}
