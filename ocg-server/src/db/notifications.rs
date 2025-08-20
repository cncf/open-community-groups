//! This module defines database functionality used to manage notifications, including
//! enqueueing, retrieving, and updating notification records.

use anyhow::{Result, bail};
use async_trait::async_trait;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{
    PgDB,
    db::TX_CLIENT_NOT_FOUND,
    services::notifications::{NewNotification, Notification},
};

/// Trait that defines database operations used to manage notifications.
#[async_trait]
pub(crate) trait DBNotifications {
    /// Enqueues a notification to be delivered.
    async fn enqueue_notification(&self, notification: &NewNotification) -> Result<()>;

    /// Retrieves a pending notification for delivery.
    async fn get_pending_notification(&self, client_id: Uuid) -> Result<Option<Notification>>;

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

        let db = self.pool.get().await?;
        db.execute(
            "
            insert into notification (kind, user_id, template_data)
            values ($1::text, $2::uuid, $3::jsonb);
            ",
            &[
                &notification.kind.to_string(),
                &notification.user_id,
                &notification.template_data,
            ],
        )
        .await?;

        Ok(())
    }

    #[instrument(skip(self), err)]
    async fn get_pending_notification(&self, client_id: Uuid) -> Result<Option<Notification>> {
        // Get transaction client
        let clients = self.txs_clients.read().await;
        let Some((tx, _)) = clients.get(&client_id) else {
            bail!(TX_CLIENT_NOT_FOUND);
        };

        // Get pending notification (if any)
        let notification = tx
            .query_opt(
                r#"
                select
                    n.kind,
                    n.notification_id,
                    n.template_data,
                    u.email
                from notification n
                join "user" u using (user_id)
                where processed = false
                order by notification_id asc
                limit 1
                for update of n skip locked;
                "#,
                &[],
            )
            .await?
            .map(|row| Notification {
                email: row.get("email"),
                kind: row
                    .get::<_, String>("kind")
                    .as_str()
                    .try_into()
                    .expect("kind to be valid"),
                notification_id: row.get("notification_id"),
                template_data: row.get("template_data"),
            });

        Ok(notification)
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
        let clients = self.txs_clients.read().await;
        let Some((tx, _)) = clients.get(&client_id) else {
            bail!(TX_CLIENT_NOT_FOUND);
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
}
