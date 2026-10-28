use axum::http::StatusCode;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    types::{
        dashboard::{DASHBOARD_PAGINATION_LIMIT, group::members::GroupMembersOutput},
        notifications::NotificationKind,
        permissions::GroupPermission,
    },
};

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let group = sample_group_summary(ids.group_id);
    let output = sample_members_output();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::MembersWrite, true);
    db.expect_list_group_members()
        .times(1)
        .withf(move |id, filters| {
            *id == ids.group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(output.clone()));
    db.expect_get_group_summary()
        .times(1)
        .withf(move |cid, gid| *cid == ids.community_id && *gid == ids.group_id)
        .returning(move |_, _| Ok(group.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group/members", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains("Group Member"));
    assert!(body.contains("name=\"subject\""));
    assert!(body.contains("value=\"Test Group\""));
}

#[tokio::test]
async fn test_list_page_with_pagination_params() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let group = sample_group_summary(ids.group_id);
    let output = sample_members_output();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::MembersWrite, true);
    db.expect_list_group_members()
        .times(1)
        .withf(move |id, filters| {
            *id == ids.group_id && filters.limit == Some(5) && filters.offset == Some(10)
        })
        .returning(move |_, _| Ok(output.clone()));
    db.expect_get_group_summary()
        .times(1)
        .withf(move |cid, gid| *cid == ids.community_id && *gid == ids.group_id)
        .returning(move |_, _| Ok(group.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group/members?limit=5&offset=10", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains("Group Member"));
}

#[tokio::test]
async fn test_send_group_custom_notification_no_members() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::MembersWrite);
    db.expect_get_group_summary().never();
    db.expect_list_group_audience_ids()
        .times(1)
        .withf(move |gid| *gid == ids.group_id)
        .returning(move |_| Ok(vec![]));
    db.expect_get_site_settings().never();
    db.expect_enqueue_tracked_custom_notification().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "POST",
        "/dashboard/group/notifications",
        ids.session_id,
        "body=Body&subject=Subject",
    );
    let (parts, bytes) = send(router, request).await;

    // Check the empty audience is rejected
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "no group members can receive this email"
    );
}

#[tokio::test]
async fn test_send_group_custom_notification_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let member_id = Uuid::new_v4();
    let site_settings = sample_site_settings();
    let group_summary = sample_group_summary(ids.group_id);

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::MembersWrite);
    db.expect_list_group_audience_ids()
        .times(1)
        .withf(move |gid| *gid == ids.group_id)
        .returning(move |_| Ok(vec![member_id]));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    db.expect_get_group_summary()
        .times(1)
        .withf(move |cid, gid| *cid == ids.community_id && *gid == ids.group_id)
        .returning(move |_, _| Ok(group_summary.clone()));
    db.expect_enqueue_tracked_custom_notification()
        .times(1)
        .withf(move |notification, tracking| {
            // The legacy `title` field still maps to the subject
            matches!(notification.kind, NotificationKind::GroupCustom)
                && notification.recipients == vec![member_id]
                && tracking.body == "Hello, group members!"
                && tracking.created_by == ids.user_id
                && tracking.subject == "Important Update"
        })
        .returning(|_, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "POST",
        "/dashboard/group/notifications",
        ids.session_id,
        "body=Hello%2C+group+members%21&title=Important+Update",
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::NO_CONTENT);
}

// Helpers.

/// Returns a members list output with the sample member.
fn sample_members_output() -> GroupMembersOutput {
    GroupMembersOutput {
        members: vec![sample_group_member()],
        total: 1,
    }
}
