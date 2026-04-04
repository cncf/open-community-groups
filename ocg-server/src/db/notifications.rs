//! This module defines database functionality used to manage notifications, including
//! enqueueing, retrieving, and updating notification records.

use std::time::Duration;

use anyhow::{Result, anyhow};
use async_trait::async_trait;
use base64::{Engine, engine::general_purpose::STANDARD as BASE64};
use cached::proc_macro::cached;
use deadpool_postgres::Client;
use serde::Serialize;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    PgDB,
    services::notifications::{Attachment, NewNotification, Notification},
};

/// Trait that defines database operations used to manage notifications.
#[async_trait]
pub(crate) trait DBNotifications {
    /// Enqueues due event reminders and returns the number of notifications created.
    async fn enqueue_due_event_reminders(&self, base_url: &str) -> Result<usize>;

    /// Enqueues a notification to be delivered.
    async fn enqueue_notification(&self, notification: &NewNotification) -> Result<()>;

    /// Retrieves a notification attachment by its ID.
    async fn get_notification_attachment(&self, attachment_id: Uuid) -> Result<Attachment>;

    /// Retrieves a pending notification for delivery.
    async fn get_pending_notification(&self, client_id: Uuid) -> Result<Option<Notification>>;

    /// Tracks a custom notification after it's been successfully enqueued.
    async fn track_custom_notification(
        &self,
        created_by: Uuid,
        event_id: Option<Uuid>,
        group_id: Option<Uuid>,
        recipient_count: usize,
        subject: &str,
        body: &str,
    ) -> Result<()>;

    /// Updates a notification after a delivery attempt.
    async fn update_notification(
        &self,
        client_id: Uuid,
        notification: &Notification,
        error: Option<String>,
    ) -> Result<()>;
}

#[async_trait]
impl DBNotifications for PgDB {
    #[instrument(skip(self), err)]
    async fn enqueue_due_event_reminders(&self, base_url: &str) -> Result<usize> {
        let db = self.pool.get().await?;
        let count = db
            .query_one(
                "
                select enqueue_due_event_reminders($1::text)::int;
                ",
                &[&base_url],
            )
            .await?
            .get::<_, i32>(0);
        let count =
            usize::try_from(count).map_err(|_| anyhow!("enqueued reminders count cannot be negative"))?;

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
        let db = self.pool.get().await?;
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

    /// Retrieves a notification attachment by its ID.
    #[instrument(skip(self), err)]
    async fn get_notification_attachment(&self, attachment_id: Uuid) -> Result<Attachment> {
        #[cached(
            time = 7200,
            key = "Uuid",
            convert = "{ attachment_id }",
            sync_writes = "by_key",
            result = true
        )]
        async fn inner(db: Client, attachment_id: Uuid) -> Result<Attachment> {
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

        let db = self.pool.get().await?;
        inner(db, attachment_id).await
    }

    #[instrument(skip(self), err)]
    async fn get_pending_notification(&self, client_id: Uuid) -> Result<Option<Notification>> {
        // Get transaction client
        let tx = self.tx_client(client_id).await?;

        // Get pending notification (if any)
        let Some(row) = tx.query_opt("select * from get_pending_notification();", &[]).await? else {
            return Ok(None);
        };

        // Fetch notification attachments
        let notification_id: Uuid = row.get("notification_id");
        let attachment_ids = row.get::<_, Option<Vec<Uuid>>>("attachment_ids").unwrap_or_default();
        let mut attachments = Vec::with_capacity(attachment_ids.len());
        for attachment_id in attachment_ids {
            let attachment = self.get_notification_attachment(attachment_id).await?;
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
    async fn track_custom_notification(
        &self,
        created_by: Uuid,
        event_id: Option<Uuid>,
        group_id: Option<Uuid>,
        recipient_count: usize,
        subject: &str,
        body: &str,
    ) -> Result<()> {
        // Convert recipient count to the database integer type
        let recipient_count =
            i32::try_from(recipient_count).map_err(|_| anyhow!("recipient count cannot exceed i32::MAX"))?;

        // Store the custom notification and corresponding audit entry
        self.execute(
            "
            select track_custom_notification(
                $1::uuid,
                $2::uuid,
                $3::uuid,
                $4::int,
                $5::text,
                $6::text
            );
            ",
            &[
                &created_by,
                &event_id,
                &group_id,
                &recipient_count,
                &subject,
                &body,
            ],
        )
        .await
    }

    /// Updates the notification record after processing, marking it as processed and
    /// recording any error.
    #[instrument(skip(self, notification), err)]
    async fn update_notification(
        &self,
        client_id: Uuid,
        notification: &Notification,
        error: Option<String>,
    ) -> Result<()> {
        // Get transaction client
        let tx = self.tx_client(client_id).await?;

        // Mark the notification as processed
        tx.execute(
            "
            select update_notification($1::uuid, $2::text);
            ",
            &[&notification.notification_id, &error],
        )
        .await?;

        Ok(())
    }
}

/// Serialized attachment payload passed to `enqueue_notification`.
#[derive(Serialize)]
struct EnqueueNotificationAttachment<'a> {
    content_type: &'a str,
    data_base64: String,
    file_name: &'a str,
}
