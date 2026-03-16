use anyhow::anyhow;
use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderValue, Request, StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE, COOKIE, HOST},
    },
};
use axum_login::tower_sessions::session;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    router::CACHE_CONTROL_NO_CACHE,
    services::notifications::{MockNotificationsManager, NotificationKind},
    templates::dashboard::DASHBOARD_PAGINATION_LIMIT,
    templates::notifications::CommunityTeamInvitation as CommunityTeamInvitationTemplate,
    types::community::CommunityRole,
    types::permissions::CommunityPermission,
};

use super::NewTeamMember;

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);
    let members = vec![
        sample_community_team_member(true),
        sample_community_team_member(false),
    ];
    let role = crate::types::community::CommunityRoleSummary {
        community_role_id: "admin".to_string(),
        display_name: "Admin".to_string(),
    };
    let output = crate::templates::dashboard::community::team::CommunityTeamOutput {
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
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id && *uid == user_id && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_list_community_team_members()
        .times(1)
        .withf(move |cid, filters| {
            *cid == community_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(output.clone()));
    db.expect_list_community_roles()
        .times(1)
        .returning(move || Ok(vec![role.clone()]));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id && *uid == user_id && permission == CommunityPermission::TeamWrite
        })
        .returning(move |_, _, _| Ok(true));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/community/team")
        .header(HOST, "example.test")
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
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("At least one accepted admin is required."));
}

#[tokio::test]
async fn test_list_page_with_pagination_params() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);
    let members = vec![
        sample_community_team_member(true),
        sample_community_team_member(true),
    ];
    let role = crate::types::community::CommunityRoleSummary {
        community_role_id: "admin".to_string(),
        display_name: "Admin".to_string(),
    };
    let output = crate::templates::dashboard::community::team::CommunityTeamOutput {
        members: members.clone(),
        total: members.len(),
        total_accepted: 2,
        total_admins_accepted: 2,
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
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id && *uid == user_id && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_list_community_team_members()
        .times(1)
        .withf(move |cid, filters| {
            *cid == community_id && filters.limit == Some(5) && filters.offset == Some(10)
        })
        .returning(move |_, _| Ok(output.clone()));
    db.expect_list_community_roles()
        .times(1)
        .returning(move || Ok(vec![role.clone()]));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id && *uid == user_id && permission == CommunityPermission::TeamWrite
        })
        .returning(move |_, _, _| Ok(true));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/community/team?limit=5&offset=10")
        .header(HOST, "example.test")
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
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(!body.contains("At least one accepted admin is required."));
}

#[tokio::test]
async fn test_list_page_db_error() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);

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
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id && *uid == user_id && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_list_community_team_members()
        .times(1)
        .withf(move |cid, filters| {
            *cid == community_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Err(anyhow!("db error")));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/community/team")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
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
async fn test_add_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let new_member_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);
    let community = sample_community_summary(community_id);
    let community_for_db = community.clone();
    let site_settings = sample_site_settings();
    let site_settings_for_assertions = site_settings.clone();
    let new_member_form = NewTeamMember {
        role: CommunityRole::Admin,
        user_id: new_member_id,
    };
    let body = serde_qs::to_string(&new_member_form).unwrap();

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
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id && *uid == user_id && permission == CommunityPermission::TeamWrite
        })
        .returning(move |_, _, _| Ok(true));
    db.expect_add_community_team_member()
        .times(1)
        .withf(move |cid, uid, role| {
            *cid == community_id && *uid == new_member_id && *role == CommunityRole::Admin
        })
        .returning(move |_, _, _| Ok(()));
    db.expect_get_community_summary()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(community_for_db.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::CommunityTeamInvitation)
                && notification.recipients == vec![new_member_id]
                && notification.template_data.as_ref().is_some_and(|data| {
                    serde_json::from_value::<CommunityTeamInvitationTemplate>(data.clone())
                        .map(|template| {
                            template.community_name == community.display_name
                                && template.link == "/dashboard/user?tab=invitations"
                                && template.theme.primary_color
                                    == site_settings_for_assertions.theme.primary_color
                        })
                        .unwrap_or(false)
                })
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("POST")
        .uri("/dashboard/community/team/add")
        .header(HOST, "example.test")
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
        &HeaderValue::from_static("refresh-community-dashboard-table"),
    );
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_add_db_error() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let new_member_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);
    let new_member_form = NewTeamMember {
        role: CommunityRole::Admin,
        user_id: new_member_id,
    };
    let body = serde_qs::to_string(&new_member_form).unwrap();

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
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id && *uid == user_id && permission == CommunityPermission::TeamWrite
        })
        .returning(move |_, _, _| Ok(true));
    db.expect_add_community_team_member()
        .times(1)
        .withf(move |cid, uid, role| {
            *cid == community_id && *uid == new_member_id && *role == CommunityRole::Admin
        })
        .returning(move |_, _, _| Err(anyhow!("db error")));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("POST")
        .uri("/dashboard/community/team/add")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(body))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_delete_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let member_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);

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
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id && *uid == user_id && permission == CommunityPermission::TeamWrite
        })
        .returning(move |_, _, _| Ok(true));
    db.expect_delete_community_team_member()
        .times(1)
        .withf(move |cid, uid| *cid == community_id && *uid == member_id)
        .returning(move |_, _| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("DELETE")
        .uri(format!("/dashboard/community/team/{member_id}/delete"))
        .header(HOST, "example.test")
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
        &HeaderValue::from_static("refresh-community-dashboard-table"),
    );
    assert!(bytes.is_empty());
}
