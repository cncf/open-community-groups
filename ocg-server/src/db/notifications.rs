//! This module defines database functionality used to manage notifications, including
//! enqueueing, retrieving, and updating notification records.

use std::time::Duration;

use anyhow::{Result, anyhow};
use async_trait::async_trait;
use base64::{Engine, engine::general_purpose::STANDARD as BASE64};
use cached::cached;
use serde::Serialize;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::{PgClient, PgExecutor},
    services::notifications::{Attachment, NewNotification, Notification},
};

/// Trait that defines database operations used to manage notifications.
#[async_trait]
pub(crate) trait DBNotifications {
    /// Claims a pending notification for delivery.
    async fn claim_pending_notification(&self) -> Result<Option<Notification>>;

    /// Enqueues due event reminders and returns the number of notifications created.
    async fn enqueue_due_event_reminders(&self, base_url: &str) -> Result<usize>;

    /// Enqueues a notification to be delivered.
    async fn enqueue_notification(&self, notification: &NewNotification) -> Result<()>;

    /// Enqueues and tracks a custom notification atomically.
    async fn enqueue_tracked_custom_notification(
        &self,
        notification: &NewNotification,
        tracking: CustomNotificationTracking,
    ) -> Result<()>;

    /// Retrieves a notification attachment by its ID.
    async fn get_notification_attachment(&self, attachment_id: Uuid) -> Result<Attachment>;

    /// Marks stale claimed notifications with an unknown delivery outcome.
    async fn mark_stale_processing_notifications_unknown(&self, timeout: Duration)
    -> Result<usize>;

    /// Requeues a notification after a retryable delivery error.
    async fn requeue_notification(
        &self,
        notification: &Notification,
        error: &str,
        base_retry_after: Duration,
        max_retry_after: Duration,
        max_delivery_attempts: usize,
    ) -> Result<()>;

    /// Updates a notification after a delivery attempt.
    async fn update_notification(
        &self,
        notification: &Notification,
        error: Option<String>,
    ) -> Result<()>;
}

