//! HTTP handlers for the members section in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::State,
    http::StatusCode,
    response::{Html, IntoResponse},
};
use garde::Validate;
use serde::{Deserialize, Serialize};
use tracing::instrument;

use crate::validation::{MAX_LEN_M, MAX_LEN_XL, trimmed_non_empty};

use crate::{
    auth::AuthSession,
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{SelectedCommunityId, SelectedGroupId, ValidatedForm},
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
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    ValidatedForm(notification): ValidatedForm<GroupCustomNotification>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Get group data and site settings
    let (site_settings, group, group_members_ids) = tokio::try_join!(
        db.get_site_settings(),
        db.get_group_summary(community_id, group_id),
        db.list_group_members_ids(group_id),
    )?;

    // If there are no members, nothing to do
    if group_members_ids.is_empty() {
        return Ok(StatusCode::NO_CONTENT.into_response());
    }

    // Enqueue notification
    let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
    let link = format!("{}/{}/group/{}", base_url, group.community_name, group.slug);
    let template_data = GroupCustom {
        body: notification.body.clone(),
        group,
        link,
        theme: site_settings.theme,
        title: notification.title.clone(),
    };
    let new_notification = NewNotification {
        attachments: vec![],
        kind: NotificationKind::GroupCustom,
        recipients: group_members_ids,
        template_data: Some(serde_json::to_value(&template_data)?),
    };
    notifications_manager.enqueue(&new_notification).await?;

    // Track custom notification for auditing purposes
    db.track_custom_notification(
        user.user_id,
        None, // event_id is None for group notifications
        Some(group_id),
        &notification.title,
        &notification.body,
    )
    .await?;

    Ok(StatusCode::NO_CONTENT.into_response())
}

// Types.

/// Form data for custom group notifications.
#[derive(Debug, Deserialize, Serialize, Validate)]
pub(crate) struct GroupCustomNotification {
    /// Body text for the notification.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_XL))]
    pub body: String,
    /// Title line for the notification email.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub title: String,
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
        handlers::dashboard::group::members::GroupCustomNotification,
        handlers::tests::*,
        router::CACHE_CONTROL_NO_CACHE,
        services::notifications::{MockNotificationsManager, NotificationKind},
        templates::notifications::GroupCustom,
    };

    #[tokio::test]
    async fn test_list_page_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(
            session_id,
            user_id,
            &auth_hash,
            Some(community_id),
            Some(group_id),
        );
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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));
        db.expect_list_group_members()
            .times(1)
            .withf(move |id| *id == group_id)
            .returning(move |_| Ok(vec![member.clone()]));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/group/members")
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
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(
            session_id,
            user_id,
            &auth_hash,
            Some(community_id),
            Some(group_id),
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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));
        db.expect_list_group_members()
            .times(1)
            .withf(move |id| *id == group_id)
            .returning(move |_| Err(anyhow!("db error")));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/group/members")
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
        let session_record = sample_session_record(
            session_id,
            user_id,
            &auth_hash,
            Some(community_id),
            Some(group_id),
        );
        let site_settings = sample_site_settings();
        let site_settings_for_notifications = site_settings.clone();
        let group_summary = sample_group_summary(group_id);
        let expected_link = format!("/{}/group/{}", group_summary.community_name, group_summary.slug);
        let group_for_notifications = group_summary.clone();
        let group_for_db = group_summary.clone();
        let notification_body = "Hello, group members!";
        let notification_subject = "Important Update";
        let form_data = serde_qs::to_string(&GroupCustomNotification {
            title: notification_subject.to_string(),
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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));
        db.expect_list_group_members_ids()
            .times(1)
            .withf(move |gid| *gid == group_id)
            .returning(move |_| Ok(vec![member_id1, member_id2]));
        db.expect_get_site_settings()
            .times(1)
            .returning(move || Ok(site_settings.clone()));
        db.expect_get_group_summary()
            .times(1)
            .withf(move |cid, gid| *cid == community_id && *gid == group_id)
            .returning(move |_, _| Ok(group_for_db.clone()));
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
                                template.title == notification_subject
                                    && template.body == notification_body
                                    && template.group.name == group_for_notifications.name
                                    && template.link == expected_link
                                    && template.theme.primary_color
                                        == site_settings_for_notifications.theme.primary_color
                            })
                            .unwrap_or(false)
                    })
            })
            .returning(|_| Box::pin(async { Ok(()) }));

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("POST")
            .uri("/dashboard/group/notifications")
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
        let group_for_db = sample_group_summary(group_id);
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(
            session_id,
            user_id,
            &auth_hash,
            Some(community_id),
            Some(group_id),
        );
        let form_data = serde_qs::to_string(&GroupCustomNotification {
            title: "Subject".to_string(),
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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));
        db.expect_get_group_summary()
            .times(1)
            .withf(move |cid, gid| *cid == community_id && *gid == group_id)
            .returning(move |_, _| Ok(group_for_db.clone()));
        db.expect_list_group_members_ids()
            .times(1)
            .withf(move |gid| *gid == group_id)
            .returning(move |_| Ok(vec![]));
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("POST")
            .uri("/dashboard/group/notifications")
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
