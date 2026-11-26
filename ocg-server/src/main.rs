//! Open Community Groups server.
//!
//! This is the main entry point for the OCG server, which provides a web-based platform
//! for managing community groups and events.

#![warn(clippy::all, clippy::pedantic)]
#![allow(clippy::struct_field_names)]
// Deep ssi/json-ld generic futures in badge verification exceed the default.
#![recursion_limit = "256"]

use std::{collections::HashMap, net::SocketAddr, path::PathBuf, sync::Arc};

use activity_tracker::ActivityTrackerDB;
use anyhow::{Context, Result};
use clap::Parser;
use ocg_common::{
    db::{create_pool, tls_connector},
    runtime::{setup_logging, shutdown_signal_with_drain},
};
use tokio::net::TcpListener;
use tokio_util::sync::CancellationToken;
use tracing::{error, info, warn};

use crate::{
    config::{Config, HttpServerConfig, ImageStorageConfig, MeetingsConfig, PaymentsConfig},
    db::{DynDB, PgDB, payments::DBPayments},
    router::RouterDeps,
    services::{
        badges::start_badge_award_workers,
        blocking::BlockingExecutor,
        enrollment::{DynEnrollmentManager, PgEnrollmentManager, start_enrollment_workers},
        events::{DynEventsManager, PgEventsManager},
        images::{
            DbImageStorage, DefaultImagesManager, DynImageStorage, DynImagesManager, S3ImageStorage,
        },
        inbox::{DynInboxManager, PgInboxManager},
        meetings::{DynMeetingsProvider, MeetingsManager, zoom::ZoomMeetingsProvider},
        notifications::{DynEmailSender, LettreEmailSender, PgNotificationsManager},
        payments::{
            DynPaymentsManager, DynPaymentsProvider, PgPaymentsManager, build_payments_provider,
            start_payment_workers,
        },
        rate_limit::{self, StartupWarning},
        workers::{BackgroundTasks, auth_cleanup, queue_health},
    },
    types::meetings::MeetingProvider,
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
/// Layer dependency rules enforced at test time.
#[cfg(test)]
mod layers;
/// HTTP router configuration and setup.
mod router;
/// Background services and workers.
mod services;
/// Templates for rendering pages, notifications, etc.
mod templates;
/// Test helpers that belong to no layer.
#[cfg(test)]
mod test_util;
/// Domain types and data structures.
mod types;
/// Utility helpers shared across modules.
mod util;
/// Validation utilities and custom validators.
mod validation;

/// Default maximum number of database connections in the server pool.
const DB_POOL_MAX_SIZE: usize = 25;

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
    let background_tasks = BackgroundTasks::new(cfg.server.shutdown_grace_period());
    let blocking_executor = BlockingExecutor::new(cfg.server.max_blocking_concurrency());
    let db = setup_db(&cfg)?;
    let image_storage = setup_image_storage(&cfg, db.clone());

    // Sync operator-managed external payments configuration before serving
    db.sync_external_payments_config(cfg.external_payments.clone())
        .await
        .context("error syncing external payments configuration")?;

    // Configure background services that depend on the database
    let workers_db = db.clone() as DynDB;
    let activity_tracker = setup_activity_tracker(db.clone(), &background_tasks);
    auth_cleanup::start(&workers_db, &background_tasks);
    start_badge_award_workers(&workers_db, &background_tasks);
    start_meetings_workers(cfg.meetings.as_ref(), db.clone(), &background_tasks)?;
    let notifications_manager = setup_notifications_manager(&cfg, db.clone(), &background_tasks)?;
    let payments_provider = build_payments_provider(cfg.payments.as_ref())?;
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

    // Setup rate limiting and its summary worker, when configured
    let rate_limiter = rate_limit::setup(cfg.server.rate_limit.as_ref(), &background_tasks)?;

    // Warn when rate limiting is disabled or observing on an HTTPS deployment
    warn_rate_limit_config(&cfg.server);

    // Start the health reporter last so its reports cover every worker
    queue_health::start(&workers_db, background_tasks.registry(), &background_tasks);

    let payments_manager = setup_payments_manager(
        db.clone(),
        notifications_manager.clone(),
        payments_provider,
        cfg.payments
            .as_ref()
            .map(PaymentsConfig::platform_fee_bps)
            .map_or(0, i32::from),
        &cfg.server,
    );
    let enrollment_manager = setup_enrollment_manager(
        db.clone(),
        notifications_manager.clone(),
        payments_manager.clone(),
        &cfg.server,
    );
    let events_manager = setup_events_manager(
        db.clone(),
        cfg.meetings.as_ref(),
        payments_manager.clone(),
        &cfg.server,
    );
    let images_manager = setup_images_manager(blocking_executor.clone(), image_storage);
    let inbox_manager = setup_inbox_manager(db.clone());

    // Serve HTTP requests until a shutdown signal is received
    run_server(RouterDeps {
        activity_tracker,
        blocking_executor,
        db,
        enrollment_manager,
        events_manager,
        images_manager,
        inbox_manager,
        notifications_manager,
        payments_manager,
        server_cfg: cfg.server,
        shutdown_drain: CancellationToken::new(),

        meetings_cfg: cfg.meetings,
        payments_cfg: cfg.payments,
        rate_limiter,
    })
    .await?;

    // Stop background workers gracefully before exiting
    background_tasks.shutdown().await;

    Ok(())
}

