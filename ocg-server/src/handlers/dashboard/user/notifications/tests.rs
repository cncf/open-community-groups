use std::collections::BTreeMap;

use axum::http::{HeaderValue, StatusCode};
use chrono::{TimeZone, Utc};
use serde_json::{Value, from_slice};
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::{error::HandlerError, tests::*},
    test_util::normalize_whitespace,
    types::dashboard::user::notifications::{
        MutedGroup, NotificationCategory, NotificationGroupOption, NotificationPreferences,
    },
};

#[tokio::test]
async fn test_group_options_returns_json() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();
    let ids = DashboardIds::new();

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_list_user_notification_group_options()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(move |_| {
            Ok(vec![NotificationGroupOption {
                community_display_name: "Community".to_string(),
                group_id,
                name: "Group".to_string(),
                logo_url: None,
            }])
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        "/dashboard/user/notifications/group-options",
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

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
async fn test_mute_group_success() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();
    let ids = DashboardIds::new();

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_mute_user_group_notifications()
        .times(1)
        .withf(move |uid, gid| *uid == ids.user_id && *gid == group_id)
        .returning(|_, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/user/notifications/muted-groups/{group_id}"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

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
    let ids = DashboardIds::new();

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_get_user_notification_preferences()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(|_| Ok(NotificationPreferences::default()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user/notifications/muted-groups", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the empty state is rendered
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("You haven't muted any groups."));
}

#[tokio::test]
async fn test_muted_groups_renders_inner_content_only() {
    // Setup identifiers and data structures
    let available_group_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let unavailable_group_id = Uuid::new_v4();
    let preferences = NotificationPreferences {
        muted_groups: vec![
            sample_muted_group(available_group_id, "Available Group", true),
            sample_muted_group(unavailable_group_id, "Retired Group", false),
        ],
        opted_out_categories: vec![],
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_get_user_notification_preferences()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(move |_| Ok(preferences.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user/notifications/muted-groups", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the rows render without the refresh wrapper
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(!body.contains("id=\"muted-groups\""));
    assert!(body.contains("aria-label=\"Unmute Available Group\""));
    assert!(body.contains(&format!(
        "hx-delete=\"/dashboard/user/notifications/muted-groups/{available_group_id}\""
    )));
    assert!(body.contains("aria-label=\"Unmute Retired Group\""));
    assert_eq!(body.matches("Not available").count(), 1);
}

#[tokio::test]
async fn test_page_renders_community_team_section() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();

    // Setup database mock for a community team member
    let mut db = MockDB::new();
    expect_session_with_teams(
        &mut db,
        &ids,
        TeamMembership {
            community: true,
            group: true,
        },
    );
    expect_preferences(&mut db, &ids, NotificationPreferences::default());

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user/notifications", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the page partial pushes the full dashboard URL
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url"),
        Some(&HeaderValue::from_static(
            "/dashboard/user?tab=notifications"
        ))
    );
    let body = std::str::from_utf8(&bytes).unwrap();

    // Check every section is rendered
    assert!(body.contains("Events and groups"));
    assert!(body.contains("Group organizing"));
    assert!(body.contains("Community organizing"));
    assert!(body.contains("name=\"preferences[paid-event-setups]\""));
}

#[tokio::test]
async fn test_page_renders_group_team_section() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();

    // Setup database mock for a group team member
    let mut db = MockDB::new();
    expect_session_with_teams(
        &mut db,
        &ids,
        TeamMembership {
            community: false,
            group: true,
        },
    );
    expect_preferences(&mut db, &ids, NotificationPreferences::default());

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user/notifications", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the page partial pushes the full dashboard URL
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url"),
        Some(&HeaderValue::from_static(
            "/dashboard/user?tab=notifications"
        ))
    );
    let body = std::str::from_utf8(&bytes).unwrap();

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
    let ids = DashboardIds::new();
    let muted_groups = (0..30)
        .map(|index| sample_muted_group(Uuid::new_v4(), &format!("Muted Group {index}"), true))
        .collect();
    let preferences = NotificationPreferences {
        muted_groups,
        opted_out_categories: vec![],
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_session_with_teams(&mut db, &ids, TeamMembership::default());
    expect_preferences(&mut db, &ids, preferences);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user/notifications", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the page partial pushes the full dashboard URL
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url"),
        Some(&HeaderValue::from_static(
            "/dashboard/user?tab=notifications"
        ))
    );
    let body = std::str::from_utf8(&bytes).unwrap();

    // Check every muted group is listed
    assert_eq!(body.matches("aria-label=\"Unmute Muted Group").count(), 30);
}

#[tokio::test]
async fn test_page_renders_member_sections_only() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();

    // Setup database mock for a member without team roles
    let mut db = MockDB::new();
    expect_session_with_teams(&mut db, &ids, TeamMembership::default());
    expect_preferences(&mut db, &ids, NotificationPreferences::default());

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user/notifications", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the page partial pushes the full dashboard URL
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url"),
        Some(&HeaderValue::from_static(
            "/dashboard/user?tab=notifications"
        ))
    );
    let body = std::str::from_utf8(&bytes).unwrap();

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
    let ids = DashboardIds::new();
    let preferences = NotificationPreferences {
        muted_groups: vec![],
        opted_out_categories: vec![
            NotificationCategory::Badges,
            NotificationCategory::EventSurveys,
        ],
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_session_with_teams(&mut db, &ids, TeamMembership::default());
    expect_preferences(&mut db, &ids, preferences);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user/notifications", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the page partial pushes the full dashboard URL
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url"),
        Some(&HeaderValue::from_static(
            "/dashboard/user?tab=notifications"
        ))
    );
    let body = std::str::from_utf8(&bytes).unwrap();

    // Check opted-out and enabled categories render their state
    let body = normalize_whitespace(body);
    assert!(body.contains("name=\"preferences[badges]\" value=\"false\""));
    assert!(body.contains("name=\"preferences[event-reminders]\" value=\"true\""));
    assert!(body.contains("name=\"preferences[event-surveys]\" value=\"false\""));
    assert!(body.contains("name=\"preferences[new-events]\" value=\"true\""));
}

