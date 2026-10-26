use std::io::Cursor;

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use image::DynamicImage;
use serde_json::json;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    services::images::MockImageStorage,
    test_util::sample_png,
    types::{
        badges::{
            AwardBadgeOutcome, BadgeAwardInput, BadgeAwardSourceFilter, BadgeInput,
            GroupAwardedBadges, GroupBadges,
        },
        images::Image,
        permissions::GroupPermission,
    },
};

use super::*;

/// Message returned for any badge artwork that fails validation.
const INVALID_ARTWORK_MESSAGE: &str = "badge artwork must be a 512x512 PNG, JPEG, or WebP image";

#[tokio::test]
async fn test_artwork_page_renders_independent_tab() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_list_badge_artwork()
        .times(1)
        .withf(move |group_id| *group_id == ids.group_id)
        .return_once(|_| Ok(Vec::new()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group/artwork", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check artwork renders alone and pushes its full dashboard URL
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url").unwrap(),
        "/dashboard/group?tab=artwork"
    );
    assert!(body.contains(">Badges Artwork</h1>"));
    assert!(!body.contains("data-badge-pane"));
}

#[tokio::test]
async fn test_awards_page_builds_navigation() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let badge_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let expected_from = NaiveDate::from_ymd_opt(2026, 1, 1)
        .unwrap()
        .and_hms_opt(0, 0, 0)
        .unwrap()
        .and_utc();
    let expected_to = NaiveDate::from_ymd_opt(2026, 2, 1)
        .unwrap()
        .and_hms_opt(0, 0, 0)
        .unwrap()
        .and_utc();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_list_awarded_badges()
        .times(1)
        .withf(move |group_id, filters| {
            *group_id == ids.group_id
                && filters.limit == 25
                && filters.offset == 50
                && filters.badge_id == Some(badge_id)
                && filters.from.as_ref() == Some(&expected_from)
                && filters.query.as_deref() == Some("alice")
                && filters.source == Some(BadgeAwardSourceFilter::Event(event_id))
                && filters.status.as_deref() == Some("active")
                && filters.to.as_ref() == Some(&expected_to)
        })
        .return_once(|_, _| {
            Ok(GroupAwardedBadges {
                total: 120,
                ..Default::default()
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!(
            "/dashboard/group/awards?awards_offset=50&awards_query=alice&badge_id={badge_id}\
             &from=2026-01-01&limit=25&source={event_id}&status=active&to=2026-01-31"
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check full and partial navigation stay within the awards tab
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url").unwrap(),
        &format!(
            "/dashboard/group?tab=awards&awards_offset=50&awards_query=alice&badge_id={badge_id}\
             &from=2026-01-01&limit=25&source={event_id}&status=active&to=2026-01-31"
        ),
    );
    assert!(body.contains("badge-awards-pagination-next-spinner"));
    assert!(body.contains("awards_offset=75"));
    assert!(body.contains("awards_query=alice"));
    assert!(body.contains("href=\"/dashboard/group?tab=awards"));
    assert!(body.contains("hx-get=\"/dashboard/group/awards?"));
    assert!(body.contains(">Badges Awards</h1>"));
}

#[tokio::test]
async fn test_awards_page_filters_direct_group_awards() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_list_awarded_badges()
        .times(1)
        .withf(move |group_id, filters| {
            *group_id == ids.group_id && filters.source == Some(BadgeAwardSourceFilter::Group)
        })
        .return_once(|_, _| Ok(GroupAwardedBadges::default()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group/awards?source=group", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the group sentinel reaches the award-history query
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_awards_page_rejects_invalid_from_date() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_list_awarded_badges().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group/awards?from=not-a-date", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check date validation fails before querying award history
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes, "from date is invalid");
}

#[tokio::test]
async fn test_awards_page_rejects_invalid_to_date() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_list_awarded_badges().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group/awards?to=2026-02-31", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check date validation fails before querying award history
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes, "to date is invalid");
}

#[tokio::test]
async fn test_awards_page_rejects_oversized_offset() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_list_awarded_badges().never();

    // Setup router and send request with an offset PostgreSQL cannot bind
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        "/dashboard/group/awards?awards_offset=2147483648",
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check invalid pagination is rejected before any page query
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes, "award history offset is too large");
}

