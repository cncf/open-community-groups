use axum::{
    body::Body,
    http::{Request, StatusCode, header::LOCATION},
};
use chrono::{Duration, Utc};
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    types::{dashboard::group::event_analytics::EventAnalytics, permissions::GroupPermission},
};

#[tokio::test]
async fn test_page_explains_missing_daily_charts_for_unpublished_events() {
    // Setup statistics of a never published event
    let mut stats = sample_event_analytics();
    stats.event.published = false;
    stats.event.published_at = None;
    stats.range = None;

    // Setup database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_page_reads(&mut db, &ids, event_id, stats);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, page_request(&ids, event_id)).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the daily charts are replaced by an explanation
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains("data-event-analytics-range-unavailable"));
    assert!(body.contains("this event is not published"));
    assert!(!body.contains("id=\"event-views-daily-chart\""));
    assert!(!body.contains("id=\"event-fill-curve-chart\""));
    assert!(body.contains("id=\"event-funnel-chart\""));
}

#[tokio::test]
async fn test_page_explains_missing_daily_charts_without_publication_date() {
    // Setup statistics of a published event without a recorded publication
    let mut stats = sample_event_analytics();
    stats.event.published_at = None;
    stats.range = None;

    // Setup database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_page_reads(&mut db, &ids, event_id, stats);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, page_request(&ids, event_id)).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the explanation names the missing publication date
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains("which is not recorded for this event"));
    assert!(!body.contains("this event is not published"));
    assert!(!body.contains("id=\"event-views-daily-chart\""));
}

#[tokio::test]
async fn test_page_hides_check_ins_before_the_event_ends() {
    // Setup statistics of an upcoming event
    let mut stats = sample_event_analytics();
    stats.event.ends_at = Some(Utc::now() + Duration::days(3));
    stats.event.starts_at = Some(Utc::now() + Duration::days(2));

    // Setup database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_page_reads(&mut db, &ids, event_id, stats);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, page_request(&ids, event_id)).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the check-in card and section are omitted
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(!body.contains("Check-in rate"));
    assert!(!body.contains("data-event-analytics-check-ins"));
    assert!(!body.contains("id=\"event-check-ins-chart\""));
}

#[tokio::test]
async fn test_page_hides_surveys_without_ready_surveys() {
    // Setup statistics of an event whose surveys are all drafts
    let mut stats = sample_event_analytics();
    stats.surveys.surveys = vec![];
    stats.surveys.total_eligible_count = 0;
    stats.surveys.total_eligible_respondents_count = 0;

    // Setup database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_page_reads(&mut db, &ids, event_id, stats);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, page_request(&ids, event_id)).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the surveys section is omitted
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(!body.contains("data-event-analytics-surveys"));
    assert!(!body.contains("Overall response rate"));
}

#[tokio::test]
async fn test_page_hides_tickets_for_free_events() {
    // Setup statistics of a free event
    let mut stats = sample_event_analytics();
    stats.event.is_paid = false;
    stats.tickets = None;

    // Setup database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_page_reads(&mut db, &ids, event_id, stats);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, page_request(&ids, event_id)).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the tickets section is omitted
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(!body.contains("data-event-analytics-tickets"));
    assert!(!body.contains("role=\"progressbar\""));
}

#[tokio::test]
async fn test_page_redirects_users_without_group_access() {
    // Setup a session whose user lost access to every group
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_session(&mut db, &ids);
    expect_group_permission_result(&mut db, &ids, GroupPermission::Read, false);
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(|_| Ok(vec![]));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id && !record.data.contains_key("selected_group_id")
        })
        .returning(|_| Ok(()));
    db.expect_group_has_event().never();
    db.expect_get_event_analytics().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, _) = send(router, page_request(&ids, event_id)).await;

    // Check the user is sent away before any analytics read
    assert_eq!(parts.status, StatusCode::SEE_OTHER);
    assert_eq!(
        parts.headers.get(LOCATION).unwrap(),
        "/dashboard/user?tab=invitations"
    );
}

