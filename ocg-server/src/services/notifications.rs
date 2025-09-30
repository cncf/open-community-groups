//! This module defines types and logic to manage and send user notifications.

use std::{sync::Arc, time::Duration};

use anyhow::{Result, anyhow};
use askama::Template;
use async_trait::async_trait;
use lettre::{
    AsyncSmtpTransport, AsyncTransport, Message, Tokio1Executor,
    message::{Mailbox, MessageBuilder, header::ContentType},
    transport::smtp::authentication::Credentials,
};
#[cfg(test)]
use mockall::automock;
use serde::{Deserialize, Serialize};
use tokio::time::sleep;
use tokio_util::{sync::CancellationToken, task::TaskTracker};
use tracing::{error, instrument, warn};
use uuid::Uuid;

use crate::{
    config::EmailConfig,
    db::DynDB,
    templates::notifications::{
        CommunityTeamInvitation, EmailVerification, EventCanceled, EventPublished, EventRescheduled,
        GroupTeamInvitation, GroupWelcome,
    },
};

/// Number of concurrent workers that deliver notifications.
const NUM_WORKERS: usize = 1;

/// Time to wait after a delivery error before retrying.
const PAUSE_ON_ERROR: Duration = Duration::from_secs(10);

/// Time to wait when there are no notifications to deliver.
const PAUSE_ON_NONE: Duration = Duration::from_secs(15);

/// Trait for a notifications manager, responsible for delivering notifications.
#[async_trait]
#[cfg_attr(test, automock)]
pub(crate) trait NotificationsManager {
    /// Enqueue a notification for delivery.
    async fn enqueue(&self, notification: &NewNotification) -> Result<()>;
}

/// Shared trait object for a notifications manager.
pub(crate) type DynNotificationsManager = Arc<dyn NotificationsManager + Send + Sync>;

/// PostgreSQL-backed notifications manager implementation.
pub(crate) struct PgNotificationsManager {
    /// Handle to the database for notification operations.
    db: DynDB,
}

impl PgNotificationsManager {
    /// Create a new `PgNotificationsManager`.
    pub(crate) fn new(
        db: DynDB,
        cfg: &EmailConfig,
        email_sender: &DynEmailSender,
        task_tracker: &TaskTracker,
        cancellation_token: &CancellationToken,
    ) -> Self {
        // Setup and run some workers to deliver notifications
        for _ in 1..=NUM_WORKERS {
            let mut worker = Worker {
                db: db.clone(),
                cfg: cfg.clone(),
                cancellation_token: cancellation_token.clone(),
                email_sender: email_sender.clone(),
            };
            task_tracker.spawn(async move {
                worker.run().await;
            });
        }

        Self { db }
    }
}

#[async_trait]
impl NotificationsManager for PgNotificationsManager {
    /// Enqueue a notification for delivery.
    async fn enqueue(&self, notification: &NewNotification) -> Result<()> {
        self.db.enqueue_notification(notification).await
    }
}

/// Worker responsible for delivering notifications from the queue.
struct Worker {
    /// Database handle for notification queries.
    db: DynDB,
    /// Email configuration for sending notifications.
    cfg: EmailConfig,
    /// Token to signal worker shutdown.
    cancellation_token: CancellationToken,
    /// Email sender for dispatching messages.
    email_sender: DynEmailSender,
}

impl Worker {
    /// Main worker loop: delivers notifications until cancelled.
    async fn run(&mut self) {
        loop {
            // Try to deliver a pending notification
            match self.deliver_notification().await {
                Ok(true) => {
                    // One notification was delivered, try to deliver another
                    // one immediately
                }
                Ok(false) => tokio::select! {
                    // No pending notifications, pause unless we've been asked
                    // to stop
                    () = sleep(PAUSE_ON_NONE) => {},
                    () = self.cancellation_token.cancelled() => break,
                },
                Err(err) => {
                    // Something went wrong delivering the notification, pause
                    // unless we've been asked to stop
                    error!(?err, "error delivering notification");
                    tokio::select! {
                        () = sleep(PAUSE_ON_ERROR) => {},
                        () = self.cancellation_token.cancelled() => break,
                    }
                }
            }

            // Exit if the worker has been asked to stop
            if self.cancellation_token.is_cancelled() {
                break;
            }
        }
    }

    /// Attempt to deliver a pending notification, if available.
    #[instrument(skip(self), err)]
    async fn deliver_notification(&mut self) -> Result<bool> {
        // Begin transaction
        let client_id = self.db.tx_begin().await?;

        // Get pending notification
        let notification = match self.db.get_pending_notification(client_id).await {
            Ok(notification) => notification,
            Err(err) => {
                self.db.tx_rollback(client_id).await?;
                return Err(err);
            }
        };

        // Deliver notification (if any)
        let notification_delivered = if let Some(notification) = &notification {
            // Prepare notification subject and body.
            let (subject, body) = Self::prepare_content(notification)?;

            // Prepare message and send email
            let err = match self.send_email(&notification.email, subject.as_str(), body).await {
                Ok(()) => None,
                Err(err) => Some(err.to_string()),
            };

            // Update notification with result
            if let Err(err) = self.db.update_notification(client_id, notification, err).await {
                error!(?err, "error updating notification");
            }

            // Commit transaction
            self.db.tx_commit(client_id).await?;

            true
        } else {
            // No pending notification, rollback transaction
            self.db.tx_rollback(client_id).await?;

            false
        };

        Ok(notification_delivered)
    }

