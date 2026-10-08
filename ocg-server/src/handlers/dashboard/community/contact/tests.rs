use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderValue, Request, StatusCode,
        header::{CONTENT_TYPE, COOKIE, HOST},
    },
};
use axum_login::tower_sessions::session;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    services::notifications::MockNotificationsManager,
    types::{
        dashboard::community::contact::{
            CommunityContactFilterOptions, CommunityContactGroupCategoryOption,
            CommunityContactRecipientGroup, CommunityContactRecipientsSummary,
            CommunityContactRegionOption, RegionFilterValue,
        },
        group::GroupRole,
        permissions::CommunityPermission,
    },
    validation::{MAX_CONTACT_FILTER_VALUES, MAX_LEN_NOTIFICATION_BODY},
};

#[tokio::test]
async fn test_page_success_can_send() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    expect_community_permission(&mut db, community_id, user_id, CommunityPermission::Read);
    expect_contact_page_reads(&mut db, community_id, user_id, true);

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/community/contact")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the page renders the filters, summary and enabled send button
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8"),
    );
    assert!(html.contains(r#"name="filters[group_category_ids]""#));
    assert!(html.contains(r#"name="filters[regions]""#));
    assert!(html.contains(r#"name="filters[roles]""#));
    assert!(html.contains("Platform (2)"));
    assert!(html.contains("No region (1)"));
    assert!(html.contains(r#"data-people-count="3""#));
    assert!(html.contains(r#"data-can-send="true""#));
    assert!(html.contains(r#"data-skip-validation="true""#));
    assert!(!html.contains("Your role cannot send emails to group teams."));
}

#[tokio::test]
async fn test_page_success_cannot_send() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    expect_community_permission(&mut db, community_id, user_id, CommunityPermission::Read);
    expect_contact_page_reads(&mut db, community_id, user_id, false);

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/community/contact")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check sending is disabled for the read-only user
    assert_eq!(parts.status, StatusCode::OK);
    assert!(html.contains(r#"data-can-send="false""#));
    assert!(html.contains("Your role cannot send emails to group teams."));
}

#[tokio::test]
async fn test_recipients_parses_filters() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_category_id = Uuid::new_v4();
    let region_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let query = format!(
        "filters%5Bgroup_category_ids%5D%5B%5D={group_category_id}\
         &filters%5Bregions%5D%5B%5D=none\
         &filters%5Bregions%5D%5B%5D={region_id}\
         &filters%5Broles%5D%5B%5D=events-manager"
    );

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    expect_community_permission(&mut db, community_id, user_id, CommunityPermission::Read);
    db.expect_get_community_contact_recipients_summary()
        .times(1)
        .withf(move |cid, filters| {
            *cid == community_id
                && filters.group_category_ids == vec![group_category_id]
                && filters.regions
                    == vec![
                        RegionFilterValue::NoRegion,
                        RegionFilterValue::Region(region_id),
                    ]
                && filters.roles == vec![GroupRole::EventsManager]
        })
        .returning(|_, _| Ok(sample_summary()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/dashboard/community/contact/recipients?{query}"))
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the summary renders with the canonical filters key
    assert_eq!(parts.status, StatusCode::OK);
    assert!(html.contains(r#"data-people-count="3""#));
    assert!(html.contains(&format!(
        r#"data-filters-key="filters%5Bgroup_category_ids%5D%5B%5D={group_category_id}"#
    )));
    assert!(html.contains("Group One"));
    assert!(html.contains("Show groups"));
}

#[tokio::test]
async fn test_recipients_rejects_oversized_filters() {
    // Setup identifiers and an oversized role filter
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let query = vec!["filters%5Broles%5D%5B%5D=admin"; MAX_CONTACT_FILTER_VALUES + 1].join("&");

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    expect_community_permission(&mut db, community_id, user_id, CommunityPermission::Read);
    db.expect_get_community_contact_recipients_summary().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!("/dashboard/community/contact/recipients?{query}"))
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();

    // Check the oversized filter is rejected before reading recipients
    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_send_community_custom_notification_blank_body() {
    assert_send_rejected("subject=Hello&body=+++").await;
}

#[tokio::test]
async fn test_send_community_custom_notification_db_error() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    expect_community_permission(
        &mut db,
        community_id,
        user_id,
        CommunityPermission::GroupsWrite,
    );
    expect_send_context(&mut db, community_id);
    db.expect_enqueue_tracked_community_custom_notification()
        .times(1)
        .returning(|_| Err(anyhow::anyhow!("db error")));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let response = router
        .oneshot(send_request(session_id, "subject=Hello&body=World"))
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_send_community_custom_notification_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_category_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let form_data = format!(
        "subject=Team+update&body=Hello+teams\
         &filters%5Bgroup_category_ids%5D%5B%5D={group_category_id}\
         &filters%5Bregions%5D%5B%5D=none\
         &filters%5Broles%5D%5B%5D=admin"
    );

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    expect_community_permission(
        &mut db,
        community_id,
        user_id,
        CommunityPermission::GroupsWrite,
    );
    expect_send_context(&mut db, community_id);
    db.expect_enqueue_tracked_community_custom_notification()
        .times(1)
        .withf(move |input| {
            input.body == "Hello teams"
                && input.community_id == community_id
                && input.created_by == user_id
                && input.filters.group_category_ids == vec![group_category_id]
                && input.filters.regions == vec![RegionFilterValue::NoRegion]
                && input.filters.roles == vec![GroupRole::Admin]
                && input.subject == "Team update"
                && input.template_data["community_display_name"] == "Test"
        })
        .returning(|_| Ok(2));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let response = router.oneshot(send_request(session_id, &form_data)).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_send_community_custom_notification_too_long_body() {
    let body = "a".repeat(MAX_LEN_NOTIFICATION_BODY + 1);
    assert_send_rejected(&format!("subject=Hello&body={body}")).await;
}

// Helpers.

/// Sends an invalid contact form and checks it is rejected before enqueueing.
async fn assert_send_rejected(form_data: &str) {
    // Setup identifiers
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_community_session(&mut db, session_id, user_id, community_id);
    expect_community_permission(
        &mut db,
        community_id,
        user_id,
        CommunityPermission::GroupsWrite,
    );
    db.expect_enqueue_tracked_community_custom_notification().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let response = router.oneshot(send_request(session_id, form_data)).await.unwrap();

    // Check the form is rejected
    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

/// Configures the reads used to prepare the contact page.
fn expect_contact_page_reads(db: &mut MockDB, community_id: Uuid, user_id: Uuid, can_send: bool) {
    db.expect_get_community_summary()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(sample_community_summary(community_id)));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == community_id
                && *uid == user_id
                && *permission == CommunityPermission::GroupsWrite
        })
        .returning(move |_, _, _| Ok(can_send));
    db.expect_list_community_contact_filter_options()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(|_| Ok(sample_filter_options()));
    db.expect_list_group_roles()
        .times(1)
        .returning(|| Ok(vec![sample_group_role_summary()]));
    db.expect_get_community_contact_recipients_summary()
        .times(1)
        .withf(move |cid, filters| {
            *cid == community_id
                && filters.group_category_ids.is_empty()
                && filters.regions.is_empty()
                && filters.roles.is_empty()
        })
        .returning(|_, _| Ok(sample_summary()));
}

/// Configures the context reads used to build the community email.
fn expect_send_context(db: &mut MockDB, community_id: Uuid) {
    db.expect_get_community_summary()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(sample_community_summary(community_id)));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
}

/// Returns contact filter options with one category and one region.
fn sample_filter_options() -> CommunityContactFilterOptions {
    CommunityContactFilterOptions {
        group_categories: vec![CommunityContactGroupCategoryOption {
            group_category_id: Uuid::new_v4(),
            groups_count: 2,
            name: "Platform".to_string(),
        }],
        no_region_groups_count: 1,
        regions: vec![CommunityContactRegionOption {
            groups_count: 1,
            name: "Europe".to_string(),
            region_id: Uuid::new_v4(),
        }],
    }
}

/// Returns a recipients summary with one contributing group.
fn sample_summary() -> CommunityContactRecipientsSummary {
    CommunityContactRecipientsSummary {
        groups: vec![CommunityContactRecipientGroup {
            group_category_name: "Platform".to_string(),
            group_id: Uuid::new_v4(),
            name: "Group One".to_string(),
            seats_count: 4,
            region_name: Some("Europe".to_string()),
        }],
        groups_count: 1,
        people_count: 3,
        seats_count: 4,
    }
}

/// Builds a send request for the community contact form.
fn send_request(session_id: session::Id, form_data: &str) -> Request<Body> {
    Request::builder()
        .method("POST")
        .uri("/dashboard/community/notifications")
        .header(HOST, "example.test")
        .header(COOKIE, format!("id={session_id}"))
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(form_data.to_string()))
        .unwrap()
}