#[tokio::test]
async fn test_page_returns_not_found_for_unavailable_events() {
    // Setup a foreign, co-hosted or deleted event
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    db.expect_group_has_event()
        .times(1)
        .withf(move |gid, eid| *gid == ids.group_id && *eid == event_id)
        .returning(|_, _| Ok(false));
    db.expect_get_event_analytics().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, page_request(&ids, event_id)).await;

    // Check the cached statistics are never served
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_page_returns_not_found_without_stats() {
    // Setup an available event whose statistics are missing
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    db.expect_group_has_event()
        .times(1)
        .withf(move |gid, eid| *gid == ids.group_id && *eid == event_id)
        .returning(|_, _| Ok(true));
    db.expect_get_event_analytics()
        .times(1)
        .withf(move |gid, eid| *gid == ids.group_id && *eid == event_id)
        .returning(|_, _| Ok(None));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, page_request(&ids, event_id)).await;

    // Check the missing statistics are reported as not found
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_page_success() {
    // Setup database mock for a past paid event
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_page_reads(&mut db, &ids, event_id, sample_event_analytics());

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, page_request(&ids, event_id)).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the summary cards
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains("Page views"));
    assert!(body.contains("Fill rate"));
    assert!(body.contains("40%"));
    assert!(body.contains("Conversion"));
    assert!(body.contains("Approximate registrations per page view"));
    assert!(body.contains("Check-in rate"));
    assert!(body.contains("75%"));
    assert!(body.contains("cached for up to an hour"));

    // Check the chart slots and data handoff
    for chart_id in [
        "event-check-ins-chart",
        "event-fill-curve-chart",
        "event-funnel-chart",
        "event-registration-paths-chart",
        "event-registrations-daily-chart",
        "event-utm-share-chart",
        "event-utm-values-chart",
        "event-views-daily-chart",
    ] {
        assert!(
            body.contains(&format!("id=\"{chart_id}\"")),
            "missing {chart_id}"
        );
    }
    assert!(body.contains("<script type=\"application/json\" data-event-analytics"));
    assert!(body.contains("src=\"/static/js/dashboard/group/event-analytics"));
    assert!(!body.contains("event-utm-sources-daily-chart"));

    // Check registration question answers render as option bars
    assert!(body.contains("data-event-analytics-question"));
    assert!(body.contains("id=\"event-analytics-question-0-options\""));
    assert!(body.contains("3 · 100%"));

    // Check the traffic totals and enrollment state
    assert!(body.contains("Total page views"));
    assert!(body.contains("Unattributed views"));
    assert!(body.contains("0 pending · 1 accepted · 0 rejected"));
    assert!(body.contains("data-event-analytics-admission-offers"));
    assert!(body.contains("1 expired (deadline passed)"));

    // Check the notes, tables and paid sections
    assert!(body.contains("3 views recorded after the event's last day (UTC) are not shown."));
    assert!(body.contains("Top 10 combinations by views; sorting applies to these rows."));
    assert!(body.contains("data-utm-dimension=\"campaign\""));
    assert!(body.contains("data-event-analytics-tickets"));
    assert!(body.contains("4 sold · 1 reserved · 5 remaining of 10"));
    assert!(body.contains("aria-valuemax=\"10\""));
    assert!(body.contains("SAVE10"));
    assert!(body.contains("Registration window: Mar 8, 2024 11:00 (publication)"));

    // Check the surveys summary renders without links to the surveys tab
    assert!(body.contains("data-event-analytics-surveys"));
    assert!(body.contains("Overall response rate"));
    assert!(body.contains("3 of 4 eligible attendees, across open and closed surveys"));
    assert!(body.contains("data-event-analytics-survey>"));
    assert!(body.contains("Feedback"));
    assert!(body.contains(">Closed</span>"));
    assert!(body.contains(r#"<span class="xl:hidden">3 / 4</span>"#));
    assert!(
        body.contains(
            r#"<span class="hidden xl:inline">3 of 4 eligible attendees responded</span>"#
        )
    );
    assert!(body.contains(r#"· <span class="font-semibold text-stone-900">75%</span>"#));
    assert!(body.contains("Survey counts are cached for up to an hour."));
    assert!(!body.contains("/surveys"));

    // Check no revenue information is rendered
    for revenue_text in ["Revenue", "revenue", "amount_minor", "currency"] {
        assert!(!body.contains(revenue_text), "unexpected {revenue_text}");
    }
}

#[tokio::test]
async fn test_page_warns_when_attribution_is_inconsistent() {
    // Setup statistics whose tagged views exceed the total views
    let mut stats = sample_event_analytics();
    stats.traffic.attribution_consistent = false;

    // Setup database mock
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_page_reads(&mut db, &ids, event_id, stats);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, page_request(&ids, event_id)).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check shares are replaced by warnings and raw totals remain
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains("Traffic source attribution is unavailable"));
    assert!(body.contains("Shares of page views are unavailable"));
    assert!(!body.contains("id=\"event-utm-share-chart\""));
    assert!(body.contains("Unavailable"));
}

// Helpers.

/// Expects the read-only group access and analytics reads of an available
/// event with the given statistics.
fn expect_page_reads(db: &mut MockDB, ids: &DashboardIds, event_id: Uuid, stats: EventAnalytics) {
    let ids = *ids;

    expect_group_access(db, &ids, GroupPermission::Read);
    db.expect_group_has_event()
        .times(1)
        .withf(move |gid, eid| *gid == ids.group_id && *eid == event_id)
        .returning(|_, _| Ok(true));
    db.expect_get_event_analytics()
        .times(1)
        .withf(move |gid, eid| *gid == ids.group_id && *eid == event_id)
        .returning(move |_, _| Ok(Some(stats.clone())));
}

/// Builds the analytics tab request for the event.
fn page_request(ids: &DashboardIds, event_id: Uuid) -> Request<Body> {
    get_request(
        &format!("/dashboard/group/events/{event_id}/analytics"),
        ids.session_id,
    )
}
