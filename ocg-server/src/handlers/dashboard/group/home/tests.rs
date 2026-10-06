use axum::{
    body::{Body, to_bytes},
    http::{Request, StatusCode, header::COOKIE},
};
use axum_login::tower_sessions::session;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    services::notifications::MockNotificationsManager,
    types::{
        dashboard::{
            DASHBOARD_PAGINATION_LIMIT, common::AuditLogSort, group::cohosts::CohostedEventsOutput,
        },
        inbox::InboxConversationsOutput,
        payments::GroupExternalPaymentsContext,
        permissions::GroupPermission::{self, CheckInsWrite, InboxWrite},
    },
};

#[tokio::test]
async fn test_page_analytics_tab_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let groups = sample_user_groups_by_community(community_id, group_id);
    let stats = sample_group_stats();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            (*cid, *gid, *uid, permission) == (community_id, group_id, user_id, &CheckInsWrite)
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::BadgesWrite
        })
        .returning(|_, _, _, _| Ok(false));
    expect_inbox_permission_denied(&mut db, community_id, group_id, user_id, 1);
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_get_group_stats()
        .times(1)
        .withf(move |cid, gid, include_subgroups| {
            *cid == community_id && *gid == group_id && !*include_subgroups
        })
        .returning(move |_, _, _| Ok(stats.clone()));
    db.expect_group_has_active_subgroups()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(false));
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
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(!body.contains("tab=artwork"));
    assert!(!body.contains("tab=awards"));
    assert!(!body.contains("tab=badges"));
    assert!(!body.contains("id-prefix=\"mobile-community\""));
    assert!(!body.contains("id-prefix=\"mobile-group\""));
    assert!(body.contains("tab=refunds"));
    assert!(body.contains("hx-get=\"/dashboard/group/analytics\""));
}

#[tokio::test]
async fn test_page_badge_tabs_require_management_permission() {
    // Setup a readable group session without badge-management access
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
    let groups = sample_user_groups_by_community(community_id, group_id);

    // Require every protected tab to stop before loading its page data
    let mut db = MockDB::new();
    db.expect_user_has_group_permission()
        .times(3)
        .withf(move |cid, gid, uid, permission| {
            (*cid, *gid, *uid, permission) == (community_id, group_id, user_id, &CheckInsWrite)
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_user_has_group_permission()
        .times(3)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::BadgesWrite
        })
        .returning(|_, _, _, _| Ok(false));
    expect_inbox_permission_denied(&mut db, community_id, group_id, user_id, 3);
    db.expect_get_session()
        .times(3)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(3)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_group_permission()
        .times(3)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_list_user_groups()
        .times(3)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_get_site_settings()
        .times(3)
        .returning(|| Ok(sample_site_settings()));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;

    // Request each badge-management tab through the full dashboard route
    for tab in ["artwork", "awards", "badges"] {
        let response = router
            .clone()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri(format!("/dashboard/group?tab={tab}"))
                    .header(COOKIE, format!("id={session_id}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        // Check unauthorized users cannot open a hidden badge tab directly
        assert_eq!(response.status(), StatusCode::FORBIDDEN);
    }
}

#[tokio::test]
async fn test_page_check_in_tab_falls_back_without_management_permission() {
    // Setup a readable group session without check-in management access
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let groups = sample_user_groups_by_community(community_id, group_id);

    // Setup permission, selector, and fallback settings expectations
    let mut db = MockDB::new();
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            (*cid, *gid, *uid, permission) == (community_id, group_id, user_id, &CheckInsWrite)
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::BadgesWrite
        })
        .returning(|_, _, _, _| Ok(false));
    expect_inbox_permission_denied(&mut db, community_id, group_id, user_id, 1);
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(groups.clone()));
    expect_settings_content(&mut db, community_id, group_id, user_id, false);
    db.expect_list_group_check_in_events().never();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Request Check-In through the full dashboard route
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group?tab=check-in")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the response explains the fallback and exposes recovery selectors
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("You cannot manage check-ins for the selected group."));
    assert!(body.contains(&format!("selected-community-id=\"{community_id}\"")));
    assert!(body.contains(&format!("selected-group-id=\"{group_id}\"")));
}