#[tokio::test]
async fn test_badges_page_builds_navigation() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_list_badge_artwork()
        .times(1)
        .withf(move |group_id| *group_id == ids.group_id)
        .return_once(|_| Ok(Vec::new()));
    db.expect_list_badges()
        .times(1)
        .withf(move |group_id, filters| {
            *group_id == ids.group_id
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

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        "/dashboard/group/badges?badges_offset=75&badges_query=helper&limit=25",
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check full and partial navigation stay within the badges tab
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url").unwrap(),
        "/dashboard/group?tab=badges&badges_offset=75&badges_query=helper&limit=25",
    );
    assert!(body.contains("badge-definitions-pagination-next-spinner"));
    assert!(body.contains("badges_offset=100"));
    assert!(body.contains("badges_query=helper"));
    assert!(body.contains("href=\"/dashboard/group?tab=badges"));
    assert!(body.contains("hx-get=\"/dashboard/group/badges?"));
    assert!(body.contains(">Badges</h1>"));
}

#[tokio::test]
async fn test_badges_page_rejects_oversized_offset() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_list_badge_artwork().never();
    db.expect_list_badges().never();

    // Setup router and send request with an offset PostgreSQL cannot bind
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        "/dashboard/group/badges?badges_offset=2147483648",
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check invalid pagination is rejected before any page query
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes, "badge definition offset is too large");
}

#[tokio::test]
async fn test_options_trims_search_and_returns_json() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_list_badges()
        .times(1)
        .withf(move |group_id, filters| {
            *group_id == ids.group_id
                && filters.limit == 50
                && filters.offset == 0
                && filters.query.as_deref() == Some("term")
        })
        .return_once(|_, _| Ok(GroupBadges::default()));

    // Setup router and send request with surrounding whitespace
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        "/dashboard/group/badges/options?query=%20term%20",
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let body: GroupBadges = serde_json::from_slice(&bytes).unwrap();

    // Check the JSON page contract
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(body.total, 0);
    assert!(
        body.badges.is_empty(),
        "badges page should be empty, got {:?}",
        body.badges
    );
}

#[tokio::test]
async fn test_recipients_resolves_all_attendees() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let recipient_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_list_event_attendees_ids()
        .times(1)
        .withf(move |group_id, event, checked_in_only| {
            *group_id == ids.group_id && *event == event_id && !*checked_in_only
        })
        .return_once(move |_, _, _| Ok(vec![recipient_id]));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/badges/recipients?scope=all-attendees"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();

    // Check the explicit recipient list crosses the HTTP boundary
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(body, json!({ "user_ids": [recipient_id] }));
}

#[tokio::test]
async fn test_recipients_resolves_checked_in_attendees() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let recipient_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_list_event_attendees_ids()
        .times(1)
        .withf(move |group_id, event, checked_in_only| {
            *group_id == ids.group_id && *event == event_id && *checked_in_only
        })
        .return_once(move |_, _, _| Ok(vec![recipient_id]));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/badges/recipients?scope=checked-in-attendees"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();

    // Check the explicit recipient list crosses the HTTP boundary
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(body, json!({ "user_ids": [recipient_id] }));
}

#[tokio::test]
async fn test_add_rejects_invalid_input() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let mut input = sample_badge_input();
    input.description = "   ".to_string();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_add_badge().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "POST",
        "/dashboard/group/badges",
        ids.session_id,
        serde_qs::to_string(&input).unwrap(),
    );
    let (parts, bytes) = send(router, request).await;

    // Check input validation fails before the badge mutation
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes, "all badge fields are required");
}

#[tokio::test]
async fn test_add_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let input = sample_badge_input();
    let body = serde_qs::to_string(&input).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_add_badge()
        .times(1)
        .withf(move |actor_id, community_id, group_id, badge| {
            *actor_id == ids.user_id
                && *community_id == ids.community_id
                && *group_id == ids.group_id
                && badge.criteria == input.criteria
                && badge.description == input.description
                && badge.image_file_name == input.image_file_name
                && badge.name == input.name
        })
        .return_once(|_, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request("POST", "/dashboard/group/badges", ids.session_id, body);
    let (parts, bytes) = send(router, request).await;

    // Check the dashboard refresh contract
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::CREATED,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_add_artwork_rejects_invalid_file_name() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_add_badge_artwork().never();

    // Setup image storage mock, which must not be read
    let mut storage = MockImageStorage::new();
    storage.expect_get().never();

    // Setup router and send request with a path instead of a basename
    let router = TestRouterBuilder::new(db).with_image_storage(storage).build().await;
    let (parts, bytes) = send(router, add_artwork_request(&ids, "../badge.png")).await;

    // Check the filename is rejected before storage or database access
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes, "artwork filename is invalid");
}