/// Build the router and serve HTTP requests until shutdown.
async fn run_server(deps: RouterDeps) -> Result<()> {
    // Capture the bind address and drain handle before moving deps into router setup
    let addr = deps.server_cfg.addr.clone();
    let shutdown_drain = deps.shutdown_drain.clone();

    // Build the router before binding the TCP listener
    let router = router::setup(deps).await?;
    let listener = TcpListener::bind(&addr).await?;

    // Serve requests with their peer address until a graceful shutdown signal arrives
    info!("server started");
    info!(%addr, "listening");

    if let Err(err) = axum::serve(
        listener,
        router.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(shutdown_signal_with_drain(shutdown_drain))
    .await
    {
        error!(error = %format_args!("{err:#}"), "server error");
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
    let pool = create_pool(&cfg.db.connection, connector, DB_POOL_MAX_SIZE)?;
    let db = Arc::new(PgDB::new(pool));

    Ok(db)
}

/// Configure the enrollment manager.
fn setup_enrollment_manager(
    db: Arc<PgDB>,
    notifications_manager: Arc<PgNotificationsManager>,
    payments_manager: DynPaymentsManager,
    server_cfg: &HttpServerConfig,
) -> DynEnrollmentManager {
    Arc::new(PgEnrollmentManager::new(
        db,
        notifications_manager,
        payments_manager,
        server_cfg.clone(),
    ))
}

/// Configure the events manager.
fn setup_events_manager(
    db: Arc<PgDB>,
    meetings_cfg: Option<&MeetingsConfig>,
    payments_manager: DynPaymentsManager,
    server_cfg: &HttpServerConfig,
) -> DynEventsManager {
    Arc::new(PgEventsManager::new(
        db,
        meetings_cfg,
        payments_manager,
        server_cfg.clone(),
    ))
}

/// Configure the image storage implementation.
fn setup_image_storage(cfg: &Config, db: Arc<PgDB>) -> DynImageStorage {
    match &cfg.images {
        ImageStorageConfig::Db => Arc::new(DbImageStorage::new(db)),
        ImageStorageConfig::S3(s3_cfg) => Arc::new(S3ImageStorage::new(s3_cfg)),
    }
}

/// Configure the images manager.
fn setup_images_manager(
    blocking_executor: BlockingExecutor,
    image_storage: DynImageStorage,
) -> DynImagesManager {
    Arc::new(DefaultImagesManager::new(blocking_executor, image_storage))
}

/// Configure the inbox manager.
fn setup_inbox_manager(db: Arc<PgDB>) -> DynInboxManager {
    Arc::new(PgInboxManager::new(db))
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
    platform_fee_bps: i32,
    server_cfg: &HttpServerConfig,
) -> DynPaymentsManager {
    Arc::new(PgPaymentsManager::new(
        db,
        notifications_manager,
        payments_provider,
        platform_fee_bps,
        server_cfg.clone(),
    ))
}

/// Start meetings workers for the enabled providers.
fn start_meetings_workers(
    meetings_cfg: Option<&MeetingsConfig>,
    db: Arc<PgDB>,
    background_tasks: &BackgroundTasks,
) -> Result<()> {
    // Collect the meetings providers enabled in the configuration
    let mut meetings_providers = HashMap::new();

    if let Some(meetings_cfg) = meetings_cfg
        && let Some(zoom_cfg) = &meetings_cfg.zoom
        && zoom_cfg.enabled
    {
        meetings_providers.insert(
            MeetingProvider::Zoom,
            Arc::new(ZoomMeetingsProvider::new(zoom_cfg)?) as DynMeetingsProvider,
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

    Ok(())
}

/// Emit a startup warning when rate limiting is disabled or observing on a
/// non-localhost HTTPS deployment.
fn warn_rate_limit_config(server_cfg: &HttpServerConfig) {
    match rate_limit::startup_warning(server_cfg.rate_limit.as_ref(), &server_cfg.base_url) {
        Some(StartupWarning::Disabled) => {
            warn!(
                "rate limiting is disabled on an https deployment; configure server.rate_limit with mode=enforce for production"
            );
        }
        Some(StartupWarning::ObserveMode) => {
            warn!(
                mode = "observe",
                "rate limiting is running in observe mode on an https deployment; set server.rate_limit.mode=enforce for production"
            );
        }
        None => {}
    }
}
