use axum::{
    body::{Body, to_bytes},
    http::{
        Request, StatusCode,
        header::{COOKIE, LOCATION},
    },
};
use axum_login::tower_sessions::session;
use chrono::{Duration, Utc};
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    services::notifications::MockNotificationsManager,
    types::{dashboard::group::event_analytics::EventAnalytics, permissions::GroupPermission},
};

#[tokio::test]
async fn test_page_explains_missing_daily_charts_for_unpublished_events() {
    // Setup statistics of a never published event
    let mut stats = sample_event_analytics();
    stats.event.published = false;
    stats.event.published_at = None;
    stats.range = None;

    // Run the request
    let (response_status, body) = request_page(stats).await;

    // Check the daily charts are replaced by an explanation
    assert_eq!(response_status, StatusCode::OK);
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

    // Run the request
    let (response_status, body) = request_page(stats).await;

    // Check the explanation names the missing publication date
    assert_eq!(response_status, StatusCode::OK);
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

    // Run the request
    let (response_status, body) = request_page(stats).await;

    // Check the check-in card and section are omitted
    assert_eq!(response_status, StatusCode::OK);
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

    // Run the request
    let (response_status, body) = request_page(stats).await;

    // Check the surveys section is omitted
    assert_eq!(response_status, StatusCode::OK);
    assert!(!body.contains("data-event-analytics-surveys"));
    assert!(!body.contains("Overall response rate"));
}

#[tokio::test]
async fn test_page_hides_tickets_for_free_events() {
    // Setup statistics of a free event
    let mut stats = sample_event_analytics();
    stats.event.is_paid = false;
    stats.tickets = None;

    // Run the request
    let (response_status, body) = request_page(stats).await;

    // Check the tickets section is omitted
    assert_eq!(response_status, StatusCode::OK);
    assert!(!body.contains("data-event-analytics-tickets"));
    assert!(!body.contains("role=\"progressbar\""));
}

#[tokio::test]
async fn test_page_redirects_users_without_group_access() {
    // Setup identifiers
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup a session whose user lost access to every group
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(|_| Ok(vec![]));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == session_id && !record.data.contains_key("selected_group_id")
        })
        .returning(|_| Ok(()));
    db.expect_group_has_event().never();
    db.expect_get_event_analytics().never();

    // Run the request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/dashboard/group/events/{event_id}/analytics"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();

    // Check the user is sent away before any analytics read
    assert_eq!(response.status(), StatusCode::SEE_OTHER);
    assert_eq!(
        response.headers().get(LOCATION).unwrap(),
        "/dashboard/user?tab=invitations"
    );
}

#[tokio::test]
async fn test_page_returns_not_found_for_unavailable_events() {
    // Setup identifiers
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup a foreign, co-hosted or deleted event
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    db.expect_group_has_event()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .returning(|_, _| Ok(false));
    db.expect_get_event_analytics().never();

    // Run the request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/dashboard/group/events/{event_id}/analytics"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the cached statistics are never served
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_page_returns_not_found_without_stats() {
    // Setup identifiers
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup an available event whose statistics are missing
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    db.expect_group_has_event()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .returning(|_, _| Ok(true));
    db.expect_get_event_analytics()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .returning(|_, _| Ok(None));

    // Run the request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/dashboard/group/events/{event_id}/analytics"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the missing statistics are reported as not found
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_page_success() {
    // Run the request for a past paid event
    let (response_status, body) = request_page(sample_event_analytics()).await;

    // Check the summary cards
    assert_eq!(response_status, StatusCode::OK);
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

    // Run the request
    let (response_status, body) = request_page(stats).await;

    // Check shares are replaced by warnings and raw totals remain
    assert_eq!(response_status, StatusCode::OK);
    assert!(body.contains("Traffic source attribution is unavailable"));
    assert!(body.contains("Shares of page views are unavailable"));
    assert!(!body.contains("id=\"event-utm-share-chart\""));
    assert!(body.contains("Unavailable"));
}

// Helpers.

/// Requests the analytics tab as a read-only group user and returns the
/// response status and body.
async fn request_page(stats: EventAnalytics) -> (StatusCode, String) {
    // Setup identifiers
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup a read-only group session and the analytics reads
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    db.expect_group_has_event()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .returning(|_, _| Ok(true));
    db.expect_get_event_analytics()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .returning(move |_, _| Ok(Some(stats.clone())));

    // Run the request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/dashboard/group/events/{event_id}/analytics"))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    (parts.status, String::from_utf8(bytes.to_vec()).unwrap())
}
