use anyhow::anyhow;
use axum::body::{Body, to_bytes};
use axum::http::{
    HeaderValue, Request, StatusCode,
    header::{CACHE_CONTROL, CONTENT_TYPE},
};
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    activity_tracker::{Activity, MockActivityTracker},
    db::mock::MockDB,
    handlers::tests::*,
    router::CACHE_CONTROL_PUBLIC_SHARED,
    services::notifications::MockNotificationsManager,
    templates::alliance::Stats,
    types::event::EventKind,
};

#[tokio::test]
async fn test_page_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let mut alliance = sample_alliance_full(alliance_id);
    alliance.description = "Alliance preview description".to_string();
    alliance.display_name = "Test Alliance".to_string();
    alliance.name = "test-alliance".to_string();
    alliance.og_image_url = Some("/images/alliance-og.png".to_string());

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_alliance_id_by_name()
        .times(1)
        .withf(|name| name == "test-alliance")
        .returning(move |_| Ok(Some(alliance_id)));
    db.expect_get_alliance_full()
        .times(1)
        .withf(move |id| *id == alliance_id)
        .returning(move |_| Ok(alliance.clone()));
    db.expect_get_alliance_recently_added_groups()
        .times(1)
        .withf(move |id| *id == alliance_id)
        .returning(|_| Ok(vec![]));
    db.expect_get_alliance_upcoming_events()
        .times(1)
        .withf(move |id, kinds| {
            *id == alliance_id && kinds == &vec![EventKind::InPerson, EventKind::Hybrid]
        })
        .returning(|_, _| Ok(vec![]));
    db.expect_get_alliance_upcoming_events()
        .times(1)
        .withf(move |id, kinds| {
            *id == alliance_id && kinds == &vec![EventKind::Virtual, EventKind::Hybrid]
        })
        .returning(|_, _| Ok(vec![]));
    db.expect_get_alliance_site_stats()
        .times(1)
        .withf(move |id| *id == alliance_id)
        .returning(move |_| Ok(Stats::default()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_server_cfg(sample_tracking_server_cfg())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/test-alliance")
        .body(axum::body::Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
    );
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("<title>Test Alliance alliance</title>"));
    assert!(body.contains(r#"<meta name="description""#));
    assert!(
        body.contains(r#"content="Open Alliance Groups, where Open Source alliances thrive.">"#)
    );
    assert!(body.contains(r#"<link rel="canonical" href="https://example.test/test-alliance">"#));
    assert!(body.contains(r#"<meta property="og:title" content="Test Alliance alliance">"#));
    assert!(
        body.contains(r#"<meta property="og:url" content="https://example.test/test-alliance">"#)
    );
    assert!(body.contains(
        r#"<meta property="og:description" content="Open Alliance Groups, where Open Source alliances thrive.">"#
    ));
    assert!(body.contains(
        r#"<meta property="og:image" content="https://example.test/images/og/alliance-og.png">"#
    ));
    assert!(body.contains(r#"<meta name="twitter:title" content="Test Alliance alliance">"#));
    assert!(body.contains(
        r#"<meta name="twitter:description" content="Open Alliance Groups, where Open Source alliances thrive.">"#
    ));
    assert!(body.contains(
        r#"<meta name="twitter:image" content="https://example.test/images/og/alliance-og.png">"#
    ));
    assert!(body.contains(r#"href="/test-alliance/brand""#));
    assert!(body.contains(">Brand</a>"));
}

#[tokio::test]
async fn test_brand_page_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let mut alliance = sample_alliance_full(alliance_id);
    alliance.banner_mobile_url = "/images/alliance-banner-mobile.png".to_string();
    alliance.banner_url = "/images/alliance-banner.png".to_string();
    alliance.display_name = "Test Alliance".to_string();
    alliance.logo_url = "/images/alliance-logo.png".to_string();
    alliance.name = "test-alliance".to_string();
    alliance.og_image_url = Some("/images/alliance-og.png".to_string());

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_alliance_id_by_name()
        .times(1)
        .withf(|name| name == "test-alliance")
        .returning(move |_| Ok(Some(alliance_id)));
    db.expect_get_alliance_full()
        .times(1)
        .withf(move |id| *id == alliance_id)
        .returning(move |_| Ok(alliance.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_server_cfg(sample_tracking_server_cfg())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/test-alliance/brand")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
    );
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("<title>Test Alliance brand</title>"));
    assert!(
        body.contains(r#"<link rel="canonical" href="https://example.test/test-alliance/brand">"#)
    );
    assert!(body.contains("Brand assets"));
    assert!(body.contains(r#"src="/images/alliance-logo.png""#));
    assert!(body.contains(r#"src="/images/alliance-banner.png""#));
    assert!(body.contains(r#"src="/images/alliance-banner-mobile.png""#));
    assert!(body.contains(r#"src="/images/alliance-og.png""#));
}

#[tokio::test]
async fn test_page_alliance_not_found() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_alliance_id_by_name()
        .times(1)
        .withf(|name| name == "missing-alliance")
        .returning(|_| Ok(None));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/missing-alliance")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NOT_FOUND);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8")
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
    );
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("We could not find that page"));
    assert!(body.contains("Go to home page"));
}

#[tokio::test]
async fn test_page_db_error() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_alliance_id_by_name()
        .times(1)
        .withf(|name| name == "test-alliance")
        .returning(move |_| Ok(Some(alliance_id)));
    db.expect_get_alliance_full()
        .times(1)
        .withf(move |id| *id == alliance_id)
        .returning(move |_| Ok(sample_alliance_full(alliance_id)));
    db.expect_get_alliance_recently_added_groups()
        .times(1)
        .withf(move |id| *id == alliance_id)
        .returning(|_| Ok(vec![]));
    db.expect_get_alliance_upcoming_events()
        .times(1)
        .withf(move |id, kinds| {
            *id == alliance_id && kinds == &vec![EventKind::InPerson, EventKind::Hybrid]
        })
        .returning(|_, _| Ok(vec![]));
    db.expect_get_alliance_upcoming_events()
        .times(1)
        .withf(move |id, kinds| {
            *id == alliance_id && kinds == &vec![EventKind::Virtual, EventKind::Hybrid]
        })
        .returning(|_, _| Ok(vec![]));
    db.expect_get_alliance_site_stats()
        .times(1)
        .withf(move |id| *id == alliance_id)
        .returning(move |_| Err(anyhow!("db error")));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/test-alliance")
        .body(axum::body::Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_track_view_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();

    // Setup database mock
    let db = MockDB::new();

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup activity tracker mock
    let mut activity_tracker = MockActivityTracker::new();
    activity_tracker
        .expect_track()
        .times(1)
        .withf(move |activity| *activity == Activity::AllianceView { alliance_id })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_activity_tracker(activity_tracker)
        .with_server_cfg(sample_tracking_server_cfg())
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/alliances/{alliance_id}/views"))
        .header("origin", "https://example.test")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_track_view_ignores_cross_origin_request() {
    // Setup database mock
    let db = MockDB::new();

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup activity tracker mock
    let mut activity_tracker = MockActivityTracker::new();
    activity_tracker.expect_track().times(0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_activity_tracker(activity_tracker)
        .with_server_cfg(sample_tracking_server_cfg())
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/alliances/{}/views", Uuid::new_v4()))
        .header("origin", "https://evil.test")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert!(bytes.is_empty());
}
