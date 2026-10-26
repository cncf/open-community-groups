use axum::http::{HeaderValue, StatusCode};
use chrono::{DateTime, Utc};
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    types::dashboard::{
        DASHBOARD_PAGINATION_LIMIT,
        user::groups::{UserGroup, UserGroupsOutput},
    },
};

#[tokio::test]
async fn test_leave_group_community_not_found() {
    // Setup identifiers and database mock
    let group_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "missing-community")
        .returning(|_| Ok(None));
    db.expect_leave_group().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "DELETE",
        &format!("/dashboard/user/groups/missing-community/{group_id}/membership"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the missing community is rejected before mutation
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_leave_group_success() {
    // Setup identifiers and database mock
    let group_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_member_context(&mut db, &ids);
    db.expect_leave_group()
        .times(1)
        .withf(move |cid, gid, uid| {
            *cid == ids.community_id && *gid == group_id && *uid == ids.user_id
        })
        .returning(|_, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "DELETE",
        &format!("/dashboard/user/groups/test-community/{group_id}/membership"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the response refreshes the dashboard list
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-user-dashboard-content",
    );
}

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and list data
    let group_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let output = UserGroupsOutput {
        groups: vec![UserGroup {
            group: sample_group_summary(group_id),
            is_member: true,
            is_team_member: false,
            joined_at: DateTime::<Utc>::from_timestamp(1_704_189_600, 0).unwrap(),
        }],
        total: 1,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_list_user_dashboard_groups()
        .times(1)
        .withf(move |uid, filters| {
            *uid == ids.user_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user/groups", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the partial response, pushed URL and listed group
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url"),
        Some(&HeaderValue::from_static(
            "/dashboard/user?tab=groups&limit=50&offset=0",
        ))
    );
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("Test Group"));
}
