use std::io::Cursor;

use axum::{
    body::{Body, to_bytes},
    http::{Request, StatusCode, header::CONTENT_TYPE, header::COOKIE},
};
use axum_login::tower_sessions::session;
use image::{DynamicImage, ImageFormat};
use serde_json::json;
use tower::ServiceExt;

use crate::{
    db::mock::MockDB,
    handlers::tests::{
        TestRouterBuilder, assert_empty_hx_trigger_response, expect_authenticated_group_session,
        expect_group_permission,
    },
    services::{
        images::{Image, MockImageStorage},
        notifications::MockNotificationsManager,
    },
    types::{
        badges::{AwardBadgeOutcome, BadgeAwardInput, BadgeInput, GroupAwardedBadges, GroupBadges},
        permissions::GroupPermission,
    },
};

use super::*;

#[tokio::test]
async fn test_add_artwork_rejects_missing_image() {
    // Setup an authorized group session and a missing stored image
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
    db.expect_add_badge_artwork().never();
    let mut storage = MockImageStorage::new();
    storage
        .expect_get()
        .times(1)
        .withf(|file_name| file_name == "badge.png")
        .returning(|_| Box::pin(async { Ok(None) }));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_image_storage(storage)
        .build()
        .await;

    // Register the missing basename through the protected gallery route
    let response = router
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/dashboard/group/badges/artwork")
                .header(COOKIE, format!("id={session_id}"))
                .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                .body(Body::from("file_name=badge.png"))
                .unwrap(),
        )
        .await
        .unwrap();

    // Check a nonexistent object cannot enter the reusable gallery
    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_add_artwork_rejects_wrong_dimensions() {
    // Setup an authorized group session and undersized stored PNG
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
    db.expect_add_badge_artwork().never();
    let mut storage = MockImageStorage::new();
    storage
        .expect_get()
        .times(1)
        .withf(|file_name| file_name == "badge.png")
        .return_once(|_| {
            Box::pin(async {
                Ok(Some(Image {
                    bytes: png_bytes(1, 1),
                    content_type: "image/png".to_string(),
                }))
            })
        });
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_image_storage(storage)
        .build()
        .await;

    // Register the undersized image through the protected gallery route
    let response = router
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/dashboard/group/badges/artwork")
                .header(COOKIE, format!("id={session_id}"))
                .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                .body(Body::from("file_name=badge.png"))
                .unwrap(),
        )
        .await
        .unwrap();

    // Check invalid dimensions are rejected before the database mutation
    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_add_artwork_success() {
    // Setup an authorized group session and valid stored badge artwork
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
    db.expect_add_badge_artwork()
        .times(1)
        .withf(move |actor_id, community, group, file_name| {
            *actor_id == user_id
                && *community == community_id
                && *group == group_id
                && file_name == "badge.png"
        })
        .return_once(|_, _, _, _| Ok(()));
    let mut storage = MockImageStorage::new();
    storage
        .expect_get()
        .times(1)
        .withf(|file_name| file_name == "badge.png")
        .return_once(|_| {
            Box::pin(async {
                Ok(Some(Image {
                    bytes: png_bytes(512, 512),
                    content_type: "image/png".to_string(),
                }))
            })
        });
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_image_storage(storage)
        .build()
        .await;

    // Register the validated image through the protected gallery route
    let response = router
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/dashboard/group/badges/artwork")
                .header(COOKIE, format!("id={session_id}"))
                .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                .body(Body::from("file_name=badge.png"))
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let body = to_bytes(body, usize::MAX).await.unwrap();

    // Check the dashboard refresh contract
    assert_empty_hx_trigger_response(
        &parts,
        &body,
        StatusCode::CREATED,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_add_success() {
    // Setup an authorized group session and valid definition
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let input = sample_badge_input();
    let body = serde_qs::to_string(&input).unwrap();
    let expected = input.clone();
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );
    db.expect_add_badge()
        .times(1)
        .withf(move |actor_id, community, group, badge| {
            *actor_id == user_id
                && *community == community_id
                && *group == group_id
                && badge.criteria == expected.criteria
                && badge.description == expected.description
                && badge.image_file_name == expected.image_file_name
                && badge.name == expected.name
        })
        .return_once(|_, _, _, _| Ok(()));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;

    // Submit the definition through its protected route
    let response = router
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/dashboard/group/badges")
                .header(COOKIE, format!("id={session_id}"))
                .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let body = to_bytes(body, usize::MAX).await.unwrap();

    // Check the dashboard refresh contract
    assert_empty_hx_trigger_response(
        &parts,
        &body,
        StatusCode::CREATED,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_award_success() {
    // Setup an authorized group session and one explicit recipient
    let badge_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let recipient_id = Uuid::new_v4();
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
    db.expect_award_badge()
        .times(1)
        .withf(move |actor, community, group, input| {
            *actor == user_id
                && *community == community_id
                && *group == group_id
                && *input
                    == BadgeAwardInput {
                        badge_id,
                        user_ids: vec![recipient_id],
                        event_id: Some(event_id),
                    }
        })
        .return_once(|_, _, _, _| {
            Ok(AwardBadgeOutcome {
                awarded_count: 1,
                skipped_count: 0,
            })
        });
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;

    // Submit the explicit recipient award
    let response = router
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/dashboard/group/badges/award")
                .header(COOKIE, format!("id={session_id}"))
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    json!({
                        "badge_id": badge_id,
                        "event_id": event_id,
                        "user_ids": [recipient_id],
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    // Check the complete explicit set reaches the award mutation
    assert_eq!(response.status(), StatusCode::CREATED);
}

#[tokio::test]
async fn test_award_requires_recipient() {
    // Setup an authorized group session
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
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;

    // Submit an award without recipient identifiers
    let response = router
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/dashboard/group/badges/award")
                .header(COOKIE, format!("id={session_id}"))
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    json!({"badge_id": Uuid::new_v4(), "user_ids": []}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    // Check the handler rejects an empty set before mutation
    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_group_scoped_award_success() {
    // Setup an authorized group session and one recipient
    let badge_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let recipient_id = Uuid::new_v4();
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
    db.expect_award_badge()
        .times(1)
        .withf(move |actor, community, group, input| {
            *actor == user_id
                && *community == community_id
                && *group == group_id
                && *input
                    == BadgeAwardInput {
                        badge_id,
                        user_ids: vec![recipient_id],
                        event_id: None,
                    }
        })
        .return_once(|_, _, _, _| {
            Ok(AwardBadgeOutcome {
                awarded_count: 1,
                skipped_count: 0,
            })
        });
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;

    // Submit the group-scoped recipient award
    let response = router
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/dashboard/group/badges/award")
                .header(COOKIE, format!("id={session_id}"))
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    json!({
                        "badge_id": badge_id,
                        "user_ids": [recipient_id],
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let body: AwardBadgeOutcome =
        serde_json::from_slice(&to_bytes(body, usize::MAX).await.unwrap()).unwrap();

    // Check the inserted and skipped counts cross the HTTP boundary
    assert_eq!(parts.status, StatusCode::CREATED);
    assert_eq!(body.awarded_count, 1);
    assert_eq!(body.skipped_count, 0);
}

#[tokio::test]
async fn test_resolve_checked_in_attendee_recipients() {
    // Setup an authorized event session and its current checked-in recipients
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let recipient_id = Uuid::new_v4();
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
    db.expect_list_event_badge_recipient_ids()
        .times(1)
        .withf(move |group, event, checked_in_only| {
            *group == group_id && *event == event_id && *checked_in_only
        })
        .return_once(move |_, _, _| Ok(vec![recipient_id]));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;

    // Resolve the checked-in bypass option
    let response = router
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/dashboard/group/events/{event_id}/badges/recipients?scope=checked-in-attendees"
                ))
                .header(COOKIE, format!("id={session_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let body: serde_json::Value =
        serde_json::from_slice(&to_bytes(body, usize::MAX).await.unwrap()).unwrap();

    // Check the explicit recipient list crosses the HTTP boundary
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(body, json!({ "user_ids": [recipient_id] }));
}

#[test]
fn test_is_safe_artwork_file_name_rejects_paths() {
    // Check the image-service basename shape and unsafe path forms
    assert!(is_safe_artwork_file_name("0123456789abcdef.png"));
    assert!(!is_safe_artwork_file_name("../../log-out"));
    assert!(!is_safe_artwork_file_name("badge/image.png"));
}

#[test]
fn test_badges_filters_fall_back_to_definitions_pane() {
    // Check supported panes and untrusted query values
    let mut filters = BadgesFilters::default();
    assert_eq!(filters.current_pane(), "definitions");
    filters.pane = Some("awards".to_string());
    assert_eq!(filters.current_pane(), "awards");
    filters.pane = Some("artwork".to_string());
    assert_eq!(filters.current_pane(), "artwork");
    filters.pane = Some("unknown".to_string());
    assert_eq!(filters.current_pane(), "definitions");
}

#[test]
fn test_validate_badge_input_rejects_oversized_text() {
    // Build otherwise-valid definitions exceeding each credential text bound
    let mut criteria = sample_badge_input();
    criteria.criteria = "a".repeat(BADGE_CRITERIA_MAX_CHARS + 1);
    let mut description = sample_badge_input();
    description.description = "a".repeat(BADGE_DESCRIPTION_MAX_CHARS + 1);
    let mut name = sample_badge_input();
    name.name = "a".repeat(BADGE_NAME_MAX_CHARS + 1);

    // Check every bounded field is rejected before persistence
    assert!(validate_badge_input(&criteria).is_err());
    assert!(validate_badge_input(&description).is_err());
    assert!(validate_badge_input(&name).is_err());
}

#[tokio::test]
async fn test_options_trims_search_and_returns_json() {
    // Setup an authorized group session and empty matching page
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
    db.expect_list_badges()
        .times(1)
        .withf(move |id, filters| {
            *id == group_id
                && filters.limit == 50
                && filters.offset == 0
                && filters.query.as_deref() == Some("term")
        })
        .return_once(|_, _| Ok(GroupBadges::default()));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;

    // Request modal options with surrounding whitespace
    let response = router
        .oneshot(
            Request::builder()
                .uri("/dashboard/group/badges/options?query=%20term%20")
                .header(COOKIE, format!("id={session_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let body: GroupBadges =
        serde_json::from_slice(&to_bytes(body, usize::MAX).await.unwrap()).unwrap();

    // Check the JSON page contract
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(body.total, 0);
    assert!(body.badges.is_empty());
}

#[tokio::test]
async fn test_page_builds_independent_badge_navigation() {
    // Setup an authorized group session and two independently paginated result sets
    let badge_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
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
    db.expect_list_badge_artwork()
        .times(1)
        .withf(move |id| *id == group_id)
        .return_once(|_| Ok(Vec::new()));
    db.expect_list_awarded_badges()
        .times(1)
        .withf(move |id, filters| {
            *id == group_id
                && filters.limit == 25
                && filters.offset == 50
                && filters.badge_id == Some(badge_id)
                && filters.event_id == Some(event_id)
                && filters.from.is_some()
                && filters.query.as_deref() == Some("alice")
                && filters.status.as_deref() == Some("active")
                && filters.to.is_some()
        })
        .return_once(|_, _| {
            Ok(GroupAwardedBadges {
                total: 120,
                ..Default::default()
            })
        });
    db.expect_list_badges()
        .times(1)
        .withf(move |id, filters| {
            *id == group_id
                && filters.limit == 25
                && filters.offset == 75
                && filters.query.as_deref() == Some("helper")
        })
        .return_once(|_, _| {
            Ok(GroupBadges {
                total: 125,
                ..Default::default()
            })
        });
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;

    // Request definition navigation while preserving award-history state
    let response = router
        .oneshot(
            Request::builder()
                .uri(format!(
                    "/dashboard/group/badges?tab=badges&awards_offset=50&awards_query=alice&badge_id={badge_id}\
                     &badges_offset=75&badges_query=helper&event_id={event_id}\
                     &from=2026-01-01&limit=25&pane=definitions&status=active&to=2026-01-31"
                ))
                .header(COOKIE, format!("id={session_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let body = String::from_utf8(to_bytes(body, usize::MAX).await.unwrap().to_vec()).unwrap();

    // Check full and partial navigation keep both offsets and filter selections
    assert_eq!(parts.status, StatusCode::OK);
    assert!(
        parts
            .headers
            .get("hx-push-url")
            .unwrap()
            .to_str()
            .unwrap()
            .starts_with("/dashboard/group?tab=badges&")
    );
    assert!(body.contains("badge-definitions-pagination-next-spinner"));
    assert!(body.contains("badge-awards-pagination-next-spinner"));
    assert!(body.contains("badges_offset=100"));
    assert!(body.contains("awards_offset=75"));
    assert!(body.contains("badges_query=helper"));
    assert!(body.contains("awards_query=alice"));
    assert!(body.contains("href=\"/dashboard/group?tab=badges"));
    assert!(body.contains("hx-get=\"/dashboard/group/badges?"));
}

#[tokio::test]
async fn test_page_rejects_oversized_awards_offset() {
    // Setup an authorized group session without database page expectations
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
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;

    // Request an offset that cannot bind to the PostgreSQL integer parameter
    let response = router
        .oneshot(
            Request::builder()
                .uri("/dashboard/group/badges?awards_offset=2147483648")
                .header(COOKIE, format!("id={session_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // Check invalid pagination is rejected before any page query
    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_page_rejects_oversized_badges_offset() {
    // Setup an authorized group session without database page expectations
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
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;

    // Request an offset that cannot bind to the PostgreSQL integer parameter
    let response = router
        .oneshot(
            Request::builder()
                .uri("/dashboard/group/badges?badges_offset=2147483648")
                .header(COOKIE, format!("id={session_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // Check invalid pagination is rejected before any page query
    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

// Helpers.

/// Encode a PNG fixture with the requested dimensions.
fn png_bytes(width: u32, height: u32) -> Vec<u8> {
    let mut output = Cursor::new(Vec::new());
    DynamicImage::new_rgba8(width, height)
        .write_to(&mut output, ImageFormat::Png)
        .unwrap();
    output.into_inner()
}

/// Build one valid badge definition form fixture.
fn sample_badge_input() -> BadgeInput {
    BadgeInput {
        criteria: "Attend the event".to_string(),
        description: "Recognizes participation".to_string(),
        image_file_name: "badge.png".to_string(),
        name: "Participant".to_string(),
    }
}
