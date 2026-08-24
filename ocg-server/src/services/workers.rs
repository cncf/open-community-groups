//! Shared helpers for background worker services.

use std::{future::Future, time::Duration};

use tokio::time::sleep;
use tokio_util::{sync::CancellationToken, task::TaskTracker};

pub(crate) mod claim_loop;

#[cfg(test)]
mod tests;

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

/// Coordinates background worker spawning and graceful shutdown.
pub(crate) struct BackgroundTasks {
    /// Token used to request worker cancellation.
    cancellation_token: CancellationToken,
    /// Tracker used to await worker completion.
    task_tracker: TaskTracker,
}

impl BackgroundTasks {
    /// Creates background task coordination primitives.
    pub(crate) fn new() -> Self {
        Self {
            cancellation_token: CancellationToken::new(),
            task_tracker: TaskTracker::new(),
        }
    }

    /// Returns a clone of the shared worker cancellation token.
    pub(crate) fn cancellation_token(&self) -> CancellationToken {
        self.cancellation_token.clone()
    }

    /// Requests background workers to stop and waits for them.
    pub(crate) async fn shutdown(self) {
        // Prevent new tasks from joining the tracked set
        self.task_tracker.close();

        // Request graceful cancellation from every worker
        self.cancellation_token.cancel();

        // Wait for all tracked workers to finish their shutdown paths
        self.task_tracker.wait().await;
    }

    /// Spawns a task tracked for graceful shutdown.
    pub(crate) fn spawn<Task>(&self, task: Task)
    where
        Task: Future<Output = ()> + Send + 'static,
    {
        self.task_tracker.spawn(task);
    }
}

/// Directs the shared worker driver after one iteration.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum WorkerIteration {
    /// Starts the next iteration immediately.
    Continue,
    /// Waits for the specified duration before the next iteration.
    Pause(Duration),
}
