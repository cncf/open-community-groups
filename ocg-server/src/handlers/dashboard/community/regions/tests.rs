use axum::http::StatusCode;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    types::{group::GroupRegion, permissions::CommunityPermission},
};

use super::RegionInput;

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
        "/dashboard/community/regions/add",
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
    let request = get_request("/dashboard/community/regions/add", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_add_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let form = RegionInput {
        name: "North America".to_string(),
    };
    let body = serde_qs::to_string(&form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::TaxonomyWrite);
    db.expect_add_region()
        .times(1)
        .withf(move |user_id, community_id, region| {
            *user_id == ids.user_id && *community_id == ids.community_id && region.name == form.name
        })
        .returning(|_, _, _| Ok(Uuid::new_v4()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "POST",
        "/dashboard/community/regions/add",
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
    let region_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::TaxonomyWrite);
    db.expect_delete_region()
        .times(1)
        .withf(move |user_id, community_id, id| {
            *user_id == ids.user_id && *community_id == ids.community_id && *id == region_id
        })
        .returning(|_, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "DELETE",
        &format!("/dashboard/community/regions/{region_id}/delete"),
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
    expect_page_reads(&mut db, &ids, vec![sample_group_region()]);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/community/regions", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the listed region is rendered
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains(r#"aria-label="Edit region: North America""#));
}

#[tokio::test]
async fn test_update_invalid_payload() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let region_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::TaxonomyWrite);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/community/regions/{region_id}/update"),
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
    let region_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_page_reads(&mut db, &ids, vec![sample_group_region()]);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/community/regions/{region_id}/update"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), b"region not found");
}

#[tokio::test]
async fn test_update_page_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let region_id = Uuid::new_v4();
    let region = GroupRegion {
        region_id,
        name: "Europe".to_string(),
        ..sample_group_region()
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_page_reads(&mut db, &ids, vec![sample_group_region(), region]);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/community/regions/{region_id}/update"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the requested region is rendered in the form
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains(&format!(
        r#"hx-put="/dashboard/community/regions/{region_id}/update""#
    )));
    assert!(body.contains(r#"value="Europe""#));
}

#[tokio::test]
async fn test_update_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let region_id = Uuid::new_v4();
    let form = RegionInput {
        name: "South America".to_string(),
    };
    let body = serde_qs::to_string(&form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::TaxonomyWrite);
    db.expect_update_region()
        .times(1)
        .withf(move |user_id, community_id, id, region| {
            *user_id == ids.user_id
                && *community_id == ids.community_id
                && *id == region_id
                && region.name == form.name
        })
        .returning(|_, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/community/regions/{region_id}/update"),
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
fn expect_page_reads(db: &mut MockDB, ids: &DashboardIds, regions: Vec<GroupRegion>) {
    let ids = *ids;
    expect_community_access(db, &ids, CommunityPermission::Read);
    expect_community_permission_result(db, &ids, CommunityPermission::TaxonomyWrite, true);
    db.expect_list_regions()
        .times(1)
        .withf(move |community_id| *community_id == ids.community_id)
        .returning(move |_| Ok(regions.clone()));
}
