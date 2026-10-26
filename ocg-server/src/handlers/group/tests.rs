use axum::{
    body::Body,
    http::{
        HeaderValue, StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE, LOCATION},
    },
};
use serde_json::{from_slice, json};
use uuid::Uuid;

use crate::{
    activity_tracker::{Activity, MockActivityTracker},
    db::mock::{MockDB, expect_site_settings},
    handlers::tests::*,
    router::CACHE_CONTROL_PUBLIC_SHARED,
    services::enrollment::{EnrollmentError, MockEnrollmentManager},
    types::{
        event::{EventKind, EventSummary},
        group::GroupFull,
    },
};

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
    let request = request("GET", "/missing-community/group/test-group")
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
async fn test_page_credits_cohosted_events_to_their_owner() {
    // Setup an upcoming event owned by another community's group
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let mut group = sample_group_full(community_id, group_id);
    group.community.name = "test-community".to_string();
    group.name = "Cohost Group".to_string();
    group.slug = "jkm2345".to_string();
    group.slug_pretty = None;
    let mut event = sample_event_summary(Uuid::new_v4());
    event.cohosts = vec![sample_event_cohost_group(group_id, "Cohost Group")];
    event.community_name = "owner-community".to_string();
    event.group_name = "Owner Group".to_string();
    event.group_slug = "def5678".to_string();
    event.slug = "ghi9abc".to_string();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_page_reads(
        &mut db,
        community_id,
        "jkm2345",
        Some(group),
        vec![event],
        vec![],
    );

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = request("GET", "/test-community/group/jkm2345")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the card credits the owner and links to the owner's community
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("Hosted by Owner Group"));
    assert!(body.contains("Co-hosted with Cohost Group"));
    assert!(body.contains("href=\"/owner-community/group/def5678/event/ghi9abc\""));
    assert!(!body.contains("href=\"/test-community/group/def5678/event/"));
    assert!(!body.contains("href=\"/test-community/group/jkm2345/event/"));
}

#[tokio::test]
async fn test_page_not_found() {
    // Setup database mock
    let community_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_page_reads(&mut db, community_id, "missing-group", None, vec![], vec![]);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = request("GET", "/test-community/group/missing-group")
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
async fn test_page_temporarily_redirects_generated_slug_to_pretty_slug() {
    // Setup a group with a pretty slug
    let community_id = Uuid::new_v4();
    let mut group = sample_group_full(community_id, Uuid::new_v4());
    group.slug = "test-group".to_string();
    group.slug_pretty = Some("pretty-group".to_string());

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_page_reads(
        &mut db,
        community_id,
        "test-group",
        Some(group),
        vec![],
        vec![],
    );

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = request("GET", "/test-community/group/test-group?utm_source=test")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::TEMPORARY_REDIRECT);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        &HeaderValue::from_static("/test-community/group/pretty-group?utm_source=test")
    );
}

