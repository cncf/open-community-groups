//! Best-effort notification helpers.
//!
//! Best-effort notifications run after the core operation has committed. They
//! load their context, build their payload, and enqueue it, logging any failure
//! together with the identifiers needed to reconstruct it. They never fail or
//! undo the operation that triggered them.

use anyhow::Result;
use tracing::warn;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::DBOperations,
    services::notifications::{DynNotificationsManager, load_event_notification_context},
    types::{event::EventSummary, notifications::NewNotification, site::SiteSettings},
};

#[cfg(test)]
mod tests;

/// Enqueues an event notification best-effort after the triggering operation
/// committed.
///
/// The event summary and site settings are loaded, handed to `build` together
/// with the server configuration, and the resulting notification is enqueued.
/// Context loading, payload building, and enqueue failures are logged with the
/// event identifiers and swallowed.
pub(crate) async fn enqueue_event_notification_best_effort<F>(
    db: &dyn DBOperations,
    notifications_manager: &DynNotificationsManager,
    server_cfg: &HttpServerConfig,
    community_id: Uuid,
    event_id: Uuid,
    build: F,
) where
    F: FnOnce(&EventSummary, &HttpServerConfig, &SiteSettings) -> Result<NewNotification>,
{
    // Load the event and site context the payload builder needs
    let (event, site_settings) =
        match load_event_notification_context(db, community_id, event_id).await {
            Ok(context) => context,
            Err(err) => {
                warn!(
                    error = %err,
                    %community_id,
                    %event_id,
                    "failed to load event notification context"
                );
                return;
            }
        };

    // Build the notification payload
    let notification = match build(&event, server_cfg, &site_settings) {
        Ok(notification) => notification,
        Err(err) => {
            warn!(
                error = %err,
                %community_id,
                %event_id,
                "failed to build event notification"
            );
            return;
        }
    };

    // Enqueue the notification, logging delivery queue failures
    if let Err(err) = notifications_manager.enqueue(&notification).await {
        warn!(
            error = %err,
            %community_id,
            %event_id,
            kind = ?notification.kind,
            "failed to enqueue event notification"
        );
    }
}