#[async_trait]
impl<T> DBNotifications for T
where
    T: PgExecutor + Send + Sync,
{
    #[instrument(skip(self), err)]
    async fn claim_pending_notification(&self) -> Result<Option<Notification>> {
        // Claim pending notification (if any)
        let db = self.client().await?;
        let Some(row) = db
            .query_opt("select * from claim_pending_notification();", &[])
            .await?
        else {
            return Ok(None);
        };

        // Fetch notification attachments
        let notification_id: Uuid = row.get("notification_id");
        let attachment_ids = row.get::<_, Option<Vec<Uuid>>>("attachment_ids").unwrap_or_default();
        let mut attachments = Vec::with_capacity(attachment_ids.len());
        for attachment_id in attachment_ids {
            let attachment = match self.get_notification_attachment(attachment_id).await {
                Ok(attachment) => attachment,
                Err(err) => {
                    // Finalize pre-send failures so claimed rows are not stranded
                    let error = err.to_string();
                    db.execute(
                        "
                        select update_notification($1::uuid, $2::text);
                        ",
                        &[&notification_id, &error],
                    )
                    .await?;
                    return Err(err);
                }
            };
            attachments.push(attachment);
        }

        // Prepare notification and return it
        let notification = Notification {
            email: row.get("email"),
            kind: row
                .get::<_, String>("kind")
                .as_str()
                .try_into()
                .expect("kind to be valid"),
            notification_id,
            template_data: row.get("template_data"),
            attachments,
        };

        Ok(Some(notification))
    }

    #[instrument(skip(self), err)]
    async fn enqueue_due_event_reminders(&self, base_url: &str) -> Result<usize> {
        let db = self.client().await?;
        let count = db
            .query_one(
                "
                select enqueue_due_event_reminders($1::text)::int;
                ",
                &[&base_url],
            )
            .await?
            .get::<_, i32>(0);
        let count = usize::try_from(count)
            .map_err(|_| anyhow!("enqueued reminders count cannot be negative"))?;

        Ok(count)
    }

    #[instrument(skip(self, notification), err)]
    async fn enqueue_notification(&self, notification: &NewNotification) -> Result<()> {
        // Nothing to enqueue
        if notification.recipients.is_empty() {
            return Ok(());
        }

        // Prepare attachments payload
        let attachments = notification
            .attachments
            .iter()
            .map(|attachment| EnqueueNotificationAttachment {
                content_type: &attachment.content_type,
                data_base64: BASE64.encode(&attachment.data),
                file_name: &attachment.file_name,
            })
            .collect::<Vec<_>>();
        let attachments = serde_json::to_value(attachments)?;

        // Enqueue notification in database
        let kind = notification.kind.to_string();
        let db = self.client().await?;
        db.execute(
            "
            select enqueue_notification(
                $1::text,
                $2::jsonb,
                $3::jsonb,
                $4::uuid[]
            );
            ",
            &[
                &kind,
                &notification.template_data,
                &attachments,
                &notification.recipients,
            ],
        )
        .await?;

        Ok(())
    }

    #[instrument(skip(self, notification, tracking), err)]
    async fn enqueue_tracked_custom_notification(
        &self,
        notification: &NewNotification,
        tracking: CustomNotificationTracking,
    ) -> Result<()> {
        // Nothing to enqueue or track
        if notification.recipients.is_empty() {
            return Ok(());
        }

        // Convert recipient count to the database integer type
        let recipient_count = i32::try_from(tracking.recipient_count)
            .map_err(|_| anyhow!("recipient count cannot exceed i32::MAX"))?;

        // Prepare attachments payload
        let attachments = notification
            .attachments
            .iter()
            .map(|attachment| EnqueueNotificationAttachment {
                content_type: &attachment.content_type,
                data_base64: BASE64.encode(&attachment.data),
                file_name: &attachment.file_name,
            })
            .collect::<Vec<_>>();
        let attachments = serde_json::to_value(attachments)?;

        // Enqueue notification and store the custom-notification audit atomically
        let kind = notification.kind.to_string();
        self.execute(
            "
            select enqueue_tracked_custom_notification(
                $1::text,
                $2::jsonb,
                $3::jsonb,
                $4::uuid[],
                $5::uuid,
                $6::uuid,
                $7::uuid,
                $8::int,
                $9::text,
                $10::text
            );
            ",
            &[
                &kind,
                &notification.template_data,
                &attachments,
                &notification.recipients,
                &tracking.created_by,
                &tracking.event_id,
                &tracking.group_id,
                &recipient_count,
                &tracking.subject,
                &tracking.body,
            ],
        )
        .await
    }

    /// Retrieves a notification attachment by its ID.
    #[instrument(skip(self), err)]
    async fn get_notification_attachment(&self, attachment_id: Uuid) -> Result<Attachment> {
        #[cached(
            ttl = 7200,
            key = "Uuid",
            convert = "{ attachment_id }",
            sync_writes = "by_key"
        )]
        async fn inner(db: PgClient<'_>, attachment_id: Uuid) -> Result<Attachment> {
            let row = db
                .query_one(
                    "
                    select file_name, content_type, data
                    from attachment
                    where attachment_id = $1;
                    ",
                    &[&attachment_id],
                )
                .await?;

            Ok(Attachment {
                content_type: row.get("content_type"),
                data: row.get("data"),
                file_name: row.get("file_name"),
            })
        }

        let db = self.client().await?;
        inner(db, attachment_id).await
    }

    #[instrument(skip(self), err)]
    async fn mark_stale_processing_notifications_unknown(
        &self,
        timeout: Duration,
    ) -> Result<usize> {
        // Convert timeout to the database integer type
        let timeout_seconds =
            duration_seconds_i64(timeout, "processing timeout cannot exceed i64::MAX seconds")?;

        // Mark stale processing notifications with an unknown delivery outcome
        let count = self
            .fetch_scalar_one::<i64>(
                "select mark_stale_processing_notifications_unknown($1::bigint)::bigint;",
                &[&timeout_seconds],
            )
            .await?;

        #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        Ok(count as usize)
    }

    #[instrument(skip(self, notification), err)]
    async fn requeue_notification(
        &self,
        notification: &Notification,
        error: &str,
        base_retry_after: Duration,
        max_retry_after: Duration,
        max_delivery_attempts: usize,
    ) -> Result<()> {
        // Convert retry metadata to database scalar types
        let base_retry_after_seconds = duration_seconds_i64(
            base_retry_after,
            "base retry delay cannot exceed i64::MAX seconds",
        )?;
        let max_retry_after_seconds = duration_seconds_i64(
            max_retry_after,
            "maximum retry delay cannot exceed i64::MAX seconds",
        )?;
        let max_delivery_attempts = i32::try_from(max_delivery_attempts)
            .map_err(|_| anyhow!("maximum delivery attempts cannot exceed i32::MAX"))?;

        // Requeue the claimed notification or finalize it if attempts are exhausted
        let db = self.client().await?;
        db.execute(
            "
            select requeue_notification(
                $1::uuid,
                $2::text,
                $3::bigint,
                $4::bigint,
                $5::integer
            );
            ",
            &[
                &notification.notification_id,
                &error,
                &base_retry_after_seconds,
                &max_retry_after_seconds,
                &max_delivery_attempts,
            ],
        )
        .await?;

        Ok(())
    }

    /// Updates the notification record after processing, marking it as processed and
    /// recording any error.
    #[instrument(skip(self, notification), err)]
    async fn update_notification(
        &self,
        notification: &Notification,
        error: Option<String>,
    ) -> Result<()> {
        // Mark the claimed notification as processed
        let db = self.client().await?;
        db.execute(
            "
            select update_notification($1::uuid, $2::text);
            ",
            &[&notification.notification_id, &error],
        )
        .await?;

        Ok(())
    }
}

/// Metadata used to track a custom notification audit entry.
pub(crate) struct CustomNotificationTracking {
    /// Body stored in the custom notification record.
    pub(crate) body: String,
    /// User who sent the custom notification.
    pub(crate) created_by: Uuid,
    /// Event associated with the notification, for event custom notifications.
    pub(crate) event_id: Option<Uuid>,
    /// Group associated with the notification.
    pub(crate) group_id: Option<Uuid>,
    /// Attempted recipient count before optional notification filtering.
    pub(crate) recipient_count: usize,
    /// Subject stored in the custom notification record.
    pub(crate) subject: String,
}

/// Serialized attachment payload passed to `enqueue_notification`.
#[derive(Serialize)]
struct EnqueueNotificationAttachment<'a> {
    content_type: &'a str,
    data_base64: String,
    file_name: &'a str,
}

/// Convert a duration to the database integer type.
fn duration_seconds_i64(duration: Duration, overflow_message: &str) -> Result<i64> {
    i64::try_from(duration.as_secs()).map_err(|_| anyhow!("{overflow_message}"))
}
