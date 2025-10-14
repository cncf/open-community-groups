//! HTTP handlers for managing group team members in the dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::{Html, IntoResponse},
};
use axum_extra::extract::Form;
use serde::Deserialize;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CommunityId, SelectedGroupId},
    },
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::dashboard::group::team,
    templates::notifications::GroupTeamInvitation,
    types::group::GroupRole,
};

// Pages handlers.

/// Displays the list of group team members.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (members, roles) = tokio::try_join!(db.list_group_team_members(group_id), db.list_group_roles())?;
    let approved_members_count = members.iter().filter(|m| m.accepted).count();
    let template = team::ListPage {
        approved_members_count,
        members,
        roles,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Adds a user to the group team.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    CommunityId(community_id): CommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(cfg): State<HttpServerConfig>,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    Form(member): Form<NewTeamMember>,
) -> Result<impl IntoResponse, HandlerError> {
    // Add team member to database using provided role
    db.add_group_team_member(group_id, member.user_id, &member.role)
        .await?;

    // Enqueue invitation email notification
    let group = db.get_group_summary(community_id, group_id).await?;
    let template_data = GroupTeamInvitation {
        group,
        link: format!(
            "{}/dashboard/user?tab=invitations",
            cfg.base_url.strip_suffix('/').unwrap_or(&cfg.base_url)
        ),
    };
    let notification = NewNotification {
        kind: NotificationKind::GroupTeamInvitation,
        recipients: vec![member.user_id],
        template_data: Some(serde_json::to_value(&template_data)?),
    };
    notifications_manager.enqueue(&notification).await?;

    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Deletes a user from the group team.
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(user_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Remove team member from database
    db.delete_group_team_member(group_id, user_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Updates a user role in the group team.
#[instrument(skip_all, err)]
pub(crate) async fn update_role(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(user_id): Path<Uuid>,
    Form(input): Form<NewTeamRole>,
) -> Result<impl IntoResponse, HandlerError> {
    // Update team member role in database
    db.update_group_team_member_role(group_id, user_id, &input.role)
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

// Types.

/// Data needed to add a new team member.
#[derive(Debug, Deserialize)]
pub(crate) struct NewTeamMember {
    /// Team role.
    role: GroupRole,
    /// User identifier.
    user_id: Uuid,
}

/// Data needed to update a team member role.
#[derive(Debug, Deserialize)]
pub(crate) struct NewTeamRole {
    role: GroupRole,
}

// Tests.

#[cfg(test)]
mod tests {
    use axum::{
        body::{Body, to_bytes},
        http::{
            HeaderValue, Request, StatusCode,
            header::{CACHE_CONTROL, CONTENT_TYPE, COOKIE, HOST},
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
        templates::notifications::GroupTeamInvitation,
        types::group::GroupRole,
    };

    use super::NewTeamMember;

    #[tokio::test]
    async fn test_list_page_success() {
        // Setup identifiers and data structures
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(group_id));
        let member = sample_team_member(true);
        let role = sample_group_role_summary();

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
        db.expect_list_group_team_members()
            .times(1)
            .withf(move |id| *id == group_id)
            .returning(move |_| Ok(vec![member.clone(), sample_team_member(false)]));
        db.expect_list_group_roles()
            .times(1)
            .returning(move || Ok(vec![role.clone()]));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/group/team")
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
    async fn test_add_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let new_member_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(group_id));
        let form = NewTeamMember {
            role: GroupRole::Organizer,
            user_id: new_member_id,
        };
        let body = format!("role={}&user_id={}", form.role, form.user_id);
        let group_summary = sample_group_summary(group_id);
        let group_summary_for_db = group_summary.clone();

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
        db.expect_add_group_team_member()
            .times(1)
            .withf(move |id, uid, role| {
                *id == group_id && *uid == new_member_id && role == &GroupRole::Organizer
            })
            .returning(move |_, _, _| Ok(()));
        db.expect_get_group_summary()
            .times(1)
            .withf(move |cid, gid| *cid == community_id && *gid == group_id)
            .returning(move |_, _| Ok(group_summary_for_db.clone()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue()
            .times(1)
            .withf(move |notification| {
                matches!(notification.kind, NotificationKind::GroupTeamInvitation)
                    && notification.recipients == vec![new_member_id]
                    && notification.template_data.as_ref().is_some_and(|value| {
                        from_value::<GroupTeamInvitation>(value.clone())
                            .map(|template| {
                                template.group.group_id == group_summary.group_id
                                    && template.link == "/dashboard/user?tab=invitations"
                            })
                            .unwrap_or(false)
                    })
            })
            .returning(|_| Box::pin(async { Ok(()) }));

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("POST")
            .uri("/dashboard/group/team/add")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(Body::from(body))
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::CREATED);
        assert_eq!(
            parts.headers.get("HX-Trigger").unwrap(),
            &HeaderValue::from_static("refresh-group-dashboard-table"),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_delete_success() {
        // Setup identifiers and data structures
        let group_id = Uuid::new_v4();
        let member_id = Uuid::new_v4();
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
        db.expect_delete_group_team_member()
            .times(1)
            .withf(move |id, uid| *id == group_id && *uid == member_id)
            .returning(move |_, _| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("DELETE")
            .uri(format!("/dashboard/group/team/{member_id}/delete"))
            .header(HOST, "example.test")
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
            &HeaderValue::from_static("refresh-group-dashboard-table"),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_update_role_success() {
        // Setup identifiers and data structures
        let group_id = Uuid::new_v4();
        let member_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(group_id));
        let form = super::NewTeamRole {
            role: GroupRole::Organizer,
        };
        let body = format!("role={}", form.role);

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
        db.expect_update_group_team_member_role()
            .times(1)
            .withf(move |id, uid, role| *id == group_id && *uid == member_id && role == &GroupRole::Organizer)
            .returning(move |_, _, _| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!("/dashboard/group/team/{member_id}/role"))
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(Body::from(body))
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::NO_CONTENT);
        assert_eq!(
            parts.headers.get("HX-Trigger").unwrap(),
            &HeaderValue::from_static("refresh-group-dashboard-table"),
        );
        assert!(bytes.is_empty());
    }
}
