use std::{
    future::ready,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicUsize, Ordering},
    },
    time::Duration,
};

use anyhow::anyhow;
use tokio::{sync::Notify, time::timeout};
use tokio_util::sync::CancellationToken;

use super::{ClaimLoopConfig, run};

#[test]
fn test_claim_loop_config_default_uses_shared_cadence() {
    let config = ClaimLoopConfig::default();

    assert_eq!(config.pause_on_error, Duration::from_secs(10));
    assert_eq!(config.pause_on_none, Duration::from_secs(15));
}

#[tokio::test]
async fn test_run_cancellation_waits_for_in_flight_work() {
    // Setup work with explicit start and completion boundaries
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_task = cancellation_token.clone();
    let call_count = Arc::new(AtomicUsize::new(0));
    let call_count_for_work = call_count.clone();
    let work_completed = Arc::new(AtomicBool::new(false));
    let work_completed_for_task = work_completed.clone();
    let work_release = Arc::new(Notify::new());
    let work_release_for_task = work_release.clone();
    let work_started = Arc::new(Notify::new());
    let work_started_for_task = work_started.clone();
    let worker_task = tokio::spawn(async move {
        run(
            &cancellation_token_for_task,
            ClaimLoopConfig::default(),
            move || {
                call_count_for_work.fetch_add(1, Ordering::SeqCst);
                let work_completed = work_completed_for_task.clone();
                let work_release = work_release_for_task.clone();
                let work_started = work_started_for_task.clone();
                async move {
                    work_started.notify_one();
                    work_release.notified().await;
                    work_completed.store(true, Ordering::SeqCst);
                    Ok::<_, anyhow::Error>(true)
                }
            },
            |_| None,
        )
        .await;
    });
    work_started.notified().await;

    // Request shutdown while the claim workflow remains in flight
    cancellation_token.cancel();
    tokio::task::yield_now().await;
    assert!(!worker_task.is_finished());
    assert!(!work_completed.load(Ordering::SeqCst));

    // Complete the work and wait for graceful shutdown
    work_release.notify_one();
    timeout(Duration::from_secs(1), worker_task)
        .await
        .expect("completed claim workflow to allow shutdown")
        .expect("claim loop to stop cleanly");

    // Check the in-flight work completed without another claim attempt
    assert!(work_completed.load(Ordering::SeqCst));
    assert_eq!(call_count.load(Ordering::SeqCst), 1);
}

#[tokio::test(start_paused = true)]
async fn test_run_error_uses_configured_pause_and_reports_error() {
    // Setup one failure followed by cancellation from the next iteration
    let config = ClaimLoopConfig {
        pause_on_error: Duration::from_secs(12),
        pause_on_none: Duration::from_secs(18),
    };
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_iteration = cancellation_token.clone();
    let call_count = Arc::new(AtomicUsize::new(0));
    let call_count_for_iteration = call_count.clone();
    let errors = Arc::new(Mutex::new(Vec::new()));
    let errors_for_reporter = errors.clone();
    let error_reported = Arc::new(Notify::new());
    let error_reported_for_reporter = error_reported.clone();
    let worker_task = tokio::spawn(async move {
        run(
            &cancellation_token,
            config,
            move || {
                let call = call_count_for_iteration.fetch_add(1, Ordering::SeqCst);
                if call == 0 {
                    ready(Err(anyhow!("claim failed")))
                } else {
                    cancellation_token_for_iteration.cancel();
                    ready(Ok(false))
                }
            },
            move |err| {
                errors_for_reporter
                    .lock()
                    .expect("error records to remain available")
                    .push(err.to_string());
                error_reported_for_reporter.notify_one();
                None
            },
        )
        .await;
    });
    error_reported.notified().await;

    // Keep the loop paused until the configured error delay elapses
    tokio::time::advance(
        config
            .pause_on_error
            .checked_sub(Duration::from_secs(1))
            .expect("error pause to exceed one second"),
    )
    .await;
    tokio::task::yield_now().await;
    assert_eq!(call_count.load(Ordering::SeqCst), 1);
    tokio::time::advance(Duration::from_secs(1)).await;
    worker_task.await.expect("claim loop to stop cleanly");

    // Check the error boundary and next iteration
    assert_eq!(call_count.load(Ordering::SeqCst), 2);
    assert_eq!(
        *errors.lock().expect("error records to remain available"),
        vec!["claim failed"]
    );
}

