use anyhow::anyhow;
use axum::http::StatusCode;
use serde_json::json;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::{
        auth::session_context::SELECTED_GROUP_ID_KEY, error::INVALID_REQUEST_PAYLOAD, tests::*,
    },
    types::{
        dashboard::{DASHBOARD_PAGINATION_LIMIT, community::groups::CommunityGroupsOutput},
        group::{GroupFull, GroupParentOption},
        permissions::CommunityPermission,
    },
};

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let groups_output = CommunityGroupsOutput {
        groups: vec![sample_group_summary(ids.group_id)],
        total: 1,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::Read);
    expect_community_permission_result(&mut db, &ids, CommunityPermission::GroupsWrite, true);
    db.expect_list_community_groups()
        .times(1)
        .withf(move |community_id, filters| {
            *community_id == ids.community_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && filters.ts_query.as_deref() == Some("rust")
        })
        .returning(move |_, _| Ok(groups_output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/community/groups?ts_query=rust", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the listed groups are rendered
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(html.contains("Open group dashboard: Test Group"));
}

#[tokio::test]
async fn test_list_page_allows_empty_search_query() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let groups_output = CommunityGroupsOutput {
        groups: vec![sample_group_summary(ids.group_id)],
        total: 1,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::Read);
    expect_community_permission_result(&mut db, &ids, CommunityPermission::GroupsWrite, true);
    db.expect_list_community_groups()
        .times(1)
        .withf(move |community_id, filters| {
            *community_id == ids.community_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && filters.ts_query.is_none()
        })
        .returning(move |_, _| Ok(groups_output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/community/groups?ts_query=", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_add_page_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let categories = vec![sample_group_category()];
    let regions = vec![sample_group_region()];

    // Setup database mock
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::Read);
    db.expect_list_group_categories()
        .times(1)
        .withf(move |community_id| *community_id == ids.community_id)
        .returning(move |_| Ok(categories.clone()));
    db.expect_list_group_parent_options()
        .times(1)
        .withf(move |community_id, user_id, group_id| {
            *community_id == ids.community_id && *user_id == ids.user_id && group_id.is_none()
        })
        .returning(|_, _, _| Ok(vec![]));
    db.expect_list_regions()
        .times(1)
        .withf(move |community_id| *community_id == ids.community_id)
        .returning(move |_| Ok(regions.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/community/groups/add", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_update_page_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let group_full = GroupFull {
        custom_logo_url: Some("https://example.test/group-logo.png".to_string()),
        description_short: Some("Short group description".to_string()),
        logo_url: "https://example.test/group-logo.png".to_string(),
        ..sample_group_full(ids.community_id, ids.group_id)
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_update_page_reads(&mut db, &ids, group_full, vec![]);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/community/groups/{}/update", ids.group_id),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the group details are rendered in the form
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_image_field_value(&html, "logo_url", "https://example.test/group-logo.png");
    assert!(html.contains(r#"value="Short group description""#));
}

#[tokio::test]
async fn test_update_page_leaves_logo_field_empty_without_own_logo() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let group_full = GroupFull {
        custom_logo_url: None,
        logo_url: "https://example.test/community-logo.png".to_string(),
        ..sample_group_full(ids.community_id, ids.group_id)
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_update_page_reads(&mut db, &ids, group_full, vec![]);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/community/groups/{}/update", ids.group_id),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the community fallback logo is not prefilled
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_image_field_value(&html, "logo_url", "");
}

#[tokio::test]
async fn test_update_page_selects_current_inactive_parent_option() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let parent_group_id = Uuid::new_v4();
    let parent_option = GroupParentOption {
        active: false,
        group_id: parent_group_id,
        is_current: true,
        is_selectable: false,
        name: "Inactive Parent".to_string(),
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_update_page_reads(
        &mut db,
        &ids,
        sample_group_full(ids.community_id, ids.group_id),
        vec![parent_option],
    );

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/community/groups/{}/update", ids.group_id),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the current parent is selected and flagged as no longer selectable
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    let option_start = body
        .find(&format!("value=\"{parent_group_id}\""))
        .expect("parent option should render");
    let option_end = body[option_start..]
        .find("</option>")
        .expect("parent option should close");
    let option_html = &body[option_start..option_start + option_end];
    assert!(option_html.contains("selected"));
    assert!(option_html.contains("(current, no longer selectable)"));
}

#[tokio::test]
async fn test_add_success_auto_selects_group() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let category_id = Uuid::new_v4();
    let new_group_id = Uuid::new_v4();
    let body = serde_qs::to_string(&sample_group_form(category_id)).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::GroupsWrite);
    db.expect_add_group()
        .times(1)
        .withf(move |user_id, community_id, group| {
            *user_id == ids.user_id
                && *community_id == ids.community_id
                && group.name == "Test Group"
                && group.category_id == category_id
                && group.description == "Group description"
                && group.description_short.as_deref() == Some("Short group description")
        })
        .returning(move |_, _, _| Ok(new_group_id));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id
                && record
                    .data
                    .get(SELECTED_GROUP_ID_KEY)
                    .is_some_and(|value| value == &json!(new_group_id))
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "POST",
        "/dashboard/community/groups/add",
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
async fn test_add_success_keeps_existing_group_selection() {
    // Setup identifiers and data structures, with a group already selected
    let ids = DashboardIds::new();
    let category_id = Uuid::new_v4();
    let body = serde_qs::to_string(&sample_group_form(category_id)).unwrap();

    // Setup database mock without a group selection write
    let mut db = MockDB::new();
    expect_group_session(&mut db, &ids);
    expect_community_permission_result(&mut db, &ids, CommunityPermission::GroupsWrite, true);
    db.expect_add_group()
        .times(1)
        .withf(move |user_id, community_id, group| {
            *user_id == ids.user_id
                && *community_id == ids.community_id
                && group.category_id == category_id
        })
        .returning(|_, _, _| Ok(Uuid::new_v4()));
    db.expect_update_session().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "POST",
        "/dashboard/community/groups/add",
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
    let category_id = Uuid::new_v4();
    let body = serde_qs::to_string(&sample_group_form(category_id)).unwrap();

    // Setup database mock with a failing write and no group selection write
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::GroupsWrite);
    db.expect_add_group()
        .times(1)
        .withf(move |user_id, community_id, group| {
            *user_id == ids.user_id
                && *community_id == ids.community_id
                && group.category_id == category_id
        })
        .returning(|_, _, _| Err(anyhow!("db error")));
    db.expect_update_session().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "POST",
        "/dashboard/community/groups/add",
        ids.session_id,
        body,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_add_invalid_payload() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::GroupsWrite);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "POST",
        "/dashboard/community/groups/add",
        ids.session_id,
        "invalid-body",
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), INVALID_REQUEST_PAYLOAD.as_bytes());
}

