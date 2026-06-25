use anyhow::anyhow;
use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderValue, Request, StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE, COOKIE, LOCATION},
    },
};
use axum_login::tower_sessions::session;
use serde_json::{from_slice, json};
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    activity_tracker::{Activity, MockActivityTracker},
    db::mock::MockDB,
    handlers::tests::*,
    router::CACHE_CONTROL_PUBLIC_SHARED,
    services::notifications::{MockNotificationsManager, NotificationKind},
    templates::notifications::GroupWelcome,
    types::event::EventKind,
};

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
        .uri("/missing-alliance/group/test-group")
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
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_alliance_id_by_name()
        .times(1)
        .withf(|name| name == "test-alliance")
        .returning(move |_| Ok(Some(alliance_id)));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_get_group_full_by_slug()
        .times(1)
        .withf(move |id, slug| *id == alliance_id && slug == "test-group")
        .returning(move |_, _| Ok(Some(sample_group_full(alliance_id, group_id))));
    db.expect_get_group_past_events()
        .times(1)
        .withf(move |id, slug, kinds, limit| {
            *id == alliance_id
                && slug == "test-group"
                && kinds == &vec![EventKind::InPerson, EventKind::Virtual, EventKind::Hybrid]
                && *limit == 9
        })
        .returning(move |_, _, _, _| Err(anyhow!("db error")));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/test-alliance/group/test-group")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_page_not_found() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_alliance_id_by_name()
        .times(1)
        .withf(|name| name == "test-alliance")
        .returning(move |_| Ok(Some(alliance_id)));
    db.expect_get_group_full_by_slug()
        .times(1)
        .withf(move |id, slug| *id == alliance_id && slug == "missing-group")
        .returning(move |_, _| Ok(None));
    db.expect_get_group_upcoming_events()
        .times(1)
        .withf(move |id, slug, kinds, limit| {
            *id == alliance_id
                && slug == "missing-group"
                && kinds == &vec![EventKind::InPerson, EventKind::Virtual, EventKind::Hybrid]
                && *limit == 9
        })
        .returning(move |_, _, _, _| Ok(vec![]));
    db.expect_get_group_past_events()
        .times(1)
        .withf(move |id, slug, kinds, limit| {
            *id == alliance_id
                && slug == "missing-group"
                && kinds == &vec![EventKind::InPerson, EventKind::Virtual, EventKind::Hybrid]
                && *limit == 9
        })
        .returning(move |_, _, _, _| Ok(vec![]));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/test-alliance/group/missing-group")
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
async fn test_page_temporarily_redirects_generated_slug_to_pretty_slug() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let mut group = sample_group_full(alliance_id, group_id);
    group.slug = "test-group".to_string();
    group.slug_pretty = Some("pretty-group".to_string());

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_alliance_id_by_name()
        .times(1)
        .withf(|name| name == "test-alliance")
        .returning(move |_| Ok(Some(alliance_id)));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_get_group_full_by_slug()
        .times(1)
        .withf(move |id, slug| *id == alliance_id && slug == "test-group")
        .returning(move |_, _| Ok(Some(group.clone())));
    db.expect_get_group_upcoming_events()
        .times(1)
        .returning(move |_, _, _, _| Ok(vec![]));
    db.expect_get_group_past_events()
        .times(1)
        .returning(move |_, _, _, _| Ok(vec![]));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/test-alliance/group/test-group?utm_source=test")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();

    // Check response matches expectations
    assert_eq!(response.status(), StatusCode::TEMPORARY_REDIRECT);
    assert_eq!(
        response.headers().get(LOCATION).unwrap(),
        &HeaderValue::from_static("/test-alliance/group/pretty-group?utm_source=test")
    );
}

