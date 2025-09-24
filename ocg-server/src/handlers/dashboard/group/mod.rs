//! HTTP handlers for the group dashboard.

use axum::{extract::Path, http::StatusCode, response::IntoResponse};
use tower_sessions::Session;
use tracing::instrument;
use uuid::Uuid;

use crate::handlers::{auth::SELECTED_GROUP_ID_KEY, error::HandlerError};

pub(crate) mod attendees;
pub(crate) mod events;
pub(crate) mod home;
pub(crate) mod members;
pub(crate) mod settings;
pub(crate) mod sponsors;
pub(crate) mod team;

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
    use std::collections::HashMap;

    use axum::{
        body::{Body, to_bytes},
        http::{
            HeaderValue, Request, StatusCode,
            header::{COOKIE, HOST},
        },
    };
    use axum_login::tower_sessions::session;
    use serde_json::json;
    use time::{Duration as TimeDuration, OffsetDateTime};
    use tower::ServiceExt;
    use uuid::Uuid;

    use crate::{
        auth::User as AuthUser, db::mock::MockDB, handlers::auth::SELECTED_GROUP_ID_KEY,
        router::setup_test_router, services::notifications::MockNotificationsManager,
    };

    #[tokio::test]
    async fn test_select_group_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash);

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
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("PUT")
            .uri(format!("/dashboard/group/{group_id}/select"))
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
            parts.headers.get("HX-Location").unwrap(),
            &HeaderValue::from_static(r#"{"path":"/dashboard/group", "target":"body"}"#),
        );
        assert!(bytes.is_empty());
    }

    // Helpers.

    /// Helper to create a sample authenticated user for tests.
    fn sample_auth_user(user_id: Uuid, auth_hash: &str) -> AuthUser {
        AuthUser {
            auth_hash: auth_hash.to_string(),
            email: "user@example.test".to_string(),
            email_verified: true,
            name: "Test User".to_string(),
            user_id,
            username: "test-user".to_string(),
            belongs_to_any_group_team: Some(true),
            ..Default::default()
        }
    }

    /// Helper to create a sample session record without an initial selected group.
    fn sample_session_record(session_id: session::Id, user_id: Uuid, auth_hash: &str) -> session::Record {
        let mut data = HashMap::new();
        data.insert(
            "axum-login.data".to_string(),
            json!({
                "user_id": user_id,
                "auth_hash": auth_hash.as_bytes(),
            }),
        );
        session::Record {
            data,
            expiry_date: OffsetDateTime::now_utc().saturating_add(TimeDuration::days(1)),
            id: session_id,
        }
    }
}
