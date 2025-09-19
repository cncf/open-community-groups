//! HTTP handlers for the community explore page.
//!
//! The explore page provides a searchable interface for discovering groups and events
//! within a community.

use std::collections::HashMap;

use anyhow::Result;
use askama::Template;
use axum::{
    Json,
    extract::{Query, RawQuery, State},
    http::{HeaderMap, Uri},
    response::{Html, IntoResponse},
};
use chrono::Duration;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::{
        DynDB,
        common::{SearchCommunityEventsOutput, SearchCommunityGroupsOutput},
    },
    handlers::{error::HandlerError, extractors::CommunityId, prepare_headers},
    templates::{
        PageId,
        auth::User,
        community::{
            explore::{
                self, Entity, EventsFilters, GroupsFilters, render_event_popover, render_group_popover,
            },
            pagination::{self, NavigationLinks},
        },
    },
};

// Pages and sections handlers.

/// Handler that renders the community explore page with either events or groups section.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Query(query): Query<HashMap<String, String>>,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let community = db.get_community(community_id).await?;
    let entity: explore::Entity = query.get("entity").into();
    let mut template = explore::Page {
        community,
        entity: entity.clone(),
        page_id: PageId::CommunityExplore,
        path: uri.path().to_string(),
        user: User::default(),
        events_section: None,
        groups_section: None,
    };

    // Attach events or groups section template to the page template
    match entity {
        explore::Entity::Events => {
            let filters = EventsFilters::new(&headers, &raw_query.unwrap_or_default())?;
            let events_section = prepare_events_section(&db, community_id, &filters).await?;
            template.events_section = Some(events_section);
        }
        explore::Entity::Groups => {
            let filters = GroupsFilters::new(&headers, &raw_query.unwrap_or_default())?;
            let groups_section = prepare_groups_section(&db, community_id, &filters).await?;
            template.groups_section = Some(groups_section);
        }
    }

    // Prepare response headers
    let headers = prepare_headers(Duration::minutes(10), &[])?;

    Ok((headers, Html(template.render()?)))
}

/// Handler that renders the events section of the explore page.
#[instrument(skip_all, err)]
pub(crate) async fn events_section(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare events section template
    let filters = EventsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    let template = prepare_events_section(&db, community_id, &filters).await?;

    // Prepare response headers
    let url = pagination::build_url("/explore?entity=events", &filters)?;
    let extra_headers = [("HX-Push-Url", url.as_str())];
    let headers = prepare_headers(Duration::minutes(10), &extra_headers)?;

    Ok((headers, Html(template.render()?)))
}

/// Handler that renders the events results section of the explore page.
#[instrument(skip_all, err)]
pub(crate) async fn events_results_section(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare events results section template
    let filters = EventsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    let template = prepare_events_result_section(&db, community_id, &filters).await?;

    // Prepare response headers
    let url = pagination::build_url("/explore?entity=events", &filters)?;
    let extra_headers = [("HX-Push-Url", url.as_str())];
    let headers = prepare_headers(Duration::minutes(10), &extra_headers)?;

    Ok((headers, Html(template.render()?)))
}

/// Prepares the events section template.
#[instrument(skip(db), err)]
async fn prepare_events_section(
    db: &DynDB,
    community_id: Uuid,
    filters: &EventsFilters,
) -> Result<explore::EventsSection> {
    // Prepare template
    let (filters_options, results_section) = tokio::try_join!(
        db.get_community_filters_options(community_id),
        prepare_events_result_section(db, community_id, filters)
    )?;
    let template = explore::EventsSection {
        filters: filters.clone(),
        filters_options,
        results_section,
    };

    Ok(template)
}

