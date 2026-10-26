use axum::http::StatusCode;
use uuid::Uuid;

use crate::{
    db::mock::{MockDB, expect_site_settings},
    handlers::tests::*,
    types::{
        dashboard::{
            DASHBOARD_PAGINATION_LIMIT,
            common::AuditLogSort,
            user::{
                events::UserEventsOutput, groups::UserGroupsOutput,
                notifications::NotificationPreferences, purchases::PurchaseDocumentsOutput,
                session_proposals::SessionProposalsOutput, surveys::UserEventSurveysOutput,
            },
        },
        inbox::InboxConversationsOutput,
    },
};

#[tokio::test]
async fn test_page_account_tab_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();

    // Setup database mock
    let mut db = home_db(&ids, 0);
    db.expect_list_timezones()
        .times(1)
        .returning(|| Ok(vec!["UTC".to_string(), "America/New_York".to_string()]));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the account form renders with the timezones and the password form,
    // and links to the notifications tab instead of carrying the toggles
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("id=\"user-details-form\""));
    assert!(body.contains("America/New_York"));
    assert!(body.contains("id=\"password-form\""));
    assert!(body.contains("href=\"/dashboard/user?tab=notifications\""));
    assert!(!body.contains("optional_notifications_enabled"));
}

#[tokio::test]
async fn test_page_badges_tab_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = home_db(&ids, 0);
    db.expect_list_user_badges()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(|_| Ok(vec![]));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user?tab=badges", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the full dashboard renders the badges list
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("Your profile modal displays the first"));
}

#[tokio::test]
async fn test_page_check_in_tab_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = home_db(&ids, 0);
    db.expect_list_user_check_in_events()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(|_| Ok(vec![]));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user?tab=check-in", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the full dashboard renders the check-in list
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains(r#"data-username="test-user""#));
}

