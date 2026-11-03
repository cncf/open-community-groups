use anyhow::anyhow;
use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::{error::INVALID_REQUEST_PAYLOAD, tests::*},
    services::notifications::MockNotificationsManager,
    types::{
        dashboard::{
            DASHBOARD_PAGINATION_LIMIT,
            group::submissions::{
                CfsSubmissionNotificationData, CfsSubmissionUpdate, CfsSubmissionsOutput,
            },
        },
        notifications::NotificationKind,
        permissions::GroupPermission,
    },
};

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let output = CfsSubmissionsOutput {
        submissions: vec![sample_group_cfs_submission(
            Uuid::new_v4(),
            Uuid::new_v4(),
            Uuid::new_v4(),
        )],
        total: 1,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);
    expect_list_page_reads(
        &mut db,
        &ids,
        event_id,
        (DASHBOARD_PAGINATION_LIMIT, 0),
        output,
    );

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/submissions"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the submission row renders the proposal title
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains(">Proposal title</div>"));
}

#[tokio::test]
async fn test_list_page_with_pagination_params() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let output = CfsSubmissionsOutput {
        submissions: vec![],
        total: 0,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);
    expect_list_page_reads(&mut db, &ids, event_id, (5, 10), output);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/submissions?limit=5&offset=10"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_list_page_rejects_limit_zero() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!(
            "/dashboard/group/events/{}/submissions?limit=0",
            Uuid::new_v4()
        ),
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
async fn test_list_page_rejects_unknown_sort() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!(
            "/dashboard/group/events/{}/submissions?sort=updated-desc",
            Uuid::new_v4()
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), INVALID_REQUEST_PAYLOAD.as_bytes());
}

#[tokio::test]
async fn test_list_page_returns_not_found_for_event_of_another_group() {
    // Setup identifiers
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();

    // Setup database mock without an event summary for the selected group
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::Read);
    expect_group_permission_result(&mut db, &ids, GroupPermission::EventsWrite, true);
    db.expect_find_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == ids.community_id && *gid == ids.group_id && *eid == event_id
        })
        .returning(|_, _, _| Ok(None));
    db.expect_list_event_labels()
        .times(1)
        .withf(move |eid| *eid == event_id)
        .returning(|_| Ok(vec![]));
    db.expect_list_event_cfs_submissions()
        .times(1)
        .withf(move |gid, eid, _| *gid == ids.group_id && *eid == event_id)
        .returning(|_, _, _| {
            Ok(CfsSubmissionsOutput {
                submissions: vec![],
                total: 0,
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        &format!("/dashboard/group/events/{event_id}/submissions"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the page is not found
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_update_db_error() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let cfs_submission_id = Uuid::new_v4();
    let form_data = serde_qs::to_string(&sample_submission_update()).unwrap();

    // Setup database mock with a failing write and no notification context reads
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);
    db.expect_update_cfs_submission()
        .times(1)
        .withf(move |uid, gid, eid, sid, _| {
            *uid == ids.user_id
                && *gid == ids.group_id
                && *eid == event_id
                && *sid == cfs_submission_id
        })
        .returning(|_, _, _, _, _| Err(anyhow!("db error")));
    db.expect_get_cfs_submission_notification_data().never();
    db.expect_get_event_summary().never();
    db.expect_get_site_settings().never();

    // Setup notifications manager mock, which must not be called
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_notifications_manager(nm)
        .build()
        .await;
    let request = update_request(&ids, event_id, cfs_submission_id, form_data);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_update_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let cfs_submission_id = Uuid::new_v4();
    let notification_user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);
    let update = CfsSubmissionUpdate {
        action_required_message: Some("Please update your slides.".to_string()),
        ..sample_submission_update()
    };
    let form_data = serde_qs::to_string(&update).unwrap();
    let notification_data = CfsSubmissionNotificationData {
        status_id: update.status_id.clone(),
        status_name: "Approved".to_string(),
        user_id: notification_user_id,

        action_required_message: update.action_required_message.clone(),
    };
    let site_settings = sample_site_settings();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);
    db.expect_update_cfs_submission()
        .times(1)
        .withf(move |uid, gid, eid, sid, submission| {
            *uid == ids.user_id
                && *gid == ids.group_id
                && *eid == event_id
                && *sid == cfs_submission_id
                && submission.status_id == "approved"
                && submission.label_ids.is_empty()
                && submission.action_required_message.as_deref()
                    == Some("Please update your slides.")
        })
        .returning(|_, _, _, _, _| Ok(true));

    // Setup the notification context reads made by the best-effort helper
    db.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == ids.community_id && *gid == ids.group_id && *eid == event_id
        })
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_cfs_submission_notification_data()
        .times(1)
        .withf(move |gid, eid, sid| {
            *gid == ids.group_id && *eid == event_id && *sid == cfs_submission_id
        })
        .returning(move |_, _, _| Ok(notification_data.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::CfsSubmissionUpdated)
                && notification.recipients == vec![notification_user_id]
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_notifications_manager(nm)
        .build()
        .await;
    let request = update_request(&ids, event_id, cfs_submission_id, form_data);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-event-submissions",
    );
}