/// Prepares the events result section template.
#[instrument(skip(db), err)]
async fn prepare_events_result_section(
    db: &DynDB,
    community_id: Uuid,
    filters: &EventsFilters,
) -> Result<explore::EventsResultsSection> {
    // Search for community events based on filters
    let SearchCommunityEventsOutput {
        mut events,
        bbox,
        total,
    } = db.search_community_events(community_id, filters).await?;

    // Render popover HTML for map and calendar views
    if filters.view_mode == Some(explore::ViewMode::Map)
        || filters.view_mode == Some(explore::ViewMode::Calendar)
    {
        for event in &mut events {
            event.popover_html = Some(render_event_popover(event)?);
        }
    }

    // Prepare template
    let template = explore::EventsResultsSection {
        events: events.into_iter().map(|event| explore::EventCard { event }).collect(),
        navigation_links: NavigationLinks::from_filters(&Entity::Events, filters, total)?,
        total,
        bbox,
        offset: filters.offset,
        view_mode: filters.view_mode.clone(),
    };

    Ok(template)
}

/// Handler that renders the groups section of the explore page.
#[instrument(skip_all, err)]
pub(crate) async fn groups_section(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare groups section template
    let filters = GroupsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    let template = prepare_groups_section(&db, community_id, &filters).await?;

    // Prepare response headers
    let url = pagination::build_url("/explore?entity=groups", &filters)?;
    let extra_headers = [("HX-Push-Url", url.as_str())];
    let headers = prepare_headers(Duration::minutes(10), &extra_headers)?;

    Ok((headers, Html(template.render()?)))
}

/// Handler that renders the groups results section of the explore page.
#[instrument(skip_all, err)]
pub(crate) async fn groups_results_section(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare groups section template
    let filters = GroupsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    let template = prepare_groups_result_section(&db, community_id, &filters).await?;

    // Prepare response headers
    let url = pagination::build_url("/explore?entity=groups", &filters)?;
    let extra_headers = [("HX-Push-Url", url.as_str())];
    let headers = prepare_headers(Duration::minutes(10), &extra_headers)?;

    Ok((headers, Html(template.render()?)))
}

/// Prepares groups section template.
#[instrument(skip(db), err)]
async fn prepare_groups_section(
    db: &DynDB,
    community_id: Uuid,
    filters: &GroupsFilters,
) -> Result<explore::GroupsSection> {
    // Prepare template
    let (filters_options, results_section) = tokio::try_join!(
        db.get_community_filters_options(community_id),
        prepare_groups_result_section(db, community_id, filters)
    )?;
    let template = explore::GroupsSection {
        filters: filters.clone(),
        filters_options,
        results_section,
    };

    Ok(template)
}

/// Prepares the groups result section template.
#[instrument(skip(db), err)]
async fn prepare_groups_result_section(
    db: &DynDB,
    community_id: Uuid,
    filters: &GroupsFilters,
) -> Result<explore::GroupsResultsSection> {
    // Search for community groups based on filters
    let SearchCommunityGroupsOutput {
        mut groups,
        bbox,
        total,
    } = db.search_community_groups(community_id, filters).await?;

    // Render popover HTML for map and calendar views
    if filters.view_mode == Some(explore::ViewMode::Map)
        || filters.view_mode == Some(explore::ViewMode::Calendar)
    {
        for group in &mut groups {
            group.popover_html = Some(render_group_popover(group)?);
        }
    }

    // Prepare template
    let template = explore::GroupsResultsSection {
        groups: groups.into_iter().map(|group| explore::GroupCard { group }).collect(),
        navigation_links: NavigationLinks::from_filters(&Entity::Groups, filters, total)?,
        total,
        bbox,
        offset: filters.offset,
        view_mode: filters.view_mode.clone(),
    };

    Ok(template)
}

// JSON search handlers.

/// Handler for the events search endpoint (JSON format).
#[instrument(skip_all, err)]
pub(crate) async fn search_events(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Search events
    let filters = EventsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    let mut search_events_output = db.search_community_events(community_id, &filters).await?;

    // Render popover HTML for each event
    for event in &mut search_events_output.events {
        event.popover_html = Some(render_event_popover(event)?);
    }

    // Prepare response headers
    let headers = prepare_headers(Duration::hours(1), &[])?;

    Ok((headers, Json(search_events_output)).into_response())
}

