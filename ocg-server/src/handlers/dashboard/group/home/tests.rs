use axum::http::StatusCode;
use uuid::Uuid;

use crate::{
    db::mock::{MockDB, expect_site_settings},
    handlers::tests::*,
    types::{
        dashboard::{
            DASHBOARD_PAGINATION_LIMIT,
            common::AuditLogSort,
            group::{
                cohosts::CohostedEventsOutput,
                members::GroupMembersOutput,
                refunds::{RefundsOutput, RefundsView},
                sponsors::GroupSponsorsOutput,
                team::GroupTeamOutput,
            },
        },
        inbox::InboxConversationsOutput,
        payments::GroupExternalPaymentsContext,
        permissions::GroupPermission,
        utm::GroupUtmSettings,
    },
};

#[tokio::test]
async fn test_page_analytics_tab_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let stats = sample_group_stats();

    // Setup database mock
    let mut db = MockDB::new();
    expect_home_context(&mut db, &ids);
    expect_group_permission_result(&mut db, &ids, GroupPermission::BadgesWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::CheckInsWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::InboxWrite, false);
    db.expect_get_group_stats()
        .times(1)
        .withf(move |community_id, group_id, include_subgroups| {
            *community_id == ids.community_id && *group_id == ids.group_id && !*include_subgroups
        })
        .returning(move |_, _, _| Ok(stats.clone()));
    db.expect_group_has_active_subgroups()
        .times(1)
        .withf(move |community_id, group_id| {
            *community_id == ids.community_id && *group_id == ids.group_id
        })
        .returning(|_, _| Ok(false));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group?tab=analytics", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(!body.contains("tab=artwork"));
    assert!(!body.contains("tab=awards"));
    assert!(!body.contains("tab=badges"));
    assert!(!body.contains("id-prefix=\"mobile-community\""));
    assert!(!body.contains("id-prefix=\"mobile-group\""));
    assert!(body.contains("tab=refunds"));
    assert!(body.contains("hx-get=\"/dashboard/group/analytics\""));
}

#[tokio::test]
async fn test_page_badge_tabs_require_management_permission() {
    // Setup identifiers
    let ids = DashboardIds::new();

    for tab in ["artwork", "awards", "badges"] {
        // Setup database mock without badge-management access
        let mut db = MockDB::new();
        expect_home_context(&mut db, &ids);
        expect_group_permission_result(&mut db, &ids, GroupPermission::BadgesWrite, false);
        expect_group_permission_result(&mut db, &ids, GroupPermission::CheckInsWrite, false);
        expect_group_permission_result(&mut db, &ids, GroupPermission::InboxWrite, false);

        // Setup router and send request
        let router = TestRouterBuilder::new(db).build().await;
        let request = get_request(&format!("/dashboard/group?tab={tab}"), ids.session_id);
        let (parts, bytes) = send(router, request).await;

        // Check the hidden badge tab is rejected before loading its page data
        assert_eq!(parts.status, StatusCode::FORBIDDEN, "tab: {tab}");
        assert!(bytes.is_empty(), "tab: {tab}");
    }
}

#[tokio::test]
async fn test_page_check_in_tab_falls_back_without_management_permission() {
    // Setup database mock without check-in management access
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_home_context(&mut db, &ids);
    expect_group_permission_result(&mut db, &ids, GroupPermission::BadgesWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::CheckInsWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::InboxWrite, false);
    expect_settings_content(&mut db, &ids, false);
    db.expect_list_group_check_in_events().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group?tab=check-in", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the response explains the fallback and exposes recovery selectors
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("You cannot manage check-ins for the selected group."));
    assert!(body.contains(&format!("selected-community-id=\"{}\"", ids.community_id)));
    assert!(body.contains(&format!("selected-group-id=\"{}\"", ids.group_id)));
}

#[tokio::test]
async fn test_page_check_in_tab_success() {
    // Setup database mock with check-in management access
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_home_context(&mut db, &ids);
    expect_group_permission_result(&mut db, &ids, GroupPermission::BadgesWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::CheckInsWrite, true);
    expect_group_permission_result(&mut db, &ids, GroupPermission::InboxWrite, false);
    db.expect_list_group_check_in_events()
        .times(1)
        .withf(move |group_id| *group_id == ids.group_id)
        .returning(|_| Ok(vec![]));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group?tab=check-in", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the check-in content is rendered without the fallback warning
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("data-group-check-in-root"));
    assert!(!body.contains("You cannot manage check-ins for the selected group."));
}