#[tokio::test]
async fn test_page_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let mut group = sample_group_full(community_id, Uuid::new_v4());
    group.community.display_name = "Test Community".to_string();
    group.community.name = "test-community".to_string();
    group.description_short = Some("Group preview description".to_string());
    group.name = "Test Group".to_string();
    group.og_image_url = Some("/images/group-og.png".to_string());
    group.slug_pretty = Some("pretty-group".to_string());
    let mut hidden_sponsor = sample_group_sponsor();
    hidden_sponsor.featured = false;
    hidden_sponsor.name = "Hidden Sponsor".to_string();
    let mut featured_sponsor = sample_group_sponsor();
    featured_sponsor.featured = true;
    featured_sponsor.name = "Featured Sponsor".to_string();
    group.sponsors = vec![featured_sponsor, hidden_sponsor];

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_page_reads(
        &mut db,
        community_id,
        "pretty-group",
        Some(group),
        vec![sample_event_summary(event_id)],
        vec![sample_event_summary(event_id)],
    );

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = request("GET", "/test-community/group/pretty-group")
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
    let description =
        "Test Community community in Open Community Groups, where Open Source communities thrive.";
    let url = "https://example.test/test-community/group/pretty-group";
    let image = "https://example.test/images/og/group-og.png";
    for tag in [
        "<title>Test Group</title>".to_string(),
        format!(r#"<meta name="description" content="{description}">"#),
        format!(r#"<link rel="canonical" href="{url}">"#),
        r#"<meta property="og:title" content="Test Group">"#.to_string(),
        format!(r#"<meta property="og:url" content="{url}">"#),
        format!(r#"<meta property="og:description" content="{description}">"#),
        format!(r#"<meta property="og:image" content="{image}">"#),
        r#"<meta name="twitter:title" content="Test Group">"#.to_string(),
        format!(r#"<meta name="twitter:description" content="{description}">"#),
        format!(r#"<meta name="twitter:image" content="{image}">"#),
    ] {
        assert!(body.contains(&tag), "missing {tag}");
    }
    assert!(body.contains("Featured Sponsor"));
    assert!(!body.contains("Hidden Sponsor"));
}

#[tokio::test]
async fn test_join_group_returns_unprocessable_entity_for_rejection() {
    // Setup identifiers and a membership rejection
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager.expect_join_group().times(1).returning(|_, _, _| {
        Box::pin(async { Err(EnrollmentError::Rejected("group is not active".to_string())) })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = empty_request("POST", &group_uri(ids.group_id, "join"), ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "group is not active"
    );
}

#[tokio::test]
async fn test_join_group_success() {
    // Setup identifiers and the membership expectation
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager
        .expect_join_group()
        .times(1)
        .withf(move |cid, gid, uid| {
            *cid == ids.community_id && *gid == ids.group_id && *uid == ids.user_id
        })
        .returning(|_, _, _| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = empty_request("POST", &group_uri(ids.group_id, "join"), ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_leave_group_returns_unprocessable_entity_for_rejection() {
    // Setup identifiers and a membership rejection
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager.expect_leave_group().times(1).returning(|_, _, _| {
        Box::pin(async {
            Err(EnrollmentError::Rejected(
                "user is not a member".to_string(),
            ))
        })
    });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = empty_request("DELETE", &group_uri(ids.group_id, "leave"), ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "user is not a member"
    );
}

#[tokio::test]
async fn test_leave_group_success() {
    // Setup identifiers and the membership removal expectation
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);

    // Setup enrollment manager mock
    let mut enrollment_manager = MockEnrollmentManager::new();
    enrollment_manager
        .expect_leave_group()
        .times(1)
        .withf(move |cid, gid, uid| {
            *cid == ids.community_id && *gid == ids.group_id && *uid == ids.user_id
        })
        .returning(|_, _, _| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_enrollment_manager(enrollment_manager)
        .build()
        .await;
    let request = empty_request("DELETE", &group_uri(ids.group_id, "leave"), ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_membership_status_rejects_invalid_group_id_before_community_lookup() {
    // Resolve authentication without looking up the community
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_get_community_id_by_name().never();

    // Request membership with a malformed group identifier
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        "/test-community/group/not-a-uuid/membership",
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check path validation rejects the request before community lookup
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert!(body.contains("Invalid URL:"));
    assert!(body.contains("not-a-uuid"));
}

#[tokio::test]
async fn test_membership_status_success() {
    // Setup identifiers and the membership read
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);
    db.expect_is_group_member()
        .times(1)
        .withf(move |cid, gid, uid| {
            *cid == ids.community_id && *gid == ids.group_id && *uid == ids.user_id
        })
        .returning(|_, _, _| Ok(true));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(&group_uri(ids.group_id, "membership"), ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("application/json")
    );
    let body: serde_json::Value = from_slice(&bytes).unwrap();
    assert_eq!(body, json!({ "is_member": true }));
}

#[tokio::test]
async fn test_track_view_accepts_same_origin_request() {
    // Setup activity tracker mock
    let group_id = Uuid::new_v4();
    let mut activity_tracker = MockActivityTracker::new();
    activity_tracker
        .expect_track()
        .times(1)
        .withf(move |activity| *activity == Activity::GroupView { group_id })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(MockDB::new())
        .with_activity_tracker(activity_tracker)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = request("POST", &format!("/groups/{group_id}/views"))
        .header("origin", "https://example.test")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
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
    let request = request("POST", &format!("/groups/{}/views", Uuid::new_v4()))
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
    let request = request("POST", &format!("/groups/{}/views", Uuid::new_v4()))
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the handler rejects the request without same-origin evidence
    assert_empty_response(&parts, &bytes, StatusCode::FORBIDDEN);
}

// Helpers.

/// Expects the reads the group page always performs for `slug`: the test
/// community, the site settings and the group and event lists, which return
/// `group`, `upcoming` and `past`.
fn expect_group_page_reads(
    db: &mut MockDB,
    community_id: Uuid,
    slug: &'static str,
    group: Option<GroupFull>,
    upcoming: Vec<EventSummary>,
    past: Vec<EventSummary>,
) {
    let kinds = vec![EventKind::InPerson, EventKind::Virtual, EventKind::Hybrid];
    let past_kinds = kinds.clone();
    expect_test_community(db, community_id);
    expect_site_settings(db);
    db.expect_get_group_full_by_slug()
        .times(1)
        .withf(move |id, group_slug| *id == community_id && group_slug == slug)
        .returning(move |_, _| Ok(group.clone()));
    db.expect_get_group_upcoming_events()
        .times(1)
        .withf(move |id, group_slug, event_kinds, limit| {
            *id == community_id && group_slug == slug && *event_kinds == kinds && *limit == 9
        })
        .returning(move |_, _, _, _| Ok(upcoming.clone()));
    db.expect_get_group_past_events()
        .times(1)
        .withf(move |id, group_slug, event_kinds, limit| {
            *id == community_id && group_slug == slug && *event_kinds == past_kinds && *limit == 9
        })
        .returning(move |_, _, _, _| Ok(past.clone()));
}

/// Builds the URI of a group-scoped route of the test community.
fn group_uri(group_id: Uuid, action: &str) -> String {
    format!("/test-community/group/{group_id}/{action}")
}
