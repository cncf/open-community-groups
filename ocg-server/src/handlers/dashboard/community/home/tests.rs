use axum::{
    body::{Body, to_bytes},
    http::{
        Request, StatusCode,
        header::{COOKIE, HOST},
    },
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
            DASHBOARD_PAGINATION_LIMIT,
            common::AuditLogSort,
            community::contact::{
                CommunityContactFilterOptions, CommunityContactRecipientsSummary,
            },
        },
        permissions::CommunityPermission,
        search::SearchGroupsOutput,
    },
};

#[tokio::test]
async fn test_page_analytics_tab_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let stats = sample_community_stats();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    expect_community_permission(&mut db, community_id, user_id, CommunityPermission::Read);
    db.expect_get_community_full()
        .times(1)
        .withf(move |id| *id == community_id)
        .returning(move |_| Ok(sample_community_full(community_id)));
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(sample_user_communities(community_id)));
    db.expect_get_community_stats()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(stats.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/community?tab=analytics")
        .header(HOST, "example.test")
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
async fn test_page_contact_tab_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    expect_community_permission(&mut db, community_id, user_id, CommunityPermission::Read);
    db.expect_get_community_full()
        .times(1)
        .withf(move |id| *id == community_id)
        .returning(move |_| Ok(sample_community_full(community_id)));
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(sample_user_communities(community_id)));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id
                && *uid == user_id
                && *permission == CommunityPermission::GroupsWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_list_community_contact_filter_options()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(|_| Ok(CommunityContactFilterOptions::default()));
    db.expect_list_group_roles()
        .times(1)
        .returning(|| Ok(vec![sample_group_role_summary()]));
    db.expect_get_community_contact_recipients_summary()
        .times(1)
        .withf(move |cid, _| *cid == community_id)
        .returning(|_, _| Ok(CommunityContactRecipientsSummary::default()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/community?tab=contact")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the contact page is rendered in the dashboard
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(html.contains(r#"id="community-contact-form""#));
    assert!(html.contains("No group team members match these filters."));
}

#[tokio::test]
async fn test_page_groups_tab_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let ts_query = "rust".to_string();
    let groups_output = SearchGroupsOutput {
        total: 0,

        bbox: None,
        ..sample_search_groups_output(group_id)
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    expect_community_permission(&mut db, community_id, user_id, CommunityPermission::Read);
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id
                && *uid == user_id
                && permission == CommunityPermission::GroupsWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_get_community_full()
        .times(1)
        .withf(move |id| *id == community_id)
        .returning(move |_| Ok(sample_community_full(community_id)));
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(sample_user_communities(community_id)));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_search_groups()
        .times(1)
        .withf({
            let ts_query = ts_query.clone();
            move |filters| {
                filters.community == vec!["test".to_string()]
                    && filters.include_inactive == Some(true)
                    && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                    && filters.sort_by.as_deref() == Some("name")
                    && filters.ts_query.as_deref() == Some(ts_query.as_str())
            }
        })
        .returning(move |_| Ok(groups_output.clone()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/community?tab=groups&ts_query=rust")
        .header(HOST, "example.test")
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
async fn test_page_logs_tab_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let output = sample_audit_logs_output();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    expect_community_permission(&mut db, community_id, user_id, CommunityPermission::Read);
    db.expect_get_community_full()
        .times(1)
        .withf(move |id| *id == community_id)
        .returning(move |_| Ok(sample_community_full(community_id)));
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(sample_user_communities(community_id)));
    db.expect_list_community_audit_logs()
        .times(1)
        .withf(move |cid, filters| {
            *cid == community_id
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
        .uri("/dashboard/community?tab=logs")
        .header(HOST, "example.test")
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
async fn test_page_settings_tab_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    expect_community_permission(&mut db, community_id, user_id, CommunityPermission::Read);
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id
                && *uid == user_id
                && permission == CommunityPermission::SettingsWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_get_community_full()
        .times(1)
        .withf(move |id| *id == community_id)
        .returning(move |_| Ok(sample_community_full(community_id)));
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(sample_user_communities(community_id)));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/community?tab=settings")
        .header(HOST, "example.test")
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
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    expect_community_permission(&mut db, community_id, user_id, CommunityPermission::Read);
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id
                && *uid == user_id
                && permission == CommunityPermission::SettingsWrite
        })
        .returning(|_, _, _| Ok(false));
    db.expect_get_community_full()
        .times(1)
        .withf(move |id| *id == community_id)
        .returning(move |_| Ok(sample_community_full(community_id)));
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(sample_user_communities(community_id)));
    db.expect_get_community_stats().never();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request without selecting a tab
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/community")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the settings tab is rendered instead of analytics
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("hx-get=\"/dashboard/community/settings/update\""));
    assert!(!body.contains("hx-get=\"/dashboard/community/analytics\""));
}

