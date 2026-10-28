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
                invitation_requests::{
                    InvitationRequest, InvitationRequestsOutput, InvitationRequestsSort,
                    InvitationRequestsStatusFilter,
                },
            },
        },
        event::EventSummary,
        payments::EventTicketType,
        permissions::GroupPermission,
        questionnaire::{
            QuestionnaireAnswer, QuestionnaireAnswerValue, QuestionnaireAnswers,
            QuestionnaireQuestion, QuestionnaireQuestionKind,
        },
    },
};

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let question_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);
    let mut invitation_request = sample_invitation_request();
    invitation_request.registration_answers = Some(QuestionnaireAnswers {
        answers: vec![QuestionnaireAnswer {
            question_id,
            value: QuestionnaireAnswerValue::One("Vegetarian".to_string()),
        }],
    });
    let registration_questions = vec![QuestionnaireQuestion {
        id: question_id,
        kind: QuestionnaireQuestionKind::FreeText,
        prompt: "Dietary restrictions?".to_string(),
        required: false,

        options: vec![],
    }];
    let output = InvitationRequestsOutput {
        invitation_requests: vec![invitation_request],
        total: 1,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_list_context(&mut db, &ids, event, registration_questions);
    db.expect_search_event_invitation_requests()
        .times(1)
        .withf(move |gid, eid, filters| {
            *gid == ids.group_id
                && *eid == event_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && filters.status == InvitationRequestsStatusFilter::Pending
        })
        .returning(move |_, _, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/invitation-requests"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("status=pending"));

    // Check the list includes review answers for the request
    assert!(body.contains("View answers"));
    assert!(body.contains("data-answers-open"));
    assert!(body.contains("id=\"invitation-request-answers-modal\""));
    assert!(body.contains("Dietary restrictions?"));
    assert!(body.contains("Vegetarian"));
}

#[tokio::test]
async fn test_list_page_disables_accept_for_sold_out_requested_ticket_type() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let available_ticket_type_id = Uuid::from_u128(1);
    let event_id = Uuid::new_v4();
    let sold_out_ticket_type_id = Uuid::from_u128(2);
    let event = EventSummary {
        attendee_approval_required: true,
        ticket_types: Some(vec![
            EventTicketType {
                active: true,
                event_ticket_type_id: available_ticket_type_id,
                title: "General admission".to_string(),
                ..Default::default()
            },
            EventTicketType {
                active: true,
                event_ticket_type_id: sold_out_ticket_type_id,
                title: "Early bird".to_string(),

                sold_out: true,
                ..Default::default()
            },
        ]),
        ..sample_event_summary(event_id)
    };
    let available_request = InvitationRequest {
        requested_event_ticket_type_id: Some(available_ticket_type_id),
        ..sample_invitation_request()
    };
    let sold_out_request = InvitationRequest {
        requested_event_ticket_type_id: Some(sold_out_ticket_type_id),
        ..sample_invitation_request()
    };
    let available_user_id = available_request.user.user_id;
    let sold_out_user_id = sold_out_request.user.user_id;
    let output = InvitationRequestsOutput {
        invitation_requests: vec![available_request, sold_out_request],
        total: 2,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_list_context(&mut db, &ids, event, vec![]);
    db.expect_search_event_invitation_requests()
        .times(1)
        .withf(move |gid, eid, _| *gid == ids.group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/invitation-requests"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();

    // Check only the sold-out request disables acceptance with guidance
    assert_eq!(
        body.matches("disabled title=\"This ticket type is sold out.\"")
            .count(),
        1
    );
    assert!(body.contains(&format!(
        "id=\"invitation-request-ticket-sold-out-{sold_out_user_id}\""
    )));
    assert!(body.contains(&format!(
        "aria-describedby=\"invitation-request-ticket-sold-out-{sold_out_user_id}\""
    )));
    assert!(!body.contains(&format!(
        "invitation-request-ticket-sold-out-{available_user_id}"
    )));
}

#[tokio::test]
async fn test_list_page_rejects_zero_pagination_limit() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    db.expect_search_event_invitation_requests().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/invitation-requests?limit=0"),
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
async fn test_list_page_rejects_pagination_limit_above_maximum() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    db.expect_search_event_invitation_requests().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/invitation-requests?limit=101"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "limit: greater than 100\n"
    );
}

#[tokio::test]
async fn test_list_page_shows_status_reset_when_status_filtered_list_is_empty() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);
    let output = InvitationRequestsOutput {
        invitation_requests: vec![],
        total: 0,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_list_context(&mut db, &ids, event, vec![]);
    db.expect_search_event_invitation_requests()
        .times(1)
        .withf(move |gid, eid, filters| {
            *gid == ids.group_id
                && *eid == event_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && filters.status == InvitationRequestsStatusFilter::Pending
                && filters.ts_query.is_none()
        })
        .returning(move |_, _, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/invitation-requests"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);

    // Check the empty state names the status filter and offers a reset
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("No pending invitation requests found."));
    assert!(body.contains("Show all statuses"));
    assert!(!body.contains("No invitation requests found."));
}

