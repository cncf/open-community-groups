use anyhow::anyhow;
use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::{auth::LOG_IN_URL, tests::*},
    services::notifications::MockNotificationsManager,
    types::{
        dashboard::{
            DASHBOARD_PAGINATION_LIMIT,
            group::team::{GroupTeamMember, GroupTeamOutput},
        },
        group::GroupRole,
        notifications::NotificationKind,
        permissions::GroupPermission,
    },
};

use super::GROUP_TEAM_MANAGEMENT_RESTRICTED_TOOLTIP;

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let member = sample_team_member(true);
    let output = sample_team_output(vec![member.clone(), sample_team_member(false)], 1);

    // Setup database mock
    let mut db = MockDB::new();
    expect_list_page_context(&mut db, &ids, true, true);
    db.expect_list_group_team_members()
        .times(1)
        .withf(move |group_id, filters| {
            *group_id == ids.group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group/team", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url").unwrap(),
        "/dashboard/group?tab=team&limit=50&offset=0",
    );
    assert!(body.contains("At least one accepted admin is required."));
    assert_eq!(body.matches("Award badge").count(), 1);
    assert!(body.contains(&format!("data-user-ids=\"{}\"", member.user_id)));
}

#[tokio::test]
async fn test_list_page_with_pagination_params() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let output = sample_team_output(vec![sample_team_member(true), sample_team_member(true)], 2);

    // Setup database mock
    let mut db = MockDB::new();
    expect_list_page_context(&mut db, &ids, true, true);
    db.expect_list_group_team_members()
        .times(1)
        .withf(move |group_id, filters| {
            *group_id == ids.group_id && filters.limit == Some(5) && filters.offset == Some(10)
        })
        .returning(move |_, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group/team?limit=5&offset=10", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url").unwrap(),
        "/dashboard/group?tab=team&limit=5&offset=10",
    );
    assert!(!body.contains("At least one accepted admin is required."));
}

#[tokio::test]
async fn test_list_page_shows_restricted_policy_tooltip_when_team_write_is_blocked() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let output = sample_team_output(vec![sample_team_member(true), sample_team_member(true)], 2);
    let mut community = sample_community_full(ids.community_id);
    community.group_team_management_restricted = true;

    // Setup database mock
    let mut db = MockDB::new();
    expect_list_page_context(&mut db, &ids, false, false);
    db.expect_list_group_team_members()
        .times(1)
        .withf(move |group_id, filters| {
            *group_id == ids.group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(output.clone()));
    db.expect_get_community_full()
        .times(1)
        .withf(move |community_id| *community_id == ids.community_id)
        .returning(move |_| Ok(community.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group/team", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let expected_tooltip = askama::filters::escape(
        GROUP_TEAM_MANAGEMENT_RESTRICTED_TOOLTIP,
        askama::filters::Html,
    )
    .unwrap()
    .to_string();
    assert!(body.contains(&expected_tooltip));
    assert!(!body.contains("Award badge"));
}

#[tokio::test]
async fn test_add_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let new_member_id = Uuid::new_v4();
    let group_summary = sample_group_summary(ids.group_id);
    let site_settings = sample_site_settings();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::TeamWrite);
    db.expect_add_group_team_member()
        .times(1)
        .withf(move |actor_user_id, group_id, user_id, role| {
            *actor_user_id == ids.user_id
                && *group_id == ids.group_id
                && *user_id == new_member_id
                && role == &GroupRole::Admin
        })
        .returning(|_, _, _, _| Ok(()));
    db.expect_get_group_summary()
        .times(1)
        .withf(move |community_id, group_id| {
            *community_id == ids.community_id && *group_id == ids.group_id
        })
        .returning(move |_, _| Ok(group_summary.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::GroupTeamInvitation)
                && notification.recipients == vec![new_member_id]
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_notifications_manager(nm)
        .build()
        .await;
    let (parts, bytes) = send(router, add_request(&ids, new_member_id)).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::CREATED,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_add_db_error() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let new_member_id = Uuid::new_v4();

    // Setup database mock with a failing write and no notification context reads
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::TeamWrite);
    db.expect_add_group_team_member()
        .times(1)
        .withf(move |actor_user_id, group_id, user_id, role| {
            *actor_user_id == ids.user_id
                && *group_id == ids.group_id
                && *user_id == new_member_id
                && role == &GroupRole::Admin
        })
        .returning(|_, _, _, _| Err(anyhow!("db error")));
    db.expect_get_group_summary().never();
    db.expect_get_site_settings().never();

    // Setup notifications manager mock, which must not be called
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_notifications_manager(nm)
        .build()
        .await;
    let (parts, bytes) = send(router, add_request(&ids, new_member_id)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_delete_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let member_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::TeamWrite);
    expect_delete_group_team_member(&mut db, &ids, member_id);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "DELETE",
        &format!("/dashboard/group/team/{member_id}/delete"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_delete_current_user_with_inherited_read_stays_logged_in() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::TeamWrite);
    expect_delete_group_team_member(&mut db, &ids, ids.user_id);
    expect_group_permission_result(&mut db, &ids, GroupPermission::Read, true);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, delete_current_user_request(&ids)).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_delete_current_user_logs_out() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::TeamWrite);
    expect_delete_group_team_member(&mut db, &ids, ids.user_id);
    expect_group_permission_result(&mut db, &ids, GroupPermission::Read, false);
    db.expect_delete_session()
        .times(1)
        .withf(move |session_id| *session_id == ids.session_id)
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, delete_current_user_request(&ids)).await;

    // Check response matches expectations
    assert_empty_hx_redirect_response(&parts, &bytes, StatusCode::OK, LOG_IN_URL);
}

