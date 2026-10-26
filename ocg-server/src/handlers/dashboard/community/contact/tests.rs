use axum::{
    body::Body,
    http::{HeaderValue, Request, StatusCode, header::CONTENT_TYPE},
};
use uuid::Uuid;

use crate::{
    db::mock::{MockDB, expect_site_settings},
    handlers::{error::INVALID_REQUEST_PAYLOAD, tests::*},
    types::{
        dashboard::community::contact::{
            CommunityContactFilterOptions, CommunityContactGroupCategoryOption,
            CommunityContactGroupLabel, CommunityContactRecipientGroup,
            CommunityContactRecipientsSummary, CommunityContactRegionOption, RegionFilterValue,
        },
        group::GroupRole,
        permissions::CommunityPermission,
    },
    validation::{MAX_CONTACT_FILTER_VALUES, MAX_LEN_NOTIFICATION_BODY},
};

#[tokio::test]
async fn test_page_success_can_send() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::Read);
    expect_community_permission_result(&mut db, &ids, CommunityPermission::GroupsWrite, true);
    expect_contact_page_reads(&mut db, &ids);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/community/contact", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the page renders the filter fields, options, summary and enabled send button
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(html.contains(r#"name="filters[group_category_ids]""#));
    assert!(html.contains(r#"name="filters[regions]""#));
    assert!(html.contains(r#"name="filters[roles]""#));
    assert!(html.contains(r#"name="filters[group_ids]""#));
    assert!(html.contains("Group One · Platform · Europe"));
    assert!(html.contains(r#"data-people-count="3""#));
    assert!(html.contains(r#"data-can-send="true""#));
    assert!(html.contains(r#"data-skip-validation="true""#));
    assert!(!html.contains("Your role cannot send emails to group teams."));
}

#[tokio::test]
async fn test_page_success_cannot_send() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::Read);
    expect_community_permission_result(&mut db, &ids, CommunityPermission::GroupsWrite, false);
    expect_contact_page_reads(&mut db, &ids);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/community/contact", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check sending is disabled for the read-only user
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(html.contains(r#"data-can-send="false""#));
    assert!(html.contains("Your role cannot send emails to group teams."));
}

#[tokio::test]
async fn test_recipients_defaults_missing_filters_to_all() {
    // Setup identifiers and forms without filters, as posted once every filter is cleared
    let ids = DashboardIds::new();
    let forms_data = ["", "subject=Team+update&body=Hello+teams"];

    for form_data in forms_data {
        // Setup database mock
        let mut db = MockDB::new();
        expect_community_access(&mut db, &ids, CommunityPermission::Read);
        db.expect_get_community_contact_recipients_summary()
            .times(1)
            .withf(move |community_id, filters| {
                *community_id == ids.community_id
                    && filters.group_category_ids.is_empty()
                    && filters.group_ids.is_empty()
                    && filters.regions.is_empty()
                    && filters.roles.is_empty()
            })
            .returning(|_, _| Ok(sample_summary()));

        // Setup router and send request
        let router = TestRouterBuilder::new(db).build().await;
        let (parts, bytes) = send(router, recipients_request(&ids, form_data)).await;
        let html = String::from_utf8(bytes.to_vec()).unwrap();

        // Check the summary covers every group team with an empty filters key
        assert_eq!(parts.status, StatusCode::OK, "form {form_data:?}");
        assert_eq!(
            parts.headers.get(CONTENT_TYPE).unwrap(),
            &HeaderValue::from_static("text/html; charset=utf-8"),
            "form {form_data:?}"
        );
        assert!(
            html.contains(r#"data-people-count="3""#),
            "form {form_data:?}"
        );
        assert!(
            html.contains(r#"data-filters-key="""#),
            "form {form_data:?}"
        );
    }
}

#[tokio::test]
async fn test_recipients_parses_filters() {
    // Setup identifiers and a form carrying the message of the contact form
    let ids = DashboardIds::new();
    let group_category_id = Uuid::new_v4();
    let region_id = Uuid::new_v4();
    let unmatched_group_id = Uuid::new_v4();
    let form_data = format!(
        "subject=Team+update&body=Hello+teams\
         &filters%5Bgroup_category_ids%5D%5B%5D={group_category_id}\
         &filters%5Bregions%5D%5B%5D=none\
         &filters%5Bregions%5D%5B%5D={region_id}\
         &filters%5Broles%5D%5B%5D=events-manager\
         &filters%5Bgroup_ids%5D%5B%5D={}\
         &filters%5Bgroup_ids%5D%5B%5D={unmatched_group_id}",
        ids.group_id
    );

    // Setup database mock
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::Read);
    db.expect_get_community_contact_recipients_summary()
        .times(1)
        .withf(move |community_id, filters| {
            *community_id == ids.community_id
                && filters.group_category_ids == vec![group_category_id]
                && filters.group_ids == vec![ids.group_id, unmatched_group_id]
                && filters.regions
                    == vec![
                        RegionFilterValue::NoRegion,
                        RegionFilterValue::Region(region_id),
                    ]
                && filters.roles == vec![GroupRole::EventsManager]
        })
        .returning(move |_, _| {
            Ok(CommunityContactRecipientsSummary {
                unmatched_groups: vec![CommunityContactGroupLabel {
                    group_id: unmatched_group_id,
                    label: "Group Two · Platform".to_string(),
                }],
                ..sample_summary()
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, recipients_request(&ids, &form_data)).await;
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the summary renders with the canonical filters key, sorted by filter
    // name with values in their submitted order, and the unmatched groups
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let filters_key = format!(
        "filters%5Bgroup_category_ids%5D%5B%5D={group_category_id}\
         &#38;filters%5Bgroup_ids%5D%5B%5D={}\
         &#38;filters%5Bgroup_ids%5D%5B%5D={unmatched_group_id}\
         &#38;filters%5Bregions%5D%5B%5D=none\
         &#38;filters%5Bregions%5D%5B%5D={region_id}\
         &#38;filters%5Broles%5D%5B%5D=events-manager",
        ids.group_id
    );
    assert!(html.contains(r#"data-people-count="3""#));
    assert!(html.contains(&format!(r#"data-filters-key="{filters_key}""#)));
    assert!(html.contains("Group One"));
    assert!(html.contains("Show groups"));
    assert!(html.contains("Group Two · Platform"));
}

#[tokio::test]
async fn test_recipients_rejects_get_requests() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::Read);
    db.expect_get_community_contact_recipients_summary().never();

    // Setup router and send a query string request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        "/dashboard/community/contact/recipients?filters%5Broles%5D%5B%5D=admin",
        ids.session_id,
    );
    let (parts, _) = send(router, request).await;

    // Check the preview only accepts posted filters
    assert_eq!(parts.status, StatusCode::METHOD_NOT_ALLOWED);
}

#[tokio::test]
async fn test_recipients_rejects_malformed_group_ids() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::Read);
    db.expect_get_community_contact_recipients_summary().never();

    // Setup router and send a group filter that is not a UUID
    let router = TestRouterBuilder::new(db).build().await;
    let request = recipients_request(&ids, "filters%5Bgroup_ids%5D%5B%5D=not-a-uuid");
    let (parts, bytes) = send(router, request).await;

    // Check the parser output stays out of the response
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), INVALID_REQUEST_PAYLOAD.as_bytes());
}

#[tokio::test]
async fn test_recipients_rejects_oversized_filters() {
    // Setup one valid value for each filter
    let filters = [
        ("group_category_ids", Uuid::new_v4().to_string()),
        ("group_ids", Uuid::new_v4().to_string()),
        ("regions", "none".to_string()),
        ("roles", "admin".to_string()),
    ];

    for (field, value) in filters {
        // Setup identifiers and database mock
        let ids = DashboardIds::new();
        let mut db = MockDB::new();
        expect_community_access(&mut db, &ids, CommunityPermission::Read);
        db.expect_get_community_contact_recipients_summary().never();

        // Setup router and send one value more than allowed for the filter
        let form_data =
            vec![format!("filters%5B{field}%5D%5B%5D={value}"); MAX_CONTACT_FILTER_VALUES + 1]
                .join("&");
        let router = TestRouterBuilder::new(db).build().await;
        let (parts, bytes) = send(router, recipients_request(&ids, &form_data)).await;
        let body = String::from_utf8(bytes.to_vec()).unwrap();

        // Check the report names the oversized filter
        assert_eq!(
            parts.status,
            StatusCode::UNPROCESSABLE_ENTITY,
            "field {field}"
        );
        assert!(
            body.contains(&format!("filters.{field}")),
            "field {field}: {body}"
        );
    }
}

#[tokio::test]
async fn test_send_community_custom_notification_blank_body() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::GroupsWrite);
    db.expect_enqueue_tracked_community_custom_notification().never();

    // Setup router and send a contact form whose body is only whitespace
    let router = TestRouterBuilder::new(db).build().await;
    let request = notification_request(&ids, "subject=Hello&body=+++");
    let (parts, bytes) = send(router, request).await;

    // Check the form is rejected
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        bytes.as_ref(),
        b"content.body: value cannot be empty or whitespace-only\n"
    );
}

#[tokio::test]
async fn test_send_community_custom_notification_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let group_category_id = Uuid::new_v4();
    let form_data = format!(
        "subject=Team+update&body=Hello+teams\
         &filters%5Bgroup_category_ids%5D%5B%5D={group_category_id}\
         &filters%5Bregions%5D%5B%5D=none\
         &filters%5Broles%5D%5B%5D=admin\
         &filters%5Bgroup_ids%5D%5B%5D={}",
        ids.group_id
    );

    // Setup database mock
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::GroupsWrite);
    expect_send_context(&mut db, &ids);
    db.expect_enqueue_tracked_community_custom_notification()
        .times(1)
        .withf(move |input| {
            input.body == "Hello teams"
                && input.community_id == ids.community_id
                && input.created_by == ids.user_id
                && input.filters.group_category_ids == vec![group_category_id]
                && input.filters.group_ids == vec![ids.group_id]
                && input.filters.regions == vec![RegionFilterValue::NoRegion]
                && input.filters.roles == vec![GroupRole::Admin]
                && input.subject == "Team update"
        })
        .returning(|_| Ok(2));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, notification_request(&ids, &form_data)).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_send_community_custom_notification_too_long_body() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::GroupsWrite);
    db.expect_enqueue_tracked_community_custom_notification().never();

    // Setup router and send a contact form whose body exceeds the maximum length
    let body = "a".repeat(MAX_LEN_NOTIFICATION_BODY + 1);
    let router = TestRouterBuilder::new(db).build().await;
    let request = notification_request(&ids, &format!("subject=Hello&body={body}"));
    let (parts, bytes) = send(router, request).await;

    // Check the form is rejected
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        format!("content.body: length is greater than {MAX_LEN_NOTIFICATION_BODY}\n")
    );
}

// Helpers.

/// Configures the reads used to prepare the contact page, other than the
/// send permission.
fn expect_contact_page_reads(db: &mut MockDB, ids: &DashboardIds) {
    let ids = *ids;
    db.expect_get_community_summary()
        .times(1)
        .withf(move |community_id| *community_id == ids.community_id)
        .returning(move |_| Ok(sample_community_summary(ids.community_id)));
    db.expect_list_community_contact_filter_options()
        .times(1)
        .withf(move |community_id| *community_id == ids.community_id)
        .returning(|_| Ok(sample_filter_options()));
    db.expect_list_group_roles()
        .times(1)
        .returning(|| Ok(vec![sample_group_role_summary()]));
    db.expect_get_community_contact_recipients_summary()
        .times(1)
        .withf(move |community_id, filters| {
            *community_id == ids.community_id
                && filters.group_category_ids.is_empty()
                && filters.group_ids.is_empty()
                && filters.regions.is_empty()
                && filters.roles.is_empty()
        })
        .returning(|_, _| Ok(sample_summary()));
}

/// Configures the context reads used to build the community email.
fn expect_send_context(db: &mut MockDB, ids: &DashboardIds) {
    let ids = *ids;
    db.expect_get_community_summary()
        .times(1)
        .withf(move |community_id| *community_id == ids.community_id)
        .returning(move |_| Ok(sample_community_summary(ids.community_id)));
    expect_site_settings(db);
}

/// Builds a send request for the community contact form.
fn notification_request(ids: &DashboardIds, form_data: &str) -> Request<Body> {
    form_request(
        "POST",
        "/dashboard/community/notifications",
        ids.session_id,
        form_data.to_string(),
    )
}

/// Builds a recipients summary request for the contact filters.
fn recipients_request(ids: &DashboardIds, form_data: &str) -> Request<Body> {
    form_request(
        "POST",
        "/dashboard/community/contact/recipients",
        ids.session_id,
        form_data.to_string(),
    )
}

/// Returns contact filter options with one category, group and region, in a
/// community with subgroups.
fn sample_filter_options() -> CommunityContactFilterOptions {
    CommunityContactFilterOptions {
        group_categories: vec![CommunityContactGroupCategoryOption {
            group_category_id: Uuid::new_v4(),
            groups_count: 2,
            name: "Platform".to_string(),
        }],
        groups: vec![CommunityContactGroupLabel {
            group_id: Uuid::new_v4(),
            label: "Group One · Platform · Europe".to_string(),
        }],
        has_subgroups: true,
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
        unmatched_groups: vec![],
    }
}
