use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderValue, Request, StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE, COOKIE},
    },
};
use axum_login::tower_sessions::session;
use chrono::Utc;
use serde_json::{from_slice, from_value, to_value};
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    config::{MeetingsConfig, MeetingsZoomConfig},
    db::mock::MockDB,
    handlers::tests::*,
    router::CACHE_CONTROL_NO_CACHE,
    services::{
        meetings::MeetingProvider,
        notifications::{MockNotificationsManager, NotificationKind},
    },
    templates::{
        dashboard::DASHBOARD_PAGINATION_LIMIT,
        notifications::{EventCanceled, EventPublished, EventRescheduled, SpeakerWelcome},
    },
    types::event::{EventFull, EventSummary, Speaker},
    types::permissions::GroupPermission,
};

#[tokio::test]
async fn test_add_page_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
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
    let category = sample_event_category();
    let kind = sample_event_kind_summary();
    let session_kind = sample_session_kind_summary();
    let sponsor = sample_group_sponsor();
    let timezones = vec!["UTC".to_string()];

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
    db.expect_list_event_categories()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![category.clone()]));
    db.expect_list_event_kinds()
        .times(1)
        .returning(move || Ok(vec![kind.clone()]));
    db.expect_list_session_kinds()
        .times(1)
        .returning(move || Ok(vec![session_kind.clone()]));
    db.expect_list_group_sponsors()
        .times(1)
        .withf(move |id, filters, full_list| {
            *id == group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && *full_list
        })
        .returning(move |_, _, _| {
            Ok(
                crate::templates::dashboard::group::sponsors::GroupSponsorsOutput {
                    sponsors: vec![sponsor.clone()],
                    total: 1,
                },
            )
        });
    db.expect_list_timezones()
        .times(1)
        .returning(move || Ok(timezones.clone()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group/events/add")
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

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
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
    let group_events = sample_group_events(Uuid::new_v4(), group_id);

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
    db.expect_list_group_events()
        .times(1)
        .withf(move |id, filters| {
            *id == group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.past_offset == Some(0)
                && filters.upcoming_offset == Some(0)
        })
        .returning({
            let group_events = group_events.clone();
            move |_, _| Ok(group_events.clone())
        });

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group/events")
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

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_update_page_success() {
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
    let event_full = sample_event_full(community_id, event_id, group_id);
    let event_full_db = event_full.clone();
    let category = sample_event_category();
    let kind = sample_event_kind_summary();
    let session_kind = sample_session_kind_summary();
    let sponsor = sample_group_sponsor();
    let timezones = vec!["UTC".to_string()];

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
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full_db.clone()));
    db.expect_list_event_categories()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![category.clone()]));
    db.expect_list_event_kinds()
        .times(1)
        .returning(move || Ok(vec![kind.clone()]));
    db.expect_list_session_kinds()
        .times(1)
        .returning(move || Ok(vec![session_kind.clone()]));
    db.expect_list_group_sponsors()
        .times(1)
        .withf(move |id, filters, full_list| {
            *id == group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && *full_list
        })
        .returning(move |_, _, _| {
            Ok(
                crate::templates::dashboard::group::sponsors::GroupSponsorsOutput {
                    sponsors: vec![sponsor.clone()],
                    total: 1,
                },
            )
        });
    db.expect_list_timezones()
        .times(1)
        .returning(move || Ok(timezones.clone()));
    db.expect_list_event_approved_cfs_submissions()
        .times(1)
        .withf(move |eid| *eid == event_id)
        .returning(|_| Ok(vec![]));
    db.expect_list_cfs_submission_statuses_for_review()
        .times(1)
        .returning(|| Ok(vec![]));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/dashboard/group/events/{event_id}/update"))
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

#[tokio::test]
async fn test_details_success() {
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
    let event_full = sample_event_full(community_id, event_id, group_id);
    let event_full_db = event_full.clone();

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
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full_db.clone()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/dashboard/group/events/{event_id}/details"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let payload: EventFull = from_slice(&bytes).unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("application/json"),
    );
    assert_eq!(to_value(payload).unwrap(), to_value(event_full).unwrap());
}

