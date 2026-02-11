//! HTTP handlers for session proposals in the user dashboard.

use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use axum_messages::Messages;
use serde_json::to_value;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    auth::AuthSession,
    config::HttpServerConfig,
    db::DynDB,
    handlers::{error::HandlerError, extractors::ValidatedForm},
    router::serde_qs_config,
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::{
        dashboard::user::session_proposals::{self, SessionProposalInput},
        notifications::SessionProposalCoSpeakerInvitation,
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

    // Fetch pending invitations, session proposal levels, and session proposals
    let filters: session_proposals::SessionProposalsFilters =
        serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
    let (pending_co_speaker_invitations, session_proposal_levels, session_proposals_output) = tokio::try_join!(
        db.list_user_pending_session_proposal_co_speaker_invitations(user.user_id),
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
        pending_co_speaker_invitations,
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

/// Accepts a pending co-speaker invitation.
#[instrument(skip_all, err)]
pub(crate) async fn accept_co_speaker_invitation(
    auth_session: AuthSession,
    messages: Messages,
    State(db): State<DynDB>,
    Path(session_proposal_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Accept invitation
    db.accept_session_proposal_co_speaker_invitation(user.user_id, session_proposal_id)
        .await?;
    messages.success("Co-speaker invitation accepted.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Adds a session proposal for the authenticated user.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    auth_session: AuthSession,
    messages: Messages,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    ValidatedForm(session_proposal): ValidatedForm<SessionProposalInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Add session proposal to database
    db.add_session_proposal(user.user_id, &session_proposal).await?;

    // Notify co-speaker when invitation is created
    if let Some(co_speaker_user_id) = session_proposal.co_speaker_user_id {
        send_co_speaker_invitation_notification(
            &db,
            &notifications_manager,
            &server_cfg,
            co_speaker_user_id,
            session_proposal.title.as_str(),
            get_speaker_name(&user),
        )
        .await?;
    }

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

/// Rejects a pending co-speaker invitation.
#[instrument(skip_all, err)]
pub(crate) async fn reject_co_speaker_invitation(
    auth_session: AuthSession,
    messages: Messages,
    State(db): State<DynDB>,
    Path(session_proposal_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Reject invitation
    db.reject_session_proposal_co_speaker_invitation(user.user_id, session_proposal_id)
        .await?;
    messages.success("Co-speaker invitation declined.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Updates a session proposal for the authenticated user.
#[instrument(skip_all, err)]
#[allow(clippy::too_many_arguments)]
pub(crate) async fn update(
    auth_session: AuthSession,
    messages: Messages,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    Path(session_proposal_id): Path<Uuid>,
    ValidatedForm(session_proposal): ValidatedForm<SessionProposalInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Load proposal record to detect invitation target changes
    let previous_session_proposal = db
        .get_session_proposal_co_speaker_user_id(user.user_id, session_proposal_id)
        .await?;
    let Some(previous_session_proposal) = previous_session_proposal else {
        return Err(HandlerError::Database("session proposal not found".to_string()));
    };
    let previous_co_speaker_user_id = previous_session_proposal.co_speaker_user_id;

    // Update session proposal in database
    db.update_session_proposal(user.user_id, session_proposal_id, &session_proposal)
        .await?;

    // Notify new co-speaker when invitation target changed
    if let Some(co_speaker_user_id) = session_proposal.co_speaker_user_id
        && Some(co_speaker_user_id) != previous_co_speaker_user_id
    {
        send_co_speaker_invitation_notification(
            &db,
            &notifications_manager,
            &server_cfg,
            co_speaker_user_id,
            session_proposal.title.as_str(),
            get_speaker_name(&user),
        )
        .await?;
    }

    messages.success("Session proposal updated.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

// Helpers.

/// Returns the display name used as session proposal speaker.
fn get_speaker_name(user: &crate::auth::User) -> &str {
    if user.name.trim().is_empty() {
        user.username.as_str()
    } else {
        user.name.as_str()
    }
}

/// Sends a co-speaker invitation notification for a session proposal.
async fn send_co_speaker_invitation_notification(
    db: &DynDB,
    notifications_manager: &DynNotificationsManager,
    server_cfg: &HttpServerConfig,
    co_speaker_user_id: Uuid,
    session_proposal_title: &str,
    speaker_name: &str,
) -> Result<(), HandlerError> {
    // Build invitation link and template data
    let site_settings = db.get_site_settings().await?;
    let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
    let link = format!("{base_url}/dashboard/user?tab=session-proposals");
    let template_data = SessionProposalCoSpeakerInvitation {
        link,
        session_proposal_title: session_proposal_title.to_string(),
        speaker_name: speaker_name.to_string(),
        theme: site_settings.theme,
    };

    // Enqueue invitation notification
    let notification = NewNotification {
        attachments: vec![],
        kind: NotificationKind::SessionProposalCoSpeakerInvitation,
        recipients: vec![co_speaker_user_id],
        template_data: Some(to_value(&template_data)?),
    };
    notifications_manager.enqueue(&notification).await?;

    Ok(())
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
        db::{dashboard::user::SessionProposalCoSpeakerUser, mock::MockDB},
        handlers::tests::*,
        router::CACHE_CONTROL_NO_CACHE,
        services::notifications::{MockNotificationsManager, NotificationKind},
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
        let pending_invitations = vec![sample_pending_co_speaker_invitation(Uuid::new_v4())];

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
        db.expect_list_user_pending_session_proposal_co_speaker_invitations()
            .times(1)
            .withf(move |uid| *uid == user_id)
            .returning(move |_| Ok(pending_invitations.clone()));
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
        db.expect_list_user_pending_session_proposal_co_speaker_invitations()
            .times(1)
            .withf(move |uid| *uid == user_id)
            .returning(move |_| Ok(vec![]));
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
    async fn test_accept_co_speaker_invitation_success() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let session_proposal_id = Uuid::new_v4();
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
        db.expect_accept_session_proposal_co_speaker_invitation()
            .times(1)
            .withf(move |uid, pid| *uid == user_id && *pid == session_proposal_id)
            .returning(|_, _| Ok(()));
        db.expect_update_session()
            .times(1)
            .withf(move |record| {
                record.id == session_id && message_matches(record, "Co-speaker invitation accepted.")
            })
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!(
                "/dashboard/user/session-proposals/{session_proposal_id}/co-speaker-invitation/accept"
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
            &HeaderValue::from_static("refresh-body"),
        );
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
    async fn test_add_success_with_co_speaker_notification() {
        // Setup identifiers and data structures
        let co_speaker_user_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let session_proposal_id = Uuid::new_v4();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
        let form_data = format!(
            concat!(
                "title=Rust%20101",
                "&session_proposal_level_id=beginner",
                "&duration_minutes=45",
                "&description=Session%20about%20Rust",
                "&co_speaker_user_id={}"
            ),
            co_speaker_user_id
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
                    && input.co_speaker_user_id == Some(co_speaker_user_id)
            })
            .returning(move |_, _| Ok(session_proposal_id));
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));
        db.expect_update_session()
            .times(1)
            .withf(move |record| {
                record.id == session_id && message_matches(record, "Session proposal added.")
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
                    && notification.attachments.is_empty()
                    && notification.template_data.is_some()
            })
            .returning(|_| Box::pin(async { Ok(()) }));

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

    #[tokio::test]
    async fn test_reject_co_speaker_invitation_success() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let session_proposal_id = Uuid::new_v4();
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
        db.expect_reject_session_proposal_co_speaker_invitation()
            .times(1)
            .withf(move |uid, pid| *uid == user_id && *pid == session_proposal_id)
            .returning(|_, _| Ok(()));
        db.expect_update_session()
            .times(1)
            .withf(move |record| {
                record.id == session_id && message_matches(record, "Co-speaker invitation declined.")
            })
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!(
                "/dashboard/user/session-proposals/{session_proposal_id}/co-speaker-invitation/reject"
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
            &HeaderValue::from_static("refresh-body"),
        );
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
        db.expect_get_session_proposal_co_speaker_user_id()
            .times(1)
            .withf(move |uid, proposal_id| *uid == user_id && *proposal_id == session_proposal_id)
            .returning(|_, _| {
                Ok(Some(SessionProposalCoSpeakerUser {
                    co_speaker_user_id: None,
                }))
            });
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
    async fn test_update_success_with_co_speaker_notification() {
        // Setup identifiers and data structures
        let co_speaker_user_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let session_proposal_id = Uuid::new_v4();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
        let form_data = format!(
            concat!(
                "title=Rust%20102",
                "&session_proposal_level_id=intermediate",
                "&duration_minutes=60",
                "&description=Updated%20description",
                "&co_speaker_user_id={}"
            ),
            co_speaker_user_id
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
        db.expect_get_session_proposal_co_speaker_user_id()
            .times(1)
            .withf(move |uid, proposal_id| *uid == user_id && *proposal_id == session_proposal_id)
            .returning(|_, _| {
                Ok(Some(SessionProposalCoSpeakerUser {
                    co_speaker_user_id: None,
                }))
            });
        db.expect_update_session_proposal()
            .times(1)
            .withf(move |uid, proposal_id, input| {
                *uid == user_id
                    && *proposal_id == session_proposal_id
                    && input.title == "Rust 102"
                    && input.session_proposal_level_id == "intermediate"
                    && input.duration_minutes == 60
                    && input.description == "Updated description"
                    && input.co_speaker_user_id == Some(co_speaker_user_id)
            })
            .returning(|_, _, _| Ok(()));
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));
        db.expect_update_session()
            .times(1)
            .withf(move |record| {
                record.id == session_id && message_matches(record, "Session proposal updated.")
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
                    && notification.attachments.is_empty()
                    && notification.template_data.is_some()
            })
            .returning(|_| Box::pin(async { Ok(()) }));

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
        db.expect_get_session_proposal_co_speaker_user_id()
            .times(1)
            .withf(move |uid, proposal_id| *uid == user_id && *proposal_id == session_proposal_id)
            .returning(|_, _| {
                Ok(Some(SessionProposalCoSpeakerUser {
                    co_speaker_user_id: None,
                }))
            });
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
}
