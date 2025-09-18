//! HTTP handlers for the community home page.
//!
//! The home page displays an overview of the community including recent groups,
//! upcoming events (both in-person and virtual), and community statistics.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::State,
    http::Uri,
    response::{Html, IntoResponse},
};
use chrono::Duration;
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::CommunityId, prepare_headers},
    templates::{PageId, auth::User, community::home},
    types::event::EventKind,
};

// Pages handlers.

/// Handler that renders the community home page.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (community, recently_added_groups, upcoming_in_person_events, upcoming_virtual_events, stats) = tokio::try_join!(
        db.get_community(community_id),
        db.get_community_recently_added_groups(community_id),
        db.get_community_upcoming_events(community_id, vec![EventKind::InPerson, EventKind::Hybrid]),
        db.get_community_upcoming_events(community_id, vec![EventKind::Virtual, EventKind::Hybrid]),
        db.get_community_home_stats(community_id),
    )?;
    let template = home::Page {
        community,
        page_id: PageId::CommunityHome,
        path: uri.path().to_string(),
        recently_added_groups: recently_added_groups
            .into_iter()
            .map(|group| home::GroupCard { group })
            .collect(),
        stats,
        upcoming_in_person_events: upcoming_in_person_events
            .into_iter()
            .map(|event| home::EventCard { event })
            .collect(),
        upcoming_virtual_events: upcoming_virtual_events
            .into_iter()
            .map(|event| home::EventCard { event })
            .collect(),
        user: User::default(),
    };

    // Prepare response headers
    let headers = prepare_headers(Duration::hours(1), &[])?;

    Ok((headers, Html(template.render()?)))
}

// Tests.

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use axum::body::to_bytes;
    use axum::http::{
        HeaderValue, Request, StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE, HOST},
    };
    use tower::ServiceExt;
    use uuid::Uuid;

    use crate::{
        db::mock::MockDB,
        router::setup_test_router,
        services::notifications::MockNotificationsManager,
        templates::community::home::Stats,
        types::{
            community::{Community, Theme},
            event::EventKind,
        },
    };

    #[tokio::test]
    async fn test_page_success() {
        // Setup database mock
        let community_id = Uuid::new_v4();
        let mut db = MockDB::new();
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community()
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community(community_id)));
        db.expect_get_community_recently_added_groups()
            .withf(move |id| *id == community_id)
            .returning(|_| Ok(vec![]));
        db.expect_get_community_upcoming_events()
            .withf(move |id, kinds| {
                *id == community_id && kinds == &vec![EventKind::InPerson, EventKind::Hybrid]
            })
            .returning(|_, _| Ok(vec![]));
        db.expect_get_community_upcoming_events()
            .withf(move |id, kinds| {
                *id == community_id && kinds == &vec![EventKind::Virtual, EventKind::Hybrid]
            })
            .returning(|_, _| Ok(vec![]));
        db.expect_get_community_home_stats()
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(Stats::default()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/")
            .header(HOST, "example.test")
            .body(axum::body::Body::empty())
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
    async fn test_page_db_error() {
        // Setup database mock
        let community_id = Uuid::new_v4();
        let mut db = MockDB::new();
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community()
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community(community_id)));
        db.expect_get_community_recently_added_groups()
            .withf(move |id| *id == community_id)
            .returning(|_| Ok(vec![]));
        db.expect_get_community_upcoming_events()
            .withf(move |id, kinds| {
                *id == community_id && kinds == &vec![EventKind::InPerson, EventKind::Hybrid]
            })
            .returning(|_, _| Ok(vec![]));
        db.expect_get_community_upcoming_events()
            .withf(move |id, kinds| {
                *id == community_id && kinds == &vec![EventKind::Virtual, EventKind::Hybrid]
            })
            .returning(|_, _| Err(anyhow::anyhow!("db error")));
        db.expect_get_community_home_stats()
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(Stats::default()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/")
            .header(HOST, "example.test")
            .body(axum::body::Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
        assert!(bytes.is_empty());
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
}
