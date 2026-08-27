//! Open Community Groups server.
//!
//! This is the main entry point for the OCG server, which provides a web-based platform
//! for managing community groups and events.

#![warn(clippy::all, clippy::pedantic)]
#![allow(clippy::struct_field_names)]
// Deep ssi/json-ld generic futures in badge verification exceed the default.
#![recursion_limit = "256"]

use std::{collections::HashMap, path::PathBuf, sync::Arc};

use activity_tracker::ActivityTrackerDB;
use anyhow::{Context, Result};
use clap::Parser;
use deadpool_postgres::Runtime;
use ocg_common::{
    db::tls_connector,
    runtime::{setup_logging, shutdown_signal},
};
use tokio::net::TcpListener;
use tracing::{error, info};

use crate::{
    config::{Config, HttpServerConfig, ImageStorageConfig, MeetingsConfig, PaymentsConfig},
    db::{DynDB, PgDB, pool as db_pool},
    services::{
        badges::start_badge_award_workers,
        enrollment::start_enrollment_workers,
        images::{DbImageStorage, DynImageStorage, S3ImageStorage},
        meetings::{
            DynMeetingsProvider, MeetingProvider, MeetingsManager, zoom::ZoomMeetingsProvider,
        },
        notifications::{DynEmailSender, LettreEmailSender, PgNotificationsManager},
        payments::{
            DynPaymentsManager, DynPaymentsProvider, PgPaymentsManager, build_payments_provider,
            start_payment_workers,
        },
        workers::BackgroundTasks,
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

/// Main entry point for the application.
#[tokio::main]
async fn main() -> Result<()> {
    // Load configuration and initialize logging
    let cfg = setup_config()?;
    setup_logging(
        &cfg.log.format,
        &format!("{}=debug", env!("CARGO_CRATE_NAME")),
    );

    // Setup shared worker coordination and core infrastructure
    let background_tasks = BackgroundTasks::new();
    let db = setup_db(&cfg)?;
    let image_storage = setup_image_storage(&cfg, db.clone());

    // Configure background services that depend on the database
    let workers_db = db.clone() as DynDB;
    start_badge_award_workers(&workers_db, &background_tasks);
    start_meetings_workers(cfg.meetings.as_ref(), db.clone(), &background_tasks);
    let activity_tracker = setup_activity_tracker(db.clone(), &background_tasks);
    let notifications_manager = setup_notifications_manager(&cfg, db.clone(), &background_tasks)?;
    let payments_provider = build_payments_provider(cfg.payments.as_ref());
    start_enrollment_workers(
        &workers_db,
        cfg.payments.as_ref().map(PaymentsConfig::provider),
        &background_tasks,
    );
    start_payment_workers(
        &workers_db,
        notifications_manager.clone(),
        payments_provider.as_ref(),
        &cfg.server,
        &background_tasks,
    );
    let payments_manager = setup_payments_manager(
        db.clone(),
        notifications_manager.clone(),
        payments_provider,
        &cfg.server,
    );

    // Serve HTTP requests until a shutdown signal is received
    run_server(
        activity_tracker,
        db,
        image_storage,
        cfg.meetings.clone(),
        cfg.payments.clone(),
        payments_manager,
        notifications_manager,
        &cfg.server,
    )
    .await?;

    // Stop background workers gracefully before exiting
    background_tasks.shutdown().await;

    Ok(())
}

/// Build the router and serve HTTP requests until shutdown.
#[allow(clippy::too_many_arguments)]
async fn run_server(
    activity_tracker: Arc<ActivityTrackerDB>,
    db: Arc<PgDB>,
    image_storage: DynImageStorage,
    meetings_cfg: Option<MeetingsConfig>,
    payments_cfg: Option<PaymentsConfig>,
    payments_manager: DynPaymentsManager,
    notifications_manager: Arc<PgNotificationsManager>,
    server_cfg: &HttpServerConfig,
) -> Result<()> {
    // Build the router before binding the TCP listener
    let router = router::setup(
        activity_tracker,
        db,
        image_storage,
        meetings_cfg,
        payments_cfg,
        payments_manager,
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

/// Configure the activity tracker and start its workers.
fn setup_activity_tracker(
    db: Arc<PgDB>,
    background_tasks: &BackgroundTasks,
) -> Arc<ActivityTrackerDB> {
    Arc::new(ActivityTrackerDB::new(db, background_tasks))
}

/// Parse the command line arguments and load configuration.
fn setup_config() -> Result<Config> {
    let args = Args::parse();
    Config::new(args.config_file.as_ref()).context("error setting up configuration")
}

/// Configure the database pool.
fn setup_db(cfg: &Config) -> Result<Arc<PgDB>> {
    // Build the TLS connector used by the Postgres pool
    let connector = tls_connector(cfg.db.tls.as_ref())?;

    // Create the Postgres connection pool and wrap it in our database abstraction
    let db_cfg = db_pool::config_with_defaults(&cfg.db.connection);
    let pool = db_cfg.create_pool(Some(Runtime::Tokio1), connector)?;
    let db = Arc::new(PgDB::new(pool));

    Ok(db)
}

/// Configure the image storage implementation.
fn setup_image_storage(cfg: &Config, db: Arc<PgDB>) -> DynImageStorage {
    match &cfg.images {
        ImageStorageConfig::Db => Arc::new(DbImageStorage::new(db)),
        ImageStorageConfig::S3(s3_cfg) => Arc::new(S3ImageStorage::new(s3_cfg)),
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
        background_tasks,
    )))
}

/// Configure the payments manager.
fn setup_payments_manager(
    db: Arc<PgDB>,
    notifications_manager: Arc<PgNotificationsManager>,
    payments_provider: Option<DynPaymentsProvider>,
    server_cfg: &HttpServerConfig,
) -> DynPaymentsManager {
    Arc::new(PgPaymentsManager::new(
        db,
        notifications_manager,
        payments_provider,
        server_cfg.clone(),
    ))
}

/// Start meetings workers for the enabled providers.
fn start_meetings_workers(
    meetings_cfg: Option<&MeetingsConfig>,
    db: Arc<PgDB>,
    background_tasks: &BackgroundTasks,
) {
    // Collect the meetings providers enabled in the configuration
    let mut meetings_providers = HashMap::new();

    if let Some(meetings_cfg) = meetings_cfg
        && let Some(zoom_cfg) = &meetings_cfg.zoom
        && zoom_cfg.enabled
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
            meetings_cfg.and_then(|meetings_cfg| meetings_cfg.zoom.clone()),
            background_tasks,
        );
    }
}
