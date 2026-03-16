use axum::body::to_bytes;

use super::*;

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
async fn test_non_db_anyhow_error_returns_500() {
    let error: HandlerError = anyhow::anyhow!("some internal error").into();
    let response = error.into_response();
    let parts = response.into_parts().0;

    assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
}
