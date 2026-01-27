//! HTTP handlers for the group dashboard home page.

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
    handlers::{
        error::HandlerError,
        extractors::{SelectedCommunityId, SelectedGroupId},
    },
    router::serde_qs_config,
    templates::{
        PageId,
        auth::User,
        dashboard::group::{
            analytics,
            events::{
                self, EventsListFilters, EventsTab, PastEventsPaginationFilters,
                UpcomingEventsPaginationFilters,
            },
            home::{Content, Page, Tab},
            members::{self, GroupMembersFilters},
            settings,
            sponsors::{self, GroupSponsorsFilters},
            team::{self, GroupTeamFilters},
        },
        pagination::NavigationLinks,
    },
};

/// Handler that returns the group dashboard home page.
///
/// This handler manages the main group dashboard page, selecting the appropriate tab
/// and preparing the content for each dashboard section.
#[instrument(skip_all, err)]
#[allow(clippy::too_many_lines)]
pub(crate) async fn page(
    auth_session: AuthSession,
    messages: Messages,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.as_ref().expect("user to be logged in").clone();

    // Get selected tab from query
    let tab: Tab = query.get("tab").unwrap_or(&String::new()).parse().unwrap_or_default();

    // Get site settings and user groups information
    let (groups_by_community, site_settings) =
        tokio::try_join!(db.list_user_groups(&user.user_id), db.get_site_settings())?;

    // Prepare content for the selected tab
    let content = match tab {
        Tab::Analytics => {
            let stats = db.get_group_stats(community_id, group_id).await?;
            Content::Analytics(Box::new(analytics::Page { stats }))
        }
        Tab::Events => {
            let mut filters: EventsListFilters =
                serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
            filters = filters.with_defaults();
            let events = db.list_group_events(group_id, &filters).await?;
            let past_filters = PastEventsPaginationFilters {
                events_tab: Some(EventsTab::Past),
                limit: filters.limit,
                past_offset: filters.past_offset,
                upcoming_offset: filters.upcoming_offset,
            }
            .with_defaults();
            let upcoming_filters = UpcomingEventsPaginationFilters {
                events_tab: Some(EventsTab::Upcoming),
                limit: filters.limit,
                past_offset: filters.past_offset,
                upcoming_offset: filters.upcoming_offset,
            }
            .with_defaults();
            let past_navigation_links = NavigationLinks::from_filters(
                &past_filters,
                events.past.total,
                "/dashboard/group?tab=events",
                "/dashboard/group/events",
            )?;
            let upcoming_navigation_links = NavigationLinks::from_filters(
                &upcoming_filters,
                events.upcoming.total,
                "/dashboard/group?tab=events",
                "/dashboard/group/events",
            )?;
            Content::Events(Box::new(events::ListPage {
                events,
                events_tab: filters.current_tab(),
                past_navigation_links,
                upcoming_navigation_links,
            }))
        }
        Tab::Members => {
            let mut filters: GroupMembersFilters =
                serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
            filters = filters.with_defaults();
            let results = db.list_group_members(group_id, &filters).await?;
            let navigation_links = NavigationLinks::from_filters(
                &filters,
                results.total,
                "/dashboard/group?tab=members",
                "/dashboard/group/members",
            )?;
            Content::Members(members::ListPage {
                members: results.members,
                navigation_links,
                total: results.total,
            })
        }
        Tab::Settings => {
            let (group, categories, regions) = tokio::try_join!(
                db.get_group_full(community_id, group_id),
                db.list_group_categories(community_id),
                db.list_regions(community_id)
            )?;
            Content::Settings(Box::new(settings::UpdatePage {
                categories,
                group,
                regions,
            }))
        }
        Tab::Sponsors => {
            let mut filters: GroupSponsorsFilters =
                serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
            filters = filters.with_defaults();
            let results = db.list_group_sponsors(group_id, &filters).await?;
            let navigation_links = NavigationLinks::from_filters(
                &filters,
                results.total,
                "/dashboard/group?tab=sponsors",
                "/dashboard/group/sponsors",
            )?;
            Content::Sponsors(sponsors::ListPage {
                navigation_links,
                sponsors: results.sponsors,
                total: results.total,
            })
        }
        Tab::Team => {
            let mut filters: GroupTeamFilters =
                serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
            filters = filters.with_defaults();
            let (results, roles) = tokio::try_join!(
                db.list_group_team_members(group_id, &filters),
                db.list_group_roles()
            )?;
            let navigation_links = NavigationLinks::from_filters(
                &filters,
                results.total,
                "/dashboard/group?tab=team",
                "/dashboard/group/team",
            )?;
            Content::Team(team::ListPage {
                approved_members_count: results.approved_total,
                members: results.members,
                navigation_links,
                roles,
                total: results.total,
            })
        }
    };

    // Render the page
    let page = Page {
        content,
        groups_by_community,
        messages: messages.into_iter().collect(),
        page_id: PageId::GroupDashboard,
        path: "/dashboard/group".to_string(),
        selected_community_id: community_id,
        selected_group_id: group_id,
        site_settings,
        user: User::from_session(auth_session).await?,
    };

    let html = Html(page.render()?);
    Ok(html)
}

