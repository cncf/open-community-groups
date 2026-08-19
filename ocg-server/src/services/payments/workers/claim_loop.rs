//! Shared claim-loop behavior for provider-mediated payment workers.

use std::{future::Future, time::Duration};

use anyhow::Result;
use tokio::time::sleep;
use tokio_util::sync::CancellationToken;

use crate::services::workers::run_until_cancelled;

#[cfg(test)]
mod tests;

/// Pause after a payment worker iteration fails.
const PAUSE_ON_ERROR: Duration = Duration::from_secs(10);

/// Pause when no payment work is available.
const PAUSE_ON_NONE: Duration = Duration::from_secs(15);

/// Runs one payment worker's claim workflow until graceful shutdown.
///
/// Cancellation drops an in-flight unit of work and deliberately leaves any
/// durable claim for the payment recovery worker to release after its timeout.
pub(super) async fn run<ProcessNext, ProcessNextFuture, ReportError>(
    cancellation_token: &CancellationToken,
    mut process_next: ProcessNext,
    mut report_error: ReportError,
) where
    ProcessNext: FnMut() -> ProcessNextFuture,
    ProcessNextFuture: Future<Output = Result<bool>>,
    ReportError: FnMut(&anyhow::Error),
{
    loop {
        // Stop before starting another unit of work after cancellation
        if cancellation_token.is_cancelled() {
            break;
        }

        // Run one unit while allowing cancellation to abandon its durable claim
        let Some(result) = run_until_cancelled(cancellation_token, process_next()).await else {
            break;
        };

        // Continue after completed work or select the appropriate pause
        let pause = match result {
            Ok(true) => None,
            Ok(false) => Some(PAUSE_ON_NONE),
            Err(err) => {
                report_error(&err);
                Some(PAUSE_ON_ERROR)
            }
        };

        // Apply the selected pause without delaying graceful shutdown
        if let Some(pause) = pause {
            tokio::select! {
                () = sleep(pause) => {},
                () = cancellation_token.cancelled() => break,
            }
        }

        // Avoid another claim when cancellation raced with this iteration
        if cancellation_token.is_cancelled() {
            break;
        }
    }
}
