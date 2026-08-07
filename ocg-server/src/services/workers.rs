//! Shared helpers for background worker services.

use std::future::Future;

use tokio_util::sync::CancellationToken;

/// Waits for work to finish while giving graceful cancellation priority.
pub(crate) async fn run_until_cancelled<T>(
    cancellation_token: &CancellationToken,
    future: impl Future<Output = T>,
) -> Option<T> {
    tokio::select! {
        biased;
        () = cancellation_token.cancelled() => None,
        result = future => Some(result),
    }
}
