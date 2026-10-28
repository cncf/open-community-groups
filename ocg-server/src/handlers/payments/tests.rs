use axum::{
    body::Body,
    http::{HeaderValue, Request, StatusCode},
};

use crate::{
    db::mock::MockDB,
    handlers::tests::{
        TestRouterBuilder, assert_empty_response, request, sample_payments_cfg, send,
    },
    services::payments::{HandleWebhookError, MockPaymentsManager},
};

#[tokio::test]
async fn test_connected_webhook_route_dispatches_to_connected_account_handler() {
    // Expect the connected route to select only the connected-account boundary
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_handle_connected_webhook()
        .times(1)
        .withf(|headers, body| {
            headers.get("stripe-signature") == Some(&HeaderValue::from_static("sig_test"))
                && body == "payload"
        })
        .returning(|_, _| Box::pin(async { Ok(()) }));
    payments_manager.expect_handle_webhook().never();

    // Setup router and send the provider payload through the application route
    let router = TestRouterBuilder::new(MockDB::new())
        .with_payments_cfg(sample_payments_cfg())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = webhook_request("/webhooks/payments/connected");
    let (parts, bytes) = send(router, request).await;

    // Check the connected endpoint accepts the successfully handled event
    assert_empty_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_webhook_returns_not_found_when_payments_are_not_configured() {
    // Setup payments manager mock
    let mut payments_manager =
        expect_platform_webhook(Err(HandleWebhookError::PaymentsNotConfigured));
    payments_manager.expect_handle_connected_webhook().never();

    // Setup router and send the provider payload
    let router = TestRouterBuilder::new(MockDB::new())
        .with_payments_cfg(sample_payments_cfg())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = webhook_request("/webhooks/payments");
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_webhook_returns_ok_when_payments_manager_succeeds() {
    // Setup payments manager mock
    let mut payments_manager = expect_platform_webhook(Ok(()));
    payments_manager.expect_handle_connected_webhook().never();

    // Setup router and send the provider payload
    let router = TestRouterBuilder::new(MockDB::new())
        .with_payments_cfg(sample_payments_cfg())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = webhook_request("/webhooks/payments");
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_webhook_returns_unauthorized_when_webhook_verification_fails() {
    // Setup payments manager mock
    let payments_manager = expect_platform_webhook(Err(HandleWebhookError::InvalidPayload));

    // Setup router and send the provider payload
    let router = TestRouterBuilder::new(MockDB::new())
        .with_payments_cfg(sample_payments_cfg())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = webhook_request("/webhooks/payments");
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn test_webhook_returns_server_error_when_payments_manager_fails() {
    // Setup payments manager mock
    let payments_manager =
        expect_platform_webhook(Err(HandleWebhookError::Unexpected(anyhow::anyhow!("boom"))));

    // Setup router and send the provider payload
    let router = TestRouterBuilder::new(MockDB::new())
        .with_payments_cfg(sample_payments_cfg())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = webhook_request("/webhooks/payments");
    let (parts, bytes) = send(router, request).await;

    // Check the failure detail is not exposed
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

// Helpers.

/// Expects one platform webhook call carrying the sample payload and returning `result`.
fn expect_platform_webhook(result: Result<(), HandleWebhookError>) -> MockPaymentsManager {
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_handle_webhook()
        .times(1)
        .withf(|headers, body| {
            headers.get("stripe-signature") == Some(&HeaderValue::from_static("sig_test"))
                && body == "payload"
        })
        .return_once(move |_, _| Box::pin(async move { result }));
    payments_manager
}

/// Builds a payments webhook request carrying the signed sample payload.
fn webhook_request(uri: &str) -> Request<Body> {
    request("POST", uri)
        .header("stripe-signature", "sig_test")
        .body(Body::from("payload"))
        .unwrap()
}
