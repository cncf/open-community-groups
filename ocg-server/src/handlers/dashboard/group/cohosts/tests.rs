use anyhow::anyhow;
use axum::{
    body::{Body, to_bytes},
    http::{Request, StatusCode, header::COOKIE},
};
use axum_login::tower_sessions::session;
use chrono::Utc;
use serde_json::{from_slice, json};
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::{error::HandlerError, tests::*},
    services::{
        events::{EventsError, MockEventsManager},
        notifications::MockNotificationsManager,
    },
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
    // Setup identifiers and the approval
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let invitation_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let db = settings_write_db(session_id, user_id, community_id, group_id);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_approve_cohosting()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == user_id
                && input.cohost_group_id == group_id
                && input.invitation_id == invitation_id
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Send the approval request
    let (parts, bytes) = send_action(
        db,
        events_manager,
        session_id,
        &format!("/dashboard/group/cohosts/{invitation_id}/approve"),
    )
    .await;

    // Check the list refresh response
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-cohosts",
    );
}

#[tokio::test]
async fn test_approve_returns_database_rejection_message() {
    // Setup identifiers and a database rejection
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let db = settings_write_db(session_id, user_id, community_id, group_id);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager.expect_approve_cohosting().times(1).returning(|_| {
        Box::pin(async {
            Err(EventsError::Other(
                HandlerError::Database("co-hosting invitation is no longer pending".to_string())
                    .into(),
            ))
        })
    });

    // Send the approval request
    let (parts, bytes) = send_action(
        db,
        events_manager,
        session_id,
        &format!("/dashboard/group/cohosts/{}/approve", Uuid::new_v4()),
    )
    .await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "co-hosting invitation is no longer pending"
    );
}

#[tokio::test]
async fn test_approve_returns_internal_error_without_body() {
    // Setup identifiers and an internal failure
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let db = settings_write_db(session_id, user_id, community_id, group_id);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_approve_cohosting()
        .times(1)
        .returning(|_| Box::pin(async { Err(EventsError::Other(anyhow!("db error"))) }));

    // Send the approval request
    let (parts, bytes) = send_action(
        db,
        events_manager,
        session_id,
        &format!("/dashboard/group/cohosts/{}/approve", Uuid::new_v4()),
    )
    .await;

    // Check the internal error hides the detail
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_approve_returns_rejected_message() {
    // Setup identifiers and a manager rejection
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let db = settings_write_db(session_id, user_id, community_id, group_id);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager.expect_approve_cohosting().times(1).returning(|_| {
        Box::pin(async { Err(EventsError::Rejected("co-hosting unavailable".to_string())) })
    });

    // Send the approval request
    let (parts, bytes) = send_action(
        db,
        events_manager,
        session_id,
        &format!("/dashboard/group/cohosts/{}/approve", Uuid::new_v4()),
    )
    .await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "co-hosting unavailable"
    );
}

#[tokio::test]
async fn test_cancel_passes_invitation_and_selected_group_to_manager() {
    // Setup identifiers and the withdrawal
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let invitation_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let db = settings_write_db(session_id, user_id, community_id, group_id);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_cancel_cohosting()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == user_id
                && input.cohost_group_id == group_id
                && input.invitation_id == invitation_id
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Send the withdrawal request
    let (parts, bytes) = send_action(
        db,
        events_manager,
        session_id,
        &format!("/dashboard/group/cohosts/{invitation_id}/cancel"),
    )
    .await;

    // Check the list refresh response
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-cohosts",
    );
}

#[tokio::test]
async fn test_cancel_returns_database_rejection_message() {
    // Setup identifiers and a database rejection
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let db = settings_write_db(session_id, user_id, community_id, group_id);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager.expect_cancel_cohosting().times(1).returning(|_| {
        Box::pin(async {
            Err(EventsError::Other(
                HandlerError::Database("co-hosting is not approved".to_string()).into(),
            ))
        })
    });

    // Send the withdrawal request
    let (parts, bytes) = send_action(
        db,
        events_manager,
        session_id,
        &format!("/dashboard/group/cohosts/{}/cancel", Uuid::new_v4()),
    )
    .await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "co-hosting is not approved"
    );
}

#[tokio::test]
async fn test_cancel_returns_internal_error_without_body() {
    // Setup identifiers and an internal failure
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let db = settings_write_db(session_id, user_id, community_id, group_id);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_cancel_cohosting()
        .times(1)
        .returning(|_| Box::pin(async { Err(EventsError::Other(anyhow!("db error"))) }));

    // Send the withdrawal request
    let (parts, bytes) = send_action(
        db,
        events_manager,
        session_id,
        &format!("/dashboard/group/cohosts/{}/cancel", Uuid::new_v4()),
    )
    .await;

    // Check the internal error hides the detail
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_cancel_returns_rejected_message() {
    // Setup identifiers and a manager rejection
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let db = settings_write_db(session_id, user_id, community_id, group_id);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager.expect_cancel_cohosting().times(1).returning(|_| {
        Box::pin(async { Err(EventsError::Rejected("co-hosting unavailable".to_string())) })
    });

    // Send the withdrawal request
    let (parts, bytes) = send_action(
        db,
        events_manager,
        session_id,
        &format!("/dashboard/group/cohosts/{}/cancel", Uuid::new_v4()),
    )
    .await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "co-hosting unavailable"
    );
}

