use axum::http::StatusCode;

use crate::{
    db::mock::MockDB,
    handlers::{error::INVALID_REQUEST_PAYLOAD, tests::*},
    types::permissions::GroupPermission,
};

#[tokio::test]
async fn test_page_hides_cohosted_events_without_cohosted_events() {
    // Setup identifiers and stats without co-hosted events
    let ids = DashboardIds::new();
    let mut stats = sample_group_stats();
    stats.cohosted_events.per_month.clear();
    stats.cohosted_events.running_total.clear();
    stats.cohosted_events.total = 0;

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    db.expect_get_group_stats()
        .times(1)
        .withf(move |cid, gid, include_subgroups| {
            *cid == ids.community_id && *gid == ids.group_id && !*include_subgroups
        })
        .returning(move |_, _, _| Ok(stats.clone()));
    db.expect_group_has_active_subgroups()
        .times(1)
        .returning(|_, _| Ok(false));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group/analytics", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the co-hosted events section is omitted
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains("id=\"events-monthly-chart\""));
    assert!(!body.contains("Co-hosted events"));
    assert!(!body.contains("cohosted-events-monthly-chart"));
}

#[tokio::test]
async fn test_page_rejects_invalid_query() {
    // Setup identifiers and database mock without statistics reads
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    db.expect_get_group_stats().never();
    db.expect_group_has_active_subgroups().never();

    // Setup router and send request with an invalid flag
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        "/dashboard/group/analytics?include_subgroups=maybe",
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the query is rejected before loading statistics
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), INVALID_REQUEST_PAYLOAD.as_bytes());
}

#[tokio::test]
async fn test_page_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let stats = sample_group_stats();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    db.expect_get_group_stats()
        .times(1)
        .withf(move |cid, gid, include_subgroups| {
            *cid == ids.community_id && *gid == ids.group_id && *include_subgroups
        })
        .returning(move |_, _, _| Ok(stats.clone()));
    db.expect_group_has_active_subgroups()
        .times(1)
        .withf(move |cid, gid| *cid == ids.community_id && *gid == ids.group_id)
        .returning(|_, _| Ok(true));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        "/dashboard/group/analytics?include_subgroups=true",
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(include_subgroups_input(&body).contains("checked"));
    assert!(body.contains("Co-hosted events"));
    assert!(body.contains("id=\"cohosted-events-monthly-chart\""));
}

// Helpers.

/// Returns the include-subgroups checkbox markup from the rendered page.
fn include_subgroups_input(body: &str) -> &str {
    let start = body.find("<input id=\"include_subgroups\"").unwrap();
    let end = start + body[start..].find('>').unwrap();
    &body[start..end]
}
