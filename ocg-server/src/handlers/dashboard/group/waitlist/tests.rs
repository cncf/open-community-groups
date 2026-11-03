use axum::http::StatusCode;
use mockall::Sequence;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    types::{
        dashboard::{
            DASHBOARD_PAGINATION_LIMIT,
            group::{
                PresenceFilter,
                waitlist::{WaitlistOutput, WaitlistSort},
            },
        },
        permissions::GroupPermission,
    },
};

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let output = WaitlistOutput {
        total: 1,
        waitlist: vec![sample_waitlist_entry()],
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_list_page_context(&mut db, &ids, event_id);
    db.expect_search_event_waitlist()
        .times(1)
        .withf(move |gid, eid, filters| {
            *gid == ids.group_id
                && *eid == event_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/waitlist"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains("Waitlisted User"));
}

#[tokio::test]
async fn test_list_page_rejects_overlong_search_query() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!(
            "/dashboard/group/events/{event_id}/waitlist?ts_query={}",
            "a".repeat(251)
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "ts_query: length is greater than 250\n"
    );
}

#[tokio::test]
async fn test_list_page_rejects_zero_pagination_limit() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/waitlist?limit=0"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "limit: lower than 1\n"
    );
}

#[tokio::test]
async fn test_list_page_returns_not_found_for_event_of_another_group() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let output = WaitlistOutput {
        total: 1,
        waitlist: vec![sample_waitlist_entry()],
    };

    // Setup database mock without an event summary for the selected group
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);
    db.expect_find_event_summary_dashboard()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == ids.community_id && *gid == ids.group_id && *eid == event_id
        })
        .returning(|_, _, _| Ok(None));
    db.expect_search_event_waitlist()
        .times(1)
        .withf(move |gid, eid, _| *gid == ids.group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/waitlist"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the page is not found
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_list_page_steps_back_to_last_page_when_offset_is_past_end() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let empty_page = WaitlistOutput {
        total: 6,
        waitlist: vec![],
    };
    let last_page = WaitlistOutput {
        total: 6,
        waitlist: vec![sample_waitlist_entry()],
    };

    // Setup the empty requested page followed by the last page with rows
    let mut db = MockDB::new();
    expect_list_page_context(&mut db, &ids, event_id);
    let mut sequence = Sequence::new();
    db.expect_search_event_waitlist()
        .times(1)
        .in_sequence(&mut sequence)
        .withf(move |gid, eid, filters| {
            *gid == ids.group_id
                && *eid == event_id
                && filters.limit == Some(5)
                && filters.offset == Some(10)
        })
        .return_once(move |_, _, _| Ok(empty_page));
    db.expect_search_event_waitlist()
        .times(1)
        .in_sequence(&mut sequence)
        .withf(move |gid, eid, filters| {
            *gid == ids.group_id
                && *eid == event_id
                && filters.limit == Some(5)
                && filters.offset == Some(5)
        })
        .return_once(move |_, _, _| Ok(last_page));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/waitlist?limit=5&offset=10"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the last page with rows is rendered and refreshed in place
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains("Waitlisted User"));
    assert!(body.contains("offset=5"));
    assert!(!body.contains("offset=10"));
}

#[tokio::test]
async fn test_list_page_with_search_query() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let output = WaitlistOutput {
        total: 2,
        waitlist: vec![sample_waitlist_entry()],
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_list_page_context(&mut db, &ids, event_id);
    db.expect_search_event_waitlist()
        .times(1)
        .withf(move |gid, eid, filters| {
            *gid == ids.group_id
                && *eid == event_id
                && filters.limit == Some(1)
                && filters.offset == Some(0)
                && filters.sort == Some(WaitlistSort::NameAsc)
                && filters.title == Some(PresenceFilter::Present)
                && filters.ts_query.as_deref() == Some("wait")
        })
        .returning(move |_, _, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!(
            "/dashboard/group/events/{event_id}/waitlist?\
             limit=1&sort=name-asc&title=present&ts_query=wait"
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains("name=\"ts_query\""));
    assert!(body.contains("value=\"wait\""));
    assert!(body.contains("Waitlisted User"));
    assert!(body.contains("offset=1"));
    assert!(body.contains("ts_query=wait"));
    assert!(body.contains("refresh-event-waitlist"));
}

// Helpers.

/// Expects the session, permissions and event summary read by the list page.
fn expect_list_page_context(db: &mut MockDB, ids: &DashboardIds, event_id: Uuid) {
    let ids = *ids;
    let event = sample_event_summary(event_id);

    expect_group_access(db, &ids, GroupPermission::Read);
    expect_group_permission_result(db, &ids, GroupPermission::EventsWrite, true);
    db.expect_find_event_summary_dashboard()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == ids.community_id && *gid == ids.group_id && *eid == event_id
        })
        .returning(move |_, _, _| Ok(Some(event.clone())));
}
