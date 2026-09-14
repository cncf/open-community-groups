use axum::body::to_bytes;
use serde::Deserialize;

use crate::router::serde_qs_config;

use super::*;

#[tokio::test]
async fn test_auth_error_returns_401_with_empty_body() {
    let response = HandlerError::Auth.into_response();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    assert_eq!(parts.status, StatusCode::UNAUTHORIZED);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_database_error_returns_422_with_message() {
    let message = "event has reached capacity";
    let error = HandlerError::Database(message.to_string());
    let response = error.into_response();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), message.as_bytes());
}

#[tokio::test]
async fn test_deserialization_error_returns_422_with_fixed_body() {
    let error = HandlerError::Deserialization("missing field `name`".to_string());
    let response = error.into_response();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), INVALID_REQUEST_PAYLOAD.as_bytes());
}

#[tokio::test]
async fn test_filter_parse_error_returns_422_with_fixed_body() {
    // Setup a query string that cannot deserialize into the target
    let parse_error = serde_qs_config()
        .deserialize_str::<Limit>("limit=invalid")
        .unwrap_err();

    // Convert the filter error and render the response
    let error: HandlerError = FilterError::Parse(parse_error).into();
    let response = error.into_response();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the parser detail is not exposed
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), INVALID_REQUEST_PAYLOAD.as_bytes());
}

#[tokio::test]
async fn test_fiscal_sponsor_not_ready_returns_422_with_message() {
    let message = "fiscal sponsor Stripe account is not ready";
    let error: HandlerError = FiscalSponsorReadinessError::NotReady(message.to_string()).into();
    let response = error.into_response();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), message.as_bytes());
}

#[tokio::test]
async fn test_fiscal_sponsor_provider_failure_returns_500() {
    let error: HandlerError =
        FiscalSponsorReadinessError::Unexpected(anyhow::anyhow!("provider unavailable")).into();
    let response = error.into_response();
    let parts = response.into_parts().0;

    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_fiscal_sponsor_unexpected_preserves_classified_handler_error() {
    // Setup an already classified rejection carried through anyhow
    let carried = anyhow::Error::new(HandlerError::Rejected("checkout closed".to_string()));

    // Convert through the fiscal sponsor error and render the response
    let error: HandlerError = FiscalSponsorReadinessError::Unexpected(carried).into();
    let response = error.into_response();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the classification survives instead of becoming a 500
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), b"checkout closed");
}

#[tokio::test]
async fn test_non_db_anyhow_error_returns_500() {
    let error: HandlerError = anyhow::anyhow!("some internal error").into();
    let response = error.into_response();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(bytes.is_empty());
}

#[tokio::test]
async fn test_not_found_error_returns_404() {
    let response = HandlerError::NotFound.into_response();
    let parts = response.into_parts().0;

    assert_eq!(parts.status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_rejected_error_returns_422_with_message() {
    let message = "ticket type is required";
    let error = HandlerError::Rejected(message.to_string());
    let response = error.into_response();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), message.as_bytes());
}

#[tokio::test]
async fn test_serde_qs_error_returns_422_with_fixed_body() {
    // Setup a query string that cannot deserialize into the target
    let parse_error = serde_qs_config()
        .deserialize_str::<Limit>("limit=invalid")
        .unwrap_err();

    // Convert the serde_qs error and render the response
    let error: HandlerError = parse_error.into();
    let response = error.into_response();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the parser detail is not exposed
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), INVALID_REQUEST_PAYLOAD.as_bytes());
}

// Helpers.

/// Minimal query target used to produce deserialization failures.
#[derive(Debug, Deserialize)]
struct Limit {
    #[allow(dead_code)]
    limit: usize,
}
