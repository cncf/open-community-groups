use axum::{
    body::{Body, to_bytes},
    http::{Request, StatusCode},
};
use tower::ServiceExt;

use crate::{
    db::mock::MockDB,
    handlers::tests::{TestRouterBuilder, sample_site_settings},
    services::notifications::MockNotificationsManager,
};

#[tokio::test]
async fn test_page_search_form_uses_htmx_for_submit_and_live_input() {
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/search")
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let body = String::from_utf8(to_bytes(body, usize::MAX).await.unwrap().to_vec()).unwrap();

    assert_eq!(parts.status, StatusCode::OK);
    assert!(body.contains("hx-get=\"/search\""));
    assert!(body.contains("hx-target=\"#site-search-results\""));
    assert!(body.contains(
        "hx-trigger=\"submit, input changed delay:300ms from:#site-search-query, search from:#site-search-query\""
    ));
}
