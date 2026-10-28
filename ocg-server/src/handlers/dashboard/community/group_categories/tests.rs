use axum::http::StatusCode;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    types::{group::GroupCategory, permissions::CommunityPermission},
};

use super::GroupCategoryInput;

#[tokio::test]
async fn test_add_invalid_payload() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::TaxonomyWrite);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "POST",
        "/dashboard/community/group-categories/add",
        ids.session_id,
        "name=",
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        bytes.as_ref(),
        b"name: value cannot be empty or whitespace-only\n"
    );
}

#[tokio::test]
async fn test_add_page_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::Read);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/community/group-categories/add", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_add_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let form = GroupCategoryInput {
        name: "Platform Engineering".to_string(),
    };
    let body = serde_qs::to_string(&form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::TaxonomyWrite);
    db.expect_add_group_category()
        .times(1)
        .withf(move |user_id, community_id, category| {
            *user_id == ids.user_id
                && *community_id == ids.community_id
                && category.name == form.name
        })
        .returning(|_, _, _| Ok(Uuid::new_v4()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "POST",
        "/dashboard/community/group-categories/add",
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
async fn test_delete_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let group_category_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::TaxonomyWrite);
    db.expect_delete_group_category()
        .times(1)
        .withf(move |user_id, community_id, id| {
            *user_id == ids.user_id && *community_id == ids.community_id && *id == group_category_id
        })
        .returning(|_, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "DELETE",
        &format!("/dashboard/community/group-categories/{group_category_id}/delete"),
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
async fn test_list_page_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_page_reads(&mut db, &ids, vec![sample_group_category()]);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/community/group-categories", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the listed category is rendered
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains(r#"aria-label="Edit group category: Meetup""#));
}

#[tokio::test]
async fn test_update_invalid_payload() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let group_category_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::TaxonomyWrite);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/community/group-categories/{group_category_id}/update"),
        ids.session_id,
        "name=",
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        bytes.as_ref(),
        b"name: value cannot be empty or whitespace-only\n"
    );
}

#[tokio::test]
async fn test_update_page_not_found() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let group_category_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_page_reads(&mut db, &ids, vec![sample_group_category()]);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/community/group-categories/{group_category_id}/update"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), b"group category not found");
}

#[tokio::test]
async fn test_update_page_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let group_category_id = Uuid::new_v4();
    let category = GroupCategory {
        group_category_id,
        name: "Platform Engineering".to_string(),
        ..sample_group_category()
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_page_reads(&mut db, &ids, vec![sample_group_category(), category]);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/community/group-categories/{group_category_id}/update"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the requested category is rendered in the form
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains(&format!(
        r#"hx-put="/dashboard/community/group-categories/{group_category_id}/update""#
    )));
    assert!(body.contains(r#"value="Platform Engineering""#));
}

#[tokio::test]
async fn test_update_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let group_category_id = Uuid::new_v4();
    let form = GroupCategoryInput {
        name: "Cloud Native".to_string(),
    };
    let body = serde_qs::to_string(&form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::TaxonomyWrite);
    db.expect_update_group_category()
        .times(1)
        .withf(move |user_id, community_id, id, category| {
            *user_id == ids.user_id
                && *community_id == ids.community_id
                && *id == group_category_id
                && category.name == form.name
        })
        .returning(|_, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/community/group-categories/{group_category_id}/update"),
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

// Helpers.

/// Expects the reads the list and update pages perform.
fn expect_page_reads(db: &mut MockDB, ids: &DashboardIds, categories: Vec<GroupCategory>) {
    let ids = *ids;
    expect_community_access(db, &ids, CommunityPermission::Read);
    expect_community_permission_result(db, &ids, CommunityPermission::TaxonomyWrite, true);
    db.expect_list_group_categories()
        .times(1)
        .withf(move |community_id| *community_id == ids.community_id)
        .returning(move |_| Ok(categories.clone()));
}
