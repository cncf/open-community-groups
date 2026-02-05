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
        EventPublished, EventRescheduled, EventWelcome, GroupCustom, GroupTeamInvitation, GroupWelcome,
        SpeakerWelcome,
    },
};

/// Number of concurrent workers that deliver notifications.
const NUM_WORKERS: usize = 2;

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
    /// Notification welcoming a speaker to an event.
    SpeakerWelcome,
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use anyhow::anyhow;
    use serde_json::json;
    use tokio_util::sync::CancellationToken;
    use uuid::Uuid;

    use crate::{
        config::{EmailConfig, SmtpConfig},
        db::{DynDB, mock::MockDB},
    };

    use super::{
        Attachment, DynEmailSender, MockEmailSender, NewNotification, Notification, NotificationKind,
        NotificationsManager, PgNotificationsManager, Worker,
    };

    #[tokio::test]
    async fn test_notifications_manager_enqueue() {
        // Setup identifiers and data structures
        let recipient = Uuid::new_v4();
        let expected_recipients = vec![recipient];
        let notification = NewNotification {
            attachments: vec![],
            kind: NotificationKind::EmailVerification,
            recipients: expected_recipients.clone(),
            template_data: Some(sample_email_verification_template_data()),
        };

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_enqueue_notification()
            .times(1)
            .withf(move |notif| {
                notif.kind.to_string() == NotificationKind::EmailVerification.to_string()
                    && notif.recipients == expected_recipients
                    && notif.template_data.is_some()
                    && notif.attachments.is_empty()
            })
            .returning(|_| Ok(()));
        let db: DynDB = Arc::new(db);

        // Execute enqueue call
        let manager = PgNotificationsManager { db: db.clone() };
        manager.enqueue(&notification).await.unwrap();
    }

    #[tokio::test]
    async fn test_worker_deliver_notification_sends_pending_notification() {
        // Setup identifiers and data structures
        let client_id = Uuid::new_v4();
        let notification = Notification {
            attachments: vec![],
            email: "notify@example.test".to_string(),
            kind: NotificationKind::EmailVerification,
            notification_id: Uuid::new_v4(),
            template_data: Some(sample_email_verification_template_data()),
        };
        let notification_id = notification.notification_id;
        let recipient = notification.email.clone();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_tx_begin().times(1).returning(move || Ok(client_id));
        db.expect_get_pending_notification()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(move |_| Ok(Some(notification.clone())));
        db.expect_update_notification()
            .times(1)
            .withf(move |cid, notif, err| {
                *cid == client_id && notif.notification_id == notification_id && err.is_none()
            })
            .returning(|_, _, _| Ok(()));
        db.expect_tx_commit()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(|_| Ok(()));
        let db: DynDB = Arc::new(db);

        // Setup email sender mock
        let mut es = MockEmailSender::new();
        es.expect_send()
            .times(1)
            .withf(move |message| {
                message
                    .envelope()
                    .to()
                    .iter()
                    .any(|rcpt| rcpt.to_string() == recipient)
            })
            .returning(|_| Box::pin(async { Ok::<(), anyhow::Error>(()) }));
        let es: DynEmailSender = Arc::new(es);

        // Setup worker and deliver notification
        let mut worker = Worker {
            db,
            cfg: sample_email_config(None),
            cancellation_token: CancellationToken::new(),
            email_sender: es,
        };
        let delivered = worker.deliver_notification().await.unwrap();

        // Check result matches expectations
        assert!(delivered);
    }

    #[tokio::test]
    async fn test_worker_deliver_notification_sends_pending_notification_with_attachment() {
        // Setup identifiers and data structures
        let client_id = Uuid::new_v4();
        let attachments = vec![Attachment {
            content_type: "text/calendar".to_string(),
            data: b"BEGIN:VCALENDAR".to_vec(),
            file_name: "event.ics".to_string(),
        }];
        let notification = Notification {
            attachments: attachments.clone(),
            email: "notify@example.test".to_string(),
            kind: NotificationKind::EmailVerification,
            notification_id: Uuid::new_v4(),
            template_data: Some(sample_email_verification_template_data()),
        };
        let notification_id = notification.notification_id;
        let recipient = notification.email.clone();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_tx_begin().times(1).returning(move || Ok(client_id));
        db.expect_get_pending_notification()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(move |_| Ok(Some(notification.clone())));
        db.expect_update_notification()
            .times(1)
            .withf(move |cid, notif, err| {
                *cid == client_id && notif.notification_id == notification_id && err.is_none()
            })
            .returning(|_, _, _| Ok(()));
        db.expect_tx_commit()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(|_| Ok(()));
        let db: DynDB = Arc::new(db);

        // Setup email sender mock
        let mut es = MockEmailSender::new();
        es.expect_send()
            .times(1)
            .withf(move |message| {
                message
                    .envelope()
                    .to()
                    .iter()
                    .any(|rcpt| rcpt.to_string() == recipient)
            })
            .returning(|_| Box::pin(async { Ok::<(), anyhow::Error>(()) }));
        let es: DynEmailSender = Arc::new(es);

        // Setup worker and deliver notification
        let mut worker = Worker {
            db,
            cfg: sample_email_config(None),
            cancellation_token: CancellationToken::new(),
            email_sender: es,
        };
        let delivered = worker.deliver_notification().await.unwrap();

        // Check result matches expectations
        assert!(delivered);
    }

    #[tokio::test]
    async fn test_worker_deliver_notification_no_pending_notifications() {
        // Setup identifiers and data structures
        let client_id = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_tx_begin().times(1).returning(move || Ok(client_id));
        db.expect_get_pending_notification()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(|_| Ok(None));
        db.expect_tx_rollback()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(|_| Ok(()));
        let db: DynDB = Arc::new(db);

        // Setup email sender mock
        let mut es = MockEmailSender::new();
        es.expect_send().never();
        let es: DynEmailSender = Arc::new(es);

        // Setup worker and deliver notification
        let mut worker = Worker {
            db,
            cfg: sample_email_config(None),
            cancellation_token: CancellationToken::new(),
            email_sender: es,
        };
        let delivered = worker.deliver_notification().await.unwrap();

        // Check result matches expectations
        assert!(!delivered);
    }

    #[tokio::test]
    async fn test_worker_deliver_notification_records_send_error() {
        // Setup identifiers and data structures
        let client_id = Uuid::new_v4();
        let notification = Notification {
            attachments: vec![],
            email: "notify@example.test".to_string(),
            kind: NotificationKind::EmailVerification,
            notification_id: Uuid::new_v4(),
            template_data: Some(sample_email_verification_template_data()),
        };
        let notification_id = notification.notification_id;

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_tx_begin().times(1).returning(move || Ok(client_id));
        db.expect_get_pending_notification()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(move |_| Ok(Some(notification.clone())));
        db.expect_update_notification()
            .times(1)
            .withf(move |cid, notif, err| {
                *cid == client_id
                    && notif.notification_id == notification_id
                    && err.as_deref() == Some("delivery error")
            })
            .returning(|_, _, _| Ok(()));
        db.expect_tx_commit()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(|_| Ok(()));
        let db: DynDB = Arc::new(db);

        // Setup email sender mock
        let mut es = MockEmailSender::new();
        es.expect_send()
            .times(1)
            .returning(|_| Box::pin(async { Err(anyhow!("delivery error")) }));
        let es: DynEmailSender = Arc::new(es);

        // Setup worker and deliver notification
        let mut worker = Worker {
            db,
            cfg: sample_email_config(None),
            cancellation_token: CancellationToken::new(),
            email_sender: es,
        };
        let delivered = worker.deliver_notification().await.unwrap();

        // Check result matches expectations
        assert!(delivered);
    }

    #[test]
    fn test_worker_prepare_content_email_verification() {
        // Setup notification
        let notification = Notification {
            attachments: vec![],
            email: "user@example.test".to_string(),
            kind: NotificationKind::EmailVerification,
            notification_id: Uuid::new_v4(),
            template_data: Some(sample_email_verification_template_data()),
        };

        // Prepare content
        let (subject, body) = Worker::prepare_content(&notification).unwrap();

        // Check content matches expectations
        assert_eq!(subject, "Verify your email address");
        assert!(body.contains("Verify your email"));
        assert!(body.contains("https://example.test/verify"));
    }

    #[test]
    fn test_worker_prepare_content_event_custom() {
        // Setup notification
        let notification = Notification {
            attachments: vec![],
            email: "user@example.test".to_string(),
            kind: NotificationKind::EventCustom,
            notification_id: Uuid::new_v4(),
            template_data: Some(sample_event_custom_template_data()),
        };

        // Prepare content
        let (subject, body) = Worker::prepare_content(&notification).unwrap();

        // Check content matches expectations
        assert_eq!(subject, "Notification Group: Custom Event");
        assert!(body.contains("Custom event body"));
    }

    #[test]
    fn test_worker_prepare_content_group_custom() {
        // Setup notification
        let notification = Notification {
            attachments: vec![],
            email: "user@example.test".to_string(),
            kind: NotificationKind::GroupCustom,
            notification_id: Uuid::new_v4(),
            template_data: Some(sample_group_custom_template_data()),
        };

        // Prepare content
        let (subject, body) = Worker::prepare_content(&notification).unwrap();

        // Check content matches expectations
        assert_eq!(subject, "Hello Group");
        assert!(body.contains("Custom group body"));
    }

    #[test]
    fn test_worker_prepare_content_missing_data() {
        // Setup notification
        let notification = Notification {
            attachments: vec![],
            email: "user@example.test".to_string(),
            kind: NotificationKind::EmailVerification,
            notification_id: Uuid::new_v4(),
            template_data: None,
        };

        // Prepare content and expect an error
        let err = Worker::prepare_content(&notification).unwrap_err();

        // Check error message
        assert!(err.to_string().contains("missing template data"));
    }

    #[tokio::test]
    async fn test_worker_send_email_allows_whitelisted_recipient() {
        // Setup email config and sender mock
        let cfg = sample_email_config(Some(vec!["notify@example.test".to_string()]));
        let mut es = MockEmailSender::new();
        es.expect_send()
            .times(1)
            .withf(|message| {
                message
                    .envelope()
                    .to()
                    .iter()
                    .any(|rcpt| rcpt.to_string() == "notify@example.test")
            })
            .returning(|_| Box::pin(async { Ok::<(), anyhow::Error>(()) }));
        let es: DynEmailSender = Arc::new(es);

        // Setup worker and send email
        let worker = sample_worker(cfg, es);
        worker
            .send_email(
                "notify@example.test",
                "Subject line",
                "<p>Body content</p>".to_string(),
                &[],
            )
            .await
            .unwrap();
    }

    #[tokio::test]
    async fn test_worker_send_email_blocks_non_whitelisted_recipient() {
        // Setup email config and sender mock
        let cfg = sample_email_config(Some(vec!["notify@example.test".to_string()]));
        let mut es = MockEmailSender::new();
        es.expect_send().never();
        let es: DynEmailSender = Arc::new(es);

        // Setup worker and send email
        let worker = sample_worker(cfg, es);
        worker
            .send_email(
                "other@example.test",
                "Subject line",
                "<p>Body content</p>".to_string(),
                &[],
            )
            .await
            .unwrap();
    }

    // Helpers.

    /// Create a sample email configuration with an optional recipients whitelist.
    fn sample_email_config(rcpts_whitelist: Option<Vec<String>>) -> EmailConfig {
        EmailConfig {
            from_address: "no-reply@example.test".to_string(),
            from_name: "Open Community Groups".to_string(),
            smtp: SmtpConfig {
                host: "smtp.example.test".to_string(),
                port: 587,
                username: "user".to_string(),
                password: "pass".to_string(),
            },

            rcpts_whitelist,
        }
    }

    /// Create a sample worker with mock dependencies.
    fn sample_worker(cfg: EmailConfig, email_sender: DynEmailSender) -> Worker {
        let db: DynDB = Arc::new(MockDB::new());

        Worker {
            db,
            cfg,
            cancellation_token: CancellationToken::new(),
            email_sender,
        }
    }

    /// Sample template payload for email verification notifications.
    fn sample_email_verification_template_data() -> serde_json::Value {
        json!({
            "link": "https://example.test/verify",
            "theme": {
                "primary_color": "#000000"
            }
        })
    }

    /// Sample template payload for custom event notifications.
    fn sample_event_custom_template_data() -> serde_json::Value {
        json!({
            "title": "Custom event title",
            "body": "Custom event body",
            "event": {
                "canceled": false,
                "community_display_name": "Test Community",
                "community_name": "test-community",
                "event_id": "11111111-1111-1111-1111-111111111111",
                "group_category_name": "Community",
                "group_name": "Notification Group",
                "group_slug": "notification-group",
                "kind": "virtual",
                "logo_url": "https://example.com/logo.png",
                "name": "Custom Event",
                "published": true,
                "slug": "custom-event",
                "timezone": "UTC"
            },
            "link": "https://example.test/test-community/group/notification-group/event/custom-event",
            "theme": {
                "primary_color": "#000000"
            }
        })
    }

    /// Sample template payload for custom group notifications.
    fn sample_group_custom_template_data() -> serde_json::Value {
        json!({
            "title": "Custom group title",
            "body": "Custom group body",
            "group": {
                "active": true,
                "category": {
                    "group_category_id": "22222222-2222-2222-2222-222222222222",
                    "name": "Sample Category",
                    "normalized_name": "sample-category"
                },
                "community_display_name": "Test Community",
                "community_name": "test-community",
                "created_at": 1,
                "group_id": "33333333-3333-3333-3333-333333333333",
                "logo_url": "https://example.com/logo.png",
                "name": "Hello Group",
                "slug": "hello-group"
            },
            "link": "https://example.test/test-community/group/hello-group",
            "theme": {
                "primary_color": "#000000"
            }
        })
    }
}
