//! This module defines types and logic to manage and send user notifications.

use std::{sync::Arc, time::Duration};

use anyhow::{Result, anyhow};
use askama::Template;
use async_trait::async_trait;
use lettre::{
    AsyncSmtpTransport, AsyncTransport, Message, Tokio1Executor,
    message::{
        Mailbox, MessageBuilder, MultiPart, SinglePart,
        header::{ContentDisposition, ContentType},
    },
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
        CfsSubmissionUpdated, CommunityTeamInvitation, EmailVerification, EventCanceled, EventCustom,
        EventPublished, EventReminder, EventRescheduled, EventWelcome, GroupCustom, GroupTeamInvitation,
        GroupWelcome, SessionProposalCoSpeakerInvitation, SpeakerWelcome,
    },
};

#[cfg(test)]
mod tests;

/// Number of concurrent workers that deliver notifications.
const NUM_DELIVERY_WORKERS: usize = 2;

/// Number of workers that enqueue due notifications.
const NUM_ENQUEUE_WORKERS: usize = 1;

/// Time to wait after a delivery error before retrying.
const PAUSE_ON_DELIVERY_ERROR: Duration = Duration::from_secs(10);

/// Time to wait when there are no notifications to deliver.
const PAUSE_ON_DELIVERY_NONE: Duration = Duration::from_secs(15);

/// Time to wait after an enqueue error before retrying.
const PAUSE_ON_ENQUEUE_ERROR: Duration = Duration::from_secs(30);

