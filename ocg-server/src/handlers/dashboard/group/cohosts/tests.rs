use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use chrono::Utc;
use serde_json::{from_slice, json};
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::{error::INVALID_REQUEST_PAYLOAD, tests::*},
    services::events::{EventsError, MockEventsManager},
    types::{
        dashboard::{
            DASHBOARD_PAGINATION_LIMIT,
            group::cohosts::{CohostedEvent, CohostedEventsOutput},
        },
        event::{EventCohostGroup, EventCohostStatus, EventKind},
        permissions::GroupPermission,
    },
};

#[tokio::test]
async fn test_approve_passes_invitation_and_selected_group_to_manager() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let invitation_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SettingsWrite);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_approve_cohosting()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == ids.user_id
                && input.cohost_group_id == ids.group_id
                && input.invitation_id == invitation_id
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = action_request(&ids, invitation_id, "approve");
    let (parts, bytes) = send(router, request).await;

    // Check the list refresh response
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-cohosts",
    );
}

#[tokio::test]
async fn test_approve_returns_rejected_message() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SettingsWrite);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager.expect_approve_cohosting().times(1).returning(|_| {
        Box::pin(async { Err(EventsError::Rejected("co-hosting unavailable".to_string())) })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = action_request(&ids, Uuid::new_v4(), "approve");
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "co-hosting unavailable"
    );
}

#[tokio::test]
async fn test_cancel_passes_invitation_and_selected_group_to_manager() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let invitation_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SettingsWrite);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_cancel_cohosting()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == ids.user_id
                && input.cohost_group_id == ids.group_id
                && input.invitation_id == invitation_id
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = action_request(&ids, invitation_id, "cancel");
    let (parts, bytes) = send(router, request).await;

    // Check the list refresh response
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-cohosts",
    );
}

#[tokio::test]
async fn test_cancel_returns_rejected_message() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SettingsWrite);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager.expect_cancel_cohosting().times(1).returning(|_| {
        Box::pin(async {
            Err(EventsError::Rejected(
                "co-hosting is not approved".to_string(),
            ))
        })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = action_request(&ids, Uuid::new_v4(), "cancel");
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "co-hosting is not approved"
    );
}

#[tokio::test]
async fn test_group_options_rejects_invalid_community_id() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);
    db.expect_list_cohost_group_options().never();

    // Setup router and send request with a malformed community identifier
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        "/dashboard/group/events/cohosts/groups?community_id=invalid",
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the malformed query is rejected
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), INVALID_REQUEST_PAYLOAD.as_bytes());
}

#[tokio::test]
async fn test_group_options_returns_community_groups_excluding_selected_group() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let other_community_id = Uuid::new_v4();
    let other_group_id = Uuid::new_v4();
    let option = EventCohostGroup {
        community_display_name: "Other Community".to_string(),
        community_name: "other".to_string(),
        group_id: other_group_id,
        logo_url: "https://example.test/logo.png".to_string(),
        name: "Other Group".to_string(),
        slug: "abc1234".to_string(),

        slug_pretty: None,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);
    db.expect_list_cohost_group_options()
        .times(1)
        .withf(move |community_id, exclude_group_id| {
            *community_id == other_community_id && *exclude_group_id == ids.group_id
        })
        .returning(move |_, _| Ok(vec![option.clone()]));

    // Setup router and send request for another community
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/cohosts/groups?community_id={other_community_id}"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let payload: serde_json::Value = from_slice(&bytes).unwrap();

    // Check the JSON options
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        payload,
        json!([{
            "community_display_name": "Other Community",
            "community_name": "other",
            "group_id": other_group_id,
            "logo_url": "https://example.test/logo.png",
            "name": "Other Group",
            "slug": "abc1234",
        }])
    );
}

#[tokio::test]
async fn test_list_page_hides_actions_without_settings_write() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::SettingsWrite, false);
    expect_list_cohosted_events(&mut db, &ids, sample_cohosted_events_output());

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group/cohosts", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the invitation renders without response actions
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url").unwrap(),
        "/dashboard/group?tab=cohosts&limit=50&offset=0"
    );
    assert!(html.contains("Cloud Native Meetup"));
    assert!(!html.contains("hx-put=\"/dashboard/group/cohosts/"));
}

#[tokio::test]
async fn test_list_page_renders_actions_with_settings_write() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let output = sample_cohosted_events_output();
    let invitation_id = output.events[0].invitation_id;

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::SettingsWrite, true);
    expect_list_cohosted_events(&mut db, &ids, output);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group/cohosts", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the pending invitation renders its approve and reject actions
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(html.contains("Cloud Native Meetup"));
    assert!(html.contains(&format!(
        "hx-put=\"/dashboard/group/cohosts/{invitation_id}/approve\""
    )));
    assert!(html.contains(&format!(
        "hx-put=\"/dashboard/group/cohosts/{invitation_id}/reject\""
    )));
    assert!(!html.contains(&format!(
        "hx-put=\"/dashboard/group/cohosts/{invitation_id}/cancel\""
    )));
}

#[tokio::test]
async fn test_reject_passes_invitation_and_selected_group_to_manager() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let invitation_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SettingsWrite);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_reject_cohosting()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == ids.user_id
                && input.cohost_group_id == ids.group_id
                && input.invitation_id == invitation_id
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = action_request(&ids, invitation_id, "reject");
    let (parts, bytes) = send(router, request).await;

    // Check the list refresh response
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-cohosts",
    );
}

#[tokio::test]
async fn test_reject_returns_rejected_message() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SettingsWrite);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager.expect_reject_cohosting().times(1).returning(|_| {
        Box::pin(async {
            Err(EventsError::Rejected(
                "co-hosting invitation not found".to_string(),
            ))
        })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = action_request(&ids, Uuid::new_v4(), "reject");
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "co-hosting invitation not found"
    );
}

// Helpers.

/// Builds the request for a co-hosting action on an invitation.
fn action_request(ids: &DashboardIds, invitation_id: Uuid, action: &str) -> Request<Body> {
    empty_request(
        "PUT",
        &format!("/dashboard/group/cohosts/{invitation_id}/{action}"),
        ids.session_id,
    )
}

/// Registers the co-hosted events read for the first list page.
fn expect_list_cohosted_events(db: &mut MockDB, ids: &DashboardIds, output: CohostedEventsOutput) {
    let group_id = ids.group_id;
    db.expect_list_group_cohosted_events()
        .times(1)
        .withf(move |gid, filters| {
            *gid == group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(output.clone()));
}

/// Returns one pending invitation to co-host an unpublished event.
fn sample_cohosted_events_output() -> CohostedEventsOutput {
    CohostedEventsOutput {
        events: vec![CohostedEvent {
            canceled: false,
            event_id: Uuid::new_v4(),
            event_kind: EventKind::InPerson,
            event_logo_url: "https://example.test/event.png".to_string(),
            event_name: "Cloud Native Meetup".to_string(),
            event_slug: "cloud-native-meetup".to_string(),
            invitation_id: Uuid::new_v4(),
            invited_at: Utc::now(),
            owner_community_display_name: "Owner Community".to_string(),
            owner_community_name: "owner".to_string(),
            owner_group_logo_url: "https://example.test/group.png".to_string(),
            owner_group_name: "Owner Group".to_string(),
            owner_group_slug: "owner-group".to_string(),
            published: false,
            status: EventCohostStatus::Pending,
            timezone: chrono_tz::UTC,

            ends_at: None,
            owner_group_slug_pretty: None,
            responded_at: None,
            starts_at: Some(Utc::now()),
        }],
        total: 1,
    }
}