#[tokio::test]
async fn test_page_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let mut group = sample_group_full(alliance_id, group_id);
    group.alliance.display_name = "Test Alliance".to_string();
    group.alliance.name = "test-alliance".to_string();
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
    db.expect_get_alliance_id_by_name()
        .times(1)
        .withf(|name| name == "test-alliance")
        .returning(move |_| Ok(Some(alliance_id)));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_get_group_full_by_slug()
        .times(1)
        .withf(move |id, slug| *id == alliance_id && slug == "pretty-group")
        .returning(move |_, _| Ok(Some(group.clone())));
    db.expect_get_group_upcoming_events()
        .times(1)
        .withf(move |id, slug, kinds, limit| {
            *id == alliance_id
                && slug == "pretty-group"
                && kinds == &vec![EventKind::InPerson, EventKind::Virtual, EventKind::Hybrid]
                && *limit == 9
        })
        .returning(move |_, _, _, _| Ok(vec![sample_event_summary(event_id, group_id)]));
    db.expect_get_group_past_events()
        .times(1)
        .withf(move |id, slug, kinds, limit| {
            *id == alliance_id
                && slug == "pretty-group"
                && kinds == &vec![EventKind::InPerson, EventKind::Virtual, EventKind::Hybrid]
                && *limit == 9
        })
        .returning(move |_, _, _, _| Ok(vec![sample_event_summary(event_id, group_id)]));
    expect_empty_group_home_previews(&mut db, group_id);

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_server_cfg(sample_tracking_server_cfg())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/test-alliance/group/pretty-group")
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
    assert!(body.contains("<title>Test Group</title>"));
    assert!(body.contains("Member spotlights"));
    assert!(body.contains("Group store"));
    assert!(body.contains(
        r#"<meta name="description" content="Test Alliance alliance in Open Alliance Groups, where Open Source alliances thrive.">"#
    ));
    assert!(body.contains(
        r#"<link rel="canonical" href="https://example.test/test-alliance/group/pretty-group">"#
    ));
    assert!(body.contains(r#"<meta property="og:title" content="Test Group">"#));
    assert!(body.contains(
        r#"<meta property="og:url" content="https://example.test/test-alliance/group/pretty-group">"#
    ));
    assert!(body.contains(
        r#"<meta property="og:description" content="Test Alliance alliance in Open Alliance Groups, where Open Source alliances thrive.">"#
    ));
    assert!(body.contains(
        r#"<meta property="og:image" content="https://example.test/images/og/group-og.png">"#
    ));
    assert!(body.contains(r#"<meta name="twitter:title" content="Test Group">"#));
    assert!(body.contains(
        r#"<meta name="twitter:description" content="Test Alliance alliance in Open Alliance Groups, where Open Source alliances thrive.">"#
    ));
    assert!(body.contains(
        r#"<meta name="twitter:image" content="https://example.test/images/og/group-og.png">"#
    ));
}

fn expect_empty_group_home_previews(db: &mut MockDB, group_id: Uuid) {
    db.expect_list_group_member_spotlights()
        .times(1)
        .withf(move |id, include_unpublished| *id == group_id && !*include_unpublished)
        .returning(|_, _| Ok(vec![]));
    db.expect_list_group_store_items()
        .times(1)
        .withf(move |id, include_inactive| *id == group_id && !*include_inactive)
        .returning(|_, _| Ok(vec![]));
}

#[tokio::test]
async fn test_join_group_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let site_settings = sample_site_settings();
    let site_settings_for_notifications = site_settings.clone();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_get_alliance_id_by_name()
        .times(1)
        .withf(|name| name == "test-alliance")
        .returning(move |_| Ok(Some(alliance_id)));
    db.expect_join_group()
        .times(1)
        .withf(move |id, gid, uid| *id == alliance_id && *gid == group_id && *uid == user_id)
        .returning(|_, _, _| Ok(()));
    let mut notification_group = sample_group_summary(group_id);
    notification_group.slug_pretty = Some("pretty-group".to_string());
    db.expect_get_group_summary()
        .times(1)
        .withf(move |cid, gid| *cid == alliance_id && *gid == group_id)
        .returning(move |_, _| Ok(notification_group.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::GroupWelcome)
                && notification.recipients == vec![user_id]
                && notification.template_data.as_ref().is_some_and(|data| {
                    serde_json::from_value::<GroupWelcome>(data.clone()).is_ok_and(|welcome| {
                        welcome.group.group_id == group_id
                            && welcome.link == "/test-alliance/group/pretty-group"
                            && welcome.theme.primary_color
                                == site_settings_for_notifications.theme.primary_color
                    })
                })
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/test-alliance/group/{group_id}/join"))
        .header(COOKIE, format!("id={session_id}"))
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
async fn test_leave_group_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_get_alliance_id_by_name()
        .times(1)
        .withf(|name| name == "test-alliance")
        .returning(move |_| Ok(Some(alliance_id)));
    db.expect_leave_group()
        .times(1)
        .withf(move |id, gid, uid| *id == alliance_id && *gid == group_id && *uid == user_id)
        .returning(|_, _, _| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!("/test-alliance/group/{group_id}/leave"))
        .header(COOKIE, format!("id={session_id}"))
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
async fn test_membership_status_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_get_alliance_id_by_name()
        .times(1)
        .withf(|name| name == "test-alliance")
        .returning(move |_| Ok(Some(alliance_id)));
    db.expect_is_group_member()
        .times(1)
        .withf(move |id, gid, uid| *id == alliance_id && *gid == group_id && *uid == user_id)
        .returning(|_, _, _| Ok(true));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/test-alliance/group/{group_id}/membership"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

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
async fn test_track_view_success() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();

    // Setup database mock
    let db = MockDB::new();

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup activity tracker mock
    let mut activity_tracker = MockActivityTracker::new();
    activity_tracker
        .expect_track()
        .times(1)
        .withf(move |activity| *activity == Activity::GroupView { group_id })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_activity_tracker(activity_tracker)
        .with_server_cfg(sample_tracking_server_cfg())
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/groups/{group_id}/views"))
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
        .uri(format!("/groups/{}/views", Uuid::new_v4()))
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
