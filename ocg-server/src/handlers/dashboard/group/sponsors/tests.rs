use axum::http::StatusCode;
use serde_qs::to_string;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::{dashboard::group::sponsors::SponsorFeatured, tests::*},
    types::{
        dashboard::{DASHBOARD_PAGINATION_LIMIT, group::sponsors::GroupSponsorsOutput},
        permissions::GroupPermission,
    },
};

#[tokio::test]
async fn test_add_invalid_body() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SponsorsWrite);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "POST",
        "/dashboard/group/sponsors/add",
        ids.session_id,
        INVALID_SPONSOR_FORM,
    );
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(body.contains("name: value cannot be empty or whitespace-only"));
    assert!(body.contains("logo_url: invalid image URL: not-a-url"));
}

#[tokio::test]
async fn test_add_page_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group/sponsors/add", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(featured_input(&body).contains("checked"));
}

#[tokio::test]
async fn test_add_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let form = sample_sponsor_form();
    let body = to_string(&form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SponsorsWrite);
    db.expect_add_group_sponsor()
        .times(1)
        .withf(move |actor_user_id, group_id, sponsor| {
            *actor_user_id == ids.user_id
                && *group_id == ids.group_id
                && sponsor.featured == form.featured
                && sponsor.name == form.name
                && sponsor.logo_url == form.logo_url
        })
        .returning(move |_, _, _| Ok(Uuid::new_v4()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "POST",
        "/dashboard/group/sponsors/add",
        ids.session_id,
        body,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::CREATED,
        "refresh-group-dashboard-table",
    );
}

#[tokio::test]
async fn test_delete_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let group_sponsor_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SponsorsWrite);
    db.expect_delete_group_sponsor()
        .times(1)
        .withf(move |actor_user_id, group_id, sponsor_id| {
            *actor_user_id == ids.user_id
                && *group_id == ids.group_id
                && *sponsor_id == group_sponsor_id
        })
        .returning(move |_, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "DELETE",
        &format!("/dashboard/group/sponsors/{group_sponsor_id}/delete"),
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
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let output = sample_sponsors_output();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::SponsorsWrite, true);
    db.expect_list_group_sponsors()
        .times(1)
        .withf(move |group_id, filters, full_list| {
            *group_id == ids.group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && !*full_list
        })
        .returning(move |_, _, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group/sponsors", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains("aria-label=\"Edit sponsor: Sponsor\""));
    assert!(body.contains("src=\"https://example.test/logo.png\""));
}

#[tokio::test]
async fn test_list_page_with_pagination_params() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let output = sample_sponsors_output();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::SponsorsWrite, true);
    db.expect_list_group_sponsors()
        .times(1)
        .withf(move |group_id, filters, full_list| {
            *group_id == ids.group_id
                && filters.limit == Some(5)
                && filters.offset == Some(10)
                && !*full_list
        })
        .returning(move |_, _, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        "/dashboard/group/sponsors?limit=5&offset=10",
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url").unwrap(),
        "/dashboard/group?tab=sponsors&limit=5&offset=10",
    );
    assert!(body.contains("aria-label=\"Edit sponsor: Sponsor\""));
}

#[tokio::test]
async fn test_update_featured_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let group_sponsor_id = Uuid::new_v4();
    let body = to_string(&SponsorFeatured { featured: false }).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SponsorsWrite);
    db.expect_update_group_sponsor_featured()
        .times(1)
        .withf(move |actor_user_id, group_id, sponsor_id, featured| {
            *actor_user_id == ids.user_id
                && *group_id == ids.group_id
                && *sponsor_id == group_sponsor_id
                && !*featured
        })
        .returning(move |_, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/group/sponsors/{group_sponsor_id}/featured"),
        ids.session_id,
        body,
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
async fn test_update_invalid_body() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let group_sponsor_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SponsorsWrite);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/group/sponsors/{group_sponsor_id}/update"),
        ids.session_id,
        INVALID_SPONSOR_FORM,
    );
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(body.contains("name: value cannot be empty or whitespace-only"));
    assert!(body.contains("logo_url: invalid image URL: not-a-url"));
}

#[tokio::test]
async fn test_update_page_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let group_sponsor_id = Uuid::new_v4();
    let mut sponsor = sample_group_sponsor();
    sponsor.featured = false;
    sponsor.group_sponsor_id = group_sponsor_id;

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::SponsorsWrite, true);
    db.expect_get_group_sponsor()
        .times(1)
        .withf(move |group_id, sponsor_id| {
            *group_id == ids.group_id && *sponsor_id == group_sponsor_id
        })
        .returning(move |_, _| Ok(sponsor.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/sponsors/{group_sponsor_id}/update"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains(&format!(
        "hx-put=\"/dashboard/group/sponsors/{group_sponsor_id}/update\""
    )));
    assert!(body.contains("value=\"Sponsor\""));
    assert!(body.contains("value=\"https://example.test/logo.png\""));
    assert!(!featured_input(&body).contains("checked"));
}

#[tokio::test]
async fn test_update_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let group_sponsor_id = Uuid::new_v4();
    let form = sample_sponsor_form();
    let body = to_string(&form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SponsorsWrite);
    db.expect_update_group_sponsor()
        .times(1)
        .withf(move |actor_user_id, group_id, sponsor_id, sponsor| {
            *actor_user_id == ids.user_id
                && *group_id == ids.group_id
                && *sponsor_id == group_sponsor_id
                && sponsor.featured == form.featured
                && sponsor.name == form.name
                && sponsor.logo_url == form.logo_url
        })
        .returning(move |_, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/group/sponsors/{group_sponsor_id}/update"),
        ids.session_id,
        body,
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

/// Sponsor form with an empty name and an invalid logo URL.
const INVALID_SPONSOR_FORM: &str = "name=&logo_url=not-a-url";

/// Returns the featured checkbox tag of a rendered sponsor form.
fn featured_input(body: &str) -> &str {
    let start = body.find("<input id=\"featured\"").unwrap();
    let end = start + body[start..].find('>').unwrap();
    &body[start..end]
}

/// Returns a sponsors list output with the sample sponsor.
fn sample_sponsors_output() -> GroupSponsorsOutput {
    GroupSponsorsOutput {
        sponsors: vec![sample_group_sponsor()],
        total: 1,
    }
}
