//! HTTP handlers for the community site.
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
    templates::{PageId, auth::User, community},
    types::event::EventKind,
};

// Pages handlers.

/// Handler that renders the community page.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (
        community,
        recently_added_groups,
        site_settings,
        upcoming_in_person_events,
        upcoming_virtual_events,
        stats,
    ) = tokio::try_join!(
        db.get_community_full(community_id),
        db.get_community_recently_added_groups(community_id),
        db.get_site_settings(),
        db.get_community_upcoming_events(community_id, vec![EventKind::InPerson, EventKind::Hybrid]),
        db.get_community_upcoming_events(community_id, vec![EventKind::Virtual, EventKind::Hybrid]),
        db.get_community_site_stats(community_id),
    )?;
    let template = community::Page {
        community,
        page_id: PageId::Community,
        path: uri.path().to_string(),
        recently_added_groups: recently_added_groups
            .into_iter()
            .map(|group| community::GroupCard { group })
            .collect(),
        site_settings,
        stats,
        upcoming_in_person_events: upcoming_in_person_events
            .into_iter()
            .map(|event| community::EventCard { event })
            .collect(),
        upcoming_virtual_events: upcoming_virtual_events
            .into_iter()
            .map(|event| community::EventCard { event })
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
    use anyhow::anyhow;
    use axum::body::to_bytes;
    use axum::http::{
        HeaderValue, Request, StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE},
    };
    use tower::ServiceExt;
    use uuid::Uuid;

    use crate::{
        db::mock::MockDB, handlers::tests::*, services::notifications::MockNotificationsManager,
        templates::community::Stats, types::event::EventKind,
    };

    #[tokio::test]
    async fn test_page_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_community_id_by_name()
            .times(1)
            .withf(|name| name == "test-community")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community_full()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community_full(community_id)));
        db.expect_get_community_recently_added_groups()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(|_| Ok(vec![]));
        db.expect_get_community_upcoming_events()
            .times(1)
            .withf(move |id, kinds| {
                *id == community_id && kinds == &vec![EventKind::InPerson, EventKind::Hybrid]
            })
            .returning(|_, _| Ok(vec![]));
        db.expect_get_community_upcoming_events()
            .times(1)
            .withf(move |id, kinds| {
                *id == community_id && kinds == &vec![EventKind::Virtual, EventKind::Hybrid]
            })
            .returning(|_, _| Ok(vec![]));
        db.expect_get_community_site_stats()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(Stats::default()));
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/test-community")
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
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_community_id_by_name()
            .times(1)
            .withf(|name| name == "test-community")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community_full()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community_full(community_id)));
        db.expect_get_community_recently_added_groups()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(|_| Ok(vec![]));
        db.expect_get_community_upcoming_events()
            .times(1)
            .withf(move |id, kinds| {
                *id == community_id && kinds == &vec![EventKind::InPerson, EventKind::Hybrid]
            })
            .returning(|_, _| Ok(vec![]));
        db.expect_get_community_upcoming_events()
            .times(1)
            .withf(move |id, kinds| {
                *id == community_id && kinds == &vec![EventKind::Virtual, EventKind::Hybrid]
            })
            .returning(|_, _| Ok(vec![]));
        db.expect_get_community_site_stats()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(move |_| Err(anyhow!("db error")));
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/test-community")
            .body(axum::body::Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
        assert!(bytes.is_empty());
    }
}
