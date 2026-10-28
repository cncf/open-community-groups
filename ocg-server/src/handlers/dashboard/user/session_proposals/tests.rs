use anyhow::anyhow;
use axum::http::{HeaderValue, StatusCode};
use uuid::Uuid;

use crate::{
    db::{
        dashboard::user::SessionProposalCoSpeakerUser,
        mock::{MockDB, expect_site_settings},
    },
    handlers::tests::*,
    services::notifications::MockNotificationsManager,
    types::{
        dashboard::{DASHBOARD_PAGINATION_LIMIT, user::session_proposals::SessionProposalsOutput},
        notifications::NotificationKind,
    },
};

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let session_proposal_id = Uuid::new_v4();
    let output = SessionProposalsOutput {
        session_proposals: vec![sample_session_proposal(session_proposal_id)],
        total: 1,
    };
    let levels = sample_session_proposal_levels();
    let pending_invitations = vec![sample_pending_co_speaker_invitation(Uuid::new_v4())];

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_list_session_proposal_levels()
        .times(1)
        .returning(move || Ok(levels.clone()));
    db.expect_list_user_pending_session_proposal_co_speaker_invitations()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(move |_| Ok(pending_invitations.clone()));
    db.expect_list_user_session_proposals()
        .times(1)
        .withf(move |uid, filters| {
            *uid == ids.user_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(move |_, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user/session-proposals", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the listed proposal and the full dashboard URL
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url"),
        Some(&HeaderValue::from_static(
            "/dashboard/user?tab=session-proposals&limit=50&offset=0"
        )),
    );
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("Rust 101"));
}

#[tokio::test]
async fn test_accept_co_speaker_invitation_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let session_proposal_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_accept_session_proposal_co_speaker_invitation()
        .times(1)
        .withf(move |uid, pid| *uid == ids.user_id && *pid == session_proposal_id)
        .returning(|_, _| Ok(()));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id
                && message_matches(record, "Co-speaker invitation accepted.")
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "PUT",
        &format!(
            "/dashboard/user/session-proposals/{session_proposal_id}/co-speaker-invitation/accept"
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-user-dashboard-content",
    );
}

#[tokio::test]
async fn test_add_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_add_session_proposal()
        .times(1)
        .withf(move |uid, input| {
            *uid == ids.user_id
                && input.title == "Rust 101"
                && input.session_proposal_level_id == "beginner"
                && input.duration_minutes == 45
                && input.description == "Session about Rust"
                && input.co_speaker_user_id.is_none()
        })
        .returning(|_, _| Ok(Uuid::new_v4()));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id && message_matches(record, "Session proposal added.")
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "POST",
        "/dashboard/user/session-proposals",
        ids.session_id,
        add_form(None),
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::CREATED,
        "refresh-user-dashboard-content",
    );
}

#[tokio::test]
async fn test_add_success_with_co_speaker_notification() {
    // Setup identifiers and database mock
    let co_speaker_user_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let session_proposal_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_add_session_proposal()
        .times(1)
        .withf(move |uid, input| {
            *uid == ids.user_id
                && input.title == "Rust 101"
                && input.session_proposal_level_id == "beginner"
                && input.duration_minutes == 45
                && input.description == "Session about Rust"
                && input.co_speaker_user_id == Some(co_speaker_user_id)
        })
        .returning(move |_, _| Ok(session_proposal_id));
    expect_site_settings(&mut db);
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id && message_matches(record, "Session proposal added.")
        })
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(
                notification.kind,
                NotificationKind::SessionProposalCoSpeakerInvitation
            ) && notification.recipients == vec![co_speaker_user_id]
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_notifications_manager(nm)
        .build()
        .await;
    let request = form_request(
        "POST",
        "/dashboard/user/session-proposals",
        ids.session_id,
        add_form(Some(co_speaker_user_id)),
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::CREATED,
        "refresh-user-dashboard-content",
    );
}

