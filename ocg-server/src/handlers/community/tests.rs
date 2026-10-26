use axum::{
    body::Body,
    http::{HeaderValue, StatusCode, header::CACHE_CONTROL},
};
use uuid::Uuid;

use crate::{
    activity_tracker::{Activity, MockActivityTracker},
    db::mock::{MockDB, expect_site_settings},
    handlers::tests::*,
    router::CACHE_CONTROL_PUBLIC_SHARED,
    types::{community::CommunityStats, event::EventKind},
};

#[tokio::test]
async fn test_page_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let mut community = sample_community_full(community_id);
    community.description = "Community preview description".to_string();
    community.display_name = "Test Community".to_string();
    community.name = "test-community".to_string();
    community.og_image_url = Some("/images/community-og.png".to_string());

    // Setup database mock
    let mut db = MockDB::new();
    expect_test_community(&mut db, community_id);
    db.expect_get_community_full()
        .times(1)
        .withf(move |id| *id == community_id)
        .returning(move |_| Ok(community.clone()));
    db.expect_get_community_recently_added_groups()
        .times(1)
        .withf(move |id| *id == community_id)
        .returning(|_| Ok(vec![]));
    db.expect_get_community_upcoming_events()
        .times(1)
        .withf(move |id, kinds| {
            *id == community_id && kinds == &vec![EventKind::InPerson, EventKind::Hybrid]
        })
        .returning(|_, _| Ok(vec![]));
    db.expect_get_community_upcoming_events()
        .times(1)
        .withf(move |id, kinds| {
            *id == community_id && kinds == &vec![EventKind::Virtual, EventKind::Hybrid]
        })
        .returning(|_, _| Ok(vec![]));
    db.expect_get_community_site_stats()
        .times(1)
        .withf(move |id| *id == community_id)
        .returning(move |_| Ok(CommunityStats::default()));
    expect_site_settings(&mut db);

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = request("GET", "/test-community").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
    );
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    let description = "Open Community Groups, where Open Source communities thrive.";
    let url = "https://example.test/test-community";
    let image = "https://example.test/images/og/community-og.png";
    for tag in [
        "<title>Test Community community</title>".to_string(),
        r#"<meta name="description""#.to_string(),
        format!(r#"content="{description}">"#),
        format!(r#"<link rel="canonical" href="{url}">"#),
        r#"<meta property="og:title" content="Test Community community">"#.to_string(),
        format!(r#"<meta property="og:url" content="{url}">"#),
        format!(r#"<meta property="og:description" content="{description}">"#),
        format!(r#"<meta property="og:image" content="{image}">"#),
        r#"<meta name="twitter:title" content="Test Community community">"#.to_string(),
        format!(r#"<meta name="twitter:description" content="{description}">"#),
        format!(r#"<meta name="twitter:image" content="{image}">"#),
    ] {
        assert!(body.contains(&tag), "missing {tag}");
    }
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
    let request = request("GET", "/missing-community").body(Body::empty()).unwrap();
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
async fn test_track_view_accepts_same_origin_request() {
    // Setup activity tracker mock
    let community_id = Uuid::new_v4();
    let mut activity_tracker = MockActivityTracker::new();
    activity_tracker
        .expect_track()
        .times(1)
        .withf(move |activity| *activity == Activity::CommunityView { community_id })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(MockDB::new())
        .with_activity_tracker(activity_tracker)
        .with_server_cfg(sample_server_cfg("https://example.test"))
        .build()
        .await;
    let request = request("POST", &format!("/communities/{community_id}/views"))
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
    let request = request("POST", &format!("/communities/{}/views", Uuid::new_v4()))
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
    let request = request("POST", &format!("/communities/{}/views", Uuid::new_v4()))
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the handler rejects the request without same-origin evidence
    assert_empty_response(&parts, &bytes, StatusCode::FORBIDDEN);
}
