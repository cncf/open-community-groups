//! Runtime helpers shared by the OCG binaries.

use tokio::signal;
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

/// Returns a future that completes when the program receives a shutdown signal.
///
/// Handles both ctrl+c and terminate signals for graceful shutdown.
///
/// # Panics
///
/// Panics when a signal handler cannot be installed.
pub async fn shutdown_signal() {
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
        () = ctrl_c => {},
        () = terminate => {},
    }
}
