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
        extractors::{CommunityId, SelectedGroupId},
    },
    templates::{
        PageId,
        auth::User,
        dashboard::group::{
            attendees, events,
            home::{Content, Page, Tab},
            members, settings, sponsors, team,
        },
    },
};

/// Handler that returns the group dashboard home page.
///
/// This handler manages the main group dashboard page, selecting the appropriate tab
/// and preparing the content for each dashboard section.
#[allow(clippy::too_many_arguments)]
#[instrument(skip_all, err)]
pub(crate) async fn page(
    auth_session: AuthSession,
    messages: Messages,
    CommunityId(community_id): CommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(serde_qs_de): State<serde_qs::Config>,
    Query(query): Query<HashMap<String, String>>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.as_ref().expect("user to be logged in").clone();

    // Get selected tab from query
    let tab: Tab = query.get("tab").unwrap_or(&String::new()).parse().unwrap_or_default();

    // Get community and user groups information
    let (community, groups) =
        tokio::try_join!(db.get_community(community_id), db.list_user_groups(&user.user_id))?;

    // Prepare content for the selected tab
    let content = match tab {
        Tab::Attendees => {
            let filters: attendees::AttendeesFilters = serde_qs_de
                .deserialize_str(&raw_query.unwrap_or_default())
                .map_err(anyhow::Error::new)?;
            let attendees = db.search_event_attendees(group_id, &filters).await?;
            let event = if let Some(event_id) = filters.event_id {
                Some(db.get_event_summary(community_id, group_id, event_id).await?)
            } else {
                None
            };
            Content::Attendees(Box::new(attendees::ListPage {
                attendees,
                group_id,
                event,
            }))
        }
        Tab::Events => {
            let events = db.list_group_events(group_id).await?;
            Content::Events(events::ListPage { events })
        }
        Tab::Members => {
            let members = db.list_group_members(group_id).await?;
            Content::Members(members::ListPage { members })
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
            let sponsors = db.list_group_sponsors(group_id).await?;
            Content::Sponsors(sponsors::ListPage { sponsors })
        }
        Tab::Team => {
            let (members, roles) =
                tokio::try_join!(db.list_group_team_members(group_id), db.list_group_roles())?;
            let approved_members_count = members.iter().filter(|m| m.accepted).count();
            Content::Team(team::ListPage {
                approved_members_count,
                members,
                roles,
            })
        }
    };

    // Render the page
    let page = Page {
        community,
        content,
        groups,
        messages: messages.into_iter().collect(),
        page_id: PageId::GroupDashboard,
        path: "/dashboard/group".to_string(),
        selected_group_id: group_id,
        user: User::from_session(auth_session).await?,
    };

    let html = Html(page.render()?);
    Ok(html)
}

// Tests.

#[cfg(test)]
mod tests {
    use std::collections::{BTreeMap, HashMap};

