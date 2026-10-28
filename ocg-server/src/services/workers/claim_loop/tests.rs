use std::{
    future::ready,
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};

use anyhow::anyhow;
use tokio::sync::Notify;
use tokio_util::sync::CancellationToken;

use super::{ClaimLoopConfig, run};

/// Cadence with distinct error and idle pauses.
const TEST_CONFIG: ClaimLoopConfig = ClaimLoopConfig {
    pause_on_error: Duration::from_secs(12),
    pause_on_none: Duration::from_secs(18),
};

#[test]
fn test_claim_loop_config_default_uses_shared_cadence() {
    let config = ClaimLoopConfig::default();

    assert_eq!(config.pause_on_error, Duration::from_secs(10));
    assert_eq!(config.pause_on_none, Duration::from_secs(15));
}

#[tokio::test(start_paused = true)]
async fn test_run_error_uses_configured_pause_and_reports_error() {
    // Fail the first claim without a reported pause override
    let reported_errors = assert_next_iteration_after(
        Err(anyhow!("claim failed")),
        None,
        TEST_CONFIG.pause_on_error,
    )
    .await;

    // Check the error reached the reporter
    assert_eq!(reported_errors, vec!["claim failed"]);
}

#[tokio::test(start_paused = true)]
async fn test_run_error_uses_reported_pause_override() {
    // Fail the first claim with a reporter-selected pause beyond the fallback
    let override_pause = Duration::from_secs(30);
    let reported_errors = assert_next_iteration_after(
        Err(anyhow!("rate limited")),
        Some(override_pause),
        override_pause,
    )
    .await;

    // Check the error reached the reporter
    assert_eq!(reported_errors, vec!["rate limited"]);
}

#[tokio::test(start_paused = true)]
async fn test_run_false_uses_idle_pause() {
    // Find no work on the first claim
    let reported_errors =
        assert_next_iteration_after(Ok(false), None, TEST_CONFIG.pause_on_none).await;

    // Check nothing was reported
    assert_eq!(reported_errors, Vec::<String>::new());
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

// Helpers.

/// Runs one claim returning `first_result` under [`TEST_CONFIG`] and checks
/// the next claim starts exactly after `expected_pause`.
///
/// The reporter returns `reported_pause` for every error. Returns the errors
/// passed to the reporter. Needs paused time.
async fn assert_next_iteration_after(
    first_result: anyhow::Result<bool>,
    reported_pause: Option<Duration>,
    expected_pause: Duration,
) -> Vec<String> {
    // Run the first claim, then cancel the loop from the second one
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_iteration = cancellation_token.clone();
    let call_count = Arc::new(AtomicUsize::new(0));
    let call_count_for_iteration = call_count.clone();
    let first_claimed = Arc::new(Notify::new());
    let first_claimed_for_iteration = first_claimed.clone();
    let mut first_result = Some(first_result);
    let reported_errors = Arc::new(Mutex::new(Vec::new()));
    let reported_errors_for_reporter = reported_errors.clone();
    let worker_task = tokio::spawn(async move {
        run(
            &cancellation_token,
            TEST_CONFIG,
            move || {
                let result = if call_count_for_iteration.fetch_add(1, Ordering::SeqCst) == 0 {
                    first_claimed_for_iteration.notify_one();
                    first_result.take().expect("first result to be used once")
                } else {
                    cancellation_token_for_iteration.cancel();
                    Ok(false)
                };
                ready(result)
            },
            move |err| {
                reported_errors_for_reporter
                    .lock()
                    .expect("reported errors to remain available")
                    .push(err.to_string());
                reported_pause
            },
        )
        .await;
    });
    first_claimed.notified().await;

    // Check the loop stays paused until just before the expected pause ends
    tokio::time::advance(
        expected_pause
            .checked_sub(Duration::from_secs(1))
            .expect("expected pause to exceed one second"),
    )
    .await;
    tokio::task::yield_now().await;
    assert_eq!(call_count.load(Ordering::SeqCst), 1);

    // Check the next claim starts once the pause ends
    tokio::time::advance(Duration::from_secs(1)).await;
    tokio::task::yield_now().await;
    assert_eq!(call_count.load(Ordering::SeqCst), 2);
    worker_task.await.expect("claim loop to stop cleanly");

    reported_errors
        .lock()
        .expect("reported errors to remain available")
        .clone()
}
