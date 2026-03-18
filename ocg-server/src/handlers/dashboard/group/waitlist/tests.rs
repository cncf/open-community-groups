use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderValue, Request, StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE, COOKIE},
    },
};
use axum_login::tower_sessions::session;
use chrono::{TimeZone, Utc};
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    router::CACHE_CONTROL_NO_CACHE,
    services::notifications::MockNotificationsManager,
    templates::{
        dashboard::DASHBOARD_PAGINATION_LIMIT,
        dashboard::group::waitlist::{WaitlistEntry, WaitlistOutput},
    },
    types::permissions::GroupPermission,
};

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );
    let waitlist_entry = sample_waitlist_entry();
    let event = sample_event_summary(event_id, group_id);
    let output = WaitlistOutput {
        total: 1,
        waitlist: vec![waitlist_entry],
    };

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
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id && *gid == group_id && *uid == user_id && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_search_event_waitlist()
        .times(1)
        .withf(move |gid, filters| {
            *gid == group_id
                && filters.event_id == event_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/dashboard/group/events/{event_id}/waitlist"))
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
        &HeaderValue::from_static("text/html; charset=utf-8"),
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_NO_CACHE),
    );
    assert!(!bytes.is_empty());
}

// Helpers.

fn sample_waitlist_entry() -> WaitlistEntry {
    WaitlistEntry {
        created_at: Utc.with_ymd_and_hms(2024, 1, 1, 12, 0, 0).unwrap(),
        user_id: Uuid::new_v4(),
        username: "waitlisted-user".to_string(),

        company: Some("Example".to_string()),
        name: Some("Waitlisted User".to_string()),
        photo_url: Some("https://example.test/avatar.png".to_string()),
        title: Some("Engineer".to_string()),
    }
}
