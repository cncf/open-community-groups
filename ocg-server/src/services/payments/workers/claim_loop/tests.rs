use std::{
    future::{pending, ready},
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};

use anyhow::{Result, anyhow};
use tokio::{sync::Notify, time::timeout};
use tokio_util::sync::CancellationToken;

use super::{PAUSE_ON_ERROR, PAUSE_ON_NONE, run};

#[tokio::test]
async fn test_run_cancellation_before_first_unit() {
    // Cancel before the loop can invoke its unit of work
    let cancellation_token = CancellationToken::new();
    cancellation_token.cancel();
    let call_count = Arc::new(AtomicUsize::new(0));
    let call_count_for_work = call_count.clone();

    // Run the already canceled loop
    run(
        &cancellation_token,
        move || {
            call_count_for_work.fetch_add(1, Ordering::SeqCst);
            ready(Ok(false))
        },
        |_| {},
    )
    .await;

    // Check no unit of work started
    assert_eq!(call_count.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn test_run_cancellation_during_error_pause() {
    // Fail one unit and signal when the error pause is selected
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_task = cancellation_token.clone();
    let call_count = Arc::new(AtomicUsize::new(0));
    let call_count_for_work = call_count.clone();
    let error_reported = Arc::new(Notify::new());
    let error_reported_for_callback = error_reported.clone();
    let worker_task = tokio::spawn(async move {
        run(
            &cancellation_token_for_task,
            move || {
                call_count_for_work.fetch_add(1, Ordering::SeqCst);
                ready(Err(anyhow!("payment work failed")))
            },
            move |_| error_reported_for_callback.notify_one(),
        )
        .await;
    });
    error_reported.notified().await;

    // Cancel without waiting for the ten-second error pause
    cancellation_token.cancel();
    timeout(Duration::from_secs(1), worker_task)
        .await
        .expect("error pause to stop promptly")
        .expect("payment claim loop to complete");

    // Check cancellation prevented another unit
    assert_eq!(call_count.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn test_run_cancellation_during_idle_pause() {
    // Return one empty queue result and signal before the idle pause
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_task = cancellation_token.clone();
    let call_count = Arc::new(AtomicUsize::new(0));
    let call_count_for_work = call_count.clone();
    let work_completed = Arc::new(Notify::new());
    let work_completed_for_task = work_completed.clone();
    let worker_task = tokio::spawn(async move {
        run(
            &cancellation_token_for_task,
            move || {
                call_count_for_work.fetch_add(1, Ordering::SeqCst);
                work_completed_for_task.notify_one();
                ready(Ok(false))
            },
            |_| {},
        )
        .await;
    });
    work_completed.notified().await;

    // Cancel without waiting for the fifteen-second idle pause
    cancellation_token.cancel();
    timeout(Duration::from_secs(1), worker_task)
        .await
        .expect("idle pause to stop promptly")
        .expect("payment claim loop to complete");

    // Check cancellation prevented another unit
    assert_eq!(call_count.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn test_run_cancellation_during_unit_of_work() {
    // Hold the first unit after it starts
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_task = cancellation_token.clone();
    let call_count = Arc::new(AtomicUsize::new(0));
    let call_count_for_work = call_count.clone();
    let work_started = Arc::new(Notify::new());
    let work_started_for_task = work_started.clone();
    let worker_task = tokio::spawn(async move {
        run(
            &cancellation_token_for_task,
            move || {
                call_count_for_work.fetch_add(1, Ordering::SeqCst);
                let work_started = work_started_for_task.clone();
                async move {
                    work_started.notify_one();
                    pending::<Result<bool>>().await
                }
            },
            |_| {},
        )
        .await;
    });
    work_started.notified().await;

    // Cancel and require the in-flight future to be dropped
    cancellation_token.cancel();
    timeout(Duration::from_secs(1), worker_task)
        .await
        .expect("in-flight unit to stop promptly")
        .expect("payment claim loop to complete");

    // Check cancellation did not start another unit
    assert_eq!(call_count.load(Ordering::SeqCst), 1);
}

#[tokio::test(start_paused = true)]
async fn test_run_error_pause_and_callback() {
    // Fail once, then cancel from the next unit after the error pause
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_work = cancellation_token.clone();
    let call_count = Arc::new(AtomicUsize::new(0));
    let call_count_for_work = call_count.clone();
    let errors = Arc::new(Mutex::new(Vec::new()));
    let errors_for_callback = errors.clone();
    let error_reported = Arc::new(Notify::new());
    let error_reported_for_callback = error_reported.clone();
    let worker_task = tokio::spawn(async move {
        run(
            &cancellation_token,
            move || {
                let call = call_count_for_work.fetch_add(1, Ordering::SeqCst);
                if call == 0 {
                    ready(Err(anyhow!("payment work failed")))
                } else {
                    cancellation_token_for_work.cancel();
                    ready(Ok(false))
                }
            },
            move |err| {
                errors_for_callback
                    .lock()
                    .expect("error records to remain available")
                    .push(err.to_string());
                error_reported_for_callback.notify_one();
            },
        )
        .await;
    });
    error_reported.notified().await;

    // Keep the loop paused until the full error delay elapses
    tokio::time::advance(
        PAUSE_ON_ERROR
            .checked_sub(Duration::from_secs(1))
            .expect("error pause to exceed one second"),
    )
    .await;
    tokio::task::yield_now().await;
    assert_eq!(call_count.load(Ordering::SeqCst), 1);
    tokio::time::advance(Duration::from_secs(1)).await;
    worker_task
        .await
        .expect("payment claim loop to stop after the second unit");

    // Check the callback received the domain error exactly once
    assert_eq!(call_count.load(Ordering::SeqCst), 2);
    assert_eq!(
        *errors.lock().expect("error records to remain available"),
        vec!["payment work failed"]
    );
}

#[tokio::test(start_paused = true)]
async fn test_run_idle_pause() {
    // Return one empty result, then cancel from the next unit
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_work = cancellation_token.clone();
    let call_count = Arc::new(AtomicUsize::new(0));
    let call_count_for_work = call_count.clone();
    let work_completed = Arc::new(Notify::new());
    let work_completed_for_task = work_completed.clone();
    let worker_task = tokio::spawn(async move {
        run(
            &cancellation_token,
            move || {
                let call = call_count_for_work.fetch_add(1, Ordering::SeqCst);
                if call == 0 {
                    work_completed_for_task.notify_one();
                    ready(Ok(false))
                } else {
                    cancellation_token_for_work.cancel();
                    ready(Ok(false))
                }
            },
            |_| {},
        )
        .await;
    });
    work_completed.notified().await;

    // Keep the loop paused until the full idle delay elapses
    tokio::time::advance(
        PAUSE_ON_NONE
            .checked_sub(Duration::from_secs(1))
            .expect("idle pause to exceed one second"),
    )
    .await;
    tokio::task::yield_now().await;
    assert_eq!(call_count.load(Ordering::SeqCst), 1);
    tokio::time::advance(Duration::from_secs(1)).await;
    worker_task
        .await
        .expect("payment claim loop to stop after the second unit");

    // Check the next unit started only after the configured pause
    assert_eq!(call_count.load(Ordering::SeqCst), 2);
}

#[tokio::test]
async fn test_run_immediately_continues_after_work() {
    // Complete one unit and cancel from the immediate next unit
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_work = cancellation_token.clone();
    let call_count = Arc::new(AtomicUsize::new(0));
    let call_count_for_work = call_count.clone();

    // Run without advancing time between successful units
    timeout(
        Duration::from_secs(1),
        run(
            &cancellation_token,
            move || {
                let call = call_count_for_work.fetch_add(1, Ordering::SeqCst);
                if call == 0 {
                    ready(Ok(true))
                } else {
                    cancellation_token_for_work.cancel();
                    ready(Ok(false))
                }
            },
            |_| {},
        ),
    )
    .await
    .expect("completed work to continue without a pause");

    // Check the next unit started immediately
    assert_eq!(call_count.load(Ordering::SeqCst), 2);
}

#[tokio::test]
async fn test_run_prevents_another_unit_after_cancellation_race() {
    // Cancel while the first successful unit completes
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_work = cancellation_token.clone();
    let call_count = Arc::new(AtomicUsize::new(0));
    let call_count_for_work = call_count.clone();

    // Complete the unit after making cancellation observable
    run(
        &cancellation_token,
        move || {
            call_count_for_work.fetch_add(1, Ordering::SeqCst);
            let cancellation_token = cancellation_token_for_work.clone();
            async move {
                cancellation_token.cancel();
                Ok(true)
            }
        },
        |_| {},
    )
    .await;

    // Check the post-iteration guard prevented another claim
    assert_eq!(call_count.load(Ordering::SeqCst), 1);
}
