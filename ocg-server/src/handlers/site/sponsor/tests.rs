use axum::{
    body::{Body, to_bytes},
    http::{HeaderValue, Request, StatusCode, header::CONTENT_TYPE},
};
use tower::ServiceExt;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    services::notifications::{MockNotificationsManager, OutboundEmail},
    templates::site::sponsor::SPONSOR_INQUIRY_RECIPIENT,
};

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
        .uri("/sponsor")
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
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("Sponsor GOUP"));
    assert!(body.contains("Send sponsor inquiry"));
}

#[tokio::test]
async fn test_submit_sends_email() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let mut nm = MockNotificationsManager::new();
    nm.expect_send_email()
        .times(1)
        .withf(|email: &OutboundEmail| {
            email.to == SPONSOR_INQUIRY_RECIPIENT
                && email.subject == "GOUP sponsor inquiry from Example Co"
                && email.body.contains("Name: Sponsor Person")
                && email.body.contains("Email: sponsor@example.com")
                && email.body.contains("Company: Example Co")
                && email.body.contains("Website: https://example.com")
                && email.body.contains("Budget: $5k")
                && email.body.contains("Message:\nWe want to sponsor a GOUP event.")
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("POST")
        .uri("/sponsor")
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(
            "name=Sponsor+Person&email=sponsor%40example.com&company=Example+Co&website=https%3A%2F%2Fexample.com&budget=%245k&message=We+want+to+sponsor+a+GOUP+event.",
        ))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::OK);
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(body.contains("Thanks for reaching out."));
}
