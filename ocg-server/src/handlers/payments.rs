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

/// Handles connected-account payment events with the Connect endpoint secret.
#[instrument(skip_all)]
pub(crate) async fn connected_webhook(
    State(payments_manager): State<DynPaymentsManager>,
    headers: HeaderMap,
    body: String,
) -> impl IntoResponse {
    handle_webhook(&payments_manager, true, &headers, &body).await
}

/// Handles payments webhook events for the configured provider.
#[instrument(skip_all)]
pub(crate) async fn webhook(
    State(payments_manager): State<DynPaymentsManager>,
    headers: HeaderMap,
    body: String,
) -> impl IntoResponse {
    handle_webhook(&payments_manager, false, &headers, &body).await
}

/// Maps a verified payment event outcome into the webhook HTTP contract.
async fn handle_webhook(
    payments_manager: &DynPaymentsManager,
    connected_account: bool,
    headers: &HeaderMap,
    body: &str,
) -> axum::response::Response {
    // Delegate scoped signature verification and reconciliation to the manager
    let result = if connected_account {
        payments_manager.handle_connected_webhook(headers, body).await
    } else {
        payments_manager.handle_webhook(headers, body).await
    };
    match result {
        Ok(()) => StatusCode::OK.into_response(),
        Err(HandleWebhookError::InvalidPayload) => StatusCode::UNAUTHORIZED.into_response(),
        Err(HandleWebhookError::PaymentsNotConfigured) => StatusCode::NOT_FOUND.into_response(),
        Err(HandleWebhookError::Unexpected(err)) => {
            warn!(error = %err, "failed to handle payments webhook");
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}