#[tokio::test]
async fn test_add_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
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
    let event_form = sample_event_form();
    let body = serde_qs::to_string(&event_form).unwrap();

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
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_add_event()
        .times(1)
        .withf(move |id, event, cfg_max_participants| {
            *id == group_id
                && event.name == event_form.name
                && cfg_max_participants.get(&MeetingProvider::Zoom) == Some(&100)
        })
        .returning(move |_, _, _| Ok(Uuid::new_v4()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup meetings config with Zoom
    let meetings_cfg = MeetingsConfig {
        zoom: Some(MeetingsZoomConfig {
            account_id: "test-account".to_string(),
            client_id: "test-client".to_string(),
            client_secret: "test-secret".to_string(),
            enabled: true,
            host_pool_users: vec!["host@example.com".to_string()],
            max_participants: 100,
            max_simultaneous_meetings_per_host: 1,
            webhook_secret_token: "test-token".to_string(),
        }),
    };

    // Setup router with meetings config and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_meetings_cfg(meetings_cfg)
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri("/dashboard/group/events/add")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::CREATED);
    assert_eq!(
        parts.headers.get("HX-Trigger").unwrap(),
        &HeaderValue::from_static("refresh-group-dashboard-table"),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_add_invalid_body() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
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
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("POST")
        .uri("/dashboard/group/events/add")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from("invalid"))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(!bytes.is_empty());
}

#[allow(clippy::too_many_lines)]
#[tokio::test]
async fn test_cancel_success() {
    // Setup identifiers and data structures
    let attendee_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let speaker_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );
    let event_summary = sample_event_summary(event_id, group_id);
    let event_full = EventFull {
        speakers: vec![Speaker {
            featured: false,
            user: sample_template_user_with_id(speaker_id),
        }],
        ..sample_event_full(community_id, event_id, group_id)
    };
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
        .returning(move |_, _, _| Ok(event_summary.clone()));
    db.expect_cancel_event()
        .times(1)
        .withf(move |id, eid| *id == group_id && *eid == event_id)
        .returning(move |_, _| Ok(()));
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full.clone()));
    db.expect_list_event_attendees_ids()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .returning(move |_, _| Ok(vec![attendee_id]));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventCanceled)
                && notification.recipients.len() == 2
                && notification.recipients.contains(&attendee_id)
                && notification.recipients.contains(&speaker_id)
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventCanceled>(value.clone())
                        .map(|template| {
                            template.link == "/test/group/npq6789/event/abc1234"
                                && template.theme.primary_color
                                    == site_settings_for_notifications.theme.primary_color
                        })
                        .unwrap_or(false)
                })
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/group/events/{event_id}/cancel"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get("HX-Location").unwrap(),
        &HeaderValue::from_static(r#"{"path":"/dashboard/group?tab=events", "target":"body"}"#,),
    );
    assert!(bytes.is_empty());
}

#[allow(clippy::too_many_lines)]
#[tokio::test]
async fn test_publish_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let member_id = Uuid::new_v4();
    let speaker_id = Uuid::new_v4();
    let team_member_id = Uuid::new_v4();
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
    let unpublished_event = EventSummary {
        published: false,
        ..sample_event_summary(event_id, group_id)
    };
    let event_full = EventFull {
        speakers: vec![Speaker {
            featured: false,
            user: sample_template_user_with_id(speaker_id),
        }],
        ..sample_event_full(community_id, event_id, group_id)
    };
    let site_settings = sample_site_settings();
    let site_settings_for_member_notification = site_settings.clone();
    let site_settings_for_speaker_notification = site_settings.clone();
    let mut expected_member_recipients = vec![member_id, team_member_id];
    expected_member_recipients.sort();

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
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(unpublished_event.clone()));
    db.expect_publish_event()
        .times(1)
        .withf(move |gid, eid, uid| *gid == group_id && *eid == event_id && *uid == user_id)
        .returning(move |_, _, _| Ok(()));
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full.clone()));
    db.expect_list_group_members_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![member_id]));
    db.expect_list_group_team_members_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![team_member_id]));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventPublished)
                && notification.recipients == expected_member_recipients
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventPublished>(value.clone())
                        .map(|template| {
                            template.theme.primary_color
                                == site_settings_for_member_notification.theme.primary_color
                        })
                        .unwrap_or(false)
                })
        })
        .returning(|_| Box::pin(async { Ok(()) }));
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::SpeakerWelcome)
                && notification.recipients == vec![speaker_id]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<SpeakerWelcome>(value.clone())
                        .map(|template| {
                            template.theme.primary_color
                                == site_settings_for_speaker_notification.theme.primary_color
                        })
                        .unwrap_or(false)
                })
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/group/events/{event_id}/publish"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get("HX-Trigger").unwrap(),
        &HeaderValue::from_static("refresh-group-dashboard-table"),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_publish_already_published_no_notification() {
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
    // Event is already published, so no notification should be sent
    let already_published_event = EventSummary {
        published: true,
        ..sample_event_summary(event_id, group_id)
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
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(already_published_event.clone()));
    db.expect_publish_event()
        .times(1)
        .withf(move |gid, eid, uid| *gid == group_id && *eid == event_id && *uid == user_id)
        .returning(move |_, _, _| Ok(()));

    // Setup notifications manager mock (no enqueue expected)
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/group/events/{event_id}/publish"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get("HX-Trigger").unwrap(),
        &HeaderValue::from_static("refresh-group-dashboard-table"),
    );
    assert!(bytes.is_empty());
}