#[tokio::test]
async fn test_unmute_group_success() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();
    let ids = DashboardIds::new();

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_unmute_user_group_notifications()
        .times(1)
        .withf(move |uid, gid| *uid == ids.user_id && *gid == group_id)
        .returning(|_, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "DELETE",
        &format!("/dashboard/user/notifications/muted-groups/{group_id}"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

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
    let ids = DashboardIds::new();

    // Setup database mock that must not be written
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_update_user_notification_preferences().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        "/dashboard/user/notifications/preferences",
        ids.session_id,
        "preferences%5Bunknown%5D=false",
    );
    let (parts, bytes) = send(router, request).await;

    // Check the payload is rejected
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), b"invalid request payload");
}

#[tokio::test]
async fn test_update_preferences_returns_database_rejection() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();

    // Setup database mock rejecting the update
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_update_user_notification_preferences()
        .times(1)
        .returning(|_, _| {
            Err(HandlerError::Database("unknown notification category".to_string()).into())
        });
    db.expect_update_session().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        "/dashboard/user/notifications/preferences",
        ids.session_id,
        "preferences%5Bbadges%5D=false",
    );
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), b"unknown notification category");
}

#[tokio::test]
async fn test_update_preferences_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let expected_preferences = BTreeMap::from([
        (NotificationCategory::Badges, false),
        (NotificationCategory::NewEvents, true),
    ]);

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_update_user_notification_preferences()
        .times(1)
        .withf(move |uid, input| *uid == ids.user_id && input.preferences == expected_preferences)
        .returning(|_, _| Ok(()));
    db.expect_update_session()
        .times(1)
        .withf(move |record| message_matches(record, "Notification preferences updated."))
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        "/dashboard/user/notifications/preferences",
        ids.session_id,
        "preferences%5Bbadges%5D=false&preferences%5Bnew-events%5D=true",
    );
    let (parts, bytes) = send(router, request).await;

    // Check the page body is refreshed
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

// Helpers.

/// Team memberships of the authenticated user that select the page sections.
#[derive(Clone, Copy, Default)]
struct TeamMembership {
    /// Whether the user belongs to a community team.
    community: bool,
    /// Whether the user belongs to any group team.
    group: bool,
}

/// Expects one preferences read for the user.
fn expect_preferences(db: &mut MockDB, ids: &DashboardIds, preferences: NotificationPreferences) {
    let user_id = ids.user_id;
    db.expect_get_user_notification_preferences()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(preferences.clone()));
}

/// Expects an authenticated session for a user with the given team memberships.
fn expect_session_with_teams(db: &mut MockDB, ids: &DashboardIds, teams: TeamMembership) {
    let user = crate::auth::User {
        belongs_to_any_group_team: Some(teams.group),
        belongs_to_community_team: Some(teams.community),
        ..sample_auth_user(ids.user_id, "hash")
    };
    expect_session_with_user(db, ids, user);
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