#[tokio::test(start_paused = true)]
async fn test_run_error_uses_reported_pause_override() {
    // Setup a provider-selected error pause followed by cancellation
    let config = ClaimLoopConfig {
        pause_on_error: Duration::from_secs(12),
        pause_on_none: Duration::from_secs(18),
    };
    let override_pause = Duration::from_secs(30);
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_iteration = cancellation_token.clone();
    let call_count = Arc::new(AtomicUsize::new(0));
    let call_count_for_iteration = call_count.clone();
    let error_reported = Arc::new(Notify::new());
    let error_reported_for_reporter = error_reported.clone();
    let worker_task = tokio::spawn(async move {
        run(
            &cancellation_token,
            config,
            move || {
                let call = call_count_for_iteration.fetch_add(1, Ordering::SeqCst);
                if call == 0 {
                    ready(Err(anyhow!("rate limited")))
                } else {
                    cancellation_token_for_iteration.cancel();
                    ready(Ok(false))
                }
            },
            move |_| {
                error_reported_for_reporter.notify_one();
                Some(override_pause)
            },
        )
        .await;
    });
    error_reported.notified().await;

    // Advance beyond the fallback while remaining inside the override
    tokio::time::advance(config.pause_on_error).await;
    tokio::task::yield_now().await;
    assert_eq!(call_count.load(Ordering::SeqCst), 1);
    tokio::time::advance(
        override_pause
            .checked_sub(config.pause_on_error)
            .expect("override pause to exceed fallback pause"),
    )
    .await;

    // Check the provider-selected pause controls the next iteration
    worker_task.await.expect("claim loop to stop cleanly");
    assert_eq!(call_count.load(Ordering::SeqCst), 2);
}

#[tokio::test(start_paused = true)]
async fn test_run_false_uses_idle_pause() {
    // Setup one idle result followed by cancellation from the next iteration
    let config = ClaimLoopConfig {
        pause_on_error: Duration::from_secs(12),
        pause_on_none: Duration::from_secs(18),
    };
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_iteration = cancellation_token.clone();
    let call_count = Arc::new(AtomicUsize::new(0));
    let call_count_for_iteration = call_count.clone();
    let iteration_completed = Arc::new(Notify::new());
    let iteration_completed_for_task = iteration_completed.clone();
    let worker_task = tokio::spawn(async move {
        run(
            &cancellation_token,
            config,
            move || {
                let call = call_count_for_iteration.fetch_add(1, Ordering::SeqCst);
                if call == 0 {
                    iteration_completed_for_task.notify_one();
                } else {
                    cancellation_token_for_iteration.cancel();
                }
                ready(Ok::<_, anyhow::Error>(false))
            },
            |_| None,
        )
        .await;
    });
    iteration_completed.notified().await;

    // Keep the loop paused until the configured idle delay elapses
    tokio::time::advance(
        config
            .pause_on_none
            .checked_sub(Duration::from_secs(1))
            .expect("idle pause to exceed one second"),
    )
    .await;
    tokio::task::yield_now().await;
    assert_eq!(call_count.load(Ordering::SeqCst), 1);
    tokio::time::advance(Duration::from_secs(1)).await;

    // Check the next iteration starts only after the idle pause
    worker_task.await.expect("claim loop to stop cleanly");
    assert_eq!(call_count.load(Ordering::SeqCst), 2);
}

#[tokio::test]
async fn test_run_true_continues_immediately() {
    // Setup completed work followed by a cancellation iteration
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_iteration = cancellation_token.clone();
    let call_count = Arc::new(AtomicUsize::new(0));
    let call_count_for_iteration = call_count.clone();

    // Run without advancing time between successful iterations
    run(
        &cancellation_token,
        ClaimLoopConfig::default(),
        move || {
            let call = call_count_for_iteration.fetch_add(1, Ordering::SeqCst);
            if call == 0 {
                ready(Ok::<_, anyhow::Error>(true))
            } else {
                cancellation_token_for_iteration.cancel();
                ready(Ok(false))
            }
        },
        |_| None,
    )
    .await;

    // Check a second iteration started without a pause
    assert_eq!(call_count.load(Ordering::SeqCst), 2);
}