#[tokio::test]
async fn test_page_cohosts_tab_success() {
    // Setup database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_home_context(&mut db, &ids);
    expect_group_permission_result(&mut db, &ids, GroupPermission::BadgesWrite, true);
    expect_group_permission_result(&mut db, &ids, GroupPermission::CheckInsWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::InboxWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::SettingsWrite, true);
    db.expect_list_group_cohosted_events()
        .times(1)
        .withf(move |group_id, filters| {
            *group_id == ids.group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(|_, _| Ok(CohostedEventsOutput::default()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group?tab=cohosts", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the co-hosts section is rendered
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("data-group-cohosts-list"));
}

#[tokio::test]
async fn test_page_events_tab_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let group_events = sample_group_events(Uuid::new_v4());

    // Setup database mock
    let mut db = MockDB::new();
    expect_home_context(&mut db, &ids);
    expect_group_permission_result(&mut db, &ids, GroupPermission::BadgesWrite, true);
    expect_group_permission_result(&mut db, &ids, GroupPermission::CheckInsWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::InboxWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);
    db.expect_list_group_events()
        .times(1)
        .withf(move |group_id, filters| {
            *group_id == ids.group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.past_offset == Some(0)
                && filters.upcoming_offset == Some(0)
        })
        .returning(move |_, _| Ok(group_events.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group?tab=events", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the response and badge section navigation
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    let events_menu = body.find("tab=events").unwrap();
    let badges_menu = body.find("tab=badges").unwrap();
    let artwork_menu = body.find("tab=artwork").unwrap();
    let awards_menu = body.find("tab=awards").unwrap();
    let members_menu = body.find("tab=members").unwrap();
    assert!(events_menu < badges_menu);
    assert!(badges_menu < artwork_menu);
    assert!(artwork_menu < awards_menu);
    assert!(awards_menu < members_menu);
}

#[tokio::test]
async fn test_page_inbox_tab_falls_back_without_inbox_permission() {
    // Setup database mock without inbox access
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_home_context(&mut db, &ids);
    expect_group_permission_result(&mut db, &ids, GroupPermission::BadgesWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::CheckInsWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::InboxWrite, false);
    db.expect_count_group_open_inbox_conversations().never();
    db.expect_list_group_inbox_conversations().never();
    expect_settings_content(&mut db, &ids, false);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group?tab=inbox", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the recoverable warning, selectors and hidden menu item
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("You don&#39;t have Inbox access for the selected group."));
    assert!(body.contains(&format!("selected-group-id=\"{}\"", ids.group_id)));
    assert!(!body.contains("href=\"/dashboard/group?tab=inbox\""));
    assert!(body.contains("This dashboard is not optimized yet for mobile devices"));
}

#[tokio::test]
async fn test_page_inbox_tab_opens_conversation_of_selected_group() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let inbox_conversation_id = Uuid::new_v4();
    let conversation = sample_inbox_conversation(inbox_conversation_id);

    // Setup database mock with inbox access and a conversation of the group
    let mut db = MockDB::new();
    expect_home_context(&mut db, &ids);
    expect_group_permission_result(&mut db, &ids, GroupPermission::BadgesWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::CheckInsWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::InboxWrite, true);
    db.expect_count_group_open_inbox_conversations()
        .times(1)
        .withf(move |group_id| *group_id == ids.group_id)
        .returning(|_| Ok(0));
    db.expect_get_group_inbox_conversation()
        .times(1)
        .withf(move |group_id, conversation_id| {
            *group_id == ids.group_id && *conversation_id == inbox_conversation_id
        })
        .returning(move |_, _| Ok(Some(conversation.clone())));
    db.expect_list_group_inbox_conversations().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group?tab=inbox&conversation_id={inbox_conversation_id}"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the thread renders inside the dashboard
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("id=\"inbox-conversation\""));
    assert!(body.contains("hx-get=\"/dashboard/group/inbox\""));
}

#[tokio::test]
async fn test_page_inbox_tab_renders_list_with_open_count_badge() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let summary = sample_inbox_conversation_summary(Uuid::new_v4());

    // Setup database mock with inbox access, badge count and list
    let mut db = MockDB::new();
    expect_home_context(&mut db, &ids);
    expect_group_permission_result(&mut db, &ids, GroupPermission::BadgesWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::CheckInsWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::InboxWrite, true);
    db.expect_count_group_open_inbox_conversations()
        .times(1)
        .withf(move |group_id| *group_id == ids.group_id)
        .returning(|_| Ok(7));
    db.expect_list_group_inbox_conversations()
        .times(1)
        .withf(move |group_id, filters| *group_id == ids.group_id && filters.status.is_none())
        .returning(move |_, _| {
            Ok(InboxConversationsOutput {
                conversations: vec![summary.clone()],
                total: 1,
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group?tab=inbox", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the menu badge, list and mobile notice
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    let inbox_menu_item = body
        .split("href=\"/dashboard/group?tab=inbox\"")
        .nth(1)
        .and_then(|rest| rest.split("</a>").next())
        .expect("inbox menu item to render");
    assert!(inbox_menu_item.contains("Inbox"));
    assert!(inbox_menu_item.split_whitespace().any(|token| token == "7"));
    assert!(body.contains("When do doors open?"));
    assert!(body.contains("This dashboard is not optimized yet for mobile devices"));
}

#[tokio::test]
async fn test_page_inbox_tab_warns_about_conversation_of_another_group() {
    // Setup identifiers
    let ids = DashboardIds::new();
    let inbox_conversation_id = Uuid::new_v4();

    // Setup database mock with inbox access and a foreign conversation
    let mut db = MockDB::new();
    expect_home_context(&mut db, &ids);
    expect_group_permission_result(&mut db, &ids, GroupPermission::BadgesWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::CheckInsWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::InboxWrite, true);
    db.expect_count_group_open_inbox_conversations()
        .times(1)
        .returning(|_| Ok(0));
    db.expect_get_group_inbox_conversation()
        .times(1)
        .withf(move |group_id, conversation_id| {
            *group_id == ids.group_id && *conversation_id == inbox_conversation_id
        })
        .returning(|_, _| Ok(None));
    db.expect_list_group_inbox_conversations()
        .times(1)
        .returning(|_, _| Ok(InboxConversationsOutput::default()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group?tab=inbox&conversation_id={inbox_conversation_id}"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the list renders with the warning
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("This conversation isn&#39;t in the selected group."));
    assert!(body.contains("No conversations yet"));
}

#[tokio::test]
async fn test_page_logs_tab_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let output = sample_audit_logs_output();

    // Setup database mock
    let mut db = MockDB::new();
    expect_home_context(&mut db, &ids);
    expect_group_permission_result(&mut db, &ids, GroupPermission::BadgesWrite, true);
    expect_group_permission_result(&mut db, &ids, GroupPermission::CheckInsWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::InboxWrite, false);
    db.expect_list_group_audit_logs()
        .times(1)
        .withf(move |group_id, filters| {
            *group_id == ids.group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && filters.sort == Some(AuditLogSort::CreatedDesc)
        })
        .returning(move |_, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group?tab=logs", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the logs section is rendered
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("id=\"open-audit-log-filters-modal\""));
}

#[tokio::test]
async fn test_page_members_tab_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let group = sample_group_summary(ids.group_id);
    let output = GroupMembersOutput {
        members: vec![sample_group_member()],
        total: 1,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_home_context(&mut db, &ids);
    expect_group_permission_result(&mut db, &ids, GroupPermission::BadgesWrite, true);
    expect_group_permission_result(&mut db, &ids, GroupPermission::CheckInsWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::InboxWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::MembersWrite, true);
    db.expect_list_group_members()
        .times(1)
        .withf(move |group_id, filters| {
            *group_id == ids.group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(output.clone()));
    db.expect_get_group_summary()
        .times(1)
        .withf(move |community_id, group_id| {
            *community_id == ids.community_id && *group_id == ids.group_id
        })
        .returning(move |_, _| Ok(group.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group?tab=members", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("name=\"subject\""));
    assert!(body.contains("value=\"Test Group\""));
    assert!(body.contains("hx-get=\"/dashboard/group/members\""));
}

#[tokio::test]
async fn test_page_refunds_tab_preserves_history_without_payments_setup() {
    // Setup identifiers and empty refund dashboard state
    let ids = DashboardIds::new();
    let output = sample_refunds_output();

    // Setup database mock after the group's payment setup was removed
    let mut db = MockDB::new();
    expect_home_context(&mut db, &ids);
    expect_group_permission_result(&mut db, &ids, GroupPermission::BadgesWrite, true);
    expect_group_permission_result(&mut db, &ids, GroupPermission::CheckInsWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::InboxWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, false);
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |community_id, group_id| {
            *community_id == ids.community_id && *group_id == ids.group_id
        })
        .returning(|_, _| Ok(None));
    db.expect_list_group_refunds()
        .times(1)
        .withf(move |group_id, filters| {
            *group_id == ids.group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && filters.view == RefundsView::Active
        })
        .returning(move |_, _| Ok(output.clone()));

    // Setup router without a configured payments provider and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group?tab=refunds", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check history remains visible and current-provider actions are explained
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("Automatic payment processing is unavailable"));
    assert!(body.contains("external refunds can still be recorded"));
    assert!(body.contains("id=\"refunds-refresh\""));
}

#[tokio::test]
async fn test_page_refunds_tab_success() {
    // Setup identifiers and empty refund dashboard state
    let ids = DashboardIds::new();
    let output = sample_refunds_output();

    // Setup database mock
    let mut db = MockDB::new();
    expect_home_context(&mut db, &ids);
    expect_group_permission_result(&mut db, &ids, GroupPermission::BadgesWrite, true);
    expect_group_permission_result(&mut db, &ids, GroupPermission::CheckInsWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::InboxWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |community_id, group_id| {
            *community_id == ids.community_id && *group_id == ids.group_id
        })
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));
    db.expect_list_group_refunds()
        .times(1)
        .withf(move |group_id, filters| {
            *group_id == ids.group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && filters.view == RefundsView::Active
        })
        .returning(move |_, _| Ok(output.clone()));

    // Setup router with payments configured and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let request = get_request("/dashboard/group?tab=refunds", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the refund operations tab renders with payments ready
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("id=\"refunds-refresh\""));
    assert!(!body.contains("Automatic payment processing is unavailable"));
}

