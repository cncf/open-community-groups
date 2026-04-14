use std::sync::Arc;

use axum::{
    extract::State,
    http::{HeaderMap, HeaderValue, StatusCode},
    response::IntoResponse,
};

use crate::services::payments::{DynPaymentsManager, HandleWebhookError, MockPaymentsManager};

use super::webhook;

#[tokio::test]
async fn test_webhook_returns_not_found_when_payments_are_not_configured() {
    // Setup payments manager mock
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_handle_webhook()
        .times(1)
        .withf(|headers, body| {
            headers.get("stripe-signature") == Some(&HeaderValue::from_static("sig_test"))
                && body == "payload"
        })
        .returning(|_, _| Box::pin(async { Err(HandleWebhookError::PaymentsNotConfigured) }));
    let payments_manager: DynPaymentsManager = Arc::new(payments_manager);

    // Setup headers and send request
    let mut headers = HeaderMap::new();
    headers.insert("stripe-signature", HeaderValue::from_static("sig_test"));
    let response = webhook(State(payments_manager), headers, "payload".to_string())
        .await
        .into_response();

    // Check response matches expectations
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_webhook_returns_ok_when_payments_manager_succeeds() {
    // Setup payments manager mock
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_handle_webhook()
        .times(1)
        .withf(|headers, body| {
            headers.get("stripe-signature") == Some(&HeaderValue::from_static("sig_test"))
                && body == "payload"
        })
        .returning(|_, _| Box::pin(async { Ok(()) }));
    let payments_manager: DynPaymentsManager = Arc::new(payments_manager);

    // Setup headers and send request
    let mut headers = HeaderMap::new();
    headers.insert("stripe-signature", HeaderValue::from_static("sig_test"));
    let response = webhook(State(payments_manager), headers, "payload".to_string())
        .await
        .into_response();

    // Check response matches expectations
    assert_eq!(response.status(), StatusCode::OK);
}

#[tokio::test]
async fn test_webhook_returns_unauthorized_when_signature_header_is_missing() {
    // Setup payments manager mock
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_handle_webhook()
        .times(1)
        .withf(|headers, body| headers.is_empty() && body == "payload")
        .returning(|_, _| Box::pin(async { Err(HandleWebhookError::InvalidPayload) }));
    let payments_manager: DynPaymentsManager = Arc::new(payments_manager);

    // Send request without the provider's required signature header
    let response = webhook(State(payments_manager), HeaderMap::new(), "payload".to_string())
        .await
        .into_response();

    // Check response matches expectations
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn test_webhook_returns_unauthorized_when_webhook_verification_fails() {
    // Setup payments manager mock
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_handle_webhook()
        .times(1)
        .withf(|headers, body| {
            headers.get("stripe-signature") == Some(&HeaderValue::from_static("sig_test"))
                && body == "payload"
        })
        .returning(|_, _| Box::pin(async { Err(HandleWebhookError::InvalidPayload) }));
    let payments_manager: DynPaymentsManager = Arc::new(payments_manager);

    // Setup headers and send request
    let mut headers = HeaderMap::new();
    headers.insert("stripe-signature", HeaderValue::from_static("sig_test"));
    let response = webhook(State(payments_manager), headers, "payload".to_string())
        .await
        .into_response();

    // Check response matches expectations
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn test_webhook_returns_server_error_when_payments_manager_fails() {
    // Setup payments manager mock
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_handle_webhook()
        .times(1)
        .withf(|headers, body| {
            headers.get("stripe-signature") == Some(&HeaderValue::from_static("sig_test"))
                && body == "payload"
        })
        .returning(|_, _| Box::pin(async { Err(HandleWebhookError::Unexpected(anyhow::anyhow!("boom"))) }));
    let payments_manager: DynPaymentsManager = Arc::new(payments_manager);

    // Setup headers and send request
    let mut headers = HeaderMap::new();
    headers.insert("stripe-signature", HeaderValue::from_static("sig_test"));
    let response = webhook(State(payments_manager), headers, "payload".to_string())
        .await
        .into_response();

    // Check response matches expectations
    assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);
}