#[tokio::test]
async fn test_page_cohosts_tab_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let groups = sample_user_groups_by_community(community_id, group_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            (*cid, *gid, *uid, permission) == (community_id, group_id, user_id, &CheckInsWrite)
        })
        .returning(|_, _, _, _| Ok(false));
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::BadgesWrite,
    );
    expect_inbox_permission_denied(&mut db, community_id, group_id, user_id, 1);
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::SettingsWrite,
    );
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_list_group_cohosted_events()
        .times(1)
        .withf(move |id, filters| {
            *id == group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(|_, _| Ok(CohostedEventsOutput::default()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group?tab=cohosts")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the co-hosts section is rendered
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("data-group-cohosts-list"));
}

#[tokio::test]
async fn test_page_events_tab_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let groups = sample_user_groups_by_community(community_id, group_id);
    let group_events = sample_group_events(event_id, group_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            (*cid, *gid, *uid, permission) == (community_id, group_id, user_id, &CheckInsWrite)
        })
        .returning(|_, _, _, _| Ok(false));
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::BadgesWrite,
    );
    expect_inbox_permission_denied(&mut db, community_id, group_id, user_id, 1);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
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

    // Check the response and badge section navigation
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    let events_menu = body.find("tab=events").unwrap();
    let badges_menu = body.find("tab=badges").unwrap();
    let artwork_menu = body.find("tab=artwork").unwrap();
    let awards_menu = body.find("tab=awards").unwrap();
    let members_menu = body.find("tab=members").unwrap();
    assert!(events_menu < badges_menu);
    assert!(badges_menu < artwork_menu);
    assert!(artwork_menu < awards_menu);
    assert!(awards_menu < members_menu);
}

#[tokio::test]
async fn test_page_inbox_tab_falls_back_without_inbox_permission() {
    // Setup a readable group session without inbox access
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup dashboard context and fallback settings expectations
    let mut db = MockDB::new();
    expect_inbox_home_context(&mut db, session_id, user_id, community_id, group_id, false);
    db.expect_count_group_open_inbox_conversations().never();
    db.expect_list_group_inbox_conversations().never();
    expect_settings_content(&mut db, community_id, group_id, user_id, false);

    // Request the inbox through the full dashboard route
    let (parts, bytes) = send_home_request(db, session_id, "/dashboard/group?tab=inbox").await;

    // Check the recoverable warning, selectors and hidden menu item
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("You don&#39;t have Inbox access for the selected group."));
    assert!(body.contains(&format!("selected-group-id=\"{group_id}\"")));
    assert!(!body.contains("href=\"/dashboard/group?tab=inbox\""));
    assert!(body.contains("This dashboard is not optimized yet for mobile devices"));
}

#[tokio::test]
async fn test_page_inbox_tab_opens_conversation_of_selected_group() {
    // Setup a group session with inbox access and a conversation of the group
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let inbox_conversation_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let conversation = sample_inbox_conversation(inbox_conversation_id);

    // Setup dashboard context and thread expectations
    let mut db = MockDB::new();
    expect_inbox_home_context(&mut db, session_id, user_id, community_id, group_id, true);
    db.expect_count_group_open_inbox_conversations()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(|_| Ok(0));
    db.expect_get_group_inbox_conversation()
        .times(1)
        .withf(move |gid, cid| *gid == group_id && *cid == inbox_conversation_id)
        .returning(move |_, _| Ok(Some(conversation.clone())));
    db.expect_list_group_inbox_conversations().never();

    // Request the conversation through the full dashboard route
    let (parts, bytes) = send_home_request(
        db,
        session_id,
        &format!("/dashboard/group?tab=inbox&conversation_id={inbox_conversation_id}"),
    )
    .await;

    // Check the thread renders inside the dashboard
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("id=\"inbox-conversation\""));
    assert!(body.contains("hx-get=\"/dashboard/group/inbox\""));
}

