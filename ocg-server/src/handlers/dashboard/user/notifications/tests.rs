use std::collections::BTreeMap;

use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderValue, Request, StatusCode,
        header::{CONTENT_TYPE, COOKIE},
    },
};
use axum_login::tower_sessions::session;
use chrono::{TimeZone, Utc};
use serde_json::{Value, from_slice};
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::{error::HandlerError, tests::*},
    services::notifications::MockNotificationsManager,
    types::dashboard::user::notifications::{
        MutedGroup, NotificationCategory, NotificationGroupOption, NotificationPreferences,
    },
};

#[tokio::test]
async fn test_group_options_returns_json() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_list_user_notification_group_options()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| {
            Ok(vec![NotificationGroupOption {
                community_display_name: "Community".to_string(),
                group_id,
                name: "Group".to_string(),
                logo_url: None,
            }])
        });

    // Send the request
    let (parts, bytes) = send_request(
        db,
        session_id,
        "GET",
        "/dashboard/user/notifications/group-options",
        "",
    )
    .await;

    // Check the response contains the options as JSON
    assert_eq!(parts.status, StatusCode::OK);
    let options: Value = from_slice(&bytes).unwrap();
    assert_eq!(
        options,
        serde_json::json!([{
            "community_display_name": "Community",
            "group_id": group_id,
            "name": "Group",
            "logo_url": null,
        }])
    );
}

#[tokio::test]
async fn test_mute_group_rejects_unavailable_group() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock rejecting the mute
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_mute_user_group_notifications()
        .times(1)
        .withf(move |uid, gid| *uid == user_id && *gid == group_id)
        .returning(|_, _| {
            Err(HandlerError::Database("group not available to mute".to_string()).into())
        });

    // Send the request
    let (parts, bytes) = send_request(
        db,
        session_id,
        "PUT",
        &format!("/dashboard/user/notifications/muted-groups/{group_id}"),
        "",
    )
    .await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), b"group not available to mute");
}

#[tokio::test]
async fn test_mute_group_success() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_mute_user_group_notifications()
        .times(1)
        .withf(move |uid, gid| *uid == user_id && *gid == group_id)
        .returning(|_, _| Ok(()));

    // Send the request
    let (parts, bytes) = send_request(
        db,
        session_id,
        "PUT",
        &format!("/dashboard/user/notifications/muted-groups/{group_id}"),
        "",
    )
    .await;

    // Check the muted groups list is refreshed
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-muted-groups",
    );
}

#[tokio::test]
async fn test_muted_groups_renders_empty_state() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_user_notification_preferences()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(|_| Ok(NotificationPreferences::default()));

    // Send the request
    let (parts, bytes) = send_request(
        db,
        session_id,
        "GET",
        "/dashboard/user/notifications/muted-groups",
        "",
    )
    .await;

    // Check the empty state is rendered
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("You haven't muted any groups."));
}

#[tokio::test]
async fn test_muted_groups_renders_inner_content_only() {
    // Setup identifiers and data structures
    let available_group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let unavailable_group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let preferences = NotificationPreferences {
        muted_groups: vec![
            sample_muted_group(available_group_id, "Available Group", true),
            sample_muted_group(unavailable_group_id, "Retired Group", false),
        ],
        opted_out_categories: vec![],
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_user_notification_preferences()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(preferences.clone()));

    // Send the request
    let (parts, bytes) = send_request(
        db,
        session_id,
        "GET",
        "/dashboard/user/notifications/muted-groups",
        "",
    )
    .await;

    // Check the rows render without the refresh wrapper
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(!body.contains("id=\"muted-groups\""));
    assert!(body.contains("aria-label=\"Unmute Available Group\""));
    assert!(body.contains(&format!(
        "hx-delete=\"/dashboard/user/notifications/muted-groups/{available_group_id}\""
    )));
    assert!(body.contains("aria-label=\"Unmute Retired Group\""));
    assert_eq!(body.matches("No longer available").count(), 1);
}

