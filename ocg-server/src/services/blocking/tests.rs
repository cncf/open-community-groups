use std::{
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
        mpsc,
    },
    time::Duration,
};

use tokio::time::{sleep, timeout};

use super::BlockingExecutor;

#[test]
fn test_new_clamps_zero_bound_to_one() {
    let executor = BlockingExecutor::new(0);

    assert_eq!(executor.available_permits(), 1);
}

#[tokio::test]
async fn test_run_keeps_async_work_responsive_during_a_blocking_burst() {
    // Setup a single-permit executor and hold that permit with blocked work
    let executor = BlockingExecutor::new(1);
    let (release, gate) = mpsc::channel::<()>();
    let gate = Arc::new(Mutex::new(gate));
    let mut burst = Vec::new();
    for _ in 0..5 {
        let executor = executor.clone();
        let gate = gate.clone();
        burst.push(tokio::spawn(async move {
            executor
                .run(move || {
                    // Block this thread until the test releases it
                    gate.lock().unwrap().recv().unwrap();
                })
                .await
        }));
    }

    // Run unrelated async work while the burst is pending
    let unrelated = timeout(Duration::from_secs(5), sleep(Duration::from_millis(10))).await;

    // Check the async work completed and the executor still holds its bound
    assert!(unrelated.is_ok());
    assert_eq!(executor.available_permits(), 0);

    // Release the burst and check every closure ran
    for _ in 0..5 {
        release.send(()).unwrap();
    }
    for task in burst {
        task.await.unwrap().unwrap();
    }
}

#[tokio::test]
async fn test_run_limits_concurrent_work_to_the_configured_bound() {
    // Setup a two-permit executor and counters observed from the blocking closures
    let executor = BlockingExecutor::new(2);
    let in_flight = Arc::new(AtomicUsize::new(0));
    let max_in_flight = Arc::new(AtomicUsize::new(0));
    let (release, gate) = mpsc::channel::<()>();
    let gate = Arc::new(Mutex::new(gate));

    // Start three closures that block until released
    let mut tasks = Vec::new();
    for _ in 0..3 {
        let executor = executor.clone();
        let gate = gate.clone();
        let in_flight = in_flight.clone();
        let max_in_flight = max_in_flight.clone();
        tasks.push(tokio::spawn(async move {
            executor
                .run(move || {
                    // Record the concurrency observed while this closure runs
                    let running = in_flight.fetch_add(1, Ordering::SeqCst) + 1;
                    max_in_flight.fetch_max(running, Ordering::SeqCst);
                    gate.lock().unwrap().recv().unwrap();
                    in_flight.fetch_sub(1, Ordering::SeqCst);
                })
                .await
        }));
    }

    // Wait until the bound is reached and check the third closure is still waiting
    wait_until(|| in_flight.load(Ordering::SeqCst) == 2).await;
    sleep(Duration::from_millis(50)).await;
    assert_eq!(in_flight.load(Ordering::SeqCst), 2);
    assert_eq!(executor.available_permits(), 0);

    // Release every closure and wait for the burst to finish
    for _ in 0..3 {
        release.send(()).unwrap();
    }
    for task in tasks {
        task.await.unwrap().unwrap();
    }

    // Check the bound held for the whole burst and the permits were returned
    assert_eq!(max_in_flight.load(Ordering::SeqCst), 2);
    assert_eq!(executor.available_permits(), 2);
}

#[tokio::test]
async fn test_run_reports_panicking_work_as_an_error() {
    // Setup a single-permit executor
    let executor = BlockingExecutor::new(1);

    // Run work that panics
    let result: anyhow::Result<()> = executor.run(|| panic!("boom")).await;

    // Check the panic surfaces as an error and the permit is released
    assert_eq!(
        result.unwrap_err().to_string(),
        "error running blocking work"
    );
    assert_eq!(executor.available_permits(), 1);
}

#[tokio::test]
async fn test_run_returns_the_work_output() {
    // Setup a single-permit executor
    let executor = BlockingExecutor::new(1);

    // Run work that produces a value
    let output = executor.run(|| 21 * 2).await.unwrap();

    // Check the value is returned and the permit is released
    assert_eq!(output, 42);
    assert_eq!(executor.available_permits(), 1);
}

// Helpers.

/// Polls `condition` until it holds, failing the test after five seconds.
async fn wait_until(condition: impl Fn() -> bool) {
    timeout(Duration::from_secs(5), async {
        while !condition() {
            sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .expect("condition to hold within the wait budget");
}