#[tokio::test]
async fn test_add_db_error() {
    // Setup identifiers and a failing write, with no invitation or flash message
    let co_speaker_user_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_add_session_proposal()
        .times(1)
        .withf(move |uid, input| {
            *uid == ids.user_id && input.co_speaker_user_id == Some(co_speaker_user_id)
        })
        .returning(|_, _| Err(anyhow!("db error")));
    db.expect_get_site_settings().never();
    db.expect_update_session().never();

    // Setup notifications manager mock, which must not be called
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_notifications_manager(nm)
        .build()
        .await;
    let request = form_request(
        "POST",
        "/dashboard/user/session-proposals",
        ids.session_id,
        add_form(Some(co_speaker_user_id)),
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_delete_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let session_proposal_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_delete_session_proposal()
        .times(1)
        .withf(move |uid, proposal_id| *uid == ids.user_id && *proposal_id == session_proposal_id)
        .returning(|_, _| Ok(()));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id && message_matches(record, "Session proposal deleted.")
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "DELETE",
        &format!("/dashboard/user/session-proposals/{session_proposal_id}"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-user-dashboard-content",
    );
}

#[tokio::test]
async fn test_delete_db_error() {
    // Setup identifiers and a failing write with no flash message
    let ids = DashboardIds::new();
    let session_proposal_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_delete_session_proposal()
        .times(1)
        .withf(move |uid, proposal_id| *uid == ids.user_id && *proposal_id == session_proposal_id)
        .returning(|_, _| Err(anyhow!("db error")));
    db.expect_update_session().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "DELETE",
        &format!("/dashboard/user/session-proposals/{session_proposal_id}"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_reject_co_speaker_invitation_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let session_proposal_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_reject_session_proposal_co_speaker_invitation()
        .times(1)
        .withf(move |uid, pid| *uid == ids.user_id && *pid == session_proposal_id)
        .returning(|_, _| Ok(()));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id
                && message_matches(record, "Co-speaker invitation declined.")
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "PUT",
        &format!(
            "/dashboard/user/session-proposals/{session_proposal_id}/co-speaker-invitation/reject"
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-user-dashboard-content",
    );
}

#[tokio::test]
async fn test_update_db_error() {
    // Setup identifiers and a failing write, with no invitation or flash message
    let co_speaker_user_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let session_proposal_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    expect_previous_co_speaker(&mut db, &ids, session_proposal_id, None);
    db.expect_update_session_proposal()
        .times(1)
        .withf(move |uid, proposal_id, input| {
            *uid == ids.user_id
                && *proposal_id == session_proposal_id
                && input.co_speaker_user_id == Some(co_speaker_user_id)
        })
        .returning(|_, _, _| Err(anyhow!("db error")));
    db.expect_get_site_settings().never();
    db.expect_update_session().never();

    // Setup notifications manager mock, which must not be called
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_notifications_manager(nm)
        .build()
        .await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/user/session-proposals/{session_proposal_id}"),
        ids.session_id,
        update_form(Some(co_speaker_user_id)),
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_update_rejects_missing_session_proposal() {
    // Setup identifiers and a proposal the user does not own
    let ids = DashboardIds::new();
    let session_proposal_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_get_session_proposal_co_speaker_user_id()
        .times(1)
        .withf(move |uid, proposal_id| *uid == ids.user_id && *proposal_id == session_proposal_id)
        .returning(|_, _| Ok(None));
    db.expect_update_session_proposal().never();
    db.expect_update_session().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/user/session-proposals/{session_proposal_id}"),
        ids.session_id,
        update_form(None),
    );
    let (parts, bytes) = send(router, request).await;

    // Check the missing proposal is rejected before the update
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), b"session proposal not found");
}

#[tokio::test]
async fn test_update_skips_notification_when_co_speaker_is_unchanged() {
    // Setup identifiers and a proposal already inviting the co-speaker
    let co_speaker_user_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let session_proposal_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    expect_previous_co_speaker(&mut db, &ids, session_proposal_id, Some(co_speaker_user_id));
    db.expect_update_session_proposal()
        .times(1)
        .withf(move |uid, proposal_id, input| {
            *uid == ids.user_id
                && *proposal_id == session_proposal_id
                && input.co_speaker_user_id == Some(co_speaker_user_id)
        })
        .returning(|_, _, _| Ok(()));
    db.expect_get_site_settings().never();
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id && message_matches(record, "Session proposal updated.")
        })
        .returning(|_| Ok(()));

    // Setup notifications manager mock, which must not be called
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_notifications_manager(nm)
        .build()
        .await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/user/session-proposals/{session_proposal_id}"),
        ids.session_id,
        update_form(Some(co_speaker_user_id)),
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-user-dashboard-content",
    );
}

