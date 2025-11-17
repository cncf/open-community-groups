//! HTTP handlers for the members section in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Form, State},
    http::StatusCode,
    response::{Html, IntoResponse},
};
use serde::{Deserialize, Serialize};
use tracing::instrument;

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CommunityId, SelectedGroupId},
    },
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::{dashboard::group::members, notifications::GroupCustom},
};

// Pages handlers.

/// Displays the list of group members.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let members = db.list_group_members(group_id).await?;
    let template = members::ListPage { members };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Sends a custom notification to all group members.
#[instrument(skip_all, err)]
pub(crate) async fn send_group_custom_notification(
    auth_session: AuthSession,
    CommunityId(community_id): CommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    Form(notification): Form<GroupCustomNotification>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Get group members
    let user_ids = db.list_group_members_ids(group_id).await?;
    if user_ids.is_empty() {
        // Group has no members, nothing to do
        return Ok(StatusCode::NO_CONTENT.into_response());
    }

    // Get community (to get theme)
    let community = db.get_community(community_id).await?;

    // Enqueue notification
    let template_data = GroupCustom {
        subject: notification.subject.clone(),
        body: notification.body.clone(),
        theme: community.theme,
    };
    let new_notification = NewNotification {
        attachments: vec![],
        kind: NotificationKind::GroupCustom,
        recipients: user_ids,
        template_data: Some(serde_json::to_value(&template_data)?),
    };
    notifications_manager.enqueue(&new_notification).await?;

    // Track custom notification for auditing purposes
    db.track_custom_notification(
        user.user_id,
        None, // event_id is None for group notifications
        Some(group_id),
        &notification.subject,
        &notification.body,
    )
    .await?;

    Ok(StatusCode::NO_CONTENT.into_response())
}

// Types.

/// Form data for custom group notifications.
#[derive(Debug, Deserialize, Serialize)]
pub(crate) struct GroupCustomNotification {
    /// Subject line for the notification email.
    pub subject: String,
    /// Body text for the notification.
    pub body: String,
}

// Tests.

#[cfg(test)]
mod tests {
    use anyhow::anyhow;
    use axum::{
        body::{Body, to_bytes},
        http::{
            HeaderValue, Request, StatusCode,
            header::{CACHE_CONTROL, CONTENT_TYPE, COOKIE, HOST},
        },
    };
    use axum_login::tower_sessions::session;
    use tower::ServiceExt;
    use uuid::Uuid;

    use crate::{
        db::mock::MockDB,
        handlers::dashboard::group::members::GroupCustomNotification,
        handlers::tests::*,
        router::CACHE_CONTROL_NO_CACHE,
        services::notifications::{MockNotificationsManager, NotificationKind},
        templates::notifications::GroupCustom,
    };

    #[tokio::test]
    async fn test_list_page_success() {
        // Setup identifiers and data structures
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(group_id));
        let member = sample_group_member();

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
        db.expect_list_group_members()
            .times(1)
            .withf(move |id| *id == group_id)
            .returning(move |_| Ok(vec![member.clone()]));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/group/members")
            .header(HOST, "example.test")
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
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(group_id));

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
        db.expect_list_group_members()
            .times(1)
            .withf(move |id| *id == group_id)
            .returning(move |_| Err(anyhow!("db error")));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/group/members")
            .header(HOST, "example.test")
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
    async fn test_send_group_custom_notification_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let member_id1 = Uuid::new_v4();
        let member_id2 = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(group_id));
        let community = sample_community(community_id);
        let community_for_notifications = community.clone();
        let community_for_db = community;
        let notification_body = "Hello, group members!";
        let notification_subject = "Important Update";
        let form_data = serde_qs::to_string(&GroupCustomNotification {
            subject: notification_subject.to_string(),
            body: notification_body.to_string(),
        })
        .unwrap();

        // Create copies for the track_custom_notification closure
        let track_user_id = user_id;
        let track_group_id = group_id;
        let track_subject = notification_subject.to_string();
        let track_body = notification_body.to_string();

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
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_list_group_members_ids()
            .times(1)
            .withf(move |gid| *gid == group_id)
            .returning(move |_| Ok(vec![member_id1, member_id2]));
        db.expect_get_community()
            .times(1)
            .withf(move |cid| *cid == community_id)
            .returning({
                let community = community_for_db;
                move |_| Ok(community.clone())
            });
        db.expect_track_custom_notification()
            .times(1)
            .withf(move |created_by, event_id, group_id, subject, body| {
                *created_by == track_user_id
                    && event_id.is_none()
                    && *group_id == Some(track_group_id)
                    && subject == track_subject
                    && body == track_body
            })
            .returning(|_, _, _, _, _| Ok(()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue()
            .times(1)
            .withf(move |notification| {
                matches!(notification.kind, NotificationKind::GroupCustom)
                    && notification.recipients == vec![member_id1, member_id2]
                    && notification.template_data.as_ref().is_some_and(|value| {
                        serde_json::from_value::<GroupCustom>(value.clone())
                            .map(|template| {
                                template.subject == notification_subject
                                    && template.body == notification_body
                                    && template.theme.primary_color
                                        == community_for_notifications.theme.primary_color
                            })
                            .unwrap_or(false)
                    })
            })
            .returning(|_| Box::pin(async { Ok(()) }));

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("POST")
            .uri("/dashboard/group/notifications")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(Body::from(form_data))
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::NO_CONTENT);
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_send_group_custom_notification_no_members() {
        // Setup identifiers and data structures
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(group_id));
        let form_data = serde_qs::to_string(&GroupCustomNotification {
            subject: "Subject".to_string(),
            body: "Body".to_string(),
        })
        .unwrap();

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
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(Uuid::new_v4())));
        db.expect_list_group_members_ids()
            .times(1)
            .withf(move |gid| *gid == group_id)
            .returning(move |_| Ok(vec![]));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("POST")
            .uri("/dashboard/group/notifications")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(Body::from(form_data))
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::NO_CONTENT);
        assert!(bytes.is_empty());
    }
}