#[tokio::test]
async fn test_page_events_tab_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let events_output = UserEventsOutput {
        events: vec![],
        total: 0,
    };

    // Setup database mock
    let mut db = home_db(&ids, 0);
    db.expect_list_user_events()
        .times(1)
        .withf(move |uid, filters| {
            *uid == ids.user_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(events_output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user?tab=events", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_page_groups_tab_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let groups_output = UserGroupsOutput {
        groups: vec![],
        total: 0,
    };

    // Setup database mock
    let mut db = home_db(&ids, 0);
    db.expect_list_user_dashboard_groups()
        .times(1)
        .withf(move |uid, filters| {
            *uid == ids.user_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(groups_output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user?tab=groups", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_page_inbox_tab_opens_owned_conversation() {
    // Setup identifiers and a conversation of the user
    let inbox_conversation_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let conversation = sample_inbox_conversation(inbox_conversation_id);

    // Setup database mock
    let mut db = home_db(&ids, 0);
    db.expect_get_user_inbox_conversation()
        .times(1)
        .withf(move |uid, cid| *uid == ids.user_id && *cid == inbox_conversation_id)
        .returning(move |_, _| Ok(Some(conversation.clone())));
    db.expect_list_user_inbox_conversations().never();

    // Request the conversation through the full dashboard route
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/user?tab=inbox&conversation_id={inbox_conversation_id}"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the thread renders and stays desktop only
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("id=\"inbox-conversation\""));
    assert!(body.contains("hx-get=\"/dashboard/user/inbox\""));
    assert!(body.contains("This dashboard is not optimized yet for mobile devices"));
}

#[tokio::test]
async fn test_page_inbox_tab_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let summary = sample_inbox_conversation_summary(Uuid::new_v4());

    // Setup database mock
    let mut db = home_db(&ids, 0);
    db.expect_list_user_inbox_conversations()
        .times(1)
        .withf(move |uid, filters| {
            *uid == ids.user_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| {
            Ok(InboxConversationsOutput {
                conversations: vec![summary.clone()],
                total: 1,
            })
        });

    // Request the inbox through the full dashboard route
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user?tab=inbox", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the list, desktop menu item and mobile notice
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert_eq!(
        body.matches("href=\"/dashboard/user?tab=inbox\"").count(),
        1
    );
    assert!(body.contains("When do doors open?"));
    assert!(body.contains("<main id=\"dashboard-main-content\""));
    assert!(body.contains("This dashboard is not optimized yet for mobile devices"));
}

#[tokio::test]
async fn test_page_inbox_tab_warns_about_conversation_of_another_user() {
    // Setup identifiers and a conversation the user does not own
    let inbox_conversation_id = Uuid::new_v4();
    let ids = DashboardIds::new();

    // Setup database mock
    let mut db = home_db(&ids, 0);
    db.expect_get_user_inbox_conversation()
        .times(1)
        .returning(|_, _| Ok(None));
    db.expect_list_user_inbox_conversations()
        .times(1)
        .returning(|_, _| Ok(InboxConversationsOutput::default()));

    // Request the conversation through the full dashboard route
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/user?tab=inbox&conversation_id={inbox_conversation_id}"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the list renders with the warning
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("This conversation isn&#39;t in your Inbox."));
    assert!(body.contains("No conversations yet"));
}

#[tokio::test]
async fn test_page_invitations_tab_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let group_id = Uuid::new_v4();
    let community_invitations = vec![sample_community_invitation(community_id)];
    let event_invitations = vec![sample_event_invitation(Uuid::new_v4())];
    let group_invitations = vec![sample_group_invitation(group_id)];

    // Setup database mock
    let mut db = home_db(&ids, 0);
    db.expect_list_user_community_team_invitations()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(move |_| Ok(community_invitations.clone()));
    db.expect_list_user_event_invitations()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(move |_| Ok(event_invitations.clone()));
    db.expect_list_user_group_team_invitations()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(move |_| Ok(group_invitations.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user?tab=invitations", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_page_logs_tab_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let output = sample_audit_logs_output();

    // Setup database mock
    let mut db = home_db(&ids, 0);
    db.expect_list_user_audit_logs()
        .times(1)
        .withf(move |uid, filters| {
            *uid == ids.user_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && filters.sort == Some(AuditLogSort::CreatedDesc)
        })
        .returning(move |_, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user?tab=logs", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_page_notifications_tab_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();

    // Setup database mock
    let mut db = home_db(&ids, 0);
    db.expect_get_user_notification_preferences()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(|_| Ok(NotificationPreferences::default()));

    // Request the notifications tab through the full dashboard route
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user?tab=notifications", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the notifications content and refresh route render
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("id=\"notification-preferences-form\""));
    assert!(body.contains("hx-get=\"/dashboard/user/notifications\""));
    assert!(body.contains("/static/js/dashboard/user/notification-group-mutes."));
    assert!(body.contains("/static/js/dashboard/user/notification-preferences."));
}

#[tokio::test]
async fn test_page_purchases_tab_success() {
    // Setup identifiers and purchase-document output
    let ids = DashboardIds::new();
    let purchases_output = PurchaseDocumentsOutput {
        purchases: Vec::new(),
        total: 0,
    };

    // Setup database expectations
    let mut db = home_db(&ids, 0);
    db.expect_list_user_purchase_documents()
        .times(1)
        .withf(move |uid, filters| {
            *uid == ids.user_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(purchases_output.clone()));

    // Request the purchases tab in the full dashboard
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user?tab=purchases", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the full dashboard renders purchase history
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains("No paid-ticket documents yet"));
}

#[tokio::test]
async fn test_page_session_proposals_tab_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let session_proposals_output = SessionProposalsOutput {
        session_proposals: vec![],
        total: 0,
    };

    // Setup database mock
    let mut db = home_db(&ids, 0);
    db.expect_list_user_pending_session_proposal_co_speaker_invitations()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(move |_| Ok(vec![sample_pending_co_speaker_invitation(Uuid::new_v4())]));
    db.expect_list_session_proposal_levels()
        .times(1)
        .returning(move || Ok(sample_session_proposal_levels()));
    db.expect_list_user_session_proposals()
        .times(1)
        .withf(move |uid, filters| {
            *uid == ids.user_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(session_proposals_output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user?tab=session-proposals", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_page_submissions_tab_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let submissions_output = crate::types::dashboard::user::submissions::CfsSubmissionsOutput {
        submissions: vec![],
        total: 0,
    };

    // Setup database mock
    let mut db = home_db(&ids, 0);
    db.expect_list_user_cfs_submissions()
        .times(1)
        .withf(move |uid, filters| {
            *uid == ids.user_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(submissions_output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user?tab=submissions", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_page_surveys_tab_ignores_malformed_survey_id() {
    // Setup identifiers
    let ids = DashboardIds::new();

    // Setup database mock
    let mut db = home_db(&ids, 0);
    expect_empty_surveys_tab(&mut db, &ids);
    db.expect_get_user_event_survey().never();

    // Send the request with a survey id that is not a UUID
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        "/dashboard/user?tab=surveys&event_survey_id=not-a-uuid",
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the list renders without opening a survey or warning about it
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains(r#"hx-get="/dashboard/user/surveys""#));
    assert!(!body.contains("data-open-on-load"));
    assert!(!body.contains("This survey is closed or isn&#39;t available to you."));
}

#[tokio::test]
async fn test_page_surveys_tab_opens_requested_survey() {
    // Setup identifiers and data structures
    let event_survey_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let survey = sample_user_event_survey(event_survey_id, Uuid::new_v4());

    // Setup database mock
    let mut db = home_db(&ids, 0);
    expect_empty_surveys_tab(&mut db, &ids);
    db.expect_get_user_event_survey()
        .times(1)
        .withf(move |sid, uid| *sid == event_survey_id && *uid == ids.user_id)
        .returning(move |_, _| Ok(Some(survey.clone())));

    // Send the request the survey opening email links to
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/user?tab=surveys&event_survey_id={event_survey_id}"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the survey modal opens on load without a warning
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("data-open-on-load"));
    assert!(body.contains(&format!(
        r#"hx-put="/dashboard/user/surveys/{event_survey_id}/response""#
    )));
    assert!(!body.contains("This survey is closed or isn&#39;t available to you."));
}

#[tokio::test]
async fn test_page_surveys_tab_renders_unanswered_surveys_badge() {
    // Setup identifiers
    let ids = DashboardIds::new();

    // Setup database mock
    let mut db = home_db(&ids, 3);
    expect_empty_surveys_tab(&mut db, &ids);
    db.expect_get_user_event_survey().never();

    // Send the request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user?tab=surveys", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the active Surveys menu item counts the surveys left to answer
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert_eq!(
        menu_item_count(body, "/dashboard/user?tab=surveys"),
        Some("3")
    );
    assert!(body.contains(r#"hx-get="/dashboard/user/surveys""#));
}

#[tokio::test]
async fn test_page_surveys_tab_warns_about_unavailable_survey() {
    // Setup identifiers
    let event_survey_id = Uuid::new_v4();
    let ids = DashboardIds::new();

    // Setup database mock
    let mut db = home_db(&ids, 0);
    expect_empty_surveys_tab(&mut db, &ids);
    db.expect_get_user_event_survey()
        .times(1)
        .withf(move |sid, uid| *sid == event_survey_id && *uid == ids.user_id)
        .returning(|_, _| Ok(None));

    // Send the request of a survey the user can't reach
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/user?tab=surveys&event_survey_id={event_survey_id}"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the list warns about the survey without opening it
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("This survey is closed or isn&#39;t available to you."));
    assert!(!body.contains("data-open-on-load"));
    assert_eq!(menu_item_count(body, "/dashboard/user?tab=surveys"), None);
}

// Helpers.

/// Expects the list read of a Surveys tab without surveys.
fn expect_empty_surveys_tab(db: &mut MockDB, ids: &DashboardIds) {
    let user_id = ids.user_id;
    db.expect_list_user_event_surveys()
        .times(1)
        .withf(move |uid, _| *uid == user_id)
        .returning(|_, _| {
            Ok(UserEventSurveysOutput {
                surveys: vec![],
                total: 0,
            })
        });
}

/// Builds a database mock with the reads every dashboard home page performs:
/// the session, the site settings and the count of surveys left to answer.
fn home_db(ids: &DashboardIds, unanswered_surveys_count: usize) -> MockDB {
    let mut db = MockDB::new();
    let user_id = ids.user_id;
    expect_session(&mut db, ids);
    expect_site_settings(&mut db);
    db.expect_count_user_unanswered_event_surveys()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(unanswered_surveys_count));

    db
}

/// Returns the count badge of the menu item linking to the given URL.
fn menu_item_count<'a>(body: &'a str, href: &str) -> Option<&'a str> {
    let start = body.find(&format!(r#"href="{href}""#))?;
    let item = &body[start..start + body[start..].find("</a>")?];
    let badge_start = item.find("rounded-full px-2 pt-px ms-3")?;
    let badge = &item[badge_start..];
    let text_start = badge.find('>')? + 1;
    let text_end = badge.find("</div>")?;

    Some(badge[text_start..text_end].trim())
}