#[tokio::test]
async fn test_update_success() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let session_proposal_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    expect_previous_co_speaker(&mut db, &ids, session_proposal_id, None);
    db.expect_update_session_proposal()
        .times(1)
        .withf(move |uid, proposal_id, input| {
            *uid == ids.user_id
                && *proposal_id == session_proposal_id
                && input.title == "Rust 102"
                && input.session_proposal_level_id == "intermediate"
                && input.duration_minutes == 60
                && input.description == "Updated description"
                && input.co_speaker_user_id.is_none()
        })
        .returning(|_, _, _| Ok(()));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id && message_matches(record, "Session proposal updated.")
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/user/session-proposals/{session_proposal_id}"),
        ids.session_id,
        update_form(None),
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-user-dashboard-content",
    );
}

#[tokio::test]
async fn test_update_success_with_co_speaker_notification() {
    // Setup identifiers and database mock
    let co_speaker_user_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let session_proposal_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    expect_previous_co_speaker(&mut db, &ids, session_proposal_id, None);
    db.expect_update_session_proposal()
        .times(1)
        .withf(move |uid, proposal_id, input| {
            *uid == ids.user_id
                && *proposal_id == session_proposal_id
                && input.title == "Rust 102"
                && input.session_proposal_level_id == "intermediate"
                && input.duration_minutes == 60
                && input.description == "Updated description"
                && input.co_speaker_user_id == Some(co_speaker_user_id)
        })
        .returning(|_, _, _| Ok(()));
    expect_site_settings(&mut db);
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id && message_matches(record, "Session proposal updated.")
        })
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(
                notification.kind,
                NotificationKind::SessionProposalCoSpeakerInvitation
            ) && notification.recipients == vec![co_speaker_user_id]
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_notifications_manager(nm)
        .build()
        .await;
    let request = form_request(
        "PUT",
        &format!("/dashboard/user/session-proposals/{session_proposal_id}"),
        ids.session_id,
        update_form(Some(co_speaker_user_id)),
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(
        &parts,
        &bytes,
        StatusCode::NO_CONTENT,
        "refresh-user-dashboard-content",
    );
}

// Helpers.

/// Builds the add form: title "Rust 101", level "beginner", 45 minutes,
/// description "Session about Rust", and the optional co-speaker.
fn add_form(co_speaker_user_id: Option<Uuid>) -> String {
    let form = concat!(
        "title=Rust%20101",
        "&session_proposal_level_id=beginner",
        "&duration_minutes=45",
        "&description=Session%20about%20Rust"
    );
    with_co_speaker(form, co_speaker_user_id)
}

/// Expects the read of the co-speaker the proposal invited before the update.
fn expect_previous_co_speaker(
    db: &mut MockDB,
    ids: &DashboardIds,
    session_proposal_id: Uuid,
    previous_co_speaker_user_id: Option<Uuid>,
) {
    let user_id = ids.user_id;
    db.expect_get_session_proposal_co_speaker_user_id()
        .times(1)
        .withf(move |uid, proposal_id| *uid == user_id && *proposal_id == session_proposal_id)
        .returning(move |_, _| {
            Ok(Some(SessionProposalCoSpeakerUser {
                co_speaker_user_id: previous_co_speaker_user_id,
            }))
        });
}

/// Builds the update form: title "Rust 102", level "intermediate", 60
/// minutes, description "Updated description", and the optional co-speaker.
fn update_form(co_speaker_user_id: Option<Uuid>) -> String {
    let form = concat!(
        "title=Rust%20102",
        "&session_proposal_level_id=intermediate",
        "&duration_minutes=60",
        "&description=Updated%20description"
    );
    with_co_speaker(form, co_speaker_user_id)
}

/// Appends the co-speaker field to the form when one is invited.
fn with_co_speaker(form: &str, co_speaker_user_id: Option<Uuid>) -> String {
    match co_speaker_user_id {
        Some(co_speaker_user_id) => format!("{form}&co_speaker_user_id={co_speaker_user_id}"),
        None => form.to_string(),
    }
}
