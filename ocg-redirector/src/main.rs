//! Open Community Groups redirector.
//!
//! This service handles permanent redirects from legacy group and event URLs to
//! their canonical pages in Open Community Groups.

#![warn(clippy::all, clippy::pedantic)]
#![allow(clippy::struct_field_names)]

use std::path::PathBuf;

use anyhow::{Context, Result};
use clap::Parser;
use deadpool_postgres::Runtime;
use openssl::ssl::{SslConnector, SslMethod, SslVerifyMode};
use postgres_openssl::MakeTlsConnector;
use tokio::{net::TcpListener, signal};
use tracing::{error, info};
use tracing_subscriber::EnvFilter;

use crate::{
    config::{Config, HttpServerConfig, LogFormat},
    db::PgDB,
};

/// Application configuration management.
mod config;
/// Database abstraction layer and operations.
mod db;
/// HTTP router configuration and setup.
mod router;

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
    setup_logging(&cfg.log.format);

    // Setup the database connection used to load redirect mappings
    let db = setup_db(&cfg)?;

    // Serve HTTP requests until a shutdown signal is received
    run_server(db, &cfg.server).await?;

    Ok(())
}

/// Parse the command line arguments and load configuration.
fn setup_config() -> Result<Config> {
    let args = Args::parse();
    Config::new(args.config_file.as_ref()).context("error setting up configuration")
}

/// Configure tracing based on the configured log format.
fn setup_logging(log_format: &LogFormat) {
    // Build the shared subscriber configuration first
    let ts = tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| format!("{}=debug", env!("CARGO_CRATE_NAME")).into()),
        )
        .with_file(true)
        .with_line_number(true);

    // Select the configured output formatter
    match log_format {
        LogFormat::Json => ts.json().init(),
        LogFormat::Pretty => ts.init(),
    }
}

/// Configure the database pool used by the redirector.
fn setup_db(cfg: &Config) -> Result<PgDB> {
    // Build the TLS connector used by the Postgres pool
    let mut builder = SslConnector::builder(SslMethod::tls())?;
    builder.set_verify(SslVerifyMode::NONE);

    // Create the pool with the configured TLS connector
    let connector = MakeTlsConnector::new(builder.build());
    let pool = cfg.db.create_pool(Some(Runtime::Tokio1), connector)?;

    Ok(PgDB::new(pool))
}

/// Build the router and serve HTTP requests until shutdown.
async fn run_server(db: PgDB, server_cfg: &HttpServerConfig) -> Result<()> {
    // Load redirects before building the router
    let redirects = db.load_redirects().await?;

    // Build the router before binding the TCP listener
    let router = router::setup(redirects, server_cfg);
    let listener = TcpListener::bind(&server_cfg.addr).await?;

    // Serve requests until a graceful shutdown signal arrives
    info!("server started");
    info!(%server_cfg.addr, "listening");

    if let Err(err) = axum::serve(listener, router)
        .with_graceful_shutdown(shutdown_signal())
        .await
    {
        error!(?err, "server error");
        return Err(anyhow::Error::new(err));
    }

    info!("server stopped");

    Ok(())
}

/// Returns a future that completes when the program receives a shutdown signal.
async fn shutdown_signal() {
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