#[tokio::test]
async fn test_page_settings_tab_success() {
    // Setup database mock with settings management access
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_home_context(&mut db, &ids);
    expect_group_permission_result(&mut db, &ids, GroupPermission::BadgesWrite, true);
    expect_group_permission_result(&mut db, &ids, GroupPermission::CheckInsWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::InboxWrite, false);
    expect_settings_content(&mut db, &ids, true);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group?tab=settings", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the editable settings form is rendered
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("id=\"groups-form\""));
    assert!(!body.contains("Your role cannot update group settings."));
}

#[tokio::test]
async fn test_page_sponsors_tab_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let output = GroupSponsorsOutput {
        sponsors: vec![sample_group_sponsor()],
        total: 1,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_home_context(&mut db, &ids);
    expect_group_permission_result(&mut db, &ids, GroupPermission::BadgesWrite, true);
    expect_group_permission_result(&mut db, &ids, GroupPermission::CheckInsWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::InboxWrite, false);
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
    let request = get_request("/dashboard/group?tab=sponsors", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the sponsors section is rendered
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("id=\"add-sponsor-button\""));
}

#[tokio::test]
async fn test_page_team_tab_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let role = sample_group_role_summary();
    let members = vec![sample_team_member(true), sample_team_member(false)];
    let output = GroupTeamOutput {
        total: members.len(),
        members,
        total_accepted: 1,
        total_admins_accepted: 1,
    };

    // Setup database mock, including the team list's own badge permission read
    let mut db = MockDB::new();
    expect_home_context(&mut db, &ids);
    expect_group_permission_result(&mut db, &ids, GroupPermission::BadgesWrite, true);
    expect_group_permission_result(&mut db, &ids, GroupPermission::CheckInsWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::InboxWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::BadgesWrite, true);
    expect_group_permission_result(&mut db, &ids, GroupPermission::TeamWrite, true);
    db.expect_list_group_team_members()
        .times(1)
        .withf(move |group_id, filters| {
            *group_id == ids.group_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(output.clone()));
    db.expect_list_group_roles()
        .times(1)
        .returning(move || Ok(vec![role.clone()]));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group?tab=team", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the team section is rendered
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("id=\"team-list\""));
}