#[tokio::test]
async fn test_update_role_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let member_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::TeamWrite);
    db.expect_update_group_team_member_role()
        .times(1)
        .withf(move |actor_user_id, group_id, user_id, role| {
            *actor_user_id == ids.user_id
                && *group_id == ids.group_id
                && *user_id == member_id
                && role == &GroupRole::Admin
        })
        .returning(move |_, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/group/team/{member_id}/role"),
        ids.session_id,
        format!("role={}", GroupRole::Admin),
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-group-dashboard-table",
    );
}

// Helpers.

/// Build the request that adds the user to the team as an admin.
fn add_request(ids: &DashboardIds, new_member_id: Uuid) -> Request<Body> {
    form_request(
        "POST",
        "/dashboard/group/team/add",
        ids.session_id,
        format!("role={}&user_id={new_member_id}", GroupRole::Admin),
    )
}

/// Build the HTMX request in which the current user leaves the team.
fn delete_current_user_request(ids: &DashboardIds) -> Request<Body> {
    authenticated_request(
        "DELETE",
        &format!("/dashboard/group/team/{}/delete", ids.user_id),
        ids.session_id,
    )
    .header("HX-Request", "true")
    .body(Body::empty())
    .unwrap()
}

/// Expect the team member removal performed by the current user.
fn expect_delete_group_team_member(db: &mut MockDB, ids: &DashboardIds, member_id: Uuid) {
    let ids = *ids;
    db.expect_delete_group_team_member()
        .times(1)
        .withf(move |actor_user_id, group_id, user_id| {
            *actor_user_id == ids.user_id && *group_id == ids.group_id && *user_id == member_id
        })
        .returning(|_, _, _| Ok(()));
}

/// Expect the fixed reads of the team list page.
///
/// The badges and team write results decide which controls the page renders.
fn expect_list_page_context(
    db: &mut MockDB,
    ids: &DashboardIds,
    can_award_badges: bool,
    can_manage_team: bool,
) {
    expect_group_access(db, ids, GroupPermission::Read);
    db.expect_list_group_roles()
        .times(1)
        .returning(|| Ok(vec![sample_group_role_summary()]));
    expect_group_permission_result(db, ids, GroupPermission::BadgesWrite, can_award_badges);
    expect_group_permission_result(db, ids, GroupPermission::TeamWrite, can_manage_team);
}

/// Sample team output with the members and accepted admins count.
fn sample_team_output(
    members: Vec<GroupTeamMember>,
    total_admins_accepted: usize,
) -> GroupTeamOutput {
    GroupTeamOutput {
        total: members.len(),
        total_accepted: total_admins_accepted,
        total_admins_accepted,
        members,
    }
}