    use axum::{
        body::{Body, to_bytes},
        http::{
            HeaderValue, Request, StatusCode,
            header::{CACHE_CONTROL, CONTENT_TYPE, COOKIE, HOST},
        },
    };
    use axum_login::tower_sessions::session;
    use chrono::{TimeZone, Utc};
    use chrono_tz::UTC;
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
        templates::dashboard::group::{
            attendees::Attendee, events::GroupEvents, members::GroupMember, team::GroupTeamMember,
        },
        types::{
            community::{Community, Theme},
            event::{EventKind, EventSummary},
            group::{
                GroupCategory, GroupFull, GroupRegion, GroupRole, GroupRoleSummary, GroupSponsor,
                GroupSummary,
            },
        },
    };

    #[tokio::test]
    async fn test_page_attendees_tab_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, group_id, &auth_hash);
        let community = sample_community(community_id);
        let groups = vec![sample_group_summary(group_id)];
        let attendees = vec![sample_attendee()];
        let event_summary = sample_event_summary(event_id, group_id);

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
        db.expect_get_community()
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(community.clone()));
        db.expect_list_user_groups()
            .withf(move |uid| uid == &user_id)
            .returning(move |_| Ok(groups.clone()));
        db.expect_search_event_attendees()
            .withf(move |id, filters| *id == group_id && filters.event_id == Some(event_id))
            .returning(move |_, _| Ok(attendees.clone()));
        db.expect_get_event_summary()
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(event_summary.clone()));
        db.expect_list_group_events()
            .withf(move |id| *id == group_id)
            .returning(move |_| Ok(sample_group_events(event_id, group_id)));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri(format!("/dashboard/group?tab=attendees&event_id={event_id}"))
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
    async fn test_page_events_tab_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, group_id, &auth_hash);
        let community = sample_community(community_id);
        let groups = vec![sample_group_summary(group_id)];
        let group_events = sample_group_events(event_id, group_id);

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
        db.expect_get_community()
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(community.clone()));
        db.expect_list_user_groups()
            .withf(move |uid| uid == &user_id)
            .returning(move |_| Ok(groups.clone()));
        db.expect_list_group_events()
            .withf(move |id| *id == group_id)
            .returning(move |_| Ok(group_events.clone()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/group?tab=events")
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
    async fn test_page_members_tab_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, group_id, &auth_hash);
        let community = sample_community(community_id);
        let groups = vec![sample_group_summary(group_id)];
        let member = sample_group_member();

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
        db.expect_get_community()
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(community.clone()));
        db.expect_list_user_groups()
            .withf(move |uid| uid == &user_id)
            .returning(move |_| Ok(groups.clone()));
        db.expect_list_group_members()
            .withf(move |id| *id == group_id)
            .returning({
                let member = member.clone();
                move |_| Ok(vec![member.clone()])
            });

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/group?tab=members")
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
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, group_id, &auth_hash);
        let community = sample_community(community_id);
        let groups = vec![sample_group_summary(group_id)];
        let group_full = sample_group_full(group_id);
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
        db.expect_get_community()
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(community.clone()));
        db.expect_list_user_groups()
            .withf(move |uid| uid == &user_id)
            .returning(move |_| Ok(groups.clone()));
        db.expect_get_group_full()
            .withf(move |cid, gid| *cid == community_id && *gid == group_id)
            .returning(move |_, _| Ok(group_full.clone()));
        db.expect_list_group_categories()
            .withf(move |cid| *cid == community_id)
            .returning({
                let category = category.clone();
                move |_| Ok(vec![category.clone()])
            });
        db.expect_list_regions()
            .withf(move |cid| *cid == community_id)
            .returning({
                let region = region.clone();
                move |_| Ok(vec![region.clone()])
            });

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/group?tab=settings")
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
    async fn test_page_sponsors_tab_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, group_id, &auth_hash);
        let community = sample_community(community_id);
        let groups = vec![sample_group_summary(group_id)];
        let sponsor = sample_group_sponsor();

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
        db.expect_get_community()
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(community.clone()));
        db.expect_list_user_groups()
            .withf(move |uid| uid == &user_id)
            .returning(move |_| Ok(groups.clone()));
        db.expect_list_group_sponsors()
            .withf(move |id| *id == group_id)
            .returning({
                let sponsor = sponsor.clone();
                move |_| Ok(vec![sponsor.clone()])
            });

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/group?tab=sponsors")
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
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, group_id, &auth_hash);
        let community = sample_community(community_id);
        let groups = vec![sample_group_summary(group_id)];
        let team_member = sample_team_member(true);
        let role = sample_group_role_summary();

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
        db.expect_get_community()
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(community.clone()));
        db.expect_list_user_groups()
            .withf(move |uid| uid == &user_id)
            .returning(move |_| Ok(groups.clone()));
        db.expect_list_group_team_members()
            .withf(move |id| *id == group_id)
            .returning({
                let team_member = team_member.clone();
                move |_| Ok(vec![team_member.clone(), sample_team_member(false)])
            });
        db.expect_list_group_roles().returning({
            let role = role.clone();
            move || Ok(vec![role.clone()])
        });

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/group?tab=team")
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

    // Helpers.

    /// Helper to create a sample attendee for tests.
    fn sample_attendee() -> Attendee {
        Attendee {
            checked_in: true,
            created_at: Utc.with_ymd_and_hms(2024, 1, 1, 12, 0, 0).unwrap(),
            username: "attendee".to_string(),

            company: Some("Example".to_string()),
            name: Some("Event Attendee".to_string()),
            photo_url: Some("https://example.test/avatar.png".to_string()),
            title: Some("Engineer".to_string()),
        }
    }

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
                palette: BTreeMap::default(),
                primary_color: "#000000".to_string(),
            },
            title: "Test Community".to_string(),
            ..Default::default()
        }
    }

    /// Helper to create a sample event summary for tests.
    fn sample_event_summary(event_id: Uuid, _group_id: Uuid) -> EventSummary {
        EventSummary {
            canceled: false,
            event_id,
            group_category_name: "Meetup".to_string(),
            group_color: "#123456".to_string(),
            group_name: "Test Group".to_string(),
            group_slug: "test-group".to_string(),
            kind: EventKind::Virtual,
            name: "Sample Event".to_string(),
            published: true,
            slug: "sample-event".to_string(),
            timezone: UTC,

            group_city: Some("Test City".to_string()),
            group_country_code: Some("US".to_string()),
            group_country_name: Some("United States".to_string()),
            group_state: Some("MA".to_string()),
            logo_url: Some("https://example.test/logo.png".to_string()),
            starts_at: Some(Utc.with_ymd_and_hms(2024, 2, 1, 18, 0, 0).unwrap()),
            venue_city: Some("Boston".to_string()),
        }
    }

    /// Helper to create sample group events for tests.
    fn sample_group_events(event_id: Uuid, group_id: Uuid) -> GroupEvents {
        let summary = sample_event_summary(event_id, group_id);
        GroupEvents {
            past: vec![summary.clone()],
            upcoming: vec![summary],
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
            facebook_url: None,
            flickr_url: None,
            github_url: None,
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

    /// Helper to create a sample group member for tests.
    fn sample_group_member() -> GroupMember {
        GroupMember {
            created_at: Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap(),
            username: "member".to_string(),

            company: Some("Example".to_string()),
            name: Some("Group Member".to_string()),
            photo_url: Some("https://example.test/photo.png".to_string()),
            title: Some("Engineer".to_string()),
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

    /// Helper to create a sample group role summary for tests.
    fn sample_group_role_summary() -> GroupRoleSummary {
        GroupRoleSummary {
            display_name: "Organizer".to_string(),
            group_role_id: "organizer".to_string(),
        }
    }

    /// Helper to create a sample group sponsor for tests.
    fn sample_group_sponsor() -> GroupSponsor {
        GroupSponsor {
            group_sponsor_id: Uuid::new_v4(),
            logo_url: "https://example.test/logo.png".to_string(),
            name: "Sponsor".to_string(),

            website_url: Some("https://example.test".to_string()),
        }
    }

    /// Helper to create a sample group summary for tests.
    fn sample_group_summary(group_id: Uuid) -> GroupSummary {
        GroupSummary {
            active: true,
            category: sample_group_category(),
            color: "#123456".to_string(),
            created_at: Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap(),
            group_id,
            name: "Test Group".to_string(),
            slug: "test-group".to_string(),

            city: Some("Test City".to_string()),
            country_code: Some("US".to_string()),
            country_name: Some("United States".to_string()),
            logo_url: Some("https://example.test/logo.png".to_string()),
            region: Some(sample_group_region()),
            state: Some("MA".to_string()),
        }
    }

    /// Helper to create a sample team member for tests.
    fn sample_team_member(accepted: bool) -> GroupTeamMember {
        GroupTeamMember {
            accepted,
            user_id: Uuid::new_v4(),
            username: "team-member".to_string(),

            company: Some("Example".to_string()),
            name: Some("Team Member".to_string()),
            photo_url: Some("https://example.test/photo.png".to_string()),
            role: Some(GroupRole::Organizer),
            title: Some("Organizer".to_string()),
        }
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