#[tokio::test]
async fn test_group_options_rejects_invalid_community_id() {
    // Setup an events manager session
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );
    db.expect_list_cohost_group_options().never();

    // Request the options with a malformed community identifier
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group/events/cohosts/groups?community_id=invalid")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();

    // Check the malformed query is rejected
    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_group_options_returns_community_groups_excluding_selected_group() {
    // Setup identifiers and the lookup result
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let other_community_id = Uuid::new_v4();
    let other_group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
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
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );
    db.expect_list_cohost_group_options()
        .times(1)
        .withf(move |cid, exclude_group_id| {
            *cid == other_community_id && *exclude_group_id == group_id
        })
        .returning(move |_, _| Ok(vec![option.clone()]));

    // Request the options for another community
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!(
            "/dashboard/group/events/cohosts/groups?community_id={other_community_id}"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let payload: serde_json::Value =
        from_slice(&to_bytes(body, usize::MAX).await.unwrap()).unwrap();

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
    // Setup identifiers and a pending invitation
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let db = list_page_db(
        session_id,
        user_id,
        community_id,
        group_id,
        false,
        sample_cohosted_events_output(),
    );

    // Request the co-hosts partial
    let (parts, bytes) = send_list_page(db, session_id).await;
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the invitation renders without response actions
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url").unwrap(),
        "/dashboard/group?tab=cohosts&limit=50&offset=0"
    );
    assert!(html.contains("Cloud Native Meetup"));
    assert!(!html.contains("/approve"));
}

#[tokio::test]
async fn test_list_page_renders_actions_with_settings_write() {
    // Setup identifiers and a pending invitation
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let output = sample_cohosted_events_output();
    let invitation_id = output.events[0].invitation_id;
    let db = list_page_db(session_id, user_id, community_id, group_id, true, output);

    // Request the co-hosts partial
    let (parts, bytes) = send_list_page(db, session_id).await;
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the invitation renders with its response actions
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(html.contains("Cloud Native Meetup"));
    assert!(html.contains(&format!("{invitation_id}")));
}

#[tokio::test]
async fn test_reject_passes_invitation_and_selected_group_to_manager() {
    // Setup identifiers and the rejection
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let invitation_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let db = settings_write_db(session_id, user_id, community_id, group_id);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_reject_cohosting()
        .times(1)
        .withf(move |input| {
            input.actor_user_id == user_id
                && input.cohost_group_id == group_id
                && input.invitation_id == invitation_id
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Send the rejection request
    let (parts, bytes) = send_action(
        db,
        events_manager,
        session_id,
        &format!("/dashboard/group/cohosts/{invitation_id}/reject"),
    )
    .await;

    // Check the list refresh response
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-cohosts",
    );
}

#[tokio::test]
async fn test_reject_returns_database_rejection_message() {
    // Setup identifiers and a database rejection
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let db = settings_write_db(session_id, user_id, community_id, group_id);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager.expect_reject_cohosting().times(1).returning(|_| {
        Box::pin(async {
            Err(EventsError::Other(
                HandlerError::Database("co-hosting invitation not found".to_string()).into(),
            ))
        })
    });

    // Send the rejection request
    let (parts, bytes) = send_action(
        db,
        events_manager,
        session_id,
        &format!("/dashboard/group/cohosts/{}/reject", Uuid::new_v4()),
    )
    .await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "co-hosting invitation not found"
    );
}

#[tokio::test]
async fn test_reject_returns_internal_error_without_body() {
    // Setup identifiers and an internal failure
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let db = settings_write_db(session_id, user_id, community_id, group_id);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager
        .expect_reject_cohosting()
        .times(1)
        .returning(|_| Box::pin(async { Err(EventsError::Other(anyhow!("db error"))) }));

    // Send the rejection request
    let (parts, bytes) = send_action(
        db,
        events_manager,
        session_id,
        &format!("/dashboard/group/cohosts/{}/reject", Uuid::new_v4()),
    )
    .await;

    // Check the internal error hides the detail
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_reject_returns_rejected_message() {
    // Setup identifiers and a manager rejection
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let db = settings_write_db(session_id, user_id, community_id, group_id);

    // Setup events manager mock
    let mut events_manager = MockEventsManager::new();
    events_manager.expect_reject_cohosting().times(1).returning(|_| {
        Box::pin(async { Err(EventsError::Rejected("co-hosting unavailable".to_string())) })
    });

    // Send the rejection request
    let (parts, bytes) = send_action(
        db,
        events_manager,
        session_id,
        &format!("/dashboard/group/cohosts/{}/reject", Uuid::new_v4()),
    )
    .await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "co-hosting unavailable"
    );
}

// Helpers.

/// Builds a database mock for the co-hosts list page reads.
fn list_page_db(
    session_id: session::Id,
    user_id: Uuid,
    community_id: Uuid,
    group_id: Uuid,
    can_manage_cohosts: bool,
    output: CohostedEventsOutput,
) -> MockDB {
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::SettingsWrite
        })
        .returning(move |_, _, _, _| Ok(can_manage_cohosts));
    db.expect_list_group_cohosted_events()
        .times(1)
        .withf(move |gid, filters| {
            *gid == group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(output.clone()));

    db
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

/// Sends a co-hosting action request through the router.
async fn send_action(
    db: MockDB,
    events_manager: MockEventsManager,
    session_id: session::Id,
    uri: &str,
) -> (axum::http::response::Parts, axum::body::Bytes) {
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_events_manager(events_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("PUT")
        .uri(uri)
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    (parts, bytes)
}

/// Sends the co-hosts list page request through the router.
async fn send_list_page(
    db: MockDB,
    session_id: session::Id,
) -> (axum::http::response::Parts, axum::body::Bytes) {
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group/cohosts")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    (parts, bytes)
}

/// Builds a database mock for a user allowed to respond to co-hosting invitations.
fn settings_write_db(
    session_id: session::Id,
    user_id: Uuid,
    community_id: Uuid,
    group_id: Uuid,
) -> MockDB {
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::SettingsWrite,
    );

    db
}
