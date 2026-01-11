//! HTTP handlers for the group dashboard.

use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
};
use tower_sessions::Session;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        auth::{SELECTED_COMMUNITY_ID_KEY, SELECTED_GROUP_ID_KEY},
        error::HandlerError,
    },
};

pub(crate) mod analytics;
pub(crate) mod attendees;
pub(crate) mod events;
pub(crate) mod home;
pub(crate) mod members;
pub(crate) mod settings;
pub(crate) mod sponsors;
pub(crate) mod team;

/// Sets the selected community and auto-selects the first group in session.
#[instrument(skip_all, err)]
pub(crate) async fn select_community(
    session: Session,
    State(db): State<DynDB>,
    Path(community_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session
    let user_id: Uuid = session
        .get("user_id")
        .await?
        .ok_or_else(|| anyhow::anyhow!("user not logged in"))?;

    // Get user's groups and find groups in the selected community
    let groups_by_community = db.list_user_groups(&user_id).await?;
    let community_groups = groups_by_community.iter().find(|c| c.community_id == community_id);

    // If user has no groups in this community, check if they're a community team member
    if community_groups.is_none() {
        let communities = db.list_user_communities(&user_id).await?;
        if !communities.iter().any(|c| c.community_id == community_id) {
            return Err(HandlerError::Forbidden);
        }
    }

    // Update the selected community and group in the session
    session.insert(SELECTED_COMMUNITY_ID_KEY, community_id).await?;
    if let Some(first_group_id) = community_groups.and_then(|c| c.groups.first()).map(|g| g.group_id) {
        session.insert(SELECTED_GROUP_ID_KEY, first_group_id).await?;
    }

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Location", r#"{"path":"/dashboard/group", "target":"body"}"#)],
    ))
}

/// Sets the selected group in the session for the current user.
#[instrument(skip_all, err)]
pub(crate) async fn select_group(
    session: Session,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Update the selected group in the session
    session.insert(SELECTED_GROUP_ID_KEY, group_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Location", r#"{"path":"/dashboard/group", "target":"body"}"#)],
    ))
}

// Tests.

#[cfg(test)]
mod tests {
    use axum::{
        body::{Body, to_bytes},
        http::{HeaderValue, Request, StatusCode, header::COOKIE},
    };
    use axum_login::tower_sessions::session;
    use serde_json::json;
    use tower::ServiceExt;
    use uuid::Uuid;

    use crate::{
        db::mock::MockDB,
        handlers::{auth::SELECTED_GROUP_ID_KEY, tests::*},
        services::notifications::MockNotificationsManager,
    };

    #[tokio::test]
    async fn test_select_group_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);

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
        db.expect_update_session()
            .times(1)
            .withf(move |record| {
                record.id == session_id
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
            .uri(format!("/dashboard/group/{group_id}/select"))
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::NO_CONTENT);
        assert_eq!(
            parts.headers.get("HX-Location").unwrap(),
            &HeaderValue::from_static(r#"{"path":"/dashboard/group", "target":"body"}"#),
        );
        assert!(bytes.is_empty());
    }
}