#[tokio::test]
async fn test_page_inbox_tab_renders_list_with_open_count_badge() {
    // Setup a group session with inbox access
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let summary = sample_inbox_conversation_summary(Uuid::new_v4());

    // Setup dashboard context, badge count and list expectations
    let mut db = MockDB::new();
    expect_inbox_home_context(&mut db, session_id, user_id, community_id, group_id, true);
    db.expect_count_group_open_inbox_conversations()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(|_| Ok(7));
    db.expect_list_group_inbox_conversations()
        .times(1)
        .withf(move |gid, filters| *gid == group_id && filters.status.is_none())
        .returning(move |_, _| {
            Ok(InboxConversationsOutput {
                conversations: vec![summary.clone()],
                total: 1,
            })
        });

    // Request the inbox through the full dashboard route
    let (parts, bytes) = send_home_request(db, session_id, "/dashboard/group?tab=inbox").await;

    // Check the menu badge, list and mobile notice
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    let inbox_menu_item = body
        .split("href=\"/dashboard/group?tab=inbox\"")
        .nth(1)
        .and_then(|rest| rest.split("</a>").next())
        .expect("inbox menu item to render");
    assert!(inbox_menu_item.contains("Inbox"));
    assert!(inbox_menu_item.split_whitespace().any(|token| token == "7"));
    assert!(body.contains("When do doors open?"));
    assert!(body.contains("This dashboard is not optimized yet for mobile devices"));
}

#[tokio::test]
async fn test_page_inbox_tab_warns_about_conversation_of_another_group() {
    // Setup a group session with inbox access and a foreign conversation
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let inbox_conversation_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup dashboard context, missing thread and list expectations
    let mut db = MockDB::new();
    expect_inbox_home_context(&mut db, session_id, user_id, community_id, group_id, true);
    db.expect_count_group_open_inbox_conversations()
        .times(1)
        .returning(|_| Ok(0));
    db.expect_get_group_inbox_conversation()
        .times(1)
        .returning(|_, _| Ok(None));
    db.expect_list_group_inbox_conversations()
        .times(1)
        .returning(|_, _| Ok(InboxConversationsOutput::default()));

    // Request the conversation through the full dashboard route
    let (parts, bytes) = send_home_request(
        db,
        session_id,
        &format!("/dashboard/group?tab=inbox&conversation_id={inbox_conversation_id}"),
    )
    .await;

    // Check the list renders with the warning
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("This conversation isn&#39;t in the selected group."));
    assert!(body.contains("No conversations yet"));
}

#[tokio::test]
async fn test_page_logs_tab_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let groups = sample_user_groups_by_community(community_id, group_id);
    let output = sample_audit_logs_output();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            (*cid, *gid, *uid, permission) == (community_id, group_id, user_id, &CheckInsWrite)
        })
        .returning(|_, _, _, _| Ok(false));
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::BadgesWrite,
    );
    expect_inbox_permission_denied(&mut db, community_id, group_id, user_id, 1);
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
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
                && filters.sort == Some(AuditLogSort::CreatedDesc)
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
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let groups = sample_user_groups_by_community(community_id, group_id);
    let group = sample_group_summary(group_id);
    let member = sample_group_member();
    let output = crate::types::dashboard::group::members::GroupMembersOutput {
        members: vec![member.clone()],
        total: 1,
    };

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            (*cid, *gid, *uid, permission) == (community_id, group_id, user_id, &CheckInsWrite)
        })
        .returning(|_, _, _, _| Ok(false));
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::BadgesWrite,
    );
    expect_inbox_permission_denied(&mut db, community_id, group_id, user_id, 1);
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::MembersWrite,
    );
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_list_group_members()
        .times(1)
        .withf(move |id, filters| {
            *id == group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(output.clone()));
    db.expect_get_group_summary()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
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
    assert!(body.contains("hx-get=\"/dashboard/group/members\""));
}