#[tokio::test]
async fn test_page_warns_when_selected_group_is_inactive() {
    // Setup identifiers and an inactive selected group
    let ids = DashboardIds::new();
    let mut groups = sample_user_groups_by_community(ids.community_id, ids.group_id);
    groups[0].groups[0].active = false;

    // Setup database mock with the inactive group in the selector
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    db.expect_list_user_groups()
        .times(1)
        .withf(move |user_id| *user_id == ids.user_id)
        .returning(move |_| Ok(groups.clone()));
    expect_site_settings(&mut db);
    expect_group_permission_result(&mut db, &ids, GroupPermission::BadgesWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::CheckInsWrite, false);
    expect_group_permission_result(&mut db, &ids, GroupPermission::InboxWrite, false);
    expect_settings_content(&mut db, &ids, false);

    // Setup router and send request without selecting a tab
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the inactive group warning is rendered
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("This group has been deactivated. Please contact a community admin."));
}

#[tokio::test]
async fn test_page_without_known_tab_defaults_to_settings() {
    // Setup requests without a known tab
    let cases = [
        ("missing tab", "/dashboard/group"),
        ("unknown tab", "/dashboard/group?tab=bogus"),
    ];

    for (case, uri) in cases {
        // Setup database mock without badge, check-in or settings management
        let ids = DashboardIds::new();
        let mut db = MockDB::new();
        expect_home_context(&mut db, &ids);
        expect_group_permission_result(&mut db, &ids, GroupPermission::BadgesWrite, false);
        expect_group_permission_result(&mut db, &ids, GroupPermission::CheckInsWrite, false);
        expect_group_permission_result(&mut db, &ids, GroupPermission::InboxWrite, false);
        expect_settings_content(&mut db, &ids, false);
        db.expect_get_group_stats().never();
        db.expect_group_has_active_subgroups().never();

        // Setup router and send request
        let router = TestRouterBuilder::new(db).build().await;
        let request = get_request(uri, ids.session_id);
        let (parts, bytes) = send(router, request).await;

        // Check the read-only settings tab is rendered instead of analytics
        assert_eq!(parts.status, StatusCode::OK, "{case}");
        let body = std::str::from_utf8(&bytes).unwrap();
        assert!(
            body.contains("hx-get=\"/dashboard/group/settings/update\""),
            "{case}"
        );
        assert!(
            body.contains("Your role cannot update group settings."),
            "{case}"
        );
        assert!(
            !body.contains("hx-get=\"/dashboard/group/analytics\""),
            "{case}"
        );
        assert!(!body.contains("This group has been deactivated."), "{case}");
    }
}

