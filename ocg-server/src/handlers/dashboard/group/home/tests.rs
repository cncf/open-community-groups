use axum::{
    body::{Body, to_bytes},
    http::{Request, StatusCode, header::COOKIE},
};
use axum_login::tower_sessions::session;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::{dashboard::common::BookExchangeMember, mock::MockDB},
    handlers::tests::*,
    services::notifications::MockNotificationsManager,
    templates::dashboard::{DASHBOARD_PAGINATION_LIMIT, group::coffee_meet::CoffeeMeetSubscriber},
    types::permissions::GroupPermission,
};

#[tokio::test]
async fn test_page_analytics_tab_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(alliance_id),
        Some(group_id),
    );
    let groups = sample_user_groups_by_alliance(alliance_id, group_id);
    let stats = sample_group_stats();

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
            *cid == alliance_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_get_group_full()
        .times(1)
        .withf(move |cid, gid| *cid == alliance_id && *gid == group_id)
        .returning(move |_, _| Ok(sample_group_full(alliance_id, group_id)));
    db.expect_get_group_stats()
        .times(1)
        .withf(move |cid, gid| *cid == alliance_id && *gid == group_id)
        .returning(move |_, _| Ok(stats.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group?tab=analytics")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_page_coffee_meet_tab_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(alliance_id),
        Some(group_id),
    );
    let groups = sample_user_groups_by_alliance(alliance_id, group_id);
    let subscribers = vec![CoffeeMeetSubscriber {
        user_id,
        username: "subscriber".to_string(),
        name: Some("Coffee Subscriber".to_string()),
        photo_url: None,
        frequency: "monthly".to_string(),
        next_suggestion_at: chrono::Utc::now(),
        last_suggestion_at: None,
        suggestions_total: 0,
    }];

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
            *cid == alliance_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == alliance_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::MembersWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_list_group_coffee_meet_subscribers()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(subscribers.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group?tab=coffee-meet")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("CoffeeMeet"));
    assert!(body.contains("Coffee Subscriber"));
}

#[tokio::test]
async fn test_page_book_exchange_tab_allows_read_only_group_member() {
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let groups = sample_user_groups_by_alliance(alliance_id, group_id);
    let member = sample_book_exchange_member(alliance_id, group_id);

    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, alliance_id, group_id);
    expect_group_permission(
        &mut db,
        alliance_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == alliance_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::SettingsWrite
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_list_book_exchange_members()
        .times(1)
        .withf(move |cid, gid| *cid == alliance_id && *gid == Some(group_id))
        .returning(move |_, _| Ok(vec![member.clone()]));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group?tab=book-exchange")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let body = std::str::from_utf8(&bytes).unwrap();

    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains("The Pragmatic Programmer"));
    assert!(body.contains("Contact details are only visible to group managers."));
    assert!(!body.contains("book-lover@example.com"));
}