/// Handler for the groups search endpoint (JSON format).
#[instrument(skip_all, err)]
pub(crate) async fn search_groups(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    RawQuery(raw_query): RawQuery,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Search groups
    let filters = GroupsFilters::new(&headers, &raw_query.unwrap_or_default())?;
    let mut search_groups_output = db.search_community_groups(community_id, &filters).await?;

    // Render popover HTML for each group
    for group in &mut search_groups_output.groups {
        group.popover_html = Some(render_group_popover(group)?);
    }

    // Prepare response headers
    let headers = prepare_headers(Duration::hours(1), &[])?;

    Ok((headers, Json(search_groups_output)).into_response())
}

// Tests.

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use axum::{
        body::{Body, to_bytes},
        http::{
            HeaderMap, HeaderValue, Request, StatusCode,
            header::{CACHE_CONTROL, CONTENT_TYPE, HOST},
        },
    };
    use chrono::{TimeZone, Utc};
    use tower::ServiceExt;
    use uuid::Uuid;

    use crate::{
        db::{
            BBox,
            common::{SearchCommunityEventsOutput, SearchCommunityGroupsOutput},
            mock::MockDB,
        },
        router::setup_test_router,
        services::notifications::MockNotificationsManager,
        templates::community::{
            explore::{self, FilterOption},
            pagination,
        },
        types::{
            community::{Community, Theme},
            event::{EventDetailed, EventKind},
            group::{GroupCategory, GroupDetailed, GroupRegion},
        },
    };

    #[tokio::test]
    async fn test_page_db_error() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community()
            .withf(move |id| *id == community_id)
            .returning(|_| Err(anyhow::anyhow!("db error")));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/explore?entity=events")
            .header(HOST, "example.test")
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
    async fn test_page_events_invalid_filters() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community()
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community(community_id)));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/explore?entity=events&limit=invalid")
            .header(HOST, "example.test")
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
    async fn test_page_groups_invalid_filters() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community()
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community(community_id)));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/explore?entity=groups&limit=invalid")
            .header(HOST, "example.test")
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
    async fn test_page_success_events() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community()
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community(community_id)));
        db.expect_get_community_filters_options()
            .withf(move |id| *id == community_id)
            .returning(|_| Ok(sample_filters_options()));
        db.expect_search_community_events()
            .withf(move |id, _| *id == community_id)
            .returning(move |_, _| Ok(sample_search_community_events_output(event_id)));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/explore?entity=events")
            .header(HOST, "example.test")
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::OK);
        assert_eq!(
            parts.headers.get(CONTENT_TYPE).unwrap(),
            &HeaderValue::from_static("text/html; charset=utf-8")
        );
        assert_eq!(
            parts.headers.get(CACHE_CONTROL).unwrap(),
            &HeaderValue::from_static("max-age=0")
        );
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_page_success_groups() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community()
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community(community_id)));
        db.expect_get_community_filters_options()
            .withf(move |id| *id == community_id)
            .returning(|_| Ok(sample_filters_options()));
        db.expect_search_community_groups()
            .withf(move |id, _| *id == community_id)
            .returning(move |_, _| Ok(sample_search_community_groups_output(group_id)));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/explore?entity=groups")
            .header(HOST, "example.test")
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::OK);
        assert_eq!(
            parts.headers.get(CONTENT_TYPE).unwrap(),
            &HeaderValue::from_static("text/html; charset=utf-8")
        );
        assert_eq!(
            parts.headers.get(CACHE_CONTROL).unwrap(),
            &HeaderValue::from_static("max-age=0")
        );
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_events_section_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community_filters_options()
            .withf(move |id| *id == community_id)
            .returning(|_| Ok(sample_filters_options()));
        db.expect_search_community_events()
            .withf(move |id, _| *id == community_id)
            .returning(move |_, _| Ok(sample_search_community_events_output(event_id)));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/explore/events-section")
            .header(HOST, "example.test")
            .body(Body::empty())
            .unwrap();
        let raw_query = request.uri().query().map(str::to_string).unwrap_or_default();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::OK);
        assert_eq!(
            parts.headers.get(CONTENT_TYPE).unwrap(),
            &HeaderValue::from_static("text/html; charset=utf-8")
        );
        assert_eq!(
            parts.headers.get(CACHE_CONTROL).unwrap(),
            &HeaderValue::from_static("max-age=0")
        );
        assert_eq!(
            parts.headers.get("HX-Push-Url").unwrap().to_str().unwrap(),
            expected_events_push_url(&raw_query)
        );
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_events_results_section_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_search_community_events()
            .withf(move |id, _| *id == community_id)
            .returning(move |_, _| Ok(sample_search_community_events_output(event_id)));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/explore/events-results-section")
            .header(HOST, "example.test")
            .body(Body::empty())
            .unwrap();
        let raw_query = request.uri().query().map(str::to_string).unwrap_or_default();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::OK);
        assert_eq!(
            parts.headers.get(CONTENT_TYPE).unwrap(),
            &HeaderValue::from_static("text/html; charset=utf-8")
        );
        assert_eq!(
            parts.headers.get(CACHE_CONTROL).unwrap(),
            &HeaderValue::from_static("max-age=0")
        );
        assert_eq!(
            parts.headers.get("HX-Push-Url").unwrap().to_str().unwrap(),
            expected_events_push_url(&raw_query)
        );
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_groups_section_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community_filters_options()
            .withf(move |id| *id == community_id)
            .returning(|_| Ok(sample_filters_options()));
        db.expect_search_community_groups()
            .withf(move |id, _| *id == community_id)
            .returning(move |_, _| Ok(sample_search_community_groups_output(group_id)));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/explore/groups-section")
            .header(HOST, "example.test")
            .body(Body::empty())
            .unwrap();
        let raw_query = request.uri().query().map(str::to_string).unwrap_or_default();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::OK);
        assert_eq!(
            parts.headers.get(CONTENT_TYPE).unwrap(),
            &HeaderValue::from_static("text/html; charset=utf-8")
        );
        assert_eq!(
            parts.headers.get(CACHE_CONTROL).unwrap(),
            &HeaderValue::from_static("max-age=0")
        );
        assert_eq!(
            parts.headers.get("HX-Push-Url").unwrap().to_str().unwrap(),
            expected_groups_push_url(&raw_query)
        );
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_groups_results_section_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_search_community_groups()
            .withf(move |id, _| *id == community_id)
            .returning(move |_, _| Ok(sample_search_community_groups_output(group_id)));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/explore/groups-results-section")
            .header(HOST, "example.test")
            .body(Body::empty())
            .unwrap();
        let raw_query = request.uri().query().map(str::to_string).unwrap_or_default();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::OK);
        assert_eq!(
            parts.headers.get(CONTENT_TYPE).unwrap(),
            &HeaderValue::from_static("text/html; charset=utf-8")
        );
        assert_eq!(
            parts.headers.get(CACHE_CONTROL).unwrap(),
            &HeaderValue::from_static("max-age=0")
        );
        assert_eq!(
            parts.headers.get("HX-Push-Url").unwrap().to_str().unwrap(),
            expected_groups_push_url(&raw_query)
        );
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_search_events_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_search_community_events()
            .withf(move |id, _| *id == community_id)
            .returning(move |_, _| Ok(sample_search_community_events_output(event_id)));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/explore/events/search")
            .header(HOST, "example.test")
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
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_search_groups_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_search_community_groups()
            .withf(move |id, _| *id == community_id)
            .returning(move |_, _| Ok(sample_search_community_groups_output(group_id)));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/explore/groups/search")
            .header(HOST, "example.test")
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
        assert!(!bytes.is_empty());
    }

    // Helpers

    /// Helper to compute the expected events HX-Push-Url for tests.
    fn expected_events_push_url(raw_query: &str) -> String {
        let headers = HeaderMap::new();
        let filters = explore::EventsFilters::new(&headers, raw_query).unwrap();
        pagination::build_url("/explore?entity=events", &filters).unwrap()
    }

    /// Helper to compute the expected groups HX-Push-Url for tests.
    fn expected_groups_push_url(raw_query: &str) -> String {
        let headers = HeaderMap::new();
        let filters = explore::GroupsFilters::new(&headers, raw_query).unwrap();
        pagination::build_url("/explore?entity=groups", &filters).unwrap()
    }

    /// Helper to create a sample bounding box for tests.
    fn sample_bbox() -> BBox {
        BBox {
            ne_lat: 1.0,
            ne_lon: 2.0,
            sw_lat: -1.0,
            sw_lon: -2.0,
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

    /// Helper to create a sample event for tests.
    fn sample_event(event_id: Uuid) -> EventDetailed {
        EventDetailed {
            event_id,
            group_category_name: "Category".to_string(),
            group_name: "Group".to_string(),
            group_slug: "group".to_string(),
            kind: EventKind::InPerson,
            name: "Sample Event".to_string(),
            published: true,
            slug: "sample-event".to_string(),
            timezone: chrono_tz::UTC,
            ends_at: Some(Utc.timestamp_opt(1_000, 0).unwrap()),
            group_city: Some("City".to_string()),
            group_country_code: Some("US".to_string()),
            group_country_name: Some("United States".to_string()),
            group_state: Some("CA".to_string()),
            latitude: Some(1.0),
            longitude: Some(2.0),
            starts_at: Some(Utc.timestamp_opt(0, 0).unwrap()),
            venue_address: Some("123 Main St".to_string()),
            venue_city: Some("City".to_string()),
            venue_name: Some("Venue".to_string()),
            ..Default::default()
        }
    }

    /// Helper to create sample filter options for tests.
    fn sample_filters_options() -> explore::FiltersOptions {
        explore::FiltersOptions {
            distance: vec![FilterOption {
                name: "5 km".to_string(),
                value: "5".to_string(),
            }],
            event_category: vec![FilterOption {
                name: "Category".to_string(),
                value: "category".to_string(),
            }],
            group_category: vec![FilterOption {
                name: "Category".to_string(),
                value: "category".to_string(),
            }],
            region: vec![FilterOption {
                name: "Region".to_string(),
                value: "region".to_string(),
            }],
        }
    }

    /// Helper to create a sample group for tests.
    fn sample_group(group_id: Uuid) -> GroupDetailed {
        let group_category_id = Uuid::from_u128(2);
        let region_id = Uuid::from_u128(3);

        GroupDetailed {
            active: true,
            category: GroupCategory {
                group_category_id,
                name: "Category".to_string(),
                normalized_name: "category".to_string(),
                order: None,
            },
            created_at: Utc.timestamp_opt(0, 0).unwrap(),
            group_id,
            name: "Sample Group".to_string(),
            slug: "sample-group".to_string(),
            city: Some("City".to_string()),
            country_code: Some("US".to_string()),
            country_name: Some("United States".to_string()),
            latitude: Some(1.0),
            longitude: Some(2.0),
            region: Some(GroupRegion {
                region_id,
                name: "Region".to_string(),
                normalized_name: "region".to_string(),
                order: None,
            }),
            state: Some("CA".to_string()),
            ..Default::default()
        }
    }

    /// Helper to create sample events search output for tests.
    fn sample_search_community_events_output(event_id: Uuid) -> SearchCommunityEventsOutput {
        let mut output = SearchCommunityEventsOutput {
            events: vec![sample_event(event_id)],
            total: 1,
            ..Default::default()
        };
        output.bbox = Some(sample_bbox());
        output
    }

    /// Helper to create sample groups search output for tests.
    fn sample_search_community_groups_output(group_id: Uuid) -> SearchCommunityGroupsOutput {
        let mut output = SearchCommunityGroupsOutput {
            groups: vec![sample_group(group_id)],
            total: 1,
            ..Default::default()
        };
        output.bbox = Some(sample_bbox());
        output
    }
}