/// Time to wait when there are no due notifications to enqueue.
const PAUSE_ON_ENQUEUE_NONE: Duration = Duration::from_secs(300);

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
        base_url: &str,
        email_sender: &DynEmailSender,
        task_tracker: &TaskTracker,
        cancellation_token: &CancellationToken,
    ) -> Self {
        // Setup and run workers to enqueue due notifications
        for _ in 1..=NUM_ENQUEUE_WORKERS {
            let worker = EnqueueWorker {
                db: db.clone(),
                base_url: base_url.to_string(),
                cancellation_token: cancellation_token.clone(),
            };
            task_tracker.spawn(async move {
                worker.run().await;
            });
        }

        // Setup and run workers to deliver notifications
        for _ in 1..=NUM_DELIVERY_WORKERS {
            let mut worker = DeliveryWorker {
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

/// Worker responsible for enqueuing due notifications.
struct EnqueueWorker {
    /// Database handle for notification queries.
    db: DynDB,
    /// Base URL used for generated links in reminders.
    base_url: String,
    /// Token to signal worker shutdown.
    cancellation_token: CancellationToken,
}

impl EnqueueWorker {
    /// Main worker loop: enqueues due notifications until cancelled.
    async fn run(&self) {
        loop {
            // Enqueue due notifications and pick next pause interval
            let pause = match self.enqueue_due_notifications().await {
                Ok(_) => PAUSE_ON_ENQUEUE_NONE,
                Err(err) => {
                    error!(?err, "error enqueueing due notifications");
                    PAUSE_ON_ENQUEUE_ERROR
                }
            };

            // Exit if the worker has been asked to stop
            tokio::select! {
                () = sleep(pause) => {},
                () = self.cancellation_token.cancelled() => break,
            }
        }
    }

    /// Enqueue due notifications and return the number enqueued.
    #[instrument(skip(self), err)]
    async fn enqueue_due_notifications(&self) -> Result<usize> {
        self.db.enqueue_due_event_reminders(&self.base_url).await
    }
}

/// Worker responsible for delivering notifications from the queue.
struct DeliveryWorker {
    /// Database handle for notification queries.
    db: DynDB,
    /// Email configuration for sending notifications.
    cfg: EmailConfig,
    /// Token to signal worker shutdown.
    cancellation_token: CancellationToken,
    /// Email sender for dispatching messages.
    email_sender: DynEmailSender,
}

impl DeliveryWorker {
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
                    () = sleep(PAUSE_ON_DELIVERY_NONE) => {},
                    () = self.cancellation_token.cancelled() => break,
                },
                Err(err) => {
                    // Something went wrong delivering the notification, pause
                    // unless we've been asked to stop
                    error!(?err, "error delivering notification");
                    tokio::select! {
                        () = sleep(PAUSE_ON_DELIVERY_ERROR) => {},
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
            let err = match self
                .send_email(
                    &notification.email,
                    subject.as_str(),
                    body,
                    &notification.attachments,
                )
                .await
            {
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
                let subject = "You have been invited to join a community team".to_string();
                let template: CommunityTeamInvitation = serde_json::from_value(template_data)?;
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::CfsSubmissionUpdated => {
                let template: CfsSubmissionUpdated = serde_json::from_value(template_data)?;
                let subject = format!("Submission update: {}", template.event.name);
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EmailVerification => {
                let subject = "Verify your email address".to_string();
                let template: EmailVerification = serde_json::from_value(template_data)?;
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventCanceled => {
                let subject = "Event canceled".to_string();
                let template: EventCanceled = serde_json::from_value(template_data)?;
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventCustom => {
                let template: EventCustom = serde_json::from_value(template_data)?;
                let subject = format!("{}: {}", template.event.group_name, template.event.name);
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventPublished => {
                let subject = "New event published".to_string();
                let template: EventPublished = serde_json::from_value(template_data)?;
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventReminder => {
                let template: EventReminder = serde_json::from_value(template_data)?;
                let subject = format!("Reminder: {} starts in 24 hours", template.event.name);
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventRescheduled => {
                let subject = "Event rescheduled".to_string();
                let template: EventRescheduled = serde_json::from_value(template_data)?;
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventWelcome => {
                let subject = "Welcome to the event".to_string();
                let template: EventWelcome = serde_json::from_value(template_data)?;
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::GroupCustom => {
                let template: GroupCustom = serde_json::from_value(template_data)?;
                let subject = template.group.name.clone();
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::GroupTeamInvitation => {
                let subject = "You have been invited to join a group team".to_string();
                let template: GroupTeamInvitation = serde_json::from_value(template_data)?;
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::GroupWelcome => {
                let subject = "Welcome to the group".to_string();
                let template: GroupWelcome = serde_json::from_value(template_data)?;
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::SessionProposalCoSpeakerInvitation => {
                let subject = "Session proposal co-speaker invitation".to_string();
                let template: SessionProposalCoSpeakerInvitation = serde_json::from_value(template_data)?;
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::SpeakerWelcome => {
                let subject = "You're speaking at an event".to_string();
                let template: SpeakerWelcome = serde_json::from_value(template_data)?;
                let body = template.render()?;
                (subject, body)
            }
        };

        Ok((subject, body))
    }

    /// Send an email to the specified address with the given subject and body.
    async fn send_email(
        &self,
        to_address: &str,
        subject: &str,
        body: String,
        attachments: &[Attachment],
    ) -> Result<()> {
        // Prepare email message
        let body_part = SinglePart::builder().header(ContentType::TEXT_HTML).body(body);
        let builder = MessageBuilder::new()
            .from(Mailbox::new(
                Some(self.cfg.from_name.clone()),
                self.cfg.from_address.parse()?,
            ))
            .to(to_address.parse()?)
            .subject(subject);
        let message = if attachments.is_empty() {
            builder.singlepart(body_part)?
        } else {
            let mut multipart = MultiPart::mixed().singlepart(body_part);
            for attachment in attachments {
                let attachment_part = SinglePart::builder()
                    .header(ContentType::parse(&attachment.content_type)?)
                    .header(ContentDisposition::attachment(&attachment.file_name))
                    .body(attachment.data.clone());
                multipart = multipart.singlepart(attachment_part);
            }
            builder.multipart(multipart)?
        };

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

/// Represents a file that should be sent with a notification.
#[derive(Debug, Clone)]
pub(crate) struct Attachment {
    /// MIME type for the attachment body.
    pub content_type: String,
    /// Raw attachment data.
    pub data: Vec<u8>,
    /// File name shown to recipients.
    pub file_name: String,
}

/// Data required to create a new notification.
#[derive(Debug, Clone)]
pub(crate) struct NewNotification {
    /// Files to include in the notification email.
    pub attachments: Vec<Attachment>,
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
    /// Files included with the notification.
    pub attachments: Vec<Attachment>,
    /// Email address to send the notification to.
    pub email: String,
    /// The type of notification.
    pub kind: NotificationKind,
    /// Unique identifier for the notification.
    pub notification_id: Uuid,

    /// Optional template data for the notification content.
    pub template_data: Option<serde_json::Value>,
}

/// Supported notification types.
#[derive(Debug, Clone, Serialize, Deserialize, strum::Display, strum::EnumString)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum NotificationKind {
    /// Notification for a CFS submission update.
    CfsSubmissionUpdated,
    /// Notification for a community team invitation.
    CommunityTeamInvitation,
    /// Notification for email verification.
    EmailVerification,
    /// Notification for an event canceled.
    EventCanceled,
    /// Notification for a custom event message.
    EventCustom,
    /// Notification for an event published.
    EventPublished,
    /// Notification reminding users about an upcoming event.
    EventReminder,
    /// Notification for an event rescheduled.
    EventRescheduled,
    /// Notification welcoming a new event attendee.
    EventWelcome,
    /// Notification for a custom group message.
    GroupCustom,
    /// Notification for a group team invitation.
    GroupTeamInvitation,
    /// Notification welcoming a new group member.
    GroupWelcome,
    /// Notification inviting a co-speaker to respond to a session proposal invitation.
    SessionProposalCoSpeakerInvitation,
    /// Notification welcoming a speaker to an event.
    SpeakerWelcome,
}
