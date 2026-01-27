//! HTTP handlers for the community dashboard.

use std::collections::HashMap;

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Query, RawQuery, State},
    response::{Html, IntoResponse},
};
use axum_messages::Messages;
use tracing::instrument;

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::{error::HandlerError, extractors::SelectedCommunityId},
    router::serde_qs_config,
    templates::{
        PageId,
        auth::User,
        dashboard::community::{
            analytics,
            groups::{self, CommunityGroupsFilters},
            home::{Content, Page, Tab},
            settings,
            team::{self, CommunityTeamFilters},
        },
        pagination::NavigationLinks,
        site::explore::GroupsFilters,
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
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Get selected tab from query
    let tab: Tab = query.get("tab").unwrap_or(&String::new()).parse().unwrap_or_default();

    // Get user_id from session
    let user_id = auth_session.user.as_ref().expect("user to be logged in").user_id;

    // Get selected community, user communities and site settings
    let (community, communities, site_settings) = tokio::try_join!(
        db.get_community_full(community_id),
        db.list_user_communities(&user_id),
        db.get_site_settings()
    )?;

    // Prepare content for the selected tab
    let content = match tab {
        Tab::Analytics => {
            let stats = db.get_community_stats(community_id).await?;
            Content::Analytics(Box::new(analytics::Page { stats }))
        }
        Tab::Groups => {
            let mut page_filters: CommunityGroupsFilters =
                serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
            page_filters = page_filters.with_defaults();
            let db_filters = GroupsFilters {
                community: vec![community.name.clone()],
                include_inactive: Some(true),
                limit: page_filters.limit,
                offset: page_filters.offset,
                sort_by: Some("name".to_string()),
                ts_query: page_filters.ts_query.clone(),
                ..GroupsFilters::default()
            };
            let results = db.search_groups(&db_filters).await?;
            let navigation_links = NavigationLinks::from_filters(
                &page_filters,
                results.total,
                "/dashboard/community?tab=groups",
                "/dashboard/community/groups",
            )?;
            Content::Groups(groups::ListPage {
                groups: results.groups,
                navigation_links,
                total: results.total,
                ts_query: page_filters.ts_query,
            })
        }
        Tab::Settings => Content::Settings(Box::new(settings::UpdatePage {
            community: community.clone(),
        })),
        Tab::Team => {
            let mut page_filters: CommunityTeamFilters =
                serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
            page_filters = page_filters.with_defaults();
            let results = db.list_community_team_members(community_id, &page_filters).await?;
            let navigation_links = NavigationLinks::from_filters(
                &page_filters,
                results.total,
                "/dashboard/community?tab=team",
                "/dashboard/community/team",
            )?;
            Content::Team(team::ListPage {
                approved_members_count: results.approved_total,
                members: results.members,
                navigation_links,
                total: results.total,
            })
        }
    };

    // Render the page
    let page = Page {
        communities,
        content,
        messages: messages.into_iter().collect(),
        page_id: PageId::CommunityDashboard,
        path: "/dashboard/community".to_string(),
        selected_community_id: community_id,
        site_settings,
        user: User::from_session(auth_session).await?,
    };

    let html = Html(page.render()?);
    Ok(html)
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
        db::{common::SearchGroupsOutput, mock::MockDB},
        handlers::tests::*,
        router::CACHE_CONTROL_NO_CACHE,
        services::notifications::MockNotificationsManager,
        templates::dashboard::DASHBOARD_PAGINATION_LIMIT,
    };

    #[tokio::test]
    async fn test_page_analytics_tab_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);
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
        db.expect_get_community_full()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community_full(community_id)));
        db.expect_list_user_communities()
            .times(1)
            .withf(move |uid| uid == &user_id)
            .returning(move |_| Ok(sample_user_communities(community_id)));
        db.expect_get_community_stats()
            .times(1)
            .withf(move |cid| *cid == community_id)
            .returning(move |_| Ok(stats.clone()));
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/community?tab=analytics")
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
    async fn test_page_groups_tab_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);
        let ts_query = "rust".to_string();
        let groups_output = SearchGroupsOutput {
            total: 0,
            bbox: None,
            ..sample_search_groups_output(group_id)
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
        db.expect_get_community_full()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community_full(community_id)));
        db.expect_list_user_communities()
            .times(1)
            .withf(move |uid| uid == &user_id)
            .returning(move |_| Ok(sample_user_communities(community_id)));
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));
        db.expect_search_groups()
            .times(1)
            .withf({
                let ts_query = ts_query.clone();
                move |filters| {
                    filters.community == vec!["test".to_string()]
                        && filters.include_inactive == Some(true)
                        && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                        && filters.sort_by.as_deref() == Some("name")
                        && filters.ts_query.as_deref() == Some(ts_query.as_str())
                }
            })
            .returning(move |_| Ok(groups_output.clone()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
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
            &HeaderValue::from_static(CACHE_CONTROL_NO_CACHE),
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
        db.expect_user_owns_community()
            .times(1)
            .withf(move |cid, uid| *cid == community_id && *uid == user_id)
            .returning(|_, _| Ok(true));
        db.expect_get_community_full()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community_full(community_id)));
        db.expect_list_user_communities()
            .times(1)
            .withf(move |uid| uid == &user_id)
            .returning(move |_| Ok(sample_user_communities(community_id)));
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
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
            &HeaderValue::from_static(CACHE_CONTROL_NO_CACHE),
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
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);
        let members = vec![
            sample_community_team_member(true),
            sample_community_team_member(false),
        ];
        let output = crate::templates::dashboard::community::team::CommunityTeamOutput {
            approved_total: 1,
            members: members.clone(),
            total: members.len(),
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
        db.expect_get_community_full()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community_full(community_id)));
        db.expect_list_user_communities()
            .times(1)
            .withf(move |uid| uid == &user_id)
            .returning(move |_| Ok(sample_user_communities(community_id)));
        db.expect_list_community_team_members()
            .times(1)
            .withf(move |id, filters| {
                *id == community_id
                    && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                    && filters.offset == Some(0)
            })
            .returning(move |_, _| Ok(output.clone()));
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
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
            &HeaderValue::from_static(CACHE_CONTROL_NO_CACHE),
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
        db.expect_user_owns_community()
            .times(1)
            .withf(move |cid, uid| *cid == community_id && *uid == user_id)
            .returning(|_, _| Ok(true));
        db.expect_get_community_full()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(move |_| Err(anyhow!("db error")));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
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
}
