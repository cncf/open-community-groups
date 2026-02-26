//! HTTP handlers to manage invitations in the user dashboard.

use askama::Template;
use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::{Html, IntoResponse},
};
use axum_messages::Messages;
use tower_sessions::Session;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        auth::{SELECTED_COMMUNITY_ID_KEY, select_first_community_and_group},
        error::HandlerError,
        extractors::CurrentUser,
    },
    templates::dashboard::user::invitations,
};

// Pages handlers.

/// Returns the invitations list page for the user dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template fetching both lists concurrently
    let (community_invitations, group_invitations) = tokio::try_join!(
        db.list_user_community_team_invitations(user.user_id),
        db.list_user_group_team_invitations(user.user_id)
    )?;
    let template = invitations::ListPage {
        community_invitations,
        group_invitations,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Accepts a pending community team invitation.
#[instrument(skip_all, err)]
pub(crate) async fn accept_community_team_invitation(
    messages: Messages,
    session: Session,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(community_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Accept community team invitation
    db.accept_community_team_invitation(community_id, user.user_id)
        .await?;
    messages.success("Team invitation accepted.");

    // Select first community and group if none selected
    if session.get::<Uuid>(SELECTED_COMMUNITY_ID_KEY).await?.is_none() {
        select_first_community_and_group(&db, &session, &user.user_id).await?;
    }

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Accepts a pending group team invitation.
#[instrument(skip_all, err)]
pub(crate) async fn accept_group_team_invitation(
    messages: Messages,
    session: Session,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Mark invitation as accepted
    db.accept_group_team_invitation(group_id, user.user_id).await?;
    messages.success("Team invitation accepted.");

    // Select first community and group if none selected
    if session.get::<Uuid>(SELECTED_COMMUNITY_ID_KEY).await?.is_none() {
        select_first_community_and_group(&db, &session, &user.user_id).await?;
    }

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Rejects a pending community team invitation.
#[instrument(skip_all, err)]
pub(crate) async fn reject_community_team_invitation(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(community_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Delete community team member
    db.delete_community_team_member(community_id, user.user_id).await?;
    messages.success("Team invitation rejected.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Rejects a pending group team invitation.
#[instrument(skip_all, err)]
pub(crate) async fn reject_group_team_invitation(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Delete group team member from database
    db.delete_group_team_member(group_id, user.user_id).await?;
    messages.success("Team invitation rejected.");

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

    use serde_json::json;

    use crate::{
        db::mock::MockDB,
        handlers::{
            auth::{SELECTED_COMMUNITY_ID_KEY, SELECTED_GROUP_ID_KEY},
            tests::*,
        },
        router::CACHE_CONTROL_NO_CACHE,
        services::notifications::MockNotificationsManager,
    };

    #[tokio::test]
    async fn test_list_page_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
        let community_invitations = vec![sample_community_invitation(community_id)];
        let group_invitations = vec![sample_group_invitation(Uuid::new_v4())];

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
        db.expect_list_user_community_team_invitations()
            .times(1)
            .withf(move |uid| *uid == user_id)
            .returning(move |_| Ok(community_invitations.clone()));
        db.expect_list_user_group_team_invitations()
            .times(1)
            .withf(move |uid| *uid == user_id)
            .returning(move |_| Ok(group_invitations.clone()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/user/invitations")
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
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
        let community_invitations = vec![sample_community_invitation(community_id)];

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
        db.expect_list_user_community_team_invitations()
            .times(1)
            .withf(move |uid| *uid == user_id)
            .returning(move |_| Ok(community_invitations.clone()));
        db.expect_list_user_group_team_invitations()
            .times(1)
            .withf(move |uid| *uid == user_id)
            .returning(move |_| Err(anyhow!("db error")));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/user/invitations")
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
    async fn test_accept_community_team_invitation_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
        let groups = sample_user_groups_by_community(community_id, group_id);

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
        db.expect_accept_community_team_invitation()
            .times(1)
            .withf(move |cid, uid| *cid == community_id && *uid == user_id)
            .returning(|_, _| Ok(()));
        db.expect_list_user_groups()
            .times(1)
            .withf(move |uid| *uid == user_id)
            .returning(move |_| Ok(groups.clone()));
        db.expect_update_session()
            .times(1)
            .withf(move |record| {
                record.id == session_id
                    && message_matches(record, "Team invitation accepted.")
                    && record
                        .data
                        .get(SELECTED_COMMUNITY_ID_KEY)
                        .is_some_and(|value| value == &json!(community_id))
                    && record
                        .data
                        .get(SELECTED_GROUP_ID_KEY)
                        .is_some_and(|value| value == &json!(group_id))
            })
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!(
                "/dashboard/user/invitations/community/{community_id}/accept"
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
    async fn test_accept_group_team_invitation_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
        let groups = sample_user_groups_by_community(community_id, group_id);

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
        db.expect_accept_group_team_invitation()
            .times(1)
            .withf(move |gid, uid| *gid == group_id && *uid == user_id)
            .returning(|_, _| Ok(()));
        db.expect_list_user_groups()
            .times(1)
            .withf(move |uid| *uid == user_id)
            .returning(move |_| Ok(groups.clone()));
        db.expect_update_session()
            .times(1)
            .withf(move |record| {
                record.id == session_id
                    && message_matches(record, "Team invitation accepted.")
                    && record
                        .data
                        .get(SELECTED_COMMUNITY_ID_KEY)
                        .is_some_and(|value| value == &json!(community_id))
                    && record
                        .data
                        .get(SELECTED_GROUP_ID_KEY)
                        .is_some_and(|value| value == &json!(group_id))
            })
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!("/dashboard/user/invitations/group/{group_id}/accept"))
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
    async fn test_reject_community_team_invitation_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
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
        db.expect_delete_community_team_member()
            .times(1)
            .withf(move |cid, uid| *cid == community_id && *uid == user_id)
            .returning(|_, _| Ok(()));
        db.expect_update_session()
            .times(1)
            .withf(move |record| {
                record.id == session_id && message_matches(record, "Team invitation rejected.")
            })
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!(
                "/dashboard/user/invitations/community/{community_id}/reject"
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
    async fn test_reject_group_team_invitation_success() {
        // Setup identifiers and data structures
        let group_id = Uuid::new_v4();
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
        db.expect_delete_group_team_member()
            .times(1)
            .withf(move |gid, uid| *gid == group_id && *uid == user_id)
            .returning(|_, _| Ok(()));
        db.expect_update_session()
            .times(1)
            .withf(move |record| {
                record.id == session_id && message_matches(record, "Team invitation rejected.")
            })
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!("/dashboard/user/invitations/group/{group_id}/reject"))
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
}