    /// Prepare the subject and body for a notification email.
    fn prepare_content(notification: &Notification) -> Result<(String, String)> {
        let template_data = notification
            .template_data
            .clone()
            .ok_or_else(|| anyhow!("missing template data"))?;

        let (subject, body) = match notification.kind {
            NotificationKind::CommunityTeamInvitation => {
                let subject = "You have been invited to join a community team";
                let template: CommunityTeamInvitation = serde_json::from_value(template_data)?;
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EmailVerification => {
                let subject = "Verify your email address";
                let template: EmailVerification = serde_json::from_value(template_data)?;
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventCanceled => {
                let subject = "Event canceled";
                let template: EventCanceled = serde_json::from_value(template_data)?;
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventPublished => {
                let subject = "New event published";
                let template: EventPublished = serde_json::from_value(template_data)?;
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventRescheduled => {
                let subject = "Event rescheduled";
                let template: EventRescheduled = serde_json::from_value(template_data)?;
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::GroupTeamInvitation => {
                let subject = "You have been invited to join a group team";
                let template: GroupTeamInvitation = serde_json::from_value(template_data)?;
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::GroupWelcome => {
                let subject = "Welcome to the group";
                let template: GroupWelcome = serde_json::from_value(template_data)?;
                let body = template.render()?;
                (subject, body)
            }
        };

        Ok((subject.to_string(), body))
    }

    /// Send an email to the specified address with the given subject and body.
    async fn send_email(&self, to_address: &str, subject: &str, body: String) -> Result<()> {
        // Prepare message
        let message = MessageBuilder::new()
            .from(Mailbox::new(
                Some(self.cfg.from_name.clone()),
                self.cfg.from_address.parse()?,
            ))
            .to(to_address.parse()?)
            .header(ContentType::TEXT_HTML)
            .subject(subject)
            .body(body)?;

        // Send email
        if let Some(whitelist) = &self.cfg.rcpts_whitelist {
            // If whitelist is present but empty, none are allowed.
            let allowed = !whitelist.is_empty() && whitelist.iter().any(|wa| wa == to_address);
            if !allowed {
                warn!(%to_address, "email recipient not allowed; skipping send");
                return Ok(());
            }
        }
        self.email_sender.send(message).await?;

        Ok(())
    }
}

/// Trait representing an async email sender used by the notifications workers.
#[async_trait]
#[cfg_attr(test, automock)]
pub(crate) trait EmailSender {
    /// Send an email represented by the provided message.
    async fn send(&self, message: Message) -> Result<()>;
}

/// Shared trait object for an email sender.
pub(crate) type DynEmailSender = Arc<dyn EmailSender + Send + Sync>;

/// Concrete email sender backed by a Lettre SMTP transport.
pub(crate) struct LettreEmailSender {
    transport: AsyncSmtpTransport<Tokio1Executor>,
}

impl LettreEmailSender {
    /// Create a new `LettreEmailSender` from the provided config.
    pub(crate) fn new(cfg: &EmailConfig) -> Result<Self> {
        let transport = AsyncSmtpTransport::<Tokio1Executor>::relay(&cfg.smtp.host)?
            .credentials(Credentials::new(
                cfg.smtp.username.clone(),
                cfg.smtp.password.clone(),
            ))
            .build();

        Ok(Self { transport })
    }
}

#[async_trait]
impl EmailSender for LettreEmailSender {
    async fn send(&self, message: Message) -> Result<()> {
        self.transport.send(message).await?;
        Ok(())
    }
}

/// Data required to create a new notification.
#[derive(Debug, Clone)]
pub(crate) struct NewNotification {
    /// The type of notification to send.
    pub kind: NotificationKind,
    /// The user IDs to notify.
    pub recipients: Vec<Uuid>,
    /// Optional template data for the notification content.
    pub template_data: Option<serde_json::Value>,
}

/// Data required to deliver a notification to a user.
#[derive(Debug, Clone)]
pub(crate) struct Notification {
    /// Unique identifier for the notification.
    pub notification_id: Uuid,
    /// Email address to send the notification to.
    pub email: String,
    /// The type of notification.
    pub kind: NotificationKind,
    /// Optional template data for the notification content.
    pub template_data: Option<serde_json::Value>,
}

/// Supported notification types.
#[derive(Debug, Clone, Serialize, Deserialize, strum::Display, strum::EnumString)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum NotificationKind {
    /// Notification for a community team invitation.
    CommunityTeamInvitation,
    /// Notification for email verification.
    EmailVerification,
    /// Notification for an event canceled.
    EventCanceled,
    /// Notification for an event published.
    EventPublished,
    /// Notification for an event rescheduled.
    EventRescheduled,
    /// Notification for a group team invitation.
    GroupTeamInvitation,
    /// Notification welcoming a new group member.
    GroupWelcome,
}
