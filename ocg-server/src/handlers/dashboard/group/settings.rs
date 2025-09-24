//! HTTP handlers for group settings management.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::State,
    http::StatusCode,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CommunityId, SelectedGroupId},
    },
    templates::dashboard::group::settings::{self, GroupUpdate},
};

// Pages handlers.

/// Displays the page to update group settings.
#[instrument(skip_all, err)]
pub(crate) async fn update_page(
    CommunityId(community_id): CommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (group, categories, regions) = tokio::try_join!(
        db.get_group_full(community_id, group_id),
        db.list_group_categories(community_id),
        db.list_regions(community_id)
    )?;
    let template = settings::UpdatePage {
        categories,
        group,
        regions,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Updates group settings in the database.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    CommunityId(community_id): CommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(serde_qs_de): State<serde_qs::Config>,
    body: String,
) -> Result<impl IntoResponse, HandlerError> {
    // Get group update information from body
    let group_update: GroupUpdate = match serde_qs_de.deserialize_str(&body).map_err(anyhow::Error::new) {
        Ok(update) => update,
        Err(e) => return Ok((StatusCode::UNPROCESSABLE_ENTITY, e.to_string()).into_response()),
    };

    // Update group in database
    db.update_group(community_id, group_id, &group_update).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    )
        .into_response())
}

// Tests.

#[cfg(test)]
mod tests {
    use std::collections::{BTreeMap, HashMap};

    use anyhow::anyhow;
    use axum::{
        body::{Body, to_bytes},
        http::{
            HeaderValue, Request, StatusCode,
            header::{CACHE_CONTROL, CONTENT_TYPE, COOKIE, HOST},
        },
    };
    use axum_login::tower_sessions::session;
    use chrono::{TimeZone, Utc};
    use serde_json::json;
    use time::{Duration as TimeDuration, OffsetDateTime};
    use tower::ServiceExt;
    use uuid::Uuid;

    use crate::{
        auth::User as AuthUser,
        db::mock::MockDB,
        handlers::auth::SELECTED_GROUP_ID_KEY,
        router::setup_test_router,
        services::notifications::MockNotificationsManager,
        templates::dashboard::group::settings::GroupUpdate,
        types::group::{GroupCategory, GroupFull, GroupRegion},
    };

    #[tokio::test]
    async fn test_update_page_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, group_id, &auth_hash);
        let group = sample_group_full(group_id);
        let category = sample_group_category();
        let region = sample_group_region();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_group_full()
            .withf(move |cid, gid| *cid == community_id && *gid == group_id)
            .returning(move |_, _| Ok(group.clone()));
        db.expect_list_group_categories()
            .withf(move |cid| *cid == community_id)
            .returning(move |_| Ok(vec![category.clone()]));
        db.expect_list_regions()
            .withf(move |cid| *cid == community_id)
            .returning(move |_| Ok(vec![region.clone()]));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/group/settings/update")
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
            &HeaderValue::from_static("max-age=0"),
        );
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_update_page_db_error() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, group_id, &auth_hash);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_group_full()
            .withf(move |cid, gid| *cid == community_id && *gid == group_id)
            .returning(move |_, _| Err(anyhow!("db error")));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/group/settings/update")
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
    async fn test_update_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, group_id, &auth_hash);
        let update = sample_group_update();
        let body = serde_qs::to_string(&update).unwrap();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_update_group()
            .withf(move |cid, gid, group| {
                *cid == community_id
                    && *gid == group_id
                    && group.name == update.name
                    && group.slug == update.slug
            })
            .returning(move |_, _, _| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("PUT")
            .uri("/dashboard/group/settings/update")
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

    #[tokio::test]
    async fn test_update_invalid_body() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, group_id, &auth_hash);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("PUT")
            .uri("/dashboard/group/settings/update")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(Body::from("invalid"))
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
        assert!(!bytes.is_empty());
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

    /// Helper to create a sample group category for tests.
    fn sample_group_category() -> GroupCategory {
        GroupCategory {
            group_category_id: Uuid::new_v4(),
            name: "Meetup".to_string(),
            normalized_name: "meetup".to_string(),
            order: Some(1),
        }
    }

    /// Helper to create a sample group full record for tests.
    fn sample_group_full(group_id: Uuid) -> GroupFull {
        GroupFull {
            active: true,
            category: sample_group_category(),
            color: "#123456".to_string(),
            created_at: Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap(),
            group_id,
            members_count: 42,
            name: "Test Group".to_string(),
            organizers: Vec::new(),
            slug: "test-group".to_string(),
            sponsors: Vec::new(),

            banner_url: Some("https://example.test/banner.png".to_string()),
            city: Some("Test City".to_string()),
            country_code: Some("US".to_string()),
            country_name: Some("United States".to_string()),
            description: Some("Test description".to_string()),
            description_short: Some("Short".to_string()),
            extra_links: Some(BTreeMap::new()),
            facebook_url: Some("https://facebook.com/test".to_string()),
            flickr_url: None,
            github_url: Some("https://github.com/test".to_string()),
            instagram_url: None,
            latitude: Some(42.0),
            linkedin_url: None,
            logo_url: Some("https://example.test/logo.png".to_string()),
            longitude: Some(-71.0),
            photos_urls: None,
            region: Some(sample_group_region()),
            slack_url: None,
            state: Some("MA".to_string()),
            tags: None,
            twitter_url: None,
            wechat_url: None,
            website_url: Some("https://example.test".to_string()),
            youtube_url: None,
        }
    }

    /// Helper to create a sample group region for tests.
    fn sample_group_region() -> GroupRegion {
        GroupRegion {
            name: "North America".to_string(),
            normalized_name: "north-america".to_string(),
            order: Some(1),
            region_id: Uuid::new_v4(),
        }
    }

    /// Helper to create a sample group update payload for tests.
    fn sample_group_update() -> GroupUpdate {
        let mut update = GroupUpdate::default();
        update.name = "Updated Group".to_string();
        update.slug = "updated-group".to_string();
        update.category_id = Uuid::new_v4();
        update.description = "Updated description".to_string();
        update.banner_url = Some("https://example.test/banner.png".to_string());
        update.city = Some("Test City".to_string());
        update.country_code = Some("US".to_string());
        update.country_name = Some("United States".to_string());
        update.extra_links = Some(BTreeMap::new());
        update.facebook_url = Some("https://facebook.com/test".to_string());
        update.github_url = Some("https://github.com/test".to_string());
        update.linkedin_url = Some("https://linkedin.com/company/test".to_string());
        update.logo_url = Some("https://example.test/logo.png".to_string());
        update.region_id = Some(Uuid::new_v4());
        update.state = Some("MA".to_string());
        update.website_url = Some("https://example.test".to_string());
        update
    }

    /// Helper to create a sample session record with selected group ID.
    fn sample_session_record(
        session_id: session::Id,
        user_id: Uuid,
        group_id: Uuid,
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
        data.insert(SELECTED_GROUP_ID_KEY.to_string(), json!(group_id));
        session::Record {
            data,
            expiry_date: OffsetDateTime::now_utc().saturating_add(TimeDuration::days(1)),
            id: session_id,
        }
    }
}
