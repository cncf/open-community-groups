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
    config::{Config, LogFormat},
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
    // Setup configuration
    let args = Args::parse();
    let cfg = Config::new(args.config_file.as_ref()).context("error setting up configuration")?;

    // Setup logging based on configuration
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

    // Setup database connection pool
    let mut builder = SslConnector::builder(SslMethod::tls())?;
    builder.set_verify(SslVerifyMode::NONE);
    let connector = MakeTlsConnector::new(builder.build());
    let pool = cfg.db.create_pool(Some(Runtime::Tokio1), connector)?;
    let db = PgDB::new(pool);

    // Setup and launch the HTTP server
    let redirects = db.load_redirects().await?;
    let router = router::setup(redirects, &cfg.server);
    let listener = TcpListener::bind(&cfg.server.addr).await?;
    info!("server started");
    info!(%cfg.server.addr, "listening");
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
