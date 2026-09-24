use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderValue, Request, StatusCode,
        header::{CONTENT_TYPE, COOKIE},
    },
};
use axum_login::tower_sessions::session;
use mockall::Sequence;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    services::notifications::MockNotificationsManager,
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
#[allow(clippy::too_many_lines)]
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let question_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, group_id);
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
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );
    db.expect_get_event_summary_dashboard()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_event_registration_questions()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(registration_questions.clone()));
    db.expect_search_event_invitation_requests()
        .times(1)
        .withf(move |gid, eid, filters| {
            *gid == group_id
                && *eid == event_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && filters.status == InvitationRequestsStatusFilter::Pending
        })
        .returning(move |_, _, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!(
            "/dashboard/group/events/{event_id}/invitation-requests"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8"),
    );
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
#[allow(clippy::too_many_lines)]
async fn test_list_page_disables_accept_for_sold_out_requested_ticket_type() {
    // Setup identifiers and data structures
    let available_ticket_type_id = Uuid::from_u128(1);
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let sold_out_ticket_type_id = Uuid::from_u128(2);
    let user_id = Uuid::new_v4();
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
        ..sample_event_summary(event_id, group_id)
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
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );
    db.expect_get_event_summary_dashboard()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_event_registration_questions()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(|_, _| Ok(vec![]));
    db.expect_search_event_invitation_requests()
        .times(1)
        .withf(move |gid, eid, _| *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!(
            "/dashboard/group/events/{event_id}/invitation-requests"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
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
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!(
            "/dashboard/group/events/{event_id}/invitation-requests?limit=0"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_list_page_rejects_pagination_limit_above_maximum() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!(
            "/dashboard/group/events/{event_id}/invitation-requests?limit=101"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_list_page_shows_status_reset_when_status_filtered_list_is_empty() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, group_id);
    let output = InvitationRequestsOutput {
        invitation_requests: vec![],
        total: 0,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );
    db.expect_get_event_summary_dashboard()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_event_registration_questions()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(|_, _| Ok(vec![]));
    db.expect_search_event_invitation_requests()
        .times(1)
        .withf(move |gid, eid, filters| {
            *gid == group_id
                && *eid == event_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && filters.status == InvitationRequestsStatusFilter::Pending
                && filters.ts_query.is_none()
        })
        .returning(move |_, _, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!(
            "/dashboard/group/events/{event_id}/invitation-requests"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8"),
    );

    // Check the empty state names the status filter and offers a reset
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("No pending invitation requests found."));
    assert!(body.contains("Show all statuses"));
    assert!(!body.contains("No invitation requests found."));
}

#[tokio::test]
async fn test_list_page_steps_back_to_last_page_when_offset_is_past_end() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, group_id);
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
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );
    db.expect_get_event_summary_dashboard()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_event_registration_questions()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(|_, _| Ok(vec![]));

    // Setup the empty requested page followed by the last page with rows
    let mut sequence = Sequence::new();
    db.expect_search_event_invitation_requests()
        .times(1)
        .in_sequence(&mut sequence)
        .withf(move |gid, eid, filters| {
            *gid == group_id
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
            *gid == group_id
                && *eid == event_id
                && filters.limit == Some(5)
                && filters.offset == Some(5)
                && filters.status == InvitationRequestsStatusFilter::Pending
        })
        .return_once(move |_, _, _| Ok(last_page));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!(
            "/dashboard/group/events/{event_id}/invitation-requests?limit=5&offset=10"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the last page with rows is rendered and refreshed in place
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8"),
    );
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("Requesting User"));
    assert!(body.contains("offset=5"));
    assert!(!body.contains("offset=10"));
}

#[tokio::test]
async fn test_list_page_with_all_status_filter() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, group_id);
    let output = InvitationRequestsOutput {
        invitation_requests: vec![],
        total: 0,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );
    db.expect_get_event_summary_dashboard()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_event_registration_questions()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(|_, _| Ok(vec![]));
    db.expect_search_event_invitation_requests()
        .times(1)
        .withf(move |gid, eid, filters| {
            *gid == group_id
                && *eid == event_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
                && filters.status == InvitationRequestsStatusFilter::All
        })
        .returning(move |_, _, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!(
            "/dashboard/group/events/{event_id}/invitation-requests?status=all"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8"),
    );
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("status=all"));

    // Check the empty list does not offer a status reset
    assert!(body.contains("No invitation requests found."));
    assert!(!body.contains("Show all statuses"));
}

#[tokio::test]
async fn test_list_page_with_pagination_params() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, group_id);
    let output = InvitationRequestsOutput {
        invitation_requests: vec![],
        total: 0,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );
    db.expect_get_event_summary_dashboard()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_event_registration_questions()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(|_, _| Ok(vec![]));
    db.expect_search_event_invitation_requests()
        .times(1)
        .withf(move |gid, eid, filters| {
            *gid == group_id
                && *eid == event_id
                && filters.limit == Some(5)
                && filters.offset == Some(10)
                && filters.status == InvitationRequestsStatusFilter::Pending
        })
        .returning(move |_, _, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!(
            "/dashboard/group/events/{event_id}/invitation-requests?limit=5&offset=10"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8"),
    );
    assert!(!bytes.is_empty());
}

#[tokio::test]
async fn test_list_page_with_search_query() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, group_id);
    let output = InvitationRequestsOutput {
        invitation_requests: vec![sample_invitation_request()],
        total: 2,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_authenticated_group_session(&mut db, session_id, user_id, community_id, group_id);
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::Read,
    );
    expect_group_permission(
        &mut db,
        community_id,
        group_id,
        user_id,
        GroupPermission::EventsWrite,
    );
    db.expect_get_event_summary_dashboard()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_event_registration_questions()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(|_, _| Ok(vec![]));
    db.expect_search_event_invitation_requests()
        .times(1)
        .withf(move |gid, eid, filters| {
            *gid == group_id
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
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!(
            concat!(
                "/dashboard/group/events/{event_id}/invitation-requests?",
                "limit=1&sort=name-desc&status=accepted&",
                "title=missing&ts_query=req"
            ),
            event_id = event_id,
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/html; charset=utf-8"),
    );
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("name=\"ts_query\""));
    assert!(body.contains("value=\"req\""));
    assert!(body.contains("Requesting User"));
    assert!(body.contains("offset=1"));
    assert!(body.contains("status=accepted"));
    assert!(body.contains("ts_query=req"));
    assert!(body.contains("refresh-event-invitation-requests"));
}
