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

/// Handles Stripe webhook events.
#[instrument(skip_all)]
pub(crate) async fn stripe_event(
    State(payments_manager): State<DynPaymentsManager>,
    headers: HeaderMap,
    body: String,
) -> impl IntoResponse {
    // Load the Stripe signature header required for webhook verification
    let Some(signature_header) = headers.get("stripe-signature").and_then(|value| value.to_str().ok()) else {
        return StatusCode::UNAUTHORIZED.into_response();
    };

    // Delegate webhook verification and processing to the payments manager
    match payments_manager.handle_webhook(signature_header, &body).await {
        Ok(()) => StatusCode::OK.into_response(),
        Err(HandleWebhookError::InvalidPayload) => StatusCode::UNAUTHORIZED.into_response(),
        Err(HandleWebhookError::PaymentsNotConfigured) => StatusCode::NOT_FOUND.into_response(),
        Err(HandleWebhookError::Unexpected(err)) => {
            warn!(error = %err, "failed to handle Stripe webhook");
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}
