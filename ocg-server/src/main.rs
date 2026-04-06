//! Open Community Groups server.
//!
//! This is the main entry point for the OCG server, which provides a web-based platform
//! for managing community groups and events.

#![warn(clippy::all, clippy::pedantic)]
#![allow(clippy::struct_field_names)]

use std::{collections::HashMap, path::PathBuf, sync::Arc};

use activity_tracker::ActivityTrackerDB;
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
    config::{Config, HttpServerConfig, ImageStorageConfig, LogFormat, MeetingsConfig},
    db::PgDB,
    services::{
        images::{DbImageStorage, DynImageStorage, S3ImageStorage},
        meetings::{DynMeetingsProvider, MeetingProvider, MeetingsManager, zoom::ZoomMeetingsProvider},
        notifications::{DynEmailSender, LettreEmailSender, PgNotificationsManager},
    },
};

/// Activity tracking.
mod activity_tracker;
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
/// Utility helpers shared across modules.
mod util;
/// Validation utilities and custom validators.
mod validation;

/// Command-line arguments for the application.
#[derive(Debug, Parser)]
#[clap(author, version, about)]
struct Args {
    /// Path to the configuration file.
    #[clap(short, long)]
    config_file: Option<PathBuf>,
}

/// Background worker coordination primitives.
struct BackgroundTasks {
    cancellation_token: CancellationToken,
    task_tracker: TaskTracker,
}

impl BackgroundTasks {
    /// Create background task coordination primitives.
    fn new() -> Self {
        Self {
            cancellation_token: CancellationToken::new(),
            task_tracker: TaskTracker::new(),
        }
    }

    /// Request background workers to stop and wait for them.
    async fn shutdown(self) {
        self.task_tracker.close();
        self.cancellation_token.cancel();
        self.task_tracker.wait().await;
    }
}

/// Main entry point for the application.
#[tokio::main]
async fn main() -> Result<()> {
    // Load configuration and initialize logging
    let cfg = setup_config()?;
    setup_logging(&cfg.log.format);

    // Setup shared worker coordination and core infrastructure
    let background_tasks = BackgroundTasks::new();
    let db = setup_db(&cfg, &background_tasks)?;
    let image_storage = setup_image_storage(&cfg, db.clone());

    // Configure background services that depend on the database
    start_meetings_workers(&cfg, db.clone(), &background_tasks);
    let notifications_manager = setup_notifications_manager(&cfg, db.clone(), &background_tasks)?;
    let activity_tracker = setup_activity_tracker(db.clone(), &background_tasks);

    // Serve HTTP requests until a shutdown signal is received
    run_server(
        activity_tracker,
        db,
        image_storage,
        cfg.meetings.clone(),
        notifications_manager,
        &cfg.server,
    )
    .await?;

    // Stop background workers gracefully before exiting
    background_tasks.shutdown().await;

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

/// Configure the database pool and start the transaction cleaner worker.
fn setup_db(cfg: &Config, background_tasks: &BackgroundTasks) -> Result<Arc<PgDB>> {
    // Build the TLS connector used by the Postgres pool
    let mut builder = SslConnector::builder(SslMethod::tls())?;
    builder.set_verify(SslVerifyMode::NONE);

    // Create the Postgres connection pool and wrap it in our database abstraction
    let connector = MakeTlsConnector::new(builder.build());
    let pool = cfg.db.create_pool(Some(Runtime::Tokio1), connector)?;
    let db = Arc::new(PgDB::new(pool));

    // Keep the transaction cleaner running in the background
    {
        let cancellation_token = background_tasks.cancellation_token.clone();
        let db = db.clone();
        background_tasks.task_tracker.spawn(async move {
            db.tx_cleaner(cancellation_token).await;
        });
    }

    Ok(db)
}

/// Configure the image storage implementation.
fn setup_image_storage(cfg: &Config, db: Arc<PgDB>) -> DynImageStorage {
    match &cfg.images {
        ImageStorageConfig::Db => Arc::new(DbImageStorage::new(db)),
        ImageStorageConfig::S3(s3_cfg) => Arc::new(S3ImageStorage::new(s3_cfg)),
    }
}

/// Start meetings workers for the enabled providers.
fn start_meetings_workers(cfg: &Config, db: Arc<PgDB>, background_tasks: &BackgroundTasks) {
    // Collect the meetings providers enabled in the configuration
    let mut meetings_providers = HashMap::new();

    if let Some(ref meetings_cfg) = cfg.meetings
        && let Some(ref zoom_cfg) = meetings_cfg.zoom
    {
        meetings_providers.insert(
            MeetingProvider::Zoom,
            Arc::new(ZoomMeetingsProvider::new(zoom_cfg)) as DynMeetingsProvider,
        );
    }

    // Start meetings workers only when at least one provider is enabled
    if !meetings_providers.is_empty() {
        MeetingsManager::new(
            Arc::new(meetings_providers),
            db,
            cfg.meetings
                .as_ref()
                .and_then(|meetings_cfg| meetings_cfg.zoom.clone()),
            &background_tasks.task_tracker,
            &background_tasks.cancellation_token,
        );
    }
}

/// Configure the notifications manager and start its workers.
fn setup_notifications_manager(
    cfg: &Config,
    db: Arc<PgDB>,
    background_tasks: &BackgroundTasks,
) -> Result<Arc<PgNotificationsManager>> {
    // Create the sender first so the manager can share it with workers
    let email_sender: DynEmailSender = Arc::new(LettreEmailSender::new(&cfg.email)?);

    Ok(Arc::new(PgNotificationsManager::new(
        db,
        &cfg.email,
        &cfg.server.base_url,
        &email_sender,
        &background_tasks.task_tracker,
        &background_tasks.cancellation_token,
    )))
}

/// Configure the activity tracker and start its workers.
fn setup_activity_tracker(db: Arc<PgDB>, background_tasks: &BackgroundTasks) -> Arc<ActivityTrackerDB> {
    Arc::new(ActivityTrackerDB::new(
        db,
        &background_tasks.task_tracker,
        &background_tasks.cancellation_token,
    ))
}

/// Build the router and serve HTTP requests until shutdown.
async fn run_server(
    activity_tracker: Arc<ActivityTrackerDB>,
    db: Arc<PgDB>,
    image_storage: DynImageStorage,
    meetings_cfg: Option<MeetingsConfig>,
    notifications_manager: Arc<PgNotificationsManager>,
    server_cfg: &HttpServerConfig,
) -> Result<()> {
    // Build the router before binding the TCP listener
    let router = router::setup(
        activity_tracker,
        db,
        image_storage,
        meetings_cfg,
        notifications_manager,
        server_cfg,
    )
    .await?;
    let listener = TcpListener::bind(&server_cfg.addr).await?;

    // Serve requests until a graceful shutdown signal arrives
    info!("server started");
    info!(%server_cfg.addr, "listening");

    if let Err(err) = axum::serve(listener, router)
        .with_graceful_shutdown(shutdown_signal())
        .await
    {
        error!(?err, "server error");
        return Err(err.into());
    }

    info!("server stopped");

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
