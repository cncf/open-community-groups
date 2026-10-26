use axum::http::StatusCode;
use serde_json::json;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::{
        auth::session_context::{SELECTED_COMMUNITY_ID_KEY, SELECTED_GROUP_ID_KEY},
        tests::*,
    },
    types::permissions::GroupPermission,
};

use super::payments_ready;

#[test]
fn test_payments_ready() {
    let payment_recipient = sample_group_payment_recipient();
    let payments_cfg = sample_payments_cfg();
    let cases = [
        ("without config", Some(&payment_recipient), None, false),
        ("without recipient", None, Some(&payments_cfg), false),
        (
            "with recipient for the configured provider",
            Some(&payment_recipient),
            Some(&payments_cfg),
            true,
        ),
    ];

    for (case, payment_recipient, payments_cfg, expected) in cases {
        assert_eq!(
            payments_ready(payment_recipient, payments_cfg),
            expected,
            "case: {case}"
        );
    }
}

#[tokio::test]
async fn test_select_community_forbidden_when_user_has_no_groups_in_community() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let other_community_id = Uuid::new_v4();
    let groups = sample_user_groups_by_community(other_community_id, ids.group_id);

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_user_has_community_permission().times(0);
    db.expect_list_user_groups()
        .times(1)
        .withf(move |user_id| *user_id == ids.user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_update_session().times(0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/group/community/{}/select", ids.community_id),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_select_community_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let groups = sample_user_groups_by_community(ids.community_id, ids.group_id);

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_user_has_community_permission().times(0);
    db.expect_list_user_groups()
        .times(1)
        .withf(move |user_id| *user_id == ids.user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id
                && record
                    .data
                    .get(SELECTED_COMMUNITY_ID_KEY)
                    .is_some_and(|value| value == &json!(ids.community_id))
                && record
                    .data
                    .get(SELECTED_GROUP_ID_KEY)
                    .is_some_and(|value| value == &json!(ids.group_id))
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/group/community/{}/select", ids.community_id),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

#[tokio::test]
async fn test_select_group_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_session(&mut db, &ids);
    db.expect_group_belongs_to_community()
        .times(1)
        .withf(move |community_id, group_id| {
            *community_id == ids.community_id && *group_id == ids.group_id
        })
        .returning(|_, _| Ok(true));
    expect_group_permission_result(&mut db, &ids, GroupPermission::Read, true);
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id
                && record
                    .data
                    .get(SELECTED_GROUP_ID_KEY)
                    .is_some_and(|value| value == &json!(ids.group_id))
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/group/{}/select", ids.group_id),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}