#[tokio::test]
async fn test_page_events_tab_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(alliance_id),
        Some(group_id),
    );
    let groups = sample_user_groups_by_alliance(alliance_id, group_id);
    let group_events = sample_group_events(event_id, group_id);

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
            *cid == alliance_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == alliance_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_list_group_events()
        .times(1)
        .withf(move |id, filters| {
            *id == group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.past_offset == Some(0)
                && filters.upcoming_offset == Some(0)
        })
        .returning(move |_, _| Ok(group_events.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group?tab=events")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

fn sample_book_exchange_member(alliance_id: Uuid, group_id: Uuid) -> BookExchangeMember {
    BookExchangeMember {
        user_id: Uuid::new_v4(),
        username: "book-lover".to_string(),
        group_id,
        group_name: "GOUP Builders".to_string(),
        alliance_id,
        alliance_display_name: "GOUP".to_string(),
        book_exchange_books: Some("The Pragmatic Programmer".to_string()),
        city: Some("Phoenix".to_string()),
        company: Some("GOUP".to_string()),
        country: Some("US".to_string()),
        email: Some("book-lover@example.com".to_string()),
        name: Some("Book Lover".to_string()),
        photo_url: None,
        title: Some("Builder".to_string()),
    }
}

#[tokio::test]
async fn test_page_logs_tab_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let groups = sample_user_groups_by_alliance(alliance_id, group_id);
    let output = sample_audit_logs_output();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(alliance_id),
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
            *cid == alliance_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_list_group_audit_logs()
        .times(1)
        .withf(move |gid, filters| {
            *gid == group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && filters.sort.as_deref() == Some("created-desc")
        })
        .returning(move |_, _| Ok(output.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group?tab=logs")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_page_members_tab_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(alliance_id),
        Some(group_id),
    );
    let groups = sample_user_groups_by_alliance(alliance_id, group_id);
    let group = sample_group_summary(group_id);
    let member = sample_group_member();
    let output = crate::templates::dashboard::group::members::GroupMembersOutput {
        members: vec![member.clone()],
        total: 1,
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
            *cid == alliance_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == alliance_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::MembersWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_list_group_members()
        .times(1)
        .withf(move |id, viewer_id, can_manage_members, filters| {
            *id == group_id
                && *viewer_id == user_id
                && *can_manage_members
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _, _, _| Ok(output.clone()));
    db.expect_list_group_join_requests()
        .times(1)
        .withf(move |id| *id == group_id)
        .returning(|_| Ok(Vec::new()));
    db.expect_get_group_summary()
        .times(1)
        .withf(move |cid, gid| *cid == alliance_id && *gid == group_id)
        .returning(move |_, _| Ok(group.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group?tab=members")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("name=\"subject\""));
    assert!(body.contains("value=\"Test Group\""));
}

#[tokio::test]
async fn test_page_settings_tab_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(alliance_id),
        Some(group_id),
    );
    let groups = sample_user_groups_by_alliance(alliance_id, group_id);
    let group_full = sample_group_full(alliance_id, group_id);
    let category = sample_group_category();
    let region = sample_group_region();

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
            *cid == alliance_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == alliance_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::SettingsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_get_group_full()
        .times(1)
        .withf(move |cid, gid| *cid == alliance_id && *gid == group_id)
        .returning(move |_, _| Ok(group_full.clone()));
    db.expect_list_group_categories()
        .times(1)
        .withf(move |cid| *cid == alliance_id)
        .returning(move |_| Ok(vec![category.clone()]));
    db.expect_list_regions()
        .times(1)
        .withf(move |cid| *cid == alliance_id)
        .returning(move |_| Ok(vec![region.clone()]));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group?tab=settings")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_page_sponsors_tab_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(alliance_id),
        Some(group_id),
    );
    let groups = sample_user_groups_by_alliance(alliance_id, group_id);
    let sponsor = sample_group_sponsor();
    let output = crate::templates::dashboard::group::sponsors::GroupSponsorsOutput {
        sponsors: vec![sponsor.clone()],
        total: 1,
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
            *cid == alliance_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == alliance_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::SponsorsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_list_group_sponsors()
        .times(1)
        .withf(move |id, filters, full_list| {
            *id == group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && !*full_list
        })
        .returning(move |_, _, _| Ok(output.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group?tab=sponsors")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_page_team_tab_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(alliance_id),
        Some(group_id),
    );
    let groups = sample_user_groups_by_alliance(alliance_id, group_id);
    let team_member = sample_team_member(true);
    let role = sample_group_role_summary();
    let members = vec![team_member.clone(), sample_team_member(false)];
    let output = crate::templates::dashboard::group::team::GroupTeamOutput {
        members: members.clone(),
        total: members.len(),
        total_accepted: 1,
        total_admins_accepted: 1,
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
            *cid == alliance_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == alliance_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::TeamWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_list_group_team_members()
        .times(1)
        .withf(move |id, filters| {
            *id == group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(output.clone()));
    db.expect_list_group_roles()
        .times(1)
        .returning(move || Ok(vec![role.clone()]));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group?tab=team")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}