#[tokio::test]
async fn test_page_renders_community_team_section() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock for a community team member
    let mut db = MockDB::new();
    expect_authenticated_session_with_teams(&mut db, session_id, user_id, true, true);
    expect_preferences(&mut db, user_id, NotificationPreferences::default());

    // Send the request
    let body = Box::pin(send_page_request(db, session_id)).await;

    // Check every section is rendered
    assert!(body.contains("Events and groups"));
    assert!(body.contains("Group organizing"));
    assert!(body.contains("Community organizing"));
    assert!(body.contains("name=\"preferences[paid-event-setups]\""));
}

#[tokio::test]
async fn test_page_renders_group_team_section() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock for a group team member
    let mut db = MockDB::new();
    expect_authenticated_session_with_teams(&mut db, session_id, user_id, true, false);
    expect_preferences(&mut db, user_id, NotificationPreferences::default());

    // Send the request
    let body = Box::pin(send_page_request(db, session_id)).await;

    // Check the group organizing section is rendered without the community one
    assert!(body.contains("Group organizing"));
    assert!(body.contains("name=\"preferences[group-inbox]\""));
    assert!(body.contains("name=\"preferences[cohosting-updates]\""));
    assert!(body.contains("name=\"preferences[attendee-activity]\""));
    assert!(!body.contains("Community organizing"));
}

#[tokio::test]
async fn test_page_renders_many_muted_groups() {
    // Setup identifiers and more muted groups than any cap
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let muted_groups = (0..30)
        .map(|index| sample_muted_group(Uuid::new_v4(), &format!("Muted Group {index}"), true))
        .collect();
    let preferences = NotificationPreferences {
        muted_groups,
        opted_out_categories: vec![],
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session_with_teams(&mut db, session_id, user_id, false, false);
    expect_preferences(&mut db, user_id, preferences);

    // Send the request
    let body = Box::pin(send_page_request(db, session_id)).await;

    // Check every muted group is listed
    assert_eq!(body.matches("aria-label=\"Unmute Muted Group").count(), 30);
}

#[tokio::test]
async fn test_page_renders_member_sections_only() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock for a member without team roles
    let mut db = MockDB::new();
    expect_authenticated_session_with_teams(&mut db, session_id, user_id, false, false);
    expect_preferences(&mut db, user_id, NotificationPreferences::default());

    // Send the request
    let body = Box::pin(send_page_request(db, session_id)).await;

    // Check only the member section, always sent list and muted groups render
    assert!(body.contains("Events and groups"));
    assert!(!body.contains("Group organizing"));
    assert!(!body.contains("Community organizing"));
    assert!(body.contains("Always sent"));
    assert!(body.contains("Organizer actions:"));
    assert!(body.contains("id=\"muted-groups\""));
    assert!(body.contains("hx-swap=\"innerHTML\""));
    assert!(body.contains("You haven't muted any groups."));
}

#[tokio::test]
async fn test_page_renders_toggle_states() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let preferences = NotificationPreferences {
        muted_groups: vec![],
        opted_out_categories: vec![NotificationCategory::Badges],
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session_with_teams(&mut db, session_id, user_id, false, false);
    expect_preferences(&mut db, user_id, preferences);

    // Send the request
    let body = Box::pin(send_page_request(db, session_id)).await;

    // Check opted-out and enabled categories render their state
    let body = body.split_whitespace().collect::<Vec<_>>().join(" ");
    assert!(body.contains("name=\"preferences[badges]\" value=\"false\""));
    assert!(body.contains("name=\"preferences[new-events]\" value=\"true\""));
}

#[tokio::test]
async fn test_unmute_group_success() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_unmute_user_group_notifications()
        .times(1)
        .withf(move |uid, gid| *uid == user_id && *gid == group_id)
        .returning(|_, _| Ok(()));

    // Send the request
    let (parts, bytes) = send_request(
        db,
        session_id,
        "DELETE",
        &format!("/dashboard/user/notifications/muted-groups/{group_id}"),
        "",
    )
    .await;

    // Check the muted groups list is refreshed
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-muted-groups",
    );
}

