//! Open Community Groups redirector.
//!
//! This service handles permanent redirects from community-specific legacy URLs
//! to their canonical pages in Open Community Groups.

#![warn(clippy::all, clippy::pedantic)]
#![allow(clippy::struct_field_names)]

use std::{future::Future, path::PathBuf, sync::Arc, time::Duration};

use anyhow::{Context, Result};
use clap::Parser;
use ocg_common::{
    db::{create_pool, tls_connector},
    runtime::{setup_logging, shutdown_signal_with_drain},
};
use tokio::{net::TcpListener, sync::RwLock, task::JoinHandle, time};
use tokio_util::sync::CancellationToken;
use tracing::{error, info};

use crate::{
    config::{Config, HttpServerConfig},
    db::PgDB,
};

/// Application configuration management.
mod config;
/// Database abstraction layer and operations.
mod db;
/// HTTP router configuration and setup.
mod router;

/// Default maximum number of database connections in the redirector pool.
const DB_POOL_MAX_SIZE: usize = 4;

/// How often redirect mappings are refreshed from the database.
const REDIRECT_REFRESH_INTERVAL: Duration = Duration::from_hours(1);

/// Command-line arguments for the application.
#[derive(Debug, Parser)]
#[clap(author, version, about)]
struct Args {
    /// Path to the configuration file.
    #[clap(short, long)]
    config_file: Option<PathBuf>,
}

/// Main entry point for the application.
#[tokio::main]
async fn main() -> Result<()> {
    // Load configuration and initialize logging
    let cfg = setup_config()?;
    setup_logging(
        &cfg.log.format,
        &format!("{}=debug", env!("CARGO_CRATE_NAME")),
    );

    // Setup the database connection used to load redirect mappings
    let db = setup_db(&cfg)?;

    // Serve HTTP requests until a shutdown signal is received
    run_server(db, &cfg.server).await?;

    Ok(())
}

/// Periodically refreshes redirect mappings until cancelled.
async fn run_redirect_refresh<F, Fut>(
    mut load_redirects: F,
    redirects: Arc<RwLock<router::Redirects>>,
    interval: Duration,
    cancellation_token: CancellationToken,
) where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<router::Redirects>>,
{
    loop {
        // Wait for the next refresh interval or stop immediately on shutdown
        tokio::select! {
            biased;
            () = cancellation_token.cancelled() => break,
            () = time::sleep(interval) => {}
        }

        // Reload redirect mappings unless shutdown interrupts the read
        let refreshed = tokio::select! {
            biased;
            () = cancellation_token.cancelled() => break,
            result = load_redirects() => result,
        };

        // Swap in the refreshed map or keep serving the previous snapshot
        match refreshed {
            Ok(refreshed_redirects) => {
                *redirects.write().await = refreshed_redirects;
                info!("redirect mappings refreshed");
            }
            Err(err) => {
                error!(
                    error = %format_args!("{err:#}"),
                    "failed to refresh redirect mappings"
                );
            }
        }
    }
}

/// Build the router and serve HTTP requests until shutdown.
async fn run_server(db: PgDB, server_cfg: &HttpServerConfig) -> Result<()> {
    // Load redirects and bind the TCP listener before starting background refresh
    let redirects = Arc::new(RwLock::new(db.load_redirects().await?));
    let shutdown_drain = CancellationToken::new();
    let router = router::setup(redirects.clone(), server_cfg, shutdown_drain.clone());
    let listener = TcpListener::bind(&server_cfg.addr).await?;

    // Start periodic redirect refreshes that stop when the server shuts down
    let refresh_shutdown = CancellationToken::new();
    let refresh_handle = spawn_redirect_refresh(db, redirects, refresh_shutdown.clone());

    // Serve requests until a graceful shutdown signal arrives
    info!("server started");
    info!(%server_cfg.addr, "listening");

    let serve_result = axum::serve(listener, router)
        .with_graceful_shutdown(shutdown_signal_with_drain(shutdown_drain))
        .await;

    // Cancel and await the redirect refresh task before exiting
    refresh_shutdown.cancel();
    if let Err(err) = refresh_handle.await {
        error!(error = %err, "redirect refresh task failed");
    }

    if let Err(err) = serve_result {
        error!(error = %format_args!("{err:#}"), "server error");
        return Err(anyhow::Error::new(err));
    }

    info!("server stopped");

    Ok(())
}

/// Parse the command line arguments and load configuration.
fn setup_config() -> Result<Config> {
    let args = Args::parse();
    Config::new(args.config_file.as_ref()).context("error setting up configuration")
}

/// Configure the database pool used by the redirector.
fn setup_db(cfg: &Config) -> Result<PgDB> {
    // Build the TLS connector used by the Postgres pool
    let connector = tls_connector(cfg.db.tls.as_ref())?;

    // Create the hardened pool with the redirector's size bound
    let pool = create_pool(&cfg.db.connection, connector, DB_POOL_MAX_SIZE)?;

    Ok(PgDB::new(pool))
}

