//! Open Community Groups redirector.
//!
//! This service handles permanent redirects from community-specific legacy URLs
//! to their canonical pages in Open Community Groups.

#![warn(clippy::all, clippy::pedantic)]
#![allow(clippy::struct_field_names)]

use std::{path::PathBuf, sync::Arc, time::Duration};

use anyhow::{Context, Result};
use clap::Parser;
use deadpool_postgres::Runtime;
use ocg_common::{
    db::tls_connector,
    runtime::{setup_logging, shutdown_signal},
};
use tokio::{net::TcpListener, sync::RwLock, time};
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

/// Build the router and serve HTTP requests until shutdown.
async fn run_server(db: PgDB, server_cfg: &HttpServerConfig) -> Result<()> {
    // Load redirects before building the router
    let redirects = Arc::new(RwLock::new(db.load_redirects().await?));
    spawn_redirect_refresh(db, redirects.clone());

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

/// Parse the command line arguments and load configuration.
fn setup_config() -> Result<Config> {
    let args = Args::parse();
    Config::new(args.config_file.as_ref()).context("error setting up configuration")
}

/// Configure the database pool used by the redirector.
fn setup_db(cfg: &Config) -> Result<PgDB> {
    // Build the TLS connector used by the Postgres pool
    let connector = tls_connector(cfg.db.tls.as_ref())?;

    // Create the pool with the configured TLS connector
    let pool = cfg.db.connection.create_pool(Some(Runtime::Tokio1), connector)?;

    Ok(PgDB::new(pool))
}

/// Spawns the periodic redirect map refresh task.
fn spawn_redirect_refresh(db: PgDB, redirects: Arc<RwLock<router::Redirects>>) {
    let _redirect_refresh_handle = tokio::spawn(async move {
        loop {
            time::sleep(REDIRECT_REFRESH_INTERVAL).await;

            match db.load_redirects().await {
                Ok(refreshed_redirects) => {
                    *redirects.write().await = refreshed_redirects;
                    info!("redirect mappings refreshed");
                }
                Err(err) => {
                    error!(?err, "failed to refresh redirect mappings");
                }
            }
        }
    });
}