#[tokio::test]
async fn test_update_preferences_rejects_unknown_category() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock that must not be written
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_update_user_notification_preferences().never();

    // Send the request
    let (parts, bytes) = send_request(
        db,
        session_id,
        "PUT",
        "/dashboard/user/notifications/preferences",
        "preferences%5Bunknown%5D=false",
    )
    .await;

    // Check the payload is rejected
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), b"invalid request payload");
}

#[tokio::test]
async fn test_update_preferences_returns_database_rejection() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock rejecting the update
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_update_user_notification_preferences()
        .times(1)
        .returning(|_, _| {
            Err(HandlerError::Database("unknown notification category".to_string()).into())
        });
    db.expect_update_session().never();

    // Send the request
    let (parts, bytes) = send_request(
        db,
        session_id,
        "PUT",
        "/dashboard/user/notifications/preferences",
        "preferences%5Bbadges%5D=false",
    )
    .await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), b"unknown notification category");
}

#[tokio::test]
async fn test_update_preferences_success() {
    // Setup identifiers and data structures
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let expected_preferences = BTreeMap::from([
        (NotificationCategory::Badges, false),
        (NotificationCategory::NewEvents, true),
    ]);

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_update_user_notification_preferences()
        .times(1)
        .withf(move |uid, input| *uid == user_id && input.preferences == expected_preferences)
        .returning(|_, _| Ok(()));
    db.expect_update_session()
        .times(1)
        .withf(move |record| message_matches(record, "Notification preferences updated."))
        .returning(|_| Ok(()));

    // Send the request
    let (parts, bytes) = send_request(
        db,
        session_id,
        "PUT",
        "/dashboard/user/notifications/preferences",
        "preferences%5Bbadges%5D=false&preferences%5Bnew-events%5D=true",
    )
    .await;

    // Check the page body is refreshed
    assert_eq!(
        parts.headers.get("HX-Trigger"),
        Some(&HeaderValue::from_static("refresh-body"))
    );
    assert_empty_response(&parts, &bytes, StatusCode::NO_CONTENT);
}

// Helpers.

/// Expects an authenticated session for a user with the given team flags.
fn expect_authenticated_session_with_teams(
    db: &mut MockDB,
    session_id: session::Id,
    user_id: Uuid,
    belongs_to_any_group_team: bool,
    belongs_to_community_team: bool,
) {
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let user = crate::auth::User {
        belongs_to_any_group_team: Some(belongs_to_any_group_team),
        belongs_to_community_team: Some(belongs_to_community_team),
        ..sample_auth_user(user_id, &auth_hash)
    };

    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(user.clone())));
}

/// Expects one preferences read for the user.
fn expect_preferences(db: &mut MockDB, user_id: Uuid, preferences: NotificationPreferences) {
    db.expect_get_user_notification_preferences()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(preferences.clone()));
}

/// Returns a muted group with the given availability.
fn sample_muted_group(group_id: Uuid, name: &str, available: bool) -> MutedGroup {
    MutedGroup {
        available,
        community_display_name: "Community".to_string(),
        group_id,
        muted_at: Utc.with_ymd_and_hms(2026, 1, 1, 0, 0, 0).unwrap(),
        name: name.to_string(),
        logo_url: None,
    }
}

/// Requests the notifications page partial and returns its body.
async fn send_page_request(db: MockDB, session_id: session::Id) -> String {
    let (parts, bytes) =
        send_request(db, session_id, "GET", "/dashboard/user/notifications", "").await;
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url"),
        Some(&HeaderValue::from_static(
            "/dashboard/user?tab=notifications"
        ))
    );

    String::from_utf8(bytes.to_vec()).unwrap()
}

/// Sends a request to the router and returns the response parts and body.
async fn send_request(
    db: MockDB,
    session_id: session::Id,
    method: &str,
    uri: &str,
    body: &str,
) -> (axum::http::response::Parts, axum::body::Bytes) {
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method(method)
        .uri(uri)
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body.to_string()))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    (parts, bytes)
}
