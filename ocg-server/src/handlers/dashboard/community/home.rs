//! HTTP handlers for the community dashboard.

use std::collections::HashMap;

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Query, State},
    response::{Html, IntoResponse},
};
use axum_messages::Messages;
use tracing::instrument;

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::{
        dashboard::community::groups::MAX_GROUPS_LISTED, error::HandlerError, extractors::CommunityId,
    },
    templates::{
        PageId,
        auth::User,
        community::explore::GroupsFilters,
        dashboard::community::{
            groups,
            home::{Content, Page, Tab},
            settings, team,
        },
    },
};

/// Handler that returns the community dashboard home page.
///
/// This handler manages the main community dashboard page, selecting the appropriate tab
/// and preparing the content for each dashboard section.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    auth_session: AuthSession,
    messages: Messages,
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get selected tab from query
    let tab: Tab = query.get("tab").unwrap_or(&String::new()).parse().unwrap_or_default();

    // Get community information
    let community = db.get_community(community_id).await?;

    // Prepare content for the selected tab
    let content = match tab {
        Tab::Groups => {
            let ts_query = query.get("ts_query").cloned();
            let filters = GroupsFilters {
                limit: Some(MAX_GROUPS_LISTED),
                sort_by: Some("name".to_string()),
                ts_query: ts_query.clone(),
                ..GroupsFilters::default()
            };
            let groups = db.search_community_groups(community_id, &filters).await?.groups;
            Content::Groups(groups::ListPage { groups, ts_query })
        }
        Tab::Settings => Content::Settings(Box::new(settings::UpdatePage {
            community: community.clone(),
        })),
        Tab::Team => {
            let members = db.list_community_team_members(community_id).await?;
            let approved_members_count = members.iter().filter(|m| m.accepted).count();
            Content::Team(team::ListPage {
                approved_members_count,
                members,
            })
        }
    };

    // Render the page
    let page = Page {
        community,
        content,
        messages: messages.into_iter().collect(),
        page_id: PageId::CommunityDashboard,
        path: "/dashboard/community".to_string(),
        user: User::from_session(auth_session).await?,
    };

    let html = Html(page.render()?);
    Ok(html)
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
        db::{common::SearchCommunityGroupsOutput, mock::MockDB},
        handlers::dashboard::community::groups::MAX_GROUPS_LISTED,
        router::setup_test_router,
        services::notifications::MockNotificationsManager,
        templates::dashboard::community::team::CommunityTeamMember,
        types::{
            community::{Community, Theme},
            group::{GroupCategory, GroupDetailed, GroupRegion},
        },
    };

    #[tokio::test]
    async fn test_page_groups_tab_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash);
        let ts_query = "rust".to_string();
        let groups_output = SearchCommunityGroupsOutput {
            groups: vec![sample_group_detailed(group_id)],
            ..Default::default()
        };

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
        db.expect_get_community()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community(community_id)));
        db.expect_search_community_groups()
            .times(1)
            .withf({
                let ts_query = ts_query.clone();
                move |id, filters| {
                    *id == community_id
                        && filters.limit == Some(MAX_GROUPS_LISTED)
                        && filters.sort_by.as_deref() == Some("name")
                        && filters.ts_query.as_deref() == Some(ts_query.as_str())
                }
            })
            .returning(move |_, _| Ok(groups_output.clone()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/community?tab=groups&ts_query=rust")
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
    async fn test_page_settings_tab_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
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
        db.expect_user_owns_community()
            .times(1)
            .withf(move |cid, uid| *cid == community_id && *uid == user_id)
            .returning(|_, _| Ok(true));
        db.expect_get_community_id()
            .times(2)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community(community_id)));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/community?tab=settings")
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
    async fn test_page_team_tab_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash);
        let members = vec![sample_team_member(true), sample_team_member(false)];

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
        db.expect_get_community()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community(community_id)));
        db.expect_list_community_team_members()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(members.clone()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/community?tab=team")
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
    async fn test_page_db_error() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
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
        let auth_hash_for_user = auth_hash.clone();
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash_for_user))));
        db.expect_user_owns_community()
            .times(1)
            .withf(move |cid, uid| *cid == community_id && *uid == user_id)
            .returning(|_, _| Ok(true));
        db.expect_get_community_id()
            .times(2)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(move |_| Err(anyhow!("db error")));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/community")
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

            has_password: Some(true),
            ..Default::default()
        }
    }

    /// Helper to create a sample community for tests.
    fn sample_community(community_id: Uuid) -> Community {
        Community {
            active: true,
            community_id,
            community_site_layout_id: "default".to_string(),
            created_at: 0,
            description: "Test community".to_string(),
            display_name: "Test".to_string(),
            header_logo_url: "/static/images/placeholder_cncf.png".to_string(),
            host: "example.test".to_string(),
            name: "test".to_string(),
            theme: Theme {
                palette: BTreeMap::new(),
                primary_color: "#000000".to_string(),
            },
            title: "Test Community".to_string(),
            ..Default::default()
        }
    }

    /// Helper to create a sample detailed group for tests.
    fn sample_group_detailed(group_id: Uuid) -> GroupDetailed {
        GroupDetailed {
            active: true,
            category: GroupCategory {
                group_category_id: Uuid::new_v4(),
                name: "Meetup".to_string(),
                normalized_name: "meetup".to_string(),

                order: Some(1),
            },
            color: "#123456".to_string(),
            created_at: Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap(),
            group_id,
            name: "Test Group".to_string(),
            slug: "test-group".to_string(),

            city: Some("Test City".to_string()),
            country_code: Some("US".to_string()),
            country_name: Some("United States".to_string()),
            description_short: Some("Test group".to_string()),
            latitude: Some(42.0),
            logo_url: Some("https://example.test/logo.png".to_string()),
            longitude: Some(-71.0),
            popover_html: Some("<p>Test</p>".to_string()),
            region: Some(GroupRegion {
                name: "North America".to_string(),
                normalized_name: "north-america".to_string(),

                order: Some(1),
                region_id: Uuid::new_v4(),
            }),
            state: Some("MA".to_string()),
        }
    }

    /// Helper to create a sample community team member for tests.
    fn sample_team_member(accepted: bool) -> CommunityTeamMember {
        CommunityTeamMember {
            accepted,
            user_id: Uuid::new_v4(),
            username: "team-member".to_string(),

            company: Some("Test Company".to_string()),
            name: Some("Team Member".to_string()),
            photo_url: Some("https://example.test/photo.png".to_string()),
            title: Some("Organizer".to_string()),
        }
    }

    /// Helper to create a sample session record for tests.
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
