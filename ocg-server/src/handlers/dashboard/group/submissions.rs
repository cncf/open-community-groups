//! HTTP handlers for event CFS submissions in the group dashboard.

use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::StatusCode,
    response::{Html, IntoResponse},
};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    auth::AuthSession,
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{SelectedCommunityId, SelectedGroupId, ValidatedForm},
    },
    router::serde_qs_config,
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::{
        dashboard::group::submissions::{self, CfsSubmissionUpdate, CfsSubmissionsFilters},
        notifications::CfsSubmissionUpdated,
        pagination::{self, NavigationLinks},
    },
};

// Pages handlers.

/// Displays the CFS submissions list for an event.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Fetch event submissions (checking event belongs to group)
    let filters: CfsSubmissionsFilters =
        serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
    let (_event, statuses, submissions) = tokio::try_join!(
        db.get_event_summary(community_id, group_id, event_id), // ensure event belongs to group
        db.list_cfs_submission_statuses_for_review(),
        db.list_event_cfs_submissions(event_id, &filters)
    )?;

    // Prepare template
    let base_path = format!("/dashboard/group/events/{event_id}/submissions");
    let navigation_links =
        NavigationLinks::from_filters(&filters, submissions.total, &base_path, &base_path)?;
    let refresh_url = pagination::build_url(&base_path, &filters)?;
    let template = submissions::ListPage {
        event_id,
        statuses,
        submissions: submissions.submissions,
        navigation_links,
        refresh_url,
        total: submissions.total,
        limit: filters.limit,
        offset: filters.offset,
    };

    Ok(Html(template.render()?))
}

// Action handlers.

