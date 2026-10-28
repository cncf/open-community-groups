use axum::http::{HeaderValue, StatusCode};
use chrono::NaiveDate;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    types::{dashboard::common::AuditLogSort, permissions::GroupPermission},
};

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let output = sample_audit_logs_output();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    db.expect_list_group_audit_logs()
        .times(1)
        .withf(move |id, filters| {
            *id == ids.group_id
                && filters.action.as_deref() == Some("group_updated")
                && filters.actor.as_deref() == Some("test-user")
                && filters.date_from == Some(NaiveDate::from_ymd_opt(2024, 1, 1).unwrap())
                && filters.date_to == Some(NaiveDate::from_ymd_opt(2024, 1, 31).unwrap())
                && filters.limit == Some(5)
                && filters.offset == Some(10)
                && filters.sort == Some(AuditLogSort::CreatedAsc)
        })
        .returning(move |_, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        "/dashboard/group/logs?action=group_updated&actor=test-user\
         &date_from=2024-01-01&date_to=2024-01-31&limit=5&offset=10&sort=created-asc",
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url").unwrap(),
        &HeaderValue::from_static(concat!(
            "/dashboard/group?tab=logs&action=group_updated&actor=test-user",
            "&date_from=2024-01-01&date_to=2024-01-31&limit=5&offset=10&sort=created-asc",
        )),
    );
    assert!(body.contains("id=\"audit-actor\""));
    assert!(body.contains("Community updated"));
    assert!(body.contains("Schedule updated"));
}
