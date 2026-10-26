use axum::http::StatusCode;
use serde_json::json;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::{
        auth::session_context::{SELECTED_COMMUNITY_ID_KEY, SELECTED_GROUP_ID_KEY},
        tests::*,
    },
    types::permissions::CommunityPermission,
};

#[tokio::test]
async fn test_select_community_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let groups = sample_user_groups_by_community(ids.community_id, ids.group_id);

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    expect_community_permission_result(&mut db, &ids, CommunityPermission::Read, true);
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
        &format!("/dashboard/community/{}/select", ids.community_id),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

#[tokio::test]
async fn test_select_community_without_groups() {
    // Setup identifiers and a session holding a stale group from another community
    let ids = DashboardIds::new();
    let stale_group_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        ids.session_id,
        ids.user_id,
        &auth_hash,
        None,
        Some(stale_group_id),
    );

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == ids.session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == ids.user_id)
        .returning(move |_| Ok(Some(sample_auth_user(ids.user_id, &auth_hash))));
    expect_community_permission_result(&mut db, &ids, CommunityPermission::Read, true);
    db.expect_list_user_groups()
        .times(1)
        .withf(move |user_id| *user_id == ids.user_id)
        .returning(|_| Ok(vec![]));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id
                && record
                    .data
                    .get(SELECTED_COMMUNITY_ID_KEY)
                    .is_some_and(|value| value == &json!(ids.community_id))
                && !record.data.contains_key(SELECTED_GROUP_ID_KEY)
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/community/{}/select", ids.community_id),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}
