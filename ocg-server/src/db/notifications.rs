//! This module defines database functionality used to manage notifications, including
//! enqueueing, retrieving, and updating notification records.

use std::{sync::Arc, time::Duration};

use anyhow::{Result, bail};
use async_trait::async_trait;
use cached::proc_macro::cached;
use deadpool_postgres::Client;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{
    PgDB,
    db::TX_CLIENT_NOT_FOUND,
    services::notifications::{Attachment, NewNotification, Notification},
    util::compute_hash,
};

/// Trait that defines database operations used to manage notifications.
#[async_trait]
pub(crate) trait DBNotifications {
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
    #[instrument(skip(self, notification), err)]
    async fn enqueue_notification(&self, notification: &NewNotification) -> Result<()> {
        trace!("db: enqueue notification");

        // Nothing to enqueue
        if notification.recipients.is_empty() {
            return Ok(());
        }

        // Insert notification records, expanding recipients (one record per recipient)
        let mut db = self.pool.get().await?;
        let tx = db.transaction().await?;
        let rows = tx
            .query(
                "
                insert into notification (kind, user_id, template_data)
                select $1::text, unnest($2::uuid[]), $3::jsonb
                returning notification_id;
                ",
                &[
                    &notification.kind.to_string(),
                    &notification.recipients,
                    &notification.template_data,
                ],
            )
            .await?;
        if notification.attachments.is_empty() {
            tx.commit().await?;
            return Ok(());
        }

        // Get inserted notification IDs
        let notification_ids = rows
            .into_iter()
            .map(|row| row.get::<_, Uuid>("notification_id"))
            .collect::<Vec<_>>();

        // Insert attachments and link them to notifications
        for attachment in &notification.attachments {
            // Insert attachment (if not already present)
            let hash = compute_hash(&attachment.data);
            let attachment_id = tx
                .query_one(
                    "
                    insert into attachment (content_type, data, file_name, hash)
                    values ($1, $2, $3, $4)
                    on conflict (hash) do update set hash = attachment.hash
                    returning attachment_id;
                    ",
                    &[
                        &attachment.content_type,
                        &attachment.data,
                        &attachment.file_name,
                        &hash,
                    ],
                )
                .await?
                .get::<_, Uuid>("attachment_id");

            // Link attachment to notifications
            tx.execute(
                "
                insert into notification_attachment (notification_id, attachment_id)
                select unnest($1::uuid[]), $2;
                ",
                &[&notification_ids, &attachment_id],
            )
            .await?;
        }
        tx.commit().await?;
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
            trace!(attachment_id = ?attachment_id, "db: get notification attachment");

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
        let tx = {
            let clients = self.txs_clients.read().await;
            let Some((tx, _)) = clients.get(&client_id) else {
                bail!(TX_CLIENT_NOT_FOUND);
            };
            Arc::clone(tx)
        };

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

    /// Updates the notification record after processing, marking it as processed and
    /// recording any error.
    #[instrument(skip(self, notification), err)]
    async fn update_notification(
        &self,
        client_id: Uuid,
        notification: &Notification,
        error: Option<String>,
    ) -> Result<()> {
        trace!("db: update notification");

        // Get transaction client
        let tx = {
            let clients = self.txs_clients.read().await;
            let Some((tx, _)) = clients.get(&client_id) else {
                bail!(TX_CLIENT_NOT_FOUND);
            };
            Arc::clone(tx)
        };

        // Update notification
        tx.execute(
            "
            update notification set
                processed = true,
                processed_at = current_timestamp,
                error = $2::text
            where notification_id = $1::uuid;
            ",
            &[&notification.notification_id, &error],
        )
        .await?;

        Ok(())
    }

    #[instrument(skip(self), err)]
    async fn track_custom_notification(
        &self,
        created_by: Uuid,
        event_id: Option<Uuid>,
        group_id: Option<Uuid>,
        subject: &str,
        body: &str,
    ) -> Result<()> {
        trace!("db: track custom notification");

        let db = self.pool.get().await?;
        db.execute(
            "
            insert into custom_notification (created_by, event_id, group_id, subject, body)
            values ($1, $2, $3, $4, $5);
            ",
            &[&created_by, &event_id, &group_id, &subject, &body],
        )
        .await?;

        Ok(())
    }
}