#[tokio::test]
async fn test_page_settings_tab_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let groups = sample_user_groups_by_community(community_id, group_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            (*cid, *gid, *uid, permission) == (community_id, group_id, user_id, &CheckInsWrite)
        })
        .returning(|_, _, _, _| Ok(false));
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::BadgesWrite,
    );
    expect_inbox_permission_denied(&mut db, community_id, group_id, user_id, 1);
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(groups.clone()));
    expect_settings_content(&mut db, community_id, group_id, user_id, true);
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
async fn test_page_without_tab_defaults_to_settings() {
    // Setup a readable group session without badge or check-in management
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup dashboard context and default settings tab expectations
    let mut db = MockDB::new();
    expect_inbox_home_context(&mut db, session_id, user_id, community_id, group_id, false);
    expect_settings_content(&mut db, community_id, group_id, user_id, false);
    db.expect_get_group_stats().never();
    db.expect_group_has_active_subgroups().never();

    // Request the dashboard without selecting a tab
    let (parts, bytes) = send_home_request(db, session_id, "/dashboard/group").await;

    // Check the settings tab is rendered instead of analytics
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("hx-get=\"/dashboard/group/settings\""));
    assert!(!body.contains("hx-get=\"/dashboard/group/analytics\""));
}

#[tokio::test]
async fn test_page_sponsors_tab_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let groups = sample_user_groups_by_community(community_id, group_id);
    let sponsor = sample_group_sponsor();
    let output = crate::types::dashboard::group::sponsors::GroupSponsorsOutput {
        sponsors: vec![sponsor.clone()],
        total: 1,
    };

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            (*cid, *gid, *uid, permission) == (community_id, group_id, user_id, &CheckInsWrite)
        })
        .returning(|_, _, _, _| Ok(false));
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::BadgesWrite,
    );
    expect_inbox_permission_denied(&mut db, community_id, group_id, user_id, 1);
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::SponsorsWrite,
    );
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
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let groups = sample_user_groups_by_community(community_id, group_id);
    let team_member = sample_team_member(true);
    let role = sample_group_role_summary();
    let members = vec![team_member.clone(), sample_team_member(false)];
    let output = crate::types::dashboard::group::team::GroupTeamOutput {
        members: members.clone(),
        total: members.len(),
        total_accepted: 1,
        total_admins_accepted: 1,
    };

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            (*cid, *gid, *uid, permission) == (community_id, group_id, user_id, &CheckInsWrite)
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_user_has_group_permission()
        .times(2)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::BadgesWrite
        })
        .returning(|_, _, _, _| Ok(true));
    expect_inbox_permission_denied(&mut db, community_id, group_id, user_id, 1);
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::TeamWrite,
    );
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

#[tokio::test]
async fn test_page_refunds_tab_preserves_history_without_payments_setup() {
    // Setup a readable group after its current payment setup was removed
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let groups = sample_user_groups_by_community(community_id, group_id);
    let output = crate::types::dashboard::group::refunds::RefundsOutput {
        events: vec![],
        financial_recoveries: vec![],
        refunds: vec![],
        total: 0,
    };

    // Setup dashboard context and historical refund-list expectations
    let mut db = MockDB::new();
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            (*cid, *gid, *uid, permission) == (community_id, group_id, user_id, &CheckInsWrite)
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(None));
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_list_group_refunds()
        .times(1)
        .withf(move |gid, filters| {
            *gid == group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && filters.view == crate::types::dashboard::group::refunds::RefundsView::Active
        })
        .returning(move |_, _| Ok(output.clone()));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(groups.clone()));
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::BadgesWrite,
    );
    expect_inbox_permission_denied(&mut db, community_id, group_id, user_id, 1);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::EventsWrite
        })
        .returning(|_, _, _, _| Ok(false));

    // Request the refunds tab without a configured payments provider
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group?tab=refunds")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check history remains visible and current-provider actions are explained
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).expect("refunds response to be UTF-8");
    assert!(body.contains("Automatic payment processing is unavailable"));
    assert!(body.contains("external refunds can still be recorded"));
    assert!(body.contains("tab=refunds"));
}