// Tests.

#[cfg(test)]
mod tests {
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
        db::mock::MockDB, handlers::tests::*, router::CACHE_CONTROL_NO_CACHE,
        services::notifications::MockNotificationsManager, templates::pagination::DASHBOARD_PAGINATION_LIMIT,
    };

    #[tokio::test]
    async fn test_page_analytics_tab_success() {
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
        let groups = sample_user_groups_by_community(community_id, group_id);
        let stats = sample_group_stats();

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
        db.expect_list_user_groups()
            .times(1)
            .withf(move |uid| uid == &user_id)
            .returning(move |_| Ok(groups.clone()));
        db.expect_get_group_stats()
            .times(1)
            .withf(move |cid, gid| *cid == community_id && *gid == group_id)
            .returning(move |_, _| Ok(stats.clone()));
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/group?tab=analytics")
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
    async fn test_page_events_tab_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
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
        let groups = sample_user_groups_by_community(community_id, group_id);
        let group_events = sample_group_events(event_id, group_id);

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
        db.expect_list_user_groups()
            .times(1)
            .withf(move |uid| uid == &user_id)
            .returning(move |_| Ok(groups.clone()));
        db.expect_list_group_events()
            .times(1)
            .withf(move |id, filters| {
                *id == group_id
                    && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                    && filters.past_offset == Some(0)
                    && filters.upcoming_offset == Some(0)
            })
            .returning(move |_, _| Ok(group_events.clone()));
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/group?tab=events")
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
    async fn test_page_members_tab_success() {
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
        let groups = sample_user_groups_by_community(community_id, group_id);
        let member = sample_group_member();
        let output = crate::templates::dashboard::group::members::GroupMembersOutput {
            members: vec![member.clone()],
            total: 1,
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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));
        db.expect_list_user_groups()
            .times(1)
            .withf(move |uid| uid == &user_id)
            .returning(move |_| Ok(groups.clone()));
        db.expect_list_group_members()
            .times(1)
            .withf(move |id, filters| {
                *id == group_id
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
            .uri("/dashboard/group?tab=members")
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
        let groups = sample_user_groups_by_community(community_id, group_id);
        let group_full = sample_group_full(community_id, group_id);
        let category = sample_group_category();
        let region = sample_group_region();

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
        db.expect_list_user_groups()
            .times(1)
            .withf(move |uid| uid == &user_id)
            .returning(move |_| Ok(groups.clone()));
        db.expect_get_group_full()
            .times(1)
            .withf(move |cid, gid| *cid == community_id && *gid == group_id)
            .returning(move |_, _| Ok(group_full.clone()));
        db.expect_list_group_categories()
            .times(1)
            .withf(move |cid| *cid == community_id)
            .returning(move |_| Ok(vec![category.clone()]));
        db.expect_list_regions()
            .times(1)
            .withf(move |cid| *cid == community_id)
            .returning(move |_| Ok(vec![region.clone()]));
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/group?tab=settings")
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
    async fn test_page_sponsors_tab_success() {
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
        let groups = sample_user_groups_by_community(community_id, group_id);
        let sponsor = sample_group_sponsor();
        let output = crate::templates::dashboard::group::sponsors::GroupSponsorsOutput {
            sponsors: vec![sponsor.clone()],
            total: 1,
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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));
        db.expect_list_user_groups()
            .times(1)
            .withf(move |uid| uid == &user_id)
            .returning(move |_| Ok(groups.clone()));
        db.expect_list_group_sponsors()
            .times(1)
            .withf(move |id, filters| {
                *id == group_id
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
            .uri("/dashboard/group?tab=sponsors")
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
        let groups = sample_user_groups_by_community(community_id, group_id);
        let team_member = sample_team_member(true);
        let role = sample_group_role_summary();
        let members = vec![team_member.clone(), sample_team_member(false)];
        let output = crate::templates::dashboard::group::team::GroupTeamOutput {
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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));
        db.expect_list_user_groups()
            .times(1)
            .withf(move |uid| uid == &user_id)
            .returning(move |_| Ok(groups.clone()));
        db.expect_list_group_team_members()
            .times(1)
            .withf(move |id, filters| {
                *id == group_id
                    && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                    && filters.offset == Some(0)
            })
            .returning(move |_, _| Ok(output.clone()));
        db.expect_list_group_roles()
            .times(1)
            .returning(move || Ok(vec![role.clone()]));
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/group?tab=team")
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
}
