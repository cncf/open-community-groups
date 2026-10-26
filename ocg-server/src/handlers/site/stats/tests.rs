use axum::{
    body::Body,
    http::{HeaderValue, StatusCode, header::CACHE_CONTROL},
};

use crate::{
    db::mock::{MockDB, expect_site_settings},
    handlers::tests::*,
    router::CACHE_CONTROL_PUBLIC_SHARED,
};

#[tokio::test]
async fn test_page_success() {
    // Setup database mock
    let mut db = MockDB::new();
    expect_site_settings(&mut db);
    db.expect_get_site_stats()
        .times(1)
        .returning(|| Ok(sample_site_stats()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = request("GET", "/stats").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        &HeaderValue::from_static(CACHE_CONTROL_PUBLIC_SHARED)
    );
}
