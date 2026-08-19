//! Shared helpers for background worker services.

use std::{future::Future, time::Duration};

use tokio::time::sleep;
use tokio_util::sync::CancellationToken;

pub(crate) mod claim_loop;

#[cfg(test)]
mod tests;

/// Directs the shared worker driver after one iteration.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum WorkerIteration {
    /// Starts the next iteration immediately.
    Continue,
    /// Waits for the specified duration before the next iteration.
    Pause(Duration),
}

/// Runs cancellation-aware worker iterations until graceful shutdown.
///
/// Cancellation waits for an in-flight iteration to finish, prevents another
/// iteration from starting, and interrupts any pause between iterations.
pub(crate) async fn run_worker<Iterate, IterateFuture>(
    cancellation_token: &CancellationToken,
    mut iterate: Iterate,
) where
    Iterate: FnMut() -> IterateFuture + Send,
    IterateFuture: Future<Output = WorkerIteration> + Send,
{
    loop {
        // Stop before starting another unit after cancellation
        if cancellation_token.is_cancelled() {
            break;
        }

        // Finish the current unit before honoring graceful shutdown
        let iteration = iterate().await;

        // Avoid starting a pause or another unit after completed work observes shutdown
        if cancellation_token.is_cancelled() {
            break;
        }

        // Apply the iteration's selected cadence without delaying shutdown
        if let WorkerIteration::Pause(duration) = iteration {
            tokio::select! {
                biased;
                () = cancellation_token.cancelled() => break,
                () = sleep(duration) => {}
            }
        }
    }
}
