//! HTTP handlers for user CFS submissions.

use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use axum_messages::Messages;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::CurrentUser},
    router::serde_qs_config,
    templates::{dashboard::user::submissions, pagination, pagination::NavigationLinks},
};

// Pages handlers.

/// Returns the submissions list page for the user dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Fetch submissions
    let filters: submissions::CfsSubmissionsFilters =
        serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
    let results = db.list_user_cfs_submissions(user.user_id, &filters).await?;

    // Prepare template
    let navigation_links = NavigationLinks::from_filters(
        &filters,
        results.total,
        "/dashboard/user?tab=submissions",
        "/dashboard/user/submissions",
    )?;
    let template = submissions::ListPage {
        submissions: results.submissions,
        navigation_links,
        total: results.total,
        limit: filters.limit,
        offset: filters.offset,
    };

    // Prepare response headers
    let url = pagination::build_url("/dashboard/user?tab=submissions", &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

// Actions handlers.

/// Resubmits a CFS submission for the authenticated user.
#[instrument(skip_all, err)]
pub(crate) async fn resubmit(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(cfs_submission_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Resubmit CFS submission
    db.resubmit_cfs_submission(user.user_id, cfs_submission_id).await?;
    messages.success("Submission resubmitted.");

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-user-dashboard-content")],
    ))
}

/// Withdraws a CFS submission for the authenticated user.
#[instrument(skip_all, err)]
pub(crate) async fn withdraw(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(cfs_submission_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Withdraw CFS submission
    db.withdraw_cfs_submission(user.user_id, cfs_submission_id).await?;
    messages.success("Submission withdrawn.");

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-user-dashboard-content")],
    ))
}

// Tests.

#[cfg(test)]
mod tests {
    use anyhow::anyhow;
    use axum::{
        body::{Body, to_bytes},
        http::{
            HeaderValue, Request, StatusCode,
            header::{CACHE_CONTROL, CONTENT_TYPE, COOKIE},
        },
    };
    use axum_login::tower_sessions::session;
    use tower::ServiceExt;
    use uuid::Uuid;

    use crate::{
        db::mock::MockDB, handlers::tests::*, router::CACHE_CONTROL_NO_CACHE,
        services::notifications::MockNotificationsManager, templates::dashboard::DASHBOARD_PAGINATION_LIMIT,
    };

    #[tokio::test]
    async fn test_list_page_success() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_proposal_id = Uuid::new_v4();
        let cfs_submission_id = Uuid::new_v4();
        let output = crate::templates::dashboard::user::submissions::CfsSubmissionsOutput {
            submissions: vec![sample_user_cfs_submission(
                cfs_submission_id,
                event_id,
                group_id,
                session_proposal_id,
            )],
            total: 1,
        };

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_list_user_cfs_submissions()
            .times(1)
            .withf(move |uid, filters| {
                *uid == user_id
                    && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                    && filters.offset == Some(0)
            })
            .returning(move |_, _| Ok(output.clone()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/user/submissions")
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
        assert_eq!(
            parts.headers.get(CACHE_CONTROL).unwrap(),
            &HeaderValue::from_static(CACHE_CONTROL_NO_CACHE),
        );
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_list_page_with_pagination_params() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
        let output = crate::templates::dashboard::user::submissions::CfsSubmissionsOutput {
            submissions: vec![],
            total: 0,
        };

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_list_user_cfs_submissions()
            .times(1)
            .withf(move |uid, filters| {
                *uid == user_id && filters.limit == Some(5) && filters.offset == Some(10)
            })
            .returning(move |_, _| Ok(output.clone()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/user/submissions?limit=5&offset=10")
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
        assert_eq!(
            parts.headers.get(CACHE_CONTROL).unwrap(),
            &HeaderValue::from_static(CACHE_CONTROL_NO_CACHE),
        );
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_list_page_db_error() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_list_user_cfs_submissions()
            .times(1)
            .withf(move |uid, filters| {
                *uid == user_id
                    && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                    && filters.offset == Some(0)
            })
            .returning(|_, _| Err(anyhow!("db error")));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/user/submissions")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_resubmit_success() {
        // Setup identifiers and data structures
        let cfs_submission_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_resubmit_cfs_submission()
            .times(1)
            .withf(move |uid, submission_id| *uid == user_id && *submission_id == cfs_submission_id)
            .returning(|_, _| Ok(()));
        db.expect_update_session()
            .times(1)
            .withf(move |record| {
                record.id == session_id && message_matches(record, "Submission resubmitted.")
            })
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!(
                "/dashboard/user/submissions/{cfs_submission_id}/resubmit"
            ))
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::NO_CONTENT);
        assert_eq!(
            parts.headers.get("HX-Trigger").unwrap(),
            &HeaderValue::from_static("refresh-user-dashboard-content"),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_withdraw_success() {
        // Setup identifiers and data structures
        let cfs_submission_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_withdraw_cfs_submission()
            .times(1)
            .withf(move |uid, submission_id| *uid == user_id && *submission_id == cfs_submission_id)
            .returning(|_, _| Ok(()));
        db.expect_update_session()
            .times(1)
            .withf(move |record| record.id == session_id && message_matches(record, "Submission withdrawn."))
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!(
                "/dashboard/user/submissions/{cfs_submission_id}/withdraw"
            ))
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::NO_CONTENT);
        assert_eq!(
            parts.headers.get("HX-Trigger").unwrap(),
            &HeaderValue::from_static("refresh-user-dashboard-content"),
        );
        assert!(bytes.is_empty());
    }
}
