//! HTTP handlers for the global site stats page.

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
    templates::{PageId, auth::User, site::stats},
};

// Page handlers.

/// Handler that renders the global site stats page.
#[instrument(skip_all, err)]
pub(crate) async fn page(State(db): State<DynDB>, uri: Uri) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (site_settings, stats) = tokio::try_join!(db.get_site_settings(), db.get_site_stats())?;
    let template = stats::Page {
        page_id: PageId::SiteStats,
        path: uri.path().to_string(),
        site_settings,
        stats,
        user: User::default(),
    };

    // Prepare response headers
    let headers = prepare_headers(Duration::hours(6), &[])?;

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
        let mut db = MockDB::new();
        db.expect_get_site_stats().returning(|| Err(anyhow!("db error")));
        db.expect_get_site_settings().returning(|| Ok(sample_site_settings()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/stats")
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
        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));
        db.expect_get_site_stats()
            .times(1)
            .returning(|| Ok(sample_site_stats()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/stats")
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
}
