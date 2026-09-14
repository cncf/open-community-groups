//! Shared helpers for background worker services.

use std::{
    any::Any,
    collections::BTreeMap,
    future::Future,
    sync::{Arc, Mutex, PoisonError},
    time::Duration,
};

use tokio::{
    task::{AbortHandle, JoinError, JoinHandle},
    time::{sleep, timeout},
};
use tokio_util::{sync::CancellationToken, task::TaskTracker};
use tracing::{error, warn};

pub(crate) mod claim_loop;
pub(crate) mod queue_health;

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
///
/// Every worker is spawned under a name and observed: a panic or a return
/// before cancellation is logged and recorded in the shared
/// [`WorkerRegistry`]. Shutdown is bounded: workers get the
/// configured grace period to finish their in-flight unit, after which the
/// remaining tasks are aborted. Jobs left in a claimed state by an aborted
/// worker are recovered by the existing stale-claim recovery workers on the
/// next start.
pub(crate) struct BackgroundTasks {
    /// Token used to request worker cancellation.
    cancellation_token: CancellationToken,
    /// Observed state of every spawned worker.
    registry: WorkerRegistry,
    /// Time granted to workers to stop after cancellation before being aborted.
    shutdown_grace_period: Duration,
    /// Tracker used to await worker completion.
    task_tracker: TaskTracker,
    /// Handles of the spawned workers, used to abort stalled ones.
    workers: Mutex<Vec<WorkerHandle>>,
}

impl BackgroundTasks {
    /// Creates background task coordination primitives.
    pub(crate) fn new(shutdown_grace_period: Duration) -> Self {
        Self {
            cancellation_token: CancellationToken::new(),
            registry: WorkerRegistry::new(),
            shutdown_grace_period,
            task_tracker: TaskTracker::new(),
            workers: Mutex::new(Vec::new()),
        }
    }

    /// Returns a clone of the shared worker cancellation token.
    pub(crate) fn cancellation_token(&self) -> CancellationToken {
        self.cancellation_token.clone()
    }

    /// Returns the shared registry observing worker exits.
    pub(crate) fn registry(&self) -> WorkerRegistry {
        self.registry.clone()
    }

    /// Requests background workers to stop and waits for them within the grace period.
    ///
    /// Workers still running when the grace period expires are aborted.
    pub(crate) async fn shutdown(self) {
        // Prevent new tasks from joining the tracked set
        self.task_tracker.close();

        // Request graceful cancellation from every worker
        self.cancellation_token.cancel();

        // Wait for the workers to finish their shutdown paths within the grace period
        if timeout(self.shutdown_grace_period, self.task_tracker.wait())
            .await
            .is_ok()
        {
            return;
        }

        // Abort the workers that did not stop in time and wait for them to unwind
        let workers =
            std::mem::take(&mut *self.workers.lock().unwrap_or_else(PoisonError::into_inner));
        let stalled_workers = workers.iter().filter(|worker| !worker.monitor.is_finished()).count();
        warn!(
            stalled_workers,
            grace_period_secs = self.shutdown_grace_period.as_secs(),
            "background workers did not stop within the grace period; aborting them"
        );
        for worker in &workers {
            worker.task.abort();
        }
        self.task_tracker.wait().await;
    }