/// Spawns the periodic redirect map refresh task.
fn spawn_redirect_refresh(
    db: PgDB,
    redirects: Arc<RwLock<router::Redirects>>,
    cancellation_token: CancellationToken,
) -> JoinHandle<()> {
    tokio::spawn(async move {
        run_redirect_refresh(
            || db.load_redirects(),
            redirects,
            REDIRECT_REFRESH_INTERVAL,
            cancellation_token,
        )
        .await;
    })
}

#[cfg(test)]
mod tests {
    use std::{
        collections::HashMap,
        sync::atomic::{AtomicUsize, Ordering},
    };

    use anyhow::anyhow;
    use tokio::sync::Notify;

    use crate::router::CommunityRedirects;

    use super::*;

    #[tokio::test(start_paused = true)]
    async fn test_run_redirect_refresh_exits_promptly_when_cancelled_during_load() {
        // Setup a refresh task whose loader blocks once started
        let redirects = Arc::new(RwLock::new(router::Redirects::new()));
        let cancellation_token = CancellationToken::new();
        let started = Arc::new(Notify::new());
        let started_for_loader = started.clone();
        let handle = tokio::spawn(run_redirect_refresh(
            move || {
                let started = started_for_loader.clone();
                async move {
                    started.notify_one();
                    std::future::pending::<Result<router::Redirects>>().await
                }
            },
            redirects,
            Duration::from_secs(10),
            cancellation_token.clone(),
        ));

        // Advance time to start the refresh load, then cancel while it is pending
        time::advance(Duration::from_secs(10)).await;
        started.notified().await;
        cancellation_token.cancel();

        // Check the task finishes without waiting for the pending loader
        handle.await.unwrap();
    }

    #[tokio::test(start_paused = true)]
    async fn test_run_redirect_refresh_stops_on_cancellation_without_loading() {
        // Setup a refresh task with a long interval and a loader counter
        let calls = Arc::new(AtomicUsize::new(0));
        let calls_for_loader = calls.clone();
        let redirects = Arc::new(RwLock::new(router::Redirects::new()));
        let cancellation_token = CancellationToken::new();
        let handle = tokio::spawn(run_redirect_refresh(
            move || {
                calls_for_loader.fetch_add(1, Ordering::SeqCst);
                async { Ok(router::Redirects::new()) }
            },
            redirects,
            Duration::from_hours(1),
            cancellation_token.clone(),
        ));

        // Cancel during sleep and await task completion
        cancellation_token.cancel();
        handle.await.unwrap();

        // Check no refresh ran before exit
        assert_eq!(calls.load(Ordering::SeqCst), 0);
    }

    #[tokio::test(start_paused = true)]
    async fn test_run_redirect_refresh_swaps_map_and_preserves_last_good_on_error() {
        // Setup initial redirect state and a loader that succeeds once then errors
        let initial = HashMap::from([(
            "initial".to_string(),
            CommunityRedirects {
                redirects: HashMap::new(),

                base_legacy_url: None,
            },
        )]);
        let redirects = Arc::new(RwLock::new(initial));
        let cancellation_token = CancellationToken::new();
        let calls = Arc::new(AtomicUsize::new(0));
        let calls_for_loader = calls.clone();
        let completed = Arc::new(Notify::new());
        let completed_for_loader = completed.clone();
        let handle = tokio::spawn(run_redirect_refresh(
            move || {
                let call = calls_for_loader.fetch_add(1, Ordering::SeqCst);
                let completed = completed_for_loader.clone();
                async move {
                    let result = if call == 0 {
                        Ok(HashMap::from([(
                            "refreshed".to_string(),
                            CommunityRedirects {
                                redirects: HashMap::new(),

                                base_legacy_url: None,
                            },
                        )]))
                    } else {
                        Err(anyhow!("transient database error"))
                    };
                    completed.notify_one();
                    result
                }
            },
            redirects.clone(),
            Duration::from_secs(10),
            cancellation_token.clone(),
        ));

        // Trigger the first refresh and check the map was replaced
        time::advance(Duration::from_secs(10)).await;
        completed.notified().await;
        tokio::task::yield_now().await;
        assert!(redirects.read().await.contains_key("refreshed"));
        assert!(!redirects.read().await.contains_key("initial"));

        // Trigger the failing refresh and check the last good map is preserved
        time::advance(Duration::from_secs(10)).await;
        completed.notified().await;
        tokio::task::yield_now().await;
        assert!(redirects.read().await.contains_key("refreshed"));

        // Cancel and await graceful shutdown
        cancellation_token.cancel();
        handle.await.unwrap();
        assert_eq!(calls.load(Ordering::SeqCst), 2);
    }
}
