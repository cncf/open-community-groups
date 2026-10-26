use anyhow::anyhow;
use axum::{body::Body, http::StatusCode};
use uuid::Uuid;

use crate::{
    db::mock::{MockDB, expect_site_settings},
    handlers::{auth::LOG_IN_URL, error::INVALID_REQUEST_PAYLOAD, tests::*},
    services::notifications::MockNotificationsManager,
    types::{
        community::CommunityRole,
        dashboard::{DASHBOARD_PAGINATION_LIMIT, community::team::CommunityTeamOutput},
        notifications::NotificationKind,
        permissions::CommunityPermission,
    },
};

use super::NewTeamMember;

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let members = vec![
        sample_community_team_member(true),
        sample_community_team_member(false),
    ];
    let output = CommunityTeamOutput {
        members: members.clone(),
        total: members.len(),
        total_accepted: 1,
        total_admins_accepted: 1,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::Read);
    expect_community_permission_result(&mut db, &ids, CommunityPermission::TeamWrite, true);
    db.expect_list_community_team_members()
        .times(1)
        .withf(move |community_id, filters| {
            *community_id == ids.community_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(output.clone()));
    db.expect_list_community_roles()
        .times(1)
        .returning(|| Ok(vec![sample_community_role_summary()]));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/community/team", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the admin warning is rendered
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains("At least one accepted admin is required."));
}

#[tokio::test]
async fn test_list_page_read_only_hides_team_management() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let member = sample_community_team_member(false);
    let member_id = member.user_id;
    let output = CommunityTeamOutput {
        members: vec![member],
        total: 1,
        total_accepted: 0,
        total_admins_accepted: 1,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::Read);
    expect_community_permission_result(&mut db, &ids, CommunityPermission::TeamWrite, false);
    db.expect_list_community_team_members()
        .times(1)
        .withf(move |community_id, _| *community_id == ids.community_id)
        .returning(move |_, _| Ok(output.clone()));
    db.expect_list_community_roles()
        .times(1)
        .returning(|| Ok(vec![sample_community_role_summary()]));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/community/team", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the role form is hidden and the delete action disabled
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains(r#"can-manage-team="false""#));
    assert!(!body.contains(&format!(
        r#"hx-put="/dashboard/community/team/{member_id}/role""#
    )));
    assert!(body.contains(r#"disabled title="Your role cannot delete team members.""#));
}

#[tokio::test]
async fn test_list_page_with_pagination_params_and_enough_admins() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let members = vec![
        sample_community_team_member(true),
        sample_community_team_member(true),
    ];
    let output = CommunityTeamOutput {
        members: members.clone(),
        total: members.len(),
        total_accepted: 2,
        total_admins_accepted: 2,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::Read);
    expect_community_permission_result(&mut db, &ids, CommunityPermission::TeamWrite, true);
    db.expect_list_community_team_members()
        .times(1)
        .withf(move |community_id, filters| {
            *community_id == ids.community_id
                && filters.limit == Some(5)
                && filters.offset == Some(10)
        })
        .returning(move |_, _| Ok(output.clone()));
    db.expect_list_community_roles()
        .times(1)
        .returning(|| Ok(vec![sample_community_role_summary()]));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        "/dashboard/community/team?limit=5&offset=10",
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the admin warning is not rendered
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(!body.contains("At least one accepted admin is required."));
}

#[tokio::test]
async fn test_add_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let new_member_id = Uuid::new_v4();
    let community = sample_community_summary(ids.community_id);
    let new_member_form = NewTeamMember {
        role: CommunityRole::Admin,
        user_id: new_member_id,
    };
    let body = serde_qs::to_string(&new_member_form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::TeamWrite);
    db.expect_add_community_team_member()
        .times(1)
        .withf(move |actor_user_id, community_id, user_id, role| {
            *actor_user_id == ids.user_id
                && *community_id == ids.community_id
                && *user_id == new_member_id
                && *role == CommunityRole::Admin
        })
        .returning(|_, _, _, _| Ok(()));
    db.expect_get_community_summary()
        .times(1)
        .withf(move |community_id| *community_id == ids.community_id)
        .returning(move |_| Ok(community.clone()));
    expect_site_settings(&mut db);

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::CommunityTeamInvitation)
                && notification.recipients == vec![new_member_id]
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_notifications_manager(nm)
        .build()
        .await;
    let request = form_request(
        "POST",
        "/dashboard/community/team/add",
        ids.session_id,
        body,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::CREATED,
        "refresh-community-dashboard-table",
    );
}

#[tokio::test]
async fn test_add_db_error() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let new_member_id = Uuid::new_v4();
    let new_member_form = NewTeamMember {
        role: CommunityRole::Admin,
        user_id: new_member_id,
    };
    let body = serde_qs::to_string(&new_member_form).unwrap();

    // Setup database mock with a failing write and no notification context reads
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::TeamWrite);
    db.expect_add_community_team_member()
        .times(1)
        .withf(move |actor_user_id, community_id, user_id, role| {
            *actor_user_id == ids.user_id
                && *community_id == ids.community_id
                && *user_id == new_member_id
                && *role == CommunityRole::Admin
        })
        .returning(|_, _, _, _| Err(anyhow!("db error")));
    db.expect_get_community_summary().never();
    db.expect_get_site_settings().never();

    // Setup notifications manager mock, which must not be called
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_notifications_manager(nm)
        .build()
        .await;
    let request = form_request(
        "POST",
        "/dashboard/community/team/add",
        ids.session_id,
        body,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_delete_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let member_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::TeamWrite);
    db.expect_delete_community_team_member()
        .times(1)
        .withf(move |actor_user_id, community_id, user_id| {
            *actor_user_id == ids.user_id
                && *community_id == ids.community_id
                && *user_id == member_id
        })
        .returning(|_, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "DELETE",
        &format!("/dashboard/community/team/{member_id}/delete"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-community-dashboard-table",
    );
}

#[tokio::test]
async fn test_delete_current_user_logs_out() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::TeamWrite);
    db.expect_delete_community_team_member()
        .times(1)
        .withf(move |actor_user_id, community_id, user_id| {
            *actor_user_id == ids.user_id
                && *community_id == ids.community_id
                && *user_id == ids.user_id
        })
        .returning(|_, _, _| Ok(()));
    db.expect_delete_session()
        .times(1)
        .withf(move |id| *id == ids.session_id)
        .returning(|_| Ok(()));

    // Setup router and send an HTMX request removing the current user
    let router = TestRouterBuilder::new(db).build().await;
    let request = authenticated_request(
        "DELETE",
        &format!("/dashboard/community/team/{}/delete", ids.user_id),
        ids.session_id,
    )
    .header("HX-Request", "true")
    .body(Body::empty())
    .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_redirect_response(&parts, &bytes, StatusCode::OK, LOG_IN_URL);
}

#[tokio::test]
async fn test_update_role_invalid_payload() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let member_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::TeamWrite);
    db.expect_update_community_team_member_role().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/community/team/{member_id}/role"),
        ids.session_id,
        "role=unknown",
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), INVALID_REQUEST_PAYLOAD.as_bytes());
}

#[tokio::test]
async fn test_update_role_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let member_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::TeamWrite);
    db.expect_update_community_team_member_role()
        .times(1)
        .withf(move |actor_user_id, community_id, user_id, role| {
            *actor_user_id == ids.user_id
                && *community_id == ids.community_id
                && *user_id == member_id
                && *role == CommunityRole::GroupsManager
        })
        .returning(|_, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/community/team/{member_id}/role"),
        ids.session_id,
        "role=groups-manager",
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-community-dashboard-table",
    );
}
