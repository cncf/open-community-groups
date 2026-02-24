//! HTTP handlers for the global site docs page.

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
    templates::{PageId, auth::User, site::docs},
};

/// Handler that renders the global site docs page.
#[instrument(skip_all, err)]
pub(crate) async fn page(State(db): State<DynDB>, uri: Uri) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let site_settings = db.get_site_settings().await?;
    let template = docs::Page {
        page_id: PageId::SiteDocs,
        path: uri.path().to_string(),
        site_settings,
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
        let mut db = MockDB::new();
        db.expect_get_site_settings().returning(|| Err(anyhow!("db error")));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/docs")
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

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/docs")
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
        assert!(String::from_utf8_lossy(&bytes).contains("/static/docs/#/"));
    }
}