#[tokio::test]
async fn test_update_without_notification_skips_context_reads() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let cfs_submission_id = Uuid::new_v4();
    let update = CfsSubmissionUpdate {
        rating_stars: Some(4),
        ..sample_submission_update()
    };
    let form_data = serde_qs::to_string(&update).unwrap();

    // Setup database mock with a write that needs no notification
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::EventsWrite);
    db.expect_update_cfs_submission()
        .times(1)
        .withf(move |uid, gid, eid, sid, submission| {
            *uid == ids.user_id
                && *gid == ids.group_id
                && *eid == event_id
                && *sid == cfs_submission_id
                && submission.rating_stars == Some(4)
        })
        .returning(|_, _, _, _, _| Ok(false));
    db.expect_get_cfs_submission_notification_data().never();
    db.expect_get_event_summary().never();
    db.expect_get_site_settings().never();

    // Setup notifications manager mock, which must not be called
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_notifications_manager(nm)
        .build()
        .await;
    let request = update_request(&ids, event_id, cfs_submission_id, form_data);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-event-submissions",
    );
}

// Helpers.

/// Registers the event, labels and submissions reads the list page performs.
fn expect_list_page_reads(
    db: &mut MockDB,
    ids: &DashboardIds,
    event_id: Uuid,
    (expected_limit, expected_offset): (usize, usize),
    output: CfsSubmissionsOutput,
) {
    let ids = *ids;
    let event = sample_event_summary(event_id);
    db.expect_find_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == ids.community_id && *gid == ids.group_id && *eid == event_id
        })
        .returning(move |_, _, _| Ok(Some(event.clone())));
    db.expect_list_event_labels()
        .times(1)
        .withf(move |eid| *eid == event_id)
        .returning(|_| Ok(vec![]));
    db.expect_list_event_cfs_submissions()
        .times(1)
        .withf(move |gid, eid, filters| {
            *gid == ids.group_id
                && *eid == event_id
                && filters.limit == Some(expected_limit)
                && filters.offset == Some(expected_offset)
        })
        .returning(move |_, _, _| Ok(output.clone()));
}

/// Returns a submission update that approves without extra review details.
fn sample_submission_update() -> CfsSubmissionUpdate {
    CfsSubmissionUpdate {
        label_ids: vec![],
        status_id: "approved".to_string(),

        action_required_message: None,
        rating_comment: None,
        rating_stars: None,
    }
}

/// Builds the submission update request.
fn update_request(
    ids: &DashboardIds,
    event_id: Uuid,
    cfs_submission_id: Uuid,
    form_data: String,
) -> Request<Body> {
    form_request(
        "PUT",
        &format!("/dashboard/group/events/{event_id}/submissions/{cfs_submission_id}"),
        ids.session_id,
        form_data,
    )
}
