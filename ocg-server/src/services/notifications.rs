//! This module defines types and logic to manage and send user notifications.

use std::{sync::Arc, time::Duration};

use anyhow::{Result, anyhow};
use askama::Template;
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use lettre::{
    AsyncSmtpTransport, AsyncTransport, Message, Tokio1Executor,
    message::{
        Mailbox, MessageBuilder, MultiPart, SinglePart,
        header::{ContentDisposition, ContentType},
    },
    transport::smtp::{
        AsyncSmtpTransportBuilder, Error as SmtpError, SUBMISSIONS_PORT,
        authentication::Credentials,
    },
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
    db::{DBOperations, DynDB},
    services::workers::{
        WorkerIteration,
        claim_loop::{self, ClaimLoopConfig},
        run_worker,
    },
    templates::{
        helpers,
        notifications::{
            BadgeAwarded, BadgeRevoked, CfsSubmissionUpdated, CommunityTeamInvitation,
            EmailVerification, EventAdmissionOfferCanceled, EventAdmissionOfferCreated,
            EventAdmissionOfferDeclined, EventAttendanceCanceled, EventCanceled, EventCustom,
            EventInvitation, EventPaidConfigured, EventPublished, EventRefundApproved,
            EventRefundRejected, EventRefundRequested, EventReminder, EventRescheduled,
            EventSeriesCanceled, EventSeriesPublished, EventTicketRequestApproved,
            EventTicketWaitlistOffer, EventWaitlistJoined, EventWaitlistLeft,
            EventWaitlistPromoted, EventWelcome, GroupCustom, GroupTeamInvitation, GroupWelcome,
            SessionProposalCoSpeakerInvitation, SpeakerSeriesWelcome, SpeakerWelcome,
        },
    },
    types::{event::EventSummary, site::SiteSettings},
    util::base_url_without_trailing_slash,
};

pub(crate) mod enqueue;
pub(crate) mod payloads;

#[cfg(test)]
mod tests;

/// Maximum number of delivery claims before a retryable failure becomes terminal.
const DELIVERY_MAX_CLAIMS: usize = 10;

/// Time after which a claimed notification requires manual delivery review.
const DELIVERY_PROCESSING_TIMEOUT: Duration = Duration::from_mins(15);

/// Initial delay before requeueing a retryable notification delivery failure.
const DELIVERY_REQUEUE_BASE_DELAY: Duration = Duration::from_mins(1);

/// Maximum delay before requeueing a retryable notification delivery failure.
const DELIVERY_REQUEUE_MAX_DELAY: Duration = Duration::from_mins(30);

/// Maximum number of attempts for one notification delivery claim.
const DELIVERY_SEND_MAX_ATTEMPTS: usize = 3;

/// Number of workers that recover stale notification delivery claims.
const NUM_DELIVERY_RECOVERY_WORKERS: usize = 1;

/// Number of concurrent workers that deliver notifications.
const NUM_DELIVERY_WORKERS: usize = 2;

/// Number of workers that enqueue due notifications.
const NUM_ENQUEUE_WORKERS: usize = 1;

/// Time to wait after a delivery error before retrying.
const PAUSE_ON_DELIVERY_ERROR: Duration = Duration::from_secs(10);

/// Time to wait when there are no notifications to deliver.
const PAUSE_ON_DELIVERY_NONE: Duration = Duration::from_secs(15);

/// Time to wait after a delivery recovery error before retrying.
const PAUSE_ON_DELIVERY_RECOVERY_ERROR: Duration = Duration::from_secs(30);

/// Time to wait between delivery recovery checks.
const PAUSE_ON_DELIVERY_RECOVERY_NONE: Duration = Duration::from_mins(1);

/// Time to wait before retrying a transient notification delivery error.
const PAUSE_ON_DELIVERY_RETRY: Duration = Duration::from_secs(5);

/// Time to wait after an enqueue error before retrying.
const PAUSE_ON_ENQUEUE_ERROR: Duration = Duration::from_secs(30);

