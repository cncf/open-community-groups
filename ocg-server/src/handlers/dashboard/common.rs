//! Common HTTP handlers shared across different dashboards.

use std::collections::HashMap;

use anyhow::Result;
use axum::{
    Json,
    extract::{Query, State},
    response::IntoResponse,
};
use reqwest::StatusCode;
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::CommunityId},
};

/// Searches for users by query.
#[instrument(skip_all, err)]
pub(crate) async fn search_user(
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get search query from query parameters
    let Some(q) = query.get("q") else {
        return Ok(StatusCode::BAD_REQUEST.into_response());
    };

    // Search users in the database
    let users = db.search_user(community_id, q).await?;

    Ok(Json(users).into_response())
}

// Tests.

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use axum::{
        body::{to_bytes, Body},
        http::{
            header::{CACHE_CONTROL, CONTENT_TYPE, COOKIE, HOST},
            HeaderValue, Request, StatusCode,
        },
    };
    use axum_login::tower_sessions::session;
    use serde_json::{from_slice, to_value, json};
    use time::{Duration as TimeDuration, OffsetDateTime};
    use tower::ServiceExt;
    use uuid::Uuid;

    use crate::{
        auth::User as AuthUser,
        db::{
            dashboard::common::User as DashboardUser,
            mock::MockDB,
        },
        router::setup_test_router,
        services::notifications::MockNotificationsManager,
    };

    #[tokio::test]
    async fn test_search_user_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let session_user_id = Uuid::new_v4();
        let search_user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, session_user_id, &auth_hash);
        let expected_users = vec![sample_dashboard_user(search_user_id)];
        let expected_body = to_value(&expected_users).unwrap();
        let expected_users_clone = expected_users.clone();
        let auth_hash_clone = auth_hash.clone();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .withf(move |id| *id == session_user_id)
            .returning(move |_| Ok(Some(sample_auth_user(session_user_id, &auth_hash_clone))));
        db.expect_user_owns_community()
            .withf(move |cid, uid| *cid == community_id && *uid == session_user_id)
            .returning(|_, _| Ok(true));
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_search_user()
            .withf(move |id, query| *id == community_id && query == "john")
            .returning(move |_, _| Ok(expected_users_clone.clone()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/community/users/search?q=john")
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
            &HeaderValue::from_static("application/json")
        );
        assert_eq!(
            parts.headers.get(CACHE_CONTROL).unwrap(),
            &HeaderValue::from_static("max-age=0")
        );
        let body: serde_json::Value = from_slice(&bytes).unwrap();
        assert_eq!(body, expected_body);
    }

    #[tokio::test]
    async fn test_search_user_missing_query() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let session_user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, session_user_id, &auth_hash);
        let auth_hash_clone = auth_hash.clone();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .withf(move |id| *id == session_user_id)
            .returning(move |_| Ok(Some(sample_auth_user(session_user_id, &auth_hash_clone))));
        db.expect_user_owns_community()
            .withf(move |cid, uid| *cid == community_id && *uid == session_user_id)
            .returning(|_, _| Ok(true));
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/community/users/search")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::BAD_REQUEST);
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
            ..Default::default()
        }
    }

    /// Helper to create a sample dashboard user for tests.
    fn sample_dashboard_user(user_id: Uuid) -> DashboardUser {
        DashboardUser {
            user_id,
            username: "test-user".to_string(),

            name: Some("Test User".to_string()),
            photo_url: Some("https://example.test/avatar.png".to_string()),
        }
    }

    /// Helper to create a sample session record for tests.
    fn sample_session_record(
        session_id: session::Id,
        user_id: Uuid,
        auth_hash: &str,
    ) -> session::Record {
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