#[tokio::test]
async fn test_page_refunds_tab_success() {
    // Setup identifiers and empty refund dashboard state
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let groups = sample_user_groups_by_community(community_id, group_id);
    let output = crate::types::dashboard::group::refunds::RefundsOutput {
        events: vec![],
        financial_recoveries: vec![],
        refunds: vec![],
        total: 0,
    };

    // Setup dashboard context, permissions, and refund list expectations
    let mut db = MockDB::new();
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            (*cid, *gid, *uid, permission) == (community_id, group_id, user_id, &CheckInsWrite)
        })
        .returning(|_, _, _, _| Ok(false));
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::BadgesWrite,
    );
    expect_inbox_permission_denied(&mut db, community_id, group_id, user_id, 1);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_list_group_refunds()
        .times(1)
        .withf(move |gid, filters| {
            *gid == group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && filters.view == crate::types::dashboard::group::refunds::RefundsView::Active
        })
        .returning(move |_, _| Ok(output.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Request the refunds tab through the full dashboard page
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group?tab=refunds")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the full dashboard renders the refund operations tab
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("tab=refunds"));
}

// Helpers.

/// Expects the dashboard context reads shared by the inbox tab scenarios.
fn expect_inbox_home_context(
    db: &mut MockDB,
    session_id: session::Id,
    user_id: Uuid,
    community_id: Uuid,
    group_id: Uuid,
    can_manage_inbox: bool,
) {
    let groups = sample_user_groups_by_community(community_id, group_id);
    expect_authenticated_group_session(db, session_id, user_id, community_id, group_id);
    expect_group_permission(db, community_id, group_id, user_id, GroupPermission::Read);
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            (*cid, *gid, *uid, permission) == (community_id, group_id, user_id, &CheckInsWrite)
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::BadgesWrite
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            (*cid, *gid, *uid, permission) == (community_id, group_id, user_id, &InboxWrite)
        })
        .returning(move |_, _, _, _| Ok(can_manage_inbox));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
}

/// Expects the dashboard's inbox permission check to be denied.
fn expect_inbox_permission_denied(
    db: &mut MockDB,
    community_id: Uuid,
    group_id: Uuid,
    user_id: Uuid,
    times: usize,
) {
    db.expect_user_has_group_permission()
        .times(times)
        .withf(move |cid, gid, uid, permission| {
            (*cid, *gid, *uid, permission) == (community_id, group_id, user_id, &InboxWrite)
        })
        .returning(|_, _, _, _| Ok(false));
}

/// Expects the reads used to prepare the settings tab content.
fn expect_settings_content(
    db: &mut MockDB,
    community_id: Uuid,
    group_id: Uuid,
    user_id: Uuid,
    can_manage_settings: bool,
) {
    let category = sample_group_category();
    let group_full = sample_group_full(community_id, group_id);
    let region = sample_group_region();

    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::SettingsWrite
        })
        .returning(move |_, _, _, _| Ok(can_manage_settings));
    db.expect_get_group_full()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(move |_, _| Ok(group_full.clone()));
    db.expect_group_has_child_links()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(false));
    db.expect_list_group_categories()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![category.clone()]));
    db.expect_list_group_parent_options()
        .times(1)
        .withf(move |cid, uid, gid| {
            *cid == community_id && *uid == user_id && *gid == Some(group_id)
        })
        .returning(|_, _, _| Ok(vec![]));
    db.expect_list_regions()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![region.clone()]));
    db.expect_get_group_external_payments_context()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| {
            Ok(GroupExternalPaymentsContext {
                configured: false,
                eligible: false,
                enabled: false,
                country_code: None,
                default_payment_window_hours: None,
                max_payment_window_hours: None,
                seller_display_name: None,
            })
        });
}

/// Sends a group dashboard home request through the router.
async fn send_home_request(
    db: MockDB,
    session_id: session::Id,
    uri: &str,
) -> (axum::http::response::Parts, axum::body::Bytes) {
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(uri)
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    (parts, bytes)
}