/// Time to wait when there are no due notifications to enqueue.
const PAUSE_ON_ENQUEUE_NONE: Duration = Duration::from_mins(5);

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
        // Normalize the shared base URL before cloning it into workers
        let base_url = base_url_without_trailing_slash(base_url).to_string();

        // Setup and run workers to enqueue due notifications
        for _ in 1..=NUM_ENQUEUE_WORKERS {
            let worker = EnqueueWorker {
                base_url: base_url.clone(),
                cancellation_token: cancellation_token.clone(),
                db: db.clone(),
            };
            task_tracker.spawn(async move {
                worker.run().await;
            });
        }

        // Setup and run workers to recover abandoned notification delivery claims
        for _ in 1..=NUM_DELIVERY_RECOVERY_WORKERS {
            let worker = DeliveryRecoveryWorker {
                cancellation_token: cancellation_token.clone(),
                db: db.clone(),
            };
            task_tracker.spawn(async move {
                worker.run().await;
            });
        }

        // Setup and run workers to deliver notifications
        for _ in 1..=NUM_DELIVERY_WORKERS {
            let worker = DeliveryWorker {
                base_url: base_url.clone(),
                cancellation_token: cancellation_token.clone(),
                cfg: cfg.clone(),
                db: db.clone(),
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
    /// Base URL used for generated links in reminders.
    base_url: String,
    /// Token to signal worker shutdown.
    cancellation_token: CancellationToken,
    /// Database handle for notification queries.
    db: DynDB,
}

impl EnqueueWorker {
    /// Main worker loop: enqueues due notifications until cancelled.
    async fn run(&self) {
        run_worker(&self.cancellation_token, || async {
            // Enqueue due notifications and select the next maintenance cadence
            let pause = match self.enqueue_due_notifications().await {
                Ok(_) => PAUSE_ON_ENQUEUE_NONE,
                Err(err) => {
                    error!(error = %err, "error enqueueing due notifications");
                    PAUSE_ON_ENQUEUE_ERROR
                }
            };
            WorkerIteration::Pause(pause)
        })
        .await;
    }

    /// Enqueue due notifications and return the number enqueued.
    #[instrument(skip(self), err)]
    async fn enqueue_due_notifications(&self) -> Result<usize> {
        self.db.enqueue_due_event_reminders(&self.base_url).await
    }
}

/// Worker responsible for marking abandoned delivery claims as unknown.
struct DeliveryRecoveryWorker {
    /// Token to signal worker shutdown.
    cancellation_token: CancellationToken,
    /// Database handle for notification queries.
    db: DynDB,
}

impl DeliveryRecoveryWorker {
    /// Main worker loop: marks stale processing notifications until cancelled.
    async fn run(&self) {
        run_worker(&self.cancellation_token, || async {
            // Recover stale delivery claims and select the next maintenance cadence
            let pause = match self.mark_stale_processing_notifications_unknown().await {
                Ok(recovered) => {
                    if recovered > 0 {
                        warn!(recovered, "marked stale notification deliveries unknown");
                    }
                    PAUSE_ON_DELIVERY_RECOVERY_NONE
                }
                Err(err) => {
                    error!(error = %err, "error recovering stale notification deliveries");
                    PAUSE_ON_DELIVERY_RECOVERY_ERROR
                }
            };
            WorkerIteration::Pause(pause)
        })
        .await;
    }

    /// Mark stale processing notifications with an unknown delivery outcome.
    #[instrument(skip(self), err)]
    async fn mark_stale_processing_notifications_unknown(&self) -> Result<usize> {
        self.db
            .mark_stale_processing_notifications_unknown(DELIVERY_PROCESSING_TIMEOUT)
            .await
    }
}

/// Worker responsible for delivering notifications from the queue.
struct DeliveryWorker {
    /// Base URL used to make database-enqueued badge links absolute.
    base_url: String,
    /// Token to signal worker shutdown.
    cancellation_token: CancellationToken,
    /// Email configuration for sending notifications.
    cfg: EmailConfig,
    /// Database handle for notification queries.
    db: DynDB,
    /// Email sender for dispatching messages.
    email_sender: DynEmailSender,
}

impl DeliveryWorker {
    /// Main worker loop: delivers notifications until cancelled.
    async fn run(&self) {
        claim_loop::run(
            &self.cancellation_token,
            ClaimLoopConfig {
                pause_on_error: PAUSE_ON_DELIVERY_ERROR,
                pause_on_none: PAUSE_ON_DELIVERY_NONE,
            },
            || self.deliver_notification(),
            |err| {
                error!(error = %err, "error delivering notification");
                None
            },
        )
        .await;
    }

    /// Attempt to deliver a pending notification, if available.
    #[instrument(skip(self), err)]
    async fn deliver_notification(&self) -> Result<bool> {
        // Claim a notification before any external delivery side effects
        let Some(notification) = self.db.claim_pending_notification().await? else {
            return Ok(false);
        };

        // Prepare and send the notification
        match Self::prepare_content(&notification, &self.base_url) {
            Ok((subject, body)) => match self
                .send_email_with_retries(
                    &notification.email,
                    subject.as_str(),
                    body,
                    &notification.attachments,
                )
                .await
            {
                Ok(()) => self.db.update_notification(&notification, None).await?,
                Err(err) => self.record_delivery_error(&notification, err).await?,
            },
            Err(err) => {
                self.db
                    .update_notification(&notification, Some(err.to_string()))
                    .await?;
            }
        }

        Ok(true)
    }

    /// Prepare the subject and body for a notification email.
    #[allow(clippy::too_many_lines)]
    fn prepare_content(notification: &Notification, base_url: &str) -> Result<(String, String)> {
        // Load the queued data before dispatching to its typed renderer
        let template_data = notification
            .template_data
            .clone()
            .ok_or_else(|| anyhow!("missing template data"))?;

        let (subject, body) = match notification.kind {
            NotificationKind::BadgeAwarded => {
                // Complete deployment-specific URLs after typed deserialization
                let mut template: BadgeAwarded = serde_json::from_value(template_data)?;
                if template.dashboard_url.starts_with('/') {
                    template.dashboard_url =
                        helpers::absolute_url(base_url, &template.dashboard_url);
                }
                template.base_url = base_url.to_string();
                let base_subject = format!("You earned the {} badge", template.badge.name);
                let subject =
                    Self::scoped_subject(&template.badge.issuer.group_name, &base_subject);
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::BadgeRevoked => {
                // Complete the deployment-specific dashboard URL after typed deserialization
                let mut template: BadgeRevoked = serde_json::from_value(template_data)?;
                if template.dashboard_url.starts_with('/') {
                    template.dashboard_url =
                        helpers::absolute_url(base_url, &template.dashboard_url);
                }
                let base_subject = format!("Your {} badge was revoked", template.badge_name);
                let subject = Self::scoped_subject(&template.group_name, &base_subject);
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::CfsSubmissionUpdated => {
                let template: CfsSubmissionUpdated = serde_json::from_value(template_data)?;
                let base_subject = format!("Submission update: {}", template.event.name);
                let subject = Self::scoped_subject(&template.event.group_name, &base_subject);
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::CommunityTeamInvitation => {
                let template: CommunityTeamInvitation = serde_json::from_value(template_data)?;
                let subject = Self::scoped_subject(
                    &template.community_name,
                    "You have been invited to join a community team",
                );
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EmailVerification => {
                let subject = "Verify your email address".to_string();
                let template: EmailVerification = serde_json::from_value(template_data)?;
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventAdmissionOfferCanceled => {
                // Complete the deployment-specific dashboard URL after typed deserialization
                let mut template: EventAdmissionOfferCanceled =
                    serde_json::from_value(template_data)?;
                if template.dashboard_url.starts_with('/') {
                    template.dashboard_url =
                        helpers::absolute_url(base_url, &template.dashboard_url);
                }
                let subject =
                    Self::scoped_subject(&template.group_name, "Your event offer was canceled");
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventAdmissionOfferCreated => {
                // Complete the deployment-specific dashboard URL after typed deserialization
                let mut template: EventAdmissionOfferCreated =
                    serde_json::from_value(template_data)?;
                if template.dashboard_url.starts_with('/') {
                    template.dashboard_url =
                        helpers::absolute_url(base_url, &template.dashboard_url);
                }
                let subject =
                    Self::scoped_subject(&template.group_name, "You have a new event offer");
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventAdmissionOfferDeclined => {
                // Complete the deployment-specific dashboard URL after typed deserialization
                let mut template: EventAdmissionOfferDeclined =
                    serde_json::from_value(template_data)?;
                if template.dashboard_url.starts_with('/') {
                    template.dashboard_url =
                        helpers::absolute_url(base_url, &template.dashboard_url);
                }
                let subject = Self::scoped_subject(&template.group_name, "Event offer declined");
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventAttendanceCanceled => {
                let template: EventAttendanceCanceled = serde_json::from_value(template_data)?;
                let subject =
                    Self::scoped_subject(&template.event.group_name, "Attendance canceled");
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventCanceled => {
                let template: EventCanceled = serde_json::from_value(template_data)?;
                let subject = Self::scoped_subject(&template.event.group_name, "Event canceled");
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventCustom => {
                let template: EventCustom = serde_json::from_value(template_data)?;
                let subject = template.subject.clone();
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventInvitation => {
                let template: EventInvitation = serde_json::from_value(template_data)?;
                let subject = Self::scoped_subject(
                    &template.event.group_name,
                    "You have been invited to an event",
                );
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventPaidConfigured => {
                let template: EventPaidConfigured = serde_json::from_value(template_data)?;
                let base_subject = if template.event_count == 1 {
                    "Paid event configured"
                } else {
                    "Paid events configured"
                };
                let subject = Self::scoped_subject(&template.group_name, base_subject);
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventPublished => {
                let template: EventPublished = serde_json::from_value(template_data)?;
                let subject =
                    Self::scoped_subject(&template.event.group_name, "New event published");
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventRefundApproved => {
                let template: EventRefundApproved = serde_json::from_value(template_data)?;
                let subject = Self::scoped_subject(&template.event.group_name, "Refund approved");
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventRefundRejected => {
                let template: EventRefundRejected = serde_json::from_value(template_data)?;
                let subject =
                    Self::scoped_subject(&template.event.group_name, "Refund request update");
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventRefundRequested => {
                let template: EventRefundRequested = serde_json::from_value(template_data)?;
                let subject = Self::scoped_subject(&template.event.group_name, "Refund requested");
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventReminder => {
                let template: EventReminder = serde_json::from_value(template_data)?;
                let base_subject = format!("Reminder: {} starts in 24 hours", template.event.name);
                let subject = Self::scoped_subject(&template.event.group_name, &base_subject);
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventRescheduled => {
                let template: EventRescheduled = serde_json::from_value(template_data)?;
                let subject = Self::scoped_subject(&template.event.group_name, "Event rescheduled");
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventSeriesCanceled => {
                let template: EventSeriesCanceled = serde_json::from_value(template_data)?;
                let subject = Self::scoped_subject(&template.group_name, "Events canceled");
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventSeriesPublished => {
                let template: EventSeriesPublished = serde_json::from_value(template_data)?;
                let subject = Self::scoped_subject(&template.group_name, "New events published");
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventTicketRequestApproved => {
                // Complete the deployment-specific dashboard URL after typed deserialization
                let mut template: EventTicketRequestApproved =
                    serde_json::from_value(template_data)?;
                if template.dashboard_url.starts_with('/') {
                    template.dashboard_url =
                        helpers::absolute_url(base_url, &template.dashboard_url);
                }
                let subject =
                    Self::scoped_subject(&template.group_name, "Your event request was approved");
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventTicketWaitlistOffer => {
                // Complete the deployment-specific dashboard URL after typed deserialization
                let mut template: EventTicketWaitlistOffer = serde_json::from_value(template_data)?;
                if template.dashboard_url.starts_with('/') {
                    template.dashboard_url =
                        helpers::absolute_url(base_url, &template.dashboard_url);
                }
                let subject =
                    Self::scoped_subject(&template.group_name, "A place is available for you");
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventWaitlistJoined => {
                let template: EventWaitlistJoined = serde_json::from_value(template_data)?;
                let subject =
                    Self::scoped_subject(&template.event.group_name, "You joined the waiting list");
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventWaitlistLeft => {
                let template: EventWaitlistLeft = serde_json::from_value(template_data)?;
                let subject =
                    Self::scoped_subject(&template.event.group_name, "You left the waiting list");
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventWaitlistPromoted => {
                let template: EventWaitlistPromoted = serde_json::from_value(template_data)?;
                let subject = Self::scoped_subject(
                    &template.event.group_name,
                    "You moved off the waiting list",
                );
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::EventWelcome => {
                let template: EventWelcome = serde_json::from_value(template_data)?;
                let subject =
                    Self::scoped_subject(&template.event.group_name, "Welcome to the event");
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::GroupCustom => {
                let template: GroupCustom = serde_json::from_value(template_data)?;
                let subject = template.subject.clone();
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::GroupTeamInvitation => {
                let template: GroupTeamInvitation = serde_json::from_value(template_data)?;
                let subject = Self::scoped_subject(
                    &template.group.name,
                    "You have been invited to join a group team",
                );
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::GroupWelcome => {
                let template: GroupWelcome = serde_json::from_value(template_data)?;
                let subject = Self::scoped_subject(&template.group.name, "Welcome to the group");
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::SessionProposalCoSpeakerInvitation => {
                let subject = "Session proposal co-speaker invitation".to_string();
                let template: SessionProposalCoSpeakerInvitation =
                    serde_json::from_value(template_data)?;
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::SpeakerSeriesWelcome => {
                let template: SpeakerSeriesWelcome = serde_json::from_value(template_data)?;
                let subject = Self::scoped_subject(
                    &template.group_name,
                    "You're speaking at upcoming events",
                );
                let body = template.render()?;
                (subject, body)
            }
            NotificationKind::SpeakerWelcome => {
                let template: SpeakerWelcome = serde_json::from_value(template_data)?;
                let subject =
                    Self::scoped_subject(&template.event.group_name, "You're speaking at an event");
                let body = template.render()?;
                (subject, body)
            }
        };

        Ok((subject, body))
    }

    /// Records a delivery error according to its safe recovery action.
    async fn record_delivery_error(
        &self,
        notification: &Notification,
        err: EmailDeliveryError,
    ) -> Result<()> {
        // Persist the safest recovery action for the classified delivery failure
        let error = err.to_string();
        match err {
            EmailDeliveryError::Retryable(_) => {
                self.db
                    .requeue_notification(
                        notification,
                        &error,
                        DELIVERY_REQUEUE_BASE_DELAY,
                        DELIVERY_REQUEUE_MAX_DELAY,
                        DELIVERY_MAX_CLAIMS,
                    )
                    .await
            }
            EmailDeliveryError::Terminal(_) => {
                self.db.update_notification(notification, Some(error)).await
            }
            EmailDeliveryError::Unknown(_) => {
                self.db.mark_notification_delivery_unknown(notification, &error).await
            }
        }
    }

    /// Builds an email subject prefixed with its community or group scope.
    fn scoped_subject(scope: &str, subject: &str) -> String {
        format!("[{scope}] {subject}")
    }

    /// Send an email to the specified address with the given subject and body.
    async fn send_email(
        &self,
        to_address: &str,
        subject: &str,
        body: String,
        attachments: &[Attachment],
    ) -> std::result::Result<(), EmailDeliveryError> {
        // Prepare email message
        let body_part = SinglePart::builder().header(ContentType::TEXT_HTML).body(body);
        let builder = MessageBuilder::new()
            .from(Mailbox::new(
                Some(self.cfg.from_name.clone()),
                self.cfg.from_address.parse().map_err(EmailDeliveryError::terminal)?,
            ))
            .to(to_address.parse().map_err(EmailDeliveryError::terminal)?)
            .subject(subject);
        let message = if attachments.is_empty() {
            builder.singlepart(body_part).map_err(EmailDeliveryError::terminal)?
        } else {
            let mut multipart = MultiPart::mixed().singlepart(body_part);
            for attachment in attachments {
                let attachment_part = SinglePart::builder()
                    .header(
                        ContentType::parse(&attachment.content_type)
                            .map_err(EmailDeliveryError::terminal)?,
                    )
                    .header(ContentDisposition::attachment(&attachment.file_name))
                    .body(attachment.data.clone());
                multipart = multipart.singlepart(attachment_part);
            }
            builder.multipart(multipart).map_err(EmailDeliveryError::terminal)?
        };

        // Send email
        if let Some(whitelist) = &self.cfg.rcpts_whitelist {
            // Reject every recipient when the configured whitelist is empty
            let allowed = !whitelist.is_empty() && whitelist.iter().any(|wa| wa == to_address);
            if !allowed {
                warn!(%to_address, "email recipient not allowed; skipping send");
                return Ok(());
            }
        }
        self.email_sender.send(message).await?;

        Ok(())
    }

    /// Send an email and retry transient transport errors before giving up.
    async fn send_email_with_retries(
        &self,
        to_address: &str,
        subject: &str,
        body: String,
        attachments: &[Attachment],
    ) -> std::result::Result<(), EmailDeliveryError> {
        let mut attempt = 1;
        loop {
            match self.send_email(to_address, subject, body.clone(), attachments).await {
                Ok(()) => return Ok(()),
                Err(err) if attempt < DELIVERY_SEND_MAX_ATTEMPTS && err.is_retryable() => {
                    warn!(
                        %to_address,
                        attempt,
                        next_attempt = attempt + 1,
                        max_attempts = DELIVERY_SEND_MAX_ATTEMPTS,
                        error = %err,
                        "transient notification email delivery error; retrying",
                    );
                    sleep(PAUSE_ON_DELIVERY_RETRY).await;
                    attempt += 1;
                }
                Err(err) => return Err(err),
            }
        }
    }
}

/// Trait representing an async email sender used by the notifications workers.
#[async_trait]
#[cfg_attr(test, automock)]
pub(crate) trait EmailSender {
    /// Send an email represented by the provided message.
    async fn send(&self, message: Message) -> std::result::Result<(), EmailDeliveryError>;
}

/// Shared trait object for an email sender.
pub(crate) type DynEmailSender = Arc<dyn EmailSender + Send + Sync>;

/// Concrete email sender backed by a Lettre SMTP transport.
pub(crate) struct LettreEmailSender {
    /// SMTP transport used to deliver messages.
    transport: AsyncSmtpTransport<Tokio1Executor>,
}

impl LettreEmailSender {
    /// Create a new `LettreEmailSender` from the provided config.
    pub(crate) fn new(cfg: &EmailConfig) -> Result<Self> {
        let transport = Self::transport_builder(cfg)?
            .credentials(Credentials::new(
                cfg.smtp.username.clone(),
                cfg.smtp.password.clone(),
            ))
            .build();

        Ok(Self { transport })
    }

    /// Create a SMTP transport builder for the configured server.
    fn transport_builder(cfg: &EmailConfig) -> Result<AsyncSmtpTransportBuilder> {
        // Use implicit TLS on port 465 and STARTTLS on other submission ports
        let builder = if cfg.smtp.port == SUBMISSIONS_PORT {
            AsyncSmtpTransport::<Tokio1Executor>::relay(&cfg.smtp.host)?
        } else {
            AsyncSmtpTransport::<Tokio1Executor>::starttls_relay(&cfg.smtp.host)?
        };

        Ok(builder.port(cfg.smtp.port))
    }
}

#[async_trait]
impl EmailSender for LettreEmailSender {
    /// [`EmailSender::send`].
    async fn send(&self, message: Message) -> std::result::Result<(), EmailDeliveryError> {
        self.transport
            .send(message)
            .await
            .map_err(EmailDeliveryError::from_smtp)?;
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

/// Error returned while sending an email, classified by its safe recovery action.
#[derive(Debug)]
pub(crate) enum EmailDeliveryError {
    /// Failure that can be retried without risking duplicate delivery.
    Retryable(anyhow::Error),
    /// Failure that cannot succeed without changing the message or configuration.
    Terminal(anyhow::Error),
    /// Failure whose delivery outcome cannot be determined safely.
    Unknown(anyhow::Error),
}

impl EmailDeliveryError {
    /// Classifies a Lettre SMTP error by the safest recovery action.
    fn from_smtp(err: SmtpError) -> Self {
        // Extract transport metadata before preserving the original error source
        let kind = if err.is_client() {
            SmtpErrorKind::Client
        } else if err.to_string().starts_with("Connection error") {
            SmtpErrorKind::Connection
        } else if err.is_permanent() {
            SmtpErrorKind::Permanent
        } else if err.is_tls() {
            SmtpErrorKind::Tls
        } else if err.is_transient() {
            SmtpErrorKind::Transient
        } else if err.is_transport_shutdown() {
            SmtpErrorKind::TransportShutdown
        } else {
            SmtpErrorKind::Unknown
        };

        // Preserve the error source in the classified delivery failure
        Self::from_smtp_kind(kind, err.into())
    }

    /// Classifies an SMTP category while preserving its error source.
    fn from_smtp_kind(kind: SmtpErrorKind, err: anyhow::Error) -> Self {
        match kind {
            // Message or configuration failures require an external correction
            SmtpErrorKind::Client | SmtpErrorKind::Permanent | SmtpErrorKind::Tls => {
                Self::Terminal(err)
            }
            // Treat pre-submission failures as safe to retry
            SmtpErrorKind::Connection
            | SmtpErrorKind::Transient
            | SmtpErrorKind::TransportShutdown => Self::Retryable(err),
            // Network, timeout, and malformed response errors may follow submission
            SmtpErrorKind::Unknown => Self::Unknown(err),
        }
    }

    /// Returns whether retrying cannot duplicate a potentially delivered email.
    fn is_retryable(&self) -> bool {
        matches!(self, Self::Retryable(_))
    }

    /// Wraps a message preparation error as terminal.
    fn terminal(err: impl Into<anyhow::Error>) -> Self {
        Self::Terminal(err.into())
    }
}

impl std::fmt::Display for EmailDeliveryError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Retryable(err) | Self::Terminal(err) | Self::Unknown(err) => write!(f, "{err}"),
        }
    }
}

impl std::error::Error for EmailDeliveryError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Retryable(err) | Self::Terminal(err) | Self::Unknown(err) => Some(err.as_ref()),
        }
    }
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
    /// Timestamp identifying the active delivery claim.
    pub delivery_claimed_at: DateTime<Utc>,
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
    /// Notification for a newly awarded badge.
    BadgeAwarded,
    /// Notification for a permanently revoked badge.
    BadgeRevoked,
    /// Notification for a CFS submission update.
    CfsSubmissionUpdated,
    /// Notification for a community team invitation.
    CommunityTeamInvitation,
    /// Notification for email verification.
    EmailVerification,
    /// Notification for a canceled event admission offer.
    EventAdmissionOfferCanceled,
    /// Notification for a newly created organizer event admission offer.
    EventAdmissionOfferCreated,
    /// Notification for an organizer whose event admission offer was declined.
    EventAdmissionOfferDeclined,
    /// Notification for a canceled event attendance.
    EventAttendanceCanceled,
    /// Notification for an event canceled.
    EventCanceled,
    /// Notification for a custom event message.
    EventCustom,
    /// Notification for an organizer-created event invitation.
    EventInvitation,
    /// Notification for paid events configured by an organizer.
    EventPaidConfigured,
    /// Notification for an event published.
    EventPublished,
    /// Notification for an approved refund.
    EventRefundApproved,
    /// Notification for a rejected refund request.
    EventRefundRejected,
    /// Notification for a newly requested refund.
    EventRefundRequested,
    /// Notification reminding users about an upcoming event.
    EventReminder,
    /// Notification for an event rescheduled.
    EventRescheduled,
    /// Notification for multiple canceled events in a linked series.
    EventSeriesCanceled,
    /// Notification for multiple published events in a linked series.
    EventSeriesPublished,
    /// Notification for an approved ticket request offer.
    EventTicketRequestApproved,
    /// Notification for an offer created from a ticket waiting list.
    EventTicketWaitlistOffer,
    /// Notification for joining an event waiting list.
    EventWaitlistJoined,
    /// Notification for leaving an event waiting list.
    EventWaitlistLeft,
    /// Notification for being promoted from an event waiting list.
    EventWaitlistPromoted,
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
    /// Notification welcoming a speaker to multiple events in a linked series.
    SpeakerSeriesWelcome,
    /// Notification welcoming a speaker to an event.
    SpeakerWelcome,
}

/// SMTP failure category relevant to notification recovery.
#[derive(Debug, Clone, Copy)]
enum SmtpErrorKind {
    /// Internal Lettre client failure.
    Client,
    /// Failure while establishing the SMTP connection.
    Connection,
    /// Permanent SMTP server response.
    Permanent,
    /// TLS negotiation or validation failure.
    Tls,
    /// Transient SMTP server response.
    Transient,
    /// Attempt to use a transport that was already shut down.
    TransportShutdown,
    /// Failure without a safe automatic recovery action.
    Unknown,
}

/// Loads the shared event and site context used to compose event notifications.
pub(crate) async fn load_event_notification_context(
    db: &dyn DBOperations,
    community_id: Uuid,
    event_id: Uuid,
) -> Result<(EventSummary, SiteSettings)> {
    // Load the independent site and event notification context concurrently
    let (site_settings, event) = tokio::try_join!(
        db.get_site_settings(),
        db.get_event_summary_by_id(community_id, event_id),
    )?;

    Ok((event, site_settings))
}