    /// Spawns a named worker tracked for graceful shutdown and exit observation.
    ///
    /// The worker runs as its own task; a monitor task tracked for shutdown
    /// awaits it and records how it ended. A return before cancellation and a
    /// panic are unexpected exits; a return after cancellation and an abort
    /// during shutdown are expected stops.
    pub(crate) fn spawn<Task>(&self, name: &'static str, task: Task)
    where
        Task: Future<Output = ()> + Send + 'static,
    {
        // Register the worker before it can exit
        self.registry.register(name);

        // Run the worker and observe its exit from a tracked monitor
        let cancellation_token = self.cancellation_token.clone();
        let registry = self.registry.clone();
        let task = tokio::spawn(task);
        let abort_handle = task.abort_handle();
        let monitor = self.task_tracker.spawn(async move {
            let exit = match task.await {
                Ok(()) if cancellation_token.is_cancelled() => WorkerExit::Stopped,
                Ok(()) => WorkerExit::ReturnedEarly,
                Err(err) if err.is_panic() => WorkerExit::Panicked(panic_message(err)),
                Err(_) => WorkerExit::Stopped,
            };
            registry.record_exit(name, exit);
        });

        // Keep the handles so a stalled worker can be aborted on shutdown
        self.workers
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .push(WorkerHandle {
                monitor,
                task: abort_handle,
            });
    }
}

/// Observed state of the background workers.
#[derive(Clone, Default)]
pub(crate) struct WorkerRegistry {
    /// State of every registered worker, keyed by name.
    workers: Arc<Mutex<BTreeMap<&'static str, WorkerState>>>,
}

impl WorkerRegistry {
    /// Creates an empty registry.
    pub(crate) fn new() -> Self {
        Self::default()
    }

    /// Returns a snapshot of every registered worker, keyed by name.
    pub(crate) fn snapshot(&self) -> BTreeMap<&'static str, WorkerStatus> {
        let workers = self.workers.lock().unwrap_or_else(PoisonError::into_inner);
        workers
            .iter()
            .map(|(name, state)| {
                (
                    *name,
                    WorkerStatus {
                        running: state.running,
                        unexpected_exits: state.unexpected_exits.clone(),
                    },
                )
            })
            .collect()
    }

    /// Records how a running worker ended, logging unexpected exits.
    fn record_exit(&self, name: &'static str, exit: WorkerExit) {
        // Log unexpected exits where they gain operational meaning
        match &exit {
            WorkerExit::Panicked(message) => {
                error!(worker = name, panic = %message, "background worker panicked");
            }
            WorkerExit::ReturnedEarly => {
                warn!(worker = name, "background worker stopped before shutdown");
            }
            WorkerExit::Stopped => {}
        }

        // Update the worker state
        let mut workers = self.workers.lock().unwrap_or_else(PoisonError::into_inner);
        let state = workers.entry(name).or_default();
        state.running = state.running.saturating_sub(1);
        if exit != WorkerExit::Stopped {
            state.unexpected_exits.push(exit);
        }
    }

    /// Registers one running instance of the named worker.
    fn register(&self, name: &'static str) {
        let mut workers = self.workers.lock().unwrap_or_else(PoisonError::into_inner);
        workers.entry(name).or_default().running += 1;
    }
}

/// How a worker task ended.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) enum WorkerExit {
    /// The task panicked; carries the panic message.
    Panicked(String),
    /// The task returned before shutdown was requested.
    ReturnedEarly,
    /// The task returned after cancellation or was aborted during shutdown.
    Stopped,
}

/// Handles kept for a spawned worker.
struct WorkerHandle {
    /// Tracked monitor that records the worker's exit.
    monitor: JoinHandle<()>,
    /// Handle used to abort the worker task itself.
    task: AbortHandle,
}

/// Registered state of one named worker, covering all of its instances.
#[derive(Debug, Default)]
struct WorkerState {
    /// Instances currently running.
    running: usize,
    /// Unexpected exits recorded since the process started.
    unexpected_exits: Vec<WorkerExit>,
}

/// Snapshot of one named worker.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct WorkerStatus {
    /// Instances currently running.
    pub running: usize,
    /// Unexpected exits recorded since the process started.
    pub unexpected_exits: Vec<WorkerExit>,
}

/// Directs the shared worker driver after one iteration.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum WorkerIteration {
    /// Starts the next iteration immediately.
    Continue,
    /// Waits for the specified duration before the next iteration.
    Pause(Duration),
}

/// Extracts a readable message from a panicked task's join error.
fn panic_message(err: JoinError) -> String {
    let payload: Box<dyn Any + Send> = err.into_panic();
    if let Some(message) = payload.downcast_ref::<&str>() {
        (*message).to_string()
    } else if let Some(message) = payload.downcast_ref::<String>() {
        message.clone()
    } else {
        "unknown panic payload".to_string()
    }
}
