use anyhow::anyhow;
use axum::http::{HeaderValue, StatusCode};
use uuid::Uuid;

use crate::{
    db::mock::MockDB, handlers::tests::*, types::dashboard::user::submissions::CfsSubmissionsOutput,
};

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and one listed submission
    let ids = DashboardIds::new();
    let output = CfsSubmissionsOutput {
        submissions: vec![sample_user_cfs_submission(
            Uuid::new_v4(),
            Uuid::new_v4(),
            Uuid::new_v4(),
        )],
        total: 11,
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_list_user_cfs_submissions()
        .times(1)
        .withf(move |uid, filters| {
            *uid == ids.user_id && filters.limit == Some(5) && filters.offset == Some(10)
        })
        .returning(move |_, _| Ok(output.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        "/dashboard/user/submissions?limit=5&offset=10",
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the requested page renders and pushes the full dashboard URL
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url"),
        Some(&HeaderValue::from_static(
            "/dashboard/user?tab=submissions&limit=5&offset=10"
        )),
    );
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("Proposal title"));
}

#[tokio::test]
async fn test_resubmit_db_error() {
    // Setup identifiers and a failing write with no flash message
    let cfs_submission_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_resubmit_cfs_submission()
        .times(1)
        .withf(move |uid, submission_id| *uid == ids.user_id && *submission_id == cfs_submission_id)
        .returning(|_, _| Err(anyhow!("db error")));
    db.expect_update_session().times(0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/user/submissions/{cfs_submission_id}/resubmit"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_resubmit_success() {
    // Setup identifiers and database mock
    let cfs_submission_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_resubmit_cfs_submission()
        .times(1)
        .withf(move |uid, submission_id| *uid == ids.user_id && *submission_id == cfs_submission_id)
        .returning(|_, _| Ok(()));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id && message_matches(record, "Submission resubmitted.")
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/user/submissions/{cfs_submission_id}/resubmit"),
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
async fn test_withdraw_db_error() {
    // Setup identifiers and a failing write with no flash message
    let cfs_submission_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_withdraw_cfs_submission()
        .times(1)
        .withf(move |uid, submission_id| *uid == ids.user_id && *submission_id == cfs_submission_id)
        .returning(|_, _| Err(anyhow!("db error")));
    db.expect_update_session().times(0);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/user/submissions/{cfs_submission_id}/withdraw"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_withdraw_success() {
    // Setup identifiers and database mock
    let cfs_submission_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_withdraw_cfs_submission()
        .times(1)
        .withf(move |uid, submission_id| *uid == ids.user_id && *submission_id == cfs_submission_id)
        .returning(|_, _| Ok(()));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id && message_matches(record, "Submission withdrawn.")
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/user/submissions/{cfs_submission_id}/withdraw"),
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