#[tokio::test]
async fn test_update_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let category_id = Uuid::new_v4();
    let body = serde_qs::to_string(&sample_group_form(category_id)).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::GroupsWrite);
    db.expect_update_group()
        .times(1)
        .withf(move |user_id, community_id, group_id, group| {
            *user_id == ids.user_id
                && *community_id == ids.community_id
                && *group_id == ids.group_id
                && group.category_id == category_id
                && group.description_short.as_deref() == Some("Short group description")
        })
        .returning(|_, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/community/groups/{}/update", ids.group_id),
        ids.session_id,
        body,
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
async fn test_update_invalid_payload() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::GroupsWrite);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/community/groups/{}/update", ids.group_id),
        ids.session_id,
        "invalid-body",
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), INVALID_REQUEST_PAYLOAD.as_bytes());
}

#[tokio::test]
async fn test_activate_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::GroupsWrite);
    db.expect_activate_group()
        .times(1)
        .withf(move |user_id, community_id, group_id| {
            *user_id == ids.user_id
                && *community_id == ids.community_id
                && *group_id == ids.group_id
        })
        .returning(|_, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/community/groups/{}/activate", ids.group_id),
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
async fn test_deactivate_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::GroupsWrite);
    db.expect_deactivate_group()
        .times(1)
        .withf(move |user_id, community_id, group_id| {
            *user_id == ids.user_id
                && *community_id == ids.community_id
                && *group_id == ids.group_id
        })
        .returning(|_, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/community/groups/{}/deactivate", ids.group_id),
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
async fn test_delete_non_selected_group() {
    // Setup identifiers, deleting a group other than the selected one
    let ids = DashboardIds::new();
    let deleted_group_id = Uuid::new_v4();

    // Setup database mock without a group selection change
    let mut db = MockDB::new();
    expect_group_session(&mut db, &ids);
    expect_community_permission_result(&mut db, &ids, CommunityPermission::GroupsWrite, true);
    db.expect_delete_group()
        .times(1)
        .withf(move |user_id, community_id, group_id| {
            *user_id == ids.user_id
                && *community_id == ids.community_id
                && *group_id == deleted_group_id
        })
        .returning(|_, _, _| Ok(()));
    db.expect_list_user_groups().never();
    db.expect_update_session().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "DELETE",
        &format!("/dashboard/community/groups/{deleted_group_id}/delete"),
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
async fn test_delete_selected_group_updates_selection() {
    // Setup identifiers, deleting the selected group
    let ids = DashboardIds::new();
    let next_group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_session(&mut db, &ids);
    expect_community_permission_result(&mut db, &ids, CommunityPermission::GroupsWrite, true);
    db.expect_delete_group()
        .times(1)
        .withf(move |user_id, community_id, group_id| {
            *user_id == ids.user_id
                && *community_id == ids.community_id
                && *group_id == ids.group_id
        })
        .returning(|_, _, _| Ok(()));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |user_id| *user_id == ids.user_id)
        .returning(move |_| {
            Ok(sample_user_groups_by_community(
                ids.community_id,
                next_group_id,
            ))
        });
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id
                && record
                    .data
                    .get(SELECTED_GROUP_ID_KEY)
                    .is_some_and(|value| value == &json!(next_group_id))
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "DELETE",
        &format!("/dashboard/community/groups/{}/delete", ids.group_id),
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
async fn test_delete_selected_group_without_fallback_clears_selection() {
    // Setup identifiers, deleting the selected group
    let ids = DashboardIds::new();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_session(&mut db, &ids);
    expect_community_permission_result(&mut db, &ids, CommunityPermission::GroupsWrite, true);
    db.expect_delete_group()
        .times(1)
        .withf(move |user_id, community_id, group_id| {
            *user_id == ids.user_id
                && *community_id == ids.community_id
                && *group_id == ids.group_id
        })
        .returning(|_, _, _| Ok(()));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |user_id| *user_id == ids.user_id)
        .returning(|_| Ok(vec![]));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id && !record.data.contains_key(SELECTED_GROUP_ID_KEY)
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "DELETE",
        &format!("/dashboard/community/groups/{}/delete", ids.group_id),
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

// Helpers.

/// Expects the reads the update page performs for the group and its parent
/// options.
fn expect_update_page_reads(
    db: &mut MockDB,
    ids: &DashboardIds,
    group_full: GroupFull,
    parent_options: Vec<GroupParentOption>,
) {
    let ids = *ids;
    expect_community_access(db, &ids, CommunityPermission::Read);
    expect_community_permission_result(db, &ids, CommunityPermission::GroupsWrite, true);
    db.expect_get_group_full()
        .times(1)
        .withf(move |community_id, group_id| {
            *community_id == ids.community_id && *group_id == ids.group_id
        })
        .returning(move |_, _| Ok(group_full.clone()));
    db.expect_group_has_child_links()
        .times(1)
        .withf(move |community_id, group_id| {
            *community_id == ids.community_id && *group_id == ids.group_id
        })
        .returning(|_, _| Ok(false));
    db.expect_list_group_categories()
        .times(1)
        .withf(move |community_id| *community_id == ids.community_id)
        .returning(|_| Ok(vec![sample_group_category()]));
    db.expect_list_group_parent_options()
        .times(1)
        .withf(move |community_id, user_id, group_id| {
            *community_id == ids.community_id
                && *user_id == ids.user_id
                && *group_id == Some(ids.group_id)
        })
        .returning(move |_, _, _| Ok(parent_options.clone()));
    db.expect_list_regions()
        .times(1)
        .withf(move |community_id| *community_id == ids.community_id)
        .returning(|_| Ok(vec![sample_group_region()]));
}