#[tokio::test]
async fn test_add_artwork_rejects_missing_image() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_add_badge_artwork().never();

    // Setup image storage mock without the stored image
    let mut storage = MockImageStorage::new();
    storage
        .expect_get()
        .times(1)
        .withf(|file_name| file_name == "badge.png")
        .returning(|_| Box::pin(async { Ok(None) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).with_image_storage(storage).build().await;
    let (parts, bytes) = send(router, add_artwork_request(&ids, "badge.png")).await;

    // Check a nonexistent object cannot enter the reusable gallery
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes, "badge artwork was not found");
}

#[tokio::test]
async fn test_add_artwork_rejects_wrong_dimensions() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_add_badge_artwork().never();

    // Setup image storage mock with an undersized PNG
    let mut storage = MockImageStorage::new();
    storage
        .expect_get()
        .times(1)
        .withf(|file_name| file_name == "badge.png")
        .return_once(|_| Box::pin(async { Ok(Some(png_image(1, 1))) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).with_image_storage(storage).build().await;
    let (parts, bytes) = send(router, add_artwork_request(&ids, "badge.png")).await;

    // Check invalid dimensions are rejected before the database mutation
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes, INVALID_ARTWORK_MESSAGE);
}

#[tokio::test]
async fn test_add_artwork_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_add_badge_artwork()
        .times(1)
        .withf(move |actor_id, community_id, group_id, file_name| {
            *actor_id == ids.user_id
                && *community_id == ids.community_id
                && *group_id == ids.group_id
                && file_name == "badge.png"
        })
        .return_once(|_, _, _, _| Ok(()));

    // Setup image storage mock with valid badge artwork
    let mut storage = MockImageStorage::new();
    storage
        .expect_get()
        .times(1)
        .withf(|file_name| file_name == "badge.png")
        .return_once(|_| Box::pin(async { Ok(Some(png_image(512, 512))) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).with_image_storage(storage).build().await;
    let (parts, bytes) = send(router, add_artwork_request(&ids, "badge.png")).await;

    // Check the dashboard refresh contract
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::CREATED,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_award_event_scoped_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let badge_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let recipient_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_award_badge()
        .times(1)
        .withf(move |actor_id, community_id, group_id, input| {
            *actor_id == ids.user_id
                && *community_id == ids.community_id
                && *group_id == ids.group_id
                && *input
                    == BadgeAwardInput {
                        badge_id,
                        user_ids: vec![recipient_id],
                        event_id: Some(event_id),
                    }
        })
        .return_once(|_, _, _, _| {
            Ok(AwardBadgeOutcome {
                queued_count: 1,
                skipped_count: 0,
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let body = json!({
        "badge_id": badge_id,
        "event_id": event_id,
        "user_ids": [recipient_id],
    });
    let request = json_request(
        "POST",
        "/dashboard/group/badges/award",
        ids.session_id,
        &body,
    );
    let (parts, bytes) = send(router, request).await;
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();

    // Check the complete explicit set reaches the award mutation
    assert_eq!(parts.status, StatusCode::CREATED);
    assert_eq!(body, json!({ "queued_count": 1, "skipped_count": 0 }));
}

#[tokio::test]
async fn test_award_group_scoped_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let badge_id = Uuid::new_v4();
    let recipient_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_award_badge()
        .times(1)
        .withf(move |actor_id, community_id, group_id, input| {
            *actor_id == ids.user_id
                && *community_id == ids.community_id
                && *group_id == ids.group_id
                && *input
                    == BadgeAwardInput {
                        badge_id,
                        user_ids: vec![recipient_id],
                        event_id: None,
                    }
        })
        .return_once(|_, _, _, _| {
            Ok(AwardBadgeOutcome {
                queued_count: 1,
                skipped_count: 2,
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let body = json!({
        "badge_id": badge_id,
        "user_ids": [recipient_id],
    });
    let request = json_request(
        "POST",
        "/dashboard/group/badges/award",
        ids.session_id,
        &body,
    );
    let (parts, bytes) = send(router, request).await;
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();

    // Check the queued and skipped counts cross the HTTP boundary
    assert_eq!(parts.status, StatusCode::CREATED);
    assert_eq!(body, json!({ "queued_count": 1, "skipped_count": 2 }));
}

#[tokio::test]
async fn test_award_requires_recipient() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_award_badge().never();

    // Setup router and send request without recipient identifiers
    let router = TestRouterBuilder::new(db).build().await;
    let body = json!({ "badge_id": Uuid::new_v4(), "user_ids": [] });
    let request = json_request(
        "POST",
        "/dashboard/group/badges/award",
        ids.session_id,
        &body,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the handler rejects an empty set before mutation
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes, "badge recipients cannot be empty");
}

#[tokio::test]
async fn test_delete_rejects_invalid_badge_id() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_delete_badge().never();

    // Setup router and send request with a malformed path identifier
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "DELETE",
        "/dashboard/group/badges/not-a-uuid",
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check path validation fails before the badge mutation
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert!(body.contains("Cannot parse"));
    assert!(body.contains("badge_id"));
}

#[tokio::test]
async fn test_delete_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let badge_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_delete_badge()
        .times(1)
        .withf(move |actor_id, community_id, group_id, badge| {
            *actor_id == ids.user_id
                && *community_id == ids.community_id
                && *group_id == ids.group_id
                && *badge == badge_id
        })
        .return_once(|_, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "DELETE",
        &format!("/dashboard/group/badges/{badge_id}"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the dashboard refresh contract
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_delete_artwork_rejects_invalid_artwork_id() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_delete_badge_artwork().never();

    // Setup router and send request with a malformed path identifier
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "DELETE",
        "/dashboard/group/badges/artwork/not-a-uuid",
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check path validation fails before the artwork mutation
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert!(body.contains("Cannot parse"));
    assert!(body.contains("badge_artwork_id"));
}

#[tokio::test]
async fn test_delete_artwork_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let badge_artwork_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_delete_badge_artwork()
        .times(1)
        .withf(move |actor_id, community_id, group_id, artwork| {
            *actor_id == ids.user_id
                && *community_id == ids.community_id
                && *group_id == ids.group_id
                && *artwork == badge_artwork_id
        })
        .return_once(|_, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "DELETE",
        &format!("/dashboard/group/badges/artwork/{badge_artwork_id}"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the dashboard refresh contract
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_revoke_rejects_invalid_user_badge_id() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_revoke_group_user_badge().never();

    // Setup router and send request with a malformed path identifier
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "POST",
        "/dashboard/group/badges/awards/not-a-uuid/revoke",
        ids.session_id,
        "reason=duplicate",
    );
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check path validation fails before the revocation mutation
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert!(body.contains("Cannot parse"));
    assert!(body.contains("user_badge_id"));
}

#[tokio::test]
async fn test_revoke_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let user_badge_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_revoke_group_user_badge()
        .times(1)
        .withf(move |actor_id, community_id, group_id, badge, reason| {
            *actor_id == ids.user_id
                && *community_id == ids.community_id
                && *group_id == ids.group_id
                && *badge == user_badge_id
                && reason == "duplicate"
        })
        .return_once(|_, _, _, _, _| Ok(()));

    // Setup router and send request with the private reason
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "POST",
        &format!("/dashboard/group/badges/awards/{user_badge_id}/revoke"),
        ids.session_id,
        "reason=duplicate",
    );
    let (parts, bytes) = send(router, request).await;

    // Check the dashboard refresh contract
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_update_rejects_invalid_input() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let badge_id = Uuid::new_v4();
    let mut input = sample_badge_input();
    input.name.clear();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_update_badge().never();

    // Setup router and send request with a missing required field
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/group/badges/{badge_id}"),
        ids.session_id,
        serde_qs::to_string(&input).unwrap(),
    );
    let (parts, bytes) = send(router, request).await;

    // Check input validation fails before the badge mutation
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes, "all badge fields are required");
}

#[tokio::test]
async fn test_update_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let badge_id = Uuid::new_v4();
    let input = sample_badge_input();
    let body = serde_qs::to_string(&input).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::BadgesWrite);
    db.expect_update_badge()
        .times(1)
        .withf(
            move |actor_id, community_id, group_id, badge_id_arg, badge| {
                *actor_id == ids.user_id
                    && *community_id == ids.community_id
                    && *group_id == ids.group_id
                    && *badge_id_arg == badge_id
                    && badge.criteria == input.criteria
                    && badge.description == input.description
                    && badge.image_file_name == input.image_file_name
                    && badge.name == input.name
            },
        )
        .return_once(|_, _, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/group/badges/{badge_id}"),
        ids.session_id,
        body,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the dashboard refresh contract
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[test]
fn test_is_safe_artwork_file_name() {
    let cases = [
        (
            "content-addressed basename",
            "0123456789abcdef.png".to_string(),
            true,
        ),
        (
            "separators after the first byte",
            "a1_b-c.d.webp".to_string(),
            true,
        ),
        ("80 characters", format!("{}.png", "a".repeat(76)), true),
        ("81 characters", format!("{}.png", "a".repeat(77)), false),
        ("empty", String::new(), false),
        ("leading dot", ".badge.png".to_string(), false),
        ("leading hyphen", "-badge.png".to_string(), false),
        ("parent traversal", "../../log-out".to_string(), false),
        ("nested path", "badge/image.png".to_string(), false),
        ("inner space", "badge image.png".to_string(), false),
        ("non-ascii", "bädge.png".to_string(), false),
    ];

    for (label, file_name, expected) in cases {
        assert_eq!(is_safe_artwork_file_name(&file_name), expected, "{label}");
    }
}

#[test]
fn test_parse_date_filters() {
    let midnight = |year, month, day| {
        NaiveDate::from_ymd_opt(year, month, day)
            .unwrap()
            .and_hms_opt(0, 0, 0)
            .unwrap()
            .and_utc()
    };
    let cases = [
        ("empty from", parse_date_filter("from", ""), Ok(None)),
        (
            "valid from",
            parse_date_filter("from", "2026-01-31"),
            Ok(Some(midnight(2026, 1, 31))),
        ),
        (
            "malformed from",
            parse_date_filter("from", "not-a-date"),
            Err("from date is invalid"),
        ),
        ("empty to", parse_to_date_filter(""), Ok(None)),
        (
            "valid to is exclusive next day",
            parse_to_date_filter("2026-01-31"),
            Ok(Some(midnight(2026, 2, 1))),
        ),
        (
            "impossible to date",
            parse_to_date_filter("2026-02-31"),
            Err("to date is invalid"),
        ),
        (
            "unrepresentable exclusive bound",
            parse_to_date_filter("+262142-12-31"),
            Err("to date is invalid"),
        ),
    ];

    for (label, result, expected) in cases {
        match (result, expected) {
            (Ok(date), Ok(expected_date)) => assert_eq!(date, expected_date, "{label}"),
            (Err(HandlerError::Rejected(message)), Err(expected_message)) => {
                assert_eq!(message, expected_message, "{label}");
            }
            (result, expected) => panic!("{label}: got {result:?}, expected {expected:?}"),
        }
    }
}

#[test]
fn test_validate_badge_artwork() {
    let mut oversized_png = sample_png(512, 512);
    oversized_png.resize(MAX_BADGE_ARTWORK_SIZE_BYTES + 1, 0);
    let cases = [
        ("512x512 png", "badge.png", png_image(512, 512), true),
        (
            "uppercase extension",
            "badge.PNG",
            png_image(512, 512),
            true,
        ),
        (
            "512x512 jpeg with jpg extension",
            "badge.jpg",
            encoded_image(ImageFormat::Jpeg, "image/jpeg"),
            true,
        ),
        (
            "512x512 jpeg with jpeg extension",
            "badge.jpeg",
            encoded_image(ImageFormat::Jpeg, "image/jpeg"),
            true,
        ),
        (
            "512x512 webp",
            "badge.webp",
            encoded_image(ImageFormat::WebP, "image/webp"),
            true,
        ),
        ("undersized png", "badge.png", png_image(1, 1), false),
        (
            "non-square png",
            "badge.png",
            stored_image(sample_png(512, 256), "image/png"),
            false,
        ),
        (
            "oversized png",
            "badge.png",
            stored_image(oversized_png, "image/png"),
            false,
        ),
        (
            "png bytes with jpg extension",
            "badge.jpg",
            png_image(512, 512),
            false,
        ),
        (
            "png bytes without extension",
            "badge",
            png_image(512, 512),
            false,
        ),
        (
            "png bytes with jpeg content type",
            "badge.png",
            stored_image(sample_png(512, 512), "image/jpeg"),
            false,
        ),
        (
            "unsupported gif format",
            "badge.gif",
            encoded_image(ImageFormat::Gif, "image/gif"),
            false,
        ),
        (
            "non-image bytes",
            "badge.png",
            stored_image(b"not an image".to_vec(), "image/png"),
            false,
        ),
    ];

    for (label, file_name, image, accepted) in cases {
        match validate_badge_artwork(file_name, &image) {
            Ok(()) => assert!(accepted, "{label}: should be rejected"),
            Err(HandlerError::Rejected(message)) => {
                assert!(!accepted, "{label}: should be accepted, got {message:?}");
                assert_eq!(message, INVALID_ARTWORK_MESSAGE, "{label}");
            }
            Err(err) => panic!("{label}: unexpected error {err:?}"),
        }
    }
}

#[test]
fn test_validate_badge_input() {
    let with = |update: fn(&mut BadgeInput)| {
        let mut input = sample_badge_input();
        update(&mut input);
        input
    };
    let cases = [
        ("valid definition", sample_badge_input(), None),
        (
            "text at every bound",
            with(|input| {
                input.criteria = "a".repeat(BADGE_CRITERIA_MAX_CHARS);
                input.description = "a".repeat(BADGE_DESCRIPTION_MAX_CHARS);
                input.name = "é".repeat(BADGE_NAME_MAX_CHARS);
            }),
            None,
        ),
        (
            "blank criteria",
            with(|input| input.criteria = " ".to_string()),
            Some("all badge fields are required"),
        ),
        (
            "empty description",
            with(|input| input.description.clear()),
            Some("all badge fields are required"),
        ),
        (
            "empty image file name",
            with(|input| input.image_file_name.clear()),
            Some("all badge fields are required"),
        ),
        (
            "blank name",
            with(|input| input.name = "\t".to_string()),
            Some("all badge fields are required"),
        ),
        (
            "unsafe image file name",
            with(|input| input.image_file_name = "../badge.png".to_string()),
            Some("all badge fields are required"),
        ),
        (
            "oversized criteria",
            with(|input| input.criteria = "a".repeat(BADGE_CRITERIA_MAX_CHARS + 1)),
            Some("badge text exceeds the allowed length"),
        ),
        (
            "oversized description",
            with(|input| input.description = "a".repeat(BADGE_DESCRIPTION_MAX_CHARS + 1)),
            Some("badge text exceeds the allowed length"),
        ),
        (
            "oversized name",
            with(|input| input.name = "a".repeat(BADGE_NAME_MAX_CHARS + 1)),
            Some("badge text exceeds the allowed length"),
        ),
    ];

    for (label, input, expected_error) in cases {
        match (validate_badge_input(&input), expected_error) {
            (Ok(()), None) => {}
            (Err(HandlerError::Rejected(message)), Some(expected_message)) => {
                assert_eq!(message, expected_message, "{label}");
            }
            (result, expected) => panic!("{label}: got {result:?}, expected {expected:?}"),
        }
    }
}

// Helpers.

/// Build the request that adds a stored image to the artwork gallery.
fn add_artwork_request(ids: &DashboardIds, file_name: &str) -> Request<Body> {
    form_request(
        "POST",
        "/dashboard/group/badges/artwork",
        ids.session_id,
        format!("file_name={file_name}"),
    )
}

/// Encode a 512x512 image in the format with the content type.
fn encoded_image(format: ImageFormat, content_type: &str) -> Image {
    let mut output = Cursor::new(Vec::new());
    DynamicImage::new_rgb8(BADGE_ARTWORK_SIZE, BADGE_ARTWORK_SIZE)
        .write_to(&mut output, format)
        .unwrap();
    stored_image(output.into_inner(), content_type)
}

/// Build a stored PNG image with the dimensions.
fn png_image(width: u32, height: u32) -> Image {
    stored_image(sample_png(width, height), "image/png")
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

/// Build a stored image from its bytes and content type.
fn stored_image(bytes: Vec<u8>, content_type: &str) -> Image {
    Image {
        bytes,
        content_type: content_type.to_string(),
    }
}
