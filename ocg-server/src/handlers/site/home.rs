//! HTTP handlers for the global site home page.

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
    handlers::{error::HandlerError, prepare_headers},
    templates::{PageId, auth::User, site::home},
    types::event::EventKind,
};

/// Handler that renders the global site home page.
#[instrument(skip_all, err)]
pub(crate) async fn page(State(db): State<DynDB>, uri: Uri) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (
        communities,
        recently_added_groups,
        site_settings,
        stats,
        upcoming_in_person_events,
        upcoming_virtual_events,
    ) = tokio::try_join!(
        db.list_communities(),
        db.get_site_recently_added_groups(),
        db.get_site_settings(),
        db.get_site_home_stats(),
        db.get_site_upcoming_events(vec![EventKind::InPerson, EventKind::Hybrid]),
        db.get_site_upcoming_events(vec![EventKind::Virtual, EventKind::Hybrid]),
    )?;
    let template = home::Page {
        communities,
        page_id: PageId::SiteHome,
        path: uri.path().to_string(),
        recently_added_groups: recently_added_groups
            .into_iter()
            .map(|group| home::GroupCard { group })
            .collect(),
        site_settings,
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
    let headers = prepare_headers(Duration::minutes(15), &[])?;

    Ok((headers, Html(template.render()?)))
}

// Tests.

#[cfg(test)]
mod tests {
    use anyhow::anyhow;
    use axum::{
        body::{Body, to_bytes},
        http::{
            HeaderValue, Request, StatusCode,
            header::{CACHE_CONTROL, CONTENT_TYPE},
        },
    };
    use tower::ServiceExt;

    use crate::{db::mock::MockDB, handlers::tests::*, services::notifications::MockNotificationsManager};

    #[tokio::test]
    async fn test_page_db_error() {
        // Setup database mock
        // Note: when get_site_home_stats fails, other concurrent calls may or may not complete
        let mut db = MockDB::new();
        db.expect_get_site_home_stats().returning(|| Err(anyhow!("db error")));
        db.expect_get_site_recently_added_groups().returning(|| Ok(vec![]));
        db.expect_get_site_settings().returning(|| Ok(sample_site_settings()));
        db.expect_get_site_upcoming_events().returning(|_| Ok(vec![]));
        db.expect_list_communities().returning(|| Ok(vec![]));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder().method("GET").uri("/").body(Body::empty()).unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_page_success() {
        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_site_home_stats()
            .times(1)
            .returning(|| Ok(sample_site_home_stats()));
        db.expect_get_site_recently_added_groups()
            .times(1)
            .returning(|| Ok(vec![]));
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));
        db.expect_get_site_upcoming_events()
            .times(2)
            .returning(|_| Ok(vec![]));
        db.expect_list_communities().times(1).returning(|| Ok(vec![]));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder().method("GET").uri("/").body(Body::empty()).unwrap();
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
}
