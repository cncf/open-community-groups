//! Open Community Groups server.
//!
//! This is the main entry point for the OCG server, which provides a web-based platform
//! for managing community groups and events.

#![warn(clippy::all, clippy::pedantic)]
#![allow(clippy::struct_field_names)]

use std::{path::PathBuf, sync::Arc};

use anyhow::{Context, Result};
use clap::Parser;
use deadpool_postgres::Runtime;
use openssl::ssl::{SslConnector, SslMethod, SslVerifyMode};
use postgres_openssl::MakeTlsConnector;
use tokio::{net::TcpListener, signal};
use tokio_util::{sync::CancellationToken, task::TaskTracker};
use tracing::{error, info};
use tracing_subscriber::EnvFilter;

use crate::{
    config::{Config, LogFormat},
    db::PgDB,
    services::notifications::PgNotificationsManager,
};

/// Authentication and authorization functionality.
mod auth;
/// Application configuration management.
mod config;
/// Database abstraction layer and operations.
mod db;
/// HTTP request handlers.
mod handlers;
/// HTTP router configuration and setup.
mod router;
/// Background services and workers.
mod services;
/// Templates for rendering pages, notifications, etc.
mod templates;
/// Domain types and data structures.
mod types;

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
    // Setup configuration.
    let args = Args::parse();
    let cfg = Config::new(args.config_file.as_ref()).context("error setting up configuration")?;

    // Setup logging based on configuration.
    let ts = tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| format!("{}=debug", env!("CARGO_CRATE_NAME")).into()),
        )
        .with_file(true)
        .with_line_number(true);
    match cfg.log.format {
        LogFormat::Json => ts.json().init(),
        LogFormat::Pretty => ts.init(),
    }

    // Setup task tracker and cancellation token for background workers.
    let task_tracker = TaskTracker::new();
    let cancellation_token = CancellationToken::new();

    // Setup database connection pool.
    let mut builder = SslConnector::builder(SslMethod::tls())?;
    builder.set_verify(SslVerifyMode::NONE);
    let connector = MakeTlsConnector::new(builder.build());
    let pool = cfg.db.create_pool(Some(Runtime::Tokio1), connector)?;
    let db = Arc::new(PgDB::new(pool));
    {
        let db = db.clone();
        let cancellation_token = cancellation_token.clone();
        task_tracker.spawn(async move {
            db.tx_cleaner(cancellation_token).await;
        });
    }

    // Setup notifications manager.
    let notifications_manager = Arc::new(PgNotificationsManager::new(
        db.clone(),
        &cfg.email,
        &task_tracker,
        &cancellation_token,
    )?);

    // Setup and launch the HTTP server.
    let router = router::setup(&cfg.server, db, notifications_manager).await?;
    let listener = TcpListener::bind(&cfg.server.addr).await?;
    info!("server started");
    info!(%cfg.server.addr, "listening");
    if let Err(err) = axum::serve(listener, router)
        .with_graceful_shutdown(shutdown_signal())
        .await
    {
        error!(?err, "server error");
        return Err(err.into());
    }
    info!("server stopped");

    // Request all background workers to stop and wait for completion.
    task_tracker.close();
    cancellation_token.cancel();
    task_tracker.wait().await;

    Ok(())
}

/// Returns a future that completes when the program receives a shutdown signal.
///
/// Handles both ctrl+c and terminate signals for graceful shutdown.
async fn shutdown_signal() {
    // Setup ctrl+c signal handler.
    let ctrl_c = async {
        signal::ctrl_c()
            .await
            .expect("failed to install ctrl+c signal handler");
    };

    #[cfg(unix)]
    // Setup terminate signal handler (Unix only).
    let terminate = async {
        signal::unix::signal(signal::unix::SignalKind::terminate())
            .expect("failed to install terminate signal handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    // Wait for either ctrl+c or terminate signal.
    tokio::select! {
        () = ctrl_c => {},
        () = terminate => {},
    }
}