#[tokio::test]
async fn test_list_page_steps_back_to_last_page_when_offset_is_past_end() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);
    let empty_page = InvitationRequestsOutput {
        invitation_requests: vec![],
        total: 6,
    };
    let last_page = InvitationRequestsOutput {
        invitation_requests: vec![sample_invitation_request()],
        total: 6,
    };

    // Setup session, permission, and event context expectations
    let mut db = MockDB::new();
    expect_list_context(&mut db, &ids, event, vec![]);

    // Setup the empty requested page followed by the last page with rows
    let mut sequence = Sequence::new();
    db.expect_search_event_invitation_requests()
        .times(1)
        .in_sequence(&mut sequence)
        .withf(move |gid, eid, filters| {
            *gid == ids.group_id
                && *eid == event_id
                && filters.limit == Some(5)
                && filters.offset == Some(10)
                && filters.status == InvitationRequestsStatusFilter::Pending
        })
        .return_once(move |_, _, _| Ok(empty_page));
    db.expect_search_event_invitation_requests()
        .times(1)
        .in_sequence(&mut sequence)
        .withf(move |gid, eid, filters| {
            *gid == ids.group_id
                && *eid == event_id
                && filters.limit == Some(5)
                && filters.offset == Some(5)
                && filters.status == InvitationRequestsStatusFilter::Pending
        })
        .return_once(move |_, _, _| Ok(last_page));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/invitation-requests?limit=5&offset=10"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the last page with rows is rendered and refreshed in place
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("Requesting User"));
    assert!(body.contains("offset=5"));
    assert!(!body.contains("offset=10"));
}

#[tokio::test]
async fn test_list_page_with_all_status_filter() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);
    let output = InvitationRequestsOutput {
        invitation_requests: vec![],
        total: 0,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_list_context(&mut db, &ids, event, vec![]);
    db.expect_search_event_invitation_requests()
        .times(1)
        .withf(move |gid, eid, filters| {
            *gid == ids.group_id
                && *eid == event_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && filters.status == InvitationRequestsStatusFilter::All
        })
        .returning(move |_, _, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/invitation-requests?status=all"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("status=all"));

    // Check the empty list does not offer a status reset
    assert!(body.contains("No invitation requests found."));
    assert!(!body.contains("Show all statuses"));
}

#[tokio::test]
async fn test_list_page_with_search_query() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);
    let output = InvitationRequestsOutput {
        invitation_requests: vec![sample_invitation_request()],
        total: 2,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_list_context(&mut db, &ids, event, vec![]);
    db.expect_search_event_invitation_requests()
        .times(1)
        .withf(move |gid, eid, filters| {
            *gid == ids.group_id
                && *eid == event_id
                && filters.limit == Some(1)
                && filters.offset == Some(0)
                && filters.sort == Some(InvitationRequestsSort::NameDesc)
                && filters.status == InvitationRequestsStatusFilter::Accepted
                && filters.title == Some(PresenceFilter::Missing)
                && filters.ts_query.as_deref() == Some("req")
        })
        .returning(move |_, _, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!(
            concat!(
                "/dashboard/group/events/{event_id}/invitation-requests?",
                "limit=1&sort=name-desc&status=accepted&",
                "title=missing&ts_query=req"
            ),
            event_id = event_id,
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("name=\"ts_query\""));
    assert!(body.contains("value=\"req\""));
    assert!(body.contains("Requesting User"));
    assert!(body.contains("offset=1"));
    assert!(body.contains("status=accepted"));
    assert!(body.contains("ts_query=req"));
    assert!(body.contains("refresh-event-invitation-requests"));
}

// Helpers.

/// Expects the session, permissions, event summary and registration questions
/// read by the list page.
fn expect_list_context(
    db: &mut MockDB,
    ids: &DashboardIds,
    event: EventSummary,
    registration_questions: Vec<QuestionnaireQuestion>,
) {
    let ids = *ids;
    let event_id = event.event_id;

    expect_group_access(db, &ids, GroupPermission::Read);
    expect_group_permission_result(db, &ids, GroupPermission::EventsWrite, true);
    db.expect_get_event_summary_dashboard()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == ids.community_id && *gid == ids.group_id && *eid == event_id
        })
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_event_registration_questions()
        .times(1)
        .withf(move |cid, eid| *cid == ids.community_id && *eid == event_id)
        .returning(move |_, _| Ok(registration_questions.clone()));
}