// Helpers.

/// Expects the session, Read access, group selector and site settings reads
/// every dashboard home request performs.
fn expect_home_context(db: &mut MockDB, ids: &DashboardIds) {
    let groups = sample_user_groups_by_community(ids.community_id, ids.group_id);
    let ids = *ids;

    expect_group_access(db, &ids, GroupPermission::Read);
    db.expect_list_user_groups()
        .times(1)
        .withf(move |user_id| *user_id == ids.user_id)
        .returning(move |_| Ok(groups.clone()));
    expect_site_settings(db);
}

/// Expects the reads used to prepare the settings tab content.
fn expect_settings_content(db: &mut MockDB, ids: &DashboardIds, can_manage_settings: bool) {
    let category = sample_group_category();
    let group_full = sample_group_full(ids.community_id, ids.group_id);
    let ids = *ids;
    let region = sample_group_region();

    expect_group_permission_result(
        db,
        &ids,
        GroupPermission::SettingsWrite,
        can_manage_settings,
    );
    db.expect_get_group_full()
        .times(1)
        .withf(move |community_id, group_id| {
            *community_id == ids.community_id && *group_id == ids.group_id
        })
        .returning(move |_, _| Ok(group_full.clone()));
    db.expect_group_has_child_links()
        .times(1)
        .withf(move |community_id, group_id| {
            *community_id == ids.community_id && *group_id == ids.group_id
        })
        .returning(|_, _| Ok(false));
    db.expect_list_group_categories()
        .times(1)
        .withf(move |community_id| *community_id == ids.community_id)
        .returning(move |_| Ok(vec![category.clone()]));
    db.expect_list_group_parent_options()
        .times(1)
        .withf(move |community_id, user_id, group_id| {
            *community_id == ids.community_id
                && *user_id == ids.user_id
                && *group_id == Some(ids.group_id)
        })
        .returning(|_, _, _| Ok(vec![]));
    db.expect_list_regions()
        .times(1)
        .withf(move |community_id| *community_id == ids.community_id)
        .returning(move |_| Ok(vec![region.clone()]));
    db.expect_get_group_external_payments_context()
        .times(1)
        .withf(move |community_id, group_id| {
            *community_id == ids.community_id && *group_id == ids.group_id
        })
        .returning(|_, _| {
            Ok(GroupExternalPaymentsContext {
                configured: false,
                eligible: false,
                enabled: false,
                country_code: None,
                default_payment_window_hours: None,
                max_payment_window_hours: None,
                seller_display_name: None,
            })
        });
    db.expect_get_group_utm_settings()
        .times(1)
        .withf(move |community_id, group_id| {
            *community_id == ids.community_id && *group_id == ids.group_id
        })
        .returning(|_, _| Ok(GroupUtmSettings::default()));
    db.expect_list_utm_mediums()
        .times(1)
        .returning(|| Ok(vec!["email".to_string()]));
}

/// Sample empty refunds list output.
fn sample_refunds_output() -> RefundsOutput {
    RefundsOutput {
        events: vec![],
        financial_recoveries: vec![],
        refunds: vec![],
        total: 0,
    }
}
