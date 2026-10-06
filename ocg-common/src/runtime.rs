//! Runtime helpers shared by the OCG binaries.

use std::time::Duration;

use tokio::{signal, time::sleep};
use tokio_util::sync::CancellationToken;
use tracing::info;
use tracing_subscriber::EnvFilter;

use crate::config::LogFormat;

/// Configures tracing based on the configured log format.
///
/// The default filter directive is used when the `RUST_LOG` environment
/// variable is not set (e.g. `my_crate=debug`).
pub fn setup_logging(log_format: &LogFormat, default_filter_directive: &str) {
    // Build the shared subscriber configuration first
    let ts = tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new(default_filter_directive)),
        )
        .with_file(true)
        .with_line_number(true);

    // Select the configured output formatter
    match log_format {
        LogFormat::Json => ts.json().init(),
        LogFormat::Pretty => ts.init(),
    }
}

// Shutdown.

/// Time a server keeps serving requests after it starts failing health checks.
///
/// Load balancers stop routing new requests to an instance only after a few
/// failed health checks, so the delay must exceed that detection window.
const SHUTDOWN_DRAIN_DELAY: Duration = Duration::from_secs(15);

/// Signal that asked the program to shut down.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ShutdownSignal {
    /// Interactive interrupt, such as ctrl+c in a terminal.
    CtrlC,
    /// Terminate signal, such as the one sent by Kubernetes before stopping a pod.
    Terminate,
}

/// Fails health checks and waits for the drain delay when the server is terminated.
async fn drain_before_shutdown(signal: ShutdownSignal, shutdown_drain: &CancellationToken) {
    // Stop immediately on interactive interrupts
    if signal != ShutdownSignal::Terminate {
        return;
    }

    // Fail health checks while still serving so load balancers drop this instance first
    shutdown_drain.cancel();
    info!(
        delay_secs = SHUTDOWN_DRAIN_DELAY.as_secs(),
        "draining traffic before shutdown"
    );
    sleep(SHUTDOWN_DRAIN_DELAY).await;
}

/// Waits for a shutdown signal, draining load balancer traffic first on terminate.
///
/// A terminate signal cancels `shutdown_drain`, which the server's health check
/// reports as unavailable while requests are still served, and then waits for
/// the drain delay so load balancers stop routing new requests before the
/// server stops. An interactive interrupt stops immediately.
///
/// # Panics
///
/// Panics when a signal handler cannot be installed.
pub async fn shutdown_signal_with_drain(shutdown_drain: CancellationToken) {
    let signal = wait_for_shutdown_signal().await;
    drain_before_shutdown(signal, &shutdown_drain).await;
}

/// Waits for a shutdown signal and returns which one was received.
async fn wait_for_shutdown_signal() -> ShutdownSignal {
    // Setup ctrl+c signal handler
    let ctrl_c = async {
        signal::ctrl_c()
            .await
            .expect("failed to install ctrl+c signal handler");
    };

    #[cfg(unix)]
    // Setup terminate signal handler (Unix only)
    let terminate = async {
        signal::unix::signal(signal::unix::SignalKind::terminate())
            .expect("failed to install terminate signal handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    // Wait for either ctrl+c or terminate signal
    tokio::select! {
        () = ctrl_c => ShutdownSignal::CtrlC,
        () = terminate => ShutdownSignal::Terminate,
    }
}

#[cfg(test)]
mod tests {
    use tokio::time::Instant;

    use super::*;

    #[tokio::test(start_paused = true)]
    async fn test_drain_before_shutdown_returns_immediately_on_ctrl_c() {
        // Setup drain token and start time
        let shutdown_drain = CancellationToken::new();
        let started_at = Instant::now();

        // Run drain for an interactive interrupt
        drain_before_shutdown(ShutdownSignal::CtrlC, &shutdown_drain).await;

        // Check the server stops without draining
        assert!(!shutdown_drain.is_cancelled());
        assert_eq!(started_at.elapsed(), Duration::ZERO);
    }

    #[tokio::test(start_paused = true)]
    async fn test_drain_before_shutdown_waits_after_failing_health_checks_on_terminate() {
        // Setup drain token and start time
        let shutdown_drain = CancellationToken::new();
        let started_at = Instant::now();

        // Run drain for a terminate signal
        drain_before_shutdown(ShutdownSignal::Terminate, &shutdown_drain).await;

        // Check health checks fail and the drain delay elapses before stopping
        assert!(shutdown_drain.is_cancelled());
        assert_eq!(started_at.elapsed(), SHUTDOWN_DRAIN_DELAY);
    }
}