/// Updates a CFS submission for an event.
#[allow(clippy::too_many_arguments)]
#[instrument(skip_all, err)]
pub(crate) async fn update(
    auth_session: AuthSession,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    Path((event_id, cfs_submission_id)): Path<(Uuid, Uuid)>,
    ValidatedForm(update): ValidatedForm<CfsSubmissionUpdate>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let reviewer = auth_session.user.expect("user to be logged in");

    // Ensure event belongs to the group
    let event = db.get_event_summary(community_id, group_id, event_id).await?;

    // Update submission in database
    db.update_cfs_submission(reviewer.user_id, event_id, cfs_submission_id, &update)
        .await?;

    // Enqueue notification to submission author
    let (notification_data, site_settings) = tokio::try_join!(
        db.get_cfs_submission_notification_data(event_id, cfs_submission_id),
        db.get_site_settings(),
    )?;
    let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
    let link = format!("{base_url}/dashboard/user?tab=submissions");
    let template_data = CfsSubmissionUpdated {
        action_required_message: notification_data.action_required_message,
        event,
        link,
        status_name: notification_data.status_name,
        theme: site_settings.theme,
    };
    let notification = NewNotification {
        attachments: vec![],
        kind: NotificationKind::CfsSubmissionUpdated,
        recipients: vec![notification_data.user_id],
        template_data: Some(serde_json::to_value(&template_data)?),
    };
    notifications_manager.enqueue(&notification).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-event-submissions")],
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
    use serde_json::from_value;
    use tower::ServiceExt;
    use uuid::Uuid;

    use crate::{
        db::mock::MockDB,
        handlers::tests::*,
        router::CACHE_CONTROL_NO_CACHE,
        services::notifications::{MockNotificationsManager, NotificationKind},
        templates::{dashboard::DASHBOARD_PAGINATION_LIMIT, notifications::CfsSubmissionUpdated},
    };

    #[tokio::test]
    async fn test_list_page_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
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
        let session_proposal_id = Uuid::new_v4();
        let cfs_submission_id = Uuid::new_v4();
        let speaker_id = Uuid::new_v4();
        let event = sample_event_summary(event_id, group_id);
        let submissions_output = crate::templates::dashboard::group::submissions::CfsSubmissionsOutput {
            submissions: vec![sample_group_cfs_submission(
                cfs_submission_id,
                session_proposal_id,
                speaker_id,
            )],
            total: 1,
        };
        let statuses = vec![sample_group_cfs_submission_status("submitted", "Submitted")];

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
        db.expect_get_event_summary()
            .times(1)
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(event.clone()));
        db.expect_list_cfs_submission_statuses_for_review()
            .times(1)
            .returning(move || Ok(statuses.clone()));
        db.expect_list_event_cfs_submissions()
            .times(1)
            .withf(move |eid, filters| {
                *eid == event_id
                    && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                    && filters.offset == Some(0)
            })
            .returning(move |_, _| Ok(submissions_output.clone()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri(format!("/dashboard/group/events/{event_id}/submissions"))
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
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
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
        let event = sample_event_summary(event_id, group_id);
        let submissions_output = crate::templates::dashboard::group::submissions::CfsSubmissionsOutput {
            submissions: vec![],
            total: 0,
        };
        let statuses = vec![sample_group_cfs_submission_status("submitted", "Submitted")];

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
        db.expect_get_event_summary()
            .times(1)
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(event.clone()));
        db.expect_list_cfs_submission_statuses_for_review()
            .times(1)
            .returning(move || Ok(statuses.clone()));
        db.expect_list_event_cfs_submissions()
            .times(1)
            .withf(move |eid, filters| {
                *eid == event_id && filters.limit == Some(5) && filters.offset == Some(10)
            })
            .returning(move |_, _| Ok(submissions_output.clone()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri(format!(
                "/dashboard/group/events/{event_id}/submissions?limit=5&offset=10"
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
        let event_id = Uuid::new_v4();
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
        db.expect_get_event_summary()
            .times(1)
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning(|_, _, _| Err(anyhow!("db error")));
        db.expect_list_cfs_submission_statuses_for_review()
            .times(0..=1)
            .returning(|| Ok(vec![]));
        db.expect_list_event_cfs_submissions().times(0..=1).returning(|_, _| {
            Ok(
                crate::templates::dashboard::group::submissions::CfsSubmissionsOutput {
                    submissions: vec![],
                    total: 0,
                },
            )
        });

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri(format!("/dashboard/group/events/{event_id}/submissions"))
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
    #[allow(clippy::too_many_lines)]
    async fn test_update_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let cfs_submission_id = Uuid::new_v4();
        let notification_user_id = Uuid::new_v4();
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
        let event = sample_event_summary(event_id, group_id);
        let update = crate::templates::dashboard::group::submissions::CfsSubmissionUpdate {
            status_id: "approved".to_string(),
            action_required_message: Some("Please update your slides.".to_string()),
        };
        let form_data = serde_qs::to_string(&update).unwrap();
        let notification_data =
            crate::templates::dashboard::group::submissions::CfsSubmissionNotificationData {
                status_id: update.status_id.clone(),
                status_name: "Approved".to_string(),
                user_id: notification_user_id,

                action_required_message: update.action_required_message.clone(),
            };
        let site_settings = sample_site_settings();
        let expected_link = "/dashboard/user?tab=submissions".to_string();
        let theme_primary_color = site_settings.theme.primary_color.clone();

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
        db.expect_get_event_summary()
            .times(1)
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(event.clone()));
        db.expect_update_cfs_submission()
            .times(1)
            .withf(move |uid, eid, sid, submission| {
                *uid == user_id
                    && *eid == event_id
                    && *sid == cfs_submission_id
                    && submission.status_id == "approved"
                    && submission.action_required_message.as_deref() == Some("Please update your slides.")
            })
            .returning(|_, _, _, _| Ok(()));
        db.expect_get_cfs_submission_notification_data()
            .times(1)
            .withf(move |eid, sid| *eid == event_id && *sid == cfs_submission_id)
            .returning(move |_, _| Ok(notification_data.clone()));
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
                    && notification.template_data.as_ref().is_some_and(|value| {
                        from_value::<CfsSubmissionUpdated>(value.clone())
                            .map(|template| {
                                template.action_required_message.as_deref()
                                    == Some("Please update your slides.")
                                    && template.event.event_id == event_id
                                    && template.link == expected_link
                                    && template.status_name == "Approved"
                                    && template.theme.primary_color == theme_primary_color
                            })
                            .unwrap_or(false)
                    })
            })
            .returning(|_| Box::pin(async { Ok(()) }));

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!(
                "/dashboard/group/events/{event_id}/submissions/{cfs_submission_id}"
            ))
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
            &HeaderValue::from_static("refresh-event-submissions"),
        );
        assert!(bytes.is_empty());
    }
}
