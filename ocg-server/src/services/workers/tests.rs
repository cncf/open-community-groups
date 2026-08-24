use std::{
    future::ready,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicUsize, Ordering},
    },
    time::Duration,
};

use tokio::{sync::Notify, time::timeout};
use tokio_util::sync::CancellationToken;

use super::{BackgroundTasks, WorkerIteration, run_worker};

#[tokio::test]
async fn test_background_tasks_shutdown_cancels_and_waits() {
    // Setup tracked work that completes only after cancellation
    let background_tasks = BackgroundTasks::new();
    let cancellation_token = background_tasks.cancellation_token();
    let task_completed = Arc::new(AtomicBool::new(false));
    let task_completed_for_worker = task_completed.clone();
    background_tasks.spawn(async move {
        cancellation_token.cancelled().await;
        task_completed_for_worker.store(true, Ordering::SeqCst);
    });

    // Request shutdown and wait for the tracked worker
    timeout(Duration::from_secs(1), background_tasks.shutdown())
        .await
        .expect("background tasks to stop promptly");

    // Check cancellation completed the tracked worker before shutdown returned
    assert!(task_completed.load(Ordering::SeqCst));
}

#[tokio::test]
async fn test_run_worker_cancellation_before_first_iteration() {
    // Setup an already canceled driver and observable callback
    let cancellation_token = CancellationToken::new();
    cancellation_token.cancel();
    let call_count = Arc::new(AtomicUsize::new(0));
    let call_count_for_iteration = call_count.clone();

    // Run the driver after cancellation
    run_worker(&cancellation_token, move || {
        call_count_for_iteration.fetch_add(1, Ordering::SeqCst);
        ready(WorkerIteration::Continue)
    })
    .await;

    // Check no iteration started
    assert_eq!(call_count.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn test_run_worker_cancellation_finishes_in_flight_iteration() {
    // Setup an iteration with explicit start and completion boundaries
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_task = cancellation_token.clone();
    let call_count = Arc::new(AtomicUsize::new(0));
    let call_count_for_iteration = call_count.clone();
    let iteration_completed = Arc::new(AtomicBool::new(false));
    let iteration_completed_for_task = iteration_completed.clone();
    let iteration_release = Arc::new(Notify::new());
    let iteration_release_for_task = iteration_release.clone();
    let iteration_started = Arc::new(Notify::new());
    let iteration_started_for_task = iteration_started.clone();
    let worker_task = tokio::spawn(async move {
        run_worker(&cancellation_token_for_task, move || {
            call_count_for_iteration.fetch_add(1, Ordering::SeqCst);
            let iteration_completed = iteration_completed_for_task.clone();
            let iteration_release = iteration_release_for_task.clone();
            let iteration_started = iteration_started_for_task.clone();
            async move {
                iteration_started.notify_one();
                iteration_release.notified().await;
                iteration_completed.store(true, Ordering::SeqCst);
                WorkerIteration::Continue
            }
        })
        .await;
    });
    iteration_started.notified().await;

    // Request shutdown while the iteration remains in flight
    cancellation_token.cancel();
    tokio::task::yield_now().await;
    assert!(!worker_task.is_finished());
    assert!(!iteration_completed.load(Ordering::SeqCst));

    // Release the iteration and wait for graceful shutdown
    iteration_release.notify_one();
    timeout(Duration::from_secs(1), worker_task)
        .await
        .expect("completed iteration to allow shutdown")
        .expect("worker driver to complete");

    // Check the iteration completed and no further work started
    assert!(iteration_completed.load(Ordering::SeqCst));
    assert_eq!(call_count.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn test_run_worker_cancellation_interrupts_pause() {
    // Setup one iteration that selects a long pause
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_task = cancellation_token.clone();
    let iteration_completed = Arc::new(Notify::new());
    let iteration_completed_for_task = iteration_completed.clone();
    let worker_task = tokio::spawn(async move {
        run_worker(&cancellation_token_for_task, move || {
            iteration_completed_for_task.notify_one();
            ready(WorkerIteration::Pause(Duration::from_hours(1)))
        })
        .await;
    });
    iteration_completed.notified().await;

    // Cancel without waiting for the selected pause
    cancellation_token.cancel();
    timeout(Duration::from_secs(1), worker_task)
        .await
        .expect("worker pause to stop promptly")
        .expect("worker driver to complete");
}

#[tokio::test]
async fn test_run_worker_cancellation_prevents_subsequent_iteration() {
    // Setup completed work that makes cancellation observable
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_iteration = cancellation_token.clone();
    let call_count = Arc::new(AtomicUsize::new(0));
    let call_count_for_iteration = call_count.clone();

    // Complete one iteration after requesting shutdown
    run_worker(&cancellation_token, move || {
        call_count_for_iteration.fetch_add(1, Ordering::SeqCst);
        cancellation_token_for_iteration.cancel();
        ready(WorkerIteration::Continue)
    })
    .await;

    // Check the post-iteration guard prevented more work
    assert_eq!(call_count.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn test_run_worker_continue_starts_next_iteration_immediately() {
    // Setup a successful iteration followed by one that cancels the driver
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_iteration = cancellation_token.clone();
    let call_count = Arc::new(AtomicUsize::new(0));
    let call_count_for_iteration = call_count.clone();

    // Run without advancing time between iterations
    timeout(
        Duration::from_secs(1),
        run_worker(&cancellation_token, move || {
            let call = call_count_for_iteration.fetch_add(1, Ordering::SeqCst);
            if call == 1 {
                cancellation_token_for_iteration.cancel();
            }
            ready(WorkerIteration::Continue)
        }),
    )
    .await
    .expect("continued iteration to run immediately");

    // Check exactly one subsequent iteration started
    assert_eq!(call_count.load(Ordering::SeqCst), 2);
}

#[tokio::test(start_paused = true)]
async fn test_run_worker_pause_waits_for_complete_duration() {
    // Setup one pause followed by cancellation from the next iteration
    let pause = Duration::from_secs(20);
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_iteration = cancellation_token.clone();
    let call_count = Arc::new(AtomicUsize::new(0));
    let call_count_for_iteration = call_count.clone();
    let first_iteration_completed = Arc::new(Notify::new());
    let first_iteration_completed_for_task = first_iteration_completed.clone();
    let worker_task = tokio::spawn(async move {
        run_worker(&cancellation_token, move || {
            let call = call_count_for_iteration.fetch_add(1, Ordering::SeqCst);
            let iteration = if call == 0 {
                first_iteration_completed_for_task.notify_one();
                WorkerIteration::Pause(pause)
            } else {
                cancellation_token_for_iteration.cancel();
                WorkerIteration::Continue
            };
            ready(iteration)
        })
        .await;
    });
    first_iteration_completed.notified().await;

    // Advance to just before the selected pause ends
    tokio::time::advance(
        pause
            .checked_sub(Duration::from_secs(1))
            .expect("worker pause to exceed one second"),
    )
    .await;
    tokio::task::yield_now().await;
    assert_eq!(call_count.load(Ordering::SeqCst), 1);

    // Finish the pause and check the next iteration begins
    tokio::time::advance(Duration::from_secs(1)).await;
    worker_task.await.expect("worker driver to stop cleanly");
    assert_eq!(call_count.load(Ordering::SeqCst), 2);
}
