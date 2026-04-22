//! Handlers for payments webhooks.

use axum::{
    extract::State,
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
};
use tracing::{instrument, warn};

use crate::services::payments::{DynPaymentsManager, HandleWebhookError};

#[cfg(test)]
mod tests;

// Actions handlers.

/// Handles payments webhook events for the configured provider.
#[instrument(skip_all)]
pub(crate) async fn webhook(
    State(payments_manager): State<DynPaymentsManager>,
    headers: HeaderMap,
    body: String,
) -> impl IntoResponse {
    // Delegate webhook verification and processing to the payments manager
    match payments_manager.handle_webhook(&headers, &body).await {
        Ok(()) => StatusCode::OK.into_response(),
        Err(HandleWebhookError::InvalidPayload) => StatusCode::UNAUTHORIZED.into_response(),
        Err(HandleWebhookError::PaymentsNotConfigured) => StatusCode::NOT_FOUND.into_response(),
        Err(HandleWebhookError::Unexpected(err)) => {
            warn!(error = %err, "failed to handle payments webhook");
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}
