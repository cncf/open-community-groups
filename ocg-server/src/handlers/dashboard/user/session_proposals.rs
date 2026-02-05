//! HTTP handlers for session proposals in the user dashboard.

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
    auth::AuthSession,
    db::DynDB,
    handlers::{error::HandlerError, extractors::ValidatedForm},
    router::serde_qs_config,
    templates::{
        dashboard::user::session_proposals::{self, SessionProposalInput},
        pagination,
        pagination::NavigationLinks,
    },
};

// Pages handlers.

/// Returns the session proposals list page for the user dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Fetch session proposals and levels
    let filters: session_proposals::SessionProposalsFilters =
        serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
    let (session_proposal_levels, session_proposals_output) = tokio::try_join!(
        db.list_session_proposal_levels(),
        db.list_user_session_proposals(user.user_id, &filters)
    )?;

    // Prepare template
    let navigation_links = NavigationLinks::from_filters(
        &filters,
        session_proposals_output.total,
        "/dashboard/user?tab=session-proposals",
        "/dashboard/user/session-proposals",
    )?;
    let template = session_proposals::ListPage {
        session_proposal_levels,
        session_proposals: session_proposals_output.session_proposals,
        navigation_links,
        total: session_proposals_output.total,
        limit: filters.limit,
        offset: filters.offset,
    };

    // Prepare response headers
    let url = pagination::build_url("/dashboard/user?tab=session-proposals", &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

// Actions handlers.

/// Adds a session proposal for the authenticated user.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    auth_session: AuthSession,
    messages: Messages,
    State(db): State<DynDB>,
    ValidatedForm(session_proposal): ValidatedForm<SessionProposalInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Add session proposal to database
    db.add_session_proposal(user.user_id, &session_proposal).await?;
    messages.success("Session proposal added.");

    Ok((StatusCode::CREATED, [("HX-Trigger", "refresh-body")]))
}

/// Deletes a session proposal for the authenticated user.
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    auth_session: AuthSession,
    messages: Messages,
    State(db): State<DynDB>,
    Path(session_proposal_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Delete session proposal from database
    db.delete_session_proposal(user.user_id, session_proposal_id).await?;
    messages.success("Session proposal deleted.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Updates a session proposal for the authenticated user.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    auth_session: AuthSession,
    messages: Messages,
    State(db): State<DynDB>,
    Path(session_proposal_id): Path<Uuid>,
    ValidatedForm(session_proposal): ValidatedForm<SessionProposalInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Update session proposal in database
    db.update_session_proposal(user.user_id, session_proposal_id, &session_proposal)
        .await?;
    messages.success("Session proposal updated.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
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
        db::mock::MockDB,
        handlers::tests::*,
        router::CACHE_CONTROL_NO_CACHE,
        services::notifications::MockNotificationsManager,
        templates::dashboard::{DASHBOARD_PAGINATION_LIMIT, user::session_proposals::SessionProposalsOutput},
    };

    #[tokio::test]
    async fn test_list_page_success() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let session_proposal_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
        let output = SessionProposalsOutput {
            session_proposals: vec![sample_session_proposal(session_proposal_id)],
            total: 1,
        };
        let levels = sample_session_proposal_levels();

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
        db.expect_list_session_proposal_levels()
            .times(1)
            .returning(move || Ok(levels.clone()));
        db.expect_list_user_session_proposals()
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
            .uri("/dashboard/user/session-proposals")
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
        db.expect_list_session_proposal_levels()
            .times(1)
            .returning(|| Ok(sample_session_proposal_levels()));
        db.expect_list_user_session_proposals()
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
            .uri("/dashboard/user/session-proposals")
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
    async fn test_add_success() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
        let form_data = concat!(
            "title=Rust%20101",
            "&session_proposal_level_id=beginner",
            "&duration_minutes=45",
            "&description=Session%20about%20Rust"
        );

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
        db.expect_add_session_proposal()
            .times(1)
            .withf(move |uid, input| {
                *uid == user_id
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
                record.id == session_id && message_matches(record, "Session proposal added.")
            })
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("POST")
            .uri("/dashboard/user/session-proposals")
            .header(COOKIE, format!("id={session_id}"))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(Body::from(form_data))
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::CREATED);
        assert_eq!(
            parts.headers.get("HX-Trigger").unwrap(),
            &HeaderValue::from_static("refresh-body"),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_add_db_error() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
        let form_data = concat!(
            "title=Rust%20101",
            "&session_proposal_level_id=beginner",
            "&duration_minutes=45",
            "&description=Session%20about%20Rust"
        );

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
        db.expect_add_session_proposal()
            .times(1)
            .withf(move |uid, input| {
                *uid == user_id
                    && input.title == "Rust 101"
                    && input.session_proposal_level_id == "beginner"
                    && input.duration_minutes == 45
                    && input.description == "Session about Rust"
                    && input.co_speaker_user_id.is_none()
            })
            .returning(|_, _| Err(anyhow!("db error")));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("POST")
            .uri("/dashboard/user/session-proposals")
            .header(COOKIE, format!("id={session_id}"))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(Body::from(form_data))
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_update_success() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let session_proposal_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
        let form_data = concat!(
            "title=Rust%20102",
            "&session_proposal_level_id=intermediate",
            "&duration_minutes=60",
            "&description=Updated%20description"
        );

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
        db.expect_update_session_proposal()
            .times(1)
            .withf(move |uid, proposal_id, input| {
                *uid == user_id
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
                record.id == session_id && message_matches(record, "Session proposal updated.")
            })
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!("/dashboard/user/session-proposals/{session_proposal_id}"))
            .header(COOKIE, format!("id={session_id}"))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(Body::from(form_data))
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::NO_CONTENT);
        assert_eq!(
            parts.headers.get("HX-Trigger").unwrap(),
            &HeaderValue::from_static("refresh-body"),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_update_db_error() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let session_proposal_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
        let form_data = concat!(
            "title=Rust%20102",
            "&session_proposal_level_id=intermediate",
            "&duration_minutes=60",
            "&description=Updated%20description"
        );

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
        db.expect_update_session_proposal()
            .times(1)
            .withf(move |uid, proposal_id, input| {
                *uid == user_id
                    && *proposal_id == session_proposal_id
                    && input.title == "Rust 102"
                    && input.session_proposal_level_id == "intermediate"
                    && input.duration_minutes == 60
                    && input.description == "Updated description"
                    && input.co_speaker_user_id.is_none()
            })
            .returning(|_, _, _| Err(anyhow!("db error")));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!("/dashboard/user/session-proposals/{session_proposal_id}"))
            .header(COOKIE, format!("id={session_id}"))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(Body::from(form_data))
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_delete_success() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let session_proposal_id = Uuid::new_v4();
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
        db.expect_delete_session_proposal()
            .times(1)
            .withf(move |uid, proposal_id| *uid == user_id && *proposal_id == session_proposal_id)
            .returning(|_, _| Ok(()));
        db.expect_update_session()
            .times(1)
            .withf(move |record| {
                record.id == session_id && message_matches(record, "Session proposal deleted.")
            })
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("DELETE")
            .uri(format!("/dashboard/user/session-proposals/{session_proposal_id}"))
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
            &HeaderValue::from_static("refresh-body"),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_delete_db_error() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let session_proposal_id = Uuid::new_v4();
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
        db.expect_delete_session_proposal()
            .times(1)
            .withf(move |uid, proposal_id| *uid == user_id && *proposal_id == session_proposal_id)
            .returning(|_, _| Err(anyhow!("db error")));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("DELETE")
            .uri(format!("/dashboard/user/session-proposals/{session_proposal_id}"))
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
}