#[allow(clippy::too_many_lines)]
#[tokio::test]
async fn test_publish_speakers_only() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let speaker_id = Uuid::new_v4();
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
    let unpublished_event = EventSummary {
        published: false,
        ..sample_event_summary(event_id, group_id)
    };
    let event_full = EventFull {
        speakers: vec![Speaker {
            featured: false,
            user: sample_template_user_with_id(speaker_id),
        }],
        ..sample_event_full(community_id, event_id, group_id)
    };
    let site_settings = sample_site_settings();
    let site_settings_for_speaker_notification = site_settings.clone();

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
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(unpublished_event.clone()));
    db.expect_publish_event()
        .times(1)
        .withf(move |gid, eid, uid| *gid == group_id && *eid == event_id && *uid == user_id)
        .returning(move |_, _, _| Ok(()));
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full.clone()));
    // No group members
    db.expect_list_group_members_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![]));
    db.expect_list_group_team_members_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![]));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));

    // Setup notifications manager mock - only speaker notification expected
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::SpeakerWelcome)
                && notification.recipients == vec![speaker_id]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<SpeakerWelcome>(value.clone())
                        .map(|template| {
                            template.theme.primary_color
                                == site_settings_for_speaker_notification.theme.primary_color
                        })
                        .unwrap_or(false)
                })
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/group/events/{event_id}/publish"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get("HX-Trigger").unwrap(),
        &HeaderValue::from_static("refresh-group-dashboard-table"),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_delete_success() {
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
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_delete_event()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .returning(move |_, _| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!("/dashboard/group/events/{event_id}/delete"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get("HX-Trigger").unwrap(),
        &HeaderValue::from_static("refresh-group-dashboard-table"),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_unpublish_success() {
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
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_unpublish_event()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .returning(move |_, _| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/group/events/{event_id}/unpublish"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get("HX-Trigger").unwrap(),
        &HeaderValue::from_static("refresh-group-dashboard-table"),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_update_success() {
    // Setup identifiers and data structures
    let attendee_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let speaker_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );
    let before = sample_event_summary(event_id, group_id);
    let after = EventSummary {
        starts_at: before.starts_at.map(|ts| ts + chrono::Duration::minutes(30)),
        ..before.clone()
    };
    let event_full = EventFull {
        speakers: vec![Speaker {
            featured: false,
            user: sample_template_user_with_id(speaker_id),
        }],
        ..sample_event_full(community_id, event_id, group_id)
    };
    let site_settings = sample_site_settings();
    let site_settings_for_notifications = site_settings.clone();
    let event_form = sample_event_form();
    let body = serde_qs::to_string(&event_form).unwrap();

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
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_get_event_summary()
        .times(2)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning({
            let mut first_call = true;
            move |_, _, _| {
                let result = if first_call {
                    first_call = false;
                    before.clone()
                } else {
                    after.clone()
                };
                Ok(result)
            }
        });
    db.expect_update_event()
        .times(1)
        .withf(move |gid, eid, event, cfg_max_participants| {
            *gid == group_id
                && *eid == event_id
                && event.get("name").and_then(|v| v.as_str()) == Some(event_form.name.as_str())
                && cfg_max_participants.is_empty()
        })
        .returning(move |_, _, _, _| Ok(()));
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full.clone()));
    db.expect_list_event_attendees_ids()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .returning(move |_, _| Ok(vec![attendee_id]));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventRescheduled)
                && notification.recipients.len() == 2
                && notification.recipients.contains(&attendee_id)
                && notification.recipients.contains(&speaker_id)
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventRescheduled>(value.clone())
                        .map(|template| {
                            template.link == "/test/group/npq6789/event/abc1234"
                                && template.theme.primary_color
                                    == site_settings_for_notifications.theme.primary_color
                        })
                        .unwrap_or(false)
                })
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/group/events/{event_id}/update"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get("HX-Trigger").unwrap(),
        &HeaderValue::from_static("refresh-group-dashboard-table"),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_update_no_notification_when_shift_too_small() {
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
    let before = sample_event_summary(event_id, group_id);
    // Shift by only 10 minutes (below MIN_RESCHEDULE_SHIFT of 15 minutes)
    let after = EventSummary {
        starts_at: before.starts_at.map(|ts| ts + chrono::Duration::minutes(10)),
        ..before.clone()
    };
    let event_form = sample_event_form();
    let body = serde_qs::to_string(&event_form).unwrap();

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
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_get_event_summary()
        .times(2)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning({
            let mut first_call = true;
            move |_, _, _| {
                let result = if first_call {
                    first_call = false;
                    before.clone()
                } else {
                    after.clone()
                };
                Ok(result)
            }
        });
    db.expect_update_event()
        .times(1)
        .withf(move |gid, eid, event, cfg_max_participants| {
            *gid == group_id
                && *eid == event_id
                && event.get("name").and_then(|v| v.as_str()) == Some(event_form.name.as_str())
                && cfg_max_participants.is_empty()
        })
        .returning(move |_, _, _, _| Ok(()));

    // Setup notifications manager mock (no enqueue expected - shift too small)
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/group/events/{event_id}/update"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get("HX-Trigger").unwrap(),
        &HeaderValue::from_static("refresh-group-dashboard-table"),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_update_no_notification_when_unpublished() {
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
    // Event is unpublished, so no reschedule notification should be sent
    let before = EventSummary {
        published: false,
        ..sample_event_summary(event_id, group_id)
    };
    // Significant reschedule (30 minutes), but event is unpublished
    let after = EventSummary {
        starts_at: before.starts_at.map(|ts| ts + chrono::Duration::minutes(30)),
        ..before.clone()
    };
    let event_form = sample_event_form();
    let body = serde_qs::to_string(&event_form).unwrap();

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
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_get_event_summary()
        .times(2)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning({
            let mut first_call = true;
            move |_, _, _| {
                let result = if first_call {
                    first_call = false;
                    before.clone()
                } else {
                    after.clone()
                };
                Ok(result)
            }
        });
    db.expect_update_event()
        .times(1)
        .withf(move |gid, eid, event, cfg_max_participants| {
            *gid == group_id
                && *eid == event_id
                && event.get("name").and_then(|v| v.as_str()) == Some(event_form.name.as_str())
                && cfg_max_participants.is_empty()
        })
        .returning(move |_, _, _, _| Ok(()));

    // Setup notifications manager mock (no enqueue expected - event unpublished)
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/group/events/{event_id}/update"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get("HX-Trigger").unwrap(),
        &HeaderValue::from_static("refresh-group-dashboard-table"),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_update_past_event_success() {
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
    let past_event = {
        let past_time = Utc::now() - chrono::Duration::hours(2);
        EventSummary {
            ends_at: Some(past_time + chrono::Duration::hours(1)),
            starts_at: Some(past_time),
            ..sample_event_summary(event_id, group_id)
        }
    };
    let mut past_event_form = sample_event_form();
    past_event_form.description = "Updated past event description".to_string();
    past_event_form.name = "Past Event Updated".to_string();
    let body = serde_qs::to_string(&past_event_form).unwrap();

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
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(past_event.clone()));
    db.expect_update_event()
        .times(1)
        .withf(move |gid, eid, event, cfg_max_participants| {
            *gid == group_id
                && *eid == event_id
                && event.get("description").and_then(|v| v.as_str()) == Some("Updated past event description")
                && event.get("name").and_then(|v| v.as_str()) == Some("Past Event Updated")
                && cfg_max_participants.is_empty()
        })
        .returning(move |_, _, _, _| Ok(()));

    // Setup notifications manager mock (no expectations - past events don't notify)
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!("/dashboard/group/events/{event_id}/update"))
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::NO_CONTENT);
    assert_eq!(
        parts.headers.get("HX-Trigger").unwrap(),
        &HeaderValue::from_static("refresh-group-dashboard-table"),
    );
    assert!(bytes.is_empty());
}
