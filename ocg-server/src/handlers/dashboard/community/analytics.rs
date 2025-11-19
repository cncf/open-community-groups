//! HTTP handlers for the community analytics page.

use askama::Template;
use axum::{
    extract::State,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::CommunityId},
    templates::dashboard::community::analytics,
};

// Pages handlers.

/// Displays the community analytics dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    let stats = db.get_community_stats(community_id).await?;
    let page = analytics::Page { stats };

    Ok(Html(page.render()?))
}

// Tests.

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

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
        handlers::tests::*,
        router::CACHE_CONTROL_NO_CACHE,
        services::notifications::MockNotificationsManager,
        templates::dashboard::community::analytics::{
            AttendeesStats, CommunityStats, EventsStats, GroupsStats, MembersStats,
        },
    };

    #[tokio::test]
    async fn test_page_db_error() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);

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
        db.expect_user_owns_community()
            .times(1)
            .withf(move |cid, uid| *cid == community_id && *uid == user_id)
            .returning(|_, _| Ok(true));
        db.expect_get_community_id()
            .times(2)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community_stats()
            .times(1)
            .withf(move |cid| *cid == community_id)
            .returning(|_| Err(anyhow!("db error")));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/community/analytics")
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
    async fn test_page_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);
        let stats = sample_community_stats();

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
        db.expect_user_owns_community()
            .times(1)
            .withf(move |cid, uid| *cid == community_id && *uid == user_id)
            .returning(|_, _| Ok(true));
        db.expect_get_community_id()
            .times(2)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community_stats()
            .times(1)
            .withf(move |cid| *cid == community_id)
            .returning(move |_| Ok(stats.clone()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/community/analytics")
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

    // Helpers.

    fn sample_community_stats() -> CommunityStats {
        CommunityStats {
            attendees: AttendeesStats {
                per_month: vec![("2024-01".to_string(), 5)],
                per_month_by_event_category: HashMap::from([(
                    "meetup".to_string(),
                    vec![("2024-01".to_string(), 5)],
                )]),
                per_month_by_group_category: HashMap::new(),
                per_month_by_group_region: HashMap::new(),
                running_total: vec![(1, 5)],
                running_total_by_event_category: HashMap::new(),
                running_total_by_group_category: HashMap::new(),
                running_total_by_group_region: HashMap::new(),
                total: 5,
                total_by_event_category: vec![("meetup".to_string(), 5)],
                total_by_group_category: vec![],
                total_by_group_region: vec![],
            },
            events: EventsStats {
                per_month: vec![("2024-01".to_string(), 3)],
                per_month_by_event_category: HashMap::from([(
                    "webinar".to_string(),
                    vec![("2024-01".to_string(), 3)],
                )]),
                per_month_by_group_category: HashMap::new(),
                per_month_by_group_region: HashMap::new(),
                running_total: vec![(1, 3)],
                running_total_by_event_category: HashMap::new(),
                running_total_by_group_category: HashMap::new(),
                running_total_by_group_region: HashMap::new(),
                total: 3,
                total_by_event_category: vec![("webinar".to_string(), 3)],
                total_by_group_category: vec![],
                total_by_group_region: vec![],
            },
            groups: GroupsStats {
                per_month: vec![("2024-01".to_string(), 2)],
                per_month_by_category: HashMap::from([("dev".to_string(), vec![("2024-01".to_string(), 2)])]),
                per_month_by_region: HashMap::new(),
                running_total: vec![(1, 2)],
                running_total_by_category: HashMap::new(),
                running_total_by_region: HashMap::new(),
                total: 2,
                total_by_category: vec![("dev".to_string(), 2)],
                total_by_region: vec![],
            },
            members: MembersStats {
                per_month: vec![("2024-01".to_string(), 8)],
                per_month_by_category: HashMap::new(),
                per_month_by_region: HashMap::new(),
                running_total: vec![(1, 8)],
                running_total_by_category: HashMap::new(),
                running_total_by_region: HashMap::new(),
                total: 8,
                total_by_category: vec![],
                total_by_region: vec![],
            },
        }
    }
}
