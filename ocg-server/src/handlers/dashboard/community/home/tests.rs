use axum::http::StatusCode;

use crate::{
    db::mock::{MockDB, expect_site_settings},
    handlers::tests::*,
    types::{
        community::CommunityFull,
        dashboard::{
            DASHBOARD_PAGINATION_LIMIT,
            common::AuditLogSort,
            community::{
                contact::{CommunityContactFilterOptions, CommunityContactRecipientsSummary},
                groups::CommunityGroupsOutput,
                team::CommunityTeamOutput,
            },
        },
        permissions::CommunityPermission,
    },
};

#[tokio::test]
async fn test_page_analytics_tab_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let stats = sample_community_stats();

    // Setup database mock
    let mut db = MockDB::new();
    expect_page_reads(&mut db, &ids, sample_community_full(ids.community_id));
    db.expect_get_community_stats()
        .times(1)
        .withf(move |community_id| *community_id == ids.community_id)
        .returning(move |_| Ok(stats.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/community?tab=analytics", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the analytics page is rendered in the dashboard
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(html.contains(r#"data-analytics-tab="groups""#));
}

#[tokio::test]
async fn test_page_contact_tab_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_page_reads(&mut db, &ids, sample_community_full(ids.community_id));
    expect_community_permission_result(&mut db, &ids, CommunityPermission::GroupsWrite, true);
    db.expect_list_community_contact_filter_options()
        .times(1)
        .withf(move |community_id| *community_id == ids.community_id)
        .returning(|_| Ok(CommunityContactFilterOptions::default()));
    db.expect_list_group_roles()
        .times(1)
        .returning(|| Ok(vec![sample_group_role_summary()]));
    db.expect_get_community_contact_recipients_summary()
        .times(1)
        .withf(move |community_id, _| *community_id == ids.community_id)
        .returning(|_, _| Ok(CommunityContactRecipientsSummary::default()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/community?tab=contact", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the contact page is rendered in the dashboard
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(html.contains(r#"id="community-contact-form""#));
    assert!(html.contains("No group team members match these filters."));
}

#[tokio::test]
async fn test_page_event_categories_tab_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let categories = vec![sample_event_category()];

    // Setup database mock
    let mut db = MockDB::new();
    expect_page_reads(&mut db, &ids, sample_community_full(ids.community_id));
    expect_community_permission_result(&mut db, &ids, CommunityPermission::TaxonomyWrite, true);
    db.expect_list_event_categories()
        .times(1)
        .withf(move |community_id| *community_id == ids.community_id)
        .returning(move |_| Ok(categories.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/community?tab=event-categories", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the event categories list is rendered in the dashboard
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(html.contains(r#"aria-label="Edit event category: Meetup""#));
}

#[tokio::test]
async fn test_page_group_categories_tab_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let categories = vec![sample_group_category()];

    // Setup database mock
    let mut db = MockDB::new();
    expect_page_reads(&mut db, &ids, sample_community_full(ids.community_id));
    expect_community_permission_result(&mut db, &ids, CommunityPermission::TaxonomyWrite, true);
    db.expect_list_group_categories()
        .times(1)
        .withf(move |community_id| *community_id == ids.community_id)
        .returning(move |_| Ok(categories.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/community?tab=group-categories", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the group categories list is rendered in the dashboard
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(html.contains(r#"aria-label="Edit group category: Meetup""#));
}

#[tokio::test]
async fn test_page_groups_tab_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let groups_output = CommunityGroupsOutput {
        groups: vec![sample_group_summary(ids.group_id)],
        total: 1,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_page_reads(&mut db, &ids, sample_community_full(ids.community_id));
    expect_community_permission_result(&mut db, &ids, CommunityPermission::GroupsWrite, true);
    db.expect_list_community_groups()
        .times(1)
        .withf(move |community_id, filters| {
            *community_id == ids.community_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && filters.ts_query.as_deref() == Some("rust")
        })
        .returning(move |_, _| Ok(groups_output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        "/dashboard/community?tab=groups&ts_query=rust",
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the groups list is rendered in the dashboard
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(html.contains("Open group dashboard: Test Group"));
}

#[tokio::test]
async fn test_page_logs_tab_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let output = sample_audit_logs_output();

    // Setup database mock
    let mut db = MockDB::new();
    expect_page_reads(&mut db, &ids, sample_community_full(ids.community_id));
    db.expect_list_community_audit_logs()
        .times(1)
        .withf(move |community_id, filters| {
            *community_id == ids.community_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && filters.sort == Some(AuditLogSort::CreatedDesc)
        })
        .returning(move |_, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/community?tab=logs", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the audit logs list is rendered in the dashboard
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(html.contains("Schedule updated"));
}

#[tokio::test]
async fn test_page_regions_tab_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let regions = vec![sample_group_region()];

    // Setup database mock
    let mut db = MockDB::new();
    expect_page_reads(&mut db, &ids, sample_community_full(ids.community_id));
    expect_community_permission_result(&mut db, &ids, CommunityPermission::TaxonomyWrite, true);
    db.expect_list_regions()
        .times(1)
        .withf(move |community_id| *community_id == ids.community_id)
        .returning(move |_| Ok(regions.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/community?tab=regions", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the regions list is rendered in the dashboard
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(html.contains(r#"aria-label="Edit region: North America""#));
}

#[tokio::test]
async fn test_page_settings_tab_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_page_reads(&mut db, &ids, sample_community_full(ids.community_id));
    expect_community_permission_result(&mut db, &ids, CommunityPermission::SettingsWrite, true);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/community?tab=settings", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the editable settings form is rendered
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains("hx-get=\"/dashboard/community/settings/update\""));
    assert!(!body.contains("Your role cannot update community settings."));
}

#[tokio::test]
async fn test_page_team_tab_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let members = vec![
        sample_community_team_member(true),
        sample_community_team_member(false),
    ];
    let output = CommunityTeamOutput {
        members: members.clone(),
        total: members.len(),
        total_accepted: 1,
        total_admins_accepted: 1,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_page_reads(&mut db, &ids, sample_community_full(ids.community_id));
    expect_community_permission_result(&mut db, &ids, CommunityPermission::TeamWrite, true);
    db.expect_list_community_team_members()
        .times(1)
        .withf(move |community_id, filters| {
            *community_id == ids.community_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(output.clone()));
    db.expect_list_community_roles()
        .times(1)
        .returning(|| Ok(vec![sample_community_role_summary()]));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/community?tab=team", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the team list is rendered in the dashboard
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(html.contains(r#"<team-add-member dashboard-type="community" can-manage-team="true""#));
}

#[tokio::test]
async fn test_page_warns_when_community_is_inactive() {
    // Setup identifiers and an inactive community
    let ids = DashboardIds::new();
    let community = CommunityFull {
        active: false,
        ..sample_community_full(ids.community_id)
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_page_reads(&mut db, &ids, community);
    expect_community_permission_result(&mut db, &ids, CommunityPermission::SettingsWrite, false);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/community", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the inactive community warning is rendered
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(
        body.contains(
            "This community has been deactivated. Please contact the site administrators."
        )
    );
}

#[tokio::test]
async fn test_page_without_known_tab_defaults_to_settings() {
    // Setup requests without a known tab
    let cases = [
        ("missing tab", "/dashboard/community"),
        ("unknown tab", "/dashboard/community?tab=bogus"),
    ];

    for (case, uri) in cases {
        // Setup identifiers and database mock
        let ids = DashboardIds::new();
        let mut db = MockDB::new();
        expect_page_reads(&mut db, &ids, sample_community_full(ids.community_id));
        expect_community_permission_result(
            &mut db,
            &ids,
            CommunityPermission::SettingsWrite,
            false,
        );
        db.expect_get_community_stats().never();

        // Setup router and send request
        let router = TestRouterBuilder::new(db).build().await;
        let request = get_request(uri, ids.session_id);
        let (parts, bytes) = send(router, request).await;

        // Check the read-only settings tab is rendered instead of analytics
        assert_eq!(parts.status, StatusCode::OK, "{case}");
        let body = std::str::from_utf8(&bytes).unwrap();
        assert!(
            body.contains("hx-get=\"/dashboard/community/settings/update\""),
            "{case}"
        );
        assert!(
            body.contains("Your role cannot update community settings."),
            "{case}"
        );
        assert!(
            !body.contains("hx-get=\"/dashboard/community/analytics\""),
            "{case}"
        );
        assert!(
            !body.contains("This community has been deactivated."),
            "{case}"
        );
    }
}

// Helpers.

/// Expects the session, permission and context reads every dashboard tab
/// performs, returning the given community.
fn expect_page_reads(db: &mut MockDB, ids: &DashboardIds, community: CommunityFull) {
    let ids = *ids;
    expect_community_access(db, &ids, CommunityPermission::Read);
    db.expect_get_community_full()
        .times(1)
        .withf(move |community_id| *community_id == ids.community_id)
        .returning(move |_| Ok(community.clone()));
    db.expect_list_user_communities()
        .times(1)
        .withf(move |user_id| *user_id == ids.user_id)
        .returning(move |_| Ok(sample_user_communities(ids.community_id)));
    expect_site_settings(db);
}
