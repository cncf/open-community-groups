//! Bounded execution of CPU-heavy work off the async executor.

use std::sync::Arc;

use anyhow::{Context, Result};
use tokio::{sync::Semaphore, task::spawn_blocking};

#[cfg(test)]
mod tests;

/// Runs CPU-heavy closures on the blocking thread pool with a concurrency bound.
///
/// Callers await a permit before their closure is handed to `spawn_blocking`,
/// so a burst of password hashes cannot saturate the blocking pool and starve
/// the other work that depends on it. The permit is held until the closure
/// completes.
#[derive(Clone)]
pub(crate) struct BlockingExecutor {
    /// Permits limiting how many closures run at once.
    permits: Arc<Semaphore>,
}

impl BlockingExecutor {
    /// Creates an executor that runs at most `max_concurrency` closures at once.
    ///
    /// A zero bound is clamped to one so the executor can always make progress.
    pub(crate) fn new(max_concurrency: usize) -> Self {
        Self {
            permits: Arc::new(Semaphore::new(max_concurrency.max(1))),
        }
    }

    /// Runs `work` on the blocking pool once a permit is available.
    ///
    /// A panic inside `work` surfaces as an error instead of unwinding the
    /// caller.
    pub(crate) async fn run<Work, Output>(&self, work: Work) -> Result<Output>
    where
        Work: FnOnce() -> Output + Send + 'static,
        Output: Send + 'static,
    {
        // Wait for a permit before occupying a blocking thread
        let permit = self
            .permits
            .clone()
            .acquire_owned()
            .await
            .context("blocking executor closed")?;

        // Run the work and release the permit when it completes
        spawn_blocking(move || {
            let output = work();
            drop(permit);
            output
        })
        .await
        .context("error running blocking work")
    }

    /// Returns how many closures can start without waiting.
    #[cfg(test)]
    pub(crate) fn available_permits(&self) -> usize {
        self.permits.available_permits()
    }
}