#[tokio::test]
async fn test_page_team_tab_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let members = vec![
        sample_community_team_member(true),
        sample_community_team_member(false),
    ];
    let output = crate::types::dashboard::community::team::CommunityTeamOutput {
        members: members.clone(),
        total: members.len(),
        total_accepted: 1,
        total_admins_accepted: 1,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    expect_community_permission(&mut db, community_id, user_id, CommunityPermission::Read);
    expect_community_permission(
        &mut db,
        community_id,
        user_id,
        CommunityPermission::TeamWrite,
    );
    db.expect_get_community_full()
        .times(1)
        .withf(move |id| *id == community_id)
        .returning(move |_| Ok(sample_community_full(community_id)));
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(sample_user_communities(community_id)));
    db.expect_list_community_team_members()
        .times(1)
        .withf(move |id, filters| {
            *id == community_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(output.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_list_community_roles()
        .times(1)
        .returning(|| Ok(vec![sample_community_role_summary()]));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/community?tab=team")
        .header(HOST, "example.test")
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
async fn test_page_regions_tab_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let regions = vec![sample_group_region()];

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    expect_community_permission(&mut db, community_id, user_id, CommunityPermission::Read);
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id
                && *uid == user_id
                && permission == CommunityPermission::TaxonomyWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_get_community_full()
        .times(1)
        .withf(move |id| *id == community_id)
        .returning(move |_| Ok(sample_community_full(community_id)));
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(sample_user_communities(community_id)));
    db.expect_list_regions()
        .times(1)
        .withf(move |id| *id == community_id)
        .returning(move |_| Ok(regions.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/community?tab=regions")
        .header(HOST, "example.test")
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
async fn test_page_group_categories_tab_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let categories = vec![sample_group_category()];

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    expect_community_permission(&mut db, community_id, user_id, CommunityPermission::Read);
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id
                && *uid == user_id
                && permission == CommunityPermission::TaxonomyWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_get_community_full()
        .times(1)
        .withf(move |id| *id == community_id)
        .returning(move |_| Ok(sample_community_full(community_id)));
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(sample_user_communities(community_id)));
    db.expect_list_group_categories()
        .times(1)
        .withf(move |id| *id == community_id)
        .returning(move |_| Ok(categories.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/community?tab=group-categories")
        .header(HOST, "example.test")
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
async fn test_page_event_categories_tab_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let categories = vec![sample_event_category()];

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    expect_community_permission(&mut db, community_id, user_id, CommunityPermission::Read);
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id
                && *uid == user_id
                && permission == CommunityPermission::TaxonomyWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_get_community_full()
        .times(1)
        .withf(move |id| *id == community_id)
        .returning(move |_| Ok(sample_community_full(community_id)));
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(sample_user_communities(community_id)));
    db.expect_list_event_categories()
        .times(1)
        .withf(move |id| *id == community_id)
        .returning(move |_| Ok(categories.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/community?tab=event-categories")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}
