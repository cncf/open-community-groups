//! Shared behavior for workers that claim one durable unit at a time.

use std::{future::Future, sync::Mutex, time::Duration};

use tokio_util::sync::CancellationToken;

use super::{WorkerIteration, run_worker};

#[cfg(test)]
mod tests;

/// Cadence applied to idle and failed claim attempts.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct ClaimLoopConfig {
    /// Pause after an iteration fails.
    pub(crate) pause_on_error: Duration,
    /// Pause when no work is available.
    pub(crate) pause_on_none: Duration,
}

impl Default for ClaimLoopConfig {
    /// [`Default::default`].
    fn default() -> Self {
        Self {
            pause_on_error: Duration::from_secs(10),
            pause_on_none: Duration::from_secs(15),
        }
    }
}

/// Runs a claim workflow until graceful shutdown.
///
/// Cancellation waits for an in-flight claim workflow to record its outcome,
/// then prevents another claim attempt from starting.
pub(crate) async fn run<E, ProcessNext, ProcessNextFuture, ReportError>(
    cancellation_token: &CancellationToken,
    config: ClaimLoopConfig,
    mut process_next: ProcessNext,
    report_error: ReportError,
) where
    E: Send,
    ProcessNext: FnMut() -> ProcessNextFuture + Send,
    ProcessNextFuture: Future<Output = Result<bool, E>> + Send,
    ReportError: FnMut(&E) -> Option<Duration> + Send,
{
    // Preserve mutable error reporting across independently owned iteration futures
    let report_error = Mutex::new(report_error);

    // Delegate cancellation and pause handling to the shared worker driver
    run_worker(cancellation_token, || {
        let process_next = process_next();
        let report_error = &report_error;
        async move {
            // Map the domain result to its immediate or delayed retry cadence
            match process_next.await {
                Ok(true) => WorkerIteration::Continue,
                Ok(false) => WorkerIteration::Pause(config.pause_on_none),
                Err(err) => {
                    // Recover the worker-local reporter after mutex poisoning
                    let mut report_error = match report_error.lock() {
                        Ok(report_error) => report_error,
                        Err(poisoned) => poisoned.into_inner(),
                    };
                    WorkerIteration::Pause(report_error(&err).unwrap_or(config.pause_on_error))
                }
            }
        }
    })
    .await;
}
