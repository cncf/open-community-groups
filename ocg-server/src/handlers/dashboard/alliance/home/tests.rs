use anyhow::anyhow;
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
    db::{common::SearchGroupsOutput, mock::MockDB},
    handlers::tests::*,
    services::notifications::MockNotificationsManager,
    templates::dashboard::DASHBOARD_PAGINATION_LIMIT,
    types::permissions::AlliancePermission,
};

#[tokio::test]
async fn test_page_analytics_tab_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record =
        sample_session_record(session_id, user_id, &auth_hash, Some(alliance_id), None);
    let stats = sample_alliance_stats();

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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id && *uid == user_id && permission == AlliancePermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_get_alliance_full()
        .times(1)
        .withf(move |id| *id == alliance_id)
        .returning(move |_| Ok(sample_alliance_full(alliance_id)));
    db.expect_list_user_alliances()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(sample_user_alliances(alliance_id)));
    db.expect_get_alliance_stats()
        .times(1)
        .withf(move |cid| *cid == alliance_id)
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
        .uri("/dashboard/alliance?tab=analytics")
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
async fn test_page_groups_tab_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record =
        sample_session_record(session_id, user_id, &auth_hash, Some(alliance_id), None);
    let ts_query = "rust".to_string();
    let groups_output = SearchGroupsOutput {
        total: 0,
        bbox: None,
        ..sample_search_groups_output(group_id)
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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id && *uid == user_id && permission == AlliancePermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id && *uid == user_id && permission == AlliancePermission::GroupsWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_get_alliance_full()
        .times(1)
        .withf(move |id| *id == alliance_id)
        .returning(move |_| Ok(sample_alliance_full(alliance_id)));
    db.expect_list_user_alliances()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(sample_user_alliances(alliance_id)));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_search_groups()
        .times(1)
        .withf({
            let ts_query = ts_query.clone();
            move |filters| {
                filters.alliance == vec!["test".to_string()]
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
        .uri("/dashboard/alliance?tab=groups&ts_query=rust")
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
    let alliance_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let output = sample_audit_logs_output();
    let session_record =
        sample_session_record(session_id, user_id, &auth_hash, Some(alliance_id), None);

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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id && *uid == user_id && permission == AlliancePermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_get_alliance_full()
        .times(1)
        .withf(move |id| *id == alliance_id)
        .returning(move |_| Ok(sample_alliance_full(alliance_id)));
    db.expect_list_user_alliances()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(sample_user_alliances(alliance_id)));
    db.expect_list_alliance_audit_logs()
        .times(1)
        .withf(move |cid, filters| {
            *cid == alliance_id
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
        .uri("/dashboard/alliance?tab=logs")
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
    let alliance_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record =
        sample_session_record(session_id, user_id, &auth_hash, Some(alliance_id), None);

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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id && *uid == user_id && permission == AlliancePermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id
                && *uid == user_id
                && permission == AlliancePermission::SettingsWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_get_alliance_full()
        .times(1)
        .withf(move |id| *id == alliance_id)
        .returning(move |_| Ok(sample_alliance_full(alliance_id)));
    db.expect_list_user_alliances()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(sample_user_alliances(alliance_id)));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/alliance?tab=settings")
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
async fn test_page_team_tab_success() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record =
        sample_session_record(session_id, user_id, &auth_hash, Some(alliance_id), None);
    let members = vec![
        sample_alliance_team_member(true),
        sample_alliance_team_member(false),
    ];
    let output = crate::templates::dashboard::alliance::team::AllianceTeamOutput {
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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id && *uid == user_id && permission == AlliancePermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id && *uid == user_id && permission == AlliancePermission::TeamWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_get_alliance_full()
        .times(1)
        .withf(move |id| *id == alliance_id)
        .returning(move |_| Ok(sample_alliance_full(alliance_id)));
    db.expect_list_user_alliances()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(sample_user_alliances(alliance_id)));
    db.expect_list_alliance_team_members()
        .times(1)
        .withf(move |id, filters| {
            *id == alliance_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(output.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_list_alliance_roles()
        .times(1)
        .returning(|| Ok(vec![sample_alliance_role_summary()]));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/alliance?tab=team")
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
    let alliance_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record =
        sample_session_record(session_id, user_id, &auth_hash, Some(alliance_id), None);
    let regions = vec![sample_group_region()];

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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id && *uid == user_id && permission == AlliancePermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id
                && *uid == user_id
                && permission == AlliancePermission::TaxonomyWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_get_alliance_full()
        .times(1)
        .withf(move |id| *id == alliance_id)
        .returning(move |_| Ok(sample_alliance_full(alliance_id)));
    db.expect_list_user_alliances()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(sample_user_alliances(alliance_id)));
    db.expect_list_regions()
        .times(1)
        .withf(move |id| *id == alliance_id)
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
        .uri("/dashboard/alliance?tab=regions")
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
    let alliance_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record =
        sample_session_record(session_id, user_id, &auth_hash, Some(alliance_id), None);
    let categories = vec![sample_group_category()];

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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id && *uid == user_id && permission == AlliancePermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id
                && *uid == user_id
                && permission == AlliancePermission::TaxonomyWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_get_alliance_full()
        .times(1)
        .withf(move |id| *id == alliance_id)
        .returning(move |_| Ok(sample_alliance_full(alliance_id)));
    db.expect_list_user_alliances()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(sample_user_alliances(alliance_id)));
    db.expect_list_group_categories()
        .times(1)
        .withf(move |id| *id == alliance_id)
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
        .uri("/dashboard/alliance?tab=group-categories")
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
    let alliance_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record =
        sample_session_record(session_id, user_id, &auth_hash, Some(alliance_id), None);
    let categories = vec![sample_event_category()];

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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id && *uid == user_id && permission == AlliancePermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id
                && *uid == user_id
                && permission == AlliancePermission::TaxonomyWrite
        })
        .returning(|_, _, _| Ok(true));
    db.expect_get_alliance_full()
        .times(1)
        .withf(move |id| *id == alliance_id)
        .returning(move |_| Ok(sample_alliance_full(alliance_id)));
    db.expect_list_user_alliances()
        .times(1)
        .withf(move |uid| uid == &user_id)
        .returning(move |_| Ok(sample_user_alliances(alliance_id)));
    db.expect_list_event_categories()
        .times(1)
        .withf(move |id| *id == alliance_id)
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
        .uri("/dashboard/alliance?tab=event-categories")
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
async fn test_page_db_error() {
    // Setup identifiers and data structures
    let alliance_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record =
        sample_session_record(session_id, user_id, &auth_hash, Some(alliance_id), None);

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
    db.expect_user_has_alliance_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == alliance_id && *uid == user_id && permission == AlliancePermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_get_alliance_full()
        .times(1)
        .withf(move |id| *id == alliance_id)
        .returning(move |_| Err(anyhow!("db error")));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/alliance")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}
